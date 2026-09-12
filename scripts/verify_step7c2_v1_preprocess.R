# AutoGrey Step 7C2 external R parity verifier.
# Run from package root:
#   source("scripts/verify_step7c2_v1_preprocess.R")

options(warn = 1)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required")
if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required")

source("R/08_features.R", local = .GlobalEnv)
source("R/09_v1_preprocess.R", local = .GlobalEnv)

fixture_path <- "inst/extdata/v1_preprocess_reference_fixture_step7c2.json"
selector_py <- "reference/python/autogrey_v2_search_step5db_r2.py"
action_csv <- "reference/frozen/AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv"

sha256_file <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)

assert_true <- function(name, cond, detail = "") {
  if (!isTRUE(cond)) stop(sprintf("FAIL %s%s", name, if (nzchar(detail)) paste0(": ", detail) else ""), call. = FALSE)
  cat(sprintf("PASS %-62s%s\n", name, if (nzchar(detail)) paste0(" ", detail) else ""))
}
assert_equal <- function(name, actual, expected) {
  if (!identical(actual, expected)) {
    stop(sprintf("FAIL %s: actual=%s expected=%s", name, paste(actual, collapse=","), paste(expected, collapse=",")), call. = FALSE)
  }
  cat(sprintf("PASS %s\n", name))
}
assert_close <- function(name, actual, expected, tol = 1e-12) {
  actual <- as.double(actual); expected <- as.double(expected)
  if (length(actual) != length(expected)) stop(sprintf("FAIL %s: length mismatch", name), call. = FALSE)
  if (!length(actual)) { cat(sprintf("PASS %s\n", name)); return(invisible(TRUE)) }
  d <- max(abs(actual - expected))
  if (!is.finite(d) || d > tol) stop(sprintf("FAIL %s: max_abs=%.17g > %.17g", name, d, tol), call. = FALSE)
  cat(sprintf("PASS %-62s max_abs=%.3e\n", name, d))
}
assert_maybe_na <- function(name, actual, expected, tol = 1e-12) {
  actual <- as.double(actual); expected <- as.double(expected)
  if (length(actual) != length(expected)) stop(sprintf("FAIL %s: length mismatch", name), call. = FALSE)
  na_a <- !is.finite(actual); na_e <- !is.finite(expected)
  if (!identical(na_a, na_e)) stop(sprintf("FAIL %s: missing-pattern mismatch", name), call. = FALSE)
  keep <- !na_e
  d <- if (any(keep)) max(abs(actual[keep] - expected[keep])) else 0.0
  if (!is.finite(d) || d > tol) stop(sprintf("FAIL %s: finite max_abs=%.17g > %.17g", name, d, tol), call. = FALSE)
  cat(sprintf("PASS %-62s max_abs=%.3e\n", name, d))
}
json_num <- function(z) vapply(z, function(x) if (is.null(x)) NA_real_ else as.double(x), numeric(1))
json_matrix <- function(z) do.call(rbind, lapply(z, json_num))

EXPECTED_SELECTOR_SHA <- "a5f6e6914809bcde3667c96165984a218595c92c4cbf1d98ff4b23de50be2d23"
EXPECTED_ACTION_SHA <- "5e943ce10c601187d46dd0f77e9059aee29c7e2710d1d8ff5acf779787983a99"
EXPECTED_STRUCTURAL_SHA <- "3c8dfb520d7409c6bf6dfd93a74aecb6a0281e39e4797de0ed6f49b9d059f188"
EXPECTED_ELIG_SHA <- "ec10d3b12120ef36c51167721f890bbee93c5e3ad08b85b7bf0ce9a2d3ed7409"
EXPECTED_FEATURE_SHA <- "30dbb8b2b19f6b6cde51fb7d5da3e51ced51004d8a973986107c3724be2e28f4"

assert_equal("canonical_selector_source_sha256", sha256_file(selector_py), EXPECTED_SELECTOR_SHA)
assert_equal("frozen_action_table_sha256", sha256_file(action_csv), EXPECTED_ACTION_SHA)
assert_equal("step7b_structural_source_preservation", sha256_file("R/06_structural_groups.R"), EXPECTED_STRUCTURAL_SHA)
assert_equal("step7b_eligibility_source_preservation", sha256_file("R/07_eligibility_collision.R"), EXPECTED_ELIG_SHA)
assert_equal("step7c1_feature_source_preservation", sha256_file("R/08_features.R"), EXPECTED_FEATURE_SHA)

oracle <- jsonlite::fromJSON(fixture_path, simplifyVector = FALSE)
assert_equal("oracle_checkpoint", oracle$checkpoint, "STEP7C2_V1_PREPROCESS_56_INPUT_PARITY")
assert_equal("oracle_selector_sha", oracle$canonical_selector_source$sha256, EXPECTED_SELECTOR_SHA)
assert_equal("oracle_action_table_sha", oracle$canonical_action_table$sha256, EXPECTED_ACTION_SHA)
assert_true("oracle_train_rows_18107", as.integer(oracle$canonical_action_table$train_rows) == 18107L)
assert_equal("group_order", as.character(unlist(oracle$groups)), AG_V1_GROUPS)
assert_equal("feature_order", as.character(unlist(oracle$feature_names)), AG_FEATURE_NAMES)
assert_true("input_width_56", as.integer(oracle$input_width) == 56L)
assert_equal("input_column_order", ag_v1_input_names(), as.character(unlist(oracle$column_names)))
assert_true("input_partition_23_23_10",
            as.integer(oracle$semantics$feature_value_count) == 23L &&
            as.integer(oracle$semantics$validity_bit_count) == 23L &&
            as.integer(oracle$semantics$eligibility_bit_count) == 10L)
assert_equal("scaling_none", oracle$semantics$scaling, "NONE")
assert_true("group_fold_specific_preprocessing", isTRUE(oracle$semantics$group_fold_specific))

# Python _valid() compatibility, including its int(float(.)) truncation semantics.
assert_equal("valid_semantics_1", ag_v1_valid_field("1"), TRUE)
assert_equal("valid_semantics_1p9_truncates_to_1", ag_v1_valid_field("1.9"), TRUE)
assert_equal("valid_semantics_zero", ag_v1_valid_field("0"), FALSE)
assert_equal("valid_semantics_negative_fraction_truncates_zero", ag_v1_valid_field("-0.2"), FALSE)
assert_equal("valid_semantics_bad_string", ag_v1_valid_field("not-a-number"), FALSE)

cat("INFO reading frozen Step5D-A action table for full group/fold median parity...\n")
action <- utils::read.csv(action_csv, header = TRUE, stringsAsFactors = FALSE,
                          check.names = FALSE, colClasses = "character",
                          na.strings = character(0))
train <- action[action$v2_split == "V2_TRAIN", , drop = FALSE]
assert_true("action_table_train_row_count", nrow(train) == 18107L)
X <- ag_v1_build_matrix_from_action_table(train)
assert_true("full_train_matrix_shape", nrow(X) == 18107L && ncol(X) == 56L)
assert_equal("full_train_matrix_column_order", colnames(X), ag_v1_input_names())

# Real action rows: build exact raw 56-vector from canonical CSV fields.
for (z in oracle$real_action_rows) {
  lab <- z$label
  hash <- z$meta$selector_row_hash
  ii <- which(train$selector_row_hash == hash)
  assert_true(paste0(lab, "_unique_selector_row"), length(ii) == 1L)
  got <- ag_v1_build_from_action_row(train[ii, , drop = FALSE])
  exp <- json_num(z$raw_vector)
  assert_maybe_na(paste0(lab, "_raw_56_vector"), got, exp, 1e-12)
  assert_true(paste0(lab, "_invalid_feature_count"), sum(!is.finite(got[1:23])) == as.integer(z$invalid_feature_count))
  assert_equal(paste0(lab, "_validity_bits"), as.integer(got[24:46]), as.integer(unlist(z$validity_bits)))
  assert_equal(paste0(lab, "_eligibility_bits"), as.integer(got[47:56]), as.integer(unlist(z$eligibility_bits)))

  # Step7C1 -> Step7C2 bridge: invalid Step7C1 zeros must become NA before imputation.
  fv <- vapply(as.list(train[ii, paste0("feat__", AG_FEATURE_NAMES), drop = FALSE]),
               function(x) suppressWarnings(as.double(x[[1L]])), numeric(1))
  vm <- vapply(as.list(train[ii, paste0("valid__", AG_FEATURE_NAMES), drop = FALSE]),
               function(x) ag_v1_valid_field(x[[1L]]), logical(1))
  fv[!is.finite(fv)] <- 0.0
  eb <- vapply(as.list(train[ii, paste0("elig__", AG_V1_GROUPS), drop = FALSE]),
               function(x) suppressWarnings(as.double(x[[1L]])), numeric(1))
  bridge <- ag_v1_build_from_snapshot(fv, vm, eb)
  assert_maybe_na(paste0(lab, "_step7c1_to_selector_bridge"), bridge, exp, 1e-12)
}

# Full canonical group-specific/fold-specific median parity for every group,
# using all frozen TRAIN action rows in the relevant training subset.
fold_num <- suppressWarnings(as.integer(as.double(train$train_cv_fold)))
for (z in oracle$group_fold_fixtures) {
  fold <- as.integer(z$fold); g <- z$group
  tr <- which(fold_num != fold & train$action_group == g)
  assert_true(paste0("fold", fold, "_", g, "_train_count"), length(tr) == as.integer(z$n_train_rows))
  med <- ag_v1_fit_medians(X[tr, , drop = FALSE])
  assert_close(paste0("fold", fold, "_", g, "_medians"), med, json_num(z$medians), 1e-12)

  ei <- which(train$selector_row_hash == z$eval_meta$selector_row_hash)
  assert_true(paste0("fold", fold, "_", g, "_eval_unique"), length(ei) == 1L)
  raw <- X[ei, , drop = FALSE]
  assert_maybe_na(paste0("fold", fold, "_", g, "_eval_raw"), raw[1,], json_num(z$eval_raw), 1e-12)
  transformed <- ag_v1_apply_medians(raw, med)
  assert_close(paste0("fold", fold, "_", g, "_eval_transformed"), transformed[1,], json_num(z$eval_transformed), 1e-12)
  assert_true(paste0("fold", fold, "_", g, "_imputed_count"), sum(!is.finite(raw[1,])) == as.integer(z$n_eval_imputed))
  assert_true(paste0("fold", fold, "_", g, "_posttransform_finite"), all(is.finite(transformed)))
  # Masks + eligibility are already finite selector inputs and must never be altered by imputation.
  assert_close(paste0("fold", fold, "_", g, "_bits_unchanged"), transformed[1,24:56], raw[1,24:56], 0.0)
}

# Prove fold-specific preprocessing is genuinely different on the frozen data.
g0 <- oracle$group_fold_fixtures[[1]]$group
z0 <- Filter(function(z) z$group == g0 && as.integer(z$fold) == 0L, oracle$group_fold_fixtures)[[1]]
z3 <- Filter(function(z) z$group == g0 && as.integer(z$fold) == 3L, oracle$group_fold_fixtures)[[1]]
assert_true("fold_specific_medians_not_identical", max(abs(json_num(z0$medians) - json_num(z3$medians))) > 0)

# Synthetic generic median fixture covers the no-finite-values => 0 rule and
# even-count numpy/R median equivalence explicitly.
s <- oracle$synthetic_median_fixture
Xtr <- json_matrix(s$train_raw); Xev <- json_matrix(s$eval_raw)
fit <- ag_v1_fit_medians_and_transform(Xtr, Xev)
assert_close("synthetic_medians", fit$medians, json_num(s$medians), 0.0)
assert_close("synthetic_train_transformed", as.double(t(fit$train)), as.double(t(json_matrix(s$train_transformed))), 0.0)
assert_close("synthetic_eval_transformed", as.double(t(fit$eval)), as.double(t(json_matrix(s$eval_transformed))), 0.0)
assert_true("synthetic_all_nonfinite_column_imputes_zero", fit$medians[2] == 0.0)
assert_true("synthetic_even_count_median", fit$medians[1] == 6.0 && fit$medians[5] == 25.0)

# Guard against accidental scaling/clipping: finite observed values remain exact.
A <- matrix(c(1e-9, 1e9, NA, 7), nrow = 1)
med <- c(3,4,5,6)
B <- ag_v1_apply_medians(A, med)
assert_close("no_scaling_or_clipping", B, c(1e-9,1e9,5,7), 0.0)

# Width/error behavior for engineering API.
msg <- tryCatch({ag_v1_build_from_snapshot(rep(0,22), rep(TRUE,22), rep(1,10)); NA_character_}, error=function(e) conditionMessage(e))
assert_equal("snapshot_width_refusal", msg, "feature_values and valid_mask must each have length 23")
msg <- tryCatch({ag_v1_build_from_snapshot(rep(0,23), rep(TRUE,23), rep(1,9)); NA_character_}, error=function(e) conditionMessage(e))
assert_equal("eligibility_width_refusal", msg, "eligibility_bits must have length 10")
msg <- tryCatch({ag_v1_fit_medians_and_transform(matrix(1,2,3), matrix(1,2,4)); NA_character_}, error=function(e) conditionMessage(e))
assert_equal("matrix_width_refusal", msg, "X_train and X_eval widths differ")

cat("\nSTEP7C2_V1_PREPROCESS_PARITY: PASS\n")
