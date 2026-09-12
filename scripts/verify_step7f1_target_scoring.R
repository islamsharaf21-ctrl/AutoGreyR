options(stringsAsFactors = FALSE)

if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required", call. = FALSE)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required", call. = FALSE)

source("R/01_utils.R")
source("R/04_mase.R")
source("R/10_v1_rf_bridge.R")
source("R/15_realbench2_target_scoring.R")

pass <- function(label, detail = "") {
  cat(sprintf("PASS %-72s%s\n", label, if (nzchar(detail)) paste0(" ", detail) else ""))
}
fail <- function(label, detail = "") {
  stop(sprintf("FAIL %s%s", label, if (nzchar(detail)) paste0(": ", detail) else ""), call. = FALSE)
}
exact <- function(label, actual, expected) {
  if (!identical(actual, expected)) {
    if (length(actual) != length(expected)) {
      fail(label, sprintf("length actual=%d expected=%d", length(actual), length(expected)))
    }
    same <- (is.na(actual) & is.na(expected)) | (!is.na(actual) & !is.na(expected) & actual == expected)
    bad <- which(!same)
    if (length(bad)) {
      j <- bad[[1L]]
      fail(label, sprintf("first_mismatch=%d actual=%s expected=%s", j, as.character(actual[[j]]), as.character(expected[[j]])))
    }
    fail(label, "attributes/types differ")
  }
  pass(label)
}
near_norm <- function(label, actual, expected, tol = 5e-12) {
  a <- as.double(actual); e <- as.double(expected)
  if (length(a) != length(e) || any(!is.finite(a)) || any(!is.finite(e))) fail(label, "shape/nonfinite")
  d <- abs(a - e) / pmax(1.0, abs(e))
  mx <- if (length(d)) max(d) else 0
  if (!is.finite(mx) || mx > tol) fail(label, sprintf("max_normalized=%.17g tol=%.17g", mx, tol))
  pass(label, sprintf("max_normalized=%.3e", mx))
  invisible(mx)
}
sha <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)

EXPECTED <- list(
  pretarget = "9a5c9aa2c0595225b47985e950d09f238d04fb6ba4c25f34f8ab15a01bc25d33",
  opening_lock = "5b1e9aad44068f19dce12b3371dd82c042169c0e442c39c98273cf14d2e77d27",
  scoring_lock = "2b98cb4be40809269d37c5552a376e9e4601467156ffc0326bd3b19c10a45dea",
  score_harness = "c5a6d8dbe0109bc8557dcfcc6333f1f254d5ef106389a43cb00fe23487732f02",
  raw_bundle = "85aac5e92b5d6b0db2299d319d096a5a4b274369cbfeabf7c79e2dc706b0f4f9",
  step7e2_contract = "61173edb5f6fe0779e3eaa4da51cc40a6a488a82df37e8b918b333c630cfe617",
  target_helper = "a66a095b46832a7bd31095215ae31964fbc6598683aa4c713e9960e466d9e79d",
  canonical_forecast_index = "557d065d4d1f18a8a6fbf858aa8101bbc7fa4db556399b2670b46f83bc0f0509",
  canonical_forecast_binary = "5f4e92f0aa98f2a2d765f5cf50cf4ec7bbecdaf8b1980849af559d1ac8f83034",
  decision_oracle = "f62d93b49610c11bef6a16813833bfb40c9af4683db041f39212ceff0692bd80",
  loss_oracle = "5baf1820234a4875ff4bca4283e37755213ad02d6d339382134154d99b93f0e3",
  target_open_oracle = "e53f33914e2a2497d1a7985aa5ef8fdc9d77c0caff8892d5c05a7564fc0cc08d",
  step7f1_oracle = "f77adf7f5e760a303e8d03b233e5da9b756778da9dc47ed3394065a0abd64d5e",
  runtime_D_binary = "903c37d1ff20796a61b077b97591d24961237b433b9fb92a91ade32ed88be81a",
  runtime_Y_binary = "4b1a6e9983b9e0fc1ead0c6b6877784737b54780e18a4bc82bb8c9362c0879dc"
)

# Frozen lineage gates.
exact("pretarget_sha256", sha("reference/frozen_step5f/AUTOGREY_REALBENCH2_PRETARGET_STEP5F.json"), EXPECTED$pretarget)
exact("opening_lock_sha256", sha("reference/frozen_step5f/AUTOGREY_REALBENCH2_OPENING_LOCK_STEP5F.json"), EXPECTED$opening_lock)
exact("scoring_implementation_lock_sha256", sha("reference/frozen_step5f/AUTOGREY_STEP5F_SCORING_IMPLEMENTATION_LOCK.json"), EXPECTED$scoring_lock)
exact("canonical_score_harness_sha256", sha("reference/frozen_step5f/autogrey_v2_realbench2_step5f_score.py"), EXPECTED$score_harness)
exact("raw_bundle_sha256", sha("reference/raw/AUTOGREY_REALBENCH2_RAW_RESERVATION_BUNDLE_STEP5B.zip"), EXPECTED$raw_bundle)
exact("step7e2_platform_contract_sha256", sha("AUTOGREY_STEP7E2_PLATFORM_CONTRACT_R8.json"), EXPECTED$step7e2_contract)
exact("target_open_helper_sha256", sha("reference/python/ag_step7f1_target_open_bridge.py"), EXPECTED$target_helper)
exact("canonical_forecast_index_sha256", sha("reference/frozen_step7f1/AUTOGREY_STEP7F1_CANONICAL_FORECAST_INDEX.csv"), EXPECTED$canonical_forecast_index)
exact("canonical_forecast_binary_sha256", sha("reference/frozen_step7f1/AUTOGREY_STEP7F1_CANONICAL_FORECASTS_LINUX.f64le"), EXPECTED$canonical_forecast_binary)
exact("decision_oracle_sha256", sha("reference/frozen_step7f1/AUTOGREY_STEP7F1_DECISIONS_ORACLE.csv"), EXPECTED$decision_oracle)
exact("loss_oracle_sha256", sha("reference/frozen_step7f1/AUTOGREY_STEP7F1_ELIGIBLE_LOSSES_ORACLE.csv"), EXPECTED$loss_oracle)
exact("target_open_oracle_sha256", sha("reference/frozen_step7f1/AUTOGREY_STEP7F1_TARGET_OPEN_ORACLE.csv"), EXPECTED$target_open_oracle)
exact("step7f1_oracle_sha256", sha("reference/frozen_step7f1/AUTOGREY_STEP7F1_ORACLE.json"), EXPECTED$step7f1_oracle)

# Preserve the already-verified scientific stack.
preserved <- c(
  "R/06_structural_groups.R" = "3c8dfb520d7409c6bf6dfd93a74aecb6a0281e39e4797de0ed6f49b9d059f188",
  "R/07_eligibility_collision.R" = "ec10d3b12120ef36c51167721f890bbee93c5e3ad08b85b7bf0ce9a2d3ed7409",
  "R/08_features.R" = "30dbb8b2b19f6b6cde51fb7d5da3e51ced51004d8a973986107c3724be2e28f4",
  "R/09_v1_preprocess.R" = "5a37921120fe2a9db910deaf68244b0a675fc3c6d0ec2cb8dc02ed95e85318f5",
  "R/10_v1_rf_bridge.R" = "a64ea65d477b88b70f654398831c169bb7c649ceb4432ee373d2d3077dd18d0b",
  "R/11_v1_selector.R" = "4892929fed7b8b62bb6b1009192a6777e04e9bcccc9785a61b0b3776ff07b828",
  "R/12_global_rank.R" = "fb18da88a3dcee86e97b050dc053679c5c54878855a4152bd4cc1e9201be0ebd",
  "R/13_realbench2_pretarget.R" = "a0f584c784cfd86d66926cdaa40ea63489efda67c45ff5d14aab04327dbe2271",
  "R/14_step7e2_canonical_bridge.R" = "7c773506d8f6a5436192f98010d8b8678610d2beb5230213ce8095ee46e75192"
)
for (p in names(preserved)) exact(paste0("preserve_", basename(p)), sha(p), unname(preserved[[p]]))

# Confirm Step7F1 scoring code is not a hidden refit/bootstrap/oracle-reader.
score_src <- paste(readLines("R/15_realbench2_target_scoring.R", warn = FALSE), collapse = "\n")
for (needle in c("sample(", "runif(", "rnorm(", "set.seed(", "RNGkind(")) {
  if (grepl(needle, score_src, fixed = TRUE)) fail("step7f1_no_rng_source_guard", needle)
}
for (needle in c("AUTOGREY_STEP7F1_DECISIONS_ORACLE.csv", "AUTOGREY_STEP7F1_ELIGIBLE_LOSSES_ORACLE.csv")) {
  if (grepl(needle, score_src, fixed = TRUE)) fail("step7f1_scoring_does_not_read_result_oracles", needle)
}
pass("step7f1_no_rng_or_bootstrap_execution_source_guard")
pass("step7f1_scoring_does_not_read_result_oracles")

lock <- jsonlite::fromJSON("reference/frozen_step5f/AUTOGREY_REALBENCH2_OPENING_LOCK_STEP5F.json", simplifyVector = TRUE)
exact("opening_lock_status", as.character(lock$status), "FROZEN_BEFORE_TARGET_NUMERIC_OPENING")
exact("opening_lock_pretarget_binding", as.character(lock$pretarget_sha256), EXPECTED$pretarget)
exact("opening_lock_score_harness_binding", as.character(lock$score_harness_sha256), EXPECTED$score_harness)
exact("opening_lock_scoring_lock_binding", as.character(lock$scoring_implementation_lock_sha256), EXPECTED$scoring_lock)
exact("opening_lock_actionable_2496", as.integer(lock$actionable_parent_count), 2496L)
exact("opening_lock_refusals_15", as.integer(lock$refusal_count), 15L)
exact("bootstrap_contract_carried_forward_not_run", c(as.integer(lock$bootstrap_replicates), as.integer(lock$bootstrap_seed)), c(4000L, 46073L))

cat("INFO checking frozen Python environment for canonical target parsing...\n")
env <- ag_rf_check_environment()
cat(sprintf("INFO python=%s numpy=%s sklearn=%s launcher=%s\n", as.character(env$python), as.character(env$numpy), as.character(env$scikit_learn), as.character(env$launcher_source)))
exact("python_version_frozen", as.character(env$python), "3.13.5")
exact("numpy_version_frozen", as.character(env$numpy), "2.3.5")
exact("sklearn_version_frozen", as.character(env$scikit_learn), "1.8.0")

cat("\n=== STEP 7F1 FORMAL REPRODUCTION TARGET OPENING / DETERMINISTIC SCORING ===\n")
cat("INFO No refit or decision change is permitted. Bootstrap remains NOT RUN.\n")
res <- ag_step7f1_score_frozen_targets(verbose = TRUE)

# Target-opening binary identity must reproduce the canonical Python parser exactly.
cat(sprintf("INFO target bridge index SHA=%s (numeric scale text may be platform-formatted)\n", as.character(res$target_bridge_hashes$index_sha256)))
target_ref <- utils::read.csv("reference/frozen_step7f1/AUTOGREY_STEP7F1_TARGET_OPEN_ORACLE.csv", stringsAsFactors = FALSE, check.names = FALSE, colClasses = "character", na.strings = character(0))
target_idx <- res$target_index
exact("target_open_parent_ids_2496_exact", as.character(target_idx$parent_id), as.character(target_ref$parent_id))
for (col in c("source_id", "series_id", "h", "M", "N", "n_D", "development_sha256", "target_raw_sha256", "target_float64_sha256")) exact(paste0("target_open_", col, "_exact"), as.character(target_idx[[col]]), as.character(target_ref[[col]]))
near_norm("target_open_mase_scale_canonical", as.double(target_idx$mase_scale), as.double(target_ref$mase_scale), tol = 5e-12)
exact("target_bridge_D_binary_sha256", as.character(res$target_bridge_hashes$d_binary_sha256), EXPECTED$runtime_D_binary)
exact("target_bridge_Y_binary_sha256", as.character(res$target_bridge_hashes$y_binary_sha256), EXPECTED$runtime_Y_binary)
if (!is.finite(res$mase_scale_max_normalized_difference) || res$mase_scale_max_normalized_difference > 5e-12) {
  fail("R_vs_canonical_MASE_scale", sprintf("max_normalized=%.17g", res$mase_scale_max_normalized_difference))
}
pass("R_vs_canonical_MASE_scale", sprintf("max_normalized=%.3e", res$mase_scale_max_normalized_difference))

# Full eligible loss surface: 23,572 rows.
loss_ref <- utils::read.csv("reference/frozen_step7f1/AUTOGREY_STEP7F1_ELIGIBLE_LOSSES_ORACLE.csv", stringsAsFactors = FALSE, check.names = FALSE)
loss_r <- res$losses
exact("eligible_loss_rows_23572", nrow(loss_r), 23572L)
for (col in c("parent_id", "source_id", "series_id", "group", "selected_config_id")) exact(paste0("eligible_loss_", col, "_exact"), as.character(loss_r[[col]]), as.character(loss_ref[[col]]))
exact("eligible_loss_h_exact", as.integer(loss_r$h), as.integer(loss_ref$h))
near_norm("eligible_loss_mase_all_23572", loss_r$mase, loss_ref$mase, tol = 5e-12)

# Per-parent deterministic decisions/loss/regret: exact identities + tight numeric parity.
dec_ref <- utils::read.csv("reference/frozen_step7f1/AUTOGREY_STEP7F1_DECISIONS_ORACLE.csv", stringsAsFactors = FALSE, check.names = FALSE)
dec_r <- res$decisions
exact("decision_rows_2496", nrow(dec_r), 2496L)
for (col in c("parent_id", "source_id", "dataset", "series_id", "frequency", "v1_choice", "global_choice")) exact(paste0("decision_", col, "_exact"), as.character(dec_r[[col]]), as.character(dec_ref[[col]]))
for (col in c("h", "N", "n_D", "eligible_count")) exact(paste0("decision_", col, "_exact"), as.integer(dec_r[[col]]), as.integer(dec_ref[[col]]))
# M is blank/NA for nonseasonal rows; compare normalized character form.
norm_m <- function(x) ifelse(is.na(x) | as.character(x) == "", "", as.character(as.integer(x)))
exact("decision_M_exact", norm_m(dec_r$M), norm_m(dec_ref$M))
for (col in c("v1_loss_mase", "v1_regret", "global_loss_mase", "global_regret", "eligible_oracle_mase")) near_norm(paste0("decision_", col, "_2496"), dec_r[[col]], dec_ref[[col]], tol = 5e-12)

oracle <- jsonlite::fromJSON("reference/frozen_step7f1/AUTOGREY_STEP7F1_ORACLE.json", simplifyVector = TRUE)
exact("oracle_status", as.character(oracle$status), "PASS")
exact("oracle_actionable_2496", as.integer(oracle$actionable_count), 2496L)
exact("oracle_eligible_actions_23572", as.integer(oracle$eligible_action_rows), 23572L)

metric_fields <- c("support_coverage", "mean_regret", "median_regret", "cvar90", "p90_regret", "zero_regret_rate")
for (nm in metric_fields) near_norm(paste0("primary_metric_", nm), res$primary_metrics[[nm]], oracle$primary_metrics[[nm]], tol = 5e-12)
for (nm in metric_fields) near_norm(paste0("global_metric_", nm), res$global_metrics[[nm]], oracle$global_metrics[[nm]], tol = 5e-12)
exact("primary_n_tasks_2496", as.integer(res$primary_metrics$n_tasks), 2496L)
exact("global_n_tasks_2496", as.integer(res$global_metrics$n_tasks), 2496L)
pc_a <- unlist(res$primary_metrics$selection_counts, use.names = TRUE); pc_e <- unlist(oracle$primary_metrics$selection_counts, use.names = TRUE)
exact("primary_selection_count_names_exact", names(pc_a), names(pc_e)); exact("primary_selection_counts_exact", as.integer(pc_a), as.integer(pc_e))
gc_a <- unlist(res$global_metrics$selection_counts, use.names = TRUE); gc_e <- unlist(oracle$global_metrics$selection_counts, use.names = TRUE)
exact("global_selection_count_names_exact", names(gc_a), names(gc_e)); exact("global_selection_counts_exact", as.integer(gc_a), as.integer(gc_e))
near_norm("point_estimand_mean_delta", res$estimands$mean_regret_delta_primary_minus_global, oracle$estimands$mean_regret_delta_primary_minus_global, tol = 5e-12)
near_norm("point_estimand_cvar90_delta", res$estimands$cvar90_regret_delta_primary_minus_global, oracle$estimands$cvar90_regret_delta_primary_minus_global, tol = 5e-12)

cat(sprintf("INFO deterministic V1 mean regret=%.15f GLOBAL=%.15f delta=%.15f\n", res$primary_metrics$mean_regret, res$global_metrics$mean_regret, res$estimands$mean_regret_delta_primary_minus_global))
cat(sprintf("INFO deterministic V1 CVaR90=%.15f GLOBAL=%.15f delta=%.15f\n", res$primary_metrics$cvar90, res$global_metrics$cvar90, res$estimands$cvar90_regret_delta_primary_minus_global))
cat("INFO These point estimates favor V1, but robust-superiority CI claims are NOT evaluated until Step7F2.\n")

# Write audit outputs only after parity gates pass.
dir.create("outputs", showWarnings = FALSE, recursive = TRUE)
utils::write.csv(loss_r, "outputs/AUTOGREY_STEP7F1_ELIGIBLE_LOSSES_R.csv", row.names = FALSE, na = "")
utils::write.csv(dec_r, "outputs/AUTOGREY_STEP7F1_DECISIONS_R.csv", row.names = FALSE, na = "")
summary_out <- list(
  checkpoint = "STEP7F1_FROZEN_TARGET_SCORING_R",
  status = "PASS",
  primary_metrics = res$primary_metrics,
  global_metrics = res$global_metrics,
  estimands = res$estimands,
  target_bridge_hashes = res$target_bridge_hashes,
  chronology = list(
    frozen_pretarget_decisions_used = TRUE,
    canonical_linux_pretarget_forecasts_used = TRUE,
    target_commitments_verified_before_numeric_parse = TRUE,
    refusal_targets_numeric_parsed = FALSE,
    post_target_refit_or_decision_change = FALSE,
    bootstrap_run = FALSE,
    step7f2_status = "NOT_STARTED"
  )
)
jsonlite::write_json(summary_out, "outputs/AUTOGREY_STEP7F1_TARGET_SCORING_R.json", pretty = TRUE, auto_unbox = TRUE, digits = 17)
pass("step7f1_outputs_written")
pass("bootstrap_not_run_step7f1")
cat("INFO Step7F2 PCG64 bootstrap remains NOT STARTED.\n")
cat("\nSTEP7F1_FROZEN_TARGET_SCORING_PARITY: PASS\n")
