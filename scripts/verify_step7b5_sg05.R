#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else "scripts/verify_step7b5_sg05.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(root, "R", "01_utils.R"))
source(file.path(root, "R", "04_mase.R"))
source(file.path(root, "R", "05_grey_common.R"))
source(file.path(root, "R", "06_structural_groups.R"))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required by the frozen Step 7A dependency contract.")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required by the frozen Step 7A dependency contract.")

fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg05_reference_fixture_step7b5.json"), simplifyVector = FALSE)
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
  cat(sprintf("PASS %-48s max_abs=%.3e\n", name, d))
}

assert_close_scaled <- function(name, got, exp, atol = SCORE_ABS, rtol = SCORE_REL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  d <- if (length(got)) max(abs(got - exp)) else 0
  scale <- if (length(exp)) max(1.0, max(abs(exp))) else 1.0
  lim <- atol + rtol * scale
  if (d > lim) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g (scale %.6g)", name, d, lim, scale))
  cat(sprintf("PASS %-48s max_abs=%.3e\n", name, d))
}

# 0) Canonical engine provenance and exact preservation of the already R-verified SG01-SG04 source prefix.
ref_py <- file.path(root, "reference", "python", "autogrey_engine_step4fb_r1.py")
got_hash <- digest::digest(ref_py, algo = "sha256", file = TRUE, serialize = FALSE)
if (!identical(got_hash, fx$canonical_python_engine_sha256)) stop(sprintf("FAIL canonical_python_engine_sha256: got %s expected %s", got_hash, fx$canonical_python_engine_sha256))
cat(sprintf("PASS canonical_python_engine_sha256 %s\n", got_hash))
parent_r <- file.path(root, "reference", "r", "06_structural_groups_step7b4_verified.R")
current_r <- file.path(root, "R", "06_structural_groups.R")
con1 <- file(parent_r, "rb"); parent_raw <- readBin(con1, "raw", n = file.info(parent_r)$size); close(con1)
con2 <- file(current_r, "rb"); current_prefix <- readBin(con2, "raw", n = length(parent_raw)); close(con2)
if (!identical(parent_raw, current_prefix)) stop("FAIL sg01_sg04_source_prefix_preservation")
cat("PASS sg01_sg04_source_prefix_preservation\n")

# 1) Frozen 32-point Gauss-Legendre constants used for every nonzero-a time-power interval.
assert_close("gauss_legendre_x32", AG_GL_X32, fx$gauss_legendre_32$x, tol = 1e-15)
assert_close("gauss_legendre_w32", AG_GL_W32, fx$gauss_legendre_32$w, tol = 1e-15)

# 2) Exact affine duplicate: direct time-power alpha=1 and FOTP order=2.
aff <- fx$affine_equivalence_fixture
xa <- num(aff$x); ha <- as.integer(aff$h)
tp1 <- ag_timepower_fit_forecast(xa, ha, as.numeric(aff$timepower_alpha))
fp2 <- ag_fotp_fit_forecast(xa, ha, as.integer(aff$fotp_order))
assert_close("affine_tp_fitted", tp1$fitted, aff$expected$timepower$fitted)
assert_close("affine_tp_forecast", tp1$forecast, aff$expected$timepower$forecast)
assert_close("affine_tp_a", tp1$params$a, aff$expected$timepower$params$a)
assert_close("affine_tp_b", tp1$params$b, aff$expected$timepower$params$b)
assert_close("affine_tp_c", tp1$params$c, aff$expected$timepower$params$c)
assert_close("affine_fp_fitted", fp2$fitted, aff$expected$fotp$fitted)
assert_close("affine_fp_forecast", fp2$forecast, aff$expected$fotp$forecast)
assert_close("affine_fp_a", fp2$params$a, aff$expected$fotp$params$a)
assert_close("affine_fp_b_desc", fp2$params$b_desc, aff$expected$fotp$params$b_desc)
if (fp2$params$p_order != as.integer(aff$expected$fotp$params$p_order)) stop("FAIL affine_fp_order") else cat("PASS affine_fp_order\n")
denom <- max(mean(abs(xa)), 1e-12)
d_aff <- max(abs(tp1$forecast - fp2$forecast)) / denom
assert_close("affine_normalized_distance", d_aff, aff$expected$normalized_forecast_distance, tol = as.numeric(fx$tolerances$identity_abs))
if (d_aff >= as.numeric(fx$tolerances$identity_abs)) stop("FAIL affine_parameterizations_equivalent") else cat("PASS affine_parameterizations_equivalent\n")

# 3) Direct noninteger time-power quadrature fixture.
td <- fx$timepower_direct_fixture
tdo <- ag_timepower_fit_forecast(num(td$x), as.integer(td$h), as.numeric(td$alpha))
assert_close("timepower_direct_fitted", tdo$fitted, td$expected$fitted)
assert_close("timepower_direct_forecast", tdo$forecast, td$expected$forecast)
assert_close("timepower_direct_a", tdo$params$a, td$expected$params$a)
assert_close("timepower_direct_b", tdo$params$b, td$expected$params$b)
assert_close("timepower_direct_c", tdo$params$c, td$expected$params$c)
assert_close("timepower_direct_alpha", tdo$params$alpha, td$expected$params$alpha, tol = 0)
if (tdo$diagnostics$rank != as.integer(td$expected$diagnostics$rank)) stop("FAIL timepower_direct_rank") else cat("PASS timepower_direct_rank\n")
assert_close("timepower_direct_condition", tdo$diagnostics$condition, td$expected$diagnostics$condition, tol = COND_TOL)
if (tdo$diagnostics$resid_df != as.integer(td$expected$diagnostics$resid_df)) stop("FAIL timepower_direct_resid_df") else cat("PASS timepower_direct_resid_df\n")

# 4) Direct FOTP polynomial-response fixture.
fd <- fx$fotp_direct_fixture
fdo <- ag_fotp_fit_forecast(num(fd$x), as.integer(fd$h), as.integer(fd$p_order))
assert_close("fotp_direct_fitted", fdo$fitted, fd$expected$fitted)
assert_close("fotp_direct_forecast", fdo$forecast, fd$expected$forecast)
assert_close("fotp_direct_a", fdo$params$a, fd$expected$params$a)
assert_close("fotp_direct_b_desc", fdo$params$b_desc, fd$expected$params$b_desc)
if (fdo$params$p_order != as.integer(fd$expected$params$p_order)) stop("FAIL fotp_direct_order") else cat("PASS fotp_direct_order\n")
if (fdo$diagnostics$rank != as.integer(fd$expected$diagnostics$rank)) stop("FAIL fotp_direct_rank") else cat("PASS fotp_direct_rank\n")
assert_close("fotp_direct_condition", fdo$diagnostics$condition, fd$expected$diagnostics$condition, tol = COND_TOL)
if (fdo$diagnostics$resid_df != as.integer(fd$expected$diagnostics$resid_df)) stop("FAIL fotp_direct_resid_df") else cat("PASS fotp_direct_resid_df\n")

# 5) Explicit a~0 response branches.
z <- fx$a_near_zero_response_fixture$timepower
zr <- ag_timepower_response(as.numeric(z$x1_0), as.numeric(z$a), as.numeric(z$b), as.numeric(z$c), as.numeric(z$alpha), as.integer(z$total))
assert_close("timepower_a0_response", zr, z$expected)
z <- fx$a_near_zero_response_fixture$fotp
zr <- ag_fotp_response(as.numeric(z$x1_0), as.numeric(z$a), num(z$c_asc), as.integer(z$total))
assert_close("fotp_a0_response", zr, z$expected)

# 6) Frozen SG05 registry and ownership of the affine duplicate.
cg <- fx$config_generation
cfgs <- ag_sg05_configs(as.integer(cg$n), as.integer(cg$h), NULL)
got_ids <- vapply(cfgs, `[[`, character(1), "config_id")
if (!identical(got_ids, chr(cg$expected_config_ids))) stop("FAIL config_generation_ids") else cat("PASS config_generation_ids\n")
if ("TP_alpha=1" %in% got_ids) stop("FAIL config_grid_excludes_timepower_alpha1") else cat("PASS config_grid_excludes_timepower_alpha1\n")
if (!(as.character(cg$affine_owner_config_id) %in% got_ids)) stop("FAIL affine_owner_fotp2_present") else cat("PASS affine_owner_fotp2_present\n")
if (length(cfgs) != length(cg$expected_config_ids)) stop("FAIL config_generation_count") else cat("PASS config_generation_count\n")

# 7) Full SG05 tuner: numerical best TP alpha=.75; FOTP order 2 is inside 5% and wins the frozen simplicity key.
g <- fx$sg05_group_tuner
res <- ag_select_sg05(num(g$x), as.integer(g$h), NULL)
if (!isTRUE(res$eligible)) stop(sprintf("FAIL sg05_group_eligible: %s:%s", res$failure_code, res$failure_detail)) else cat("PASS sg05_group_eligible\n")
if (!identical(res$selected_config_id, as.character(g$expected$selected_config_id))) stop("FAIL sg05_selected_config_id") else cat("PASS sg05_selected_config_id\n")
if (!identical(res$selected_config$kind, as.character(g$expected$selected_config$kind))) stop("FAIL sg05_selected_kind") else cat("PASS sg05_selected_kind\n")
if (res$selected_config$p_order != as.integer(g$expected$selected_config$p_order)) stop("FAIL sg05_selected_p_order") else cat("PASS sg05_selected_p_order\n")
assert_close("sg05_common_origins", res$diagnostics$common_origins, g$expected$common_origins, tol = 0)
if (res$diagnostics$config_count_registered != as.integer(g$expected$config_count_registered)) stop("FAIL sg05_config_count_registered") else cat("PASS sg05_config_count_registered\n")
if (res$diagnostics$config_count_valid != as.integer(g$expected$config_count_valid)) stop("FAIL sg05_config_count_valid") else cat("PASS sg05_config_count_valid\n")
assert_close_scaled("sg05_Lmin", res$diagnostics$Lmin, g$expected$Lmin)
if (res$diagnostics$band_size != as.integer(g$expected$band_size)) stop("FAIL sg05_band_size") else cat("PASS sg05_band_size\n")
means <- vapply(res$inner_scores, `[[`, numeric(1), "mean_inner_mase")
band_ids <- vapply(res$inner_scores[means <= 1.05 * res$diagnostics$Lmin + 1e-15], `[[`, character(1), "config_id")
if (!identical(band_ids, chr(g$expected$band_config_ids))) stop("FAIL sg05_band_config_ids") else cat("PASS sg05_band_config_ids\n")
best_id <- res$inner_scores[[which.min(means)]]$config_id
if (!identical(best_id, as.character(g$expected$best_config_id))) stop("FAIL sg05_best_config_id") else cat("PASS sg05_best_config_id\n")
if (identical(best_id, res$selected_config_id) || !identical(res$selected_config_id, "FOTP_order=2")) stop("FAIL sg05_fotp2_simplicity_override") else cat("PASS sg05_fotp2_simplicity_override\n")
assert_close_scaled("sg05_selected_inner_mase", res$diagnostics$selected_inner_mase, g$expected$selected_inner_mase)
assert_close_scaled("sg05_selected_to_best_ratio", res$diagnostics$selected_to_best_ratio, g$expected$selected_to_best_ratio)
assert_close("sg05_final_a", res$diagnostics$final_params$a, g$expected$final_params$a)
assert_close("sg05_final_b_desc", res$diagnostics$final_params$b_desc, g$expected$final_params$b_desc)
if (res$diagnostics$final_params$p_order != as.integer(g$expected$final_params$p_order)) stop("FAIL sg05_final_p_order") else cat("PASS sg05_final_p_order\n")
assert_close("sg05_final_condition", res$diagnostics$final_model_diagnostics$condition, g$expected$final_model_diagnostics$condition, tol = COND_TOL)
assert_close("sg05_fitted", res$fitted, g$expected$fitted)
assert_close("sg05_forecast", res$forecast, g$expected$forecast)

exp_scores <- g$expected$scores
if (length(res$inner_scores) != length(exp_scores)) stop("FAIL sg05_score_count") else cat("PASS sg05_score_count\n")
for (i in seq_along(res$inner_scores)) {
  got <- res$inner_scores[[i]]; exp <- exp_scores[[i]]
  if (!identical(got$config_id, as.character(exp$config_id))) stop(sprintf("FAIL score_id_%02d", i))
  if (!identical(got$kind, as.character(exp$kind))) stop(sprintf("FAIL score_kind_%02d", i))
  if (identical(got$kind, "timepower")) assert_close(sprintf("score_alpha_%02d", i), got$alpha, exp$alpha, tol = 0)
  else if (got$p_order != as.integer(exp$p_order)) stop(sprintf("FAIL score_p_order_%02d", i))
  assert_close_scaled(sprintf("score_mean_%02d", i), got$mean_inner_mase, exp$mean_inner_mase)
  assert_close_scaled(sprintf("score_origins_%02d", i), got$origin_losses, exp$origin_losses)
}

# 8) Explicit SG05 failure semantics.
for (z in fx$failure_fixtures) {
  if (identical(z$kind, "timepower")) {
    err <- tryCatch({ ag_timepower_fit_forecast(num(z$x), as.integer(z$h), as.numeric(z$alpha)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(z$kind, "fotp")) {
    err <- tryCatch({ ag_fotp_fit_forecast(num(z$x), as.integer(z$h), as.integer(z$p_order)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(z$kind, "group")) {
    rr <- ag_select_sg05(num(z$x), as.integer(z$h), NULL)
    if (isTRUE(rr$eligible) || !identical(rr$failure_code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, rr$failure_code))
  } else stop(sprintf("FAIL unknown_failure_fixture_kind_%s", z$name))
}

# 9) Regression guards for SG01-SG04, all already externally R-verified by the user.
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

cat("\nSTEP7B5_SG05_PARITY: PASS\n")
