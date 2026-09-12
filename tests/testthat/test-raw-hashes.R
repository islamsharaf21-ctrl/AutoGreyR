testthat::test_that("REALBENCH2 raw reservation bundle is the frozen object", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  h <- digest::digest(file=file.path(root,"reference","raw","AUTOGREY_REALBENCH2_RAW_RESERVATION_BUNDLE_STEP5B.zip"),algo="sha256",serialize=FALSE)
  testthat::expect_identical(h,"85aac5e92b5d6b0db2299d319d096a5a4b274369cbfeabf7c79e2dc706b0f4f9")
})
