testthat::test_that("frozen bootstrap artifact and PCG64 contract are preserved", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  h <- digest::digest(file=file.path(root,"reference","frozen_step5f","AUTOGREY_REALBENCH2_BOOTSTRAP_STEP5F.csv"),algo="sha256",serialize=FALSE)
  testthat::expect_identical(h,"b78899ea38552ca546746a7f80ef7c5b9b28e9f8fc31ed45a9bde9faa11bb5fa")
  r <- jsonlite::fromJSON(file.path(root,"reference","frozen_step5f","AUTOGREY_REALBENCH2_RESULTS_STEP5F.json"),simplifyVector=FALSE)
  testthat::expect_identical(as.integer(r$bootstrap$seed),46073L)
  testthat::expect_identical(as.integer(r$bootstrap$replicates),4000L)
})
