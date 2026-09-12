#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else "scripts/verify_step7b3_sg03.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(root, "R", "01_utils.R"))
source(file.path(root, "R", "04_mase.R"))
source(file.path(root, "R", "05_grey_common.R"))
source(file.path(root, "R", "06_structural_groups.R"))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required by the frozen Step 7A dependency contract.")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required by the frozen Step 7A dependency contract.")

fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg03_reference_fixture_step7b3.json"), simplifyVector = FALSE)
TOL <- as.numeric(fx$tolerances$numeric_abs)
ref_py <- file.path(root, "reference", "python", "autogrey_engine_step4fb_r1.py")
got_hash <- digest::digest(ref_py, algo = "sha256", file = TRUE, serialize = FALSE)
if (!identical(got_hash, fx$canonical_python_engine_sha256)) stop(sprintf("FAIL canonical_python_engine_sha256: got %s expected %s", got_hash, fx$canonical_python_engine_sha256))
cat(sprintf("PASS canonical_python_engine_sha256 %s\n", got_hash))

num <- function(x) as.numeric(unlist(x, use.names = FALSE))
int <- function(x) as.integer(unlist(x, use.names = FALSE))
chr <- function(x) as.character(unlist(x, use.names = FALSE))

assert_close <- function(name, got, exp, tol = TOL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  d <- if (length(got)) max(abs(got - exp)) else 0
  if (d > tol) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g", name, d, tol))
  cat(sprintf("PASS %-44s max_abs=%.3e\n", name, d))
}

# 1) Fractional operator algebra, including general non-selectable orders.
op <- fx$fractional_operator_fixture
xop <- num(op$x)
for (i in seq_along(op$cases)) {
  z <- op$cases[[i]]; r <- as.numeric(z$r)
  tag <- gsub("\\.", "p", format(r, trim = TRUE, scientific = FALSE))
  w <- ag_fractional_weights(r, length(xop))
  ago <- ag_fractional_ago(xop, r)
  back <- ag_fractional_iago(ago, r)
  assert_close(paste0("operator_weights_r", tag), w, z$weights, tol = as.numeric(fx$tolerances$operator_abs))
  assert_close(paste0("operator_ago_r", tag), ago, z$ago, tol = as.numeric(fx$tolerances$operator_abs))
  assert_close(paste0("operator_roundtrip_r", tag), back, xop, tol = as.numeric(fx$tolerances$operator_abs))
}
assert_close("operator_r1_is_ordinary_ago", ag_fractional_ago(xop, 1.0), op$r1_expected_ago, tol = as.numeric(fx$tolerances$operator_abs))

# 2) Wu et al. (2013) Table 2, r=0.3 source-faithful fixture.
w <- fx$wu2013_table2_r03
out <- ag_fgm_fit_forecast(num(w$x), as.integer(w$h), as.numeric(w$r))
assert_close("wu_a", out$params$a, w$expected$params$a)
assert_close("wu_b", out$params$b, w$expected$params$b)
assert_close("wu_c", out$params$c, w$expected$params$c)
assert_close("wu_d", out$params$d, w$expected$params$d)
assert_close("wu_r", out$params$r, w$expected$params$r, tol = 0)
assert_close("wu_fitted", out$fitted, w$expected$fitted)
assert_close("wu_forecast", out$forecast, w$expected$forecast)
assert_close("wu_combined_full_precision", c(out$fitted, out$forecast), w$expected$combined)
assert_close("wu_printed_table2_r03", c(out$fitted, out$forecast), w$printed_expected_combined, tol = as.numeric(fx$tolerances$printed_source_abs))
fit_mape <- mean(abs((num(w$x) - out$fitted) / num(w$x))) * 100
test_mape <- mean(abs((num(w$y_test) - out$forecast) / num(w$y_test))) * 100
assert_close("wu_fit_mape_percent", fit_mape, w$expected$fit_mape_percent, tol = as.numeric(fx$tolerances$mape_abs))
assert_close("wu_test_mape_percent", test_mape, w$expected$test_mape_percent, tol = as.numeric(fx$tolerances$mape_abs))
if (out$diagnostics$rank != as.integer(w$expected$diagnostics$rank)) stop("FAIL wu_rank") else cat("PASS wu_rank\n")
assert_close("wu_condition", out$diagnostics$condition, w$expected$diagnostics$condition, tol = as.numeric(fx$tolerances$condition_abs))
if (out$diagnostics$cd_rank != as.integer(w$expected$diagnostics$cd_rank)) stop("FAIL wu_cd_rank") else cat("PASS wu_cd_rank\n")
assert_close("wu_cd_condition", out$diagnostics$cd_condition, w$expected$diagnostics$cd_condition, tol = as.numeric(fx$tolerances$condition_abs))
if (!identical(out$diagnostics$response_convention, w$expected$diagnostics$response_convention)) stop("FAIL wu_response_convention") else cat("PASS wu_response_convention\n")
if (!identical(out$diagnostics$r1_owner, w$expected$diagnostics$r1_owner)) stop("FAIL wu_r1_owner") else cat("PASS wu_r1_owner\n")

# 3) Frozen SG03 config generation: exactly r=0.1..0.9.
cg <- fx$config_generation
cfgs <- ag_sg03_configs(as.integer(cg$n), as.integer(cg$h), NULL)
got_ids <- vapply(cfgs, `[[`, character(1), "config_id")
if (!identical(got_ids, chr(cg$expected_config_ids))) stop("FAIL config_generation_ids") else cat("PASS config_generation_ids\n")
assert_close("config_generation_r", vapply(cfgs, `[[`, numeric(1), "r"), cg$expected_r, tol = 0)

# 4) Full nine-r SG03 group tuner. 5% band has r=.5,.6,.7; loss-first key selects .6.
g <- fx$sg03_group_tuner
res <- ag_select_sg03(num(g$x), as.integer(g$h), NULL)
if (!isTRUE(res$eligible)) stop(sprintf("FAIL sg03_group_eligible: %s:%s", res$failure_code, res$failure_detail)) else cat("PASS sg03_group_eligible\n")
if (!identical(res$selected_config_id, g$expected$selected_config_id)) stop("FAIL sg03_selected_config_id") else cat("PASS sg03_selected_config_id\n")
assert_close("sg03_selected_r", res$selected_config$r, g$expected$selected_r, tol = 0)
assert_close("sg03_common_origins", res$diagnostics$common_origins, g$expected$common_origins, tol = 0)
if (res$diagnostics$config_count_registered != as.integer(g$expected$config_count_registered)) stop("FAIL sg03_config_count_registered") else cat("PASS sg03_config_count_registered\n")
if (res$diagnostics$config_count_valid != as.integer(g$expected$config_count_valid)) stop("FAIL sg03_config_count_valid") else cat("PASS sg03_config_count_valid\n")
assert_close("sg03_Lmin", res$diagnostics$Lmin, g$expected$Lmin)
if (res$diagnostics$band_size != as.integer(g$expected$band_size)) stop("FAIL sg03_band_size") else cat("PASS sg03_band_size\n")
means <- vapply(res$inner_scores, `[[`, numeric(1), "mean_inner_mase")
band_ids <- vapply(res$inner_scores[means <= 1.05 * res$diagnostics$Lmin + 1e-15], `[[`, character(1), "config_id")
if (!identical(band_ids, chr(g$expected$band_config_ids))) stop("FAIL sg03_band_config_ids") else cat("PASS sg03_band_config_ids\n")
best_id <- res$inner_scores[[which.min(means)]]$config_id
if (!identical(best_id, g$expected$best_config_id)) stop("FAIL sg03_best_config_id") else cat("PASS sg03_best_config_id\n")
if (!identical(best_id, res$selected_config_id)) stop("FAIL sg03_loss_first_selection") else cat("PASS sg03_loss_first_selection\n")
assert_close("sg03_selected_inner_mase", res$diagnostics$selected_inner_mase, g$expected$selected_inner_mase)
assert_close("sg03_selected_to_best_ratio", res$diagnostics$selected_to_best_ratio, g$expected$selected_to_best_ratio)
assert_close("sg03_final_a", res$diagnostics$final_params$a, g$expected$final_params$a)
assert_close("sg03_final_b", res$diagnostics$final_params$b, g$expected$final_params$b)
assert_close("sg03_final_c", res$diagnostics$final_params$c, g$expected$final_params$c)
assert_close("sg03_final_d", res$diagnostics$final_params$d, g$expected$final_params$d)
assert_close("sg03_final_r", res$diagnostics$final_params$r, g$expected$final_params$r, tol = 0)
assert_close("sg03_fitted", res$fitted, g$expected$fitted)
assert_close("sg03_forecast", res$forecast, g$expected$forecast)

exp_scores <- g$expected$scores
if (length(res$inner_scores) != length(exp_scores)) stop("FAIL sg03_score_count") else cat("PASS sg03_score_count\n")
for (i in seq_along(res$inner_scores)) {
  got <- res$inner_scores[[i]]; exp <- exp_scores[[i]]
  if (!identical(got$config_id, exp$config_id)) stop(sprintf("FAIL score_id_%02d", i))
  assert_close(sprintf("score_r_%02d", i), got$r, exp$r, tol = 0)
  assert_close(sprintf("score_mean_%02d", i), got$mean_inner_mase, exp$mean_inner_mase)
  assert_close(sprintf("score_origins_%02d", i), got$origin_losses, exp$origin_losses)
}

# 5) Explicit failure semantics.
for (z in fx$failure_fixtures) {
  if (identical(z$kind, "direct")) {
    err <- tryCatch({ ag_fgm_fit_forecast(num(z$x), as.integer(z$h), as.numeric(z$r)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, z$expected_code)) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(z$kind, "group")) {
    rr <- ag_select_sg03(num(z$x), as.integer(z$h), NULL)
    if (isTRUE(rr$eligible) || !identical(rr$failure_code, z$expected_code)) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, rr$failure_code))
  } else stop(sprintf("FAIL unknown_failure_fixture_kind_%s", z$name))
}

# 6) Regression guards for already externally verified SG01 and SG02.
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

cat("\nSTEP7B3_SG03_PARITY: PASS\n")
