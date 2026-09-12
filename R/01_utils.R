# AutoGrey R reproduction — shared numerical primitives for Step 7B1.
# Scientific contract source: AG_ENGINE_4FB_1R1.

AG_NEAR_ATOL <- 1e-10
AG_NEAR_RTOL <- 1e-6
AG_COND_FAIL <- 1e12

ag_engine_failure <- function(code, detail = "") {
  msg <- if (nzchar(detail)) paste0(code, ": ", detail) else code
  structure(
    list(message = msg, call = NULL, code = as.character(code), detail = as.character(detail)),
    class = c("autogrey_engine_failure", "error", "condition")
  )
}

ag_stop <- function(code, detail = "") {
  stop(ag_engine_failure(code, detail))
}

ag_as_series <- function(x, min_n = 1L) {
  if (!is.atomic(x) || !is.null(dim(x))) ag_stop("SERIES_NOT_1D")
  x <- as.numeric(x)
  if (length(x) < as.integer(min_n)) {
    ag_stop("SERIES_TOO_SHORT", sprintf("n=%d < %d", length(x), as.integer(min_n)))
  }
  if (any(!is.finite(x))) ag_stop("SERIES_NONFINITE")
  x
}

ag_near <- function(x, y = 0, atol = AG_NEAR_ATOL, rtol = AG_NEAR_RTOL) {
  abs(as.numeric(x) - as.numeric(y)) <=
    as.numeric(atol) + as.numeric(rtol) * max(1, abs(as.numeric(x)), abs(as.numeric(y)))
}

ag_cond <- function(B) {
  B <- as.matrix(B)
  s <- svd(B, nu = 0L, nv = 0L)$d
  if (length(s) == 0L || tail(s, 1L) <= .Machine$double.eps * max(s[1L], 1)) {
    return(Inf)
  }
  as.numeric(s[1L] / tail(s, 1L))
}

# SVD least-squares port of numpy.linalg.lstsq(..., rcond=None).
# We deliberately avoid solve(crossprod(B), crossprod(B,Y)).
ag_lstsq_checked <- function(B, Y, min_resid_df = 0L,
                              cond_fail = AG_COND_FAIL,
                              failure_prefix = "OLS") {
  B <- as.matrix(B)
  storage.mode(B) <- "double"
  Y <- as.numeric(Y)
  if (length(dim(B)) != 2L || nrow(B) != length(Y)) {
    ag_stop(paste0(failure_prefix, "_SHAPE"))
  }
  if (any(!is.finite(B)) || any(!is.finite(Y))) {
    ag_stop(paste0(failure_prefix, "_NONFINITE"))
  }
  rows <- nrow(B)
  cols <- ncol(B)
  if ((rows - cols) < as.integer(min_resid_df)) {
    ag_stop(
      paste0(failure_prefix, "_RESID_DF"),
      sprintf("rows=%d, params=%d, required_df=%d", rows, cols, as.integer(min_resid_df))
    )
  }

  decomp <- tryCatch(
    La.svd(B, nu = cols, nv = cols),
    error = function(e) ag_stop(paste0(failure_prefix, "_LSTSQ_FAIL"), conditionMessage(e))
  )
  s <- as.numeric(decomp$d)
  if (length(s) < cols) ag_stop(paste0(failure_prefix, "_RANK"), "insufficient singular values")
  smax <- if (length(s)) s[1L] else 0
  cutoff <- .Machine$double.eps * max(rows, cols) * smax
  rank <- sum(s > cutoff)
  if (rank < cols) {
    ag_stop(paste0(failure_prefix, "_RANK"), sprintf("rank=%d < %d", rank, cols))
  }

  kappa <- ag_cond(B)
  if (!is.finite(kappa) || kappa >= as.numeric(cond_fail)) {
    ag_stop(paste0(failure_prefix, "_CONDITION"), sprintf("kappa=%.6g", kappa))
  }

  # La.svd returns u and vt. With full column rank, this is V D^-1 U'Y.
  U <- decomp$u[, seq_len(cols), drop = FALSE]
  V <- t(decomp$vt[seq_len(cols), , drop = FALSE])
  theta <- as.numeric(V %*% (as.numeric(crossprod(U, Y)) / s[seq_len(cols)]))
  if (any(!is.finite(theta))) ag_stop(paste0(failure_prefix, "_PARAM_NONFINITE"))

  list(
    theta = theta,
    diagnostics = list(
      rank = as.integer(rank),
      condition = as.numeric(kappa),
      rows = as.integer(rows),
      params = as.integer(cols),
      resid_df = as.integer(rows - cols)
    )
  )
}

ag_inner_origins <- function(n, h) {
  n <- as.integer(n); h <- as.integer(h)
  if (h < 1L) ag_stop("H_INVALID")
  origins <- c(n - h - 2L, n - h - 1L, n - h)
  if (origins[1L] < 1L) ag_stop("INNER_ORIGINS_UNAVAILABLE", sprintf("n=%d,h=%d", n, h))
  as.integer(origins)
}
