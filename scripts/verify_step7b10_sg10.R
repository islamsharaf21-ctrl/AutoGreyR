#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else "scripts/verify_step7b10_sg10.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(root, "R", "01_utils.R"))
source(file.path(root, "R", "04_mase.R"))
source(file.path(root, "R", "05_grey_common.R"))
source(file.path(root, "R", "06_structural_groups.R"))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required by the frozen Step 7A dependency contract.")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required by the frozen Step 7A dependency contract.")

fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg10_reference_fixture_step7b10.json"), simplifyVector = FALSE)
TOL <- as.numeric(fx$tolerances$numeric_abs)
COND_TOL <- as.numeric(fx$tolerances$condition_abs)
SCORE_ABS <- as.numeric(fx$tolerances$score_abs)
SCORE_REL <- as.numeric(fx$tolerances$score_rel)
num <- function(x) as.numeric(unlist(x, use.names = FALSE))
chr <- function(x) as.character(unlist(x, use.names = FALSE))
ints <- function(x) as.integer(unlist(x, use.names = FALSE))

assert_close <- function(name, got, exp, tol = TOL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  d <- if (length(got)) max(abs(got - exp)) else 0
  if (d > tol) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g", name, d, tol))
  cat(sprintf("PASS %-62s max_abs=%.3e\n", name, d))
}
assert_close_scaled <- function(name, got, exp, atol = SCORE_ABS, rtol = SCORE_REL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  d <- if (length(got)) max(abs(got - exp)) else 0
  scale <- if (length(exp)) max(1.0, max(abs(exp))) else 1.0
  lim <- atol + rtol * scale
  if (d > lim) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g", name, d, lim))
  cat(sprintf("PASS %-62s max_abs=%.3e\n", name, d))
}
assert_int <- function(name, got, exp) {
  if (!identical(as.integer(got), as.integer(exp))) stop(sprintf("FAIL %s", name))
  cat(sprintf("PASS %s\n", name))
}
assert_chr <- function(name, got, exp) {
  if (!identical(as.character(got), as.character(exp))) stop(sprintf("FAIL %s", name))
  cat(sprintf("PASS %s\n", name))
}
assert_diag <- function(prefix, got, exp) {
  assert_int(paste0(prefix, "_rank"), got$rank, exp$rank)
  assert_close(paste0(prefix, "_condition"), got$condition, exp$condition, tol = COND_TOL)
  assert_int(paste0(prefix, "_rows"), got$rows, exp$rows)
  assert_int(paste0(prefix, "_params"), got$params, exp$params)
  assert_int(paste0(prefix, "_resid_df"), got$resid_df, exp$resid_df)
}

# 0) Canonical provenance and exact preservation of externally R-verified SG01-SG09 source.
engine_path <- file.path(root, "reference", "python", "autogrey_engine_step4fb_r1.py")
engine_sha <- digest::digest(file = engine_path, algo = "sha256", serialize = FALSE)
if (!identical(engine_sha, as.character(fx$canonical_python_engine_sha256))) stop("FAIL canonical_python_engine_sha256")
cat(sprintf("PASS canonical_python_engine_sha256 %s\n", engine_sha))

parent_path <- file.path(root, "reference", "r", "06_structural_groups_step7b9_verified.R")
current_path <- file.path(root, "R", "06_structural_groups.R")
read_raw <- function(p) { con <- file(p, "rb"); on.exit(close(con)); readBin(con, "raw", n = file.info(p)$size) }
parent_raw <- read_raw(parent_path); current_raw <- read_raw(current_path)
if (length(current_raw) < length(parent_raw) || !identical(current_raw[seq_along(parent_raw)], parent_raw)) stop("FAIL sg01_sg09_source_prefix_preservation")
cat("PASS sg01_sg09_source_prefix_preservation\n")

# 1) Seasonal-factor operator fixture: training-only phase means / overall mean.
o <- fx$operator_fixture
ox <- num(o$x); OM <- as.integer(o$M)
of <- ag_seasonal_factors(ox, OM)
assert_close("operator_factors", of, o$expected_factors)
manual <- numeric(OM)
for (s in 0L:(OM - 1L)) manual[s + 1L] <- mean(ox[seq.int(s + 1L, length(ox), by = OM)]) / mean(ox)
assert_close("operator_manual_factors", manual, o$manual_factors)
assert_close("operator_mean_factor_one", mean(of), o$expected_mean_factor, tol = 1e-14)

# 2) Wang-Li-Pei (2018) source-backed SGM reproduction already frozen in B1.
s <- fx$source_wang_li_pei_2018
sx <- num(s$train); sy <- num(s$test); sh <- as.integer(s$h); SM <- as.integer(s$M)
sout <- ag_sgm_fit_forecast(sx, sh, SM)
assert_close("source_factors_full_precision", sout$params$factors, s$expected$params$factors)
assert_close("source_a_full_precision", sout$params$a, s$expected$params$a)
assert_close("source_b_full_precision", sout$params$b, s$expected$params$b)
assert_int("source_M", sout$params$M, s$expected$params$M)
assert_close("source_fitted", sout$fitted, s$expected$fitted)
assert_close("source_forecast", sout$forecast, s$expected$forecast)
assert_diag("source", sout$diagnostics, s$expected$diagnostics)
assert_close("source_published_factors", sout$params$factors, s$expected_published_factors, tol = as.numeric(fx$tolerances$source_factor_abs))
assert_close("source_published_a", sout$params$a, s$expected_published_a, tol = as.numeric(fx$tolerances$source_a_abs))
assert_close("source_published_b", sout$params$b, s$expected_published_b, tol = as.numeric(fx$tolerances$source_b_abs))
mape <- mean(abs((sy - sout$forecast) / sy)) * 100
assert_close("source_holdout_mape_full_precision", mape, s$holdout_mape_percent_full_precision)
assert_close("source_published_holdout_mape", mape, s$expected_published_holdout_mape_percent, tol = as.numeric(fx$tolerances$source_mape_abs))
gmcmp <- ag_gm_fit_forecast(sx, sh, 0.5)
assert_close("source_gm_comparator_full_precision", gmcmp$forecast, s$gm_comparator_forecast_full_precision)
if (!identical(round(as.numeric(gmcmp$forecast), 2), num(s$gm_comparator_table5_rounded))) stop("FAIL source_gm_comparator_table5_rounded") else cat("PASS source_gm_comparator_table5_rounded\n")

# 3) Exact SG10 registry: one known-M configuration only.
cg <- fx$config_generation
cfgs <- ag_sg10_configs(as.integer(cg$n), as.integer(cg$h), as.integer(cg$M))
ids <- vapply(cfgs, `[[`, character(1), "config_id")
if (!identical(ids, chr(cg$expected_config_ids))) stop("FAIL config_generation_ids") else cat("PASS config_generation_ids\n")
if (length(cfgs) != 1L) stop("FAIL config_generation_singleton") else cat("PASS config_generation_singleton\n")
assert_int("config_generation_M", cfgs[[1L]]$M, cg$expected_configs[[1L]]$M)
if (length(ag_sg10_configs(as.integer(cg$n), as.integer(cg$h), NULL)) != 0L) stop("FAIL config_generation_missing_M_empty") else cat("PASS config_generation_missing_M_empty\n")

# 4) Full SG10 group selection: singleton config, seasonal MASE at three common origins.
g <- fx$sg10_group_tuner
res <- ag_select_sg10(num(g$x), as.integer(g$h), as.integer(g$M))
if (!isTRUE(res$eligible)) stop(sprintf("FAIL sg10_group_eligible: %s:%s", res$failure_code, res$failure_detail)) else cat("PASS sg10_group_eligible\n")
assert_chr("sg10_selected_config_id", res$selected_config_id, g$expected$selected_config_id)
assert_int("sg10_selected_M", res$selected_config$M, g$expected$selected_config$M)
if (!identical(res$diagnostics$common_origins, ints(g$expected$common_origins))) stop("FAIL sg10_common_origins") else cat("PASS sg10_common_origins\n")
assert_int("sg10_config_count_registered", res$diagnostics$config_count_registered, g$expected$config_count_registered)
assert_int("sg10_config_count_valid", res$diagnostics$config_count_valid, g$expected$config_count_valid)
assert_close_scaled("sg10_Lmin", res$diagnostics$Lmin, g$expected$Lmin)
assert_int("sg10_band_size", res$diagnostics$band_size, g$expected$band_size)
means <- vapply(res$inner_scores, `[[`, numeric(1), "mean_inner_mase")
band_ids <- vapply(res$inner_scores[means <= 1.05 * res$diagnostics$Lmin + 1e-15], `[[`, character(1), "config_id")
if (!identical(band_ids, chr(g$expected$band_config_ids))) stop("FAIL sg10_band_config_ids") else cat("PASS sg10_band_config_ids\n")
best_id <- res$inner_scores[[which.min(means)]]$config_id
assert_chr("sg10_best_config_id", best_id, g$expected$best_config_id)
if (length(res$inner_scores) != 1L || res$selected_config_id != "M=4") stop("FAIL sg10_singleton_selection") else cat("PASS sg10_singleton_selection\n")
assert_close_scaled("sg10_selected_inner_mase", res$diagnostics$selected_inner_mase, g$expected$selected_inner_mase)
assert_close_scaled("sg10_selected_to_best_ratio", res$diagnostics$selected_to_best_ratio, g$expected$selected_to_best_ratio)
assert_close("sg10_final_a", res$diagnostics$final_params$a, g$expected$final_params$a)
assert_close("sg10_final_b", res$diagnostics$final_params$b, g$expected$final_params$b)
assert_int("sg10_final_M", res$diagnostics$final_params$M, g$expected$final_params$M)
assert_close("sg10_final_factors", res$diagnostics$final_params$factors, g$expected$final_params$factors)
assert_diag("sg10_final", res$diagnostics$final_model_diagnostics, g$expected$final_model_diagnostics)
assert_close("sg10_fitted", res$fitted, g$expected$fitted)
assert_close("sg10_forecast", res$forecast, g$expected$forecast)

exp_scores <- g$expected$scores
if (length(res$inner_scores) != length(exp_scores)) stop("FAIL sg10_score_count") else cat("PASS sg10_score_count\n")
for (i in seq_along(res$inner_scores)) {
  got <- res$inner_scores[[i]]; exp <- exp_scores[[i]]
  assert_chr(sprintf("score_id_%02d", i), got$config_id, exp$config_id)
  assert_int(sprintf("score_M_%02d", i), got$config$M, exp$config$M)
  assert_close_scaled(sprintf("score_mean_%02d", i), got$mean_inner_mase, exp$mean_inner_mase)
  assert_close_scaled(sprintf("score_origins_%02d", i), got$origin_losses, exp$origin_losses)
  if (length(got$diagnostics$origin_diagnostics) != 3L) stop(sprintf("FAIL score_origin_diag_count_%02d", i))
  for (j in seq_len(3L)) assert_diag(sprintf("score_diag_%02d_%02d", i, j), got$diagnostics$origin_diagnostics[[j]], exp$origin_diagnostics[[j]])
  cat(sprintf("PASS score_origin_diagnostics_%02d\n", i))
}

# 5) Final-refit failure is explicit; no fallback/reinterpretation after selection.
fr <- fx$final_refit_failure_fixture
rr <- ag_select_sg10(num(fr$x), as.integer(fr$h), as.integer(fr$M))
if (isTRUE(rr$eligible)) stop("FAIL final_refit_failure_fixture_eligible")
assert_chr("final_refit_selected_config_id", rr$selected_config_id, fr$expected_selected_config_id)
assert_chr("final_refit_failure_code", rr$failure_code, fr$expected_failure_code)
if (!startsWith(as.character(rr$failure_detail), as.character(fr$expected_failure_detail_prefix))) stop("FAIL final_refit_failure_detail") else cat("PASS final_refit_failure_detail\n")
assert_close_scaled("final_refit_inner_mean", rr$inner_scores[[1L]]$mean_inner_mase, fr$expected_inner_score$mean_inner_mase)
assert_close_scaled("final_refit_inner_origins", rr$inner_scores[[1L]]$origin_losses, fr$expected_inner_score$origin_losses)

# 6) Explicit SG10 operator/model/group refusal semantics and precheck ordering.
for (z in fx$failure_fixtures) {
  kind <- as.character(z$kind)
  if (identical(kind, "operator")) {
    err <- tryCatch({ ag_seasonal_factors(num(z$x), as.integer(z$M)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "model")) {
    err <- tryCatch({ ag_sgm_fit_forecast(num(z$x), as.integer(z$h), as.integer(z$M)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "group")) {
    mval <- if (is.null(z$M)) NULL else as.integer(z$M)
    gr <- ag_select_sg10(num(z$x), as.integer(z$h), mval)
    if (isTRUE(gr$eligible) || !identical(gr$failure_code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, gr$failure_code))
  } else stop(sprintf("FAIL unknown_failure_fixture_kind_%s", z$name))
}

# 7) Regression guards for SG01-SG09 — all nine prior checkpoints were externally R-verified.
fx1 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg01_reference_fixture_step7b1.json"), simplifyVector = TRUE)
g1 <- fx1$sg01_group_tuner; r1 <- ag_select_sg01(g1$x, g1$h, g1$M)
if (!isTRUE(r1$eligible) || !identical(r1$selected_config_id, g1$expected$selected_config_id)) stop("FAIL sg01_regression_guard_selection")
cat("PASS sg01_regression_guard_selection\n")
d1 <- max(abs(as.numeric(r1$forecast) - as.numeric(g1$expected$forecast)))
if (d1 > as.numeric(fx1$tolerances$numeric_abs)) stop("FAIL sg01_regression_guard_forecast")
cat(sprintf("PASS sg01_regression_guard_forecast         max_abs=%.3e\n", d1))

for (k in 2:9) {
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

cat("\nSTEP7B10_SG10_PARITY: PASS\n")
