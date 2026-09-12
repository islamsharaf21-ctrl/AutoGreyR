#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else "scripts/verify_step7b7_sg07.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(root, "R", "01_utils.R"))
source(file.path(root, "R", "04_mase.R"))
source(file.path(root, "R", "05_grey_common.R"))
source(file.path(root, "R", "06_structural_groups.R"))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required by the frozen Step 7A dependency contract.")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required by the frozen Step 7A dependency contract.")

fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg07_reference_fixture_step7b7.json"), simplifyVector = FALSE)
TOL <- as.numeric(fx$tolerances$numeric_abs)
COND_TOL <- as.numeric(fx$tolerances$condition_abs)
SCORE_ABS <- as.numeric(fx$tolerances$score_abs)
SCORE_REL <- as.numeric(fx$tolerances$score_rel)
num <- function(x) as.numeric(unlist(x, use.names = FALSE))
chr <- function(x) as.character(unlist(x, use.names = FALSE))

assert_close <- function(name, got, exp, tol = TOL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  d <- if (length(got)) max(abs(got - exp)) else 0
  if (d > tol) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g", name, d, tol))
  cat(sprintf("PASS %-52s max_abs=%.3e\n", name, d))
}

assert_close_scaled <- function(name, got, exp, atol = SCORE_ABS, rtol = SCORE_REL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  d <- if (length(got)) max(abs(got - exp)) else 0
  scale <- if (length(exp)) max(1.0, max(abs(exp))) else 1.0
  lim <- atol + rtol * scale
  if (d > lim) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g (scale %.6g)", name, d, lim, scale))
  cat(sprintf("PASS %-52s max_abs=%.3e\n", name, d))
}

# 0) Canonical provenance + byte-exact preservation of externally R-verified SG01-SG06.
ref_py <- file.path(root, "reference", "python", "autogrey_engine_step4fb_r1.py")
got_hash <- digest::digest(ref_py, algo = "sha256", file = TRUE, serialize = FALSE)
if (!identical(got_hash, as.character(fx$canonical_python_engine_sha256))) stop(sprintf("FAIL canonical_python_engine_sha256: got %s expected %s", got_hash, fx$canonical_python_engine_sha256))
cat(sprintf("PASS canonical_python_engine_sha256 %s\n", got_hash))
parent_r <- file.path(root, "reference", "r", "06_structural_groups_step7b6_verified.R")
current_r <- file.path(root, "R", "06_structural_groups.R")
con1 <- file(parent_r, "rb"); parent_raw <- readBin(con1, "raw", n = file.info(parent_r)$size); close(con1)
con2 <- file(current_r, "rb"); current_prefix <- readBin(con2, "raw", n = length(parent_raw)); close(con2)
if (!identical(parent_raw, current_prefix)) stop("FAIL sg01_sg06_source_prefix_preservation")
cat("PASS sg01_sg06_source_prefix_preservation\n")

# 1) Direct recursive SG07 fixture: exact three rolling windows/refits.
d <- fx$direct_recursive_fixture
x <- num(d$x); h <- as.integer(d$h); w <- as.integer(d$w)
out <- ag_rolling_gm_forecast(x, h, w)
assert_close("direct_forecast", out$forecast, d$expected$forecast)
assert_close("direct_fitted_placeholder", out$fitted, d$expected$fitted)
if (out$params$w != as.integer(d$expected$params$w)) stop("FAIL direct_param_w") else cat("PASS direct_param_w\n")
assert_close("direct_param_alpha_bg", out$params$alpha_bg, d$expected$params$alpha_bg, tol = 0)
if (out$diagnostics$recursive_refits != as.integer(d$expected$diagnostics$recursive_refits)) stop("FAIL direct_recursive_refits") else cat("PASS direct_recursive_refits\n")
if (!identical(out$diagnostics$fitted_semantics, as.character(d$expected$diagnostics$fitted_semantics))) stop("FAIL direct_fitted_semantics") else cat("PASS direct_fitted_semantics\n")
if (!isTRUE(all.equal(as.numeric(out$fitted), x, tolerance = 0))) stop("FAIL direct_fitted_equals_observed") else cat("PASS direct_fitted_equals_observed\n")

pseudo <- x
for (i in seq_along(d$recursive_steps)) {
  z <- d$recursive_steps[[i]]
  window <- tail(pseudo, 4L)
  # Window 1 is observed-only and must match exactly. Later windows contain
  # recursively generated forecasts, so use the frozen numeric tolerance.
  window_tol <- if (i == 1L) 0 else TOL
  assert_close(sprintf("recursive_window_%02d", i), window, z$window, tol = window_tol)
  gm <- ag_gm_fit_forecast(window, 1L, 0.5)
  assert_close(sprintf("recursive_forecast_%02d", i), gm$forecast, z$gm_forecast)
  assert_close(sprintf("recursive_a_%02d", i), gm$params$a, z$gm_a)
  assert_close(sprintf("recursive_b_%02d", i), gm$params$b, z$gm_b)
  assert_close(sprintf("recursive_alpha_bg_%02d", i), gm$params$alpha_bg, z$gm_alpha_bg, tol = 0)
  assert_close(sprintf("recursive_condition_%02d", i), gm$diagnostics$condition, z$gm_condition, tol = COND_TOL)
  if (gm$diagnostics$rank != as.integer(z$gm_rank)) stop(sprintf("FAIL recursive_rank_%02d", i)) else cat(sprintf("PASS recursive_rank_%02d\n", i))
  pseudo <- c(pseudo, as.numeric(gm$forecast[1L]))
}
assert_close("recursive_steps_reconstruct_forecast", tail(pseudo, h), d$expected$forecast)
assert_close("first_step_equals_last_window_gm", out$forecast[1L], d$static_gm_last_window_first_step)

# 2) Exact frozen registry: one and only one config, w=4.
cg <- fx$config_generation
cfgs <- ag_sg07_configs(as.integer(cg$n), as.integer(cg$h), NULL)
got_ids <- vapply(cfgs, `[[`, character(1), "config_id")
got_w <- vapply(cfgs, `[[`, integer(1), "w")
if (!identical(got_ids, chr(cg$expected_config_ids))) stop("FAIL config_generation_ids") else cat("PASS config_generation_ids\n")
assert_close("config_generation_w", got_w, cg$expected_w, tol = 0)
if (length(cfgs) != 1L || got_w[1L] != 4L) stop("FAIL config_generation_singleton_w4") else cat("PASS config_generation_singleton_w4\n")

# 3) Full SG07 group selection over common origins.
g <- fx$sg07_group_tuner
res <- ag_select_sg07(num(g$x), as.integer(g$h), NULL)
if (!isTRUE(res$eligible)) stop(sprintf("FAIL sg07_group_eligible: %s:%s", res$failure_code, res$failure_detail)) else cat("PASS sg07_group_eligible\n")
if (!identical(res$selected_config_id, as.character(g$expected$selected_config_id))) stop("FAIL sg07_selected_config_id") else cat("PASS sg07_selected_config_id\n")
if (res$selected_config$w != as.integer(g$expected$selected_w)) stop("FAIL sg07_selected_w") else cat("PASS sg07_selected_w\n")
assert_close("sg07_common_origins", res$diagnostics$common_origins, g$expected$common_origins, tol = 0)
if (res$diagnostics$config_count_registered != as.integer(g$expected$config_count_registered)) stop("FAIL sg07_config_count_registered") else cat("PASS sg07_config_count_registered\n")
if (res$diagnostics$config_count_valid != as.integer(g$expected$config_count_valid)) stop("FAIL sg07_config_count_valid") else cat("PASS sg07_config_count_valid\n")
assert_close_scaled("sg07_Lmin", res$diagnostics$Lmin, g$expected$Lmin)
if (res$diagnostics$band_size != as.integer(g$expected$band_size)) stop("FAIL sg07_band_size") else cat("PASS sg07_band_size\n")
means <- vapply(res$inner_scores, `[[`, numeric(1), "mean_inner_mase")
band_ids <- vapply(res$inner_scores[means <= 1.05 * res$diagnostics$Lmin + 1e-15], `[[`, character(1), "config_id")
if (!identical(band_ids, chr(g$expected$band_config_ids))) stop("FAIL sg07_band_config_ids") else cat("PASS sg07_band_config_ids\n")
best_id <- res$inner_scores[[which.min(means)]]$config_id
if (!identical(best_id, as.character(g$expected$best_config_id))) stop("FAIL sg07_best_config_id") else cat("PASS sg07_best_config_id\n")
if (length(res$inner_scores) != 1L || !identical(res$selected_config_id, best_id)) stop("FAIL sg07_singleton_selection") else cat("PASS sg07_singleton_selection\n")
assert_close_scaled("sg07_selected_inner_mase", res$diagnostics$selected_inner_mase, g$expected$selected_inner_mase)
assert_close_scaled("sg07_selected_to_best_ratio", res$diagnostics$selected_to_best_ratio, g$expected$selected_to_best_ratio)
if (res$diagnostics$final_params$w != as.integer(g$expected$final_params$w)) stop("FAIL sg07_final_w") else cat("PASS sg07_final_w\n")
assert_close("sg07_final_alpha_bg", res$diagnostics$final_params$alpha_bg, g$expected$final_params$alpha_bg, tol = 0)
if (res$diagnostics$final_model_diagnostics$recursive_refits != as.integer(g$expected$final_model_diagnostics$recursive_refits)) stop("FAIL sg07_final_recursive_refits") else cat("PASS sg07_final_recursive_refits\n")
if (!identical(res$diagnostics$final_model_diagnostics$fitted_semantics, as.character(g$expected$final_model_diagnostics$fitted_semantics))) stop("FAIL sg07_final_fitted_semantics") else cat("PASS sg07_final_fitted_semantics\n")
assert_close("sg07_fitted", res$fitted, g$expected$fitted)
assert_close("sg07_forecast", res$forecast, g$expected$forecast)

exp_scores <- g$expected$scores
if (length(res$inner_scores) != length(exp_scores)) stop("FAIL sg07_score_count") else cat("PASS sg07_score_count\n")
for (i in seq_along(res$inner_scores)) {
  got <- res$inner_scores[[i]]; exp <- exp_scores[[i]]
  if (!identical(got$config_id, as.character(exp$config_id))) stop(sprintf("FAIL score_id_%02d", i))
  if (got$w != as.integer(exp$w)) stop(sprintf("FAIL score_w_%02d", i)) else cat(sprintf("PASS score_w_%02d\n", i))
  assert_close_scaled(sprintf("score_mean_%02d", i), got$mean_inner_mase, exp$mean_inner_mase)
  assert_close_scaled(sprintf("score_origins_%02d", i), got$origin_losses, exp$origin_losses)
  for (j in seq_along(got$diagnostics$origin_diagnostics)) {
    gd <- got$diagnostics$origin_diagnostics[[j]]; ed <- exp$origin_diagnostics[[j]]
    if (gd$recursive_refits != as.integer(ed$recursive_refits)) stop(sprintf("FAIL score_origin_refits_%02d_%02d", i, j))
    if (!identical(gd$fitted_semantics, as.character(ed$fitted_semantics))) stop(sprintf("FAIL score_origin_semantics_%02d_%02d", i, j))
  }
  cat(sprintf("PASS score_origin_diagnostics_%02d\n", i))
}

# 4) Explicit rolling failure semantics, including validation ordering.
for (z in fx$failure_fixtures) {
  kind <- as.character(z$kind)
  if (identical(kind, "model")) {
    err <- tryCatch({ ag_rolling_gm_forecast(num(z$x), as.integer(z$h), as.integer(z$w)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "group")) {
    rr <- ag_select_sg07(num(z$x), as.integer(z$h), NULL)
    if (isTRUE(rr$eligible) || !identical(rr$failure_code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, rr$failure_code))
  } else stop(sprintf("FAIL unknown_failure_fixture_kind_%s", z$name))
}

# 5) Regression guards for SG01-SG06 — all six prior checkpoints were externally R-verified.
fx1 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg01_reference_fixture_step7b1.json"), simplifyVector = TRUE)
g1 <- fx1$sg01_group_tuner; r1 <- ag_select_sg01(g1$x, g1$h, g1$M)
if (!isTRUE(r1$eligible) || !identical(r1$selected_config_id, g1$expected$selected_config_id)) stop("FAIL sg01_regression_guard_selection")
cat("PASS sg01_regression_guard_selection\n")
d1 <- max(abs(as.numeric(r1$forecast) - as.numeric(g1$expected$forecast)))
if (d1 > as.numeric(fx1$tolerances$numeric_abs)) stop("FAIL sg01_regression_guard_forecast")
cat(sprintf("PASS sg01_regression_guard_forecast         max_abs=%.3e\n", d1))

fx2 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg02_reference_fixture_step7b2.json"), simplifyVector = FALSE)
g2 <- fx2$sg02_group_tuner; r2 <- ag_select_sg02(num(g2$x), as.integer(g2$h), NULL)
if (!isTRUE(r2$eligible) || !identical(r2$selected_config_id, as.character(g2$expected$selected_config_id))) stop("FAIL sg02_regression_guard_selection")
cat("PASS sg02_regression_guard_selection\n")
d2 <- max(abs(as.numeric(r2$forecast) - num(g2$expected$forecast)))
if (d2 > as.numeric(fx2$tolerances$numeric_abs)) stop("FAIL sg02_regression_guard_forecast")
cat(sprintf("PASS sg02_regression_guard_forecast         max_abs=%.3e\n", d2))

fx3 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg03_reference_fixture_step7b3.json"), simplifyVector = FALSE)
g3 <- fx3$sg03_group_tuner; r3 <- ag_select_sg03(num(g3$x), as.integer(g3$h), NULL)
if (!isTRUE(r3$eligible) || !identical(r3$selected_config_id, as.character(g3$expected$selected_config_id))) stop("FAIL sg03_regression_guard_selection")
cat("PASS sg03_regression_guard_selection\n")
d3 <- max(abs(as.numeric(r3$forecast) - num(g3$expected$forecast)))
if (d3 > as.numeric(fx3$tolerances$numeric_abs)) stop("FAIL sg03_regression_guard_forecast")
cat(sprintf("PASS sg03_regression_guard_forecast         max_abs=%.3e\n", d3))

fx4 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg04_reference_fixture_step7b4.json"), simplifyVector = FALSE)
g4 <- fx4$sg04_group_tuner; r4 <- ag_select_sg04(num(g4$x), as.integer(g4$h), NULL)
if (!isTRUE(r4$eligible) || !identical(r4$selected_config_id, as.character(g4$expected$selected_config_id))) stop("FAIL sg04_regression_guard_selection")
cat("PASS sg04_regression_guard_selection\n")
d4 <- max(abs(as.numeric(r4$forecast) - num(g4$expected$forecast)))
if (d4 > as.numeric(fx4$tolerances$numeric_abs)) stop("FAIL sg04_regression_guard_forecast")
cat(sprintf("PASS sg04_regression_guard_forecast         max_abs=%.3e\n", d4))

fx5 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg05_reference_fixture_step7b5.json"), simplifyVector = FALSE)
g5 <- fx5$sg05_group_tuner; r5 <- ag_select_sg05(num(g5$x), as.integer(g5$h), NULL)
if (!isTRUE(r5$eligible) || !identical(r5$selected_config_id, as.character(g5$expected$selected_config_id))) stop("FAIL sg05_regression_guard_selection")
cat("PASS sg05_regression_guard_selection\n")
d5 <- max(abs(as.numeric(r5$forecast) - num(g5$expected$forecast)))
if (d5 > as.numeric(fx5$tolerances$numeric_abs)) stop("FAIL sg05_regression_guard_forecast")
cat(sprintf("PASS sg05_regression_guard_forecast         max_abs=%.3e\n", d5))

fx6 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg06_reference_fixture_step7b6.json"), simplifyVector = FALSE)
g6 <- fx6$sg06_group_tuner; r6 <- ag_select_sg06(num(g6$x), as.integer(g6$h), NULL)
if (!isTRUE(r6$eligible) || !identical(r6$selected_config_id, as.character(g6$expected$selected_config_id))) stop("FAIL sg06_regression_guard_selection")
cat("PASS sg06_regression_guard_selection\n")
d6 <- max(abs(as.numeric(r6$forecast) - num(g6$expected$forecast)))
if (d6 > as.numeric(fx6$tolerances$numeric_abs)) stop("FAIL sg06_regression_guard_forecast")
cat(sprintf("PASS sg06_regression_guard_forecast         max_abs=%.3e\n", d6))

cat("\nSTEP7B7_SG07_PARITY: PASS\n")
