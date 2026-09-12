# AutoGrey Step 7D2 — full frozen V1 TRAIN/R2 parity verifier.
# Run from package root: source("scripts/verify_step7d2_full_v1_train.R")

options(warn = 1)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required")
if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required")

source("R/08_features.R", local = .GlobalEnv)
source("R/09_v1_preprocess.R", local = .GlobalEnv)
source("R/10_v1_rf_bridge.R", local = .GlobalEnv)
source("R/11_v1_selector.R", local = .GlobalEnv)

sha256_file <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
assert_true <- function(name, cond, detail = "") {
  if (!isTRUE(cond)) stop(sprintf("FAIL %s%s", name, if (nzchar(detail)) paste0(": ", detail) else ""), call. = FALSE)
  cat(sprintf("PASS %-72s%s\n", name, if (nzchar(detail)) paste0(" ", detail) else ""))
}
assert_equal <- function(name, actual, expected) {
  if (!identical(actual, expected)) stop(sprintf("FAIL %s", name), call. = FALSE)
  cat(sprintf("PASS %s\n", name))
}
assert_close <- function(name, actual, expected, tol = 5e-13) {
  a <- as.double(actual); e <- as.double(expected)
  if (length(a) != length(e)) stop(sprintf("FAIL %s: length mismatch", name), call. = FALSE)
  d <- if (length(a)) max(abs(a - e)) else 0
  if (!is.finite(d) || d > tol) stop(sprintf("FAIL %s: max_abs=%.17g > %.17g", name, d, tol), call. = FALSE)
  cat(sprintf("PASS %-72s max_abs=%.3e\n", name, d))
}

EXPECTED <- list(
  selector = "a5f6e6914809bcde3667c96165984a218595c92c4cbf1d98ff4b23de50be2d23",
  action = "5e943ce10c601187d46dd0f77e9059aee29c7e2710d1d8ff5acf779787983a99",
  labels = "77e202112c8d3de45aeebfdbe6a4c8d1ac9b725aac598af5974d46a3f5be4631",
  structural = "3c8dfb520d7409c6bf6dfd93a74aecb6a0281e39e4797de0ed6f49b9d059f188",
  elig = "ec10d3b12120ef36c51167721f890bbee93c5e3ad08b85b7bf0ce9a2d3ed7409",
  feature = "30dbb8b2b19f6b6cde51fb7d5da3e51ced51004d8a973986107c3724be2e28f4",
  preprocess = "5a37921120fe2a9db910deaf68244b0a675fc3c6d0ec2cb8dc02ed95e85318f5",
  rf_bridge = "a64ea65d477b88b70f654398831c169bb7c649ceb4432ee373d2d3077dd18d0b",
  rf_helper = "a51cc499f92d06da7c333af7112b35f2dae8c6327f15c6c477d22def489a6ac7",
  v1_oof = "510069e07fd8a28c21cd3ab5f04f473a5856fec559cde6ffceb48dc784188c5c",
  r2_repro = "" # loaded from oracle to avoid duplicate transcription
)

selector_py <- "reference/python/autogrey_v2_search_step5db_r2.py"
action_csv <- "reference/frozen/AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv"
labels_csv <- "reference/frozen/AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv"
helper_py <- "reference/python/ag_step7d1_sklearn_bridge.py"
canonical_v1_path <- "reference/frozen/AUTOGREY_V2_V1STYLE_OOF_STEP5D_B_R2.json"
repro_path <- "reference/frozen/AUTOGREY_V2_5DB_R2_REPRODUCIBILITY_AUDIT.json"
oracle_path <- "inst/extdata/v1_full_train_reference_step7d2.json"

assert_equal("canonical_selector_source_sha256", sha256_file(selector_py), EXPECTED$selector)
assert_equal("frozen_action_table_sha256", sha256_file(action_csv), EXPECTED$action)
assert_equal("frozen_train_labels_sha256", sha256_file(labels_csv), EXPECTED$labels)
assert_equal("step7b_structural_source_preservation", sha256_file("R/06_structural_groups.R"), EXPECTED$structural)
assert_equal("step7b_eligibility_source_preservation", sha256_file("R/07_eligibility_collision.R"), EXPECTED$elig)
assert_equal("step7c1_feature_source_preservation", sha256_file("R/08_features.R"), EXPECTED$feature)
assert_equal("step7c2_preprocess_source_preservation", sha256_file("R/09_v1_preprocess.R"), EXPECTED$preprocess)
assert_equal("step7d1_rf_bridge_source_preservation", sha256_file("R/10_v1_rf_bridge.R"), EXPECTED$rf_bridge)
assert_equal("step7d1_python_helper_preservation", sha256_file(helper_py), EXPECTED$rf_helper)
assert_equal("canonical_v1_oof_sha256", sha256_file(canonical_v1_path), EXPECTED$v1_oof)

oracle <- jsonlite::fromJSON(oracle_path, simplifyVector = TRUE)
canonical <- jsonlite::fromJSON(canonical_v1_path, simplifyVector = TRUE)
repro <- jsonlite::fromJSON(repro_path, simplifyVector = TRUE)
assert_equal("oracle_checkpoint", oracle$checkpoint, "STEP7D2_FULL_V1_TRAIN_R2_REPRODUCTION")
assert_equal("canonical_r2_reproducibility_status", repro$status, "PASS")
assert_true("canonical_r2_v1_clean_process_identity", isTRUE(oracle$canonical_r2_reproducibility_audit$v1_oof_run1_run2_identical))
assert_true("rf_contract_50_models_per_run", as.integer(oracle$rf_contract$forest_fits_per_full_run) == 50L)
assert_true("rf_contract_500_trees", as.integer(oracle$rf_contract$n_estimators) == 500L)
assert_true("rf_contract_support_20", as.integer(oracle$rf_contract$support_min_parents) == 20L)

cat("INFO checking frozen Python RF environment through R...\n")
env <- ag_rf_check_environment(helper_py)
cat(sprintf("INFO python=%s numpy=%s sklearn=%s launcher=%s\n", env$python, env$numpy, env$scikit_learn, env$launcher_source))
assert_equal("python_version_frozen", as.character(env$python), "3.13.5")
assert_equal("numpy_version_frozen", as.character(env$numpy), "2.3.5")
assert_equal("sklearn_version_frozen", as.character(env$scikit_learn), "1.8.0")
assert_true("algorithm_versions_compatible", isTRUE(env$algorithm_versions_compatible))

cat("INFO loading and rebuilding the full frozen TRAIN selector arrays in R...\n")
dat <- ag_v1_load_frozen_train(action_csv, labels_csv)
assert_true("train_action_rows_18107", length(dat$parent) == 18107L)
assert_true("train_parents_2070", length(dat$parents) == 2070L)
pc <- table(factor(dat$fold[match(dat$parents, dat$parent)], levels = 0:4))
assert_equal("parents_by_fold_421_417_413_411_408", as.integer(pc), c(421L,417L,413L,411L,408L))

# Check all 50 expected training/evaluation counts before any RF is fitted.
fg <- oracle$fold_group_models
for (i in seq_len(nrow(fg))) {
  fold <- as.integer(fg$fold[i]); g <- as.character(fg$group[i]); gi <- match(g, AG_V1_GROUPS)
  tr <- which(dat$fold != fold & dat$group_idx == gi)
  ev <- which(dat$fold == fold & dat$group_idx == gi)
  assert_true(sprintf("count_f%d_%s", fold, g),
              length(tr) == as.integer(fg$n_train[i]) && length(ev) == as.integer(fg$n_eval[i]) &&
              length(unique(dat$parent[tr])) == as.integer(fg$train_parent_count[i]))
}

cat("\n=== FULL V1 OOF RUN 1 / 2 ===\n")
r1 <- ag_v1_full_oof(dat, helper = helper_py, verbose = TRUE)
assert_true("run1_all_18107_action_predictions_finite", all(is.finite(r1$action_predictions)))
assert_true("run1_exactly_50_supported_models", sum(r1$supported_model) == 50L)
assert_true("run1_2070_decisions", nrow(r1$decisions) == 2070L)

# Canonical decisions are already sorted by parent_id; R is explicitly sorted the same way.
cd <- canonical$decisions
assert_equal("run1_parent_ids_2070_exact", as.character(r1$decisions$parent_id), as.character(cd$parent_id))
assert_equal("run1_fold_identity_exact", as.integer(r1$decisions$fold), as.integer(cd$fold))
assert_equal("run1_support_identity_exact", as.integer(r1$decisions$supported), as.integer(cd$supported))
choice_match <- as.character(r1$decisions$choice) == as.character(cd$choice)
assert_true("run1_choices_2070_of_2070_exact", sum(choice_match) == 2070L,
            sprintf("matches=%d/2070", sum(choice_match)))
assert_close("run1_regret_identity", r1$decisions$regret, as.double(cd$regret), 1e-15)

m1 <- ag_v1_metrics_core(r1$decisions)
cm <- canonical$metrics
assert_true("run1_supported_2070", m1$n_supported == 2070L)
assert_close("run1_support_coverage", m1$support_coverage, cm$support_coverage, 0)
assert_close("run1_mean_regret", m1$mean_regret, cm$mean_regret, 5e-13)
assert_close("run1_median_regret", m1$median_regret, cm$median_regret, 5e-13)
assert_close("run1_cvar90", m1$cvar90, cm$cvar90, 5e-13)
assert_close("run1_p90_regret", m1$p90_regret, cm$p90_regret, 5e-13)
assert_close("run1_zero_regret_rate", m1$zero_regret_rate, cm$zero_regret_rate, 5e-13)
canon_counts <- setNames(as.integer(unlist(cm$selection_counts[AG_V1_GROUPS], use.names = FALSE)), AG_V1_GROUPS)
assert_equal("run1_selection_counts_exact", m1$selection_counts, canon_counts)
cat(sprintf("INFO run1 frozen V1 mean=%.15f CVaR90=%.15f p90=%.15f\n", m1$mean_regret, m1$cvar90, m1$p90_regret))
cat("INFO global_same_tasks/rho/J fields are carried in the frozen artifact but are NOT recomputed in Step7D2; GLOBAL reproduction remains Step7E1.\n")

cat("\n=== FULL V1 OOF RUN 2 / 2 (DETERMINISM GATE) ===\n")
r2 <- ag_v1_full_oof(dat, helper = helper_py, verbose = TRUE)
assert_true("run2_all_18107_action_predictions_finite", all(is.finite(r2$action_predictions)))
assert_equal("repeat_parent_ids_exact", as.character(r2$decisions$parent_id), as.character(r1$decisions$parent_id))
assert_equal("repeat_choices_2070_exact", as.character(r2$decisions$choice), as.character(r1$decisions$choice))
assert_close("repeat_action_predictions", r2$action_predictions, r1$action_predictions, 2e-14)
# The first bootstrap stream hash for every fold/group model must be identical across runs.
h1 <- vapply(r1$model_audit, function(z) as.character(z$bootstrap_hash_first), character(1))
h2 <- vapply(r2$model_audit, function(z) as.character(z$bootstrap_hash_first), character(1))
assert_equal("repeat_50_model_bootstrap_first_hashes_exact", h2, h1)

# Write a compact local reproduction output for audit use; no target sets beyond TRAIN are touched.
dir.create("outputs", showWarnings = FALSE)
utils::write.csv(r1$decisions, "outputs/AUTOGREY_STEP7D2_V1_OOF_DECISIONS_R.csv", row.names = FALSE, quote = TRUE)
out_metrics <- list(
  checkpoint = "STEP7D2_FULL_V1_TRAIN_R2_REPRODUCTION",
  status = "PASS",
  choice_matches = 2070L,
  metrics = m1,
  canonical_v1_oof_sha256 = EXPECTED$v1_oof,
  deferred = c("GLOBAL_RANK_REPRODUCTION", "CAL", "LOCKTEST", "REALBENCH2_PRETARGET", "TARGET_OPENING", "BOOTSTRAP")
)
jsonlite::write_json(out_metrics, "outputs/AUTOGREY_STEP7D2_V1_OOF_METRICS_R.json", auto_unbox = TRUE, pretty = TRUE, digits = 17)
cat(sprintf("INFO wrote %s\n", normalizePath("outputs/AUTOGREY_STEP7D2_V1_OOF_DECISIONS_R.csv", winslash = "/", mustWork = TRUE)))
cat(sprintf("INFO wrote %s\n", normalizePath("outputs/AUTOGREY_STEP7D2_V1_OOF_METRICS_R.json", winslash = "/", mustWork = TRUE)))

cat("\nSTEP7D2_FULL_V1_TRAIN_R2_PARITY: PASS\n")
