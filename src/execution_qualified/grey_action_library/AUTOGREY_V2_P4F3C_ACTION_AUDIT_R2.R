args <- commandArgs(trailingOnly=TRUE)

meta_path <- args[1]
values_path <- args[2]
sg11_path <- args[3]
sg12_path <- args[4]
sg13_path <- args[5]
audit_path <- args[6]
collision_path <- args[7]
summary_path <- args[8]

options(stringsAsFactors=FALSE)

source(sg11_path)
source(sg12_path)
source(sg13_path)

meta <- read.csv(
  meta_path,
  stringsAsFactors=FALSE,
  check.names=FALSE,
  na.strings=c("")
)

vals <- read.csv(
  values_path,
  stringsAsFactors=FALSE,
  check.names=FALSE
)

stopifnot(nrow(meta) == 2596L)
stopifnot(length(unique(meta$parent_id)) == 2596L)

value_key <- paste(vals$parent_id, vals$part, sep="|||")
value_map <- split(vals$value, value_key)

get_vec <- function(pid, part) {
  z <- value_map[[paste(pid, part, sep="|||")]]
  if (is.null(z)) stop("Missing vector: ", pid, " ", part)
  as.numeric(z)
}

mase_loss <- function(train, truth, forecast, M) {

  if (length(truth) != length(forecast) ||
      !all(is.finite(forecast)) ||
      !all(is.finite(truth))) {
    return(NA_real_)
  }

  lag_m <- 1L

  if (!is.na(M) && is.finite(M) && M >= 1) {
    lag_m <- as.integer(M)
  }

  n <- length(train)

  if (n <= lag_m) return(NA_real_)

  scale <- mean(abs(
    train[(lag_m + 1L):n] -
    train[1L:(n - lag_m)]
  ))

  if (!is.finite(scale) || scale <= 1e-12) {
    return(NA_real_)
  }

  mean(abs(truth - forecast)) / scale
}

extract_forecast <- function(res, h) {

  if (!is.list(res) || !isTRUE(res$ok)) {
    status <- if (is.list(res) && !is.null(res$status))
      as.character(res$status) else "MODEL_FAIL"

    return(list(
      ok=FALSE,
      status=status,
      forecast=NULL
    ))
  }

  fc <- res$forecast

  if (is.null(fc) &&
      !is.null(res$prediction) &&
      !is.null(res$prediction$forecast)) {
    fc <- res$prediction$forecast
  }

  if (is.null(fc) ||
      length(fc) != h ||
      !all(is.finite(fc))) {
    return(list(
      ok=FALSE,
      status="FORECAST_SHAPE_OR_FINITE_FAIL",
      forecast=NULL
    ))
  }

  list(
    ok=TRUE,
    status="OK",
    forecast=as.numeric(fc)
  )
}

sg11_cfg <- data.frame(
  config_id=c("FAN_P1","FAN_P2","FAN_P3"),
  p=c(1L,2L,3L),
  stringsAsFactors=FALSE
)

sg12_cfg <- ag_sg12_registered_configs()
sg13_cfg <- ag_sg13_registered_configs()

stopifnot(nrow(sg11_cfg) == 3L)
stopifnot(nrow(sg12_cfg) == 20L)
stopifnot(nrow(sg13_cfg) == 20L)

call_model <- function(group, cfg, x, h) {

  res <- tryCatch({

    if (group == "SG11") {
      ag_fan_smgm_forecast(
        x=x,
        h=h,
        p=cfg$p
      )

    } else if (group == "SG12") {
      ag_sg12_forecast(
        x=x,
        h=h,
        r=cfg$r,
        q=cfg$q
      )

    } else if (group == "SG13") {
      ag_sg13_forecast(
        x=x,
        h=h,
        r=cfg$r,
        gamma=cfg$gamma
      )

    } else {
      stop("Unknown group")
    }

  }, error=function(e) {
    list(
      ok=FALSE,
      status=paste0(
        "R_ERROR:",
        conditionMessage(e)
      )
    )
  })

  extract_forecast(res, h)
}

audit_group <- function(pid, D, Y, h, M, group, cfgs) {

  n <- length(D)

  origins <- c(
    n - h - 2L,
    n - h - 1L,
    n - h
  )

  if (any(origins < 5L) ||
      any(origins + h > n)) {

    return(list(
      row=data.frame(
        parent_id=pid,
        group=group,
        eligible_config_count=0L,
        selected_config_id="",
        selected_inner_loss=NA_real_,
        final_status="INNER_ORIGIN_INVALID",
        action_loss_mase=NA_real_,
        stringsAsFactors=FALSE
      ),
      forecast=NULL
    ))
  }

  losses <- rep(NA_real_, nrow(cfgs))
  statuses <- rep("", nrow(cfgs))

  for (j in seq_len(nrow(cfgs))) {

    cfg <- as.list(cfgs[j,,drop=FALSE])

    fold_losses <- rep(NA_real_, 3L)
    good <- TRUE

    for (k in seq_along(origins)) {

      t <- origins[k]

      xtr <- D[seq_len(t)]
      yva <- D[(t+1L):(t+h)]

      z <- call_model(
        group,
        cfg,
        xtr,
        h
      )

      if (!z$ok) {
        statuses[j] <- z$status
        good <- FALSE
        break
      }

      ell <- mase_loss(
        xtr,
        yva,
        z$forecast,
        M
      )

      if (!is.finite(ell)) {
        statuses[j] <- "INNER_MASE_FAIL"
        good <- FALSE
        break
      }

      fold_losses[k] <- ell
    }

    if (good) {
      losses[j] <- mean(fold_losses)
      statuses[j] <- "OK"
    }
  }

  valid <- which(is.finite(losses))

  if (length(valid) == 0L) {

    return(list(
      row=data.frame(
        parent_id=pid,
        group=group,
        eligible_config_count=0L,
        selected_config_id="",
        selected_inner_loss=NA_real_,
        final_status="NO_VALID_CONFIG",
        action_loss_mase=NA_real_,
        stringsAsFactors=FALSE
      ),
      forecast=NULL
    ))
  }

  lmin <- min(losses[valid])

  retained <- valid[
    losses[valid] <= 1.05 * lmin
  ]

  # Frozen P4D selection contract.
  #
  # SG11:
  #   simplicity precedes inner loss; with the admitted Fan-only
  #   p={1,2,3} registry, registered order implements lower p.
  #
  # SG12 / SG13:
  #   all registered configurations have the same structural complexity.
  #   Frozen order is LOWER_MEAN_INNER_MASE first, then registered grid
  #   order, then deterministic config ID.
  if (group %in% c("SG12", "SG13")) {

    ord <- order(
      losses[retained],
      retained,
      na.last=NA
    )

    selected <- retained[ord[1L]]

  } else {

    selected <- retained[1L]
  }

  cfg <- as.list(cfgs[selected,,drop=FALSE])

  final <- call_model(
    group,
    cfg,
    D,
    h
  )

  if (!final$ok) {

    return(list(
      row=data.frame(
        parent_id=pid,
        group=group,
        eligible_config_count=length(valid),
        selected_config_id=cfgs$config_id[selected],
        selected_inner_loss=losses[selected],
        final_status=final$status,
        action_loss_mase=NA_real_,
        stringsAsFactors=FALSE
      ),
      forecast=NULL
    ))
  }

  loss <- mase_loss(
    D,
    Y,
    final$forecast,
    M
  )

  if (!is.finite(loss)) {

    return(list(
      row=data.frame(
        parent_id=pid,
        group=group,
        eligible_config_count=length(valid),
        selected_config_id=cfgs$config_id[selected],
        selected_inner_loss=losses[selected],
        final_status="FINAL_MASE_FAIL",
        action_loss_mase=NA_real_,
        stringsAsFactors=FALSE
      ),
      forecast=NULL
    ))
  }

  list(
    row=data.frame(
      parent_id=pid,
      group=group,
      eligible_config_count=length(valid),
      selected_config_id=cfgs$config_id[selected],
      selected_inner_loss=losses[selected],
      final_status="OK",
      action_loss_mase=loss,
      stringsAsFactors=FALSE
    ),
    forecast=final$forecast
  )
}

run_parent <- function(i) {

  r <- meta[i,,drop=FALSE]

  pid <- r$parent_id
  h <- as.integer(r$h)

  M <- suppressWarnings(as.integer(r$M))
  if (is.na(M)) M <- NA_integer_

  D <- get_vec(pid, "D")
  Y <- get_vec(pid, "Y")

  if (length(D) != as.integer(r$development_n))
    stop("D length mismatch inside R audit: ", pid)

  if (length(Y) != h)
    stop("Y length mismatch inside R audit: ", pid)

  a11 <- audit_group(
    pid,D,Y,h,M,
    "SG11",
    sg11_cfg
  )

  a12 <- audit_group(
    pid,D,Y,h,M,
    "SG12",
    sg12_cfg
  )

  a13 <- audit_group(
    pid,D,Y,h,M,
    "SG13",
    sg13_cfg
  )

  actions <- rbind(
    a11$row,
    a12$row,
    a13$row
  )

  forecasts <- list(
    SG11=a11$forecast,
    SG12=a12$forecast,
    SG13=a13$forecast
  )

  pairs <- list(
    c("SG11","SG12"),
    c("SG11","SG13"),
    c("SG12","SG13")
  )

  denom <- max(
    mean(abs(D)),
    1e-12
  )

  cc <- list()

  for (pp in pairs) {

    f1 <- forecasts[[pp[1]]]
    f2 <- forecasts[[pp[2]]]

    if (is.null(f1) || is.null(f2)) next

    d <- max(abs(f1-f2)) / denom

    cc[[length(cc)+1L]] <- data.frame(
      parent_id=pid,
      group_a=pp[1],
      group_b=pp[2],
      d_inf=d,
      collision_1e4=(d <= 1e-4),
      collision_1e3=(d <= 1e-3),
      collision_1e2=(d <= 1e-2),
      stringsAsFactors=FALSE
    )
  }

  collisions <- if (length(cc))
    do.call(rbind, cc) else NULL

  list(
    actions=actions,
    collisions=collisions
  )
}

# ------------------------------------------------------------
# Deterministic smoke test before full execution
# ------------------------------------------------------------

smoke_idx <- seq_len(min(12L, nrow(meta)))

smoke1 <- lapply(smoke_idx, run_parent)
smoke2 <- lapply(smoke_idx, run_parent)

smoke_a1 <- do.call(rbind, lapply(smoke1, `[[`, "actions"))
smoke_a2 <- do.call(rbind, lapply(smoke2, `[[`, "actions"))

stopifnot(identical(smoke_a1, smoke_a2))

cat("P4F3C_SMOKE_DETERMINISM=PASS\n")
cat("P4F3C_SMOKE_PARENTS=", length(smoke_idx), "\n", sep="")

# ------------------------------------------------------------
# Full development-corpus action audit
# ------------------------------------------------------------

all_actions <- vector("list", nrow(meta))
all_collisions <- vector("list", nrow(meta))

for (i in seq_len(nrow(meta))) {

  z <- run_parent(i)

  all_actions[[i]] <- z$actions
  all_collisions[[i]] <- z$collisions

  if (i %% 100L == 0L || i == nrow(meta)) {
    cat(
      "P4F3C_PROGRESS=",
      i,
      "/",
      nrow(meta),
      "\n",
      sep=""
    )
    flush.console()
  }
}

actions <- do.call(rbind, all_actions)

nonempty_coll <- Filter(
  function(x) !is.null(x) && nrow(x)>0L,
  all_collisions
)

collisions <- if (length(nonempty_coll))
  do.call(rbind, nonempty_coll) else
  data.frame(
    parent_id=character(),
    group_a=character(),
    group_b=character(),
    d_inf=numeric(),
    collision_1e4=logical(),
    collision_1e3=logical(),
    collision_1e2=logical()
  )

stopifnot(nrow(actions) == 2596L * 3L)

write.csv(
  actions,
  audit_path,
  row.names=FALSE,
  quote=TRUE,
  na=""
)

write.csv(
  collisions,
  collision_path,
  row.names=FALSE,
  quote=TRUE,
  na=""
)

groups <- c("SG11","SG12","SG13")

lines <- c(
  "AUTOGREY V2 P4-F3C DEVELOPMENT ACTION AUDIT R2",
  "================================================",
  "",
  "ACTIONABLE_PARENTS=2596",
  paste0("ACTION_ROWS=", nrow(actions))
)

for (g in groups) {

  a <- actions[actions$group==g,,drop=FALSE]

  ok <- sum(a$final_status=="OK")

  lines <- c(
    lines,
    "",
    paste0(g, "_PARENTS=", nrow(a)),
    paste0(g, "_FINAL_OK=", ok),
    paste0(g, "_FINAL_NONOK=", nrow(a)-ok),
    paste0(
      g,
      "_NO_VALID_CONFIG=",
      sum(a$final_status=="NO_VALID_CONFIG")
    ),
    paste0(
      g,
      "_MEDIAN_ACTION_LOSS_MASE=",
      format(
        median(
          a$action_loss_mase[
            is.finite(a$action_loss_mase)
          ],
          na.rm=TRUE
        ),
        digits=17
      )
    )
  )
}

lines <- c(
  lines,
  "",
  paste0(
    "NEWGROUP_COLLISION_1E4=",
    sum(collisions$collision_1e4)
  ),
  paste0(
    "NEWGROUP_COLLISION_1E3=",
    sum(collisions$collision_1e3)
  ),
  paste0(
    "NEWGROUP_COLLISION_1E2=",
    sum(collisions$collision_1e2)
  ),
  "",
  "SELECTOR_TRAINING_PERFORMED=FALSE",
  "FEATURE_GOVERNANCE_CHANGED=FALSE",
  "REALBENCH3_TARGETS_OPENED=FALSE",
  "",
  "P4F3C_DEVELOPMENT_ACTION_AUDIT_STATUS=PASS"
)

writeLines(
  lines,
  summary_path,
  useBytes=TRUE
)

cat(paste(lines, collapse="\n"))
cat("\n")
