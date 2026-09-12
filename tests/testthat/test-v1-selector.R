testthat::test_that("Step7D2 full V1 verifier exists", {
  testthat::expect_true(file.exists("scripts/verify_step7d2_full_v1_train.R") || file.exists(file.path("..","..","scripts","verify_step7d2_full_v1_train.R")))
})
