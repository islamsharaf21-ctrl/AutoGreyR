# AutoGrey Step 7C1 — frozen AG_FEAT_4E_1 feature engine.
# This file ports ONLY the target-free 23-feature map, masks, reason codes,
# and provenance hashes. It does not perform imputation, scaling, selector
# fitting, action assembly, GLOBAL comparison, or target scoring.

AG_FEATURE_VERSION <- "AG_FEAT_4E_1"
AG_FEATURE_EPS <- 1e-12
AG_FEATURE_NAMES <- c(
  "trend_r2",
  "quadratic_gain",
  "up_step_fraction",
  "curvature_sign",
  "cv_abs",
  "range_rel",
  "smoothness",
  "outlier_fraction_tukey",
  "acf1",
  "acf2",
  "diff_skewness",
  "ago_linearity_r2",
  "class_ratio_pass_rate",
  "class_ratio_max_log_violation",
  "mean_log_growth",
  "log_growth_delta",
  "recent_slope_shift",
  "wbo_distortion",
  "gm_background_sensitivity",
  "gm_residual_acf1",
  "seasonal_factor_amplitude",
  "log_n",
  "horizon_ratio"
)

agf_stop <- function(message) stop(as.character(message), call. = FALSE)

agf_scale <- function(x) max(mean(abs(x)), AG_FEATURE_EPS)

agf_raw_hex <- function(r) paste(sprintf("%02x", as.integer(r)), collapse = "")

agf_double_raw_le <- function(x) {
  con <- rawConnection(raw(), "wb")
  on.exit(close(con), add = TRUE)
  writeBin(as.double(x), con, size = 8L, endian = "little")
  rawConnectionValue(con)
}

agf_sha256_raw <- function(r) digest::digest(r, algo = "sha256", serialize = FALSE)

agf_train_hash <- function(x) agf_sha256_raw(agf_double_raw_le(x))

# Exact Python json.dumps(..., sort_keys=True) payload layout used by AG_FEAT_4E_1.
agf_feature_hash <- function(values, mask, n, h, M = NULL) {
  values_hex <- agf_raw_hex(agf_double_raw_le(values))
  mask_raw <- as.raw(as.integer(as.logical(mask)))
  mask_hex <- agf_raw_hex(mask_raw)
  mtxt <- if (is.null(M)) "null" else sprintf("%d", as.integer(M))
  payload <- paste0(
    "{\"M\": ", mtxt,
    ", \"h\": ", sprintf("%d", as.integer(h)),
    ", \"mask\": \"", mask_hex, "\"",
    ", \"n\": ", sprintf("%d", as.integer(n)),
    ", \"values_hex\": \"", values_hex, "\"",
    ", \"version\": \"", AG_FEATURE_VERSION, "\"}"
  )
  agf_sha256_raw(charToRaw(enc2utf8(payload)))
}

# SVD least squares matching numpy.linalg.lstsq(..., rcond=None) rank convention.
# No Step-7B condition-number refusal is introduced here: the frozen Step-4E
# feature engine only checks rank/non-finite output for these landmarks.
agf_lstsq <- function(X, y) {
  X <- as.matrix(X); storage.mode(X) <- "double"
  y <- as.double(y)
  if (nrow(X) != length(y) || any(!is.finite(X)) || any(!is.finite(y))) return(NULL)
  decomp <- tryCatch(La.svd(X, nu = min(nrow(X), ncol(X)), nv = ncol(X)), error = function(e) NULL)
  if (is.null(decomp)) return(NULL)
  s <- as.double(decomp$d)
  if (!length(s)) return(NULL)
  smax <- max(s)
  cutoff <- .Machine$double.eps * max(nrow(X), ncol(X)) * smax
  rank <- sum(s > cutoff)
  if (rank < ncol(X)) return(list(theta = NULL, rank = as.integer(rank)))
  k <- ncol(X)
  U <- decomp$u[, seq_len(k), drop = FALSE]
  V <- t(decomp$vt[seq_len(k), , drop = FALSE])
  theta <- as.double(V %*% (as.double(crossprod(U, y)) / s[seq_len(k)]))
  if (any(!is.finite(theta))) return(NULL)
  list(theta = theta, rank = as.integer(rank))
}

agf_r2 <- function(y, X) {
  y <- as.double(y); X <- as.matrix(X)
  yc <- y - mean(y)
  sst <- sum(yc * yc)
  if (!is.finite(sst) || sst <= AG_FEATURE_EPS * max(mean(abs(y))^2, 1.0)) {
    return(list(value = 0.0, ok = FALSE))
  }
  fit <- agf_lstsq(X, y)
  if (is.null(fit) || is.null(fit$theta) || fit$rank < ncol(X)) return(list(value = 0.0, ok = FALSE))
  resid <- y - as.double(X %*% fit$theta)
  sse <- sum(resid * resid)
  val <- 1.0 - sse / sst
  if (!is.finite(val)) return(list(value = 0.0, ok = FALSE))
  list(value = as.double(min(1.0, max(0.0, val))), ok = TRUE)
}

agf_slope <- function(y, t) {
  X <- cbind(1.0, as.double(t))
  fit <- agf_lstsq(X, y)
  if (is.null(fit) || is.null(fit$theta) || fit$rank < 2L || any(!is.finite(fit$theta))) {
    return(list(value = 0.0, ok = FALSE))
  }
  list(value = as.double(fit$theta[2L]), ok = TRUE)
}

agf_acf_global_mean <- function(x, lag) {
  x <- as.double(x); lag <- as.integer(lag); n <- length(x)
  if (n <= lag) return(list(value = 0.0, ok = FALSE))
  xc <- x - mean(x)
  den <- sum(xc * xc)
  if (den <= AG_FEATURE_EPS * max(mean(abs(x))^2, 1.0)) return(list(value = 0.0, ok = FALSE))
  num <- sum(xc[(lag + 1L):n] * xc[1L:(n - lag)])
  val <- num / den
  if (!is.finite(val)) return(list(value = 0.0, ok = FALSE))
  list(value = as.double(min(1.0, max(-1.0, val))), ok = TRUE)
}

agf_near_zero <- function(x) abs(as.double(x)) <= 1e-10 + 1e-6

agf_gm_fit_forecast <- function(x, h, alpha = 0.5) {
  x <- as.double(x); n <- length(x); h <- as.integer(h)
  if (n < 4L || h < 1L) return(NULL)
  x1 <- cumsum(x)
  z <- alpha * x1[2:n] + (1.0 - alpha) * x1[1:(n - 1L)]
  B <- cbind(-z, 1.0)
  Y <- x[2:n]
  fit <- agf_lstsq(B, Y)
  if (is.null(fit) || is.null(fit$theta) || fit$rank < 2L) return(NULL)
  a <- as.double(fit$theta[1L]); b <- as.double(fit$theta[2L])
  k <- as.double(0:(n + h - 1L))
  if (agf_near_zero(a)) {
    x1h <- x[1L] + b * k
  } else {
    x1h <- (x[1L] - b / a) * exp(-a * k) + b / a
  }
  if (any(!is.finite(x1h))) return(NULL)
  xh <- c(x1h[1L], diff(x1h))
  if (any(!is.finite(xh))) return(NULL)
  list(fitted = as.double(xh[seq_len(n)]), forecast = as.double(xh[(n + 1L):(n + h)]))
}

agf_average_wbo <- function(x) {
  x <- as.double(x); n <- length(x)
  suffix <- rev(cumsum(rev(x)))
  suffix / as.double(n:1L)
}

agf_seasonal_factors <- function(x, M) {
  x <- as.double(x); n <- length(x); M <- as.integer(M)
  if (M < 2L || n < 2L * M) return(NULL)
  means <- numeric(M)
  for (s in 0:(M - 1L)) {
    vals <- x[seq.int(s + 1L, n, by = M)]
    if (length(vals) < 2L) return(NULL)
    means[s + 1L] <- mean(vals)
  }
  overall <- mean(x)
  if (abs(overall) <= AG_FEATURE_EPS * max(mean(abs(x)), 1.0)) return(NULL)
  factors <- means / overall
  if (any(!is.finite(factors)) || any(factors <= 0)) return(NULL)
  as.double(factors)
}

ag_extract_features <- function(D, h, M = NULL) {
  if (!is.atomic(D) || !is.null(dim(D))) agf_stop("D must be a 1-D development sequence")
  x <- as.double(D)
  n <- length(x)
  if (n < 4L) agf_stop("Step 4E feature extraction requires n>=4")
  if (any(!is.finite(x))) agf_stop("D contains non-finite values")
  if (length(h) != 1L || is.na(h) || !is.numeric(h) || h != as.integer(h) || as.integer(h) < 1L) {
    agf_stop("h must be a positive integer")
  }
  h <- as.integer(h)
  if (!is.null(M)) {
    if (length(M) != 1L || is.na(M) || !is.numeric(M) || M != as.integer(M) || as.integer(M) < 2L) {
      agf_stop("M must be None or an integer >=2")
    }
    M <- as.integer(M)
  }

  values <- rep(0.0, length(AG_FEATURE_NAMES))
  valid <- rep(FALSE, length(AG_FEATURE_NAMES))
  reasons <- rep("UNSET", length(AG_FEATURE_NAMES))
  names(values) <- names(valid) <- names(reasons) <- AG_FEATURE_NAMES

  setf <- function(name, value, ok = TRUE, reason = "OK") {
    i <- match(name, AG_FEATURE_NAMES)
    if (isTRUE(ok) && length(value) == 1L && is.finite(value)) {
      values[i] <<- as.double(value); valid[i] <<- TRUE; reasons[i] <<- reason
    } else {
      values[i] <<- 0.0; valid[i] <<- FALSE; reasons[i] <<- if (reason != "OK") reason else "NUMERIC_UNDEFINED"
    }
  }

  t <- as.double(seq_len(n))
  Xlin <- cbind(1.0, t)
  Xquad <- cbind(1.0, t, t^2)

  r2lin <- agf_r2(x, Xlin)
  setf("trend_r2", r2lin$value, r2lin$ok, if (r2lin$ok) "OK" else "ZERO_OR_NEARZERO_VARIANCE")

  if (n >= 5L && r2lin$ok) {
    r2q <- agf_r2(x, Xquad)
    setf("quadratic_gain", max(0.0, r2q$value - r2lin$value), r2q$ok,
         if (r2q$ok) "OK" else "QUADRATIC_FIT_UNDEFINED")
  } else {
    setf("quadratic_gain", 0.0, FALSE, if (n < 5L) "N_LT_5" else "ZERO_OR_NEARZERO_VARIANCE")
  }

  d1 <- diff(x); d2 <- diff(x, differences = 2L)
  setf("up_step_fraction", mean(d1 > 0))
  m2 <- mean(d2)
  setf("curvature_sign", if (m2 > 0) 1.0 else if (m2 < 0) -1.0 else 0.0)

  mean_x <- mean(x); scale_x <- agf_scale(x); sd_x <- stats::sd(x)
  mean_tol <- AG_FEATURE_EPS * max(scale_x, 1.0)
  mean_ok <- abs(mean_x) > mean_tol
  setf("cv_abs", if (mean_ok) sd_x / abs(mean_x) else 0.0, mean_ok, if (mean_ok) "OK" else "MEAN_NEAR_ZERO")
  setf("range_rel", if (mean_ok) (max(x) - min(x)) / abs(mean_x) else 0.0, mean_ok, if (mean_ok) "OK" else "MEAN_NEAR_ZERO")

  var_x <- stats::var(x)
  if (var_x <= AG_FEATURE_EPS * max(scale_x^2, 1.0)) {
    setf("smoothness", 1.0, TRUE, "CONSTANT_BOUNDARY_VALUE")
  } else {
    var_d <- if (length(d1) > 1L) stats::var(d1) else 0.0
    setf("smoothness", min(1.0, max(-1.0, 1.0 - var_d / var_x)))
  }

  qs <- as.double(stats::quantile(x, probs = c(0.25, 0.75), type = 7L, names = FALSE))
  iqr <- qs[2L] - qs[1L]; lo <- qs[1L] - 1.5 * iqr; hi <- qs[2L] + 1.5 * iqr
  setf("outlier_fraction_tukey", mean((x < lo) | (x > hi)))

  ac1 <- agf_acf_global_mean(x, 1L)
  setf("acf1", ac1$value, ac1$ok, if (ac1$ok) "OK" else "ACF_VARIANCE_UNDEFINED")
  ac2 <- agf_acf_global_mean(x, 2L)
  setf("acf2", ac2$value, ac2$ok, if (ac2$ok) "OK" else "ACF_VARIANCE_UNDEFINED")

  if (length(d1) >= 4L) {
    dc <- d1 - mean(d1); m2d <- mean(dc^2)
    if (m2d > AG_FEATURE_EPS * max(mean(abs(d1))^2, 1.0)) {
      setf("diff_skewness", mean(dc^3) / (m2d^1.5))
    } else setf("diff_skewness", 0.0, FALSE, "DIFF_VARIANCE_UNDEFINED")
  } else setf("diff_skewness", 0.0, FALSE, "FEWER_THAN_4_DIFFERENCES")

  x1 <- cumsum(x); r2ago <- agf_r2(x1, Xlin)
  setf("ago_linearity_r2", r2ago$value, r2ago$ok, if (r2ago$ok) "OK" else "AGO_VARIANCE_UNDEFINED")

  positive <- all(x > 0)
  if (positive) {
    lam <- x[1:(n - 1L)] / x[2:n]
    loglam <- log(lam); bound <- 2.0 / (n + 1.0)
    setf("class_ratio_pass_rate", mean(abs(loglam) < bound))
    setf("class_ratio_max_log_violation", max(pmax(0.0, abs(loglam) - bound)))
    lg <- log(x[2:n] / x[1:(n - 1L)])
    setf("mean_log_growth", mean(lg))
    if (n >= 7L) setf("log_growth_delta", mean(tail(lg, 3L)) - mean(head(lg, 3L)))
    else setf("log_growth_delta", 0.0, FALSE, "N_LT_7")
  } else {
    for (nm in c("class_ratio_pass_rate", "class_ratio_max_log_violation", "mean_log_growth", "log_growth_delta")) {
      setf(nm, 0.0, FALSE, "REQUIRES_STRICT_POSITIVITY")
    }
  }

  bfull <- agf_slope(x, t)
  recent_idx <- seq.int(max(1L, n - 3L), n)
  brec <- agf_slope(x[recent_idx], t[recent_idx])
  if (bfull$ok && brec$ok && scale_x > AG_FEATURE_EPS) {
    setf("recent_slope_shift", (brec$value - bfull$value) * n / scale_x)
  } else setf("recent_slope_shift", 0.0, FALSE, "SLOPE_UNDEFINED")

  wbo <- agf_average_wbo(x)
  if (scale_x > AG_FEATURE_EPS) setf("wbo_distortion", mean(abs(wbo - x)) / scale_x)
  else setf("wbo_distortion", 0.0, FALSE, "LEVEL_SCALE_UNDEFINED")

  gm_forecasts <- list(); gm_ok <- TRUE
  for (alpha in c(0.25, 0.50, 0.75)) {
    fit <- agf_gm_fit_forecast(x, h, alpha)
    if (is.null(fit)) { gm_ok <- FALSE; break }
    gm_forecasts[[length(gm_forecasts) + 1L]] <- fit$forecast
  }
  if (gm_ok && scale_x > AG_FEATURE_EPS) {
    F <- do.call(rbind, gm_forecasts)
    spread <- apply(F, 2L, function(v) max(v) - min(v))
    setf("gm_background_sensitivity", max(spread) / scale_x)
  } else setf("gm_background_sensitivity", 0.0, FALSE, "GM_LANDMARK_FAIL")

  gm0 <- agf_gm_fit_forecast(x, 1L, 0.50)
  if (!is.null(gm0)) {
    resid <- x[2:n] - gm0$fitted[2:n]
    racf <- agf_acf_global_mean(resid, 1L)
    setf("gm_residual_acf1", racf$value, racf$ok, if (racf$ok) "OK" else "GM_RESIDUAL_VARIANCE_UNDEFINED")
  } else setf("gm_residual_acf1", 0.0, FALSE, "GM_LANDMARK_FAIL")

  if (is.null(M)) {
    setf("seasonal_factor_amplitude", 0.0, FALSE, "SEASONAL_METADATA_MISSING")
  } else {
    fac <- agf_seasonal_factors(x, M)
    if (is.null(fac)) setf("seasonal_factor_amplitude", 0.0, FALSE, "SEASONAL_FACTOR_UNAVAILABLE")
    else setf("seasonal_factor_amplitude", max(fac) - min(fac))
  }

  setf("log_n", log(n))
  setf("horizon_ratio", h / n)

  if (any(!is.finite(values))) agf_stop("Feature engine produced non-finite output; this violates Step 4E")
  th <- agf_train_hash(x)
  fh <- agf_feature_hash(values, valid, n, h, M)
  list(
    version = AG_FEATURE_VERSION,
    names = unname(AG_FEATURE_NAMES),
    values = unname(as.double(values)),
    valid_mask = unname(as.logical(valid)),
    reason_codes = unname(as.character(reasons)),
    n = as.integer(n), h = as.integer(h), M = M,
    train_hash = th,
    feature_hash = fh
  )
}
