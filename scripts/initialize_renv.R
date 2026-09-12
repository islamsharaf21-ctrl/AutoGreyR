options(warn = 1)

required_r <- "4.6.1"

required <- c(
  renv = "1.2.3",
  jsonlite = "2.0.0",
  digest = "0.6.39",
  testthat = "3.3.2"
)

expected_lock_sha256 <-
  "1878fca606f6a74365baa05e7a103ee3d9f8a2a411bfc5669fadff1bc7048d59"

if (!identical(as.character(getRversion()), required_r)) {
  stop(
    sprintf(
      "R version mismatch: got %s, required %s",
      getRversion(),
      required_r
    ),
    call. = FALSE
  )
}

if (!file.exists("renv.lock")) {
  stop("Missing committed renv.lock", call. = FALSE)
}

if (!file.exists("renv/activate.R")) {
  stop("Missing renv/activate.R bootstrap", call. = FALSE)
}

# Preserve the committed lockfile bytes before restoration.
# Public reproduction restores FROM this file and must never regenerate it.
lock_size_before <- file.info("renv.lock")$size

if (is.na(lock_size_before) || lock_size_before <= 0) {
  stop("renv.lock is empty or unreadable", call. = FALSE)
}

lock_bytes_before <- readBin(
  "renv.lock",
  what = "raw",
  n = lock_size_before
)

# Explicit activation also makes this script safe when launched
# from a clean Rscript child process.
source("renv/activate.R")

# On Windows, prefer CRAN binary packages for the frozen R version.
# This avoids unnecessary source compilation while preserving the exact
# package versions recorded in renv.lock. Non-Windows platforms retain
# their normal renv package-selection behavior.
if (.Platform$OS.type == "windows") {
  options(pkgType = "binary")
}

if (!requireNamespace("renv", quietly = TRUE)) {
  stop("renv bootstrap failed", call. = FALSE)
}

got_renv <- as.character(utils::packageVersion("renv"))

if (!identical(got_renv, required[["renv"]])) {
  stop(
    sprintf(
      "renv version mismatch: got %s, required %s",
      got_renv,
      required[["renv"]]
    ),
    call. = FALSE
  )
}

cat("Restoring the frozen AutoGreyR environment from renv.lock...\n")

# The committed lockfile is the source of truth.
# Never snapshot or regenerate it during public reproduction.
renv::restore(
  project = getwd(),
  lockfile = "renv.lock",
  prompt = FALSE
)

# The committed lock must remain byte-identical after restore.
lock_size_after <- file.info("renv.lock")$size

if (is.na(lock_size_after) || lock_size_after <= 0) {
  stop("renv.lock became unreadable after restore", call. = FALSE)
}

lock_bytes_after <- readBin(
  "renv.lock",
  what = "raw",
  n = lock_size_after
)

if (!identical(lock_bytes_before, lock_bytes_after)) {
  stop(
    "renv.lock changed during restore; frozen-lock contract violated",
    call. = FALSE
  )
}

# Verify exact package versions required by the release layer.
for (pkg in names(required)) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(
      sprintf(
        "Missing package after restore: %s",
        pkg
      ),
      call. = FALSE
    )
  }

  got <- as.character(utils::packageVersion(pkg))

  if (!identical(got, required[[pkg]])) {
    stop(
      sprintf(
        "Package version mismatch %s: got %s required %s",
        pkg,
        got,
        required[[pkg]]
      ),
      call. = FALSE
    )
  }
}

lock <- jsonlite::fromJSON(
  "renv.lock",
  simplifyVector = FALSE
)

if (!identical(as.character(lock$R$Version), required_r)) {
  stop("renv.lock R version mismatch", call. = FALSE)
}

for (pkg in names(required)) {
  rec <- lock$Packages[[pkg]]

  if (is.null(rec)) {
    stop(
      sprintf("renv.lock missing %s", pkg),
      call. = FALSE
    )
  }

  if (!identical(
    as.character(rec$Version),
    required[[pkg]]
  )) {
    stop(
      sprintf(
        "renv.lock version mismatch for %s",
        pkg
      ),
      call. = FALSE
    )
  }
}

lock_sha256 <- digest::digest(
  file = "renv.lock",
  algo = "sha256",
  serialize = FALSE
)

if (!identical(lock_sha256, expected_lock_sha256)) {
  stop(
    sprintf(
      "renv.lock SHA-256 mismatch: got %s required %s",
      lock_sha256,
      expected_lock_sha256
    ),
    call. = FALSE
  )
}

dir.create(
  "outputs",
  showWarnings = FALSE,
  recursive = TRUE
)

jsonlite::write_json(
  list(
    status = "PASS",
    mode = "restore_from_committed_lock",
    lock_regenerated = FALSE,
    lock_byte_immutable = TRUE,
    r_version = as.character(getRversion()),
    required_packages = as.list(required),
    lock_sha256 = lock_sha256
  ),
  "outputs/AUTOGREY_RENV_STATUS.json",
  pretty = TRUE,
  auto_unbox = TRUE
)

cat("AUTOGREY_RENV_LOCK: PASS\n")