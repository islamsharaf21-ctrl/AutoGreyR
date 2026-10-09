req <- c(
  forecast="9.0.2", renv="1.2.3", jsonlite="2.0.0", digest="0.6.39",
  callr="3.8.0", processx="3.9.0", withr="3.0.3", testthat="3.3.2"
)
if (as.character(getRversion()) != "4.6.1") stop("P3_R_VERSION_MISMATCH")
for (p in names(req)) {
  if (!requireNamespace(p, quietly=TRUE)) stop(paste0("P3_PACKAGE_MISSING:",p))
  got <- as.character(utils::packageVersion(p))
  if (!identical(got, req[[p]])) stop(paste0("P3_PACKAGE_VERSION_MISMATCH:",p,":",got))
}
blas <- unname(extSoftVersion()[["BLAS"]])
lapack <- unname(La_library())
cat("R_VERSION=",as.character(getRversion()),"\n",sep="")
cat("BLAS=",blas,"\n",sep="")
cat("LAPACK=",lapack,"\n",sep="")
if (!identical(blas, "/opt/autogrey-openblas-0.3.30-lp64-skylakex/lib/libopenblas_skylakex-r0.3.30.so")) stop("P3_BLAS_IDENTITY_MISMATCH")
if (!identical(lapack, "/opt/autogrey-openblas-0.3.30-lp64-skylakex/lib/libopenblas_skylakex-r0.3.30.so")) stop("P3_LAPACK_IDENTITY_MISMATCH")
cat("P11A2_R_RUNTIME_PREFLIGHT=PASS\n")
