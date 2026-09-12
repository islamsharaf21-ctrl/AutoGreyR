testthat::test_that("collision first-owner dedup matches frozen distinct group set", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root,"R","01_utils.R")); source(file.path(root,"R","04_mase.R")); source(file.path(root,"R","05_grey_common.R")); source(file.path(root,"R","06_structural_groups.R")); source(file.path(root,"R","07_eligibility_collision.R"))
  fx <- jsonlite::fromJSON(file.path(root,"inst","extdata","eligibility_collision_reference_fixture_step7b11.json"), simplifyVector=FALSE)
  z <- fx$collision_portfolio_fixture
  p <- ag_run_structural_portfolio(as.numeric(unlist(z$D,use.names=FALSE)), as.integer(z$h), NULL)
  testthat::expect_identical(as.character(p$distinct_groups), as.character(unlist(z$expected$distinct_groups,use.names=FALSE)))
  testthat::expect_equal(length(p$collisions), length(z$expected$collisions))
})
