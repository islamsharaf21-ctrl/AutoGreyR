# AutoGrey R reproduction — Step 7B1 scope: SG01_CONT_GM only.
# No SG02-SG10 implementation is included at this checkpoint.

AG_ENGINE_VERSION <- "AG_ENGINE_4FB_1R1"
AG_GM_ALPHA_GRID <- round(seq(0, 1, by = 0.05), 10)

ag_gm_fit_forecast <- function(x, h, alpha = 0.5) {
  x <- ag_as_series(x, 4L)
  h <- as.integer(h)
  alpha <- as.numeric(alpha)
  if (h < 1L) ag_stop("H_INVALID")
  if (!(alpha >= 0 && alpha <= 1)) ag_stop("GM_ALPHA_DOMAIN")

  x1 <- cumsum(x)
  z <- alpha * x1[-1L] + (1 - alpha) * x1[-length(x1)]
  B <- cbind(-z, rep(1, length(x) - 1L))
  lsq <- ag_lstsq_checked(B, x[-1L], failure_prefix = "GM")
  a <- lsq$theta[1L]
  b <- lsq$theta[2L]

  x1hat <- ag_continuous_response_constant(x[1L], a, b, length(x) + h)
  xhat <- c(x1hat[1L], diff(x1hat))
  if (any(!is.finite(xhat))) ag_stop("GM_RESTORE_NONFINITE")

  list(
    forecast = tail(xhat, h),
    fitted = head(xhat, length(x)),
    params = list(a = as.numeric(a), b = as.numeric(b), alpha_bg = alpha),
    diagnostics = lsq$diagnostics
  )
}

ag_sg01_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT", sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }
  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }
  invisible(TRUE)
}

ag_select_sg01 <- function(x, h, M = NULL) {
  x <- ag_as_series(x)
  h <- as.integer(h)
  pre <- tryCatch({ ag_sg01_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG01_CONT_GM", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(AG_GM_ALPHA_GRID))
  failures <- list()

  for (i in seq_along(AG_GM_ALPHA_GRID)) {
    alpha <- AG_GM_ALPHA_GRID[i]
    cid <- sprintf("alpha=%.2f", alpha)
    losses <- numeric(0)
    ok <- TRUE
    fail <- NULL
    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_gm_fit_forecast(train, h, alpha)
        L <- ag_mase(val, out$forecast, train, M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        as.numeric(L)
      }, autogrey_engine_failure = identity)
      if (inherits(ans, "autogrey_engine_failure")) {
        ok <- FALSE; fail <- ans; break
      }
      losses <- c(losses, ans)
    }
    if (!ok) {
      failures[[cid]] <- paste0(fail$code, ":", fail$detail)
      next
    }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    scores[[i]] <- list(
      config_id = cid,
      alpha = as.numeric(alpha),
      mean_inner_mase = as.numeric(mean(losses)),
      origin_losses = as.numeric(losses)
    )
  }
  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG01_CONT_GM", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  in_band <- means <= 1.05 * Lmin + 1e-15
  band <- scores[in_band]

  primary <- vapply(band, function(s) if (ag_near(s$alpha, 0.5, atol = 1e-12, rtol = 0)) 0 else 1, numeric(1))
  distance <- vapply(band, function(s) abs(s$alpha - 0.5), numeric(1))
  loss <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  cid <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(primary, distance, loss, cid)[1L]]]

  final <- tryCatch(ag_gm_fit_forecast(x, h, chosen$alpha), autogrey_engine_failure = identity)
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG01_CONT_GM", eligible = FALSE,
                selected_config_id = chosen$config_id,
                selected_config = list(alpha = chosen$alpha),
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG01_CONT_GM",
    eligible = TRUE,
    selected_config_id = chosen$config_id,
    selected_config = list(alpha = chosen$alpha),
    forecast = final$forecast,
    fitted = final$fitted,
    inner_scores = scores,
    config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin),
      band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(AG_GM_ALPHA_GRID)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}

# ---------------------------------------------------------------------------
# Step 7B2 — SG02_DISCRETE_POLY
# Exact port of AG_ENGINE_4FB_1R1 dgpm_fit_forecast/group subset selection.
# ---------------------------------------------------------------------------

ag_normalize_degrees <- function(degrees) {
  if (length(degrees) == 0L) return(integer(0))
  d <- sort(unique(as.integer(degrees)))
  if (any(is.na(d)) || any(d < 1L | d > 4L)) ag_stop("DGPM_DEGREE_DOMAIN")
  as.integer(d)
}

ag_dgpm_fit_forecast <- function(x, h, degrees = integer(0)) {
  x <- ag_as_series(x, 4L)
  h <- as.integer(h)
  degrees <- ag_normalize_degrees(degrees)

  x1 <- cumsum(x)
  k <- as.numeric(seq.int(2L, length(x)))
  cols <- list(x1[-length(x1)], rep(1, length(x) - 1L))
  if (length(degrees)) {
    for (d in degrees) cols[[length(cols) + 1L]] <- k ^ d
  }
  B <- do.call(cbind, cols)
  lsq <- ag_lstsq_checked(B, x[-1L], min_resid_df = 1L, failure_prefix = "DGPM")
  theta <- lsq$theta
  alpha <- as.numeric(theta[1L])
  beta0 <- as.numeric(theta[2L])
  beta_vec <- if (length(degrees)) as.numeric(theta[2L + seq_along(degrees)]) else numeric(0)
  names(beta_vec) <- as.character(degrees)

  pseudo <- as.numeric(x)
  x1_prev <- as.numeric(x1[length(x1)])
  if (h > 0L) {
    for (kk in seq.int(length(x) + 1L, length(x) + h)) {
      poly <- if (length(degrees)) sum(beta_vec * (as.numeric(kk) ^ degrees)) else 0
      xnext <- alpha * x1_prev + beta0 + poly
      if (!is.finite(xnext)) ag_stop("DGPM_RESPONSE_NONFINITE")
      pseudo <- c(pseudo, as.numeric(xnext))
      x1_prev <- x1_prev + as.numeric(xnext)
    }
  }

  fitted <- numeric(length(x))
  fitted[1L] <- x[1L]
  if (length(x) >= 2L) {
    for (idx in 2L:length(x)) {
      kk <- as.numeric(idx)
      poly <- if (length(degrees)) sum(beta_vec * (kk ^ degrees)) else 0
      fitted[idx] <- alpha * x1[idx - 1L] + beta0 + poly
    }
  }

  beta_list <- if (length(beta_vec)) as.list(beta_vec) else list()
  list(
    forecast = if (h > 0L) tail(pseudo, h) else pseudo,
    fitted = fitted,
    params = list(
      alpha = alpha,
      beta0 = beta0,
      beta = beta_list,
      degrees = as.integer(degrees)
    ),
    diagnostics = lsq$diagnostics
  )
}

ag_all_degree_subsets <- function(max_degree) {
  max_degree <- as.integer(max_degree)
  if (max_degree < 1L) return(list(integer(0)))
  pool <- seq_len(max_degree)
  out <- list(integer(0))
  for (r in seq_len(max_degree)) {
    cm <- combn(pool, r, simplify = FALSE)
    out <- c(out, lapply(cm, as.integer))
  }
  out
}

ag_sg02_configs <- function(n, h, M = NULL) {
  origins <- ag_inner_origins(n, h)
  m_first <- origins[1L]
  Nmax <- min(4L, m_first - 4L)
  if (Nmax < 0L) return(list())
  subsets <- ag_all_degree_subsets(Nmax)
  lapply(subsets, function(S) {
    cid <- if (!length(S)) "deg=empty" else paste0("deg=", paste(S, collapse = "."))
    list(config_id = cid, degrees = as.integer(S))
  })
}

ag_sg02_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT", sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }
  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }
  invisible(TRUE)
}

ag_select_sg02 <- function(x, h, M = NULL) {
  x <- ag_as_series(x)
  h <- as.integer(h)
  pre <- tryCatch({ ag_sg02_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG02_DISCRETE_POLY", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  configs <- ag_sg02_configs(length(x), h, M)
  if (!length(configs)) {
    return(list(group_id = "SG02_DISCRETE_POLY", eligible = FALSE,
                failure_code = "NO_REGISTERED_CONFIG", failure_detail = ""))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(configs))
  failures <- list()

  for (i in seq_along(configs)) {
    cfg <- configs[[i]]
    cid <- cfg$config_id
    losses <- numeric(0)
    ok <- TRUE
    fail <- NULL
    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_dgpm_fit_forecast(train, h, cfg$degrees)
        L <- ag_mase(val, out$forecast, train, M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        as.numeric(L)
      }, autogrey_engine_failure = identity)
      if (inherits(ans, "autogrey_engine_failure")) {
        ok <- FALSE; fail <- ans; break
      }
      losses <- c(losses, ans)
    }
    if (!ok) {
      failures[[cid]] <- paste0(fail$code, ":", fail$detail)
      next
    }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    scores[[i]] <- list(
      config_id = cid,
      degrees = as.integer(cfg$degrees),
      mean_inner_mase = as.numeric(mean(losses)),
      origin_losses = as.numeric(losses)
    )
  }

  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG02_DISCRETE_POLY", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  band <- scores[means <= 1.05 * Lmin + 1e-15]

  ndeg <- vapply(band, function(s) length(s$degrees), integer(1))
  maxdeg <- vapply(band, function(s) if (length(s$degrees)) max(s$degrees) else 0L, integer(1))
  sumdeg <- vapply(band, function(s) sum(s$degrees), integer(1))
  loss <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  cid <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(ndeg, maxdeg, sumdeg, loss, cid)[1L]]]

  final <- tryCatch(ag_dgpm_fit_forecast(x, h, chosen$degrees), autogrey_engine_failure = identity)
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG02_DISCRETE_POLY", eligible = FALSE,
                selected_config_id = chosen$config_id,
                selected_config = list(degrees = chosen$degrees),
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG02_DISCRETE_POLY",
    eligible = TRUE,
    selected_config_id = chosen$config_id,
    selected_config = list(degrees = as.integer(chosen$degrees)),
    forecast = final$forecast,
    fitted = final$fitted,
    inner_scores = scores,
    config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin),
      band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(configs)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}

# ---------------------------------------------------------------------------
# Step 7B3 — SG03_FRAC_LINEAR
# Exact port of AG_ENGINE_4FB_1R1 fractional AGO/IAGO + Wu et al. (2013)
# source-faithful 0<r<1 branch and frozen nine-r selection.
# ---------------------------------------------------------------------------

AG_FGM_R_GRID <- c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9)

ag_fractional_weights <- function(r, n) {
  r <- as.numeric(r); n <- as.integer(n)
  if (n < 1L) return(numeric(0))
  w <- numeric(n)
  w[1L] <- 1.0
  if (n >= 2L) {
    for (j in 2L:n) {
      jj <- as.numeric(j - 1L)
      w[j] <- w[j - 1L] * (r + jj - 1.0) / jj
    }
  }
  if (any(!is.finite(w))) ag_stop("FGM_WEIGHT_NONFINITE")
  as.numeric(w)
}

ag_fractional_ago <- function(x, r) {
  x <- ag_as_series(x)
  w <- ag_fractional_weights(as.numeric(r), length(x))
  n <- length(x)
  out <- numeric(n)
  for (k in seq_len(n)) {
    # np.convolve(x,w)[k-1] = sum_{i=1}^k x[i] * w[k-i+1].
    out[k] <- sum(x[seq_len(k)] * rev(w[seq_len(k)]))
  }
  if (any(!is.finite(out))) ag_stop("FGM_OPERATOR_NONFINITE")
  as.numeric(out)
}

ag_fractional_iago <- function(xr, r) {
  xr <- ag_as_series(xr)
  ag_fractional_ago(xr, -as.numeric(r))
}

ag_fgm_fit_forecast <- function(x, h, r) {
  x <- ag_as_series(x, 4L)
  h <- as.integer(h)
  r <- as.numeric(r)
  if (!(r > 0.0 && r < 1.0)) {
    ag_stop("FGM_R_V1_DOMAIN", sprintf("v1 source-faithful branch requires 0<r<1; r=%s", format(r, digits = 17)))
  }

  xr <- ag_fractional_ago(x, r)

  Y <- diff(xr)
  z <- 0.5 * (xr[-1L] + xr[-length(xr)])
  B <- cbind(-z, rep(1.0, length(x) - 1L))
  ab <- ag_lstsq_checked(B, Y, failure_prefix = "FGM")
  a <- as.numeric(ab$theta[1L])
  b <- as.numeric(ab$theta[2L])

  k_fit <- as.numeric(seq_len(length(x) - 1L))
  E <- cbind(exp(-a * k_fit), rep(1.0, length(k_fit)))
  cd <- ag_lstsq_checked(E, xr[-1L], failure_prefix = "FGM_CD")
  ccoef <- as.numeric(cd$theta[1L])
  d <- as.numeric(cd$theta[2L])

  k_all <- as.numeric(seq_len(length(x) + h - 1L))
  xrhat <- c(xr[1L], ccoef * exp(-a * k_all) + d)
  if (any(!is.finite(xrhat))) ag_stop("FGM_RESPONSE_NONFINITE")

  xhat <- ag_fractional_iago(xrhat, r)
  if (any(!is.finite(xhat))) ag_stop("FGM_RESTORE_NONFINITE")

  diagnostics <- ab$diagnostics
  diagnostics$cd_rank <- as.integer(cd$diagnostics$rank)
  diagnostics$cd_condition <- as.numeric(cd$diagnostics$condition)
  diagnostics$response_convention <- "WU2013_c_d_initial_condition_correction"
  diagnostics$r1_owner <- "SG01_CONT_GM"

  list(
    forecast = tail(xhat, h),
    fitted = xhat[seq_len(length(x))],
    params = list(a = a, b = b, c = ccoef, d = d, r = r),
    diagnostics = diagnostics
  )
}

ag_sg03_configs <- function(n, h, M = NULL) {
  # group_configs() first obtains common origins, so retain that validation.
  ag_inner_origins(as.integer(n), as.integer(h))
  lapply(AG_FGM_R_GRID, function(r) {
    list(config_id = sprintf("r=%.1f", r), r = as.numeric(r))
  })
}

ag_sg03_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT", sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }
  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }
  invisible(TRUE)
}

ag_select_sg03 <- function(x, h, M = NULL) {
  x <- ag_as_series(x)
  h <- as.integer(h)
  pre <- tryCatch({ ag_sg03_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG03_FRAC_LINEAR", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  configs <- ag_sg03_configs(length(x), h, M)
  if (!length(configs)) {
    return(list(group_id = "SG03_FRAC_LINEAR", eligible = FALSE,
                failure_code = "NO_REGISTERED_CONFIG", failure_detail = ""))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(configs))
  failures <- list()

  for (i in seq_along(configs)) {
    cfg <- configs[[i]]
    cid <- cfg$config_id
    losses <- numeric(0)
    ok <- TRUE
    fail <- NULL
    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_fgm_fit_forecast(train, h, cfg$r)
        L <- ag_mase(val, out$forecast, train, M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        as.numeric(L)
      }, autogrey_engine_failure = identity)
      if (inherits(ans, "autogrey_engine_failure")) {
        ok <- FALSE; fail <- ans; break
      }
      losses <- c(losses, ans)
    }
    if (!ok) {
      failures[[cid]] <- paste0(fail$code, ":", fail$detail)
      next
    }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    scores[[i]] <- list(
      config_id = cid,
      r = as.numeric(cfg$r),
      mean_inner_mase = as.numeric(mean(losses)),
      origin_losses = as.numeric(losses)
    )
  }

  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG03_FRAC_LINEAR", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  band <- scores[means <= 1.05 * Lmin + 1e-15]

  # Frozen SG03 key is (inner loss, r, config ID). The 5% band therefore does
  # not permit a worse r to displace the numerical best unless loss is tied.
  loss <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  rr <- vapply(band, `[[`, numeric(1), "r")
  cid <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(loss, rr, cid)[1L]]]

  final <- tryCatch(ag_fgm_fit_forecast(x, h, chosen$r), autogrey_engine_failure = identity)
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG03_FRAC_LINEAR", eligible = FALSE,
                selected_config_id = chosen$config_id,
                selected_config = list(r = chosen$r),
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG03_FRAC_LINEAR",
    eligible = TRUE,
    selected_config_id = chosen$config_id,
    selected_config = list(r = as.numeric(chosen$r)),
    forecast = final$forecast,
    fitted = final$fitted,
    inner_scores = scores,
    config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin),
      band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(configs)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}

# ---------------------------------------------------------------------------
# Step 7B4 — SG04_BERNOULLI
# Exact port of AG_ENGINE_4FB_1R1 NGBM / Verhulst branch.
# ---------------------------------------------------------------------------

AG_NGBM_ID_WARN <- 1e3
AG_NGBM_ID_FAIL <- 1e4
AG_NGBM_GAMMA_GRID <- c(
  -1.0, -0.75, -0.5, -0.25, 0.25, 0.5, 0.75,
  1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0
)

ag_is_integer_like <- function(p) {
  abs(as.numeric(p) - round(as.numeric(p))) <= 1e-10
}

ag_real_power_scalar <- function(base, exponent) {
  base <- as.numeric(base); exponent <- as.numeric(exponent)
  if (base > 0) {
    val <- base ^ exponent
  } else if (base == 0) {
    if (exponent < 0) ag_stop("NGBM_REAL_DOMAIN_FAIL", "zero base with negative power")
    val <- if (exponent == 0) 1.0 else 0.0
  } else {
    if (!ag_is_integer_like(exponent)) {
      ag_stop("NGBM_REAL_DOMAIN_FAIL",
              sprintf("negative base %s ^ %s", format(base, digits = 17), format(exponent, digits = 17)))
    }
    val <- base ^ as.integer(round(exponent))
  }
  if (!is.finite(val)) {
    ag_stop("NGBM_REAL_DOMAIN_FAIL",
            sprintf("nonfinite power %s^%s", format(base, digits = 17), format(exponent, digits = 17)))
  }
  as.numeric(val)
}

ag_ngbm_fit_forecast <- function(x, h, gamma) {
  x <- ag_as_series(x, 4L)
  h <- as.integer(h)
  gamma <- as.numeric(gamma)
  if (ag_near(gamma, 1.0)) ag_stop("NGBM_GAMMA_ONE_SINGULAR")

  x1 <- cumsum(x)
  z <- 0.5 * (x1[-1L] + x1[-length(x1)])
  zg <- vapply(z, ag_real_power_scalar, numeric(1), exponent = gamma)
  B <- cbind(-z, zg)

  norms <- sqrt(colSums(B ^ 2))
  if (any(norms <= .Machine$double.eps)) {
    ag_stop("NGBM_IDENTIFIABILITY_FAIL", "zero design-column norm")
  }
  Bn <- sweep(B, 2L, norms, "/")
  kappa_id <- ag_cond(Bn)
  if (!is.finite(kappa_id) || kappa_id >= AG_NGBM_ID_FAIL) {
    ag_stop("NGBM_IDENTIFIABILITY_FAIL", sprintf("kappa_id=%.6g", kappa_id))
  }

  lsq <- ag_lstsq_checked(B, x[-1L], failure_prefix = "NGBM")
  a <- as.numeric(lsq$theta[1L])
  b <- as.numeric(lsq$theta[2L])
  power0 <- 1.0 - gamma
  u0 <- ag_real_power_scalar(x1[1L], power0)
  tau <- as.numeric(seq.int(0L, length(x) + h - 1L))
  if (ag_near(a, 0.0)) {
    bracket <- u0 + power0 * b * tau
  } else {
    bracket <- (u0 - b / a) * exp(-a * power0 * tau) + b / a
  }
  y1 <- vapply(bracket, ag_real_power_scalar, numeric(1), exponent = 1.0 / power0)
  xhat <- c(y1[1L], diff(y1))
  if (any(!is.finite(xhat))) ag_stop("NGBM_REAL_DOMAIN_FAIL", "restored sequence nonfinite")

  diagnostics <- lsq$diagnostics
  diagnostics$kappa_id <- as.numeric(kappa_id)
  diagnostics$kappa_id_warning <- isTRUE(kappa_id >= AG_NGBM_ID_WARN)

  list(
    forecast = tail(xhat, h),
    fitted = head(xhat, length(x)),
    params = list(a = a, b = b, gamma = gamma),
    diagnostics = diagnostics
  )
}

ag_sg04_configs <- function(n, h, M = NULL) {
  ag_inner_origins(as.integer(n), as.integer(h))
  lapply(AG_NGBM_GAMMA_GRID, function(gamma) {
    list(config_id = paste0("gamma=", sprintf("%g", gamma)), gamma = as.numeric(gamma))
  })
}

ag_sg04_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT", sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }
  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }
  invisible(TRUE)
}

ag_select_sg04 <- function(x, h, M = NULL) {
  x <- ag_as_series(x)
  h <- as.integer(h)
  pre <- tryCatch({ ag_sg04_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG04_BERNOULLI", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  configs <- ag_sg04_configs(length(x), h, M)
  if (!length(configs)) {
    return(list(group_id = "SG04_BERNOULLI", eligible = FALSE,
                failure_code = "NO_REGISTERED_CONFIG", failure_detail = ""))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(configs))
  failures <- list()

  for (i in seq_along(configs)) {
    cfg <- configs[[i]]
    cid <- cfg$config_id
    losses <- numeric(0)
    ok <- TRUE
    fail <- NULL
    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_ngbm_fit_forecast(train, h, cfg$gamma)
        L <- ag_mase(val, out$forecast, train, M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        as.numeric(L)
      }, autogrey_engine_failure = identity)
      if (inherits(ans, "autogrey_engine_failure")) {
        ok <- FALSE; fail <- ans; break
      }
      losses <- c(losses, ans)
    }
    if (!ok) {
      failures[[cid]] <- paste0(fail$code, ":", fail$detail)
      next
    }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    scores[[i]] <- list(
      config_id = cid,
      gamma = as.numeric(cfg$gamma),
      mean_inner_mase = as.numeric(mean(losses)),
      origin_losses = as.numeric(losses)
    )
  }

  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG04_BERNOULLI", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  band <- scores[means <= 1.05 * Lmin + 1e-15]

  # Frozen SG04 key: prefer named Verhulst gamma=2 whenever it is in the 5% band;
  # then loss, gamma, config ID.
  primary <- vapply(band, function(s) if (ag_near(s$gamma, 2.0, atol = 1e-12, rtol = 0)) 0 else 1, numeric(1))
  loss <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  gamma <- vapply(band, `[[`, numeric(1), "gamma")
  cid <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(primary, loss, gamma, cid)[1L]]]

  final <- tryCatch(ag_ngbm_fit_forecast(x, h, chosen$gamma), autogrey_engine_failure = identity)
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG04_BERNOULLI", eligible = FALSE,
                selected_config_id = chosen$config_id,
                selected_config = list(gamma = chosen$gamma),
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG04_BERNOULLI",
    eligible = TRUE,
    selected_config_id = chosen$config_id,
    selected_config = list(gamma = as.numeric(chosen$gamma)),
    forecast = final$forecast,
    fitted = final$fitted,
    inner_scores = scores,
    config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin),
      band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(configs)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}


# ---------------------------------------------------------------------------
# Step 7B5 — SG05_CONT_TIME_POLY
# Exact port of AG_ENGINE_4FB_1R1 continuous time-power + FOTP whitening.
# SG01-SG04 above are preserved from the externally R-verified Step 7B4 source.
# ---------------------------------------------------------------------------

AG_TIMEPOWER_ALPHA_GRID <- c(0.25, 0.5, 0.75, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0)
AG_GL_X32 <- c(
  -0.99726386184948157,
  -0.98561151154526838,
  -0.96476225558750639,
  -0.93490607593773967,
  -0.89632115576605209,
  -0.84936761373256997,
  -0.79448379596794239,
  -0.73218211874028971,
  -0.66304426693021523,
  -0.5877157572407623,
  -0.50689990893222936,
  -0.42135127613063533,
  -0.33186860228212767,
  -0.23928736225213706,
  -0.14447196158279649,
  -0.048307665687738324,
  0.048307665687738324,
  0.14447196158279649,
  0.23928736225213706,
  0.33186860228212767,
  0.42135127613063533,
  0.50689990893222936,
  0.5877157572407623,
  0.66304426693021523,
  0.73218211874028971,
  0.79448379596794239,
  0.84936761373256997,
  0.89632115576605209,
  0.93490607593773967,
  0.96476225558750639,
  0.98561151154526838,
  0.99726386184948157
)
AG_GL_W32 <- c(
  0.0070186100094705058,
  0.016274394730905743,
  0.025392065309262024,
  0.034273862913021765,
  0.042835898022226836,
  0.050998059262376091,
  0.058684093478535565,
  0.065822222776361683,
  0.072345794108848338,
  0.078193895787070228,
  0.083311924226946707,
  0.087652093004403783,
  0.09117387869576378,
  0.093844399080804511,
  0.095638720079274708,
  0.096540088514727659,
  0.096540088514727659,
  0.095638720079274708,
  0.093844399080804511,
  0.09117387869576378,
  0.087652093004403783,
  0.083311924226946707,
  0.078193895787070228,
  0.072345794108848338,
  0.065822222776361683,
  0.058684093478535565,
  0.050998059262376091,
  0.042835898022226836,
  0.034273862913021765,
  0.025392065309262024,
  0.016274394730905743,
  0.0070186100094705058
)

ag_timepower_response <- function(x1_0, a, b, c, alpha, total) {
  x1_0 <- as.numeric(x1_0); a <- as.numeric(a); b <- as.numeric(b)
  c <- as.numeric(c); alpha <- as.numeric(alpha); total <- as.integer(total)
  ts <- as.numeric(seq_len(total))
  out <- numeric(total)
  out[1L] <- x1_0

  if (ag_near(a, 0.0)) {
    if (total >= 2L) {
      for (i in 2L:total) {
        tt <- ts[i]
        out[i] <- x1_0 + b * (tt ^ (alpha + 1.0) - 1.0) / (alpha + 1.0) + c * (tt - 1.0)
      }
    }
  } else {
    decay <- exp(-a)
    if (!is.finite(decay)) ag_stop("TIMEPOWER_RESPONSE_NONFINITE", "nonfinite unit decay")
    if (total >= 2L) {
      for (i in 2L:total) {
        left <- as.numeric(i - 1L)
        right <- as.numeric(i)
        mid <- 0.5 * (left + right)
        half <- 0.5 * (right - left)
        s <- mid + half * AG_GL_X32
        integrand <- exp(-a * (right - s)) * (b * (s ^ alpha) + c)
        if (any(!is.finite(integrand))) {
          ag_stop("TIMEPOWER_RESPONSE_NONFINITE", "nonfinite quadrature integrand")
        }
        integ <- half * sum(AG_GL_W32 * integrand)
        out[i] <- decay * out[i - 1L] + integ
      }
    }
  }

  if (any(!is.finite(out))) ag_stop("TIMEPOWER_RESPONSE_NONFINITE")
  as.numeric(out)
}

ag_timepower_fit_forecast <- function(x, h, alpha) {
  x <- ag_as_series(x, 5L)
  h <- as.integer(h); alpha <- as.numeric(alpha)
  if (alpha < 0 || ag_near(alpha, 0.0)) ag_stop("TIMEPOWER_ALPHA_REDUCTION")

  x1 <- cumsum(x)
  k <- as.numeric(seq.int(2L, length(x)))
  z <- 0.5 * (x1[-1L] + x1[-length(x1)])
  B <- cbind(-z, k ^ alpha, rep(1.0, length(x) - 1L))
  lsq <- ag_lstsq_checked(B, x[-1L], min_resid_df = 1L, failure_prefix = "TIMEPOWER")
  a <- as.numeric(lsq$theta[1L]); b <- as.numeric(lsq$theta[2L]); cc <- as.numeric(lsq$theta[3L])

  y1 <- ag_timepower_response(x[1L], a, b, cc, alpha, length(x) + h)
  xhat <- c(y1[1L], diff(y1))
  list(
    forecast = tail(xhat, h),
    fitted = head(xhat, length(x)),
    params = list(a = a, b = b, c = cc, alpha = alpha),
    diagnostics = lsq$diagnostics
  )
}

ag_poly_eval_ascending <- function(coeff, t) {
  coeff <- as.numeric(coeff); t <- as.numeric(t)
  out <- rep(0.0, length(t))
  if (length(coeff)) {
    for (j in seq_along(coeff)) out <- out + coeff[j] * (t ^ (j - 1L))
  }
  as.numeric(out)
}

ag_fotp_response <- function(x1_0, a, c_asc, total) {
  x1_0 <- as.numeric(x1_0); a <- as.numeric(a); c_asc <- as.numeric(c_asc); total <- as.integer(total)
  ts <- as.numeric(seq_len(total))
  d <- length(c_asc) - 1L

  if (ag_near(a, 0.0)) {
    out <- rep(x1_0, total)
    for (j in seq_along(c_asc)) {
      jj <- as.numeric(j - 1L)
      out <- out + c_asc[j] / (jj + 1.0) * (ts ^ (jj + 1.0) - 1.0)
    }
  } else {
    q <- numeric(d + 1L)
    q_next <- 0.0
    for (m in seq.int(d, 0L, by = -1L)) {
      idx <- m + 1L
      q[idx] <- (c_asc[idx] - (as.numeric(m) + 1.0) * q_next) / a
      q_next <- q[idx]
    }
    q1 <- ag_poly_eval_ascending(q, 1.0)
    out <- ag_poly_eval_ascending(q, ts) + (x1_0 - q1) * exp(-a * (ts - 1.0))
  }

  if (any(!is.finite(out))) ag_stop("FOTP_RESPONSE_NONFINITE")
  as.numeric(out)
}

ag_fotp_fit_forecast <- function(x, h, p_order) {
  x <- ag_as_series(x, 5L)
  h <- as.integer(h); p_order <- as.integer(p_order)
  if (p_order < 2L || p_order > 4L) ag_stop("FOTP_ORDER_DOMAIN")

  x1 <- cumsum(x)
  k <- as.numeric(seq.int(2L, length(x)))
  z <- 0.5 * (x1[-1L] + x1[-length(x1)])
  powers <- seq.int(p_order - 1L, 0L, by = -1L)
  cols <- c(list(-z), lapply(powers, function(pp) k ^ pp))
  B <- do.call(cbind, cols)
  lsq <- ag_lstsq_checked(B, x[-1L], min_resid_df = 1L, failure_prefix = "FOTP")
  a <- as.numeric(lsq$theta[1L])
  b_desc <- as.numeric(lsq$theta[-1L])
  c_asc <- rev(b_desc)

  y1 <- ag_fotp_response(x[1L], a, c_asc, length(x) + h)
  xhat <- c(y1[1L], diff(y1))
  list(
    forecast = tail(xhat, h),
    fitted = head(xhat, length(x)),
    params = list(a = a, b_desc = b_desc, p_order = p_order),
    diagnostics = lsq$diagnostics
  )
}

ag_sg05_configs <- function(n, h, M = NULL) {
  origins <- ag_inner_origins(as.integer(n), as.integer(h))
  m_first <- origins[1L]
  out <- lapply(AG_TIMEPOWER_ALPHA_GRID, function(alpha) {
    list(config_id = paste0("TP_alpha=", sprintf("%g", alpha)), kind = "timepower", alpha = as.numeric(alpha))
  })
  Hmax <- min(4L, m_first - 3L)
  if (Hmax >= 2L) {
    for (pp in seq.int(2L, Hmax)) {
      out[[length(out) + 1L]] <- list(config_id = paste0("FOTP_order=", pp), kind = "fotp", p_order = as.integer(pp))
    }
  }
  out
}

ag_sg05_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT", sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }
  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }
  if (ag_inner_origins(n, h)[1L] < 5L) ag_stop("GROUP_HISTORY_SHORT")
  invisible(TRUE)
}

ag_sg05_fit_config <- function(x, h, cfg) {
  if (identical(cfg$kind, "timepower")) return(ag_timepower_fit_forecast(x, h, cfg$alpha))
  if (identical(cfg$kind, "fotp")) return(ag_fotp_fit_forecast(x, h, cfg$p_order))
  ag_stop("GROUP_UNKNOWN", "SG05 config kind")
}

ag_select_sg05 <- function(x, h, M = NULL) {
  x <- ag_as_series(x); h <- as.integer(h)
  pre <- tryCatch({ ag_sg05_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG05_CONT_TIME_POLY", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  configs <- ag_sg05_configs(length(x), h, M)
  if (!length(configs)) {
    return(list(group_id = "SG05_CONT_TIME_POLY", eligible = FALSE,
                failure_code = "NO_REGISTERED_CONFIG", failure_detail = ""))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(configs)); failures <- list()

  for (i in seq_along(configs)) {
    cfg <- configs[[i]]; cid <- cfg$config_id
    losses <- numeric(0); ok <- TRUE; fail <- NULL
    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_sg05_fit_config(train, h, cfg)
        L <- ag_mase(val, out$forecast, train, M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        as.numeric(L)
      }, autogrey_engine_failure = identity)
      if (inherits(ans, "autogrey_engine_failure")) { ok <- FALSE; fail <- ans; break }
      losses <- c(losses, ans)
    }
    if (!ok) { failures[[cid]] <- paste0(fail$code, ":", fail$detail); next }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    score <- list(config_id = cid, kind = cfg$kind,
                  mean_inner_mase = as.numeric(mean(losses)), origin_losses = as.numeric(losses))
    if (identical(cfg$kind, "timepower")) score$alpha <- as.numeric(cfg$alpha)
    else score$p_order <- as.integer(cfg$p_order)
    scores[[i]] <- score
  }

  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG05_CONT_TIME_POLY", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  band <- scores[means <= 1.05 * Lmin + 1e-15]

  params <- vapply(band, function(s) if (identical(s$kind, "fotp")) as.numeric(s$p_order + 1L) else 3.0, numeric(1))
  branch <- vapply(band, function(s) if (identical(s$kind, "fotp")) 0.0 else 1.0, numeric(1))
  order_key <- vapply(band, function(s) if (identical(s$kind, "fotp")) as.numeric(s$p_order) else 999.0, numeric(1))
  loss <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  cid <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(params, branch, order_key, loss, cid)[1L]]]

  chosen_cfg <- if (identical(chosen$kind, "timepower"))
    list(kind = "timepower", alpha = as.numeric(chosen$alpha)) else
    list(kind = "fotp", p_order = as.integer(chosen$p_order))

  final <- tryCatch(ag_sg05_fit_config(x, h, chosen_cfg), autogrey_engine_failure = identity)
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG05_CONT_TIME_POLY", eligible = FALSE,
                selected_config_id = chosen$config_id, selected_config = chosen_cfg,
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG05_CONT_TIME_POLY", eligible = TRUE,
    selected_config_id = chosen$config_id, selected_config = chosen_cfg,
    forecast = final$forecast, fitted = final$fitted,
    inner_scores = scores, config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin), band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(configs)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}

# ---------------------------------------------------------------------------
# Step 7B6 — SG06_CONFORMABLE
# Exact port of AG_ENGINE_4FB_1R1 conformable CFA/CFD branch.
# SG01-SG05 above are frozen from externally R-verified Step 7B5.
# ---------------------------------------------------------------------------

AG_CFGM_ALPHA_GRID <- c(
  round(seq(0.0, 0.9, by = 0.1), 10),
  round(seq(1.1, 2.0, by = 0.1), 10)
)

ag_conformable_cfa <- function(x, alpha) {
  x <- ag_as_series(x)
  alpha <- as.numeric(alpha)
  if (alpha < 0) ag_stop("CFGM_ALPHA_DOMAIN")
  if (ag_near(alpha, 0.0, atol = 1e-14, rtol = 0.0)) return(as.numeric(x))

  q <- as.integer(ceiling(alpha - 1e-14))
  q <- max(q, 1L)
  k <- as.numeric(seq_along(x))
  out <- x / (k ^ (q - alpha))
  for (i in seq_len(q)) out <- cumsum(out)
  if (any(!is.finite(out))) ag_stop("CFGM_CFA_NONFINITE")
  as.numeric(out)
}

ag_conformable_cfd <- function(xa, alpha) {
  xa <- ag_as_series(xa)
  alpha <- as.numeric(alpha)
  if (alpha < 0) ag_stop("CFGM_ALPHA_DOMAIN")
  if (ag_near(alpha, 0.0, atol = 1e-14, rtol = 0.0)) return(as.numeric(xa))

  q <- as.integer(ceiling(alpha - 1e-14))
  q <- max(q, 1L)
  out <- as.numeric(xa)
  for (i in seq_len(q)) out <- c(out[1L], diff(out))
  k <- as.numeric(seq_along(out))
  out <- out * (k ^ (q - alpha))
  if (any(!is.finite(out))) ag_stop("CFGM_CFD_NONFINITE")
  as.numeric(out)
}

ag_cfgm_fit_forecast <- function(x, h, alpha) {
  x <- ag_as_series(x, 4L)
  h <- as.integer(h)
  alpha <- as.numeric(alpha)
  if (alpha < 0 || alpha > 2.0 + 1e-12) ag_stop("CFGM_ALPHA_DOMAIN")

  xa <- ag_conformable_cfa(x, alpha)
  Y <- diff(xa)
  z <- 0.5 * (xa[-1L] + xa[-length(xa)])
  B <- cbind(-z, rep(1.0, length(x) - 1L))
  lsq <- ag_lstsq_checked(B, Y, failure_prefix = "CFGM")
  a <- as.numeric(lsq$theta[1L])
  b <- as.numeric(lsq$theta[2L])

  xahat <- ag_continuous_response_constant(xa[1L], a, b, length(x) + h)
  xhat <- ag_conformable_cfd(xahat, alpha)
  list(
    forecast = tail(xhat, h),
    fitted = head(xhat, length(x)),
    params = list(a = a, b = b, alpha = alpha),
    diagnostics = lsq$diagnostics
  )
}

ag_sg06_configs <- function(n, h, M = NULL) {
  ag_inner_origins(as.integer(n), as.integer(h))
  lapply(AG_CFGM_ALPHA_GRID, function(alpha) {
    list(config_id = sprintf("alpha=%.1f", alpha), alpha = as.numeric(alpha))
  })
}

ag_sg06_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT", sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }
  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }
  invisible(TRUE)
}

ag_select_sg06 <- function(x, h, M = NULL) {
  x <- ag_as_series(x)
  h <- as.integer(h)
  pre <- tryCatch({ ag_sg06_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG06_CONFORMABLE", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  configs <- ag_sg06_configs(length(x), h, M)
  if (!length(configs)) {
    return(list(group_id = "SG06_CONFORMABLE", eligible = FALSE,
                failure_code = "NO_REGISTERED_CONFIG", failure_detail = ""))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(configs))
  failures <- list()

  for (i in seq_along(configs)) {
    cfg <- configs[[i]]
    cid <- cfg$config_id
    losses <- numeric(0)
    ok <- TRUE
    fail <- NULL
    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_cfgm_fit_forecast(train, h, cfg$alpha)
        L <- ag_mase(val, out$forecast, train, M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        as.numeric(L)
      }, autogrey_engine_failure = identity)
      if (inherits(ans, "autogrey_engine_failure")) {
        ok <- FALSE; fail <- ans; break
      }
      losses <- c(losses, ans)
    }
    if (!ok) {
      failures[[cid]] <- paste0(fail$code, ":", fail$detail)
      next
    }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    scores[[i]] <- list(
      config_id = cid,
      alpha = as.numeric(cfg$alpha),
      mean_inner_mase = as.numeric(mean(losses)),
      origin_losses = as.numeric(losses)
    )
  }

  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG06_CONFORMABLE", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  band <- scores[means <= 1.05 * Lmin + 1e-15]

  # Frozen SG06 key is (inner loss, alpha, config ID). As in SG03, the
  # 5% band cannot displace a strictly better configuration; alpha is a tie key.
  loss <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  alpha <- vapply(band, `[[`, numeric(1), "alpha")
  cid <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(loss, alpha, cid)[1L]]]

  final <- tryCatch(ag_cfgm_fit_forecast(x, h, chosen$alpha), autogrey_engine_failure = identity)
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG06_CONFORMABLE", eligible = FALSE,
                selected_config_id = chosen$config_id,
                selected_config = list(alpha = chosen$alpha),
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG06_CONFORMABLE",
    eligible = TRUE,
    selected_config_id = chosen$config_id,
    selected_config = list(alpha = as.numeric(chosen$alpha)),
    forecast = final$forecast,
    fitted = final$fitted,
    inner_scores = scores,
    config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin),
      band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(configs)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}

# ---------------------------------------------------------------------------
# Step 7B7 — SG07_ROLLING
# Exact port of AG_ENGINE_4FB_1R1 rolling GM branch.
# SG01-SG06 above are frozen from externally R-verified Step 7B6.
# ---------------------------------------------------------------------------

ag_rolling_gm_forecast <- function(x, h, w = 4L) {
  w <- as.integer(w)
  x <- ag_as_series(x, w)
  h <- as.integer(h)

  # Match Python ordering exactly: series-length validation above occurs
  # before refusing any non-v1 rolling window.
  if (w != 4L) ag_stop("ROLL_WINDOW_NOT_V1", sprintf("w=%d", w))

  pseudo <- as.numeric(x)
  if (h > 0L) {
    for (j in seq_len(h)) {
      window <- tail(pseudo, w)
      if (length(window) != w) ag_stop("ROLL_WINDOW_UNAVAILABLE")
      out <- ag_gm_fit_forecast(window, 1L, 0.5)
      pseudo <- c(pseudo, as.numeric(out$forecast[1L]))
    }
  }

  list(
    forecast = tail(pseudo, h),
    # Rolling forecasts do not define one static fitted path. Frozen B1 keeps
    # the observed history as a NaN-free diagnostic placeholder.
    fitted = as.numeric(x),
    params = list(w = 4L, alpha_bg = 0.5),
    diagnostics = list(
      recursive_refits = as.integer(h),
      fitted_semantics = "observed_history_placeholder"
    )
  )
}

ag_sg07_configs <- function(n, h, M = NULL) {
  # Python group_configs computes common origins before dispatching by group.
  ag_inner_origins(as.integer(n), as.integer(h))
  list(list(config_id = "w=4", w = 4L))
}

ag_sg07_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT", sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }
  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }
  invisible(TRUE)
}

ag_select_sg07 <- function(x, h, M = NULL) {
  x <- ag_as_series(x)
  h <- as.integer(h)
  pre <- tryCatch({ ag_sg07_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG07_ROLLING", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  configs <- ag_sg07_configs(length(x), h, M)
  if (!length(configs)) {
    return(list(group_id = "SG07_ROLLING", eligible = FALSE,
                failure_code = "NO_REGISTERED_CONFIG", failure_detail = ""))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(configs))
  failures <- list()

  for (i in seq_along(configs)) {
    cfg <- configs[[i]]
    cid <- cfg$config_id
    losses <- numeric(0)
    origin_diagnostics <- list()
    ok <- TRUE
    fail <- NULL

    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_rolling_gm_forecast(train, h, cfg$w)
        L <- ag_mase(val, out$forecast, train, M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        list(loss = as.numeric(L), diagnostics = out$diagnostics)
      }, autogrey_engine_failure = identity)
      if (inherits(ans, "autogrey_engine_failure")) {
        ok <- FALSE; fail <- ans; break
      }
      losses <- c(losses, ans$loss)
      origin_diagnostics[[length(origin_diagnostics) + 1L]] <- ans$diagnostics
    }

    if (!ok) {
      failures[[cid]] <- paste0(fail$code, ":", fail$detail)
      next
    }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    scores[[i]] <- list(
      config_id = cid,
      w = as.integer(cfg$w),
      mean_inner_mase = as.numeric(mean(losses)),
      origin_losses = as.numeric(losses),
      diagnostics = list(origin_diagnostics = origin_diagnostics)
    )
  }

  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG07_ROLLING", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  band <- scores[means <= 1.05 * Lmin + 1e-15]

  # Frozen default key for SG07 is (inner loss, config ID).
  loss <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  cid <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(loss, cid)[1L]]]
  chosen_cfg <- list(w = as.integer(chosen$w))

  final <- tryCatch(ag_rolling_gm_forecast(x, h, chosen_cfg$w), autogrey_engine_failure = identity)
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG07_ROLLING", eligible = FALSE,
                selected_config_id = chosen$config_id,
                selected_config = chosen_cfg,
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG07_ROLLING",
    eligible = TRUE,
    selected_config_id = chosen$config_id,
    selected_config = chosen_cfg,
    forecast = final$forecast,
    fitted = final$fitted,
    inner_scores = scores,
    config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin),
      band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(configs)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}

# ---------------------------------------------------------------------------
# Step 7B8 — SG08_WBO
# Exact port of AG_ENGINE_4FB_1R1 average weakening-buffer + GM endpoint branch.
# SG01-SG07 above are frozen from externally R-verified Step 7B7 R1.
# ---------------------------------------------------------------------------

ag_average_wbo <- function(x) {
  x <- ag_as_series(x)
  n <- length(x)
  suffix <- rev(cumsum(rev(x)))
  counts <- seq.int(n, 1L)
  out <- suffix / as.numeric(counts)
  if (any(!is.finite(out))) ag_stop("WBO_NONFINITE")
  tol <- 1e-12 * max(1.0, abs(as.numeric(x[n])))
  if (abs(as.numeric(out[n]) - as.numeric(x[n])) > tol) {
    ag_stop("WBO_FIXED_POINT_FAIL")
  }
  as.numeric(out)
}

ag_wbo_gm_forecast <- function(x, h) {
  x <- ag_as_series(x, 4L)
  h <- as.integer(h)
  pseudo <- as.numeric(x)

  if (h > 0L) {
    for (j in seq_len(h)) {
      d <- ag_average_wbo(pseudo)
      gm <- ag_gm_fit_forecast(d, 1L, 0.5)
      pseudo <- c(pseudo, as.numeric(gm$forecast[1L]))
    }
  }

  list(
    forecast = tail(pseudo, h),
    fitted = as.numeric(x),
    params = list(operator = "average_suffix_WBO", alpha_bg = 0.5),
    diagnostics = list(
      recursive_refits = as.integer(h),
      output_scale = "AutoGrey endpoint convention on original scale"
    )
  )
}

ag_sg08_configs <- function(n, h, M = NULL) {
  # Match Python group_configs: common-origin feasibility is evaluated before
  # group dispatch even though SG08 itself has no tuning parameter.
  ag_inner_origins(as.integer(n), as.integer(h))
  list(list(config_id = "average_WBO"))
}

ag_sg08_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT", sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }
  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }
  invisible(TRUE)
}

ag_select_sg08 <- function(x, h, M = NULL) {
  x <- ag_as_series(x)
  h <- as.integer(h)
  pre <- tryCatch({ ag_sg08_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG08_WBO", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  configs <- ag_sg08_configs(length(x), h, M)
  if (!length(configs)) {
    return(list(group_id = "SG08_WBO", eligible = FALSE,
                failure_code = "NO_REGISTERED_CONFIG", failure_detail = ""))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(configs))
  failures <- list()

  for (i in seq_along(configs)) {
    cfg <- configs[[i]]
    cid <- cfg$config_id
    losses <- numeric(0)
    origin_diagnostics <- list()
    ok <- TRUE
    fail <- NULL

    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_wbo_gm_forecast(train, h)
        L <- ag_mase(val, out$forecast, train, M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        list(loss = as.numeric(L), diagnostics = out$diagnostics)
      }, autogrey_engine_failure = identity)
      if (inherits(ans, "autogrey_engine_failure")) {
        ok <- FALSE; fail <- ans; break
      }
      losses <- c(losses, ans$loss)
      origin_diagnostics[[length(origin_diagnostics) + 1L]] <- ans$diagnostics
    }

    if (!ok) {
      failures[[cid]] <- paste0(fail$code, ":", fail$detail)
      next
    }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    scores[[i]] <- list(
      config_id = cid,
      config = list(),
      mean_inner_mase = as.numeric(mean(losses)),
      origin_losses = as.numeric(losses),
      diagnostics = list(origin_diagnostics = origin_diagnostics)
    )
  }

  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG08_WBO", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  band <- scores[means <= 1.05 * Lmin + 1e-15]

  # Frozen default key for SG08 is (inner loss, config ID).
  loss <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  cid <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(loss, cid)[1L]]]

  final <- tryCatch(ag_wbo_gm_forecast(x, h), autogrey_engine_failure = identity)
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG08_WBO", eligible = FALSE,
                selected_config_id = chosen$config_id,
                selected_config = list(),
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG08_WBO",
    eligible = TRUE,
    selected_config_id = chosen$config_id,
    selected_config = list(),
    forecast = final$forecast,
    fitted = final$fitted,
    inner_scores = scores,
    config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin),
      band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(configs)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}

# ---------------------------------------------------------------------------
# Step 7B9 — SG09_GREY_MARKOV
# Exact port of AG_ENGINE_4FB_1R1 Grey-Markov branch.
# SG01-SG08 above are frozen from externally R-verified Step 7B8.
# ---------------------------------------------------------------------------

AG_MARKOV_ROW_TOL <- 1e-10

ag_markov_state_edges <- function(resid, S, boundary) {
  resid <- as.numeric(resid)
  S <- as.integer(S)
  boundary <- as.character(boundary)
  if (S < 2L) ag_stop("MARKOV_S_DOMAIN")
  rmin <- min(resid)
  rmax <- max(resid)
  eps <- 1e-12 * max(mean(abs(resid)), 1.0)
  if ((rmax - rmin) <= eps) ag_stop("MARKOV_RESIDUAL_RANGE_DEGENERATE")

  if (identical(boundary, "EQW")) {
    edges <- seq(rmin, rmax, length.out = S + 1L)
  } else if (identical(boundary, "EQT")) {
    # NumPy quantile(..., method="linear") corresponds to R quantile type=7.
    edges <- as.numeric(stats::quantile(
      resid,
      probs = seq(0, 1, length.out = S + 1L),
      type = 7,
      names = FALSE
    ))
    if (any(diff(edges) <= eps)) ag_stop("MARKOV_EQT_DUPLICATE_BOUNDARY")
  } else {
    ag_stop("MARKOV_BOUNDARY_UNKNOWN")
  }
  as.numeric(edges)
}

ag_markov_assign_states <- function(values, edges) {
  values <- as.numeric(values)
  edges <- as.numeric(edges)
  S <- length(edges) - 1L
  if (S < 1L) return(integer(length(values)))
  if (S == 1L) return(rep.int(0L, length(values)))
  # NumPy searchsorted(edges[1:-1], values, side="right"):
  # internal boundaries belong to the upper/right interval; max maps to S-1.
  as.integer(findInterval(values, edges[2L:S], left.open = FALSE, rightmost.closed = FALSE))
}

ag_markov_transition_matrix <- function(states, S, lag = 1L) {
  states <- as.integer(states)
  S <- as.integer(S)
  lag <- as.integer(lag)
  counts <- matrix(0L, nrow = S, ncol = S)
  origins <- integer(S)
  if (lag < 1L || length(states) <= lag) {
    return(list(P = matrix(NaN, nrow = S, ncol = S), origins = origins, counts = counts))
  }
  for (i in seq_len(length(states) - lag)) {
    a <- states[i] + 1L
    b <- states[i + lag] + 1L
    counts[a, b] <- counts[a, b] + 1L
    origins[a] <- origins[a] + 1L
  }
  P <- matrix(NaN, nrow = S, ncol = S)
  for (i in seq_len(S)) {
    if (origins[i] > 0L) P[i, ] <- as.numeric(counts[i, ]) / origins[i]
  }
  list(P = P, origins = origins, counts = counts)
}

ag_markov_resolve_next_state <- function(states, S, current) {
  states <- as.integer(states)
  S <- as.integer(S)
  current <- as.integer(current)

  t1 <- ag_markov_transition_matrix(states, S, 1L)
  idx <- current + 1L
  if (t1$origins[idx] < 2L) {
    ag_stop("MARKOV_CURRENT_OUTGOING_TOO_FEW",
            sprintf("state=%d,count=%d", current, t1$origins[idx]))
  }
  row <- t1$P[idx, ]
  if (any(!is.finite(row)) || abs(sum(row) - 1.0) > AG_MARKOV_ROW_TOL) {
    ag_stop("MARKOV_ROW_NOT_STOCHASTIC")
  }
  mx <- max(row)
  tied <- which(abs(row - mx) <= 1e-15) - 1L
  if (length(tied) == 1L) return(list(next_state = as.integer(tied), used_lag = 1L))

  # Frozen source-inspired higher-lag rule: use the first direct lag whose
  # empirical transition probabilities uniquely separate the tied states.
  if (length(states) > 2L) {
    for (lag in 2L:(length(states) - 1L)) {
      tm <- ag_markov_transition_matrix(states, S, lag)
      if (tm$origins[idx] <= 0L || any(!is.finite(tm$P[idx, ]))) next
      vals <- tm$P[idx, tied + 1L]
      vmax <- max(vals)
      winners <- tied[abs(vals - vmax) <= 1e-15]
      if (length(winners) == 1L) {
        return(list(next_state = as.integer(winners), used_lag = as.integer(lag)))
      }
    }
  }
  ag_stop("MARKOV_TIE_UNRESOLVED",
          sprintf("state=%d, tied=[%s]", current, paste(tied, collapse = ", ")))
}

ag_greymarkov_fit_forecast <- function(x, h, S, boundary) {
  x <- ag_as_series(x, 6L)
  h <- as.integer(h)
  S <- as.integer(S)
  boundary <- as.character(boundary)

  if (S > min(4L, (length(x) - 1L) %/% 2L)) {
    ag_stop("MARKOV_S_CAP", sprintf("S=%d,n=%d", S, length(x)))
  }

  gm <- ag_gm_fit_forecast(x, h, 0.5)
  resid <- x - gm$fitted
  edges <- ag_markov_state_edges(resid, S, boundary)
  states <- ag_markov_assign_states(resid, edges)

  occupied <- sort(unique(states))
  t1 <- ag_markov_transition_matrix(states, S, 1L)
  for (st in occupied) {
    idx <- st + 1L
    if (t1$origins[idx] < 2L) {
      ag_stop("MARKOV_OUTGOING_TOO_FEW",
              sprintf("state=%d,count=%d", st, t1$origins[idx]))
    }
    row <- t1$P[idx, ]
    if (any(!is.finite(row)) || abs(sum(row) - 1.0) > AG_MARKOV_ROW_TOL) {
      ag_stop("MARKOV_ROW_NOT_STOCHASTIC", sprintf("state=%d", st))
    }
  }

  mids <- 0.5 * (edges[-length(edges)] + edges[-1L])
  current <- as.integer(tail(states, 1L))
  corrected <- numeric(h)
  tie_lags <- integer(h)
  if (h > 0L) {
    for (j in seq_len(h)) {
      r <- ag_markov_resolve_next_state(states, S, current)
      tie_lags[j] <- r$used_lag
      corrected[j] <- as.numeric(gm$forecast[j] + mids[r$next_state + 1L])
      current <- r$next_state
    }
  }
  if (any(!is.finite(corrected))) ag_stop("MARKOV_FORECAST_NONFINITE")

  state_counts <- setNames(
    lapply(occupied, function(st) as.integer(sum(states == st))),
    as.character(occupied)
  )
  outgoing_counts <- setNames(
    lapply(occupied, function(st) as.integer(t1$origins[st + 1L])),
    as.character(occupied)
  )

  list(
    forecast = as.numeric(corrected),
    fitted = as.numeric(gm$fitted),
    params = list(S = as.integer(S), boundary = boundary, edges = as.numeric(edges)),
    diagnostics = list(
      base_gm_params = gm$params,
      state_counts = state_counts,
      outgoing_counts = outgoing_counts,
      tie_resolution_lags = as.integer(tie_lags),
      states = as.integer(states)
    )
  )
}

ag_sg09_configs <- function(n, h, M = NULL) {
  origins <- ag_inner_origins(as.integer(n), as.integer(h))
  m_first <- origins[1L]
  Smax <- min(4L, (m_first - 1L) %/% 2L)
  if (Smax < 2L) return(list())
  out <- list()
  k <- 1L
  for (S in 2L:Smax) {
    for (boundary in c("EQW", "EQT")) {
      out[[k]] <- list(
        config_id = sprintf("S=%d_%s", S, boundary),
        S = as.integer(S),
        boundary = boundary
      )
      k <- k + 1L
    }
  }
  out
}

ag_sg09_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT",
            sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }
  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }
  if (n < h + 8L) {
    ag_stop("GROUP_HISTORY_SHORT", sprintf("SG09 requires n>=%d", h + 8L))
  }
  invisible(TRUE)
}

ag_select_sg09 <- function(x, h, M = NULL) {
  x <- ag_as_series(x)
  h <- as.integer(h)
  pre <- tryCatch({ ag_sg09_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG09_GREY_MARKOV", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  configs <- ag_sg09_configs(length(x), h, M)
  if (!length(configs)) {
    return(list(group_id = "SG09_GREY_MARKOV", eligible = FALSE,
                failure_code = "NO_REGISTERED_CONFIG", failure_detail = ""))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(configs))
  failures <- list()

  for (i in seq_along(configs)) {
    cfg <- configs[[i]]
    cid <- cfg$config_id
    losses <- numeric(0)
    origin_diagnostics <- list()
    ok <- TRUE
    fail <- NULL
    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_greymarkov_fit_forecast(train, h, cfg$S, cfg$boundary)
        L <- ag_mase(val, out$forecast, train, M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        list(loss = as.numeric(L), diagnostics = out$diagnostics)
      }, autogrey_engine_failure = identity)
      if (inherits(ans, "autogrey_engine_failure")) {
        ok <- FALSE; fail <- ans; break
      }
      losses <- c(losses, ans$loss)
      origin_diagnostics[[length(origin_diagnostics) + 1L]] <- ans$diagnostics
    }
    if (!ok) {
      failures[[cid]] <- paste0(fail$code, ":", fail$detail)
      next
    }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    scores[[i]] <- list(
      config_id = cid,
      config = list(S = as.integer(cfg$S), boundary = cfg$boundary),
      S = as.integer(cfg$S),
      boundary = cfg$boundary,
      mean_inner_mase = as.numeric(mean(losses)),
      origin_losses = as.numeric(losses),
      diagnostics = list(origin_diagnostics = origin_diagnostics)
    )
  }

  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG09_GREY_MARKOV", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  band <- scores[means <= 1.05 * Lmin + 1e-15]

  # Frozen SG09 key: fewer states, EQW before EQT, then loss, then config ID.
  Skey <- vapply(band, `[[`, integer(1), "S")
  Bkey <- vapply(band, function(s) if (identical(s$boundary, "EQW")) 0L else 1L, integer(1))
  Lkey <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  Ckey <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(Skey, Bkey, Lkey, Ckey)[1L]]]

  final <- tryCatch(
    ag_greymarkov_fit_forecast(x, h, chosen$S, chosen$boundary),
    autogrey_engine_failure = identity
  )
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG09_GREY_MARKOV", eligible = FALSE,
                selected_config_id = chosen$config_id,
                selected_config = list(S = chosen$S, boundary = chosen$boundary),
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG09_GREY_MARKOV",
    eligible = TRUE,
    selected_config_id = chosen$config_id,
    selected_config = list(S = as.integer(chosen$S), boundary = chosen$boundary),
    forecast = final$forecast,
    fitted = final$fitted,
    inner_scores = scores,
    config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin),
      band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(configs)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}

# ---------------------------------------------------------------------------
# Step 7B10 — SG10_SEASONAL
# Append-only port of AG_ENGINE_4FB_1R1. SG01-SG09 above are frozen parents.
# ---------------------------------------------------------------------------

AG_SEASON_REDUCTION_TOL <- 1e-6

ag_seasonal_factors <- function(x, M) {
  x <- ag_as_series(x)
  M <- as.integer(M)
  if (M < 2L) ag_stop("SEASON_M_INVALID")
  if (length(x) < 2L * M) {
    ag_stop("SEASON_PHASE_COUNT_TOO_FEW", sprintf("n=%d,M=%d", length(x), M))
  }

  means <- numeric(M)
  for (s in 0L:(M - 1L)) {
    idx <- seq.int(s + 1L, length(x), by = M)
    if (length(idx) < 2L) {
      ag_stop("SEASON_PHASE_COUNT_TOO_FEW",
              sprintf("phase=%d,count=%d", s, length(idx)))
    }
    means[s + 1L] <- mean(x[idx])
  }

  overall <- mean(x)
  eps <- 1e-12 * max(mean(abs(x)), 1.0)
  if (!is.finite(overall) || abs(overall) <= eps) {
    ag_stop("SEASON_OVERALL_MEAN_INVALID")
  }
  factors <- as.numeric(means / overall)
  if (any(!is.finite(factors)) || any(factors <= 0)) {
    ag_stop("SEASON_FACTOR_INVALID")
  }
  if (max(abs(factors - 1.0)) <= AG_SEASON_REDUCTION_TOL) {
    ag_stop("SEASON_GM_REDUCTION")
  }
  factors
}

ag_sgm_fit_forecast <- function(x, h, M) {
  M <- as.integer(M)
  x <- ag_as_series(x, max(4L, 2L * M))
  h <- as.integer(h)

  f <- ag_seasonal_factors(x, M)
  phase <- ((seq_along(x) - 1L) %% M) + 1L
  u <- as.numeric(x / f[phase])
  xs <- cumsum(u)
  z <- 0.5 * (xs[-1L] + xs[-length(xs)])
  B <- cbind(-z, rep(1.0, length(x) - 1L))
  fit <- ag_lstsq_checked(B, u[-1L], failure_prefix = "SGM")
  a <- as.numeric(fit$theta[1L])
  b <- as.numeric(fit$theta[2L])

  xshat <- ag_continuous_response_constant(xs[1L], a, b, length(x) + h)
  uhat <- numeric(length(xshat))
  uhat[1L] <- xshat[1L]
  if (length(xshat) > 1L) uhat[-1L] <- diff(xshat)
  all_phase <- ((seq_along(xshat) - 1L) %% M) + 1L
  xhat <- as.numeric(uhat * f[all_phase])
  if (any(!is.finite(xhat))) ag_stop("SEASON_RESTORE_NONFINITE")

  list(
    forecast = as.numeric(tail(xhat, h)),
    fitted = as.numeric(xhat[seq_len(length(x))]),
    params = list(a = a, b = b, M = as.integer(M), factors = as.numeric(f)),
    diagnostics = fit$diagnostics
  )
}

ag_sg10_configs <- function(n, h, M = NULL) {
  if (is.null(M)) return(list())
  list(list(config_id = sprintf("M=%d", as.integer(M)), M = as.integer(M)))
}

ag_sg10_precheck <- function(x, h, M = NULL) {
  n <- length(x); h <- as.integer(h)
  if (n < h + 7L) {
    ag_stop("GLOBAL_SELECTION_HISTORY_SHORT",
            sprintf("n=%d,h=%d,requires>=%d", n, h, h + 7L))
  }

  if (!is.null(M)) {
    MM <- as.integer(M)
    if (MM < 2L) ag_stop("SEASON_M_INVALID")
    m_first <- ag_inner_origins(n, h)[1L]
    if (m_first <= MM) {
      ag_stop("INNER_MASE_SCALE_HISTORY_SHORT",
              sprintf("earliest_inner_n=%d must exceed M=%d", m_first, MM))
    }
  }

  if (is.null(M)) ag_stop("SEASON_METADATA_MISSING")
  MM <- as.integer(M)
  if (MM < 2L) ag_stop("SEASON_M_INVALID")
  if (ag_inner_origins(n, h)[1L] < 2L * MM) {
    ag_stop("SEASON_PHASE_COUNT_TOO_FEW")
  }
  invisible(TRUE)
}

ag_select_sg10 <- function(x, h, M = NULL) {
  x <- ag_as_series(x)
  h <- as.integer(h)
  pre <- tryCatch({ ag_sg10_precheck(x, h, M); NULL }, autogrey_engine_failure = identity)
  if (!is.null(pre)) {
    return(list(group_id = "SG10_SEASONAL", eligible = FALSE,
                failure_code = pre$code, failure_detail = pre$detail))
  }

  configs <- ag_sg10_configs(length(x), h, M)
  if (!length(configs)) {
    return(list(group_id = "SG10_SEASONAL", eligible = FALSE,
                failure_code = "NO_REGISTERED_CONFIG", failure_detail = ""))
  }

  origins <- ag_inner_origins(length(x), h)
  scores <- vector("list", length(configs))
  failures <- list()

  for (i in seq_along(configs)) {
    cfg <- configs[[i]]
    cid <- cfg$config_id
    losses <- numeric(0)
    origin_diagnostics <- list()
    ok <- TRUE
    fail <- NULL

    for (m in origins) {
      ans <- tryCatch({
        train <- x[seq_len(m)]
        val <- x[(m + 1L):(m + h)]
        out <- ag_sgm_fit_forecast(train, h, cfg$M)
        L <- ag_mase(val, out$forecast, train, cfg$M)
        if (!is.finite(L)) ag_stop("INNER_LOSS_NONFINITE")
        list(loss = as.numeric(L), diagnostics = out$diagnostics)
      }, autogrey_engine_failure = identity)

      if (inherits(ans, "autogrey_engine_failure")) {
        ok <- FALSE; fail <- ans; break
      }
      losses <- c(losses, ans$loss)
      origin_diagnostics[[length(origin_diagnostics) + 1L]] <- ans$diagnostics
    }

    if (!ok) {
      failures[[cid]] <- paste0(fail$code, ":", fail$detail)
      next
    }
    if (length(losses) != 3L) ag_stop("UNEQUAL_INNER_ORIGINS")
    scores[[i]] <- list(
      config_id = cid,
      config = list(M = as.integer(cfg$M)),
      M = as.integer(cfg$M),
      mean_inner_mase = as.numeric(mean(losses)),
      origin_losses = as.numeric(losses),
      diagnostics = list(origin_diagnostics = origin_diagnostics)
    )
  }

  scores <- Filter(Negate(is.null), scores)
  if (!length(scores)) {
    return(list(group_id = "SG10_SEASONAL", eligible = FALSE, inner_scores = list(),
                config_failures = failures, failure_code = "NO_VALID_CONFIG",
                failure_detail = "All frozen configurations failed at >=1 common origin."))
  }

  means <- vapply(scores, `[[`, numeric(1), "mean_inner_mase")
  Lmin <- min(means)
  band <- scores[means <= 1.05 * Lmin + 1e-15]
  # Frozen generic singleton key for SG10: loss, then config ID.
  Lkey <- vapply(band, `[[`, numeric(1), "mean_inner_mase")
  Ckey <- vapply(band, `[[`, character(1), "config_id")
  chosen <- band[[order(Lkey, Ckey)[1L]]]

  final <- tryCatch(
    ag_sgm_fit_forecast(x, h, chosen$M),
    autogrey_engine_failure = identity
  )
  if (inherits(final, "autogrey_engine_failure")) {
    return(list(group_id = "SG10_SEASONAL", eligible = FALSE,
                selected_config_id = chosen$config_id,
                selected_config = list(M = as.integer(chosen$M)),
                inner_scores = scores, config_failures = failures,
                failure_code = "FINAL_REFIT_FAIL",
                failure_detail = paste0(final$code, ":", final$detail)))
  }

  list(
    group_id = "SG10_SEASONAL",
    eligible = TRUE,
    selected_config_id = chosen$config_id,
    selected_config = list(M = as.integer(chosen$M)),
    forecast = final$forecast,
    fitted = final$fitted,
    inner_scores = scores,
    config_failures = failures,
    diagnostics = list(
      Lmin = as.numeric(Lmin),
      band_size = as.integer(length(band)),
      selected_to_best_ratio = as.numeric(chosen$mean_inner_mase / max(Lmin, 1e-15)),
      selected_inner_mase = as.numeric(chosen$mean_inner_mase),
      config_count_registered = as.integer(length(configs)),
      config_count_valid = as.integer(length(scores)),
      final_model_diagnostics = final$diagnostics,
      final_params = final$params,
      common_origins = as.integer(origins)
    )
  )
}
