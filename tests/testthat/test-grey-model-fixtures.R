testthat::test_that("Step 7B1 SG01 matches frozen Python oracle", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root, "R", "01_utils.R"))
  source(file.path(root, "R", "04_mase.R"))
  source(file.path(root, "R", "05_grey_common.R"))
  source(file.path(root, "R", "06_structural_groups.R"))
  fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg01_reference_fixture_step7b1.json"), simplifyVector = TRUE)
  tol <- fx$tolerances$numeric_abs

  w <- fx$wu2013_table2_sg01
  out <- ag_gm_fit_forecast(w$x, w$h, w$alpha)
  testthat::expect_equal(out$params$a, w$expected$a, tolerance = tol)
  testthat::expect_equal(out$params$b, w$expected$b, tolerance = tol)
  testthat::expect_equal(out$fitted, w$expected$fitted, tolerance = tol)
  testthat::expect_equal(out$forecast, w$expected$forecast, tolerance = tol)

  g <- fx$sg01_group_tuner
  res <- ag_select_sg01(g$x, g$h, g$M)
  testthat::expect_true(res$eligible)
  testthat::expect_identical(res$selected_config_id, g$expected$selected_config_id)
  testthat::expect_equal(res$diagnostics$Lmin, g$expected$Lmin, tolerance = tol)
  testthat::expect_equal(res$forecast, g$expected$forecast, tolerance = tol)
  testthat::expect_equal(res$fitted, g$expected$fitted, tolerance = tol)
})

testthat::test_that("Step 7B2 SG02 matches frozen Python oracle", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root, "R", "01_utils.R"))
  source(file.path(root, "R", "04_mase.R"))
  source(file.path(root, "R", "05_grey_common.R"))
  source(file.path(root, "R", "06_structural_groups.R"))
  fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg02_reference_fixture_step7b2.json"), simplifyVector = FALSE)
  tol <- as.numeric(fx$tolerances$numeric_abs)

  s <- fx$wei_xie_yang_dgpm_source
  out <- ag_dgpm_fit_forecast(as.numeric(unlist(s$x)), as.integer(s$h), as.integer(unlist(s$degrees)))
  testthat::expect_equal(out$params$alpha, as.numeric(s$expected$alpha), tolerance = tol)
  testthat::expect_equal(out$params$beta0, as.numeric(s$expected$beta0), tolerance = tol)
  testthat::expect_equal(out$forecast, as.numeric(unlist(s$expected$forecast)), tolerance = tol)

  g <- fx$sg02_group_tuner
  res <- ag_select_sg02(as.numeric(unlist(g$x)), as.integer(g$h), NULL)
  testthat::expect_true(res$eligible)
  testthat::expect_identical(res$selected_config_id, g$expected$selected_config_id)
  testthat::expect_identical(res$selected_config$degrees, as.integer(unlist(g$expected$selected_degrees)))
  testthat::expect_equal(res$diagnostics$Lmin, as.numeric(g$expected$Lmin), tolerance = tol)
  testthat::expect_equal(res$forecast, as.numeric(unlist(g$expected$forecast)), tolerance = tol)
})

testthat::test_that("Step 7B3 SG03 matches frozen Python oracle", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root, "R", "01_utils.R"))
  source(file.path(root, "R", "04_mase.R"))
  source(file.path(root, "R", "05_grey_common.R"))
  source(file.path(root, "R", "06_structural_groups.R"))
  fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg03_reference_fixture_step7b3.json"), simplifyVector = FALSE)
  tol <- as.numeric(fx$tolerances$numeric_abs)

  w <- fx$wu2013_table2_r03
  out <- ag_fgm_fit_forecast(as.numeric(unlist(w$x)), as.integer(w$h), as.numeric(w$r))
  testthat::expect_equal(out$params$a, as.numeric(w$expected$params$a), tolerance = tol)
  testthat::expect_equal(out$params$b, as.numeric(w$expected$params$b), tolerance = tol)
  testthat::expect_equal(out$params$c, as.numeric(w$expected$params$c), tolerance = tol)
  testthat::expect_equal(out$params$d, as.numeric(w$expected$params$d), tolerance = tol)
  testthat::expect_equal(out$forecast, as.numeric(unlist(w$expected$forecast)), tolerance = tol)

  g <- fx$sg03_group_tuner
  res <- ag_select_sg03(as.numeric(unlist(g$x)), as.integer(g$h), NULL)
  testthat::expect_true(res$eligible)
  testthat::expect_identical(res$selected_config_id, g$expected$selected_config_id)
  testthat::expect_equal(res$selected_config$r, as.numeric(g$expected$selected_r), tolerance = 0)
  testthat::expect_equal(res$diagnostics$Lmin, as.numeric(g$expected$Lmin), tolerance = tol)
  testthat::expect_equal(res$forecast, as.numeric(unlist(g$expected$forecast)), tolerance = tol)
})

testthat::test_that("Step 7B4 SG04 matches frozen Python oracle", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root, "R", "01_utils.R"))
  source(file.path(root, "R", "04_mase.R"))
  source(file.path(root, "R", "05_grey_common.R"))
  source(file.path(root, "R", "06_structural_groups.R"))
  fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg04_reference_fixture_step7b4.json"), simplifyVector = FALSE)
  tol <- as.numeric(fx$tolerances$numeric_abs)
  num <- function(x) as.numeric(unlist(x, use.names = FALSE))

  r <- fx$reduction_fixture
  ng0 <- ag_ngbm_fit_forecast(num(r$x), as.integer(r$h), 0.0)
  ng2 <- ag_ngbm_fit_forecast(num(r$x), as.integer(r$h), 2.0)
  testthat::expect_equal(ng0$forecast, num(r$expected$gamma0_forecast), tolerance = tol)
  testthat::expect_equal(ng2$forecast, num(r$expected$gamma2_forecast), tolerance = tol)

  g <- fx$sg04_group_tuner
  res <- ag_select_sg04(num(g$x), as.integer(g$h), NULL)
  testthat::expect_true(res$eligible)
  testthat::expect_identical(res$selected_config_id, g$expected$selected_config_id)
  testthat::expect_equal(res$selected_config$gamma, as.numeric(g$expected$selected_gamma), tolerance = 0)
  testthat::expect_equal(res$diagnostics$Lmin, as.numeric(g$expected$Lmin), tolerance = tol)
  testthat::expect_equal(res$forecast, num(g$expected$forecast), tolerance = tol)
})

testthat::test_that("Step 7B6 SG06 matches frozen Python oracle", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root, "R", "01_utils.R"))
  source(file.path(root, "R", "04_mase.R"))
  source(file.path(root, "R", "05_grey_common.R"))
  source(file.path(root, "R", "06_structural_groups.R"))
  fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg06_reference_fixture_step7b6.json"), simplifyVector = FALSE)
  tol <- as.numeric(fx$tolerances$numeric_abs)
  num <- function(x) as.numeric(unlist(x, use.names = FALSE))

  s <- fx$source_cfgm_alpha_059
  out <- ag_cfgm_fit_forecast(num(s$x), as.integer(s$h), as.numeric(s$alpha))
  testthat::expect_equal(out$params$a, as.numeric(s$expected$params$a), tolerance = tol)
  testthat::expect_equal(out$params$b, as.numeric(s$expected$params$b), tolerance = tol)
  testthat::expect_equal(out$forecast, num(s$expected$forecast), tolerance = tol)

  g <- fx$sg06_group_tuner
  res <- ag_select_sg06(num(g$x), as.integer(g$h), NULL)
  testthat::expect_true(res$eligible)
  testthat::expect_identical(res$selected_config_id, as.character(g$expected$selected_config_id))
  testthat::expect_equal(res$selected_config$alpha, as.numeric(g$expected$selected_alpha), tolerance = 0)
  testthat::expect_equal(res$diagnostics$Lmin, as.numeric(g$expected$Lmin), tolerance = tol)
  testthat::expect_equal(res$forecast, num(g$expected$forecast), tolerance = tol)
})

testthat::test_that("Step 7B8 SG08 matches frozen Python oracle", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root, "R", "01_utils.R"))
  source(file.path(root, "R", "04_mase.R"))
  source(file.path(root, "R", "05_grey_common.R"))
  source(file.path(root, "R", "06_structural_groups.R"))
  fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg08_reference_fixture_step7b8.json"), simplifyVector = FALSE)
  tol <- as.numeric(fx$tolerances$numeric_abs)
  num <- function(x) as.numeric(unlist(x, use.names = FALSE))

  d <- fx$direct_recursive_fixture
  out <- ag_wbo_gm_forecast(num(d$x), as.integer(d$h))
  testthat::expect_equal(out$forecast, num(d$expected$forecast), tolerance = tol)
  testthat::expect_equal(out$fitted, num(d$expected$fitted), tolerance = 0)

  g <- fx$sg08_group_tuner
  res <- ag_select_sg08(num(g$x), as.integer(g$h), NULL)
  testthat::expect_true(res$eligible)
  testthat::expect_identical(res$selected_config_id, as.character(g$expected$selected_config_id))
  testthat::expect_equal(res$diagnostics$Lmin, as.numeric(g$expected$Lmin), tolerance = tol)
  testthat::expect_equal(res$forecast, num(g$expected$forecast), tolerance = tol)
})

testthat::test_that("Step 7B9 SG09 matches frozen Python oracle", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root, "R", "01_utils.R"))
  source(file.path(root, "R", "04_mase.R"))
  source(file.path(root, "R", "05_grey_common.R"))
  source(file.path(root, "R", "06_structural_groups.R"))
  fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "sg09_reference_fixture_step7b9.json"), simplifyVector = FALSE)
  tol <- as.numeric(fx$tolerances$numeric_abs)
  num <- function(x) as.numeric(unlist(x, use.names = FALSE))

  d <- fx$direct_tie_resolution_fixture
  out <- ag_greymarkov_fit_forecast(num(d$x), as.integer(d$h), as.integer(d$S), as.character(d$boundary))
  testthat::expect_equal(out$forecast, num(d$expected$forecast), tolerance = tol)
  testthat::expect_equal(out$diagnostics$tie_resolution_lags, as.integer(unlist(d$expected$diagnostics$tie_resolution_lags)), tolerance = 0)

  g <- fx$sg09_group_tuner
  res <- ag_select_sg09(num(g$x), as.integer(g$h), NULL)
  testthat::expect_true(res$eligible)
  testthat::expect_identical(res$selected_config_id, as.character(g$expected$selected_config_id))
  testthat::expect_equal(res$diagnostics$Lmin, as.numeric(g$expected$Lmin), tolerance = tol)
  testthat::expect_equal(res$forecast, num(g$expected$forecast), tolerance = tol)
})
