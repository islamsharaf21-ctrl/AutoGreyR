testthat::test_that("Step7 verified SG05/SG07/SG10 tuners retain frozen choices", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root,"R","01_utils.R"))
  source(file.path(root,"R","04_mase.R"))
  source(file.path(root,"R","05_grey_common.R"))
  source(file.path(root,"R","06_structural_groups.R"))
  cases <- list(
    list(file="sg05_reference_fixture_step7b5.json", key="sg05_group_tuner", fun=ag_select_sg05),
    list(file="sg07_reference_fixture_step7b7.json", key="sg07_group_tuner", fun=ag_select_sg07),
    list(file="sg10_reference_fixture_step7b10.json", key="sg10_group_tuner", fun=ag_select_sg10)
  )
  for (z in cases) {
    fx <- jsonlite::fromJSON(file.path(root,"inst","extdata",z$file), simplifyVector=FALSE)
    g <- fx[[z$key]]
    D <- as.numeric(unlist(g$x, use.names=FALSE)); h <- as.integer(g$h)
    M <- if (is.null(g$M)) NULL else as.integer(g$M)
    got <- z$fun(D,h,M)
    testthat::expect_true(got$eligible)
    testthat::expect_identical(as.character(got$selected_config_id), as.character(g$expected$selected_config_id))
    testthat::expect_equal(as.numeric(got$forecast), as.numeric(unlist(g$expected$forecast,use.names=FALSE)), tolerance=1e-7)
  }
})
