args <- commandArgs(trailingOnly=TRUE)
if (length(args) != 9L) stop("Expected: index_csv binary sg11_R sg12_R sg13_R start_row end_row audit_csv forecast_csv")
index_path <- args[[1]]
binary_path <- args[[2]]
sg11_path <- args[[3]]
sg12_path <- args[[4]]
sg13_path <- args[[5]]
start_row <- as.integer(args[[6]])
end_row <- as.integer(args[[7]])
audit_path <- args[[8]]
forecast_path <- args[[9]]

options(stringsAsFactors=FALSE)
source(sg11_path, local=FALSE)
source(sg12_path, local=FALSE)
source(sg13_path, local=FALSE)
idx <- read.csv(index_path, stringsAsFactors=FALSE, check.names=FALSE, na.strings=c(""))
if (nrow(idx) != 4781L) stop("P11A2_INDEX_ROW_COUNT")
if (!is.finite(start_row) || !is.finite(end_row) || start_row < 1L || end_row > nrow(idx) || end_row < start_row) stop("P11A2_CHUNK_BOUNDS")

mase_loss <- function(train, truth, forecast, M) {
  if (length(truth) != length(forecast) || !all(is.finite(truth)) || !all(is.finite(forecast))) return(NA_real_)
  lag_m <- 1L
  if (!is.na(M) && is.finite(M) && M >= 1) lag_m <- as.integer(M)
  n <- length(train)
  if (n <= lag_m) return(NA_real_)
  scale <- mean(abs(train[(lag_m+1L):n] - train[1L:(n-lag_m)]))
  if (!is.finite(scale) || scale <= 1e-12) return(NA_real_)
  mean(abs(truth - forecast)) / scale
}

read_slice <- function(offset_bytes, n_values) {
  con <- file(binary_path, open="rb")
  on.exit(close(con), add=TRUE)
  seek(con, where=as.numeric(offset_bytes), origin="start", rw="read")
  x <- readBin(con, what="double", n=as.integer(n_values), size=8L, endian="little")
  if (length(x) != as.integer(n_values) || any(!is.finite(x))) stop("P11A2_D_SLICE_INVALID")
  x
}

extract_forecast <- function(res, h) {
  if (!is.list(res) || !isTRUE(res$ok)) {
    status <- if (is.list(res) && !is.null(res$status)) as.character(res$status) else "MODEL_FAIL"
    return(list(ok=FALSE, status=status, forecast=NULL))
  }
  fc <- res$forecast
  if (is.null(fc) && !is.null(res$prediction) && !is.null(res$prediction$forecast)) fc <- res$prediction$forecast
  if (is.null(fc) || length(fc) != h || any(!is.finite(fc))) return(list(ok=FALSE, status="FORECAST_SHAPE_OR_FINITE_FAIL", forecast=NULL))
  list(ok=TRUE, status="OK", forecast=as.numeric(fc))
}

sg11_cfg <- data.frame(config_id=c("FAN_P1","FAN_P2","FAN_P3"), p=c(1L,2L,3L), stringsAsFactors=FALSE)
sg12_cfg <- ag_sg12_registered_configs()
sg13_cfg <- ag_sg13_registered_configs()
if (nrow(sg11_cfg) != 3L || nrow(sg12_cfg) != 20L || nrow(sg13_cfg) != 20L) stop("P11A2_CONFIG_REGISTRY_COUNT")

call_model <- function(group, cfg, x, h) {
  res <- tryCatch({
    if (group == "SG11_SELF_MEMORY") ag_fan_smgm_forecast(x=x, h=h, p=cfg$p)
    else if (group == "SG12_FRAC_DYNAMIC") ag_sg12_forecast(x=x, h=h, r=cfg$r, q=cfg$q)
    else if (group == "SG13_FRAC_BERNOULLI") ag_sg13_forecast(x=x, h=h, r=cfg$r, gamma=cfg$gamma)
    else stop("UNKNOWN_GROUP")
  }, error=function(e) list(ok=FALSE, status=paste0("R_ERROR:",conditionMessage(e))))
  extract_forecast(res, h)
}

select_group <- function(pid, D, h, M, group, cfgs) {
  n <- length(D)
  origins <- c(n-h-2L, n-h-1L, n-h)
  if (any(origins < 5L) || any(origins+h > n)) {
    return(list(row=data.frame(parent_id=pid,group=group,eligible_config_count=0L,selected_config_id="",selected_inner_loss=NA_real_,final_status="INNER_ORIGIN_INVALID",stringsAsFactors=FALSE), forecast=NULL))
  }
  losses <- rep(NA_real_, nrow(cfgs))
  for (j in seq_len(nrow(cfgs))) {
    cfg <- as.list(cfgs[j,,drop=FALSE]); fold_losses <- rep(NA_real_,3L); good <- TRUE
    for (k in seq_along(origins)) {
      t <- origins[k]; xtr <- D[seq_len(t)]; yva <- D[(t+1L):(t+h)]
      z <- call_model(group,cfg,xtr,h)
      if (!z$ok) {good <- FALSE; break}
      ell <- mase_loss(xtr,yva,z$forecast,M)
      if (!is.finite(ell)) {good <- FALSE; break}
      fold_losses[k] <- ell
    }
    if (good) losses[j] <- mean(fold_losses)
  }
  valid <- which(is.finite(losses))
  if (length(valid) == 0L) return(list(row=data.frame(parent_id=pid,group=group,eligible_config_count=0L,selected_config_id="",selected_inner_loss=NA_real_,final_status="NO_VALID_CONFIG",stringsAsFactors=FALSE),forecast=NULL))
  lmin <- min(losses[valid]); retained <- valid[losses[valid] <= 1.05*lmin]
  if (group %in% c("SG12_FRAC_DYNAMIC","SG13_FRAC_BERNOULLI")) {
    ord <- order(losses[retained], retained, na.last=NA); selected <- retained[ord[1L]]
  } else selected <- retained[1L]
  cfg <- as.list(cfgs[selected,,drop=FALSE]); final <- call_model(group,cfg,D,h)
  if (!final$ok) return(list(row=data.frame(parent_id=pid,group=group,eligible_config_count=length(valid),selected_config_id=cfgs$config_id[selected],selected_inner_loss=losses[selected],final_status=final$status,stringsAsFactors=FALSE),forecast=NULL))
  list(row=data.frame(parent_id=pid,group=group,eligible_config_count=length(valid),selected_config_id=cfgs$config_id[selected],selected_inner_loss=losses[selected],final_status="OK",stringsAsFactors=FALSE), forecast=final$forecast)
}

chunk_idx <- idx[start_row:end_row,,drop=FALSE]
audit_rows <- vector("list", nrow(chunk_idx)*3L); fc_rows <- list(); ai <- 0L; fi <- 0L
for (local_i in seq_len(nrow(chunk_idx))) {
  r <- chunk_idx[local_i,,drop=FALSE]; pid <- r$parent_id; h <- as.integer(r$h); M <- suppressWarnings(as.integer(r$M))
  D <- read_slice(r$binary_offset_bytes, r$binary_length_values)
  specs <- list(list("SG11_SELF_MEMORY",sg11_cfg), list("SG12_FRAC_DYNAMIC",sg12_cfg), list("SG13_FRAC_BERNOULLI",sg13_cfg))
  for (sp in specs) {
    z <- select_group(pid,D,h,M,sp[[1]],sp[[2]])
    ai <- ai+1L; audit_rows[[ai]] <- z$row
    if (!is.null(z$forecast)) {
      for (step in seq_along(z$forecast)) {
        fi <- fi+1L
        fc_rows[[fi]] <- data.frame(parent_id=pid,source_id=r$source_id,h=h,group=sp[[1]],step=step,forecast=as.numeric(z$forecast[step]),stringsAsFactors=FALSE)
      }
    }
  }
  global_i <- start_row + local_i - 1L
  if (local_i %% 25L == 0L || local_i == nrow(chunk_idx)) cat("P11A2_R2_CHUNK_PROGRESS=",global_i,"/",nrow(idx),"\n",sep="")
}
audit <- do.call(rbind,audit_rows)
forecasts <- if (length(fc_rows)) do.call(rbind,fc_rows) else data.frame(parent_id=character(),source_id=character(),h=integer(),group=character(),step=integer(),forecast=double(),stringsAsFactors=FALSE)
write.csv(audit,audit_path,row.names=FALSE,quote=TRUE,na="")
write.csv(forecasts,forecast_path,row.names=FALSE,quote=TRUE,na="")
cat("P11A2_R2_CHUNK_START=",start_row,"\n",sep="")
cat("P11A2_R2_CHUNK_END=",end_row,"\n",sep="")
cat("P11A2_R2_CHUNK_AUDIT_ROWS=",nrow(audit),"\n",sep="")
cat("P11A2_R2_CHUNK_FORECAST_ROWS=",nrow(forecasts),"\n",sep="")
cat("REALBENCH3_TARGET_VALUES_OPENED=FALSE\n")
