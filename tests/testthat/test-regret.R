testthat::test_that("frozen regret is nonnegative selected loss minus eligible oracle", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  d <- utils::read.csv(file.path(root,"reference","frozen_step7f1","AUTOGREY_STEP7F1_DECISIONS_ORACLE.csv"), stringsAsFactors=FALSE, check.names=FALSE)
  testthat::expect_true(all(d$v1_regret >= -1e-14))
  testthat::expect_true(all(d$global_regret >= -1e-14))
  testthat::expect_equal(d$v1_regret, pmax(0,d$v1_loss_mase-d$eligible_oracle_mase), tolerance=5e-12)
  testthat::expect_equal(d$global_regret, pmax(0,d$global_loss_mase-d$eligible_oracle_mase), tolerance=5e-12)
})
