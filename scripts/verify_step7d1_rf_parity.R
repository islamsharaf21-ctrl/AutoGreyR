# AutoGrey Step 7D1 — deterministic frozen RF parity verifier.
# Run from package root:
#   source("scripts/verify_step7d1_rf_parity.R")
#
# This verifier intentionally does NOT substitute ranger for sklearn.
# The production parity path is R orchestration -> exact frozen sklearn RF bridge.

options(warn = 1)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required")
if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required")

source("R/08_features.R", local = .GlobalEnv)
source("R/09_v1_preprocess.R", local = .GlobalEnv)
source("R/10_v1_rf_bridge.R", local = .GlobalEnv)

sha256_file <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
assert_true <- function(name, cond, detail = "") {
  if (!isTRUE(cond)) stop(sprintf("FAIL %s%s", name, if (nzchar(detail)) paste0(": ", detail) else ""), call. = FALSE)
  cat(sprintf("PASS %-66s%s\n", name, if (nzchar(detail)) paste0(" ", detail) else ""))
}
assert_equal <- function(name, actual, expected) {
  if (!identical(actual, expected)) {
    stop(sprintf("FAIL %s: actual=%s expected=%s", name, paste(actual, collapse=","), paste(expected, collapse=",")), call. = FALSE)
  }
  cat(sprintf("PASS %s\n", name))
}
assert_close <- function(name, actual, expected, tol = 1e-12) {
  a <- as.double(actual); e <- as.double(expected)
  if (length(a) != length(e)) stop(sprintf("FAIL %s: length mismatch", name), call. = FALSE)
  d <- if (length(a)) max(abs(a - e)) else 0.0
  if (!is.finite(d) || d > tol) stop(sprintf("FAIL %s: max_abs=%.17g > %.17g", name, d, tol), call. = FALSE)
  cat(sprintf("PASS %-66s max_abs=%.3e\n", name, d))
}
numvec <- function(x) as.double(unlist(x, use.names = FALSE))
strvec <- function(x) as.character(unlist(x, use.names = FALSE))
json_matrix <- function(x) do.call(rbind, lapply(x, numvec))

EXPECTED <- list(
  selector = "a5f6e6914809bcde3667c96165984a218595c92c4cbf1d98ff4b23de50be2d23",
  action = "5e943ce10c601187d46dd0f77e9059aee29c7e2710d1d8ff5acf779787983a99",
  labels = "77e202112c8d3de45aeebfdbe6a4c8d1ac9b725aac598af5974d46a3f5be4631",
  structural = "3c8dfb520d7409c6bf6dfd93a74aecb6a0281e39e4797de0ed6f49b9d059f188",
  elig = "ec10d3b12120ef36c51167721f890bbee93c5e3ad08b85b7bf0ce9a2d3ed7409",
  feature = "30dbb8b2b19f6b6cde51fb7d5da3e51ced51004d8a973986107c3724be2e28f4",
  preprocess = "5a37921120fe2a9db910deaf68244b0a675fc3c6d0ec2cb8dc02ed95e85318f5",
  oracle = "c501d2364dfd7f528d523e8ab9462f03109439b9f4b07eaef9590849b615f8ef"
)

selector_py <- "reference/python/autogrey_v2_search_step5db_r2.py"
helper_py <- "reference/python/ag_step7d1_sklearn_bridge.py"
compare_py <- "reference/python/ag_step7d1_input_compare.py"
action_csv <- "reference/frozen/AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv"
labels_csv <- "reference/frozen/AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv"
fixture_path <- "inst/extdata/rf_reference_fixture_step7d1.json"

assert_equal("canonical_selector_source_sha256", sha256_file(selector_py), EXPECTED$selector)
assert_equal("frozen_action_table_sha256", sha256_file(action_csv), EXPECTED$action)
assert_equal("frozen_train_labels_sha256", sha256_file(labels_csv), EXPECTED$labels)
assert_equal("step7b_structural_source_preservation", sha256_file("R/06_structural_groups.R"), EXPECTED$structural)
assert_equal("step7b_eligibility_source_preservation", sha256_file("R/07_eligibility_collision.R"), EXPECTED$elig)
assert_equal("step7c1_feature_source_preservation", sha256_file("R/08_features.R"), EXPECTED$feature)
assert_equal("step7c2_preprocess_source_preservation", sha256_file("R/09_v1_preprocess.R"), EXPECTED$preprocess)
assert_equal("rf_oracle_fixture_sha256", sha256_file(fixture_path), EXPECTED$oracle)

oracle <- jsonlite::fromJSON(fixture_path, simplifyVector = FALSE)
assert_equal("oracle_checkpoint", oracle$checkpoint, "STEP7D1_RF_DETERMINISTIC_PARITY")
assert_equal("oracle_selector_sha", oracle$canonical_selector_source$sha256, EXPECTED$selector)
assert_true("rf_contract_500_trees", as.integer(oracle$constants$n_estimators) == 500L)
assert_true("rf_contract_seed_62291", as.integer(oracle$constants$random_seed) == 62291L)
assert_equal("rf_contract_max_features_sqrt", oracle$constants$max_features, "sqrt")
assert_true("rf_contract_width_56", AG_V1_RF_WIDTH == 56L)

cat("INFO checking frozen Python RF environment through R...\n")
env <- ag_rf_check_environment(helper_py)
cat(sprintf("INFO python=%s numpy=%s sklearn=%s launcher=%s\n",
            env$python, env$numpy, env$scikit_learn, env$launcher_source))
assert_equal("python_version_frozen", as.character(env$python), "3.13.5")
assert_equal("numpy_version_frozen", as.character(env$numpy), "2.3.5")
assert_equal("sklearn_version_frozen", as.character(env$scikit_learn), "1.8.0")
assert_true("algorithm_versions_compatible", isTRUE(env$algorithm_versions_compatible))

# ---------------------------------------------------------------------------
# Synthetic weighted semantics fixture.
# Proves that sample_weight changes fitted predictions while the sklearn
# bootstrap index stream remains unchanged under the same random_state.
# ---------------------------------------------------------------------------
syn <- oracle$synthetic_weight_semantics
Xs <- json_matrix(syn$x_train)
ys <- numvec(syn$y_train)
ws <- numvec(syn$weights)
Es <- json_matrix(syn$x_eval)
assert_true("synthetic_shape", nrow(Xs) == as.integer(syn$n_train) && ncol(Xs) == 56L && nrow(Es) == as.integer(syn$n_eval))

cat("INFO fitting canonical weighted sklearn fixture through R bridge...\n")
rw1 <- ag_rf_fit_predict_sklearn(Xs, ys, ws, Es, helper = helper_py)
assert_close("synthetic_weighted_predictions", numvec(rw1$predictions), numvec(syn$weighted_predictions), 2e-14)
assert_true("synthetic_effective_min_leaf", as.integer(rw1$effective_min_samples_leaf) == as.integer(syn$effective_min_samples_leaf))
assert_true("synthetic_mtry_sqrt", as.integer(rw1$mtry_sqrt) == 7L)
assert_equal("synthetic_bootstrap_hashes_weighted", strvec(rw1$bootstrap_index_sha256_first12), strvec(syn$bootstrap_hashes_weighted_first12))

cat("INFO fitting canonical unweighted sklearn fixture through R bridge...\n")
ru <- ag_rf_fit_predict_sklearn(Xs, ys, NULL, Es, helper = helper_py)
assert_close("synthetic_unweighted_predictions", numvec(ru$predictions), numvec(syn$unweighted_predictions), 2e-14)
assert_equal("synthetic_bootstrap_hashes_unweighted", strvec(ru$bootstrap_index_sha256_first12), strvec(syn$bootstrap_hashes_unweighted_first12))
assert_equal("sample_weight_does_not_change_bootstrap_stream",
             strvec(rw1$bootstrap_index_sha256_first12), strvec(ru$bootstrap_index_sha256_first12))
wdiff <- max(abs(numvec(rw1$predictions) - numvec(ru$predictions)))
assert_close("weighted_vs_unweighted_prediction_difference", wdiff, as.double(syn$weighted_vs_unweighted_max_abs), 2e-14)
assert_true("sample_weight_changes_fitted_predictions", wdiff > 1e-6)

cat("INFO repeating weighted fit in a fresh sklearn process...\n")
rw2 <- ag_rf_fit_predict_sklearn(Xs, ys, ws, Es, helper = helper_py)
assert_close("cross_process_weighted_prediction_repeat", numvec(rw2$predictions), numvec(rw1$predictions), 2e-14)
assert_equal("cross_process_bootstrap_repeat", strvec(rw2$bootstrap_index_sha256_first12), strvec(rw1$bootstrap_index_sha256_first12))

# Diagnostic tree fingerprints. These are stronger than ensemble prediction alone.
for (k in seq_len(8L)) {
  got <- rw1$tree_meta_first8[[k]]; exp <- syn$weighted_tree_meta_first8[[k]]
  assert_true(sprintf("synthetic_tree_%02d_random_state", k), as.integer(got$random_state) == as.integer(exp$random_state))
  assert_true(sprintf("synthetic_tree_%02d_node_count", k), as.integer(got$node_count) == as.integer(exp$node_count))
  assert_true(sprintf("synthetic_tree_%02d_max_depth", k), as.integer(got$max_depth) == as.integer(exp$max_depth))
  assert_true(sprintf("synthetic_tree_%02d_root_feature", k), as.integer(got$root_feature) == as.integer(exp$root_feature))
  assert_close(sprintf("synthetic_tree_%02d_root_threshold", k), as.double(got$root_threshold), as.double(exp$root_threshold), 0.0)
}

# ---------------------------------------------------------------------------
# Real frozen TRAIN parent competition: WDI_GDP:ISR, fold 1, exactly two
# distinct eligible actions. R rebuilds and preprocesses the canonical inputs;
# only the RF fit/predict crosses into sklearn.
# ---------------------------------------------------------------------------
cat("INFO reading frozen Step5D-A action table and TRAIN labels...\n")
action <- utils::read.csv(action_csv, header = TRUE, stringsAsFactors = FALSE,
                          check.names = FALSE, colClasses = "character",
                          na.strings = character(0))
labels <- utils::read.csv(labels_csv, header = TRUE, stringsAsFactors = FALSE,
                          check.names = FALSE, colClasses = "character",
                          na.strings = character(0))
train <- action[action$v2_split == "V2_TRAIN", , drop = FALSE]
mi <- match(train$selector_row_hash, labels$selector_row_hash)
assert_true("all_train_labels_joined", length(mi) == nrow(train) && all(!is.na(mi)))
lab <- labels[mi, , drop = FALSE]
assert_true("train_row_count_18107", nrow(train) == 18107L && nrow(labels) == 18107L)
assert_true("join_parent_identity", identical(train$parent_id, lab$parent_id))
assert_true("join_group_identity", identical(train$action_group, lab$action_group))

# Canonical harness order: parent_id, then frozen SG01..SG10 index.
old_collate <- Sys.getlocale("LC_COLLATE")
try(Sys.setlocale("LC_COLLATE", "C"), silent = TRUE)
gidx <- match(train$action_group, AG_V1_GROUPS)
ord <- order(train$parent_id, gidx, method = "radix")
train <- train[ord, , drop = FALSE]
lab <- lab[ord, , drop = FALSE]
gidx <- gidx[ord]
if (!is.na(old_collate) && nzchar(old_collate)) try(Sys.setlocale("LC_COLLATE", old_collate), silent = TRUE)

Xraw <- ag_v1_build_matrix_from_action_table(train)
folds <- suppressWarnings(as.integer(as.double(train$train_cv_fold)))
yall <- suppressWarnings(as.double(lab$target_log1p_regret))
wall <- suppressWarnings(as.double(train$action_row_weight))
assert_true("full_train_arrays_finite_targets_weights", all(is.finite(yall)) && all(is.finite(wall)) && all(wall > 0))

real <- oracle$real_parent_competition
parent <- real$parent_id
fold <- as.integer(real$fold)
ei_all <- which(train$parent_id == parent)
assert_true("real_parent_two_actions", length(ei_all) == 2L)
assert_equal("real_parent_groups", as.character(train$action_group[ei_all]), vapply(real$actions, `[[`, character(1), "group"))

pred_scores <- numeric(0); pred_groups <- character(0)
for (z in real$actions) {
  g <- z$group
  gi <- match(g, AG_V1_GROUPS)
  tr <- which(folds != fold & gidx == gi)
  ei <- which(train$parent_id == parent & train$action_group == g)
  assert_true(paste0(g, "_one_eval_row"), length(ei) == 1L)
  assert_true(paste0(g, "_train_count"), length(tr) == as.integer(z$n_train))
  fit <- ag_v1_fit_medians_and_transform(Xraw[tr, , drop = FALSE], Xraw[ei, , drop = FALSE])
  y <- yall[tr]; w <- wall[tr]

  # Cross-language input gate. Step7C1/7C2 already established numerical R/Python
  # parity rather than raw-float byte identity. Therefore Step7D1 R1 verifies:
  # (1) canonical parent-row order exactly; (2) R matrices/vectors numerically
  # match a fresh canonical Python reconstruction within the Step7C2 1e-12
  # tolerance; and (3) the Python-side hashes still match the frozen oracle.
  # R byte hashes are reported transparently but are not a scientific failure
  # by themselves because a one-ULP parse/median difference changes SHA-256.
  td_cmp <- tempfile(paste0("autogrey_step7d1_cmp_", g, "_"))
  dir.create(td_cmp, recursive = TRUE, showWarnings = FALSE)
  px <- file.path(td_cmp, "x_train.f64")
  pyv <- file.path(td_cmp, "y_train.f64")
  pw <- file.path(td_cmp, "weight_train.f64")
  pe <- file.path(td_cmp, "x_eval.f64")
  pm <- file.path(td_cmp, "medians.f64")
  pp <- file.path(td_cmp, "train_parent_ids.txt")
  preq <- file.path(td_cmp, "request.json")
  pout <- file.path(td_cmp, "result.json")
  ag_rf_write_matrix_f64le(fit$train, px)
  ag_rf_write_vector_f64le(y, pyv)
  ag_rf_write_vector_f64le(w, pw)
  ag_rf_write_matrix_f64le(fit$eval, pe)
  ag_rf_write_vector_f64le(fit$medians, pm)
  writeLines(as.character(train$parent_id[tr]), pp, useBytes = TRUE)
  req_cmp <- list(
    selector_path = normalizePath(selector_py, winslash = "/", mustWork = TRUE),
    frozen_dir = normalizePath("reference/frozen", winslash = "/", mustWork = TRUE),
    group = g, fold = fold, parent_id = parent,
    x_train_path = normalizePath(px, winslash = "/", mustWork = TRUE),
    y_train_path = normalizePath(pyv, winslash = "/", mustWork = TRUE),
    weight_train_path = normalizePath(pw, winslash = "/", mustWork = TRUE),
    x_eval_path = normalizePath(pe, winslash = "/", mustWork = TRUE),
    medians_path = normalizePath(pm, winslash = "/", mustWork = TRUE),
    train_parent_ids_path = normalizePath(pp, winslash = "/", mustWork = TRUE),
    n_train = nrow(fit$train), n_eval = nrow(fit$eval), n_features = ncol(fit$train)
  )
  jsonlite::write_json(req_cmp, preq, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 17)
  spec_cmp <- ag_rf_python_spec()
  run_cmp <- ag_rf_system2(spec_cmp, c(compare_py, "--request", preq, "--output", pout), stdout = TRUE, stderr = TRUE)
  assert_true(paste0(g, "_input_compare_result_created"), file.exists(pout))
  cmp <- jsonlite::fromJSON(pout, simplifyVector = FALSE)
  if (run_cmp$status != 0L || !identical(cmp$status, "PASS")) {
    stop(paste0("FAIL ", g, " canonical input comparison: ", cmp$error %||% paste(run_cmp$output, collapse = "\n")), call. = FALSE)
  }
  assert_true(paste0(g, "_canonical_row_order_exact"), isTRUE(cmp$row_order_exact))
  assert_true(paste0(g, "_x_train_numeric_parity"), as.double(cmp$x_train$max_abs) <= 1e-12,
              sprintf("max_abs=%.3e", as.double(cmp$x_train$max_abs)))
  assert_true(paste0(g, "_x_eval_numeric_parity"), as.double(cmp$x_eval$max_abs) <= 1e-12,
              sprintf("max_abs=%.3e", as.double(cmp$x_eval$max_abs)))
  assert_true(paste0(g, "_y_train_numeric_parity"), as.double(cmp$y_train$max_abs) <= 1e-12,
              sprintf("max_abs=%.3e", as.double(cmp$y_train$max_abs)))
  assert_true(paste0(g, "_weight_train_numeric_parity"), as.double(cmp$weight_train$max_abs) <= 1e-12,
              sprintf("max_abs=%.3e", as.double(cmp$weight_train$max_abs)))
  assert_true(paste0(g, "_median_numeric_parity"), as.double(cmp$medians$max_abs) <= 1e-12,
              sprintf("max_abs=%.3e", as.double(cmp$medians$max_abs)))
  assert_equal(paste0(g, "_python_x_train_hash_matches_oracle"), cmp$x_train$python_sha256, z$x_train_sha256_f64)
  assert_equal(paste0(g, "_python_y_train_hash_matches_oracle"), cmp$y_train$python_sha256, z$y_train_sha256_f64)
  assert_equal(paste0(g, "_python_weight_hash_matches_oracle"), cmp$weight_train$python_sha256, z$weight_train_sha256_f64)
  assert_equal(paste0(g, "_python_x_eval_hash_matches_oracle"), cmp$x_eval$python_sha256, z$x_eval_sha256_f64)
  assert_equal(paste0(g, "_python_median_hash_matches_oracle"), cmp$medians$python_sha256, z$medians_sha256_f64)
  cat(sprintf("INFO %s R-vs-Python exact bytes: Xtr=%s y=%s w=%s Xev=%s; nonexact cells Xtr=%d max_abs=%.3e\n",
              g, cmp$x_train$exact_equal, cmp$y_train$exact_equal, cmp$weight_train$exact_equal, cmp$x_eval$exact_equal,
              as.integer(cmp$x_train$n_nonexact), as.double(cmp$x_train$max_abs)))
  unlink(td_cmp, recursive = TRUE, force = TRUE)

  cat(sprintf("INFO fitting real frozen %s fold %d model...\n", g, fold))
  ans <- ag_rf_fit_predict_sklearn(fit$train, y, w, fit$eval, helper = helper_py)
  p <- numvec(ans$predictions)[1L]
  assert_close(paste0(g, "_prediction"), p, as.double(z$prediction), 2e-14)
  assert_true(paste0(g, "_effective_min_leaf"), as.integer(ans$effective_min_samples_leaf) == as.integer(z$effective_min_samples_leaf))
  assert_equal(paste0(g, "_bootstrap_first8"), strvec(ans$bootstrap_index_sha256_first12)[1:8], strvec(z$bootstrap_index_sha256_first8))
  for (k in seq_len(8L)) {
    got <- ans$tree_meta_first8[[k]]; exp <- z$tree_meta_first8[[k]]
    assert_true(sprintf("%s_tree_%02d_state", g, k), as.integer(got$random_state) == as.integer(exp$random_state))
    assert_true(sprintf("%s_tree_%02d_nodes", g, k), as.integer(got$node_count) == as.integer(exp$node_count))
    assert_true(sprintf("%s_tree_%02d_depth", g, k), as.integer(got$max_depth) == as.integer(exp$max_depth))
    assert_true(sprintf("%s_tree_%02d_root_feature", g, k), as.integer(got$root_feature) == as.integer(exp$root_feature))
    assert_close(sprintf("%s_tree_%02d_root_threshold", g, k), as.double(got$root_threshold), as.double(exp$root_threshold), 1e-12)
    assert_close(sprintf("%s_tree_%02d_prediction", g, k), as.double(got_pred <- ans$per_tree_predictions_first8[[k]][[1L]]), as.double(z$per_tree_prediction_first8[[k]]), 2e-14)
  }
  # Frozen label/weight identity on the evaluation action.
  assert_close(paste0(g, "_eval_target_identity"), yall[ei], as.double(z$target_actual), 1e-15)
  assert_close(paste0(g, "_eval_regret_identity"), suppressWarnings(as.double(lab$eligible_regret[ei])), as.double(z$regret_actual), 1e-15)
  assert_close(paste0(g, "_eval_weight_identity"), wall[ei], as.double(z$weight_actual), 1e-15)
  pred_scores <- c(pred_scores, p); pred_groups <- c(pred_groups, g)
}

names(pred_scores) <- pred_groups
choice <- ag_v1_choose_by_predicted_target(pred_scores, pred_groups)
assert_equal("real_parent_selected_group", choice$group, real$selected_group)
assert_close("real_parent_SG04_score", pred_scores[["SG04_BERNOULLI"]], as.double(real$predicted_scores$SG04_BERNOULLI), 2e-14)
assert_close("real_parent_SG06_score", pred_scores[["SG06_CONFORMABLE"]], as.double(real$predicted_scores$SG06_CONFORMABLE), 2e-14)

# Exact tie behavior: no tolerance-based tie is introduced by the V1 decision rule.
tie <- ag_v1_choose_by_predicted_target(c(0.5, 0.5), c("SG06_CONFORMABLE", "SG04_BERNOULLI"))
assert_equal("exact_prediction_tie_uses_frozen_group_index", tie$group, "SG04_BERNOULLI")
near <- ag_v1_choose_by_predicted_target(c(0.2, 0.2000000000001), c("SG04_BERNOULLI", "SG01_CONT_GM"))
assert_equal("near_but_not_equal_scores_do_not_use_tie_tolerance", near$group, "SG04_BERNOULLI")

# Native ranger is not used as the canonical engine. Report availability only.
if (requireNamespace("ranger", quietly = TRUE)) {
  cat(sprintf("INFO ranger=%s present; diagnostic only, not used for frozen RF fits.\n",
              as.character(utils::packageVersion("ranger"))))
} else {
  cat("INFO ranger not installed; this does not affect the canonical sklearn bridge parity gate.\n")
}

cat("\nSTEP7D1_RF_DETERMINISTIC_PARITY_R1: PASS\n")
