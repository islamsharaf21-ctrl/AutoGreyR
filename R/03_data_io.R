# Minimal deterministic I/O helpers used by release scripts.
ag_read_csv_char <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                  colClasses = "character", na.strings = character(0))
}

ag_write_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(x, path, pretty = TRUE, auto_unbox = TRUE, digits = 17)
  invisible(path)
}

ag_require_packages <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop(sprintf("Missing R package(s): %s", paste(missing, collapse = ", ")), call. = FALSE)
  invisible(TRUE)
}
