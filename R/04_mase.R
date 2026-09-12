# AutoGrey R reproduction — frozen prospective MASE primitives for Step 7B1.

ag_mase_scale <- function(D, M = NULL) {
  x <- ag_as_series(D)
  lag <- if (is.null(M)) 1L else as.integer(M)
  if (lag < 1L || length(x) <= lag) {
    ag_stop("LOSS_SCALE_UNDEFINED", sprintf("n=%d,lag=%d", length(x), lag))
  }
  diffs <- abs(x[(lag + 1L):length(x)] - x[seq_len(length(x) - lag)])
  scale <- mean(diffs)
  eps <- 1e-12 * max(mean(abs(x)), 1)
  if (!is.finite(scale) || scale <= eps) {
    ag_stop("LOSS_SCALE_UNDEFINED", sprintf("scale=%.6g,eps=%.6g", scale, eps))
  }
  as.numeric(scale)
}

ag_mase <- function(y, f, D_scale, M = NULL) {
  y <- as.numeric(y); f <- as.numeric(f)
  if (length(y) != length(f) || any(!is.finite(y)) || any(!is.finite(f))) {
    ag_stop("LOSS_INPUT_INVALID")
  }
  q <- ag_mase_scale(D_scale, M)
  as.numeric(mean(abs(y - f)) / q)
}
