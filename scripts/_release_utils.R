ag_release_root <- function() {
  wd <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  if (!file.exists(file.path(wd, "DESCRIPTION")) || !dir.exists(file.path(wd, "R"))) {
    stop("Run Step7G scripts from the AutoGreyR project root.", call. = FALSE)
  }
  wd
}

ag_rscript_path <- function() {
  exe <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  if (!file.exists(exe)) stop(sprintf("Rscript not found at %s", exe), call. = FALSE)
  exe
}

ag_run_release_stage <- function(script, marker, log_name) {
  root <- ag_release_root()
  if (!file.exists(script)) stop(sprintf("Missing stage script: %s", script), call. = FALSE)
  dir.create(file.path(root, "outputs", "logs"), recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n===== RUN %s =====\n", script))
  out <- system2(
    ag_rscript_path(),
    c("--no-site-file", "--no-restore", script),
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  log_path <- file.path(root, "outputs", "logs", log_name)
  writeLines(out, log_path, useBytes = TRUE)
  if (length(out)) cat(paste0(out, collapse = "\n"), "\n")
  if (status != 0L) stop(sprintf("Stage failed with status %d: %s. See %s", status, script, log_path), call. = FALSE)
  if (!any(grepl(marker, out, fixed = TRUE))) stop(sprintf("Stage completed without required marker '%s': %s", marker, script), call. = FALSE)
  cat(sprintf("PASS stage marker: %s\n", marker))
  invisible(log_path)
}
