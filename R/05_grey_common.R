# AutoGrey R reproduction — common continuous-GM response for Step 7B1.

ag_continuous_response_constant <- function(x1_0, a, b, total) {
  total <- as.integer(total)
  tau <- seq.int(0L, total - 1L)
  if (ag_near(a, 0)) {
    y <- as.numeric(x1_0) + as.numeric(b) * tau
  } else {
    y <- (as.numeric(x1_0) - as.numeric(b) / as.numeric(a)) * exp(-as.numeric(a) * tau) +
      as.numeric(b) / as.numeric(a)
  }
  if (any(!is.finite(y))) ag_stop("RESPONSE_NONFINITE")
  as.numeric(y)
}
