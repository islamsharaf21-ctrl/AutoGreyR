testthat::test_that("Step7E2 cross-platform contract is frozen", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  h <- digest::digest(file=file.path(root,"AUTOGREY_STEP7E2_PLATFORM_CONTRACT_R8.json"),algo="sha256",serialize=FALSE)
  testthat::expect_identical(h,"61173edb5f6fe0779e3eaa4da51cc40a6a488a82df37e8b918b333c630cfe617")
})
