options(stringsAsFactors = FALSE, warn = 1)
need <- c("jsonlite", "digest")
miss <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) stop(paste0("Missing R package(s): ", paste(miss, collapse = ", ")), call. = FALSE)
for (f in c(
  "R/01_utils.R", "R/04_mase.R", "R/05_grey_common.R",
  "R/06_structural_groups.R", "R/07_eligibility_collision.R", "R/08_features.R",
  "R/09_v1_preprocess.R", "R/10_v1_rf_bridge.R", "R/11_v1_selector.R",
  "R/12_global_rank.R", "R/13_realbench2_pretarget.R", "R/14_step7e2_canonical_bridge.R"
)) source(f, local = .GlobalEnv)

sha <- function(p) digest::digest(file = p, algo = "sha256", serialize = FALSE)
pass <- function(x) cat(sprintf("PASS %-72s\n", x))
exact <- function(name, a, b) {
  if (!identical(a, b)) stop(paste0("FAIL ", name), call. = FALSE)
  pass(name)
}
close_scaled <- function(name, a, b, atol = 0, rtol = 0) {
  a <- as.double(a); b <- as.double(b)
  if (length(a) != length(b)) stop(paste0("FAIL ", name, " length"), call. = FALSE)
  d <- if (length(a)) max(abs(a - b)) else 0
  scale <- if (length(a)) max(1, max(abs(b))) else 1
  lim <- atol + rtol * scale
  if (!is.finite(d) || d > lim) stop(sprintf("FAIL %s: max_abs=%.17g > %.17g scale=%.6g", name, d, lim, scale), call. = FALSE)
  cat(sprintf("PASS %-72s max_abs=%.3e\n", name, d))
  invisible(d)
}
oracle <- jsonlite::fromJSON("AUTOGREY_STEP7E2_ORACLE.json", simplifyVector = FALSE)
canon <- jsonlite::fromJSON("reference/frozen_step5f/AUTOGREY_REALBENCH2_PRETARGET_STEP5F.json", simplifyVector = FALSE)

# Step7E2 R8 cross-platform contract. Linux/OpenBLAS is the byte-exact canonical
# reference. Windows CPython/NumPy is qualified numerically against the frozen
# Linux float64 forecasts for SG02/SG05 only; all discrete scientific decisions
# remain exact and held-out targets remain sealed.
platform_contract_path <- "AUTOGREY_STEP7E2_PLATFORM_CONTRACT_R8.json"
canonical_sensitive_index_path <- "reference/frozen_step5f/AUTOGREY_STEP7E2_SENSITIVE_FORECAST_CANONICAL_LINUX_R7.csv"
canonical_sensitive_binary_path <- "reference/frozen_step5f/AUTOGREY_STEP7E2_SENSITIVE_FORECAST_CANONICAL_LINUX_R7.f64le"
platform_contract <- jsonlite::fromJSON(platform_contract_path, simplifyVector = FALSE)
canonical_sensitive_index <- utils::read.csv(
  canonical_sensitive_index_path, stringsAsFactors = FALSE, check.names = FALSE,
  colClasses = "character", na.strings = character(0)
)
canonical_sensitive_key <- paste(canonical_sensitive_index$parent_id, canonical_sensitive_index$group, sep = "\r")
if (anyDuplicated(canonical_sensitive_key)) stop("FAIL canonical sensitive index duplicate key", call. = FALSE)
canonical_sensitive_values <- ag_step7e2_read_f64le(canonical_sensitive_binary_path)
get_canonical_sensitive_forecast <- function(parent_id, group, config_id, h) {
  j <- match(paste(parent_id, group, sep = "\r"), canonical_sensitive_key)
  if (is.na(j)) stop(sprintf("FAIL canonical sensitive index missing parent=%s group=%s", parent_id, group), call. = FALSE)
  r <- canonical_sensitive_index[j, , drop = FALSE]
  if (!identical(as.character(r$config_id[[1L]]), as.character(config_id)) ||
      as.integer(r$h[[1L]]) != as.integer(h)) {
    stop(sprintf("FAIL canonical sensitive metadata parent=%s group=%s", parent_id, group), call. = FALSE)
  }
  nf <- as.integer(r$n_forecast[[1L]]); off <- as.numeric(r$offset_bytes[[1L]])
  if (is.na(nf) || nf != as.integer(h) || !is.finite(off) || off < 0 || off != floor(off) || (off %% 8) != 0) {
    stop(sprintf("FAIL canonical sensitive geometry parent=%s group=%s", parent_id, group), call. = FALSE)
  }
  lo <- as.integer(off / 8) + 1L; hi <- lo + nf - 1L
  if (lo < 1L || hi > length(canonical_sensitive_values)) stop("FAIL canonical sensitive bounds", call. = FALSE)
  canonical_sensitive_values[lo:hi]
}

# ---------------------------------------------------------------------------
# Immutable provenance + closed-parent preservation
# ---------------------------------------------------------------------------
exact("canonical_pretarget_sha256",
      sha("reference/frozen_step5f/AUTOGREY_REALBENCH2_PRETARGET_STEP5F.json"),
      oracle$canonical_pretarget_sha256)
exact("canonical_opening_lock_sha256",
      sha("reference/frozen_step5f/AUTOGREY_REALBENCH2_OPENING_LOCK_STEP5F.json"),
      oracle$canonical_opening_lock_sha256)
exact("canonical_pretarget_harness_sha256",
      sha("reference/python/autogrey_v2_realbench2_step5f_pretarget_r1.py"),
      oracle$canonical_pretarget_harness_sha256)
exact("raw_reservation_bundle_sha256",
      sha("reference/raw/AUTOGREY_REALBENCH2_RAW_RESERVATION_BUNDLE_STEP5B.zip"),
      oracle$raw_bundle_sha256)
exact("step5e_results_sha256",
      sha("reference/frozen_step5f/AUTOGREY_V2_LOCKTEST_RESULTS_STEP5E.json"),
      oracle$step5e_results_sha256)

expected_hashes <- c(
  "R/06_structural_groups.R" = "3c8dfb520d7409c6bf6dfd93a74aecb6a0281e39e4797de0ed6f49b9d059f188",
  "R/07_eligibility_collision.R" = "ec10d3b12120ef36c51167721f890bbee93c5e3ad08b85b7bf0ce9a2d3ed7409",
  "R/08_features.R" = "30dbb8b2b19f6b6cde51fb7d5da3e51ced51004d8a973986107c3724be2e28f4",
  "R/09_v1_preprocess.R" = "5a37921120fe2a9db910deaf68244b0a675fc3c6d0ec2cb8dc02ed95e85318f5",
  "R/10_v1_rf_bridge.R" = "a64ea65d477b88b70f654398831c169bb7c649ceb4432ee373d2d3077dd18d0b",
  "R/11_v1_selector.R" = "4892929fed7b8b62bb6b1009192a6777e04e9bcccc9785a61b0b3776ff07b828",
  "R/12_global_rank.R" = "fb18da88a3dcee86e97b050dc053679c5c54878855a4152bd4cc1e9201be0ebd",
  "R/13_realbench2_pretarget.R" = "a0f584c784cfd86d66926cdaa40ea63489efda67c45ff5d14aab04327dbe2271"
)
for (p in names(expected_hashes)) exact(paste0("preserve_", basename(p)), sha(p), unname(expected_hashes[[p]]))
exact("canonical_engine_sha256",
      sha("reference/python/autogrey_engine_step4fb_r1.py"),
      "01c745d8a627748748f82916a576efbee231a2f87d66c314d57947dbede67974")
exact("canonical_d_bridge_sha256",
      sha("reference/python/ag_step7e2_canonical_d_bridge.py"),
      "a53525378711b7d0514b9bcbc338644065096e0e796cfb25a38972d9479154b5")
exact("sensitive_forecast_bridge_sha256",
      sha("reference/python/ag_step7e2_sensitive_forecast_bridge.py"),
      "1b7d8410810d81cb4107e3e37ab5909737ad6939b284ac3ed21dc445d0bfadfa")
exact("canonical_bridge_R14_sha256",
      sha("R/14_step7e2_canonical_bridge.R"),
      "7c773506d8f6a5436192f98010d8b8678610d2beb5230213ce8095ee46e75192")
exact("independent_sensitive_bridge_audit_status",
      jsonlite::fromJSON("AUTOGREY_STEP7E2_R5_SENSITIVE_BRIDGE_AUDIT.json")$result,
      "PASS")
exact("platform_contract_R8_sha256", sha(platform_contract_path),
      "61173edb5f6fe0779e3eaa4da51cc40a6a488a82df37e8b918b333c630cfe617")
exact("canonical_sensitive_linux_index_sha256", sha(canonical_sensitive_index_path),
      "b04714ba5f1d7293f0ea83d5983a227113504c3dfdf524a85394d565ae8c5af7")
exact("canonical_sensitive_linux_binary_sha256", sha(canonical_sensitive_binary_path),
      "c6e473e96971d32f4f7edb0b363558ad764359a8006ea9286ca50f4d88b6757c")
exact("canonical_sensitive_rows_4826", nrow(canonical_sensitive_index), 4826L)
exact("canonical_sensitive_SG02_2410", sum(canonical_sensitive_index$group == "SG02_DISCRETE_POLY"), 2410L)
exact("canonical_sensitive_SG05_2416", sum(canonical_sensitive_index$group == "SG05_CONT_TIME_POLY"), 2416L)
pass("canonical_sensitive_unique_parent_group_keys")

# Chronology source guards. No target numeric conversion is permitted.
src13 <- paste(readLines("R/13_realbench2_pretarget.R", warn = FALSE), collapse = "\n")
src14 <- paste(readLines("R/14_step7e2_canonical_bridge.R", warn = FALSE), collapse = "\n")
py_d <- paste(readLines("reference/python/ag_step7e2_canonical_d_bridge.py", warn = FALSE), collapse = "\n")
py_s <- paste(readLines("reference/python/ag_step7e2_sensitive_forecast_bridge.py", warn = FALSE), collapse = "\n")
if (grepl("as\\.(double|numeric|integer)\\s*\\(\\s*target_tokens", src13, perl = TRUE) ||
    grepl("as\\.(double|numeric|integer)\\s*\\(\\s*target_tokens", src14, perl = TRUE)) {
  stop("FAIL target-token numeric-conversion source guard", call. = FALSE)
}
pass("target_tokens_never_numeric_converted_R_source_guard")
if (grepl("float\\s*\\(\\s*(target|target_tokens)", py_d, perl = TRUE) ||
    grepl("asarray\\s*\\(\\s*(target|target_tokens)", py_d, perl = TRUE)) {
  stop("FAIL canonical-D helper target numeric conversion", call. = FALSE)
}
pass("canonical_d_bridge_development_only_source_guard")
if (grepl("target_tokens|target_raw|heldout|held_out", py_s, perl = TRUE, ignore.case = TRUE)) {
  # Docstrings may mention the word 'target'; only names suggesting actual target input are forbidden.
  bad <- grepl("target_tokens|target_raw|heldout|held_out", py_s, perl = TRUE, ignore.case = TRUE)
  if (bad) stop("FAIL sensitive forecast bridge appears to accept held-out target material", call. = FALSE)
}
pass("sensitive_forecast_bridge_development_only_source_guard")
if (!identical(canon$chronology$target_tokens_numeric_parsed, FALSE) ||
    !identical(canon$chronology$target_losses_computed, FALSE) ||
    !identical(canon$chronology$outcomes_opened, FALSE)) {
  stop("FAIL canonical chronology is not pretarget", call. = FALSE)
}
pass("canonical_chronology_targets_sealed")

# ---------------------------------------------------------------------------
# Frozen Python environment
# ---------------------------------------------------------------------------
cat("INFO checking frozen Python environment through R...\n")
env <- ag_rf_check_environment()
cat(sprintf("INFO python=%s numpy=%s sklearn=%s launcher=%s\n",
            as.character(env$python), as.character(env$numpy),
            as.character(env$scikit_learn), as.character(env$launcher_source)))
exact("python_version_frozen", as.character(env$python), "3.13.5")
exact("numpy_version_frozen", as.character(env$numpy), "2.3.5")
exact("sklearn_version_frozen", as.character(env$scikit_learn), "1.8.0")
exact("algorithm_versions_compatible", isTRUE(env$algorithm_versions_compatible), TRUE)

# ---------------------------------------------------------------------------
# Canonical-D + R structural/selector reproduction + SG02/SG05 canonical bridge
# ---------------------------------------------------------------------------
cat("\n=== REALBENCH2 PRETARGET R8 CROSS-PLATFORM FINAL PARITY (TARGETS SEALED) ===\n")
res <- ag_rb2_pretarget_reproduce_canonical(verbose = TRUE)
dec <- res$decisions; refus <- res$refusals
ref <- canon$decisions; rref <- canon$refusals

exact("reservation_count_2511", nrow(res$reservations), 2511L)
exact("actionable_count_2496", length(dec), 2496L)
exact("refusal_count_15", length(refus), 15L)
exact("sensitive_bridge_requests_4826", as.integer(res$sensitive_bridge_request_count), 4826L)
exact("sensitive_bridge_SG02_requests_2410", as.integer(res$sensitive_bridge_counts[["SG02_DISCRETE_POLY"]]), 2410L)
exact("sensitive_bridge_SG05_requests_2416", as.integer(res$sensitive_bridge_counts[["SG05_CONT_TIME_POLY"]]), 2416L)

pid <- vapply(dec, `[[`, character(1), "parent_id")
rpid <- vapply(ref, `[[`, character(1), "parent_id")
exact("actionable_parent_ids_exact", pid, rpid)
frid <- if (length(refus)) vapply(refus, `[[`, character(1), "parent_id") else character(0)
frrid <- if (length(rref)) vapply(rref, `[[`, character(1), "parent_id") else character(0)
exact("refusal_parent_ids_exact", frid, frrid)

# Full-TRAIN GLOBAL handoff remains the already-verified Step7E1 contract.
exact("full_train_global_rank_exact", as.character(res$global_rank), as.character(oracle$expected$full_train_global_rank))
gm_exp <- as.double(unlist(oracle$expected$full_train_global_means, use.names = TRUE)[AG_V1_GROUPS])
gm_got <- as.double(res$global_means[AG_V1_GROUPS])
close_scaled("full_train_global_means", gm_got, gm_exp,
             atol = 0, rtol = as.double(oracle$tolerances$global_mean_rel))
gs_exp <- as.integer(unlist(oracle$expected$full_train_group_support, use.names = TRUE)[AG_V1_GROUPS])
exact("full_train_group_support_exact", as.integer(res$global_support[AG_V1_GROUPS]), gs_exp)

# Refusals: exact reason and target commitment, no outcome opening.
for (i in seq_along(refus)) {
  a <- refus[[i]]; b <- rref[[i]]
  exact(paste0("refusal_reason_", i), as.character(a$reason), as.character(b$reason))
  exact(paste0("refusal_target_sha_", i), as.character(a$target_raw_sha256), as.character(b$target_raw_sha256))
}
pass("all_15_refusal_reasons_and_target_commitments_exact")

# Decision-level parity.
max_fore <- setNames(rep(0, length(AG_V1_GROUPS)), AG_V1_GROUPS)
max_fore_rel <- setNames(rep(0, length(AG_V1_GROUPS)), AG_V1_GROUPS)
max_score <- 0
sensitive_exact <- setNames(integer(length(AG_STEP7E2_SENSITIVE_GROUPS)), AG_STEP7E2_SENSITIVE_GROUPS)
sensitive_arrays <- setNames(integer(length(AG_STEP7E2_SENSITIVE_GROUPS)), AG_STEP7E2_SENSITIVE_GROUPS)
sensitive_nonexact_values <- setNames(integer(length(AG_STEP7E2_SENSITIVE_GROUPS)), AG_STEP7E2_SENSITIVE_GROUPS)
sensitive_max_abs <- setNames(rep(0, length(AG_STEP7E2_SENSITIVE_GROUPS)), AG_STEP7E2_SENSITIVE_GROUPS)
sensitive_max_rel <- setNames(rep(0, length(AG_STEP7E2_SENSITIVE_GROUPS)), AG_STEP7E2_SENSITIVE_GROUPS)
action_rows <- 0L
v1_choice <- character(length(dec)); global_choice <- character(length(dec))
hv <- integer(length(dec)); sourcev <- character(length(dec)); elig_count <- integer(length(dec))

for (i in seq_along(dec)) {
  a <- dec[[i]]; b <- ref[[i]]
  for (k in c("source_id", "dataset", "series_id", "frequency", "h", "N", "n_D",
              "start_timestamp", "development_hash", "target_raw_sha256")) {
    if (!identical(as.character(a[[k]]), as.character(b[[k]]))) {
      stop(sprintf("FAIL decision metadata %s parent=%s", k, a$parent_id), call. = FALSE)
    }
  }
  if (is.null(a$M) != is.null(b$M) || (!is.null(a$M) && as.integer(a$M) != as.integer(b$M))) {
    stop(paste0("FAIL M identity parent=", a$parent_id), call. = FALSE)
  }
  if (!identical(as.character(a$eligible_groups), as.character(b$eligible_groups))) {
    stop(paste0("FAIL eligible groups parent=", a$parent_id), call. = FALSE)
  }
  if (as.integer(a$eligible_count) != as.integer(b$eligible_count)) stop(paste0("FAIL eligible count parent=", a$parent_id), call. = FALSE)
  if (!identical(as.character(a$v1_choice), as.character(b$v1_choice))) stop(paste0("FAIL V1 choice parent=", a$parent_id), call. = FALSE)
  if (!identical(as.character(a$global_choice), as.character(b$global_choice))) stop(paste0("FAIL GLOBAL choice parent=", a$parent_id), call. = FALSE)

  dv <- abs(as.double(a$v1_pred_log1p_regret) - as.double(b$v1_pred_log1p_regret))
  max_score <- max(max_score, dv)
  lims <- as.double(oracle$tolerances$v1_score_abs) +
    as.double(oracle$tolerances$v1_score_rel) * max(1, abs(as.double(b$v1_pred_log1p_regret)))
  if (!is.finite(dv) || dv > lims) stop(sprintf("FAIL V1 score parent=%s diff=%.17g lim=%.17g", a$parent_id, dv, lims), call. = FALSE)

  action_rows <- action_rows + length(a$eligible_groups)
  elig_count[[i]] <- as.integer(a$eligible_count)
  v1_choice[[i]] <- as.character(a$v1_choice)
  global_choice[[i]] <- as.character(a$global_choice)
  hv[[i]] <- as.integer(a$h)
  sourcev[[i]] <- as.character(a$source_id)

  for (g in a$eligible_groups) {
    ga <- a$groups[[g]]; gb <- b$groups[[g]]
    if (!identical(as.character(ga$selected_config_id), as.character(gb$selected_config_id))) {
      stop(sprintf("FAIL config parent=%s group=%s got=%s exp=%s", a$parent_id, g, ga$selected_config_id, gb$selected_config_id), call. = FALSE)
    }
    gotf <- as.double(ga$forecast); expf <- as.double(gb$forecast)
    da <- max(abs(gotf - expf)); scale_f <- max(1, max(abs(expf))); dr <- da / scale_f
    max_fore[[g]] <- max(max_fore[[g]], da); max_fore_rel[[g]] <- max(max_fore_rel[[g]], dr)
    if (g %in% AG_STEP7E2_SENSITIVE_GROUPS) {
      cf <- get_canonical_sensitive_forecast(a$parent_id, g, ga$selected_config_id, a$h)
      if (length(cf) != length(gotf)) stop(sprintf("FAIL sensitive canonical length parent=%s group=%s", a$parent_id, g), call. = FALSE)
      absd <- abs(gotf - cf); reld <- absd / pmax(1, abs(cf))
      sma <- if (length(absd)) max(absd) else 0; smr <- if (length(reld)) max(reld) else 0
      sensitive_arrays[[g]] <- sensitive_arrays[[g]] + 1L
      sensitive_nonexact_values[[g]] <- sensitive_nonexact_values[[g]] + sum(gotf != cf)
      sensitive_max_abs[[g]] <- max(sensitive_max_abs[[g]], sma)
      sensitive_max_rel[[g]] <- max(sensitive_max_rel[[g]], smr)
      got_raw <- writeBin(as.double(gotf), raw(), size = 8L, endian = "little")
      got_sha <- digest::digest(got_raw, algo = "sha256", serialize = FALSE)
      cj <- match(paste(a$parent_id, g, sep = "\r"), canonical_sensitive_key)
      if (identical(got_sha, as.character(canonical_sensitive_index$forecast_sha256[[cj]]))) {
        sensitive_exact[[g]] <- sensitive_exact[[g]] + 1L
      }
    } else {
      lim <- as.double(oracle$tolerances$forecast_abs_by_group[[g]]) +
        as.double(oracle$tolerances$forecast_rel) * scale_f
      if (!is.finite(da) || da > lim) stop(sprintf("FAIL forecast parent=%s group=%s diff=%.17g lim=%.17g", a$parent_id, g, da, lim), call. = FALSE)
    }
    ds <- abs(as.double(ga$v1_pred_log1p_regret) - as.double(gb$v1_pred_log1p_regret))
    max_score <- max(max_score, ds)
    sl <- as.double(oracle$tolerances$v1_score_abs) +
      as.double(oracle$tolerances$v1_score_rel) * max(1, abs(as.double(gb$v1_pred_log1p_regret)))
    if (!is.finite(ds) || ds > sl) stop(sprintf("FAIL group V1 score parent=%s group=%s diff=%.17g", a$parent_id, g, ds), call. = FALSE)
  }
}

pass("all_2496_metadata_including_canonical_development_hash_exact")
pass("all_2496_eligibility_sets_exact")
pass("all_23572_selected_config_ids_exact")
exact("SG02_sensitive_arrays_2410", as.integer(sensitive_arrays[["SG02_DISCRETE_POLY"]]), 2410L)
exact("SG05_sensitive_arrays_2416", as.integer(sensitive_arrays[["SG05_CONT_TIME_POLY"]]), 2416L)
sysname <- as.character(Sys.info()[["sysname"]])
if (identical(sysname, "Windows")) {
  win_bounds <- platform_contract$windows_qualified_profile$acceptance
  sg02_abs_lim <- as.double(win_bounds$SG02_DISCRETE_POLY$max_abs)
  sg02_rel_lim <- as.double(win_bounds$SG02_DISCRETE_POLY$max_rel_normalized)
  sg05_abs_lim <- as.double(win_bounds$SG05_CONT_TIME_POLY$max_abs)
  sg05_rel_lim <- as.double(win_bounds$SG05_CONT_TIME_POLY$max_rel_normalized)
  if (sensitive_max_abs[["SG02_DISCRETE_POLY"]] > sg02_abs_lim || sensitive_max_rel[["SG02_DISCRETE_POLY"]] > sg02_rel_lim) {
    stop(sprintf("FAIL SG02 Windows numerical contract max_abs=%.17g/%.17g max_rel=%.17g/%.17g",
                 sensitive_max_abs[["SG02_DISCRETE_POLY"]], sg02_abs_lim, sensitive_max_rel[["SG02_DISCRETE_POLY"]], sg02_rel_lim), call. = FALSE)
  }
  pass("SG02_windows_crossplatform_numerical_contract")
  if (sensitive_max_abs[["SG05_CONT_TIME_POLY"]] > sg05_abs_lim || sensitive_max_rel[["SG05_CONT_TIME_POLY"]] > sg05_rel_lim) {
    stop(sprintf("FAIL SG05 Windows numerical contract max_abs=%.17g/%.17g max_rel=%.17g/%.17g",
                 sensitive_max_abs[["SG05_CONT_TIME_POLY"]], sg05_abs_lim, sensitive_max_rel[["SG05_CONT_TIME_POLY"]], sg05_rel_lim), call. = FALSE)
  }
  pass("SG05_windows_crossplatform_numerical_contract")
} else if (identical(sysname, "Linux")) {
  exact("SG02_linux_byte_exact_arrays_2410", as.integer(sensitive_exact[["SG02_DISCRETE_POLY"]]), 2410L)
  exact("SG05_linux_byte_exact_arrays_2416", as.integer(sensitive_exact[["SG05_CONT_TIME_POLY"]]), 2416L)
  if (sensitive_max_abs[["SG02_DISCRETE_POLY"]] != 0 || sensitive_max_abs[["SG05_CONT_TIME_POLY"]] != 0) {
    stop("FAIL canonical Linux sensitive forecasts are not byte/numerically exact", call. = FALSE)
  }
  pass("canonical_linux_byte_exact_sensitive_contract")
} else {
  stop(paste0("FAIL unsupported Step7E2 platform profile: ", sysname), call. = FALSE)
}
cat(sprintf("INFO SG02 canonical-Linux comparison exact=%d/%d nonexact_values=%d max_abs=%.17g max_rel=%.17g\n",
            sensitive_exact[["SG02_DISCRETE_POLY"]], sensitive_arrays[["SG02_DISCRETE_POLY"]],
            sensitive_nonexact_values[["SG02_DISCRETE_POLY"]], sensitive_max_abs[["SG02_DISCRETE_POLY"]], sensitive_max_rel[["SG02_DISCRETE_POLY"]]))
cat(sprintf("INFO SG05 canonical-Linux comparison exact=%d/%d nonexact_values=%d max_abs=%.17g max_rel=%.17g\n",
            sensitive_exact[["SG05_CONT_TIME_POLY"]], sensitive_arrays[["SG05_CONT_TIME_POLY"]],
            sensitive_nonexact_values[["SG05_CONT_TIME_POLY"]], sensitive_max_abs[["SG05_CONT_TIME_POLY"]], sensitive_max_rel[["SG05_CONT_TIME_POLY"]]))
cat(sprintf("PASS %-72s max_abs=%.3e\n", "all_other_group_forecasts_original_tolerance", max(max_fore[setdiff(AG_V1_GROUPS, AG_STEP7E2_SENSITIVE_GROUPS)])))
cat(sprintf("PASS %-72s max_abs=%.3e\n", "all_v1_external_scores_numeric_parity", max_score))
exact("action_rows_23572", action_rows, 23572L)

count_named <- function(x, lev) {
  z <- table(factor(x, levels = lev)); setNames(as.integer(z), lev)
}
expv <- unlist(oracle$expected$choice_counts$v1, use.names = TRUE)
expg <- unlist(oracle$expected$choice_counts$global, use.names = TRUE)
gotv <- count_named(v1_choice, names(expv)); gotg <- count_named(global_choice, names(expg))
exact("v1_choice_counts_exact", unname(gotv), as.integer(expv))
exact("global_choice_counts_exact", unname(gotg), as.integer(expg))
he <- count_named(as.character(hv), names(oracle$expected$actionable_horizon_counts))
exact("actionable_horizon_counts_exact", unname(he), as.integer(unlist(oracle$expected$actionable_horizon_counts, use.names = FALSE)))
se <- count_named(sourcev, names(oracle$expected$actionable_source_counts))
exact("actionable_source_counts_exact", unname(se), as.integer(unlist(oracle$expected$actionable_source_counts, use.names = FALSE)))
if (length(res$bootstrap_first) != 10L || any(!nzchar(res$bootstrap_first))) stop("FAIL final 10-model bootstrap fingerprints", call. = FALSE)
pass("final_10_v1_model_bootstrap_fingerprints_recorded")

# Target-free outputs only.
dir.create("outputs", showWarnings = FALSE)
outdf <- data.frame(
  parent_id = pid, source_id = sourcev, h = hv, eligible_count = elig_count,
  v1_choice = v1_choice, global_choice = global_choice,
  development_hash = vapply(dec, `[[`, character(1), "development_hash"),
  target_raw_sha256 = vapply(dec, `[[`, character(1), "target_raw_sha256"),
  stringsAsFactors = FALSE
)
utils::write.csv(outdf, "outputs/AUTOGREY_STEP7E2_PRETARGET_CHOICES_R8.csv", row.names = FALSE, na = "")
audit <- list(
  checkpoint = "STEP_7E2_REALBENCH2_PRETARGET_R8_CROSSPLATFORM_FINAL",
  status = "PASS",
  reservation_count = 2511L, actionable_count = length(dec), refusal_count = length(refus),
  action_rows = action_rows,
  canonical_development_hashes_exact = length(dec),
  platform_contract = list(
    canonical_platform = "linux/OpenBLAS",
    current_platform = as.character(Sys.info()[["sysname"]]),
    byte_exact_claim_on_windows = FALSE,
    contract_sha256 = sha(platform_contract_path)
  ),
  sensitive_bridge = list(
    request_count = as.integer(res$sensitive_bridge_request_count),
    group_counts = as.list(res$sensitive_bridge_counts),
    SG02 = list(arrays = as.integer(sensitive_arrays[["SG02_DISCRETE_POLY"]]), exact_arrays = as.integer(sensitive_exact[["SG02_DISCRETE_POLY"]]), nonexact_values = as.integer(sensitive_nonexact_values[["SG02_DISCRETE_POLY"]]), max_abs = sensitive_max_abs[["SG02_DISCRETE_POLY"]], max_rel = sensitive_max_rel[["SG02_DISCRETE_POLY"]]),
    SG05 = list(arrays = as.integer(sensitive_arrays[["SG05_CONT_TIME_POLY"]]), exact_arrays = as.integer(sensitive_exact[["SG05_CONT_TIME_POLY"]]), nonexact_values = as.integer(sensitive_nonexact_values[["SG05_CONT_TIME_POLY"]]), max_abs = sensitive_max_abs[["SG05_CONT_TIME_POLY"]], max_rel = sensitive_max_rel[["SG05_CONT_TIME_POLY"]])
  ),
  max_forecast_abs_by_group = as.list(max_fore),
  max_forecast_rel_by_group = as.list(max_fore_rel),
  max_v1_score_abs = max_score,
  v1_choice_counts = as.list(gotv), global_choice_counts = as.list(gotg),
  chronology = list(
    target_tokens_numeric_parsed = FALSE,
    target_losses_computed = FALSE,
    outcomes_opened = FALSE,
    all_group_forecasts_frozen_from_D_only = TRUE
  )
)
jsonlite::write_json(audit, "outputs/AUTOGREY_STEP7E2_PRETARGET_AUDIT_R8.json",
                     pretty = TRUE, auto_unbox = TRUE, digits = 17)
cat("INFO wrote target-free Step7E2 R8 cross-platform outputs; no held-out target numeric value was parsed.\n")
cat("INFO Step7F1 target scoring remains NOT STARTED.\n\n")
cat("STEP7E2_REALBENCH2_PRETARGET_CROSSPLATFORM_PARITY_R8: PASS\n")
