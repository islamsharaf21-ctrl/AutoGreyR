# AutoGrey V2-P4E3B
# SG13 Fractional Nonlinear Grey Bernoulli Model
# FANGBM(1,1) implementation R1
#
# Frozen registered design:
#   r     = {0.25,0.50,0.75,1.25,1.50}
#   gamma = {-1.00,-0.50,0.50,2.00}
#
# Important governance:
# - r=1 is not registered.
# - gamma=0 is not registered.
# - gamma=1 is structurally excluded.
# - no optimizer is imported.
# - no arbitrary a-near-zero tolerance.
# - stable expm1 analytic continuation is used.
# - no clipping, flooring, shifting, abs repair, or fallback.
# - REALBENCH3 is not accessed.

# ============================================================
# Generic failure object
# ============================================================

.ag_sg13_fail <- function(status,
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
    "autogrey_sg13_failure",
    "list"
  )

  out
}


# ============================================================
# Frozen P4-C registry
# ============================================================

.ag_sg13_r_grid <- c(
  0.25,
  0.50,
  0.75,
  1.25,
  1.50
)

.ag_sg13_gamma_grid <- c(
  -1.00,
  -0.50,
   0.50,
   2.00
)


.ag_sg13_token <- function(x) {

  if (length(x)!=1L ||
      !is.finite(x)) {
    stop("Token value must be one finite number.")
  }

  prefix <-
    if (x < 0) "m" else ""

  core <- formatC(
    abs(x),
    format="f",
    digits=2
  )

  core <- gsub(
    ".",
    "p",
    core,
    fixed=TRUE
  )

  paste0(
    prefix,
    core
  )
}


ag_sg13_registered_configs <- function() {

  out <- expand.grid(
    r=.ag_sg13_r_grid,
    gamma=.ag_sg13_gamma_grid,
    KEEP.OUT.ATTRS=FALSE,
    stringsAsFactors=FALSE
  )

  out$config_id <- paste0(
    "SG13_R",
    vapply(
      out$r,
      .ag_sg13_token,
      character(1)
    ),
    "_G",
    vapply(
      out$gamma,
      .ag_sg13_token,
      character(1)
    )
  )

  out <- out[
    ,
    c(
      "config_id",
      "r",
      "gamma"
    )
  ]

  rownames(out) <- NULL

  out
}


.ag_sg13_is_registered <- function(r,
                                    gamma) {

  length(r)==1L &&
  length(gamma)==1L &&
  is.finite(r) &&
  is.finite(gamma) &&
  r %in% .ag_sg13_r_grid &&
  gamma %in% .ag_sg13_gamma_grid
}


# ============================================================
# Fractional accumulation operator
#
# Rising generalized-binomial coefficient:
#
# alpha(alpha+1)...(alpha+m-1)/m!
#
# m=0 -> 1
# ============================================================

.ag_sg13_rising_binom <- function(alpha,
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
      "Non-finite fractional coefficient."
    )
  }

  ans
}


.ag_sg13_operator_matrix <- function(order,
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

  w <- vapply(
    0:(n-1L),
    function(m) {
      .ag_sg13_rising_binom(
        order,
        m
      )
    },
    numeric(1)
  )

  A <- matrix(
    0,
    nrow=n,
    ncol=n
  )

  for (i in seq_len(n)) {

    for (j in seq_len(i)) {

      lag <- i-j

      A[i,j] <-
        w[lag+1L]
    }
  }

  if (!all(is.finite(A))) {
    stop(
      "Fractional operator produced non-finite entries."
    )
  }

  A
}


.ag_sg13_apply_operator <- function(x,
                                    order) {

  x <- as.numeric(x)

  if (length(x)<1L ||
      !all(is.finite(x))) {
    stop(
      "Operator input must be finite numeric data."
    )
  }

  as.numeric(
    .ag_sg13_operator_matrix(
      order,
      length(x)
    ) %*% x
  )
}


# ============================================================
# Frozen numerical linear-system governance
# ============================================================

.ag_sg13_qr_ls <- function(X,
                           y,
                           label="SG13") {

  X <- as.matrix(X)
  y <- as.numeric(y)

  if (!all(is.finite(X)) ||
      !all(is.finite(y))) {

    return(
      .ag_sg13_fail(
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
      .ag_sg13_fail(
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
      .ag_sg13_fail(
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
      .ag_sg13_fail(
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

  rank_x <- sum(
    s > tol
  )

  if (rank_x < nc) {

    return(
      .ag_sg13_fail(
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
      .ag_sg13_fail(
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
      .ag_sg13_fail(
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
      .ag_sg13_fail(
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
# Stable Bernoulli response
#
# p   = 1-gamma
# tau = k-1
# z   = -a*p*tau
#
# Source expression:
#
# [(x1^p-b/a) exp(z)+b/a]^(1/p)
#
# Algebraically stable continuation:
#
# [x1^p exp(z)
#  + b*p*tau*phi1(z)]^(1/p)
#
# where:
# phi1(z)=expm1(z)/z
# phi1(0)=1
#
# This gives the exact analytic a=0 limit with no
# arbitrary near-zero threshold.
# ============================================================

.ag_sg13_phi1 <- function(z) {

  if (!is.finite(z)) {
    stop(
      "phi1 requires finite z."
    )
  }

  if (z==0) {
    return(1)
  }

  ans <- expm1(z)/z

  if (!is.finite(ans)) {
    stop(
      "phi1 produced non-finite result."
    )
  }

  ans
}


.ag_sg13_response_r <- function(a,
                                b,
                                gamma,
                                x0_first,
                                total_n) {

  if (!all(is.finite(
    c(
      a,
      b,
      gamma,
      x0_first
    )
  ))) {
    stop(
      "Non-finite Bernoulli-response input."
    )
  }

  if (x0_first <= 0) {
    stop(
      "Initial value must be strictly positive."
    )
  }

  if (gamma==1) {
    stop(
      "gamma=1 is structurally excluded."
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

  p <- 1-gamma

  if (!is.finite(p) ||
      p==0) {
    stop(
      "Invalid Bernoulli power p=1-gamma."
    )
  }

  x1p <- x0_first^p

  if (!is.finite(x1p) ||
      x1p <= 0) {
    stop(
      "Initial transformed power is invalid."
    )
  }

  out <- numeric(total_n)

  # Preserve exact source initial condition.
  out[1] <- x0_first

  if (total_n >= 2L) {

    for (k in 2:total_n) {

      tau <- k-1

      z <-
        -a *
        p *
        tau

      ez <- exp(z)

      if (!is.finite(ez)) {
        stop(
          paste0(
            "Non-finite exponential response at k=",
            k
          )
        )
      }

      phi <-
        .ag_sg13_phi1(z)

      base <-
        x1p*ez +
        b*p*tau*phi

      if (!is.finite(base) ||
          base <= 0) {
        stop(
          paste0(
            "Bernoulli response domain failure at k=",
            k,
            "; transformed base=",
            format(
              base,
              digits=17
            )
          )
        )
      }

      value <-
        base^(1/p)

      if (!is.finite(value) ||
          !is.numeric(value)) {
        stop(
          paste0(
            "Non-finite Bernoulli response at k=",
            k
          )
        )
      }

      out[k] <- value
    }
  }

  out
}


# ============================================================
# Source-core fit
# ============================================================

ag_sg13_fit_source_core <- function(x,
                                     r,
                                     gamma) {

  x <- as.numeric(x)

  if (length(x)<4L) {

    return(
      .ag_sg13_fail(
        "SG13_CAPACITY_FAIL",
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
      .ag_sg13_fail(
        "INPUT_NONFINITE_OR_MISSING",
        "Input must be finite."
      )
    )
  }

  if (any(x < 0) ||
      x[1] <= 0) {

    return(
      .ag_sg13_fail(
        "SG13_SOURCE_DOMAIN_FAIL",
        paste0(
          "Training sequence must be nonnegative ",
          "with strictly positive first value."
        )
      )
    )
  }

  if (length(r)!=1L ||
      !is.finite(r) ||
      r <= 0) {

    return(
      .ag_sg13_fail(
        "SG13_R_DOMAIN_FAIL",
        "r must be finite and >0."
      )
    )
  }

  if (length(gamma)!=1L ||
      !is.finite(gamma)) {

    return(
      .ag_sg13_fail(
        "SG13_GAMMA_DOMAIN_FAIL",
        "gamma must be finite."
      )
    )
  }

  if (gamma==1) {

    return(
      .ag_sg13_fail(
        "SG13_GAMMA1_NONIDENTIFIABLE",
        paste0(
          "gamma=1 makes the design columns ",
          "-z and z linearly dependent."
        )
      )
    )
  }

  n <- length(x)

  Ar <- tryCatch(
    .ag_sg13_operator_matrix(
      order=r,
      n=n
    ),
    error=function(e) NULL
  )

  if (is.null(Ar)) {

    return(
      .ag_sg13_fail(
        "SG13_OPERATOR_DOMAIN_FAIL",
        "Could not construct fractional accumulation operator."
      )
    )
  }

  xr <- as.numeric(
    Ar %*% x
  )

  if (!all(is.finite(xr))) {

    return(
      .ag_sg13_fail(
        "SG13_OPERATOR_DOMAIN_FAIL",
        "Fractional accumulated sequence is non-finite."
      )
    )
  }

  z <- 0.5 * (
    xr[1:(n-1L)] +
    xr[2:n]
  )

  if (!all(is.finite(z)) ||
      any(z <= 0)) {

    return(
      .ag_sg13_fail(
        "SG13_BACKGROUND_DOMAIN_FAIL",
        paste0(
          "All accumulated background values ",
          "must be finite and strictly positive."
        )
      )
    )
  }

  zgamma <- tryCatch(
    z^gamma,
    warning=function(w) rep(NaN,length(z)),
    error=function(e) rep(NaN,length(z))
  )

  if (!all(is.finite(zgamma))) {

    return(
      .ag_sg13_fail(
        "SG13_BERNOULLI_DESIGN_DOMAIN_FAIL",
        "z^gamma is not real finite."
      )
    )
  }

  Y <- diff(xr)

  B <- cbind(
    -z,
    zgamma
  )

  fit <- .ag_sg13_qr_ls(
    B,
    Y,
    label="SG13_FANGBM"
  )

  if (!isTRUE(fit$ok)) {
    return(fit)
  }

  a <- fit$coefficients[1]
  b <- fit$coefficients[2]

  if (!all(is.finite(c(a,b)))) {

    return(
      .ag_sg13_fail(
        "SG13_PARAMETER_NONFINITE",
        "Estimated a/b are non-finite."
      )
    )
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG13_FRAC_BERNOULLI",
    model="FANGBM(1,1)",
    implementation_revision="R1",
    r=as.numeric(r),
    gamma=as.numeric(gamma),
    n=n,
    parameter_count=2L,
    fit_rows=n-1L,
    a=a,
    b=b,
    training_x0=x,
    training_xr=xr,
    training_zr=z,
    training_zr_gamma=zgamma,
    design_matrix=B,
    response_vector=Y,
    diagnostics=fit
  )
}


# ============================================================
# Source-core prediction
# ============================================================

ag_sg13_predict_source_core <- function(fit,
                                         h) {

  if (!is.list(fit) ||
      !isTRUE(fit$ok) ||
      !identical(
        fit$group,
        "SG13_FRAC_BERNOULLI"
      )) {

    return(
      .ag_sg13_fail(
        "SG13_INVALID_FIT_OBJECT",
        "Valid SG13 fit object required."
      )
    )
  }

  if (length(h)!=1L ||
      !is.finite(h) ||
      h != as.integer(h) ||
      h < 1L) {

    return(
      .ag_sg13_fail(
        "SG13_H_INVALID",
        "h must be a positive integer."
      )
    )
  }

  h <- as.integer(h)

  total_n <- fit$n+h

  xr_hat <- tryCatch(
    .ag_sg13_response_r(
      a=fit$a,
      b=fit$b,
      gamma=fit$gamma,
      x0_first=fit$training_x0[1],
      total_n=total_n
    ),
    error=function(e) NULL
  )

  if (is.null(xr_hat) ||
      length(xr_hat)!=total_n ||
      !all(is.finite(xr_hat))) {

    return(
      .ag_sg13_fail(
        "SG13_RESPONSE_DOMAIN_FAIL",
        "Bernoulli time response is invalid."
      )
    )
  }

  AminusR <- tryCatch(
    .ag_sg13_operator_matrix(
      order=-fit$r,
      n=total_n
    ),
    error=function(e) NULL
  )

  if (is.null(AminusR)) {

    return(
      .ag_sg13_fail(
        "SG13_RESTORATION_OPERATOR_FAIL",
        "Could not construct inverse fractional operator."
      )
    )
  }

  x0_hat <- as.numeric(
    AminusR %*% xr_hat
  )

  if (!all(is.finite(x0_hat))) {

    return(
      .ag_sg13_fail(
        "FORECAST_DOMAIN_INVALID",
        "Restored response is non-finite."
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
      .ag_sg13_fail(
        "FORECAST_SHAPE_OR_FINITE_FAIL",
        "Forecast shape/finite check failed."
      )
    )
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG13_FRAC_BERNOULLI",
    model="FANGBM(1,1)",
    implementation_revision="R1",
    r=fit$r,
    gamma=fit$gamma,
    h=h,
    accumulated_response=xr_hat,
    restored_response=x0_hat,
    fitted_original=x0_hat[
      seq_len(fit$n)
    ],
    forecast=forecast
  )
}


ag_sg13_forecast_source_core <- function(x,
                                          h,
                                          r,
                                          gamma) {

  fit <- ag_sg13_fit_source_core(
    x=x,
    r=r,
    gamma=gamma
  )

  if (!isTRUE(fit$ok)) {
    return(fit)
  }

  pred <- ag_sg13_predict_source_core(
    fit=fit,
    h=h
  )

  if (!isTRUE(pred$ok)) {
    return(pred)
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG13_FRAC_BERNOULLI",
    model="FANGBM(1,1)",
    implementation_revision="R1",
    fit=fit,
    prediction=pred,
    forecast=pred$forecast
  )
}


# ============================================================
# AutoGrey registered-grid wrappers
# ============================================================

ag_sg13_fit <- function(x,
                        r,
                        gamma) {

  if (!.ag_sg13_is_registered(
    r,
    gamma
  )) {

    return(
      .ag_sg13_fail(
        "SG13_CONFIG_NOT_REGISTERED",
        paste0(
          "Unregistered SG13 configuration: r=",
          r,
          ", gamma=",
          gamma
        )
      )
    )
  }

  ag_sg13_fit_source_core(
    x=x,
    r=r,
    gamma=gamma
  )
}


ag_sg13_forecast <- function(x,
                             h,
                             r,
                             gamma) {

  if (!.ag_sg13_is_registered(
    r,
    gamma
  )) {

    return(
      .ag_sg13_fail(
        "SG13_CONFIG_NOT_REGISTERED",
        paste0(
          "Unregistered SG13 configuration: r=",
          r,
          ", gamma=",
          gamma
        )
      )
    )
  }

  fit <- ag_sg13_fit(
    x=x,
    r=r,
    gamma=gamma
  )

  if (!isTRUE(fit$ok)) {
    return(fit)
  }

  pred <- ag_sg13_predict_source_core(
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
      "SG13_R",
      .ag_sg13_token(r),
      "_G",
      .ag_sg13_token(gamma)
    ),
    group="SG13_FRAC_BERNOULLI",
    model="FANGBM(1,1)",
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



# ============================================================
# P11-A2C2 QUALIFIED LONG-SERIES IMPLEMENTATION CANDIDATE
# Short path <=1024 is exactly canonical.
# Long path uses previously qualified matrix-free kernels.
# ============================================================

.AG_P11_FAST_THRESHOLD <- 1024L

.ag_sg13_fit_source_core_canonical <- ag_sg13_fit_source_core
.ag_sg13_predict_source_core_canonical <- ag_sg13_predict_source_core
.ag_sg13_apply_operator_canonical <- .ag_sg13_apply_operator

.ag_sg13_apply_operator <- function(x,order) {
  x <- as.numeric(x)
  if (length(x) <= .AG_P11_FAST_THRESHOLD) {
    return(.ag_sg13_apply_operator_canonical(x,order))
  }
  .ag_fast_fractional_apply_fft(x,order)
}

ag_sg13_fit_source_core <- function(x,r,gamma) {
  x <- as.numeric(x)

  if (length(x) <= .AG_P11_FAST_THRESHOLD) {
    return(.ag_sg13_fit_source_core_canonical(
      x=x,r=r,gamma=gamma
    ))
  }

  if (length(x)<4L) {
    return(.ag_sg13_fail(
      "SG13_CAPACITY_FAIL",
      paste0("n=",length(x),"; source-core requires n>=4")
    ))
  }

  if (!all(is.finite(x))) {
    return(.ag_sg13_fail(
      "INPUT_NONFINITE_OR_MISSING",
      "Input must be finite."
    ))
  }

  if (any(x < 0) || x[1] <= 0) {
    return(.ag_sg13_fail(
      "SG13_SOURCE_DOMAIN_FAIL",
      paste0(
        "Training sequence must be nonnegative ",
        "with strictly positive first value."
      )
    ))
  }

  if (length(r)!=1L || !is.finite(r) || r <= 0) {
    return(.ag_sg13_fail(
      "SG13_R_DOMAIN_FAIL",
      "r must be finite and >0."
    ))
  }

  if (length(gamma)!=1L || !is.finite(gamma)) {
    return(.ag_sg13_fail(
      "SG13_GAMMA_DOMAIN_FAIL",
      "gamma must be finite."
    ))
  }

  if (gamma==1) {
    return(.ag_sg13_fail(
      "SG13_GAMMA1_NONIDENTIFIABLE",
      paste0(
        "gamma=1 makes the design columns ",
        "-z and z linearly dependent."
      )
    ))
  }

  n <- length(x)

  xr <- tryCatch(
    .ag_fast_fractional_apply_fft(x,r),
    error=function(e) NULL
  )

  if (is.null(xr) || !all(is.finite(xr))) {
    return(.ag_sg13_fail(
      "SG13_OPERATOR_DOMAIN_FAIL",
      "Fractional accumulated sequence is non-finite."
    ))
  }

  z <- 0.5 * (xr[1:(n-1L)] + xr[2:n])

  if (!all(is.finite(z)) || any(z <= 0)) {
    return(.ag_sg13_fail(
      "SG13_BACKGROUND_DOMAIN_FAIL",
      paste0(
        "All accumulated background values ",
        "must be finite and strictly positive."
      )
    ))
  }

  zgamma <- tryCatch(
    z^gamma,
    warning=function(w) rep(NaN,length(z)),
    error=function(e) rep(NaN,length(z))
  )

  if (!all(is.finite(zgamma))) {
    return(.ag_sg13_fail(
      "SG13_BERNOULLI_DESIGN_DOMAIN_FAIL",
      "z^gamma is not real finite."
    ))
  }

  Y <- diff(xr)
  B <- cbind(-z,zgamma)

  fit <- .ag_sg13_qr_ls(
    B,Y,label="SG13_FANGBM"
  )

  if (!isTRUE(fit$ok))
    return(fit)

  a <- fit$coefficients[1]
  b <- fit$coefficients[2]

  if (!all(is.finite(c(a,b)))) {
    return(.ag_sg13_fail(
      "SG13_PARAMETER_NONFINITE",
      "Estimated a/b are non-finite."
    ))
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG13_FRAC_BERNOULLI",
    model="FANGBM(1,1)",
    implementation_revision="R1",
    r=as.numeric(r),
    gamma=as.numeric(gamma),
    n=n,
    parameter_count=2L,
    fit_rows=n-1L,
    a=a,
    b=b,
    training_x0=x,
    training_xr=xr,
    training_zr=z,
    training_zr_gamma=zgamma,
    design_matrix=B,
    response_vector=Y,
    diagnostics=fit
  )
}

ag_sg13_predict_source_core <- function(fit,h) {

  if (!is.list(fit) ||
      !isTRUE(fit$ok) ||
      !identical(fit$group,"SG13_FRAC_BERNOULLI")) {
    return(.ag_sg13_fail(
      "SG13_INVALID_FIT_OBJECT",
      "Valid SG13 fit object required."
    ))
  }

  if (length(h)!=1L ||
      !is.finite(h) ||
      h != as.integer(h) ||
      h < 1L) {
    return(.ag_sg13_fail(
      "SG13_H_INVALID",
      "h must be a positive integer."
    ))
  }

  h <- as.integer(h)
  total_n <- fit$n+h

  if (total_n <= .AG_P11_FAST_THRESHOLD) {
    return(.ag_sg13_predict_source_core_canonical(
      fit=fit,h=h
    ))
  }

  xr_hat <- tryCatch(
    .ag_sg13_response_r(
      a=fit$a,
      b=fit$b,
      gamma=fit$gamma,
      x0_first=fit$training_x0[1],
      total_n=total_n
    ),
    error=function(e) NULL
  )

  if (is.null(xr_hat) ||
      length(xr_hat)!=total_n ||
      !all(is.finite(xr_hat))) {
    return(.ag_sg13_fail(
      "SG13_RESPONSE_DOMAIN_FAIL",
      "Bernoulli time response is invalid."
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
    return(.ag_sg13_fail(
      "FORECAST_DOMAIN_INVALID",
      "Restored response is non-finite."
    ))
  }

  forecast <- x0_hat[(fit$n+1L):total_n]

  if (length(forecast)!=h ||
      !all(is.finite(forecast))) {
    return(.ag_sg13_fail(
      "FORECAST_SHAPE_OR_FINITE_FAIL",
      "Forecast shape/finite check failed."
    ))
  }

  list(
    ok=TRUE,
    status="OK",
    group="SG13_FRAC_BERNOULLI",
    model="FANGBM(1,1)",
    implementation_revision="R1",
    r=fit$r,
    gamma=fit$gamma,
    h=h,
    accumulated_response=xr_hat,
    restored_response=x0_hat,
    fitted_original=x0_hat[seq_len(fit$n)],
    forecast=forecast
  )
}

