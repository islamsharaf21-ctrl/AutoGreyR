#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else "scripts/verify_step7b6_sg06.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(root, "R", "01_utils.R"))
source(file.path(root, "R", "04_mase.R"))
source(file.path(root, "R", "05_grey_common.R"))
source(file.path(root, "R", "06_structural_groups.R"))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required by the frozen Step 7A dependency contract.")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required by the frozen Step 7A dependency contract.")

fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg06_reference_fixture_step7b6.json"), simplifyVector = FALSE)
TOL <- as.numeric(fx$tolerances$numeric_abs)
COND_TOL <- as.numeric(fx$tolerances$condition_abs)
IDENTITY_TOL <- as.numeric(fx$tolerances$identity_abs)
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

# 0) Canonical provenance + byte-exact preservation of externally R-verified SG01-SG05.
ref_py <- file.path(root, "reference", "python", "autogrey_engine_step4fb_r1.py")
got_hash <- digest::digest(ref_py, algo = "sha256", file = TRUE, serialize = FALSE)
if (!identical(got_hash, as.character(fx$canonical_python_engine_sha256))) stop(sprintf("FAIL canonical_python_engine_sha256: got %s expected %s", got_hash, fx$canonical_python_engine_sha256))
cat(sprintf("PASS canonical_python_engine_sha256 %s\n", got_hash))
parent_r <- file.path(root, "reference", "r", "06_structural_groups_step7b5_verified.R")
current_r <- file.path(root, "R", "06_structural_groups.R")
con1 <- file(parent_r, "rb"); parent_raw <- readBin(con1, "raw", n = file.info(parent_r)$size); close(con1)
con2 <- file(current_r, "rb"); current_prefix <- readBin(con2, "raw", n = length(parent_raw)); close(con2)
if (!identical(parent_raw, current_prefix)) stop("FAIL sg01_sg05_source_prefix_preservation")
cat("PASS sg01_sg05_source_prefix_preservation\n")

# 1) CFA/CFD operator fixtures: alpha=0, ordinary q=1, and higher-order q=2 branches.
for (i in seq_along(fx$operator_fixtures)) {
  z <- fx$operator_fixtures[[i]]
  alpha <- as.numeric(z$alpha)
  xa <- ag_conformable_cfa(num(z$x), alpha)
  xb <- ag_conformable_cfd(xa, alpha)
  assert_close(sprintf("operator_cfa_%02d", i), xa, z$expected_cfa)
  assert_close(sprintf("operator_cfd_%02d", i), xb, z$expected_cfd_roundtrip)
  qgot <- if (ag_near(alpha, 0.0, atol = 1e-14, rtol = 0.0)) 0L else max(as.integer(ceiling(alpha - 1e-14)), 1L)
  if (qgot != as.integer(z$q)) stop(sprintf("FAIL operator_q_%02d", i)) else cat(sprintf("PASS operator_q_%02d\n", i))
}

# 2) Frozen source fixture at alpha=.59: printed CFA, inverse, parameters, fit and forecast.
s <- fx$source_cfgm_alpha_059
sx <- num(s$x); sa <- as.numeric(s$alpha)
scfa <- ag_conformable_cfa(sx, sa)
scfd <- ag_conformable_cfd(scfa, sa)
assert_close("source_cfa_full_precision", scfa, s$expected_cfa_full_precision)
assert_close("source_cfd_roundtrip", scfd, s$expected_cfd_roundtrip)
printed_d <- max(abs(scfa - num(s$printed_cfa)))
if (printed_d > 1e-3) stop(sprintf("FAIL source_printed_cfa max_abs=%.17g", printed_d)) else cat(sprintf("PASS source_printed_cfa                         max_abs=%.3e\n", printed_d))
so <- ag_cfgm_fit_forecast(sx, as.integer(s$h), sa)
assert_close("source_a", so$params$a, s$expected$params$a)
assert_close("source_b", so$params$b, s$expected$params$b)
assert_close("source_alpha", so$params$alpha, s$expected$params$alpha, tol = 0)
assert_close("source_fitted", so$fitted, s$expected$fitted)
assert_close("source_forecast", so$forecast, s$expected$forecast)
if (so$diagnostics$rank != as.integer(s$expected$diagnostics$rank)) stop("FAIL source_rank") else cat("PASS source_rank\n")
assert_close("source_condition", so$diagnostics$condition, s$expected$diagnostics$condition, tol = COND_TOL)
if (so$diagnostics$resid_df != as.integer(s$expected$diagnostics$resid_df)) stop("FAIL source_resid_df") else cat("PASS source_resid_df\n")

# 3) Direct higher-order CFGM fit forces q=2 response/restoration.
hd <- fx$higher_order_direct_fixture
hdo <- ag_cfgm_fit_forecast(num(hd$x), as.integer(hd$h), as.numeric(hd$alpha))
qgot <- max(as.integer(ceiling(as.numeric(hd$alpha) - 1e-14)), 1L)
if (qgot != as.integer(hd$q)) stop("FAIL higher_order_q") else cat("PASS higher_order_q\n")
assert_close("higher_order_a", hdo$params$a, hd$expected$params$a)
assert_close("higher_order_b", hdo$params$b, hd$expected$params$b)
assert_close("higher_order_alpha", hdo$params$alpha, hd$expected$params$alpha, tol = 0)
assert_close("higher_order_fitted", hdo$fitted, hd$expected$fitted)
assert_close("higher_order_forecast", hdo$forecast, hd$expected$forecast)
if (hdo$diagnostics$rank != as.integer(hd$expected$diagnostics$rank)) stop("FAIL higher_order_rank") else cat("PASS higher_order_rank\n")
assert_close("higher_order_condition", hdo$diagnostics$condition, hd$expected$diagnostics$condition, tol = COND_TOL)

# 4) alpha=1 is callable for identity testing but is owned by SG01, not selectable in SG06.
id <- fx$alpha1_gm_identity_fixture
ix <- num(id$x); ih <- as.integer(id$h)
c1 <- ag_cfgm_fit_forecast(ix, ih, as.numeric(id$cfgm_alpha))
g1id <- ag_gm_fit_forecast(ix, ih, as.numeric(id$gm_alpha_bg))
assert_close("alpha1_cfgm_forecast", c1$forecast, id$expected_cfgm$forecast)
assert_close("alpha1_gm_forecast", g1id$forecast, id$expected_gm_forecast)
denom <- max(mean(abs(ix)), 1e-12)
did <- max(abs(c1$forecast - g1id$forecast)) / denom
assert_close("alpha1_normalized_distance", did, id$normalized_distance, tol = IDENTITY_TOL)
if (did >= IDENTITY_TOL) stop("FAIL alpha1_gm_identity") else cat("PASS alpha1_gm_identity\n")

# 5) Exact frozen SG06 registry: 20 values, alpha=1 excluded/owned by SG01.
cg <- fx$config_generation
cfgs <- ag_sg06_configs(as.integer(cg$n), as.integer(cg$h), NULL)
got_ids <- vapply(cfgs, `[[`, character(1), "config_id")
got_a <- vapply(cfgs, `[[`, numeric(1), "alpha")
if (!identical(got_ids, chr(cg$expected_config_ids))) stop("FAIL config_generation_ids") else cat("PASS config_generation_ids\n")
assert_close("config_generation_alpha", got_a, cg$expected_alphas, tol = 0)
if (any(abs(got_a - 1.0) <= 1e-12)) stop("FAIL config_grid_excludes_alpha1") else cat("PASS config_grid_excludes_alpha1\n")
if (length(cfgs) != 20L) stop("FAIL config_generation_count") else cat("PASS config_generation_count\n")

# 6) Full SG06 tuner: all 20 configs evaluated; best alpha=.6; .7 also lies in 5% band.
g <- fx$sg06_group_tuner
res <- ag_select_sg06(num(g$x), as.integer(g$h), NULL)
if (!isTRUE(res$eligible)) stop(sprintf("FAIL sg06_group_eligible: %s:%s", res$failure_code, res$failure_detail)) else cat("PASS sg06_group_eligible\n")
if (!identical(res$selected_config_id, as.character(g$expected$selected_config_id))) stop("FAIL sg06_selected_config_id") else cat("PASS sg06_selected_config_id\n")
assert_close("sg06_selected_alpha", res$selected_config$alpha, g$expected$selected_alpha, tol = 0)
assert_close("sg06_common_origins", res$diagnostics$common_origins, g$expected$common_origins, tol = 0)
if (res$diagnostics$config_count_registered != as.integer(g$expected$config_count_registered)) stop("FAIL sg06_config_count_registered") else cat("PASS sg06_config_count_registered\n")
if (res$diagnostics$config_count_valid != as.integer(g$expected$config_count_valid)) stop("FAIL sg06_config_count_valid") else cat("PASS sg06_config_count_valid\n")
assert_close_scaled("sg06_Lmin", res$diagnostics$Lmin, g$expected$Lmin)
if (res$diagnostics$band_size != as.integer(g$expected$band_size)) stop("FAIL sg06_band_size") else cat("PASS sg06_band_size\n")
means <- vapply(res$inner_scores, `[[`, numeric(1), "mean_inner_mase")
band_ids <- vapply(res$inner_scores[means <= 1.05 * res$diagnostics$Lmin + 1e-15], `[[`, character(1), "config_id")
if (!identical(band_ids, chr(g$expected$band_config_ids))) stop("FAIL sg06_band_config_ids") else cat("PASS sg06_band_config_ids\n")
best_id <- res$inner_scores[[which.min(means)]]$config_id
if (!identical(best_id, as.character(g$expected$best_config_id))) stop("FAIL sg06_best_config_id") else cat("PASS sg06_best_config_id\n")
if (!identical(best_id, res$selected_config_id)) stop("FAIL sg06_loss_first_selection") else cat("PASS sg06_loss_first_selection\n")
assert_close_scaled("sg06_selected_inner_mase", res$diagnostics$selected_inner_mase, g$expected$selected_inner_mase)
assert_close_scaled("sg06_selected_to_best_ratio", res$diagnostics$selected_to_best_ratio, g$expected$selected_to_best_ratio)
assert_close("sg06_final_a", res$diagnostics$final_params$a, g$expected$final_params$a)
assert_close("sg06_final_b", res$diagnostics$final_params$b, g$expected$final_params$b)
assert_close("sg06_final_alpha", res$diagnostics$final_params$alpha, g$expected$final_params$alpha, tol = 0)
assert_close("sg06_final_condition", res$diagnostics$final_model_diagnostics$condition, g$expected$final_model_diagnostics$condition, tol = COND_TOL)
assert_close("sg06_fitted", res$fitted, g$expected$fitted)
assert_close("sg06_forecast", res$forecast, g$expected$forecast)

exp_scores <- g$expected$scores
if (length(res$inner_scores) != length(exp_scores)) stop("FAIL sg06_score_count") else cat("PASS sg06_score_count\n")
for (i in seq_along(res$inner_scores)) {
  got <- res$inner_scores[[i]]; exp <- exp_scores[[i]]
  if (!identical(got$config_id, as.character(exp$config_id))) stop(sprintf("FAIL score_id_%02d", i))
  assert_close(sprintf("score_alpha_%02d", i), got$alpha, exp$alpha, tol = 0)
  assert_close_scaled(sprintf("score_mean_%02d", i), got$mean_inner_mase, exp$mean_inner_mase)
  assert_close_scaled(sprintf("score_origins_%02d", i), got$origin_losses, exp$origin_losses)
}

# 7) Explicit CFGM failure semantics.
for (z in fx$failure_fixtures) {
  kind <- as.character(z$kind)
  if (identical(kind, "cfa")) {
    err <- tryCatch({ ag_conformable_cfa(num(z$x), as.numeric(z$alpha)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "cfd")) {
    err <- tryCatch({ ag_conformable_cfd(num(z$xa), as.numeric(z$alpha)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "model")) {
    err <- tryCatch({ ag_cfgm_fit_forecast(num(z$x), as.integer(z$h), as.numeric(z$alpha)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "group")) {
    rr <- ag_select_sg06(num(z$x), as.integer(z$h), NULL)
    if (isTRUE(rr$eligible) || !identical(rr$failure_code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, rr$failure_code))
  } else stop(sprintf("FAIL unknown_failure_fixture_kind_%s", z$name))
}

# 8) Regression guards for SG01-SG05 — each previous checkpoint already externally R-verified.
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

cat("\nSTEP7B6_SG06_PARITY: PASS\n")
