testthat::test_that("frozen Step5F confirmatory result remains bound", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  r <- jsonlite::fromJSON(file.path(root,"reference","frozen_step5f","AUTOGREY_REALBENCH2_RESULTS_STEP5F.json"),simplifyVector=FALSE)
  testthat::expect_true(isTRUE(r$final_gate$overall_robust_superiority))
  testthat::expect_equal(as.numeric(r$primary_metrics$mean_regret),1.317290834344165,tolerance=1e-15)
  testthat::expect_equal(as.numeric(r$global_rank_v2_metrics$mean_regret),1.9289794121083974,tolerance=1e-15)
  testthat::expect_equal(as.numeric(unlist(r$bootstrap$mean_delta_ci95,use.names=FALSE)),c(-0.7414871255255626,-0.49395892999206054),tolerance=1e-15)
})
