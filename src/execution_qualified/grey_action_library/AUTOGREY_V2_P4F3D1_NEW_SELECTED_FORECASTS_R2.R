args <- commandArgs(trailingOnly=TRUE)

meta_path <- args[1]
values_path <- args[2]
audit_path <- args[3]

sg11_path <- args[4]
sg12_path <- args[5]
sg13_path <- args[6]

out_path <- args[7]

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

audit <- read.csv(
  audit_path,
  stringsAsFactors=FALSE,
  check.names=FALSE,
  na.strings=c("")
)

stopifnot(nrow(meta) == 2596L)
stopifnot(nrow(audit) == 7788L)

value_key <- paste(
  vals$parent_id,
  vals$part,
  sep="|||"
)

value_map <- split(
  vals$value,
  value_key
)

get_vec <- function(pid, part) {

  x <- value_map[[
    paste(pid, part, sep="|||")
  ]]

  if (is.null(x))
    stop("Missing materialized vector: ", pid)

  as.numeric(x)
}

cfg12 <- ag_sg12_registered_configs()
cfg13 <- ag_sg13_registered_configs()

rows <- list()
kk <- 0L

ok_audit <- audit[
  audit$final_status == "OK",
  ,
  drop=FALSE
]

expected <- c(
  SG11=2511L,
  SG12=2550L,
  SG13=2579L
)

actual <- table(ok_audit$group)

stopifnot(
  as.integer(actual["SG11"]) == expected["SG11"],
  as.integer(actual["SG12"]) == expected["SG12"],
  as.integer(actual["SG13"]) == expected["SG13"]
)

for (i in seq_len(nrow(ok_audit))) {

  a <- ok_audit[i,,drop=FALSE]

  pid <- a$parent_id
  group <- a$group
  cid <- a$selected_config_id

  m <- meta[
    meta$parent_id == pid,
    ,
    drop=FALSE
  ]

  stopifnot(nrow(m) == 1L)

  D <- get_vec(pid, "D")
  h <- as.integer(m$h)

  z <- NULL

  if (group == "SG11") {

    p <- match(
      cid,
      c("FAN_P1","FAN_P2","FAN_P3")
    )

    if (is.na(p))
      stop("Unknown SG11 config: ", cid)

    z <- ag_fan_smgm_forecast(
      x=D,
      h=h,
      p=p
    )

  } else if (group == "SG12") {

    cc <- cfg12[
      cfg12$config_id == cid,
      ,
      drop=FALSE
    ]

    if (nrow(cc) != 1L)
      stop("Unknown SG12 config: ", cid)

    z <- ag_sg12_forecast(
      x=D,
      h=h,
      r=cc$r,
      q=cc$q
    )

  } else if (group == "SG13") {

    cc <- cfg13[
      cfg13$config_id == cid,
      ,
      drop=FALSE
    ]

    if (nrow(cc) != 1L)
      stop("Unknown SG13 config: ", cid)

    z <- ag_sg13_forecast(
      x=D,
      h=h,
      r=cc$r,
      gamma=cc$gamma
    )

  } else {
    stop("Unexpected group: ", group)
  }

  if (!is.list(z) || !isTRUE(z$ok))
    stop(
      "Previously successful final forecast failed on replay: ",
      pid, " ", group, " ", cid
    )

  fc <- z$forecast

  if (is.null(fc) &&
      !is.null(z$prediction) &&
      !is.null(z$prediction$forecast)) {
    fc <- z$prediction$forecast
  }

  if (is.null(fc) ||
      length(fc) != h ||
      !all(is.finite(fc))) {
    stop(
      "Invalid selected forecast replay: ",
      pid, " ", group
    )
  }

  for (j in seq_len(h)) {

    kk <- kk + 1L

    rows[[kk]] <- data.frame(
      parent_id=pid,
      group=group,
      selected_config_id=cid,
      step=j,
      forecast=as.numeric(fc[j]),
      stringsAsFactors=FALSE
    )
  }

  if (i %% 1000L == 0L) {
    cat(
      "NEW_FORECAST_PROGRESS=",
      i,
      "/",
      nrow(ok_audit),
      "\n",
      sep=""
    )
    flush.console()
  }
}

out <- do.call(rbind, rows)

write.csv(
  out,
  out_path,
  row.names=FALSE,
  quote=TRUE,
  na=""
)

cat("SG11_SELECTED_FORECASTS=2511\n")
cat("SG12_SELECTED_FORECASTS=2550\n")
cat("SG13_SELECTED_FORECASTS=2579\n")
cat("NEW_SELECTED_FORECAST_PARENT_GROUPS=", nrow(ok_audit), "\n", sep="")
cat("NEW_SELECTED_FORECAST_ROWS=", nrow(out), "\n", sep="")
cat("P4F3D1_NEW_FORECAST_REPLAY=PASS\n")
cat("REALBENCH3_TARGETS_OPENED=FALSE\n")
