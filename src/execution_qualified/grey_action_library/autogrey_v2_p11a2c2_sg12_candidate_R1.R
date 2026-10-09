# AutoGrey V2-P4E2B
# SG12 fractional-dynamic model: Mao et al. FGM(q,1)
#
# Implementation revision: R1
#
# Source model:
#   x^(r-q)(k) + a*z^(r)(k) = b
#
# with:
#   x^(r)     = A^r x^(0)
#   x^(r-q)   = A^(-q) x^(r)
#   z^(r)(k)  = 0.5*x^(r)(k-1)+0.5*x^(r)(k)
#
# Forecast response follows Mao et al. Eq. (35),
# restoration follows A^(-r).
#
# IMPORTANT:
# - Exact P4-C r/q grid only.
# - q=1 reduction is not registered.
# - No PSO.
# - No REALBENCH3.
# - No selector training.
# - No silent fallback.

# ============================================================
# Failure object
# ============================================================

.ag_sg12_fail <- function(status,
                          message,
                          ...) {

  out <- c(
    list(
      ok=FALSE,
      status=status,
      message=message
    ),
    list(...)
  )

  class(out) <- c(
    "autogrey_sg12_failure",
    "list"
  )

  out
}


# ============================================================
# Frozen P4-C configuration grid
# ============================================================

.ag_sg12_r_grid <- c(
  0.25,
  0.50,
  1.00,
  1.50,
  2.00
)

.ag_sg12_q_grid <- c(
  0.25,
  0.50,
  0.75,
  1.25
)


.ag_sg12_token <- function(x) {

  s <- formatC(
    x,
    format="f",
    digits=2
  )

  gsub(
    ".",
    "p",
    s,
    fixed=TRUE
  )
}


ag_sg12_registered_configs <- function() {

  out <- expand.grid(
    r=.ag_sg12_r_grid,
    q=.ag_sg12_q_grid,
    KEEP.OUT.ATTRS=FALSE,
    stringsAsFactors=FALSE
  )

  out$config_id <- paste0(
    "SG12_R",
    vapply(
      out$r,
      .ag_sg12_token,
      character(1)
    ),
    "_Q",
    vapply(
      out$q,
      .ag_sg12_token,
      character(1)
    )
  )

  out <- out[
    ,
    c(
      "config_id",
      "r",
      "q"
    )
  ]

  rownames(out) <- NULL

  out
}


.ag_sg12_is_registered <- function(r,
                                    q) {

  length(r)==1L &&
  length(q)==1L &&
  is.finite(r) &&
  is.finite(q) &&
  r %in% .ag_sg12_r_grid &&
  q %in% .ag_sg12_q_grid
}


# ============================================================
# Generalized rising factorial coefficient
#
# Mao et al. Definition 2:
#
# [ alpha ]
# [   m   ]
#
# = alpha(alpha+1)...(alpha+m-1)/m!
#
# m=0 -> 1
# ============================================================

.ag_sg12_rising_binom <- function(alpha,
                                   m) {

  if (length(alpha)!=1L ||
      !is.finite(alpha)) {
    stop("alpha must be one finite number.")
  }

  if (length(m)!=1L ||
      !is.finite(m) ||
      m != as.integer(m) ||
      m < 0L) {
    stop("m must be one non-negative integer.")
  }

  m <- as.integer(m)

  if (m==0L) {
    return(1)
  }

  ans <- 1

  for (j in seq_len(m)) {

    ans <-
      ans *
      (alpha+j-1) /
      j
  }

  if (!is.finite(ans)) {
    stop(
      "Non-finite generalized rising coefficient."
    )
  }

  ans
}


.ag_sg12_weights <- function(alpha,
                             n) {

  if (length(n)!=1L ||
      !is.finite(n) ||
      n != as.integer(n) ||
      n < 1L) {
    stop("n must be a positive integer.")
  }

  n <- as.integer(n)

  vapply(
    0:(n-1L),
    function(m) {
      .ag_sg12_rising_binom(
        alpha,
        m
      )
    },
    numeric(1)
  )
}


# ============================================================
# Fractional AGO matrix A^order
# ============================================================

.ag_sg12_operator_matrix <- function(order,
                                     n) {

  if (length(order)!=1L ||
      !is.finite(order)) {
    stop("order must be finite.")
  }

  if (length(n)!=1L ||
      !is.finite(n) ||
      n != as.integer(n) ||
      n < 1L) {
    stop("n must be a positive integer.")
  }

  n <- as.integer(n)

  w <- .ag_sg12_weights(
    order,
    n
  )

  A <- matrix(
    0,
    nrow=n,
    ncol=n
  )

  for (i in seq_len(n)) {

    for (j in seq_len(i)) {

      lag <- i-j

      A[i,j] <- w[lag+1L]
    }
  }

  if (!all(is.finite(A))) {
    stop(
      "Fractional operator produced non-finite entries."
    )
  }

  A
}


.ag_sg12_apply_operator <- function(x,
                                    order) {

  x <- as.numeric(x)

  if (length(x)<1L ||
      !all(is.finite(x))) {
    stop(
      "Operator input must be finite numeric data."
    )
  }

  A <- .ag_sg12_operator_matrix(
    order=order,
    n=length(x)
  )

  out <- as.numeric(
    A %*% x
  )

  if (!all(is.finite(out))) {
    stop(
      "Fractional operator output is non-finite."
    )
  }

  out
}


# ============================================================
# Linear solver governance
# ============================================================

.ag_sg12_qr_ls <- function(X,
                           y,
                           label="SG12") {

  X <- as.matrix(X)
  y <- as.numeric(y)

  if (!all(is.finite(X)) ||
      !all(is.finite(y))) {

    return(
      .ag_sg12_fail(
        paste0(
          label,
          "_NONFINITE_LINEAR_SYSTEM"
        ),
        "Non-finite linear system."
      )
    )
  }

  nr <- nrow(X)
  nc <- ncol(X)

  if (length(y)!=nr) {

    return(
      .ag_sg12_fail(
        paste0(
          label,
          "_DIMENSION_MISMATCH"
        ),
        "X/y dimension mismatch."
      )
    )
  }

  residual_df <- nr-nc

  if (residual_df < 1L) {

    return(
      .ag_sg12_fail(
        paste0(
          label,
          "_RESIDUAL_DF_FAIL"
        ),
        paste0(
          "residual_df=",
          residual_df,
          "; required>=1"
        )
      )
    )
  }

  s <- tryCatch(
    svd(
      X,
      nu=0L,
      nv=0L
    )$d,
    error=function(e) NULL
  )

  if (is.null(s) ||
      length(s)!=nc ||
      !all(is.finite(s))) {

    return(
      .ag_sg12_fail(
        paste0(
          label,
          "_SVD_FAIL"
        ),
        "SVD diagnostics failed."
      )
    )
  }

  sigma_max <- max(s)

  tol <-
    max(dim(X)) *
    .Machine$double.eps *
    sigma_max

  rank_x <- sum(s > tol)

  if (rank_x < nc) {

    return(
      .ag_sg12_fail(
        paste0(
          label,
          "_RANK_FAIL"
        ),
        paste0(
          "rank=",
          rank_x,
          "; columns=",
          nc
        ),
        rank=rank_x,
        columns=nc,
        rank_tolerance=tol
      )
    )
  }

  sigma_min <- min(s)

  kappa2 <-
    if (sigma_min <= 0) {
      Inf
    } else {
      sigma_max/sigma_min
    }

  if (!is.finite(kappa2) ||
      kappa2 >= 1e12) {

    return(
      .ag_sg12_fail(
        paste0(
          label,
          "_KAPPA_FAIL"
        ),
        paste0(
          "kappa2=",
          format(
            kappa2,
            digits=17
          )
        ),
        kappa2=kappa2
      )
    )
  }

  qrx <- tryCatch(
    qr(
      X,
      LAPACK=TRUE
    ),
    error=function(e) NULL
  )

  if (is.null(qrx)) {

    return(
      .ag_sg12_fail(
        paste0(
          label,
          "_QR_FAIL"
        ),
        "QR decomposition failed."
      )
    )
  }

  beta <- tryCatch(
    as.numeric(
      qr.coef(
        qrx,
        y
      )
    ),
    error=function(e) NULL
  )

  if (is.null(beta) ||
      length(beta)!=nc ||
      !all(is.finite(beta))) {

    return(
      .ag_sg12_fail(
        paste0(
          label,
          "_SOLVE_FAIL"
        ),
        "QR coefficient solve failed."
      )
    )
  }

  list(
    ok=TRUE,
    status="OK",
    coefficients=beta,
    rank=rank_x,
    columns=nc,
    rows=nr,
    residual_df=residual_df,
    singular_values=s,
    rank_tolerance=tol,
    kappa2=kappa2,
    kappa_warning=(
      kappa2 >= 1e8
    )
  )
}


# ============================================================
# a+2 singularity governance
#
# Machine-scale detection only.
# This is not a fallback or alternate response branch.
# ============================================================

.ag_sg12_a_plus_2_tol <- function(a) {

  100 *
    .Machine$double.eps *
    max(
      1,
      abs(a),
      2
    )
}


.ag_sg12_a_plus_2_singular <- function(a) {

  abs(a+2) <=
    .ag_sg12_a_plus_2_tol(a)
}


# ============================================================
# Source-core fitting
# ============================================================

ag_sg12_fit_source_core <- function(x,
                                     r,
                                     q) {

  x <- as.numeric(x)

  if (length(x)<4L) {

    return(
      .ag_sg12_fail(
        "SG12_CAPACITY_FAIL",
        paste0(
          "n=",
          length(x),
          "; source-core requires n>=4"
        )
      )
    )
  }

  if (!all(is.finite(x))) {

    return(
      .ag_sg12_fail(
        "INPUT_NONFINITE_OR_MISSING",
        "SG12 input must be finite."
      )
    )
  }

  if (length(r)!=1L ||
      !is.finite(r) ||
      r <= 0) {

    return(
      .ag_sg12_fail(
        "SG12_R_DOMAIN_FAIL",
        "r must be finite and >0."
      )
    )
  }

  if (length(q)!=1L ||
      !is.finite(q) ||
      q <= 0) {

    return(
      .ag_sg12_fail(
        "SG12_Q_DOMAIN_FAIL",
        "q must be finite and >0."
      )
    )
  }

  n <- length(x)

  Ar <- tryCatch(
    .ag_sg12_operator_matrix(
      order=r,
      n=n
    ),
    error=function(e) NULL
  )

  Amq <- tryCatch(
    .ag_sg12_operator_matrix(
      order=-q,
      n=n
    ),
    error=function(e) NULL
  )

  if (is.null(Ar) ||
      is.null(Amq)) {

    return(
      .ag_sg12_fail(
        "SG12_OPERATOR_DOMAIN_FAIL",
        "Could not construct fractional operators."
      )
    )
  }

  xr <- as.numeric(
    Ar %*% x
  )

  xrq <- as.numeric(
    Amq %*% xr
  )

  if (!all(is.finite(xr)) ||
      !all(is.finite(xrq))) {

    return(
      .ag_sg12_fail(
        "SG12_OPERATOR_DOMAIN_FAIL",
        "Fractional transformed sequence is non-finite."
      )
    )
  }

  z <- 0.5 * (
    xr[1:(n-1L)] +
    xr[2:n]
  )

  B <- cbind(
    -z,
    rep(
      1,
      n-1L
    )
  )

  Y <- xrq[2:n]

  fit <- .ag_sg12_qr_ls(
    B,
    Y,
    label="SG12_FGMQ1"
  )

  if (!isTRUE(fit$ok)) {
    return(fit)
  }

  a <- fit$coefficients[1]
  b <- fit$coefficients[2]

  if (!all(is.finite(c(a,b)))) {

    return(
      .ag_sg12_fail(
        "SG12_PARAMETER_NONFINITE",
        "Estimated a/b are non-finite."
      )
    )
  }

  if (.ag_sg12_a_plus_2_singular(a)) {

    return(
      .ag_sg12_fail(
        "SG12_A_PLUS_2_SINGULAR",
        paste0(
          "a=",
          format(
            a,
            digits=17
          ),
          "; a+2 is numerically singular"
        ),
        a=a,
        b=b
      )
    )
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG12_FRAC_DYNAMIC",
    model="FGM(q,1)",
    implementation_revision="R1",
    r=as.numeric(r),
    q=as.numeric(q),
    n=n,
    parameter_count=2L,
    fit_rows=n-1L,
    a=a,
    b=b,
    training_x0=x,
    training_xr=xr,
    training_xr_minus_q=xrq,
    training_zr=z,
    design_matrix=B,
    response_vector=Y,
    diagnostics=fit
  )
}


# ============================================================
# Eq. (35) accumulated-response recursion
# ============================================================

.ag_sg12_response_r <- function(a,
                                b,
                                q,
                                x0_first,
                                total_n) {

  if (!all(is.finite(
    c(
      a,
      b,
      q,
      x0_first
    )
  ))) {
    stop(
      "Non-finite Eq.35 input."
    )
  }

  if (q <= 0) {
    stop(
      "q must be >0."
    )
  }

  if (length(total_n)!=1L ||
      !is.finite(total_n) ||
      total_n != as.integer(total_n) ||
      total_n < 1L) {
    stop(
      "total_n must be a positive integer."
    )
  }

  total_n <- as.integer(total_n)

  if (.ag_sg12_a_plus_2_singular(a)) {
    stop(
      "a+2 is numerically singular."
    )
  }

  xr_hat <- numeric(total_n)

  # Mao et al. source initial condition:
  # xhat^(r)(1) = x^(0)(1)
  xr_hat[1] <- x0_first

  if (total_n >= 2L) {

    for (k in 2:total_n) {

      ii <- seq_len(k-1L)

      conv <- sum(
        vapply(
          ii,
          function(i) {

            lag <- k-i

            .ag_sg12_rising_binom(
              -q,
              lag
            ) *
            xr_hat[i]
          },
          numeric(1)
        )
      )

      numerator <-
        2*b -
        2*conv -
        a*xr_hat[k-1L]

      denominator <- a+2

      xr_hat[k] <-
        numerator /
        denominator

      if (!is.finite(xr_hat[k])) {
        stop(
          paste0(
            "Non-finite Eq.35 response at k=",
            k
          )
        )
      }
    }
  }

  xr_hat
}


# ============================================================
# Source-core prediction
# ============================================================

ag_sg12_predict_source_core <- function(fit,
                                         h) {

  if (!is.list(fit) ||
      !isTRUE(fit$ok) ||
      !identical(
        fit$group,
        "SG12_FRAC_DYNAMIC"
      )) {

    return(
      .ag_sg12_fail(
        "SG12_INVALID_FIT_OBJECT",
        "Valid SG12 fit object required."
      )
    )
  }

  if (length(h)!=1L ||
      !is.finite(h) ||
      h != as.integer(h) ||
      h < 1L) {

    return(
      .ag_sg12_fail(
        "SG12_H_INVALID",
        "h must be a positive integer."
      )
    )
  }

  h <- as.integer(h)

  total_n <- fit$n+h

  xr_hat <- tryCatch(
    .ag_sg12_response_r(
      a=fit$a,
      b=fit$b,
      q=fit$q,
      x0_first=fit$training_x0[1],
      total_n=total_n
    ),
    error=function(e) NULL
  )

  if (is.null(xr_hat) ||
      length(xr_hat)!=total_n ||
      !all(is.finite(xr_hat))) {

    return(
      .ag_sg12_fail(
        "SG12_RESPONSE_FAIL",
        "Eq.35 response generation failed."
      )
    )
  }

  AminusR <- tryCatch(
    .ag_sg12_operator_matrix(
      order=-fit$r,
      n=total_n
    ),
    error=function(e) NULL
  )

  if (is.null(AminusR)) {

    return(
      .ag_sg12_fail(
        "SG12_RESTORATION_OPERATOR_FAIL",
        "Could not construct A^(-r)."
      )
    )
  }

  x0_hat <- as.numeric(
    AminusR %*% xr_hat
  )

  if (!all(is.finite(x0_hat))) {

    return(
      .ag_sg12_fail(
        "FORECAST_DOMAIN_INVALID",
        "Restored sequence is non-finite."
      )
    )
  }

  forecast <-
    x0_hat[
      (fit$n+1L):
      total_n
    ]

  if (length(forecast)!=h ||
      !all(is.finite(forecast))) {

    return(
      .ag_sg12_fail(
        "FORECAST_SHAPE_OR_FINITE_FAIL",
        "SG12 forecast shape/finite check failed."
      )
    )
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG12_FRAC_DYNAMIC",
    model="FGM(q,1)",
    implementation_revision="R1",
    r=fit$r,
    q=fit$q,
    h=h,
    accumulated_response=xr_hat,
    restored_response=x0_hat,
    fitted_original=x0_hat[
      seq_len(fit$n)
    ],
    forecast=forecast
  )
}


ag_sg12_forecast_source_core <- function(x,
                                          h,
                                          r,
                                          q) {

  fit <- ag_sg12_fit_source_core(
    x=x,
    r=r,
    q=q
  )

  if (!isTRUE(fit$ok)) {
    return(fit)
  }

  pred <- ag_sg12_predict_source_core(
    fit=fit,
    h=h
  )

  if (!isTRUE(pred$ok)) {
    return(pred)
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG12_FRAC_DYNAMIC",
    model="FGM(q,1)",
    implementation_revision="R1",
    fit=fit,
    prediction=pred,
    forecast=pred$forecast
  )
}


# ============================================================
# AutoGrey registered-grid wrapper
# ============================================================

ag_sg12_fit <- function(x,
                        r,
                        q) {

  if (!.ag_sg12_is_registered(
    r,
    q
  )) {

    return(
      .ag_sg12_fail(
        "SG12_CONFIG_NOT_REGISTERED",
        paste0(
          "Unregistered SG12 configuration: r=",
          r,
          ", q=",
          q
        )
      )
    )
  }

  ag_sg12_fit_source_core(
    x=x,
    r=r,
    q=q
  )
}


ag_sg12_forecast <- function(x,
                             h,
                             r,
                             q) {

  if (!.ag_sg12_is_registered(
    r,
    q
  )) {

    return(
      .ag_sg12_fail(
        "SG12_CONFIG_NOT_REGISTERED",
        paste0(
          "Unregistered SG12 configuration: r=",
          r,
          ", q=",
          q
        )
      )
    )
  }

  fit <- ag_sg12_fit(
    x=x,
    r=r,
    q=q
  )

  if (!isTRUE(fit$ok)) {
    return(fit)
  }

  pred <- ag_sg12_predict_source_core(
    fit=fit,
    h=h
  )

  if (!isTRUE(pred$ok)) {
    return(pred)
  }

  list(
    ok=TRUE,
    status="OK",
    config_id=paste0(
      "SG12_R",
      .ag_sg12_token(r),
      "_Q",
      .ag_sg12_token(q)
    ),
    group="SG12_FRAC_DYNAMIC",
    model="FGM(q,1)",
    implementation_revision="R1",
    fit=fit,
    prediction=pred,
    forecast=pred$forecast
  )
}


# ===== P11 FAST OPERATOR HELPER =====
# AutoGrey v2 P11-A2C1A
# Matrix-free fractional operator kernel R1.

.AG_FAST_THRESHOLD <- 1024L

.ag_fast_weights <- function(alpha, n) {
  if (length(alpha)!=1L || !is.finite(alpha)) stop("alpha must be finite")
  if (length(n)!=1L || !is.finite(n) || n != as.integer(n) || n < 1L)
    stop("n must be positive integer")
  n <- as.integer(n)
  w <- numeric(n)
  w[1L] <- 1
  if (n >= 2L) {
    for (m in 1:(n-1L)) {
      w[m+1L] <- w[m] * (alpha + m - 1) / m
    }
  }
  if (!all(is.finite(w))) stop("fractional weights non-finite")
  w
}

.ag_fast_next_pow2 <- function(n) {
  if (n <= 1L) return(1L)
  as.integer(2^ceiling(log(n, base=2)))
}

.ag_fast_linear_convolution_prefix <- function(x, w, nout=length(x)) {
  x <- as.numeric(x); w <- as.numeric(w)
  if (length(x)<1L || length(w)<1L || !all(is.finite(x)) || !all(is.finite(w)))
    stop("finite nonempty vectors required")
  need <- length(x)+length(w)-1L
  L <- .ag_fast_next_pow2(need)
  X <- fft(c(x, rep(0, L-length(x))))
  W <- fft(c(w, rep(0, L-length(w))))
  z <- Re(fft(X*W, inverse=TRUE))/L
  z <- z[seq_len(need)]
  z[seq_len(as.integer(nout))]
}

.ag_fast_fractional_apply_fft <- function(x, order) {
  x <- as.numeric(x)
  if (length(x)<1L || !all(is.finite(x))) stop("finite nonempty x required")
  w <- .ag_fast_weights(order, length(x))
  out <- .ag_fast_linear_convolution_prefix(x, w, length(x))
  if (!all(is.finite(out))) stop("operator output non-finite")
  out
}

.ag_fast_fractional_apply_hybrid <- function(x, order, threshold=.AG_FAST_THRESHOLD) {
  x <- as.numeric(x)
  if (length(x)<1L || !all(is.finite(x))) stop("finite nonempty x required")
  w <- .ag_fast_weights(order, length(x))
  if (length(x) <= as.integer(threshold)) {
    out <- convolve(x, rev(w), type="open")[seq_len(length(x))]
  } else {
    out <- .ag_fast_linear_convolution_prefix(x, w, length(x))
  }
  if (!all(is.finite(out))) stop("operator output non-finite")
  out
}


# ===== P11 FAST SG12 RESPONSE HELPER =====
# AutoGrey v2 P11-A2C1B
# Fast mathematically-equivalent SG12 Eq.35 response solver R2.
# R2 changes only evidence serialization from the failed R1 harness.
# Requires canonical SG12 source and the P11-A2C1A fast operator helper.

.AG_SG12_FAST_RESPONSE_THRESHOLD <- 1024L

.ag_fast_poly_inverse <- function(d, n) {
  d <- as.numeric(d)
  n <- as.integer(n)

  if (n < 1L || length(d) < n || !all(is.finite(d[seq_len(n)])))
    stop("invalid polynomial inverse input")

  if (d[1L] == 0 || !is.finite(d[1L]))
    stop("zero/nonfinite leading coefficient")

  g <- c(1 / d[1L])
  m <- 1L

  while (m < n) {
    m2 <- min(2L * m, n)

    t <- .ag_fast_linear_convolution_prefix(
      d[seq_len(m2)],
      g,
      m2
    )

    h <- -t
    h[1L] <- h[1L] + 2

    g <- .ag_fast_linear_convolution_prefix(
      g,
      h,
      m2
    )

    if (length(g) < m2)
      g <- c(g, rep(0, m2 - length(g)))

    g <- g[seq_len(m2)]
    m <- m2
  }

  if (!all(is.finite(g[seq_len(n)])))
    stop("non-finite formal power-series inverse")

  g[seq_len(n)]
}

.ag_fast_sg12_response_fps <- function(a,
                                       b,
                                       q,
                                       x0_first,
                                       total_n) {

  if (!all(is.finite(c(a,b,q,x0_first))))
    stop("Non-finite Eq.35 input.")

  if (q <= 0)
    stop("q must be >0.")

  if (length(total_n)!=1L ||
      !is.finite(total_n) ||
      total_n != as.integer(total_n) ||
      total_n < 1L)
    stop("total_n must be a positive integer.")

  total_n <- as.integer(total_n)

  if (.ag_sg12_a_plus_2_singular(a))
    stop("a+2 is numerically singular.")

  if (total_n == 1L)
    return(as.numeric(x0_first))

  w <- .ag_fast_weights(-q, total_n)

  d <- numeric(total_n)
  d[1L] <- a + 2
  d[2L] <- a + 2*w[2L]
  if (total_n >= 3L)
    d[3L:total_n] <- 2*w[3L:total_n]

  rhs <- rep(2*b, total_n)
  rhs[1L] <- (a+2)*x0_first

  inv_d <- .ag_fast_poly_inverse(d, total_n)

  y <- .ag_fast_linear_convolution_prefix(
    inv_d,
    rhs,
    total_n
  )

  y[1L] <- x0_first

  if (length(y)!=total_n || !all(is.finite(y)))
    stop("Non-finite Eq.35 fast response.")

  as.numeric(y)
}

.ag_fast_sg12_response_hybrid <- function(a,
                                          b,
                                          q,
                                          x0_first,
                                          total_n,
                                          threshold=.AG_SG12_FAST_RESPONSE_THRESHOLD) {
  total_n <- as.integer(total_n)

  if (total_n <= as.integer(threshold)) {
    return(.ag_sg12_response_r(
      a=a,
      b=b,
      q=q,
      x0_first=x0_first,
      total_n=total_n
    ))
  }

  .ag_fast_sg12_response_fps(
    a=a,
    b=b,
    q=q,
    x0_first=x0_first,
    total_n=total_n
  )
}



# ============================================================
# P11-A2C2 QUALIFIED LONG-SERIES IMPLEMENTATION CANDIDATE
# Short path <=1024 is exactly canonical.
# Long path uses previously qualified matrix-free kernels.
# ============================================================

.AG_P11_FAST_THRESHOLD <- 1024L

.ag_sg12_fit_source_core_canonical <- ag_sg12_fit_source_core
.ag_sg12_predict_source_core_canonical <- ag_sg12_predict_source_core
.ag_sg12_apply_operator_canonical <- .ag_sg12_apply_operator
.ag_sg12_response_r_canonical <- .ag_sg12_response_r

.ag_sg12_apply_operator <- function(x, order) {
  x <- as.numeric(x)
  if (length(x) <= .AG_P11_FAST_THRESHOLD) {
    return(.ag_sg12_apply_operator_canonical(x, order))
  }
  .ag_fast_fractional_apply_fft(x, order)
}

.ag_sg12_response_r <- function(a,b,q,x0_first,total_n) {
  total_n <- as.integer(total_n)
  if (total_n <= .AG_P11_FAST_THRESHOLD) {
    return(.ag_sg12_response_r_canonical(
      a=a,b=b,q=q,x0_first=x0_first,total_n=total_n
    ))
  }
  .ag_fast_sg12_response_fps(
    a=a,b=b,q=q,x0_first=x0_first,total_n=total_n
  )
}

ag_sg12_fit_source_core <- function(x,r,q) {
  x <- as.numeric(x)

  if (length(x) <= .AG_P11_FAST_THRESHOLD) {
    return(.ag_sg12_fit_source_core_canonical(x=x,r=r,q=q))
  }

  if (length(x)<4L) {
    return(.ag_sg12_fail(
      "SG12_CAPACITY_FAIL",
      paste0("n=",length(x),"; source-core requires n>=4")
    ))
  }

  if (!all(is.finite(x))) {
    return(.ag_sg12_fail(
      "INPUT_NONFINITE_OR_MISSING",
      "SG12 input must be finite."
    ))
  }

  if (length(r)!=1L || !is.finite(r) || r <= 0) {
    return(.ag_sg12_fail(
      "SG12_R_DOMAIN_FAIL",
      "r must be finite and >0."
    ))
  }

  if (length(q)!=1L || !is.finite(q) || q <= 0) {
    return(.ag_sg12_fail(
      "SG12_Q_DOMAIN_FAIL",
      "q must be finite and >0."
    ))
  }

  n <- length(x)

  xr <- tryCatch(
    .ag_fast_fractional_apply_fft(x,r),
    error=function(e) NULL
  )

  xrq <- tryCatch(
    .ag_fast_fractional_apply_fft(xr,-q),
    error=function(e) NULL
  )

  if (is.null(xr) || is.null(xrq) ||
      !all(is.finite(xr)) || !all(is.finite(xrq))) {
    return(.ag_sg12_fail(
      "SG12_OPERATOR_DOMAIN_FAIL",
      "Fractional transformed sequence is non-finite."
    ))
  }

  z <- 0.5 * (xr[1:(n-1L)] + xr[2:n])

  B <- cbind(-z, rep(1,n-1L))
  Y <- xrq[2:n]

  fit <- .ag_sg12_qr_ls(
    B,Y,label="SG12_FGMQ1"
  )

  if (!isTRUE(fit$ok))
    return(fit)

  a <- fit$coefficients[1]
  b <- fit$coefficients[2]

  if (!all(is.finite(c(a,b)))) {
    return(.ag_sg12_fail(
      "SG12_PARAMETER_NONFINITE",
      "Estimated a/b are non-finite."
    ))
  }

  if (.ag_sg12_a_plus_2_singular(a)) {
    return(.ag_sg12_fail(
      "SG12_A_PLUS_2_SINGULAR",
      paste0(
        "a=",format(a,digits=17),
        "; a+2 is numerically singular"
      ),
      a=a,b=b
    ))
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG12_FRAC_DYNAMIC",
    model="FGM(q,1)",
    implementation_revision="R1",
    r=as.numeric(r),
    q=as.numeric(q),
    n=n,
    parameter_count=2L,
    fit_rows=n-1L,
    a=a,
    b=b,
    training_x0=x,
    training_xr=xr,
    training_xr_minus_q=xrq,
    training_zr=z,
    design_matrix=B,
    response_vector=Y,
    diagnostics=fit
  )
}

ag_sg12_predict_source_core <- function(fit,h) {

  if (!is.list(fit) ||
      !isTRUE(fit$ok) ||
      !identical(fit$group,"SG12_FRAC_DYNAMIC")) {
    return(.ag_sg12_fail(
      "SG12_INVALID_FIT_OBJECT",
      "Valid SG12 fit object required."
    ))
  }

  if (length(h)!=1L ||
      !is.finite(h) ||
      h != as.integer(h) ||
      h < 1L) {
    return(.ag_sg12_fail(
      "SG12_H_INVALID",
      "h must be a positive integer."
    ))
  }

  h <- as.integer(h)
  total_n <- fit$n+h

  if (total_n <= .AG_P11_FAST_THRESHOLD) {
    return(.ag_sg12_predict_source_core_canonical(
      fit=fit,h=h
    ))
  }

  xr_hat <- tryCatch(
    .ag_fast_sg12_response_fps(
      a=fit$a,
      b=fit$b,
      q=fit$q,
      x0_first=fit$training_x0[1],
      total_n=total_n
    ),
    error=function(e) NULL
  )

  if (is.null(xr_hat) ||
      length(xr_hat)!=total_n ||
      !all(is.finite(xr_hat))) {
    return(.ag_sg12_fail(
      "SG12_RESPONSE_FAIL",
      "Eq.35 response generation failed."
    ))
  }

  x0_hat <- tryCatch(
    .ag_fast_fractional_apply_fft(
      xr_hat,-fit$r
    ),
    error=function(e) NULL
  )

  if (is.null(x0_hat) ||
      length(x0_hat)!=total_n ||
      !all(is.finite(x0_hat))) {
    return(.ag_sg12_fail(
      "FORECAST_DOMAIN_INVALID",
      "Restored sequence is non-finite."
    ))
  }

  forecast <- x0_hat[(fit$n+1L):total_n]

  if (length(forecast)!=h ||
      !all(is.finite(forecast))) {
    return(.ag_sg12_fail(
      "FORECAST_SHAPE_OR_FINITE_FAIL",
      "SG12 forecast shape/finite check failed."
    ))
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG12_FRAC_DYNAMIC",
    model="FGM(q,1)",
    implementation_revision="R1",
    r=fit$r,
    q=fit$q,
    h=h,
    accumulated_response=xr_hat,
    restored_response=x0_hat,
    fitted_original=x0_hat[seq_len(fit$n)],
    forecast=forecast
  )
}

