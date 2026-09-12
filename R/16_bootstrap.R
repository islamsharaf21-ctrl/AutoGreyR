# AutoGrey Step 7F2 — exact frozen NumPy PCG64 bootstrap bridge.
AG_STEP7F2_VERSION <- "AG_STEP7F2_PCG64_BOOTSTRAP_R_1"
AG_STEP7F2_HELPER <- "reference/python/ag_step7f2_pcg64_bootstrap.py"
AG_STEP7F2_DECISIONS <- "reference/frozen_step7f1/AUTOGREY_STEP7F1_DECISIONS_ORACLE.csv"

ag_step7f2_run_pcg64_bootstrap <- function(decisions=AG_STEP7F2_DECISIONS, helper=AG_STEP7F2_HELPER) {
  if (!requireNamespace("jsonlite", quietly=TRUE)) stop("Package 'jsonlite' is required", call.=FALSE)
  spec <- ag_rf_python_spec()
  td <- tempfile("autogrey_step7f2_"); dir.create(td, recursive=TRUE, showWarnings=FALSE)
  csvp <- file.path(td,"bootstrap.csv"); jsp <- file.path(td,"summary.json")
  z <- ag_rf_system2(spec,c(helper,"--decisions",decisions,"--out-csv",csvp,"--out-json",jsp),stdout=TRUE,stderr=TRUE)
  if (z$status!=0L || !file.exists(csvp) || !file.exists(jsp)) {
    unlink(td,recursive=TRUE,force=TRUE); stop(paste0("Step7F2 PCG64 bridge failed: ",paste(z$output,collapse="\n")),call.=FALSE)
  }
  dat <- utils::read.csv(csvp,stringsAsFactors=FALSE,check.names=FALSE)
  js <- jsonlite::fromJSON(jsp,simplifyVector=FALSE)
  hashes <- list(csv_sha256=digest::digest(file=csvp,algo="sha256",serialize=FALSE), json_sha256=digest::digest(file=jsp,algo="sha256",serialize=FALSE))
  rawcsv <- readBin(csvp,"raw",n=file.info(csvp)$size)
  unlink(td,recursive=TRUE,force=TRUE)
  list(data=dat,summary=js,hashes=hashes,csv_raw=rawcsv,console=z$output)
}
