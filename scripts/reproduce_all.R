options(warn = 1)
source("scripts/_release_utils.R", local = .GlobalEnv)

cat("=== AutoGreyR 1.0.0 public reproduction ===\n")
cat("Scientific design is frozen. This workflow restores/verifies the committed renv.lock and writes reproduction outputs only.\n")

ag_prepare_release_python <- function() {
  explicit <- Sys.getenv("AUTOGREY_PYTHON", unset = "")
  if (nzchar(explicit)) {
    if (!file.exists(explicit)) {
      stop("AUTOGREY_PYTHON does not point to an existing executable", call. = FALSE)
    }
    cat("INFO Python launcher: using existing AUTOGREY_PYTHON\n")
    return(invisible(explicit))
  }

  if (identical(.Platform$OS.type, "windows")) {
    py <- Sys.which("py")
    if (nzchar(py)) {
      z <- system2(
        unname(py),
        args = c("-3.13", "-c", shQuote("import sys; print(sys.executable)")),
        stdout = TRUE,
        stderr = TRUE
      )
      status <- attr(z, "status")
      if (is.null(status)) status <- 0L

      if (identical(as.integer(status), 0L)) {
        lines <- trimws(as.character(z))
        lines <- lines[nzchar(lines)]
        if (length(lines)) {
          candidate <- lines[[length(lines)]]
          if (file.exists(candidate)) {
            candidate <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
            Sys.setenv(AUTOGREY_PYTHON = candidate)
            cat("INFO Python launcher: resolved AUTOGREY_PYTHON via py -3.13\n")
            return(invisible(candidate))
          }
        }
      }
    }
  }

  cat("INFO Python launcher: no release override set; frozen bridge discovery will be used\n")
  invisible("")
}

ag_prepare_release_python()

ag_run_release_stage("scripts/initialize_renv.R", "AUTOGREY_RENV_LOCK: PASS", "initialize_renv.log")
ag_run_release_stage("scripts/check_release_environment.R", "AUTOGREY_RELEASE_ENVIRONMENT: PASS", "release_environment.log")
ag_run_release_stage("scripts/run_unit_tests.R", "AUTOGREY_UNIT_TESTS: PASS", "unit_tests.log")
ag_run_release_stage("scripts/reproduce_train_r2.R", "AUTOGREY_REPRODUCE_TRAIN_R2: PASS", "reproduce_train_r2.log")
ag_run_release_stage("scripts/reproduce_realbench2_pretarget.R", "AUTOGREY_REPRODUCE_REALBENCH2_PRETARGET: PASS", "reproduce_realbench2_pretarget.log")
ag_run_release_stage("scripts/reproduce_realbench2_final.R", "AUTOGREY_REPRODUCE_REALBENCH2_FINAL: PASS", "reproduce_realbench2_final.log")
ag_run_release_stage("scripts/verify_step7g_release.R", "AUTOGREY_PUBLIC_RELEASE_AUDIT: PASS", "public_release_audit.log")

cat("\nAUTOGREY_STEP7G_REPRODUCE_ALL: PASS\n")
