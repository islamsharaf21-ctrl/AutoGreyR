#!/usr/bin/env Rscript
# R5-B2 clean-room preflight. This file does not read REALBENCH3 data.
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args) >= 1) args[[1]] else normalizePath(file.path(dirname(commandArgs(FALSE)[grepl("--file=", commandArgs(FALSE))][1] |> sub("--file=", "", x=_)), ".."), mustWork=FALSE)
expected_r <- "4.6.1"
if (as.character(getRversion()) != expected_r) stop(sprintf("R_VERSION_MISMATCH expected=%s actual=%s", expected_r, getRversion()))
expected <- c(forecast="9.0.2",renv="1.2.3",jsonlite="2.0.0",digest="0.6.39",callr="3.8.0",processx="3.9.0",withr="3.0.3",testthat="3.3.2",ps="1.9.3",S7="0.2.2",magrittr="2.0.5",Rcpp="1.1.2",cli="3.6.6",rlang="1.3.0",cpp11="0.5.5",vctrs="0.7.3")
for (pkg in names(expected)) {
  if (!requireNamespace(pkg, quietly=TRUE)) stop(sprintf("PACKAGE_MISSING %s", pkg))
  got <- as.character(packageVersion(pkg))
  if (got != expected[[pkg]]) stop(sprintf("PACKAGE_VERSION_MISMATCH %s expected=%s actual=%s",pkg,expected[[pkg]],got))
}
si <- sessionInfo()
blas <- as.character(si$BLAS)
lapack <- as.character(si$LAPACK)
if (!grepl("openblas.*0\\.3\\.30", blas, ignore.case=TRUE)) stop(sprintf("BLAS_IDENTITY_MISMATCH %s",blas))
if (!grepl("lp64", blas, ignore.case=TRUE)) stop(sprintf("BLAS_INTERFACE_MISMATCH %s",blas))
for (v in c("OPENBLAS_NUM_THREADS","OMP_NUM_THREADS","MKL_NUM_THREADS","VECLIB_MAXIMUM_THREADS","NUMEXPR_NUM_THREADS")) {
  if (Sys.getenv(v, unset="") != "1") stop(sprintf("THREAD_POLICY_MISMATCH %s=%s",v,Sys.getenv(v,unset="<unset>")))
}
cat("R5B2_R_ENVIRONMENT_PREFLIGHT=PASS\n")
cat("R_VERSION=",as.character(getRversion()),"\n",sep="")
cat("BLAS=",blas,"\n",sep="")
cat("LAPACK=",lapack,"\n",sep="")
