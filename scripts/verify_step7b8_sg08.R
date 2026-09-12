#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else "scripts/verify_step7b8_sg08.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(root, "R", "01_utils.R"))
source(file.path(root, "R", "04_mase.R"))
source(file.path(root, "R", "05_grey_common.R"))
source(file.path(root, "R", "06_structural_groups.R"))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required by the frozen Step 7A dependency contract.")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required by the frozen Step 7A dependency contract.")

fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg08_reference_fixture_step7b8.json"), simplifyVector = FALSE)
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
  cat(sprintf("PASS %-56s max_abs=%.3e\n", name, d))
}
assert_close_scaled <- function(name, got, exp, atol = SCORE_ABS, rtol = SCORE_REL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  d <- if (length(got)) max(abs(got - exp)) else 0
  scale <- if (length(exp)) max(1.0, max(abs(exp))) else 1.0
  lim <- atol + rtol * scale
  if (d > lim) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g", name, d, lim))
  cat(sprintf("PASS %-56s max_abs=%.3e\n", name, d))
}

# 0) Canonical provenance and exact preservation of externally R-verified SG01-SG07 source.
engine_path <- file.path(root, "reference", "python", "autogrey_engine_step4fb_r1.py")
engine_sha <- digest::digest(file = engine_path, algo = "sha256", serialize = FALSE)
if (!identical(engine_sha, as.character(fx$canonical_python_engine_sha256))) stop("FAIL canonical_python_engine_sha256")
cat(sprintf("PASS canonical_python_engine_sha256 %s\n", engine_sha))

parent_path <- file.path(root, "reference", "r", "06_structural_groups_step7b7_verified.R")
current_path <- file.path(root, "R", "06_structural_groups.R")
read_raw <- function(p) { con <- file(p, "rb"); on.exit(close(con)); readBin(con, "raw", n = file.info(p)$size) }
parent_raw <- read_raw(parent_path); current_raw <- read_raw(current_path)
if (length(current_raw) < length(parent_raw) || !identical(current_raw[seq_along(parent_raw)], parent_raw)) stop("FAIL sg01_sg07_source_prefix_preservation")
cat("PASS sg01_sg07_source_prefix_preservation\n")

# 1) Average-WBO operator definition and fixed point.
d <- fx$direct_recursive_fixture
op <- d$operator_fixture
ow <- ag_average_wbo(num(op$x))
assert_close("operator_suffix_mean", ow, op$expected_wbo)
assert_close("operator_manual_suffix_mean", ow, op$manual_suffix_means)
assert_close("operator_fixed_point", tail(ow, 1L), op$fixed_point, tol = 0)

# 2) Direct recursive SG08 forecast and every recomputed WBO/GM refit.
x <- num(d$x); h <- as.integer(d$h)
out <- ag_wbo_gm_forecast(x, h)
assert_close("direct_forecast", out$forecast, d$expected$forecast)
assert_close("direct_fitted_placeholder", out$fitted, d$expected$fitted, tol = 0)
if (!identical(out$params$operator, as.character(d$expected$params$operator))) stop("FAIL direct_param_operator") else cat("PASS direct_param_operator\n")
assert_close("direct_param_alpha_bg", out$params$alpha_bg, d$expected$params$alpha_bg, tol = 0)
if (out$diagnostics$recursive_refits != as.integer(d$expected$diagnostics$recursive_refits)) stop("FAIL direct_recursive_refits") else cat("PASS direct_recursive_refits\n")
if (!identical(out$diagnostics$output_scale, as.character(d$expected$diagnostics$output_scale))) stop("FAIL direct_output_scale") else cat("PASS direct_output_scale\n")
if (!isTRUE(d$fitted_equals_observed) || !identical(as.numeric(out$fitted), as.numeric(x))) stop("FAIL direct_fitted_equals_observed") else cat("PASS direct_fitted_equals_observed\n")

pseudo <- as.numeric(x)
for (i in seq_along(d$recursive_steps)) {
  z <- d$recursive_steps[[i]]
  # Later pseudo histories inherit tiny R/Python differences from earlier forecasts.
  assert_close(sprintf("recursive_history_%02d", i), pseudo, z$pseudo_history, tol = if (i == 1L) 0 else TOL)
  wb <- ag_average_wbo(pseudo)
  assert_close(sprintf("recursive_wbo_%02d", i), wb, z$wbo)
  assert_close(sprintf("recursive_fixed_point_%02d", i), tail(wb,1L), z$wbo_fixed_point)
  gm <- ag_gm_fit_forecast(wb, 1L, 0.5)
  assert_close(sprintf("recursive_forecast_%02d", i), gm$forecast[1L], z$gm_forecast)
  assert_close(sprintf("recursive_a_%02d", i), gm$params$a, z$gm_a)
  assert_close(sprintf("recursive_b_%02d", i), gm$params$b, z$gm_b)
  assert_close(sprintf("recursive_alpha_bg_%02d", i), gm$params$alpha_bg, z$gm_alpha_bg, tol = 0)
  assert_close(sprintf("recursive_condition_%02d", i), gm$diagnostics$condition, z$gm_condition, tol = COND_TOL)
  if (gm$diagnostics$rank != as.integer(z$gm_rank)) stop(sprintf("FAIL recursive_rank_%02d", i)) else cat(sprintf("PASS recursive_rank_%02d\n", i))
  pseudo <- c(pseudo, as.numeric(gm$forecast[1L]))
}
assert_close("recursive_steps_reconstruct_forecast", tail(pseudo, h), d$expected$forecast)

# 3) Exact frozen registry: one and only one average_WBO config.
cg <- fx$config_generation
cfgs <- ag_sg08_configs(as.integer(cg$n), as.integer(cg$h), NULL)
got_ids <- vapply(cfgs, `[[`, character(1), "config_id")
if (!identical(got_ids, chr(cg$expected_config_ids))) stop("FAIL config_generation_ids") else cat("PASS config_generation_ids\n")
if (length(cfgs) != 1L || !identical(got_ids[1L], "average_WBO")) stop("FAIL config_generation_singleton_average_wbo") else cat("PASS config_generation_singleton_average_wbo\n")

# 4) Full SG08 group selection over common origins.
g <- fx$sg08_group_tuner
res <- ag_select_sg08(num(g$x), as.integer(g$h), NULL)
if (!isTRUE(res$eligible)) stop(sprintf("FAIL sg08_group_eligible: %s:%s", res$failure_code, res$failure_detail)) else cat("PASS sg08_group_eligible\n")
if (!identical(res$selected_config_id, as.character(g$expected$selected_config_id))) stop("FAIL sg08_selected_config_id") else cat("PASS sg08_selected_config_id\n")
if (length(res$selected_config) != 0L) stop("FAIL sg08_selected_config_empty") else cat("PASS sg08_selected_config_empty\n")
assert_close("sg08_common_origins", res$diagnostics$common_origins, g$expected$common_origins, tol = 0)
if (res$diagnostics$config_count_registered != as.integer(g$expected$config_count_registered)) stop("FAIL sg08_config_count_registered") else cat("PASS sg08_config_count_registered\n")
if (res$diagnostics$config_count_valid != as.integer(g$expected$config_count_valid)) stop("FAIL sg08_config_count_valid") else cat("PASS sg08_config_count_valid\n")
assert_close_scaled("sg08_Lmin", res$diagnostics$Lmin, g$expected$Lmin)
if (res$diagnostics$band_size != as.integer(g$expected$band_size)) stop("FAIL sg08_band_size") else cat("PASS sg08_band_size\n")
means <- vapply(res$inner_scores, `[[`, numeric(1), "mean_inner_mase")
band_ids <- vapply(res$inner_scores[means <= 1.05 * res$diagnostics$Lmin + 1e-15], `[[`, character(1), "config_id")
if (!identical(band_ids, chr(g$expected$band_config_ids))) stop("FAIL sg08_band_config_ids") else cat("PASS sg08_band_config_ids\n")
best_id <- res$inner_scores[[which.min(means)]]$config_id
if (!identical(best_id, as.character(g$expected$best_config_id))) stop("FAIL sg08_best_config_id") else cat("PASS sg08_best_config_id\n")
if (length(res$inner_scores) != 1L || !identical(res$selected_config_id, best_id)) stop("FAIL sg08_singleton_selection") else cat("PASS sg08_singleton_selection\n")
assert_close_scaled("sg08_selected_inner_mase", res$diagnostics$selected_inner_mase, g$expected$selected_inner_mase)
assert_close_scaled("sg08_selected_to_best_ratio", res$diagnostics$selected_to_best_ratio, g$expected$selected_to_best_ratio)
if (!identical(res$diagnostics$final_params$operator, as.character(g$expected$final_params$operator))) stop("FAIL sg08_final_operator") else cat("PASS sg08_final_operator\n")
assert_close("sg08_final_alpha_bg", res$diagnostics$final_params$alpha_bg, g$expected$final_params$alpha_bg, tol = 0)
if (res$diagnostics$final_model_diagnostics$recursive_refits != as.integer(g$expected$final_model_diagnostics$recursive_refits)) stop("FAIL sg08_final_recursive_refits") else cat("PASS sg08_final_recursive_refits\n")
if (!identical(res$diagnostics$final_model_diagnostics$output_scale, as.character(g$expected$final_model_diagnostics$output_scale))) stop("FAIL sg08_final_output_scale") else cat("PASS sg08_final_output_scale\n")
assert_close("sg08_fitted", res$fitted, g$expected$fitted, tol = 0)
assert_close("sg08_forecast", res$forecast, g$expected$forecast)

exp_scores <- g$expected$scores
if (length(res$inner_scores) != length(exp_scores)) stop("FAIL sg08_score_count") else cat("PASS sg08_score_count\n")
for (i in seq_along(res$inner_scores)) {
  got <- res$inner_scores[[i]]; exp <- exp_scores[[i]]
  if (!identical(got$config_id, as.character(exp$config_id))) stop(sprintf("FAIL score_id_%02d", i))
  if (length(got$config) != 0L) stop(sprintf("FAIL score_config_%02d", i)) else cat(sprintf("PASS score_config_%02d\n", i))
  assert_close_scaled(sprintf("score_mean_%02d", i), got$mean_inner_mase, exp$mean_inner_mase)
  assert_close_scaled(sprintf("score_origins_%02d", i), got$origin_losses, exp$origin_losses)
  for (j in seq_along(got$diagnostics$origin_diagnostics)) {
    gd <- got$diagnostics$origin_diagnostics[[j]]; ed <- exp$origin_diagnostics[[j]]
    if (gd$recursive_refits != as.integer(ed$recursive_refits)) stop(sprintf("FAIL score_origin_refits_%02d_%02d", i, j))
    if (!identical(gd$output_scale, as.character(ed$output_scale))) stop(sprintf("FAIL score_origin_output_scale_%02d_%02d", i, j))
  }
  cat(sprintf("PASS score_origin_diagnostics_%02d\n", i))
}

# 5) Explicit SG08 failure semantics.
for (z in fx$failure_fixtures) {
  kind <- as.character(z$kind)
  if (identical(kind, "model")) {
    err <- tryCatch({ ag_wbo_gm_forecast(num(z$x), as.integer(z$h)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "operator")) {
    err <- tryCatch({ suppressWarnings(ag_average_wbo(num(z$x))); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "group")) {
    rr <- ag_select_sg08(num(z$x), as.integer(z$h), NULL)
    if (isTRUE(rr$eligible) || !identical(rr$failure_code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, rr$failure_code))
  } else stop(sprintf("FAIL unknown_failure_fixture_kind_%s", z$name))
}

# 6) Regression guards for SG01-SG07 — all seven prior checkpoints were externally R-verified.
fx1 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg01_reference_fixture_step7b1.json"), simplifyVector = TRUE)
g1 <- fx1$sg01_group_tuner; r1 <- ag_select_sg01(g1$x, g1$h, g1$M)
if (!isTRUE(r1$eligible) || !identical(r1$selected_config_id, g1$expected$selected_config_id)) stop("FAIL sg01_regression_guard_selection")
cat("PASS sg01_regression_guard_selection\n")
d1 <- max(abs(as.numeric(r1$forecast) - as.numeric(g1$expected$forecast)))
if (d1 > as.numeric(fx1$tolerances$numeric_abs)) stop("FAIL sg01_regression_guard_forecast")
cat(sprintf("PASS sg01_regression_guard_forecast         max_abs=%.3e\n", d1))

for (k in 2:7) {
  fpath <- file.path(root, "inst", "extdata", sprintf("sg%02d_reference_fixture_step7b%d.json", k, k))
  fxk <- jsonlite::fromJSON(fpath, simplifyVector = FALSE)
  gname <- sprintf("sg%02d_group_tuner", k)
  gk <- fxk[[gname]]
  fn <- get(sprintf("ag_select_sg%02d", k), mode = "function")
  rk <- fn(num(gk$x), as.integer(gk$h), NULL)
  if (!isTRUE(rk$eligible) || !identical(rk$selected_config_id, as.character(gk$expected$selected_config_id))) stop(sprintf("FAIL sg%02d_regression_guard_selection", k))
  cat(sprintf("PASS sg%02d_regression_guard_selection\n", k))
  dk <- max(abs(as.numeric(rk$forecast) - num(gk$expected$forecast)))
  if (dk > as.numeric(fxk$tolerances$numeric_abs)) stop(sprintf("FAIL sg%02d_regression_guard_forecast", k))
  cat(sprintf("PASS sg%02d_regression_guard_forecast         max_abs=%.3e\n", k, dk))
}

cat("\nSTEP7B8_SG08_PARITY: PASS\n")
