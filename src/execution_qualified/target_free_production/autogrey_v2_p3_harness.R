#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, warn = 1)

required_versions <- c(
  jsonlite = "2.0.0",
  digest = "0.6.39",
  processx = "3.9.0"
)

method_ids <- sprintf("NG%02d_%s", 1:9, c(
  "NAIVE", "SNAIVE", "DRIFT", "SES", "HOLT", "DAMPED",
  "THETA", "ETS_AUTO", "ARIMA_AUTO"
))

timeout_seconds <- c(
  NG01_NAIVE = 5,
  NG02_SNAIVE = 5,
  NG03_DRIFT = 5,
  NG04_SES = 30,
  NG05_HOLT = 30,
  NG06_DAMPED = 30,
  NG07_THETA = 120,
  NG08_ETS_AUTO = 120,
  NG09_ARIMA_AUTO = 120
)

supervisor_startup_grace_seconds <- 30

assert_master_environment <- function() {
  if (as.character(getRversion()) != "4.6.1") {
    stop(sprintf("ENV_R_VERSION_MISMATCH: expected 4.6.1, got %s", getRversion()))
  }
  for (pkg in names(required_versions)) {
    if (!requireNamespace(pkg, quietly = TRUE)) stop(sprintf("ENV_PACKAGE_MISSING: %s", pkg))
    got <- as.character(utils::packageVersion(pkg))
    if (!identical(got, required_versions[[pkg]])) {
      stop(sprintf("ENV_PACKAGE_VERSION_MISMATCH: %s expected %s got %s",
                   pkg, required_versions[[pkg]], got))
    }
  }
  invisible(TRUE)
}

validate_item <- function(item) {
  allowed <- c("parent_id", "source_id", "h", "M", "n_D", "development")
  if (!is.list(item) || !setequal(names(item), allowed)) {
    stop(sprintf("SCHEMA_FIELDS_MISMATCH: expected exactly [%s]", paste(allowed, collapse = ",")))
  }
  if (length(item$parent_id) != 1L || !nzchar(as.character(item$parent_id))) stop("INVALID_PARENT_ID")
  if (length(item$source_id) != 1L || !nzchar(as.character(item$source_id))) stop("INVALID_SOURCE_ID")
  h <- as.integer(item$h)
  M <- as.integer(item$M)
  n_D <- as.integer(item$n_D)
  D <- as.numeric(unlist(item$development, use.names = FALSE))
  if (!h %in% c(1L, 3L, 5L)) stop("INVALID_HORIZON")
  if (M < 1L) stop("INVALID_SEASONAL_PERIOD")
  if (n_D < 1L || length(D) != n_D || any(!is.finite(D))) stop("INVALID_DEVELOPMENT_VECTOR")
  invisible(TRUE)
}

canonical_numeric <- function(x) paste(sprintf("%.17g", as.numeric(x)), collapse = ",")
hash_forecast <- function(x) digest::digest(canonical_numeric(x), algo = "sha256", serialize = FALSE)

successful <- function(x) {
  is.list(x) && identical(x$status, "OK") && length(x$forecast) > 0L && all(is.finite(x$forecast))
}

combine_ng10 <- function(component_results, baseline_results, h) {
  component_ids <- c("NG07_THETA", "NG08_ETS_AUTO", "NG09_ARIMA_AUTO")
  ok <- vapply(component_ids, function(id) successful(component_results[[id]]), logical(1))
  n_ok <- sum(ok)
  if (n_ok > 0L) {
    mat <- do.call(cbind, lapply(component_ids[ok], function(id) as.numeric(component_results[[id]]$forecast)))
    if (n_ok == 1L) point <- as.numeric(mat) else point <- rowMeans(mat)
    status <- c("DEGRADED_1OF3", "DEGRADED_2OF3", "OK_3OF3")[[n_ok]]
    used <- component_ids[ok]
  } else {
    fallback_id <- if (successful(baseline_results[["NG02_SNAIVE"]])) "NG02_SNAIVE" else "NG01_NAIVE"
    if (!successful(baseline_results[[fallback_id]])) {
      return(list(
        method_id = "NG10_STATCOMB3", status = "NO_FORECAST", forecast = numeric(),
        forecast_sha256 = NA_character_, components_successful = 0L, used = character()
      ))
    }
    point <- as.numeric(baseline_results[[fallback_id]]$forecast)
    status <- "FALLBACK_BASELINE"
    used <- fallback_id
  }
  if (length(point) != h || any(!is.finite(point))) stop("NG10_INVALID_COMBINATION")
  list(
    method_id = "NG10_STATCOMB3",
    status = status,
    forecast = point,
    forecast_sha256 = hash_forecast(point),
    components_successful = n_ok,
    used = used
  )
}

run_one_method <- function(item, method_id, worker_path, scratch_dir) {
  token <- paste(gsub("[^A-Za-z0-9_.-]", "_", as.character(item$parent_id)), method_id, sep = "__")
  input_path <- file.path(scratch_dir, paste0(token, "__input.json"))
  output_path <- file.path(scratch_dir, paste0(token, "__output.json"))
  jsonlite::write_json(item, input_path, auto_unbox = TRUE, digits = 17, pretty = FALSE)
  started <- proc.time()[["elapsed"]]
  proc <- processx::run(
    command = file.path(R.home("bin"), "Rscript"),
    args = c("--vanilla", worker_path, input_path, method_id, output_path),
    echo = FALSE,
    echo_cmd = FALSE,
    error_on_status = FALSE,
    # processx::run() defines timeout in seconds. R1 incorrectly multiplied
    # this frozen seconds budget by 1000 as if the API used milliseconds.
    timeout = as.numeric(timeout_seconds[[method_id]] + supervisor_startup_grace_seconds),
    windows_hide_window = TRUE
  )
  elapsed <- unname(proc.time()[["elapsed"]] - started)
  timed_out <- isTRUE(proc$timeout) || isTRUE(attr(proc, "timeout")) || identical(proc$status, -9L)
  if (timed_out || !file.exists(output_path)) {
    return(list(
      protocol = "AUTOGREY_V2_P3_HARNESS_R5D",
      parent_id = as.character(item$parent_id), method_id = method_id,
      eligible = NA, status = if (timed_out) "TIMEOUT_SUPERVISOR" else "PROCESS_FAILURE",
      process_status = proc$status, stdout = proc$stdout, stderr = proc$stderr,
      process_timeout_flag = isTRUE(proc$timeout),
      method_budget_seconds = as.numeric(timeout_seconds[[method_id]]),
      supervisor_timeout_seconds = as.numeric(timeout_seconds[[method_id]] + supervisor_startup_grace_seconds),
      forecast = numeric(), forecast_sha256 = NA_character_, elapsed_supervisor_seconds = elapsed
    ))
  }
  out <- jsonlite::read_json(output_path, simplifyVector = TRUE)
  method_elapsed <- suppressWarnings(as.numeric(out$elapsed_method_seconds))
  if (identical(out$status, "OK") &&
      (length(method_elapsed) != 1L || !is.finite(method_elapsed) || method_elapsed < 0)) {
    out$status <- "TIMING_FAILURE"
    out$error <- "Missing, non-finite, or negative elapsed_method_seconds"
    out$forecast <- numeric()
    out$forecast_sha256 <- NA_character_
  } else if (identical(out$status, "OK") &&
             method_elapsed > timeout_seconds[[method_id]]) {
    out$status <- "TIMEOUT_BUDGET"
    out$error <- sprintf(
      "Method elapsed %.6f seconds exceeded frozen method budget %.6f seconds",
      method_elapsed, timeout_seconds[[method_id]]
    )
    out$forecast <- numeric()
    out$forecast_sha256 <- NA_character_
  }
  out$process_status <- proc$status
  out$process_timeout_flag <- isTRUE(proc$timeout)
  out$method_budget_seconds <- as.numeric(timeout_seconds[[method_id]])
  out$supervisor_timeout_seconds <- as.numeric(timeout_seconds[[method_id]] + supervisor_startup_grace_seconds)
  out$stdout <- proc$stdout
  out$stderr <- proc$stderr
  out$elapsed_supervisor_seconds <- elapsed
  out
}

run_harness <- function(input_path, output_path, selected_methods = method_ids, worker_path = NULL) {
  assert_master_environment()
  Sys.setenv(
    TZ = "UTC", LANG = "C", LC_ALL = "C",
    OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
  )
  RNGkind(kind = "L'Ecuyer-CMRG", normal.kind = "Inversion", sample.kind = "Rejection")
  set.seed(46073)

  if (is.null(worker_path)) {
    worker_path <- file.path(dirname(normalizePath(sys.frame(1)$ofile %||% "autogrey_v2_p3_harness.R")),
                             "autogrey_v2_p3_worker.R")
  }
  worker_path <- normalizePath(worker_path, mustWork = TRUE)
  selected_methods <- unique(as.character(selected_methods))
  if (length(setdiff(selected_methods, method_ids))) stop("UNKNOWN_SELECTED_METHOD")

  payload <- jsonlite::read_json(input_path, simplifyVector = FALSE)
  if (!is.list(payload) || is.null(payload$series) || !setequal(names(payload), c("protocol", "series"))) {
    stop("INPUT_ENVELOPE_MISMATCH")
  }
  if (!identical(as.character(payload$protocol), "AUTOGREY_V2_P3_DEVELOPMENT_ONLY_R1")) {
    stop("INPUT_PROTOCOL_MISMATCH")
  }
  if (!length(payload$series)) stop("EMPTY_INPUT")
  lapply(payload$series, validate_item)

  scratch_dir <- tempfile("autogrey_p3_")
  dir.create(scratch_dir, recursive = TRUE)
  on.exit(unlink(scratch_dir, recursive = TRUE, force = TRUE), add = TRUE)

  rows <- vector("list", length(payload$series))
  for (i in seq_along(payload$series)) {
    item <- payload$series[[i]]
    method_results <- setNames(vector("list", length(selected_methods)), selected_methods)
    for (method_id in selected_methods) {
      method_results[[method_id]] <- run_one_method(item, method_id, worker_path, scratch_dir)
    }
    components <- method_results[intersect(c("NG07_THETA", "NG08_ETS_AUTO", "NG09_ARIMA_AUTO"), names(method_results))]
    baselines <- method_results[intersect(c("NG01_NAIVE", "NG02_SNAIVE"), names(method_results))]
    ng10 <- NULL
    if (all(c("NG07_THETA", "NG08_ETS_AUTO", "NG09_ARIMA_AUTO", "NG01_NAIVE", "NG02_SNAIVE") %in% names(method_results))) {
      ng10 <- combine_ng10(components, baselines, as.integer(item$h))
    }
    rows[[i]] <- list(
      parent_id = as.character(item$parent_id),
      source_id = as.character(item$source_id),
      h = as.integer(item$h), M = as.integer(item$M), n_D = as.integer(item$n_D),
      development_sha256 = digest::digest(canonical_numeric(unlist(item$development)), algo = "sha256", serialize = FALSE),
      methods = method_results,
      NG10_STATCOMB3 = ng10
    )
  }

  installed_versions <- utils::installed.packages()[, "Version"]
  inventory_order <- order(names(installed_versions))
  inventory <- setNames(as.character(installed_versions[inventory_order]),
                        names(installed_versions)[inventory_order])
  inventory_text <- paste(names(inventory), inventory, sep = "==", collapse = "\n")
  result <- list(
    protocol = "AUTOGREY_V2_P3_HARNESS_OUTPUT_R5D",
    target_blind_schema = TRUE,
    direct_environment = list(
      R = as.character(getRversion()),
      platform = R.version$platform,
      forecast = as.character(utils::packageVersion("forecast")),
      jsonlite = as.character(utils::packageVersion("jsonlite")),
      digest = as.character(utils::packageVersion("digest")),
      processx = as.character(utils::packageVersion("processx"))
    ),
    package_inventory = as.list(inventory),
    package_inventory_sha256 = digest::digest(inventory_text, algo = "sha256", serialize = FALSE),
    rows = rows
  )
  jsonlite::write_json(result, output_path, auto_unbox = TRUE, pretty = TRUE, digits = 17, na = "null")
  invisible(result)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

args <- commandArgs(trailingOnly = TRUE)
if (sys.nframe() == 0L && length(args) > 0L) {
  if (length(args) < 2L || length(args) > 3L) {
    stop("Usage: Rscript autogrey_v2_p3_harness.R INPUT_JSON OUTPUT_JSON [METHODS_COMMA_SEPARATED]")
  }
  selected <- if (length(args) == 3L) strsplit(args[[3]], ",", fixed = TRUE)[[1]] else method_ids
  script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  script_path <- sub("^--file=", "", script_arg[[1]])
  run_harness(args[[1]], args[[2]], selected_methods = selected,
              worker_path = file.path(dirname(normalizePath(script_path)), "autogrey_v2_p3_worker.R"))
}
