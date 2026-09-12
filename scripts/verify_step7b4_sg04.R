#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else "scripts/verify_step7b4_sg04.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(root, "R", "01_utils.R"))
source(file.path(root, "R", "04_mase.R"))
source(file.path(root, "R", "05_grey_common.R"))
source(file.path(root, "R", "06_structural_groups.R"))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required by the frozen Step 7A dependency contract.")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required by the frozen Step 7A dependency contract.")

fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg04_reference_fixture_step7b4.json"), simplifyVector = FALSE)
TOL <- as.numeric(fx$tolerances$numeric_abs)
ref_py <- file.path(root, "reference", "python", "autogrey_engine_step4fb_r1.py")
got_hash <- digest::digest(ref_py, algo = "sha256", file = TRUE, serialize = FALSE)
if (!identical(got_hash, fx$canonical_python_engine_sha256)) stop(sprintf("FAIL canonical_python_engine_sha256: got %s expected %s", got_hash, fx$canonical_python_engine_sha256))
cat(sprintf("PASS canonical_python_engine_sha256 %s\n", got_hash))

num <- function(x) as.numeric(unlist(x, use.names = FALSE))
chr <- function(x) as.character(unlist(x, use.names = FALSE))

assert_close <- function(name, got, exp, tol = TOL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  d <- if (length(got)) max(abs(got - exp)) else 0
  if (d > tol) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g", name, d, tol))
  cat(sprintf("PASS %-46s max_abs=%.3e\n", name, d))
}

# 1) Scalar real-power semantics used by the Bernoulli response.
pw <- fx$real_power_fixture
for (i in seq_along(pw$valid)) {
  z <- pw$valid[[i]]
  got <- ag_real_power_scalar(as.numeric(z$base), as.numeric(z$exponent))
  assert_close(sprintf("real_power_valid_%02d", i), got, z$expected, tol = as.numeric(fx$tolerances$power_abs))
}
for (z in pw$failures) {
  err <- tryCatch({ ag_real_power_scalar(as.numeric(z$base), as.numeric(z$exponent)); NULL }, autogrey_engine_failure = identity)
  if (is.null(err) || !identical(err$code, z$expected_code)) stop(sprintf("FAIL real_power_failure_%s", z$name))
  cat(sprintf("PASS real_power_failure_%s code=%s\n", z$name, err$code))
}

# 2) Frozen NGBM reductions: gamma=0 is traditional background-value GM; gamma=2 is Verhulst.
r <- fx$reduction_fixture
x <- num(r$x); h <- as.integer(r$h)
gm <- ag_gm_fit_forecast(x, h, as.numeric(r$gm_alpha))
ng0 <- ag_ngbm_fit_forecast(x, h, 0.0)
ng2 <- ag_ngbm_fit_forecast(x, h, 2.0)
assert_close("reduction_gm_fitted", gm$fitted, r$expected$gm_fitted)
assert_close("reduction_gm_forecast", gm$forecast, r$expected$gm_forecast)
assert_close("gamma0_fitted", ng0$fitted, r$expected$gamma0_fitted)
assert_close("gamma0_forecast", ng0$forecast, r$expected$gamma0_forecast)
assert_close("gamma0_identity_fitted", ng0$fitted, gm$fitted, tol = as.numeric(fx$tolerances$identity_abs))
assert_close("gamma0_identity_forecast", ng0$forecast, gm$forecast, tol = as.numeric(fx$tolerances$identity_abs))
assert_close("gamma0_a", ng0$params$a, r$expected$gamma0_params$a)
assert_close("gamma0_b", ng0$params$b, r$expected$gamma0_params$b)
assert_close("gamma0_gamma", ng0$params$gamma, r$expected$gamma0_params$gamma, tol = 0)
if (ng0$diagnostics$rank != as.integer(r$expected$gamma0_diagnostics$rank)) stop("FAIL gamma0_rank") else cat("PASS gamma0_rank\n")
assert_close("gamma0_condition", ng0$diagnostics$condition, r$expected$gamma0_diagnostics$condition, tol = as.numeric(fx$tolerances$condition_abs))
assert_close("gamma0_kappa_id", ng0$diagnostics$kappa_id, r$expected$gamma0_diagnostics$kappa_id, tol = as.numeric(fx$tolerances$condition_abs))
if (!identical(isTRUE(ng0$diagnostics$kappa_id_warning), isTRUE(r$expected$gamma0_diagnostics$kappa_id_warning))) stop("FAIL gamma0_kappa_id_warning") else cat("PASS gamma0_kappa_id_warning\n")
assert_close("gamma2_fitted", ng2$fitted, r$expected$gamma2_fitted)
assert_close("gamma2_forecast", ng2$forecast, r$expected$gamma2_forecast)
assert_close("gamma2_a", ng2$params$a, r$expected$gamma2_params$a)
assert_close("gamma2_b", ng2$params$b, r$expected$gamma2_params$b)
assert_close("gamma2_gamma", ng2$params$gamma, r$expected$gamma2_params$gamma, tol = 0)
if (any(!is.finite(ng2$forecast))) stop("FAIL gamma2_verhulst_finite") else cat("PASS gamma2_verhulst_finite\n")
assert_close("gamma2_kappa_id", ng2$diagnostics$kappa_id, r$expected$gamma2_diagnostics$kappa_id, tol = as.numeric(fx$tolerances$condition_abs))

# 3) Explicit analytic a~0 branch.
z <- fx$a_near_zero_fixture
az <- ag_ngbm_fit_forecast(num(z$x), as.integer(z$h), as.numeric(z$gamma))
assert_close("a_near_zero_a", az$params$a, z$expected$params$a)
if (!ag_near(az$params$a, 0.0)) stop("FAIL a_near_zero_branch_not_exercised") else cat("PASS a_near_zero_branch_exercised\n")
assert_close("a_near_zero_fitted", az$fitted, z$expected$fitted)
assert_close("a_near_zero_forecast", az$forecast, z$expected$forecast)

# 4) Identifiability warning band (1e3 <= kappa_id < 1e4), valid fit retained.
w <- fx$identifiability_warning_fixture
wo <- ag_ngbm_fit_forecast(num(w$x), as.integer(w$h), as.numeric(w$gamma))
assert_close("id_warning_kappa_id", wo$diagnostics$kappa_id, w$expected$diagnostics$kappa_id, tol = as.numeric(fx$tolerances$condition_abs))
if (!isTRUE(wo$diagnostics$kappa_id_warning)) stop("FAIL id_warning_flag") else cat("PASS id_warning_flag\n")
assert_close("id_warning_forecast", wo$forecast, w$expected$forecast)

# 5) Frozen SG04 configuration registry: 15 gammas, excluding reductions/singularity gamma=0 and gamma=1.
cg <- fx$config_generation
cfgs <- ag_sg04_configs(as.integer(cg$n), as.integer(cg$h), NULL)
got_ids <- vapply(cfgs, `[[`, character(1), "config_id")
if (!identical(got_ids, chr(cg$expected_config_ids))) stop("FAIL config_generation_ids") else cat("PASS config_generation_ids\n")
assert_close("config_generation_gamma", vapply(cfgs, `[[`, numeric(1), "gamma"), cg$expected_gamma, tol = 0)
if (any(vapply(cfgs, `[[`, numeric(1), "gamma") %in% c(0, 1))) stop("FAIL config_grid_excludes_gamma0_gamma1") else cat("PASS config_grid_excludes_gamma0_gamma1\n")

# 6) Full SG04 tuner: numerical best gamma=.25, but Verhulst gamma=2 is in 5% band and must win.
g <- fx$sg04_group_tuner
res <- ag_select_sg04(num(g$x), as.integer(g$h), NULL)
if (!isTRUE(res$eligible)) stop(sprintf("FAIL sg04_group_eligible: %s:%s", res$failure_code, res$failure_detail)) else cat("PASS sg04_group_eligible\n")
if (!identical(res$selected_config_id, g$expected$selected_config_id)) stop("FAIL sg04_selected_config_id") else cat("PASS sg04_selected_config_id\n")
assert_close("sg04_selected_gamma", res$selected_config$gamma, g$expected$selected_gamma, tol = 0)
assert_close("sg04_common_origins", res$diagnostics$common_origins, g$expected$common_origins, tol = 0)
if (res$diagnostics$config_count_registered != as.integer(g$expected$config_count_registered)) stop("FAIL sg04_config_count_registered") else cat("PASS sg04_config_count_registered\n")
if (res$diagnostics$config_count_valid != as.integer(g$expected$config_count_valid)) stop("FAIL sg04_config_count_valid") else cat("PASS sg04_config_count_valid\n")
assert_close("sg04_Lmin", res$diagnostics$Lmin, g$expected$Lmin)
if (res$diagnostics$band_size != as.integer(g$expected$band_size)) stop("FAIL sg04_band_size") else cat("PASS sg04_band_size\n")
means <- vapply(res$inner_scores, `[[`, numeric(1), "mean_inner_mase")
band_ids <- vapply(res$inner_scores[means <= 1.05 * res$diagnostics$Lmin + 1e-15], `[[`, character(1), "config_id")
if (!identical(band_ids, chr(g$expected$band_config_ids))) stop("FAIL sg04_band_config_ids") else cat("PASS sg04_band_config_ids\n")
best_id <- res$inner_scores[[which.min(means)]]$config_id
if (!identical(best_id, g$expected$best_config_id)) stop("FAIL sg04_best_config_id") else cat("PASS sg04_best_config_id\n")
if (identical(best_id, res$selected_config_id) || !identical(res$selected_config_id, "gamma=2")) stop("FAIL sg04_verhulst_simplicity_override") else cat("PASS sg04_verhulst_simplicity_override\n")
assert_close("sg04_selected_inner_mase", res$diagnostics$selected_inner_mase, g$expected$selected_inner_mase)
assert_close("sg04_selected_to_best_ratio", res$diagnostics$selected_to_best_ratio, g$expected$selected_to_best_ratio)
assert_close("sg04_final_a", res$diagnostics$final_params$a, g$expected$final_params$a)
assert_close("sg04_final_b", res$diagnostics$final_params$b, g$expected$final_params$b)
assert_close("sg04_final_gamma", res$diagnostics$final_params$gamma, g$expected$final_params$gamma, tol = 0)
assert_close("sg04_final_kappa_id", res$diagnostics$final_model_diagnostics$kappa_id, g$expected$final_model_diagnostics$kappa_id, tol = as.numeric(fx$tolerances$condition_abs))
if (!identical(isTRUE(res$diagnostics$final_model_diagnostics$kappa_id_warning), isTRUE(g$expected$final_model_diagnostics$kappa_id_warning))) stop("FAIL sg04_final_kappa_id_warning") else cat("PASS sg04_final_kappa_id_warning\n")
assert_close("sg04_fitted", res$fitted, g$expected$fitted)
assert_close("sg04_forecast", res$forecast, g$expected$forecast)

exp_scores <- g$expected$scores
if (length(res$inner_scores) != length(exp_scores)) stop("FAIL sg04_score_count") else cat("PASS sg04_score_count\n")
for (i in seq_along(res$inner_scores)) {
  got <- res$inner_scores[[i]]; exp <- exp_scores[[i]]
  if (!identical(got$config_id, exp$config_id)) stop(sprintf("FAIL score_id_%02d", i))
  assert_close(sprintf("score_gamma_%02d", i), got$gamma, exp$gamma, tol = 0)
  assert_close(sprintf("score_mean_%02d", i), got$mean_inner_mase, exp$mean_inner_mase)
  assert_close(sprintf("score_origins_%02d", i), got$origin_losses, exp$origin_losses)
}

# 7) Explicit NGBM failure semantics.
for (z in fx$failure_fixtures) {
  if (identical(z$kind, "direct")) {
    err <- tryCatch({ ag_ngbm_fit_forecast(num(z$x), as.integer(z$h), as.numeric(z$gamma)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, z$expected_code)) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(z$kind, "group")) {
    rr <- ag_select_sg04(num(z$x), as.integer(z$h), NULL)
    if (isTRUE(rr$eligible) || !identical(rr$failure_code, z$expected_code)) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, rr$failure_code))
  } else stop(sprintf("FAIL unknown_failure_fixture_kind_%s", z$name))
}

# 8) Regression guards for SG01-SG03, already externally R-verified by the user.
fx1 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg01_reference_fixture_step7b1.json"), simplifyVector = TRUE)
g1 <- fx1$sg01_group_tuner; r1 <- ag_select_sg01(g1$x, g1$h, g1$M)
if (!isTRUE(r1$eligible) || !identical(r1$selected_config_id, g1$expected$selected_config_id)) stop("FAIL sg01_regression_guard_selection")
cat("PASS sg01_regression_guard_selection\n")
d1 <- max(abs(as.numeric(r1$forecast) - as.numeric(g1$expected$forecast)))
if (d1 > as.numeric(fx1$tolerances$numeric_abs)) stop("FAIL sg01_regression_guard_forecast")
cat(sprintf("PASS sg01_regression_guard_forecast         max_abs=%.3e\n", d1))

fx2 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg02_reference_fixture_step7b2.json"), simplifyVector = FALSE)
g2 <- fx2$sg02_group_tuner; r2 <- ag_select_sg02(num(g2$x), as.integer(g2$h), NULL)
if (!isTRUE(r2$eligible) || !identical(r2$selected_config_id, g2$expected$selected_config_id)) stop("FAIL sg02_regression_guard_selection")
cat("PASS sg02_regression_guard_selection\n")
d2 <- max(abs(as.numeric(r2$forecast) - num(g2$expected$forecast)))
if (d2 > as.numeric(fx2$tolerances$numeric_abs)) stop("FAIL sg02_regression_guard_forecast")
cat(sprintf("PASS sg02_regression_guard_forecast         max_abs=%.3e\n", d2))

fx3 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg03_reference_fixture_step7b3.json"), simplifyVector = FALSE)
g3 <- fx3$sg03_group_tuner; r3 <- ag_select_sg03(num(g3$x), as.integer(g3$h), NULL)
if (!isTRUE(r3$eligible) || !identical(r3$selected_config_id, g3$expected$selected_config_id)) stop("FAIL sg03_regression_guard_selection")
cat("PASS sg03_regression_guard_selection\n")
d3 <- max(abs(as.numeric(r3$forecast) - num(g3$expected$forecast)))
if (d3 > as.numeric(fx3$tolerances$numeric_abs)) stop("FAIL sg03_regression_guard_forecast")
cat(sprintf("PASS sg03_regression_guard_forecast         max_abs=%.3e\n", d3))

cat("\nSTEP7B4_SG04_PARITY: PASS\n")
