# Release-level SHA-256 helpers. Scientific model code is intentionally elsewhere.
ag_sha256_file <- function(path) {
  if (!file.exists(path)) stop(sprintf("Missing file: %s", path), call. = FALSE)
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

ag_expect_sha256 <- function(path, expected, label = path) {
  got <- ag_sha256_file(path)
  if (!identical(got, as.character(expected))) {
    stop(sprintf("SHA256 mismatch for %s: got=%s expected=%s", label, got, expected), call. = FALSE)
  }
  invisible(got)
}

ag_read_hash_manifest <- function(path = "inst/extdata/expected_hashes.json") {
  if (!file.exists(path)) stop(sprintf("Missing hash manifest: %s", path), call. = FALSE)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}
