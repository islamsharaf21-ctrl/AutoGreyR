ag_release_expect <- function(condition, label, detail = NULL) {
  if (!isTRUE(condition)) {
    msg <- if (is.null(detail)) sprintf("FAIL %s", label) else sprintf("FAIL %s: %s", label, detail)
    stop(msg, call. = FALSE)
  }
  cat(sprintf("PASS %-68s\n", label))
  invisible(TRUE)
}

ag_release_expect_identical <- function(actual, expected, label) {
  ag_release_expect(identical(actual, expected), label,
                    sprintf("actual=%s expected=%s", paste(actual, collapse = ","), paste(expected, collapse = ",")))
}

ag_release_expect_near <- function(actual, expected, tol, label) {
  a <- as.double(actual); b <- as.double(expected)
  d <- if (length(a)) max(abs(a - b)) else 0
  ag_release_expect(length(a) == length(b) && is.finite(d) && d <= tol, label,
                    sprintf("max_abs=%.17g tol=%.17g", d, tol))
}
