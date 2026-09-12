testthat::test_that("Step 7C1 feature engine preserves frozen schema", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  source(file.path(root, "R", "08_features.R"))
  fx <- jsonlite::fromJSON(file.path(root, "inst", "extdata", "feature_reference_fixture_step7c1.json"), simplifyVector = FALSE)
  testthat::expect_identical(AG_FEATURE_VERSION, "AG_FEAT_4E_1")
  testthat::expect_identical(AG_FEATURE_NAMES, as.character(unlist(fx$relationships$feature_names)))
  z <- fx$fixtures[[1L]]
  got <- ag_extract_features(as.numeric(unlist(z$D)), as.integer(z$h), NULL)
  testthat::expect_equal(got$values, as.numeric(unlist(z$values)), tolerance = 1e-8)
  testthat::expect_identical(got$valid_mask, as.logical(unlist(z$valid_mask)))
  testthat::expect_identical(got$reason_codes, as.character(unlist(z$reason_codes)))
  testthat::expect_identical(got$train_hash, z$train_hash)
})
