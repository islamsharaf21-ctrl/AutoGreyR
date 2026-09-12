#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else "scripts/verify_step7b9_sg09.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(root, "R", "01_utils.R"))
source(file.path(root, "R", "04_mase.R"))
source(file.path(root, "R", "05_grey_common.R"))
source(file.path(root, "R", "06_structural_groups.R"))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required by the frozen Step 7A dependency contract.")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required by the frozen Step 7A dependency contract.")

fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg09_reference_fixture_step7b9.json"), simplifyVector = FALSE)
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
  cat(sprintf("PASS %-60s max_abs=%.3e\n", name, d))
}
assert_close_scaled <- function(name, got, exp, atol = SCORE_ABS, rtol = SCORE_REL) {
  got <- as.numeric(got); exp <- num(exp)
  if (length(got) != length(exp) || any(!is.finite(got)) || any(!is.finite(exp))) stop(sprintf("FAIL %s: shape/nonfinite mismatch", name))
  d <- if (length(got)) max(abs(got - exp)) else 0
  scale <- if (length(exp)) max(1.0, max(abs(exp))) else 1.0
  lim <- atol + rtol * scale
  if (d > lim) stop(sprintf("FAIL %s: max_abs=%.17g > %.3g", name, d, lim))
  cat(sprintf("PASS %-60s max_abs=%.3e\n", name, d))
}
assert_int <- function(name, got, exp) {
  if (!identical(as.integer(got), as.integer(exp))) stop(sprintf("FAIL %s", name))
  cat(sprintf("PASS %s\n", name))
}
assert_chr <- function(name, got, exp) {
  if (!identical(as.character(got), as.character(exp))) stop(sprintf("FAIL %s", name))
  cat(sprintf("PASS %s\n", name))
}
assert_named_counts <- function(name, got, exp) {
  gn <- names(got); en <- names(exp)
  if (!identical(gn, en)) stop(sprintf("FAIL %s_names", name))
  gv <- as.integer(unlist(got, use.names = FALSE)); ev <- as.integer(unlist(exp, use.names = FALSE))
  if (!identical(gv, ev)) stop(sprintf("FAIL %s_values", name))
  cat(sprintf("PASS %s\n", name))
}

# 0) Canonical provenance and exact preservation of externally R-verified SG01-SG08 source.
engine_path <- file.path(root, "reference", "python", "autogrey_engine_step4fb_r1.py")
engine_sha <- digest::digest(file = engine_path, algo = "sha256", serialize = FALSE)
if (!identical(engine_sha, as.character(fx$canonical_python_engine_sha256))) stop("FAIL canonical_python_engine_sha256")
cat(sprintf("PASS canonical_python_engine_sha256 %s\n", engine_sha))

parent_path <- file.path(root, "reference", "r", "06_structural_groups_step7b8_verified.R")
current_path <- file.path(root, "R", "06_structural_groups.R")
read_raw <- function(p) { con <- file(p, "rb"); on.exit(close(con)); readBin(con, "raw", n = file.info(p)$size) }
parent_raw <- read_raw(parent_path); current_raw <- read_raw(current_path)
if (length(current_raw) < length(parent_raw) || !identical(current_raw[seq_along(parent_raw)], parent_raw)) stop("FAIL sg01_sg08_source_prefix_preservation")
cat("PASS sg01_sg08_source_prefix_preservation\n")

# 1) Direct SG09 model: residual partition, right-boundary ownership, transition matrix, and lag-2 tie resolution.
d <- fx$direct_tie_resolution_fixture
x <- num(d$x); h <- as.integer(d$h); S <- as.integer(d$S); boundary <- as.character(d$boundary)
gm <- ag_gm_fit_forecast(x, h, 0.5)
resid <- x - gm$fitted
edges <- ag_markov_state_edges(resid, S, boundary)
states <- ag_markov_assign_states(resid, edges)
mids <- 0.5 * (edges[-length(edges)] + edges[-1L])
t1 <- ag_markov_transition_matrix(states, S, 1L)

assert_close("base_gm_forecast", gm$forecast, d$base_gm$forecast)
assert_close("base_gm_fitted", gm$fitted, d$base_gm$fitted)
assert_close("base_gm_a", gm$params$a, d$base_gm$params$a)
assert_close("base_gm_b", gm$params$b, d$base_gm$params$b)
assert_close("base_gm_alpha_bg", gm$params$alpha_bg, d$base_gm$params$alpha_bg, tol = 0)
assert_close("base_gm_condition", gm$diagnostics$condition, d$base_gm$diagnostics$condition, tol = COND_TOL)
assert_int("base_gm_rank", gm$diagnostics$rank, d$base_gm$diagnostics$rank)
assert_close("residuals", resid, d$residuals)
assert_close("eqw_edges", edges, d$expected_edges)
if (!identical(states, ints(d$expected_states))) stop("FAIL assigned_states") else cat("PASS assigned_states\n")
assert_close("state_midpoints", mids, d$expected_midpoints)
expP <- matrix(num(d$expected_transition_matrix_lag1), nrow = S, byrow = TRUE)
assert_close("transition_matrix_lag1", as.numeric(t(t1$P)), as.numeric(t(expP)))
if (!identical(t1$origins, ints(d$expected_outgoing_counts_lag1))) stop("FAIL outgoing_counts_lag1") else cat("PASS outgoing_counts_lag1\n")

eqt_edges <- ag_markov_state_edges(resid, S, "EQT")
assert_close("eqt_edges_same_residuals", eqt_edges, d$eqt_edges_same_residuals)
probe_states <- ag_markov_assign_states(num(d$boundary_ownership_probe$values), edges)
if (!identical(probe_states, ints(d$boundary_ownership_probe$expected_states))) stop("FAIL internal_boundary_right_ownership") else cat("PASS internal_boundary_right_ownership\n")

out <- ag_greymarkov_fit_forecast(x, h, S, boundary)
assert_close("direct_forecast", out$forecast, d$expected$forecast)
assert_close("direct_fitted", out$fitted, d$expected$fitted)
assert_int("direct_param_S", out$params$S, d$expected$params$S)
assert_chr("direct_param_boundary", out$params$boundary, d$expected$params$boundary)
assert_close("direct_param_edges", out$params$edges, d$expected$params$edges)
assert_close("direct_base_gm_a", out$diagnostics$base_gm_params$a, d$expected$diagnostics$base_gm_params$a)
assert_close("direct_base_gm_b", out$diagnostics$base_gm_params$b, d$expected$diagnostics$base_gm_params$b)
assert_close("direct_base_gm_alpha", out$diagnostics$base_gm_params$alpha_bg, d$expected$diagnostics$base_gm_params$alpha_bg, tol = 0)
assert_named_counts("direct_state_counts", out$diagnostics$state_counts, d$expected$diagnostics$state_counts)
assert_named_counts("direct_outgoing_counts", out$diagnostics$outgoing_counts, d$expected$diagnostics$outgoing_counts)
if (!identical(out$diagnostics$tie_resolution_lags, ints(d$expected$diagnostics$tie_resolution_lags))) stop("FAIL direct_tie_resolution_lags") else cat("PASS direct_tie_resolution_lags\n")
if (!identical(out$diagnostics$states, ints(d$expected$diagnostics$states))) stop("FAIL direct_states") else cat("PASS direct_states\n")

current <- tail(states, 1L)
recon <- numeric(h)
for (i in seq_along(d$prediction_chain)) {
  z <- d$prediction_chain[[i]]
  assert_int(sprintf("chain_current_state_%02d", i), current, z$current_state)
  rr <- ag_markov_resolve_next_state(states, S, current)
  assert_int(sprintf("chain_next_state_%02d", i), rr$next_state, z$next_state)
  assert_int(sprintf("chain_used_lag_%02d", i), rr$used_lag, z$used_lag)
  assert_close(sprintf("chain_base_forecast_%02d", i), gm$forecast[i], z$base_gm_forecast)
  assert_close(sprintf("chain_midpoint_%02d", i), mids[rr$next_state + 1L], z$midpoint_correction)
  recon[i] <- gm$forecast[i] + mids[rr$next_state + 1L]
  assert_close(sprintf("chain_corrected_%02d", i), recon[i], z$corrected_forecast)
  current <- rr$next_state
}
assert_close("prediction_chain_reconstructs_forecast", recon, d$expected$forecast)
if (!all(out$diagnostics$tie_resolution_lags == 2L)) stop("FAIL lag2_tie_resolution_exercised") else cat("PASS lag2_tie_resolution_exercised\n")

# 2) Exact frozen SG09 registry: S=2..4 crossed with EQW/EQT.
cg <- fx$config_generation
cfgs <- ag_sg09_configs(as.integer(cg$n), as.integer(cg$h), NULL)
got_ids <- vapply(cfgs, `[[`, character(1), "config_id")
if (!identical(got_ids, chr(cg$expected_config_ids))) stop("FAIL config_generation_ids") else cat("PASS config_generation_ids\n")
if (length(cfgs) != length(cg$expected_configs)) stop("FAIL config_generation_count") else cat("PASS config_generation_count\n")
for (i in seq_along(cfgs)) {
  assert_int(sprintf("config_S_%02d", i), cfgs[[i]]$S, cg$expected_configs[[i]]$S)
  assert_chr(sprintf("config_boundary_%02d", i), cfgs[[i]]$boundary, cg$expected_configs[[i]]$boundary)
}

# 3) Full SG09 group selection over three common origins.
g <- fx$sg09_group_tuner
res <- ag_select_sg09(num(g$x), as.integer(g$h), NULL)
if (!isTRUE(res$eligible)) stop(sprintf("FAIL sg09_group_eligible: %s:%s", res$failure_code, res$failure_detail)) else cat("PASS sg09_group_eligible\n")
assert_chr("sg09_selected_config_id", res$selected_config_id, g$expected$selected_config_id)
assert_int("sg09_selected_S", res$selected_config$S, g$expected$selected_config$S)
assert_chr("sg09_selected_boundary", res$selected_config$boundary, g$expected$selected_config$boundary)
if (!identical(res$diagnostics$common_origins, ints(g$expected$common_origins))) stop("FAIL sg09_common_origins") else cat("PASS sg09_common_origins\n")
assert_int("sg09_config_count_registered", res$diagnostics$config_count_registered, g$expected$config_count_registered)
assert_int("sg09_config_count_valid", res$diagnostics$config_count_valid, g$expected$config_count_valid)
assert_close_scaled("sg09_Lmin", res$diagnostics$Lmin, g$expected$Lmin)
assert_int("sg09_band_size", res$diagnostics$band_size, g$expected$band_size)
means <- vapply(res$inner_scores, `[[`, numeric(1), "mean_inner_mase")
band_ids <- vapply(res$inner_scores[means <= 1.05 * res$diagnostics$Lmin + 1e-15], `[[`, character(1), "config_id")
if (!identical(band_ids, chr(g$expected$band_config_ids))) stop("FAIL sg09_band_config_ids") else cat("PASS sg09_band_config_ids\n")
best_id <- res$inner_scores[[which.min(means)]]$config_id
assert_chr("sg09_best_config_id", best_id, g$expected$best_config_id)
if (!identical(best_id, "S=2_EQT") || !identical(res$selected_config_id, "S=2_EQW")) stop("FAIL sg09_eqw_simplicity_override") else cat("PASS sg09_eqw_simplicity_override\n")
assert_close_scaled("sg09_selected_inner_mase", res$diagnostics$selected_inner_mase, g$expected$selected_inner_mase)
assert_close_scaled("sg09_selected_to_best_ratio", res$diagnostics$selected_to_best_ratio, g$expected$selected_to_best_ratio)
assert_int("sg09_final_S", res$diagnostics$final_params$S, g$expected$final_params$S)
assert_chr("sg09_final_boundary", res$diagnostics$final_params$boundary, g$expected$final_params$boundary)
assert_close("sg09_final_edges", res$diagnostics$final_params$edges, g$expected$final_params$edges)
assert_named_counts("sg09_final_state_counts", res$diagnostics$final_model_diagnostics$state_counts, g$expected$final_model_diagnostics$state_counts)
assert_named_counts("sg09_final_outgoing_counts", res$diagnostics$final_model_diagnostics$outgoing_counts, g$expected$final_model_diagnostics$outgoing_counts)
if (!identical(res$diagnostics$final_model_diagnostics$tie_resolution_lags, ints(g$expected$final_model_diagnostics$tie_resolution_lags))) stop("FAIL sg09_final_tie_lags") else cat("PASS sg09_final_tie_lags\n")
if (!identical(res$diagnostics$final_model_diagnostics$states, ints(g$expected$final_model_diagnostics$states))) stop("FAIL sg09_final_states") else cat("PASS sg09_final_states\n")
assert_close("sg09_fitted", res$fitted, g$expected$fitted)
assert_close("sg09_forecast", res$forecast, g$expected$forecast)

exp_scores <- g$expected$scores
if (length(res$inner_scores) != length(exp_scores)) stop("FAIL sg09_score_count") else cat("PASS sg09_score_count\n")
for (i in seq_along(res$inner_scores)) {
  got <- res$inner_scores[[i]]; exp <- exp_scores[[i]]
  assert_chr(sprintf("score_id_%02d", i), got$config_id, exp$config_id)
  assert_int(sprintf("score_S_%02d", i), got$config$S, exp$config$S)
  assert_chr(sprintf("score_boundary_%02d", i), got$config$boundary, exp$config$boundary)
  assert_close_scaled(sprintf("score_mean_%02d", i), got$mean_inner_mase, exp$mean_inner_mase)
  assert_close_scaled(sprintf("score_origins_%02d", i), got$origin_losses, exp$origin_losses)
  if (length(got$diagnostics$origin_diagnostics) != 3L) stop(sprintf("FAIL score_origin_diag_count_%02d", i))
  for (j in seq_len(3L)) {
    gd <- got$diagnostics$origin_diagnostics[[j]]; ed <- exp$origin_diagnostics[[j]]
    if (!identical(gd$states, ints(ed$states))) stop(sprintf("FAIL score_states_%02d_%02d", i, j))
    if (!identical(gd$tie_resolution_lags, ints(ed$tie_resolution_lags))) stop(sprintf("FAIL score_tie_lags_%02d_%02d", i, j))
    assert_named_counts(sprintf("score_state_counts_%02d_%02d", i, j), gd$state_counts, ed$state_counts)
    assert_named_counts(sprintf("score_outgoing_counts_%02d_%02d", i, j), gd$outgoing_counts, ed$outgoing_counts)
  }
  cat(sprintf("PASS score_origin_diagnostics_%02d\n", i))
}

# 4) Explicit SG09 failure semantics, including precheck ordering.
for (z in fx$failure_fixtures) {
  kind <- as.character(z$kind)
  if (identical(kind, "model")) {
    err <- tryCatch({ ag_greymarkov_fit_forecast(num(z$x), as.integer(z$h), as.integer(z$S), as.character(z$boundary)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "resolver")) {
    err <- tryCatch({ ag_markov_resolve_next_state(ints(z$states), as.integer(z$S), as.integer(z$current)); NULL }, autogrey_engine_failure = identity)
    if (is.null(err) || !identical(err$code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, err$code))
  } else if (identical(kind, "group")) {
    rr <- ag_select_sg09(num(z$x), as.integer(z$h), NULL)
    if (isTRUE(rr$eligible) || !identical(rr$failure_code, as.character(z$expected_code))) stop(sprintf("FAIL failure_fixture_%s", z$name))
    cat(sprintf("PASS failure_fixture_%s code=%s\n", z$name, rr$failure_code))
  } else stop(sprintf("FAIL unknown_failure_fixture_kind_%s", z$name))
}

# 5) Regression guards for SG01-SG08 — all eight prior checkpoints were externally R-verified.
fx1 <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg01_reference_fixture_step7b1.json"), simplifyVector = TRUE)
g1 <- fx1$sg01_group_tuner; r1 <- ag_select_sg01(g1$x, g1$h, g1$M)
if (!isTRUE(r1$eligible) || !identical(r1$selected_config_id, g1$expected$selected_config_id)) stop("FAIL sg01_regression_guard_selection")
cat("PASS sg01_regression_guard_selection\n")
d1 <- max(abs(as.numeric(r1$forecast) - as.numeric(g1$expected$forecast)))
if (d1 > as.numeric(fx1$tolerances$numeric_abs)) stop("FAIL sg01_regression_guard_forecast")
cat(sprintf("PASS sg01_regression_guard_forecast         max_abs=%.3e\n", d1))

for (k in 2:8) {
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

cat("\nSTEP7B9_SG09_PARITY: PASS\n")
