options(warn = 1)
if (!requireNamespace("jsonlite", quietly=TRUE) || !requireNamespace("digest", quietly=TRUE)) stop("jsonlite and digest are required", call.=FALSE)
source("R/10_v1_rf_bridge.R", local=.GlobalEnv)
required_r <- "4.6.1"
if (!identical(as.character(getRversion()), required_r)) stop(sprintf("R version mismatch: %s", getRversion()), call.=FALSE)
required_pkgs <- c(jsonlite="2.0.0", digest="0.6.39", testthat="3.3.2", renv="1.2.3")
for (pkg in names(required_pkgs)) {
  if (!requireNamespace(pkg, quietly=TRUE)) stop(sprintf("Missing %s", pkg), call.=FALSE)
  got <- as.character(utils::packageVersion(pkg))
  if (!identical(got, unname(required_pkgs[[pkg]]))) stop(sprintf("Version mismatch %s: %s != %s", pkg, got, required_pkgs[[pkg]]), call.=FALSE)
}
env <- ag_rf_check_environment()
if (!identical(as.character(env$python), "3.13.5")) stop("Python version mismatch", call.=FALSE)
if (!identical(as.character(env$numpy), "2.3.5")) stop("NumPy version mismatch", call.=FALSE)
if (!identical(as.character(env$scikit_learn), "1.8.0")) stop("scikit-learn version mismatch", call.=FALSE)
spec <- ag_rf_python_spec()
sc <- ag_rf_system2(spec, c("-c", shQuote("import scipy; print(scipy.__version__)")), stdout=TRUE, stderr=TRUE)
if (sc$status != 0L || length(sc$output) < 1L) stop("SciPy environment check failed", call.=FALSE)
scipy_version <- trimws(as.character(sc$output[[length(sc$output)]]))
if (!identical(scipy_version, "1.17.0")) stop(sprintf("SciPy version mismatch: %s", scipy_version), call.=FALSE)
if (!file.exists("renv.lock")) stop("renv.lock missing; run scripts/initialize_renv.R", call.=FALSE)
dir.create("outputs", showWarnings=FALSE)
info <- list(
  status="PASS", r=as.character(getRversion()), platform=R.version$platform,
  python=env$python, numpy=env$numpy, scipy=scipy_version, scikit_learn=env$scikit_learn,
  launcher=env$launcher_source,
  renv_lock_sha256=digest::digest(file="renv.lock",algo="sha256",serialize=FALSE),
  session_info=capture.output(utils::sessionInfo())
)
jsonlite::write_json(info,"outputs/AUTOGREY_RELEASE_ENVIRONMENT.json",pretty=TRUE,auto_unbox=TRUE)
cat(sprintf("INFO R=%s Python=%s NumPy=%s SciPy=%s sklearn=%s\n", getRversion(), env$python, env$numpy, scipy_version, env$scikit_learn))
cat("AUTOGREY_RELEASE_ENVIRONMENT: PASS\n")
