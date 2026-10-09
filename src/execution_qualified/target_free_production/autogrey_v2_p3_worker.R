#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, warn = 1)

required_versions <- c(
  forecast = "9.0.2",
  jsonlite = "2.0.0",
  digest = "0.6.39"
)

assert_environment <- function() {
  if (as.character(getRversion()) != "4.6.1") {
    stop(sprintf("ENV_R_VERSION_MISMATCH: expected 4.6.1, got %s", getRversion()))
  }
  for (pkg in names(required_versions)) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("ENV_PACKAGE_MISSING: %s", pkg))
    }
    got <- as.character(utils::packageVersion(pkg))
    if (!identical(got, required_versions[[pkg]])) {
      stop(sprintf("ENV_PACKAGE_VERSION_MISMATCH: %s expected %s got %s",
                   pkg, required_versions[[pkg]], got))
    }
  }
  invisible(TRUE)
}

canonical_numeric <- function(x) {
  paste(sprintf("%.17g", as.numeric(x)), collapse = ",")
}

forecast_hash <- function(x) {
  digest::digest(canonical_numeric(x), algo = "sha256", serialize = FALSE)
}

eligibility <- function(method_id, n_D, M) {
  switch(
    method_id,
    NG01_NAIVE = n_D >= 1L,
    NG02_SNAIVE = M > 1L && n_D > M,
    NG03_DRIFT = n_D >= 2L,
    NG04_SES = n_D >= 3L,
    NG05_HOLT = n_D >= 4L,
    NG06_DAMPED = n_D >= 4L,
    NG07_THETA = n_D >= max(3L, 2L * M),
    NG08_ETS_AUTO = n_D >= max(4L, 2L * M),
    NG09_ARIMA_AUTO = n_D >= max(6L, 2L * M),
    stop(sprintf("UNKNOWN_METHOD: %s", method_id))
  )
}

ets_common <- function(y, model, damped) {
  forecast::ets(
    y = y,
    model = model,
    damped = damped,
    alpha = NULL,
    beta = NULL,
    gamma = NULL,
    phi = NULL,
    additive.only = FALSE,
    lambda = NULL,
    biasadj = FALSE,
    lower = c(1e-4, 1e-4, 1e-4, 0.8),
    upper = c(0.9999, 0.9999, 0.9999, 0.98),
    opt.crit = "lik",
    nmse = 3,
    bounds = "both",
    ic = "aicc",
    restrict = TRUE,
    allow.multiplicative.trend = FALSE,
    use.initial.values = FALSE
  )
}

fit_forecast <- function(method_id, D, h, M) {
  n_D <- length(D)
  if (!eligibility(method_id, n_D, M)) {
    return(list(
      status = "INELIGIBLE",
      forecast = numeric(),
      selected_model = NA_character_,
      internal_evaluations_observed = 0L,
      trace = character()
    ))
  }

  y <- stats::ts(D, start = 1, frequency = M)
  trace_lines <- character()
  selected_model <- NA_character_
  internal_evaluations <- 1L

  if (method_id == "NG01_NAIVE") {
    fc <- forecast::rwf(y, h = h, drift = FALSE, level = 80, fan = FALSE)
  } else if (method_id == "NG02_SNAIVE") {
    fc <- forecast::snaive(y, h = h, level = 80, fan = FALSE)
  } else if (method_id == "NG03_DRIFT") {
    fc <- forecast::rwf(y, h = h, drift = TRUE, level = 80, fan = FALSE)
  } else if (method_id == "NG04_SES") {
    fit <- ets_common(y, model = "ANN", damped = FALSE)
    selected_model <- fit$method
    fc <- forecast::forecast(fit, h = h, level = 80, bootstrap = FALSE)
  } else if (method_id == "NG05_HOLT") {
    fit <- ets_common(y, model = "AAN", damped = FALSE)
    selected_model <- fit$method
    fc <- forecast::forecast(fit, h = h, level = 80, bootstrap = FALSE)
  } else if (method_id == "NG06_DAMPED") {
    fit <- ets_common(y, model = "AAN", damped = TRUE)
    selected_model <- fit$method
    fc <- forecast::forecast(fit, h = h, level = 80, bootstrap = FALSE)
  } else if (method_id == "NG07_THETA") {
    fit <- forecast::theta_model(y, lambda = NULL, biasadj = FALSE)
    selected_model <- "THETA_MULTIPLICATIVE_SEASONAL_TEST"
    fc <- forecast::forecast(fit, h = h, level = 80, bootstrap = FALSE)
  } else if (method_id == "NG08_ETS_AUTO") {
    fit <- ets_common(y, model = "ZZZ", damped = NULL)
    selected_model <- fit$method
    internal_evaluations <- if (M > 1L) 18L else 6L
    fc <- forecast::forecast(fit, h = h, level = 80, bootstrap = FALSE)
  } else if (method_id == "NG09_ARIMA_AUTO") {
    approximation_flag <- n_D > 150L || M > 12L
    trace_lines <- utils::capture.output({
      fit <- forecast::auto.arima(
        y = y,
        d = NA,
        D = NA,
        max.p = 5,
        max.q = 5,
        max.P = 2,
        max.Q = 2,
        max.order = 5,
        max.d = 2,
        max.D = 1,
        stationary = FALSE,
        seasonal = TRUE,
        ic = "aicc",
        stepwise = FALSE,
        approximation = approximation_flag,
        method = NULL,
        truncate = NULL,
        xreg = NULL,
        test = "kpss",
        test.args = list(),
        seasonal.test = "seas",
        seasonal.test.args = list(),
        allowdrift = TRUE,
        allowmean = TRUE,
        lambda = NULL,
        biasadj = FALSE,
        parallel = FALSE,
        num.cores = 1,
        trace = TRUE
      )
    })
    ord <- forecast::arimaorder(fit)
    selected_model <- paste(names(ord), as.integer(ord), sep = "=", collapse = ";")
    internal_evaluations <- sum(grepl("ARIMA\\(", trace_lines, fixed = FALSE))
    fc <- forecast::forecast(fit, h = h, level = 80, bootstrap = FALSE)
  } else {
    stop(sprintf("UNKNOWN_METHOD: %s", method_id))
  }

  point <- as.numeric(fc$mean)
  if (length(point) != h) {
    stop(sprintf("WRONG_FORECAST_LENGTH: expected %d got %d", h, length(point)))
  }
  if (any(!is.finite(point))) {
    stop("NONFINITE_FORECAST")
  }

  list(
    status = "OK",
    forecast = point,
    selected_model = selected_model,
    internal_evaluations_observed = as.integer(internal_evaluations),
    trace = trace_lines
  )
}

run_worker <- function(input_path, method_id, output_path) {
  started_worker <- proc.time()[["elapsed"]]
  started_method <- NA_real_
  elapsed_method_seconds <- NA_real_
  warnings_seen <- character()
  result <- tryCatch(
    withCallingHandlers({
      assert_environment()
      RNGkind(kind = "L'Ecuyer-CMRG", normal.kind = "Inversion", sample.kind = "Rejection")
      set.seed(46073)

      item <- jsonlite::read_json(input_path, simplifyVector = FALSE)
      allowed <- c("parent_id", "source_id", "h", "M", "n_D", "development")
      if (!setequal(names(item), allowed)) {
        stop(sprintf("SCHEMA_FIELDS_MISMATCH: got [%s]", paste(sort(names(item)), collapse = ",")))
      }
      D <- as.numeric(unlist(item$development, use.names = FALSE))
      h <- as.integer(item$h)
      M <- as.integer(item$M)
      n_D <- as.integer(item$n_D)
      if (length(D) != n_D) stop("N_D_LENGTH_MISMATCH")
      if (n_D < 1L || any(!is.finite(D))) stop("INVALID_DEVELOPMENT_VECTOR")
      if (!h %in% c(1L, 3L, 5L)) stop("INVALID_HORIZON")
      if (M < 1L) stop("INVALID_SEASONAL_PERIOD")

      # The frozen scientific budget applies only to the method computation.
      # Environment verification, input parsing, and schema checks are worker
      # overhead and are retained separately in elapsed_worker_seconds.
      started_method <- proc.time()[["elapsed"]]
      fitted <- fit_forecast(method_id, D, h, M)
      elapsed_method_seconds <- unname(proc.time()[["elapsed"]] - started_method)
      list(
        protocol = "AUTOGREY_V2_P3_WORKER_R5D",
        parent_id = as.character(item$parent_id),
        source_id = as.character(item$source_id),
        method_id = method_id,
        eligible = fitted$status != "INELIGIBLE",
        status = fitted$status,
        forecast = fitted$forecast,
        forecast_sha256 = if (length(fitted$forecast)) forecast_hash(fitted$forecast) else NA_character_,
        selected_model = fitted$selected_model,
        top_level_fit_attempts = if (fitted$status == "INELIGIBLE") 0L else 1L,
        internal_evaluations_observed = fitted$internal_evaluations_observed,
        elapsed_method_seconds = elapsed_method_seconds,
        trace = fitted$trace
      )
    }, warning = function(w) {
      warnings_seen <<- c(warnings_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    }),
    error = function(e) list(
      protocol = "AUTOGREY_V2_P3_WORKER_R5D",
      method_id = method_id,
      eligible = NA,
      status = "ERROR",
      error = conditionMessage(e),
      forecast = numeric(),
      forecast_sha256 = NA_character_,
      selected_model = NA_character_,
      top_level_fit_attempts = 0L,
      internal_evaluations_observed = 0L,
      elapsed_method_seconds = if (is.finite(started_method)) {
        unname(proc.time()[["elapsed"]] - started_method)
      } else {
        NA_real_
      },
      trace = character()
    )
  )
  result$warnings <- warnings_seen
  result$elapsed_worker_seconds <- unname(proc.time()[["elapsed"]] - started_worker)
  jsonlite::write_json(result, output_path, auto_unbox = TRUE, pretty = TRUE, digits = 17, na = "null")
  invisible(result)
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop("Usage: Rscript autogrey_v2_p3_worker.R INPUT_JSON METHOD_ID OUTPUT_JSON")
}
run_worker(args[[1]], args[[2]], args[[3]])
