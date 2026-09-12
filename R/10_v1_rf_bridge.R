# AutoGrey Step 7D1 — frozen V1 RF bridge and deterministic selector helper.
#
# Scientific boundary:
# - Upstream 56-input construction and group/fold median preprocessing remain R-native
#   and were externally verified at Step 7C2.
# - The RF fit itself is executed by the exact frozen scikit-learn 1.8.0
#   RandomForestRegressor semantics from Step 5D-B-R2.
# - This is deliberate: ranger::case.weights changes bootstrap sampling probability,
#   whereas sklearn sample_weight affects weighted tree fitting without changing the
#   uniform bootstrap index stream. Substituting ranger would change the frozen model.
# - No RF hyperparameter may be retuned here.

AG_V1_RF_BRIDGE_VERSION <- "AG_STEP7D1_RF_BRIDGE_R_1"
AG_V1_RF_SEED <- 62291L
AG_V1_RF_TREES <- 500L
AG_V1_RF_WIDTH <- 56L
AG_V1_RF_MIN_LEAF_FRACTION <- 0.01
AG_V1_RF_MAX_FEATURES <- "sqrt"

ag_rf_python_spec <- function() {
  explicit <- Sys.getenv("AUTOGREY_PYTHON", unset = "")
  if (nzchar(explicit)) {
    if (!file.exists(explicit)) stop("AUTOGREY_PYTHON does not point to an existing executable", call. = FALSE)
    return(list(exe = explicit, prefix = character(0), source = "AUTOGREY_PYTHON"))
  }
  for (nm in c("python", "python3")) {
    p <- Sys.which(nm)
    if (nzchar(p)) return(list(exe = unname(p), prefix = character(0), source = nm))
  }
  py <- Sys.which("py")
  if (nzchar(py)) return(list(exe = unname(py), prefix = "-3.13", source = "py -3.13"))
  stop(paste0(
    "No Python executable found. Install/use Python 3.13 with numpy 2.3.5 and scikit-learn 1.8.0, ",
    "or set AUTOGREY_PYTHON to the exact python.exe path."
  ), call. = FALSE)
}

ag_rf_system2 <- function(spec, args, stdout = TRUE, stderr = TRUE) {
  out <- system2(spec$exe, args = c(spec$prefix, args), stdout = stdout, stderr = stderr)
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  list(output = out, status = as.integer(status))
}

ag_rf_check_environment <- function(helper = "reference/python/ag_step7d1_sklearn_bridge.py", python = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required", call. = FALSE)
  if (!file.exists(helper)) stop(paste0("RF bridge helper missing: ", helper), call. = FALSE)
  spec <- if (is.null(python)) ag_rf_python_spec() else list(exe = python, prefix = character(0), source = "explicit")
  z <- ag_rf_system2(spec, c(helper, "--check-env"), stdout = TRUE, stderr = TRUE)
  if (z$status != 0L) stop(paste0("Python environment check failed: ", paste(z$output, collapse = "\n")), call. = FALSE)
  txt <- paste(z$output, collapse = "\n")
  env <- jsonlite::fromJSON(txt, simplifyVector = TRUE)
  env$launcher_source <- spec$source
  env
}

ag_rf_write_matrix_f64le <- function(X, path) {
  A <- as.matrix(X)
  storage.mode(A) <- "double"
  if (length(dim(A)) != 2L || nrow(A) < 1L || ncol(A) < 1L) stop("X must be a nonempty numeric matrix", call. = FALSE)
  if (any(!is.finite(A))) stop("RF bridge matrix contains non-finite values; preprocess before fitting", call. = FALSE)
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  # R matrices are column-major. as.double(t(A)) emits original A in row-major
  # order, matching numpy reshape(order='C').
  writeBin(as.double(t(A)), con, size = 8L, endian = "little")
  invisible(path)
}

ag_rf_write_vector_f64le <- function(x, path, allow_zero = TRUE) {
  v <- as.double(x)
  if (!length(v) || any(!is.finite(v))) stop("RF bridge vector must be finite and nonempty", call. = FALSE)
  if (!allow_zero && any(v <= 0)) stop("RF bridge weights must be strictly positive", call. = FALSE)
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(v, con, size = 8L, endian = "little")
  invisible(path)
}

ag_rf_fit_predict_sklearn <- function(X_train, y_train, sample_weight, X_eval,
                                      helper = "reference/python/ag_step7d1_sklearn_bridge.py",
                                      python = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required", call. = FALSE)
  A <- as.matrix(X_train); E <- as.matrix(X_eval)
  storage.mode(A) <- storage.mode(E) <- "double"
  y <- as.double(y_train)
  w <- if (is.null(sample_weight)) NULL else as.double(sample_weight)
  if (nrow(A) != length(y)) stop("X_train/y_train row mismatch", call. = FALSE)
  if (!is.null(w) && nrow(A) != length(w)) stop("X_train/sample_weight row mismatch", call. = FALSE)
  if (ncol(A) != AG_V1_RF_WIDTH || ncol(E) != AG_V1_RF_WIDTH) stop("RF bridge requires exactly 56 predictors", call. = FALSE)
  if (any(!is.finite(A)) || any(!is.finite(E)) || any(!is.finite(y))) stop("RF bridge inputs must be finite after preprocessing", call. = FALSE)
  if (!is.null(w) && (any(!is.finite(w)) || any(w < 0))) stop("sample_weight must be finite and nonnegative", call. = FALSE)

  spec <- if (is.null(python)) ag_rf_python_spec() else list(exe = python, prefix = character(0), source = "explicit")
  td <- tempfile("autogrey_step7d1_rf_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)
  px <- file.path(td, "x_train.f64")
  py <- file.path(td, "y_train.f64")
  pe <- file.path(td, "x_eval.f64")
  pw <- if (is.null(w)) NULL else file.path(td, "weights.f64")
  preq <- file.path(td, "request.json")
  pout <- file.path(td, "result.json")
  ag_rf_write_matrix_f64le(A, px)
  ag_rf_write_vector_f64le(y, py)
  ag_rf_write_matrix_f64le(E, pe)
  if (!is.null(w)) ag_rf_write_vector_f64le(w, pw, allow_zero = TRUE)
  req <- list(
    x_train_path = normalizePath(px, winslash = "/", mustWork = TRUE),
    y_train_path = normalizePath(py, winslash = "/", mustWork = TRUE),
    x_eval_path = normalizePath(pe, winslash = "/", mustWork = TRUE),
    weight_train_path = if (is.null(pw)) NULL else normalizePath(pw, winslash = "/", mustWork = TRUE),
    n_train = nrow(A), n_eval = nrow(E), n_features = ncol(A)
  )
  jsonlite::write_json(req, preq, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 17)
  z <- ag_rf_system2(spec, c(helper, "--request", preq, "--output", pout), stdout = TRUE, stderr = TRUE)
  if (!file.exists(pout)) stop(paste0("RF bridge produced no result file. Console: ", paste(z$output, collapse = "\n")), call. = FALSE)
  ans <- jsonlite::fromJSON(pout, simplifyVector = FALSE)
  if (z$status != 0L || !identical(ans$status, "PASS")) {
    stop(paste0("RF bridge failed: ", ans$error %||% paste(z$output, collapse = "\n")), call. = FALSE)
  }
  ans
}

`%||%` <- function(x, y) if (is.null(x)) y else x

ag_v1_choose_by_predicted_target <- function(scores, groups = names(scores)) {
  s <- as.double(scores)
  g <- as.character(groups)
  if (!length(s) || length(s) != length(g)) stop("scores/groups mismatch", call. = FALSE)
  if (any(!is.finite(s))) stop("predicted scores must be finite", call. = FALSE)
  if (!exists("AG_V1_GROUPS", inherits = TRUE)) stop("AG_V1_GROUPS unavailable; source R/09_v1_preprocess.R", call. = FALSE)
  gi <- match(g, AG_V1_GROUPS)
  if (anyNA(gi)) stop("unknown structural group", call. = FALSE)
  # Canonical Python rule: min((predicted target, frozen group index)).
  ord <- order(s, gi, method = "radix")
  list(group = g[ord[1L]], score = s[ord[1L]], group_index_0based = gi[ord[1L]] - 1L)
}
