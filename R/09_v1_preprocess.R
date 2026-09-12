# AutoGrey Step 7C2 — frozen V1 preprocessing and 56-input assembly.
# Canonical source: autogrey_v2_search_step5db_r2.py (Step 5D-B-R2).
#
# Scope is deliberately narrow:
# - 23 masked feature values
# - 23 validity bits
# - 10 structural eligibility bits
# - group/fold-specific finite-value median imputation
# - zero fallback when a training column has no finite values
# - NO feature scaling
#
# No random-forest fitting or prediction is implemented in this file.

AG_V1_PREPROCESS_VERSION <- "AG_V1_PREPROCESS_5DB_R2"

AG_V1_GROUPS <- c(
  "SG01_CONT_GM",
  "SG02_DISCRETE_POLY",
  "SG03_FRAC_LINEAR",
  "SG04_BERNOULLI",
  "SG05_CONT_TIME_POLY",
  "SG06_CONFORMABLE",
  "SG07_ROLLING",
  "SG08_WBO",
  "SG09_GREY_MARKOV",
  "SG10_SEASONAL"
)

ag_v1_feature_names <- function() {
  if (!exists("AG_FEATURE_NAMES", inherits = TRUE)) {
    stop("AG_FEATURE_NAMES is unavailable; source R/08_features.R first", call. = FALSE)
  }
  as.character(AG_FEATURE_NAMES)
}

ag_v1_input_names <- function() {
  fn <- ag_v1_feature_names()
  c(paste0("value::", fn), paste0("valid::", fn), paste0("elig::", AG_V1_GROUPS))
}

# Exact helper semantics of Python _valid(): int(float(value)) == 1.
# Python int() truncates toward zero; R as.integer() does the same for finite reals.
ag_v1_valid_field <- function(x) {
  if (length(x) != 1L || is.null(x) || is.na(x)) return(FALSE)
  y <- suppressWarnings(as.double(x))
  if (length(y) != 1L || !is.finite(y)) return(FALSE)
  identical(as.integer(y), 1L)
}

ag_v1_float_or_na <- function(x) {
  if (length(x) != 1L || is.null(x) || is.na(x)) return(NA_real_)
  y <- suppressWarnings(as.double(x))
  if (length(y) != 1L || !is.finite(y)) return(NA_real_)
  y
}

ag_v1_int_strict <- function(x, field = "integer field") {
  if (length(x) != 1L || is.null(x) || is.na(x)) stop(paste0("invalid ", field), call. = FALSE)
  y <- suppressWarnings(as.double(x))
  if (length(y) != 1L || !is.finite(y)) stop(paste0("invalid ", field), call. = FALSE)
  # Canonical as_int() is int(float(s)); fractional values are truncated.
  as.integer(y)
}

ag_v1_build_from_action_row <- function(row) {
  if (is.data.frame(row)) {
    if (nrow(row) != 1L) stop("action row must contain exactly one row", call. = FALSE)
    row <- as.list(row[1L, , drop = FALSE])
  }
  if (!is.list(row)) stop("action row must be a named list or one-row data.frame", call. = FALSE)

  fn <- ag_v1_feature_names()
  vals <- numeric(length(fn))
  masks <- numeric(length(fn))
  for (j in seq_along(fn)) {
    vk <- paste0("valid__", fn[j])
    fk <- paste0("feat__", fn[j])
    if (is.null(row[[vk]]) || is.null(row[[fk]])) stop(paste0("missing action-table field: ", if (is.null(row[[vk]])) vk else fk), call. = FALSE)
    ok <- ag_v1_valid_field(row[[vk]])
    masks[j] <- if (ok) 1.0 else 0.0
    vals[j] <- if (ok) ag_v1_float_or_na(row[[fk]]) else NA_real_
  }

  elig <- numeric(length(AG_V1_GROUPS))
  for (j in seq_along(AG_V1_GROUPS)) {
    k <- paste0("elig__", AG_V1_GROUPS[j])
    if (is.null(row[[k]])) stop(paste0("missing action-table field: ", k), call. = FALSE)
    elig[j] <- as.double(ag_v1_int_strict(row[[k]], k))
  }

  out <- c(vals, masks, elig)
  names(out) <- ag_v1_input_names()
  out
}

# Bridge from the Step-7C1 feature object to the selector raw input.
# INVALID feature values MUST become missing here even though Step 7C1 transports
# them as numeric zero. The training-subset median is applied only later.
ag_v1_build_from_snapshot <- function(feature_values, valid_mask, eligibility_bits) {
  fn <- ag_v1_feature_names()
  if (length(feature_values) != length(fn) || length(valid_mask) != length(fn)) {
    stop("feature_values and valid_mask must each have length 23", call. = FALSE)
  }
  if (length(eligibility_bits) != length(AG_V1_GROUPS)) {
    stop("eligibility_bits must have length 10", call. = FALSE)
  }
  fv <- as.double(feature_values)
  vm <- as.logical(valid_mask)
  if (any(is.na(vm))) stop("valid_mask contains NA", call. = FALSE)
  vals <- fv
  vals[!vm] <- NA_real_
  vals[vm & !is.finite(vals)] <- NA_real_

  eb <- suppressWarnings(as.double(eligibility_bits))
  if (any(!is.finite(eb))) stop("eligibility_bits contain non-finite values", call. = FALSE)
  eb <- as.double(as.integer(eb))

  out <- c(vals, as.double(vm), eb)
  names(out) <- ag_v1_input_names()
  out
}

# Vectorized action-table assembly used by parity and later TRAIN reproduction.
ag_v1_build_matrix_from_action_table <- function(df) {
  if (!is.data.frame(df)) stop("df must be a data.frame", call. = FALSE)
  fn <- ag_v1_feature_names()
  required <- c(paste0("feat__", fn), paste0("valid__", fn), paste0("elig__", AG_V1_GROUPS))
  miss <- setdiff(required, names(df))
  if (length(miss)) stop(paste0("missing action-table fields: ", paste(miss, collapse = ",")), call. = FALSE)
  n <- nrow(df)

  values <- matrix(NA_real_, nrow = n, ncol = length(fn))
  masks <- matrix(0.0, nrow = n, ncol = length(fn))
  for (j in seq_along(fn)) {
    vr <- suppressWarnings(as.double(df[[paste0("valid__", fn[j])]]))
    ok <- is.finite(vr) & (as.integer(vr) == 1L)
    masks[, j] <- as.double(ok)
    vv <- suppressWarnings(as.double(df[[paste0("feat__", fn[j])]]))
    vv[!is.finite(vv)] <- NA_real_
    values[ok, j] <- vv[ok]
  }

  elig <- matrix(0.0, nrow = n, ncol = length(AG_V1_GROUPS))
  for (j in seq_along(AG_V1_GROUPS)) {
    y <- suppressWarnings(as.double(df[[paste0("elig__", AG_V1_GROUPS[j])]]))
    if (any(!is.finite(y))) stop(paste0("invalid eligibility column: ", AG_V1_GROUPS[j]), call. = FALSE)
    elig[, j] <- as.double(as.integer(y))
  }

  X <- cbind(values, masks, elig)
  colnames(X) <- ag_v1_input_names()
  storage.mode(X) <- "double"
  X
}

ag_v1_fit_medians <- function(X_train) {
  X <- as.matrix(X_train)
  storage.mode(X) <- "double"
  if (length(dim(X)) != 2L || nrow(X) < 1L) stop("X_train must be a nonempty numeric matrix", call. = FALSE)
  med <- numeric(ncol(X))
  for (j in seq_len(ncol(X))) {
    col <- X[, j]
    good <- is.finite(col)
    med[j] <- if (any(good)) stats::median(col[good]) else 0.0
  }
  names(med) <- colnames(X)
  med
}

ag_v1_apply_medians <- function(X, medians) {
  A <- as.matrix(X); storage.mode(A) <- "double"
  med <- as.double(medians)
  if (ncol(A) != length(med)) stop("median width does not match matrix width", call. = FALSE)
  bad <- !is.finite(A)
  if (any(bad)) {
    idx <- which(bad, arr.ind = TRUE)
    A[bad] <- med[idx[, 2L]]
  }
  A
}

ag_v1_fit_medians_and_transform <- function(X_train, X_eval) {
  tr <- as.matrix(X_train); ev <- as.matrix(X_eval)
  storage.mode(tr) <- storage.mode(ev) <- "double"
  if (ncol(tr) != ncol(ev)) stop("X_train and X_eval widths differ", call. = FALSE)
  med <- ag_v1_fit_medians(tr)
  list(
    train = ag_v1_apply_medians(tr, med),
    eval = ag_v1_apply_medians(ev, med),
    medians = med
  )
}
