#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else "scripts/verify_step7b2_sg02.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(root, "R", "01_utils.R"))
source(file.path(root, "R", "04_mase.R"))
source(file.path(root, "R", "05_grey_common.R"))
source(file.path(root, "R", "06_structural_groups.R"))

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite is required by the frozen Step 7A dependency contract.")
}
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("digest is required by the frozen Step 7A dependency contract.")
}

fx <- jsonlite::fromJSON(
  file.path(root, "inst", "extdata", "sg02_reference_fixture_step7b2.json"),
  simplifyVector = FALSE
)
TOL <- as.numeric(fx$tolerances$numeric_abs)

ref_py <- file.path(root, "reference", "python", "autogrey_engine_step4fb_r1.py")
got_hash <- digest::digest(ref_py, algo = "sha256", file = TRUE, serialize = FALSE)
if (!identical(got_hash, fx$canonical_python_engine_sha256)) {
  stop(sprintf("FAIL canonical_python_engine_sha256: got %s expected %s", got_hash, fx$canonical_python_engine_sha256))
}
cat(sprintf("PASS canonical_python_engine_sha256 %s\n", got_hash))

num <- function(x) as.numeric(unlist(x, use.names = FALSE))
int <- function(x) as.integer(unlist(x, use.names = FALSE))
chr <- function(x) as.character(unlist(x, use.names = FALSE))

assert_close <- function(name, got, exp, tol = TOL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) {
    stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  }
  d <- if (length(got)) max(abs(got - exp)) else 0
  if (d > tol) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g", name, d, tol))
  cat(sprintf("PASS %-42s max_abs=%.3e\n", name, d))
}

assert_identical_int <- function(name, got, exp) {
  got <- as.integer(got); exp <- int(exp)
  if (!identical(got, exp)) {
    stop(sprintf("FAIL %s: got [%s] expected [%s]", name,
                 paste(got, collapse = ","), paste(exp, collapse = ",")))
  }
  cat(sprintf("PASS %s\n", name))
}

# Fixture 1: Wei-Xie-Yang exact generating example.
s <- fx$wei_xie_yang_dgpm_source
out <- ag_dgpm_fit_forecast(num(s$x), as.integer(s$h), int(s$degrees))
assert_close("source_alpha", out$params$alpha, s$expected$alpha)
assert_close("source_beta0", out$params$beta0, s$expected$beta0)
assert_close("source_beta1", out$params$beta[["1"]], s$expected$beta[["1"]])
assert_close("source_beta2", out$params$beta[["2"]], s$expected$beta[["2"]])
assert_identical_int("source_degrees", out$params$degrees, s$expected$degrees)
assert_close("source_fitted", out$fitted, s$expected$fitted)
assert_close("source_forecast", out$forecast, s$expected$forecast,
             tol = as.numeric(fx$tolerances$source_forecast_abs))
assert_close("source_exact_k7", out$forecast, s$expected$exact_k7,
             tol = as.numeric(fx$tolerances$source_forecast_abs))
if (out$diagnostics$rank != as.integer(s$expected$rank)) stop("FAIL source_rank") else cat("PASS source_rank\n")
assert_close("source_condition", out$diagnostics$condition, s$expected$condition,
             tol = as.numeric(fx$tolerances$condition_abs))
if (out$diagnostics$rows != as.integer(s$expected$rows)) stop("FAIL source_rows") else cat("PASS source_rows\n")
if (out$diagnostics$params != as.integer(s$expected$params)) stop("FAIL source_params") else cat("PASS source_params\n")
if (out$diagnostics$resid_df != as.integer(s$expected$resid_df)) stop("FAIL source_resid_df") else cat("PASS source_resid_df\n")

# Degree normalization must reproduce Python tuple(sorted(set(int(d)...))).
nf <- fx$degree_normalization_fixture
norm_out <- ag_dgpm_fit_forecast(num(s$x), as.integer(s$h), int(nf$input_degrees))
assert_identical_int("degree_normalization", norm_out$params$degrees, nf$expected_degrees)
assert_close("degree_normalization_forecast", norm_out$forecast, nf$expected_forecast)

# Frozen config generation boundary: n=12,h=5 -> m_first=5 -> Nmax=1.
cb <- fx$config_generation_boundary
cfgs <- ag_sg02_configs(as.integer(cb$n), as.integer(cb$h), NULL)
got_ids <- vapply(cfgs, `[[`, character(1), "config_id")
exp_ids <- chr(cb$expected_config_ids)
if (!identical(got_ids, exp_ids)) {
  stop(sprintf("FAIL config_generation_ids: got [%s] expected [%s]",
               paste(got_ids, collapse = ";"), paste(exp_ids, collapse = ";")))
}
cat("PASS config_generation_ids\n")
if (length(cfgs) != length(cb$expected_degrees)) stop("FAIL config_generation_count")
for (i in seq_along(cfgs)) {
  assert_identical_int(sprintf("config_generation_degrees_%02d", i),
                       cfgs[[i]]$degrees, cb$expected_degrees[[i]])
}

# Fixture 2: full SG02 tuner. Best model is complex, frozen 5% simplicity selects empty set.
g <- fx$sg02_group_tuner
res <- ag_select_sg02(num(g$x), as.integer(g$h), NULL)
if (!isTRUE(res$eligible)) stop(sprintf("FAIL sg02_group_eligible: %s:%s", res$failure_code, res$failure_detail)) else cat("PASS sg02_group_eligible\n")
if (!identical(res$selected_config_id, g$expected$selected_config_id)) {
  stop(sprintf("FAIL sg02_selected_config_id: got %s expected %s", res$selected_config_id, g$expected$selected_config_id))
} else cat("PASS sg02_selected_config_id\n")
assert_identical_int("sg02_selected_degrees", res$selected_config$degrees, g$expected$selected_degrees)
assert_close("sg02_common_origins", res$diagnostics$common_origins, g$expected$common_origins, tol = 0)
if (res$diagnostics$config_count_registered != as.integer(g$expected$config_count_registered)) stop("FAIL sg02_config_count_registered") else cat("PASS sg02_config_count_registered\n")
if (res$diagnostics$config_count_valid != as.integer(g$expected$config_count_valid)) stop("FAIL sg02_config_count_valid") else cat("PASS sg02_config_count_valid\n")
assert_close("sg02_Lmin", res$diagnostics$Lmin, g$expected$Lmin)
if (res$diagnostics$band_size != as.integer(g$expected$band_size)) stop("FAIL sg02_band_size") else cat("PASS sg02_band_size\n")
assert_close("sg02_selected_inner_mase", res$diagnostics$selected_inner_mase, g$expected$selected_inner_mase)
assert_close("sg02_selected_to_best_ratio", res$diagnostics$selected_to_best_ratio, g$expected$selected_to_best_ratio)

means <- vapply(res$inner_scores, `[[`, numeric(1), "mean_inner_mase")
best_id <- res$inner_scores[[which.min(means)]]$config_id
if (!identical(best_id, g$expected$best_config_id)) stop("FAIL sg02_best_config_id") else cat("PASS sg02_best_config_id\n")
if (identical(best_id, res$selected_config_id)) stop("FAIL sg02_simplicity_override_not_exercised") else cat("PASS sg02_simplicity_override_exercised\n")

assert_close("sg02_final_alpha", res$diagnostics$final_params$alpha, g$expected$final_alpha)
assert_close("sg02_final_beta0", res$diagnostics$final_params$beta0, g$expected$final_beta0)
assert_identical_int("sg02_final_degrees", res$diagnostics$final_params$degrees, g$expected$final_degrees)
if (length(g$expected$final_beta) == 0L) {
  if (length(res$diagnostics$final_params$beta) != 0L) stop("FAIL sg02_final_beta_empty") else cat("PASS sg02_final_beta_empty\n")
}
assert_close("sg02_fitted", res$fitted, g$expected$fitted)
assert_close("sg02_forecast", res$forecast, g$expected$forecast)

# Every one of the 16 registered subset scores and all three origin losses must match.
exp_scores <- g$expected$scores
if (length(res$inner_scores) != length(exp_scores)) stop("FAIL sg02_score_count") else cat("PASS sg02_score_count\n")
for (i in seq_along(res$inner_scores)) {
  got <- res$inner_scores[[i]]
  exp <- exp_scores[[i]]
  if (!identical(got$config_id, exp$config_id)) stop(sprintf("FAIL score_id_%02d", i))
  assert_identical_int(sprintf("score_degrees_%02d", i), got$degrees, exp$degrees)
  assert_close(sprintf("score_mean_%02d", i), got$mean_inner_mase, exp$mean_inner_mase)
  assert_close(sprintf("score_origins_%02d", i), got$origin_losses, exp$origin_losses)
}

# Explicit failure semantics: direct model and group-level history gate.
for (z in fx$failure_fixtures) {
  if (identical(z$kind, "direct")) {
    err <- tryCatch({
      ag_dgpm_fit_forecast(num(z$x), as.integer(z$h), int(z$degrees)); NULL
    }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, z$expected_code)) {
      stop(sprintf("FAIL failure_fixture_%s", z$name))
    }
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(z$kind, "group")) {
    rr <- ag_select_sg02(num(z$x), as.integer(z$h), NULL)
    if (isTRUE(rr$eligible) || !identical(rr$failure_code, z$expected_code)) {
      stop(sprintf("FAIL failure_fixture_%s", z$name))
    }
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, rr$failure_code))
  } else stop(sprintf("FAIL unknown_failure_fixture_kind_%s", z$name))
}

# Regression guard: Step 7B1 SG01 verified forecast must remain unchanged.
fx1 <- jsonlite::fromJSON(
  file.path(root, "inst", "extdata", "sg01_reference_fixture_step7b1.json"),
  simplifyVector = TRUE
)
g1 <- fx1$sg01_group_tuner
r1 <- ag_select_sg01(g1$x, g1$h, g1$M)
if (!isTRUE(r1$eligible) || !identical(r1$selected_config_id, g1$expected$selected_config_id)) {
  stop("FAIL sg01_regression_guard_selection")
}
cat("PASS sg01_regression_guard_selection\n")
d1 <- max(abs(as.numeric(r1$forecast) - as.numeric(g1$expected$forecast)))
if (d1 > as.numeric(fx1$tolerances$numeric_abs)) stop("FAIL sg01_regression_guard_forecast")
cat(sprintf("PASS sg01_regression_guard_forecast       max_abs=%.3e\n", d1))

cat("\nSTEP7B2_SG02_PARITY: PASS\n")
