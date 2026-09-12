testthat::test_that("release entry points exist", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  needed <- c("scripts/reproduce_train_r2.R","scripts/reproduce_realbench2_pretarget.R","scripts/reproduce_realbench2_final.R","scripts/reproduce_all.R","scripts/verify_step7g_release.R")
  testthat::expect_true(all(file.exists(file.path(root,needed))))
})
