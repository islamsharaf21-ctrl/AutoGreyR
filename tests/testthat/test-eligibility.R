testthat::test_that("eligibility and refusal semantics match frozen fixture", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root,"R","01_utils.R")); source(file.path(root,"R","04_mase.R")); source(file.path(root,"R","05_grey_common.R")); source(file.path(root,"R","06_structural_groups.R")); source(file.path(root,"R","07_eligibility_collision.R"))
  fx <- jsonlite::fromJSON(file.path(root,"inst","extdata","eligibility_collision_reference_fixture_step7b11.json"), simplifyVector=FALSE)
  z <- fx$no_eligible_fixture
  p <- ag_run_structural_portfolio(as.numeric(unlist(z$D,use.names=FALSE)), as.integer(z$h), if(is.null(z$M)) NULL else as.integer(z$M))
  a <- ag_structural_actionability(p)
  testthat::expect_false(a$actionable)
  testthat::expect_identical(a$reason, "NO_ELIGIBLE_STRUCTURAL_GROUP")
})
