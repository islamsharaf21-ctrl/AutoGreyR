# AutoGrey v2 — V2-P4E1 Fan implementation R2
#
# SOURCE-DRIVEN R2 AMENDMENT:
# Fan & Zhang's dynamic kernel is evaluated using the
# fitted accumulated GM response xhat^(1)(t), not the
# observed accumulated state.
#
# R1 remains immutable and preserved.
# No REALBENCH3, selector training, or feature redesign.
#
# AutoGrey v2 — V2-P4E1B
# Fan & Zhang (2003) self-memory grey model
#
# IMPORTANT:
# - source-core functions allow any integer p >= 1 for source-fixture work;
# - selectable AutoGrey wrappers allow ONLY p in {1,2,3};
# - no REALBENCH3 data, selector training, or feature redesign occurs here.

.ag_fail <- function(code, detail = NULL) {
  list(
    ok = FALSE,
    status = code,
    detail = if (is.null(detail)) "" else as.character(detail)
  )
}

.ag_svd_diagnostics <- function(X) {
  X <- as.matrix(X)

  if (!all(is.finite(X))) {
    return(list(
      rank = NA_integer_,
      tol = NA_real_,
      kappa2 = Inf,
      sigma_max = NA_real_
    ))
  }

  s <- svd(X, nu = 0L, nv = 0L)$d

  if (length(s) == 0L) {
    return(list(
      rank = 0L,
      tol = 0,
      kappa2 = Inf,
      sigma_max = 0
    ))
  }

  sigma_max <- max(s)

  tol <- max(dim(X)) *
    .Machine$double.eps *
    sigma_max

  rank <- sum(s > tol)

  kappa2 <- if (min(s) <= 0) {
    Inf
  } else {
    max(s) / min(s)
  }

  list(
    rank = as.integer(rank),
    tol = tol,
    kappa2 = kappa2,
    sigma_max = sigma_max
  )
}

.ag_qr_ls <- function(X, y, label) {
  X <- as.matrix(X)
  y <- as.numeric(y)

  if (!all(is.finite(X)) || !all(is.finite(y))) {
    return(.ag_fail(
      "INPUT_NONFINITE_OR_MISSING",
      paste0(label, ": non-finite LS input")
    ))
  }

  nr <- nrow(X)
  nc <- ncol(X)

  if ((nr - nc) < 1L) {
    return(.ag_fail(
      "SATURATED_CONFIGURATION",
      paste0(
        label,
        ": rows=", nr,
        " parameters=", nc,
        " residual_df=", nr - nc
      )
    ))
  }

  dg <- .ag_svd_diagnostics(X)

  if (dg$rank < nc) {
    return(.ag_fail(
      "RANK_DEFICIENT",
      paste0(
        label,
        ": rank=", dg$rank,
        " parameters=", nc
      )
    ))
  }

  if (!is.finite(dg$kappa2) || dg$kappa2 >= 1e12) {
    return(.ag_fail(
      "ILL_CONDITIONED",
      paste0(label, ": kappa2=", format(dg$kappa2))
    ))
  }

  qx <- qr(X, LAPACK = TRUE)
  beta <- tryCatch(
    as.numeric(qr.coef(qx, y)),
    error = function(e) NULL
  )

  if (is.null(beta) ||
      length(beta) != nc ||
      !all(is.finite(beta))) {
    return(.ag_fail(
      "FAN_SOURCE_EQUATION_SOLVE_FAIL",
      paste0(label, ": QR solution failed")
    ))
  }

  list(
    ok = TRUE,
    status = "OK",
    coefficients = beta,
    residual_df = nr - nc,
    rank = dg$rank,
    rank_tol = dg$tol,
    kappa2 = dg$kappa2,
    conditioning_warning =
      is.finite(dg$kappa2) &&
      dg$kappa2 >= 1e8 &&
      dg$kappa2 < 1e12
  )
}

.ag_fan_gm_xhat1 <- function(a,
                              u,
                              x0_first,
                              time_index) {
  tau <- as.numeric(time_index) - 1

  if (!all(is.finite(c(a, u, x0_first, tau)))) {
    stop("Non-finite Fan GM response input.")
  }

  # Source GM time response:
  #
  # xhat^(1)(t) =
  #   (x^(0)(1) - u/a) exp[-a(t-1)] + u/a
  #
  # Algebraically equivalent stable form:
  #
  # x^(0)(1) exp(-a*tau)
  #   - u*expm1(-a*tau)/a
  #
  # Exact a=0 limit is x0_first + u*tau.
  if (a == 0) {
    return(x0_first + u * tau)
  }

  ans <-
    x0_first * exp(-a * tau) -
    u * expm1(-a * tau) / a

  if (!all(is.finite(ans))) {
    stop("Non-finite Fan fitted accumulated response.")
  }

  ans
}


.ag_fan_gm_kernel_fit <- function(x0) {
  x0 <- as.numeric(x0)

  if (length(x0) < 4L) {
    return(.ag_fail(
      "FAN_GM_HISTORY_INSUFFICIENT",
      "GM kernel requires at least four observations"
    ))
  }

  if (!all(is.finite(x0))) {
    return(.ag_fail(
      "INPUT_NONFINITE_OR_MISSING",
      "Fan GM kernel input is non-finite"
    ))
  }

  x1 <- cumsum(x0)
  n <- length(x1)

  # Fan & Zhang GM(1,1):
  # x^(0)(k) + a*z^(1)(k) = u
  zneg <- -0.5 * (
    x1[2:n] +
    x1[1:(n - 1L)]
  )

  B <- cbind(
    zneg,
    rep(1, n - 1L)
  )

  fit <- .ag_qr_ls(
    B,
    x0[2:n],
    "FAN_GM_KERNEL"
  )

  if (!isTRUE(fit$ok)) {
    return(fit)
  }

  a <- fit$coefficients[1]
  u <- fit$coefficients[2]

  x1_hat <- tryCatch(
    .ag_fan_gm_xhat1(
      a = a,
      u = u,
      x0_first = x0[1],
      time_index = seq_len(n)
    ),
    error = function(e) NULL
  )

  if (is.null(x1_hat) ||
      length(x1_hat) != n ||
      !all(is.finite(x1_hat))) {
    return(.ag_fail(
      "FAN_GM_RESPONSE_FAIL",
      "Could not construct fitted accumulated GM response"
    ))
  }

  list(
    ok = TRUE,
    status = "OK",
    a = a,
    u = u,
    x1 = x1,
    x1_hat = x1_hat,
    diagnostics = fit
  )
}


.ag_fan_design_row <- function(history_x1,
                               kernel_x1hat,
                               a,
                               u,
                               p,
                               dt = 1) {
  history_x1 <- as.numeric(history_x1)
  kernel_x1hat <- as.numeric(kernel_x1hat)

  if (length(history_x1) != (p + 1L)) {
    stop(
      "Fan state history must contain p+1 accumulated states."
    )
  }

  if (length(kernel_x1hat) != (p + 1L)) {
    stop(
      "Fan fitted-kernel history must contain p+1 values."
    )
  }

  if (!all(is.finite(history_x1)) ||
      !all(is.finite(kernel_x1hat)) ||
      !is.finite(a) ||
      !is.finite(u) ||
      !is.finite(dt) ||
      dt <= 0) {
    stop("Non-finite/invalid Fan design inputs.")
  }

  # Fan source dynamic kernel:
  #
  # F(x,t) = u - a*xhat^(1)(t)
  #
  # where xhat^(1) is the fitted accumulated GM response.
  #
  # IMPORTANT:
  # history_x1 remains the self-memory state sequence.
  Fv <- u - a * kernel_x1hat

  phi <- numeric(p + 2L)

  # alpha_{-p}
  phi[1L] <-
    history_x1[1L] -
    history_x1[2L] +
    2 * Fv[1L] * dt

  # alpha_i, i=-p+1,...,-1
  if (p >= 2L) {
    for (j in 2L:p) {
      phi[j] <-
        history_x1[j - 1L] -
        history_x1[j + 1L] +
        2 * Fv[j] * dt
    }
  }

  # alpha_0
  phi[p + 1L] <-
    history_x1[p] +
    2 * Fv[p + 1L] * dt

  # alpha_1
  phi[p + 2L] <-
    history_x1[p + 1L]

  phi
}


# Generic source-faithful core.
# p >= 1 is permitted here ONLY so published source fixtures
# such as Fan's p=4 example can be independently reproduced.
ag_fan_smgm_fit_source_core <- function(x,
                                        p,
                                        dt = 1) {
  x <- as.numeric(x)

  if (length(p) != 1L ||
      !is.finite(p) ||
      p != as.integer(p) ||
      p < 1L) {
    return(.ag_fail(
      "FAN_P_INVALID",
      "p must be one positive integer"
    ))
  }

  p <- as.integer(p)

  if (!all(is.finite(x))) {
    return(.ag_fail(
      "INPUT_NONFINITE_OR_MISSING",
      "Fan source-core input is non-finite"
    ))
  }

  if (!is.finite(dt) || dt <= 0) {
    return(.ag_fail(
      "FAN_DT_INVALID",
      "dt must be finite and > 0"
    ))
  }

  gm <- .ag_fan_gm_kernel_fit(x)

  if (!isTRUE(gm$ok)) {
    return(gm)
  }

  x1 <- gm$x1
  x1_hat <- gm$x1_hat
  n <- length(x1)

  effective_rows <- n - p - 1L
  parameter_count <- p + 2L

  if (effective_rows < (p + 3L)) {
    return(.ag_fail(
      "FAN_CAPACITY_FAIL",
      paste0(
        "effective_rows=", effective_rows,
        "; required>=", p + 3L,
        "; p=", p
      )
    ))
  }

  X <- matrix(
    NA_real_,
    nrow = effective_rows,
    ncol = parameter_count
  )

  y <- numeric(effective_rows)

  target_indices <- (p + 2L):n

  for (rr in seq_along(target_indices)) {
    tt <- target_indices[rr]

    idx_start <- tt - p - 1L
    idx_end <- tt - 1L

    history <- x1[idx_start:idx_end]

    kernel_history <-
      x1_hat[idx_start:idx_end]

    X[rr, ] <- .ag_fan_design_row(
      history_x1 = history,
      kernel_x1hat = kernel_history,
      a = gm$a,
      u = gm$u,
      p = p,
      dt = dt
    )

    y[rr] <- x1[tt]
  }

  alpha_fit <- .ag_qr_ls(
    X,
    y,
    paste0("FAN_MEMORY_P", p)
  )

  if (!isTRUE(alpha_fit$ok)) {
    return(alpha_fit)
  }

  alpha <- alpha_fit$coefficients

  if (length(alpha) != parameter_count ||
      !all(is.finite(alpha))) {
    return(.ag_fail(
      "FAN_SOURCE_EQUATION_SOLVE_FAIL",
      "Invalid memory-coefficient vector"
    ))
  }

  list(
    ok = TRUE,
    status = "OK",
    implementation_revision = "R2_XHAT1_KERNEL",
    branch = "FAN",
    p = p,
    dt = dt,
    n = n,
    a = gm$a,
    u = gm$u,
    alpha = alpha,
    alpha_names = c(
      paste0("alpha_", -p:0),
      "alpha_1"
    ),
    effective_rows = effective_rows,
    parameter_count = parameter_count,
    gm_diagnostics = gm$diagnostics,
    memory_diagnostics = alpha_fit,
    training_x0 = x,
    training_x1 = x1,
    training_x1_hat = x1_hat
  )
}


ag_fan_smgm_predict_source_core <- function(fit,
                                            h) {
  if (!is.list(fit) ||
      !isTRUE(fit$ok) ||
      !identical(fit$branch, "FAN")) {
    return(.ag_fail(
      "FAN_INVALID_FIT_OBJECT",
      "Valid Fan source-core fit required"
    ))
  }

  if (length(h) != 1L ||
      !is.finite(h) ||
      h != as.integer(h) ||
      h < 1L) {
    return(.ag_fail(
      "FAN_H_INVALID",
      "h must be one positive integer"
    ))
  }

  h <- as.integer(h)

  p <- fit$p
  x1_ext <- as.numeric(fit$training_x1)
  fc <- numeric(h)

  for (step in seq_len(h)) {
    current_n <- length(x1_ext)

    history_idx <-
      (current_n - p):current_n

    history <-
      x1_ext[history_idx]

    kernel_history <- tryCatch(
      .ag_fan_gm_xhat1(
        a = fit$a,
        u = fit$u,
        x0_first = fit$training_x0[1],
        time_index = history_idx
      ),
      error = function(e) NULL
    )

    if (is.null(kernel_history) ||
        !all(is.finite(kernel_history))) {
      return(.ag_fail(
        "FAN_GM_RESPONSE_FAIL",
        paste0(
          "invalid fitted kernel at forecast step ",
          step
        )
      ))
    }

    phi <- .ag_fan_design_row(
      history_x1 = history,
      kernel_x1hat = kernel_history,
      a = fit$a,
      u = fit$u,
      p = p,
      dt = fit$dt
    )

    next_x1 <- sum(phi * fit$alpha)

    next_x0 <-
      next_x1 -
      tail(x1_ext, 1L)

    if (!is.finite(next_x1) ||
        !is.finite(next_x0)) {
      return(.ag_fail(
        "FORECAST_DOMAIN_INVALID",
        paste0(
          "non-finite Fan forecast at step ",
          step
        )
      ))
    }

    fc[step] <- next_x0
    x1_ext <- c(x1_ext, next_x1)
  }

  list(
    ok = TRUE,
    status = "OK",
    implementation_revision = "R2_XHAT1_KERNEL",
    branch = "FAN",
    p = p,
    h = h,
    forecast = fc,
    accumulated_extension =
      tail(x1_ext, h)
  )
}


ag_fan_smgm_forecast_source_core <- function(x,
                                             h,
                                             p,
                                             dt = 1) {
  fit <- ag_fan_smgm_fit_source_core(
    x = x,
    p = p,
    dt = dt
  )

  if (!isTRUE(fit$ok)) {
    return(fit)
  }

  pred <- ag_fan_smgm_predict_source_core(
    fit = fit,
    h = h
  )

  if (!isTRUE(pred$ok)) {
    return(pred)
  }

  pred$fit <- fit
  pred
}

# ----------------------------------------------------
# AutoGrey P4 selectable wrappers
# ----------------------------------------------------

.ag_fan_registered_p <- c(1L, 2L, 3L)

ag_fan_smgm_fit <- function(x,
                            p,
                            dt = 1) {
  if (length(p) != 1L ||
      !is.finite(p) ||
      p != as.integer(p) ||
      !(as.integer(p) %in% .ag_fan_registered_p)) {
    return(.ag_fail(
      "FAN_P_NOT_REGISTERED",
      "AutoGrey P4 permits Fan p only in {1,2,3}"
    ))
  }

  ag_fan_smgm_fit_source_core(
    x = x,
    p = as.integer(p),
    dt = dt
  )
}

ag_fan_smgm_forecast <- function(x,
                                 h,
                                 p,
                                 dt = 1) {
  fit <- ag_fan_smgm_fit(
    x = x,
    p = p,
    dt = dt
  )

  if (!isTRUE(fit$ok)) {
    return(fit)
  }

  pred <- ag_fan_smgm_predict_source_core(
    fit = fit,
    h = h
  )

  if (!isTRUE(pred$ok)) {
    return(pred)
  }

  pred$fit <- fit
  pred
}
