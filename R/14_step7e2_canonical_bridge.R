# AutoGrey Step 7E2 R5 — canonical development/forecast bridge.
#
# Purpose:
#   Preserve the externally verified native-R structural engine unchanged while
#   reproducing the frozen Python numerical semantics at the two places where
#   R4 demonstrated material cross-language divergence:
#     1) decimal -> float64 parsing for development D (4 / 2496 parents), and
#     2) final selected-config forecasts for SG02 and SG05 only.
#
# This layer NEVER accepts numeric held-out targets. It uses the already-audited
# development-only Python parser and a forecast helper that accepts only D.

AG_STEP7E2_CANONICAL_BRIDGE_VERSION <- "AG_STEP7E2_CANONICAL_BRIDGE_R_1"
AG_STEP7E2_SENSITIVE_GROUPS <- c("SG02_DISCRETE_POLY", "SG05_CONT_TIME_POLY")
AG_STEP7E2_CANONICAL_D_HELPER <- "reference/python/ag_step7e2_canonical_d_bridge.py"
AG_STEP7E2_SENSITIVE_FORECAST_HELPER <- "reference/python/ag_step7e2_sensitive_forecast_bridge.py"
AG_STEP7E2_CANONICAL_ENGINE <- "reference/python/autogrey_engine_step4fb_r1.py"

ag_step7e2_read_f64le <- function(path) {
  if (!file.exists(path)) stop(paste0("binary file missing: ", path), call. = FALSE)
  sz <- file.info(path)$size
  if (is.na(sz) || sz < 0 || (sz %% 8) != 0) stop(paste0("invalid float64 binary size: ", path), call. = FALSE)
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  readBin(con, what = "double", n = as.integer(sz / 8), size = 8L, endian = "little")
}

ag_step7e2_build_canonical_d <- function(
    bundle = "reference/raw/AUTOGREY_REALBENCH2_RAW_RESERVATION_BUNDLE_STEP5B.zip",
    helper = AG_STEP7E2_CANONICAL_D_HELPER) {
  spec <- ag_rf_python_spec()
  td <- tempfile("autogrey_step7e2_canonical_d_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  idx_path <- file.path(td, "canonical_d_index.csv")
  bin_path <- file.path(td, "canonical_d.f64le")
  z <- ag_rf_system2(
    spec,
    c(helper, "--bundle", bundle, "--out-index", idx_path, "--out-binary", bin_path),
    stdout = TRUE, stderr = TRUE
  )
  if (z$status != 0L || !file.exists(idx_path) || !file.exists(bin_path)) {
    unlink(td, recursive = TRUE, force = TRUE)
    stop(paste0("canonical-D bridge failed: ", paste(z$output, collapse = "\n")), call. = FALSE)
  }
  idx <- utils::read.csv(idx_path, stringsAsFactors = FALSE, check.names = FALSE,
                         colClasses = "character", na.strings = character(0))
  if (nrow(idx) != 2511L || anyDuplicated(idx$parent_id)) {
    unlink(td, recursive = TRUE, force = TRUE)
    stop("canonical-D index identity/count failure", call. = FALSE)
  }
  d_all <- ag_step7e2_read_f64le(bin_path)
  list(root = td, index = idx, values = d_all, binary_path = bin_path,
       helper_console = z$output)
}

ag_step7e2_get_canonical_d <- function(parent_id, n_D, canon_d) {
  j <- match(as.character(parent_id), canon_d$index$parent_id)
  if (is.na(j)) stop(paste0("canonical-D parent missing: ", parent_id), call. = FALSE)
  r <- canon_d$index[j, , drop = FALSE]
  if (!identical(as.character(r$status[[1L]]), "D_PARSED")) {
    stop(paste0("canonical-D status not D_PARSED: ", parent_id), call. = FALSE)
  }
  n <- suppressWarnings(as.integer(r$n_D[[1L]]))
  off <- suppressWarnings(as.numeric(r$offset_bytes[[1L]]))
  if (is.na(n) || n != as.integer(n_D) || !is.finite(off) || off < 0 || off != floor(off) || (off %% 8) != 0) {
    stop(paste0("canonical-D geometry mismatch: ", parent_id), call. = FALSE)
  }
  lo <- as.integer(off / 8) + 1L
  hi <- lo + n - 1L
  if (lo < 1L || hi > length(canon_d$values)) stop(paste0("canonical-D bounds: ", parent_id), call. = FALSE)
  D <- canon_d$values[lo:hi]
  if (length(D) != n || any(!is.finite(D))) stop(paste0("canonical-D nonfinite/length: ", parent_id), call. = FALSE)
  list(D = D, development_hash = as.character(r$development_hash[[1L]]),
       offset_bytes = off)
}

# Same frozen target-sealing chronology as R/13, except D is supplied from the
# canonical Python float64 parser instead of R's decimal parser. Target tokens
# remain opaque character strings and are used only for missing-marker checks
# and their SHA-256 commitment.
ag_rb2_scan_pretarget_canonical_d <- function(reservations, rawdir, canon_d, verbose = TRUE) {
  items <- list(); refusals <- list(); ii <- 0L; rrn <- 0L
  sources <- sort(names(AG_RB2_RAW), method = "radix")
  for (source in sources) {
    rs <- reservations[reservations$source_id == source, , drop = FALSE]
    recovered <- ag_rb2_read_reserved_source(
      file.path(rawdir, AG_RB2_RAW[[source]]$file), AG_RB2_RAW[[source]]$member, rs$series_id
    )
    if (verbose) cat(sprintf("INFO canonical-D pretarget source=%s reserved=%d\n", source, nrow(rs)))
    for (jj in seq_len(nrow(rs))) {
      r <- rs[jj, , drop = FALSE]; sid <- r$series_id[[1L]]; z <- recovered[[sid]]
      h <- r$h_int[[1L]]; M <- if (is.na(r$M_int[[1L]])) NULL else r$M_int[[1L]]
      tokens <- strsplit(z$value_field, ",", fixed = TRUE)[[1L]]
      N <- length(tokens); t <- N - h
      missing_marker <- trimws(tokens) %in% c("?", "NaN", "nan", "inf", "-inf", "")
      if (any(missing_marker)) {
        rrn <- rrn + 1L
        refusals[[rrn]] <- list(parent_id = r$parent_id[[1L]], source_id = source,
                                series_id = sid, h = h, M = M, N = N,
                                reason = "SOURCE_MISSING_OR_NONFINITE_TOKEN")
        next
      }
      # CRITICAL: target_tokens remain CHARACTER and are never numeric-parsed.
      target_tokens <- if (t >= 0L) tokens[(t + 1L):N] else tokens
      target_raw_sha <- ag_rb2_sha_ascii(paste(target_tokens, collapse = ","))
      if (t < 4L) {
        rrn <- rrn + 1L
        refusals[[rrn]] <- list(parent_id = r$parent_id[[1L]], source_id = source,
                                series_id = sid, h = h, M = M, N = N,
                                reason = "INSUFFICIENT_HISTORY_N_MINUS_H_LT_4",
                                target_raw_sha256 = target_raw_sha)
        next
      }
      cd <- tryCatch(ag_step7e2_get_canonical_d(r$parent_id[[1L]], t, canon_d), error = identity)
      if (inherits(cd, "error")) {
        rrn <- rrn + 1L
        refusals[[rrn]] <- list(parent_id = r$parent_id[[1L]], source_id = source,
                                series_id = sid, h = h, M = M, N = N,
                                reason = "D_PARSE_FAIL", target_raw_sha256 = target_raw_sha)
        next
      }
      D <- cd$D
      got <- tryCatch({
        snap <- ag_extract_features(D, h, M)
        port <- ag_run_structural_portfolio(D, h, M)
        list(snap = snap, port = port)
      }, error = function(e) e)
      if (inherits(got, "error")) {
        rrn <- rrn + 1L
        refusals[[rrn]] <- list(parent_id = r$parent_id[[1L]], source_id = source,
                                series_id = sid, h = h, M = M, N = N,
                                reason = paste0("PRETARGET_ENGINE_OR_FEATURE_FAIL:", class(got)[1L]),
                                target_raw_sha256 = target_raw_sha)
        next
      }
      eligible <- as.character(got$port$distinct_groups)
      if (!length(eligible)) {
        rrn <- rrn + 1L
        refusals[[rrn]] <- list(parent_id = r$parent_id[[1L]], source_id = source,
                                series_id = sid, h = h, M = M, N = N,
                                reason = "NO_ELIGIBLE_STRUCTURAL_GROUP",
                                target_raw_sha256 = target_raw_sha)
        next
      }
      if (any(!eligible %in% AG_V1_GROUPS)) stop(paste0("unknown eligible group: ", r$parent_id[[1L]]), call. = FALSE)
      eb <- as.double(AG_V1_GROUPS %in% eligible)
      x <- ag_v1_build_from_snapshot(got$snap$values, got$snap$valid, eb)
      groups <- vector("list", length(eligible)); names(groups) <- eligible
      for (g in eligible) {
        gr <- got$port$group_results[[g]]
        f <- as.double(gr$forecast)
        if (length(f) != h || any(!is.finite(f))) stop(paste0("nonfinite target-free forecast: ", r$parent_id[[1L]], " ", g), call. = FALSE)
        groups[[g]] <- list(selected_config_id = as.character(gr$selected_config_id), forecast = f)
      }
      ii <- ii + 1L
      items[[ii]] <- list(
        parent_id = r$parent_id[[1L]], source_id = source, dataset = r$dataset[[1L]],
        series_id = sid, frequency = r$frequency[[1L]], M = M, h = h, N = N,
        n_D = t, start_timestamp = z$start_timestamp,
        development_hash = cd$development_hash,
        feature_hash_r = got$snap$feature_hash,
        target_raw_sha256 = target_raw_sha,
        eligible_count = length(eligible), eligible_groups = eligible,
        Xraw = as.double(x), groups = groups
      )
    }
  }
  list(items = items, refusals = refusals)
}

ag_step7e2_apply_sensitive_forecast_bridge <- function(
    decisions, canon_d,
    helper = AG_STEP7E2_SENSITIVE_FORECAST_HELPER,
    engine = AG_STEP7E2_CANONICAL_ENGINE,
    verbose = TRUE) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' required", call. = FALSE)
  spec <- ag_rf_python_spec()
  req <- list(); map_i <- integer(0); map_g <- character(0); rn <- 0L
  for (i in seq_along(decisions)) {
    z <- decisions[[i]]
    j <- match(z$parent_id, canon_d$index$parent_id)
    if (is.na(j)) stop(paste0("sensitive bridge parent missing: ", z$parent_id), call. = FALSE)
    off <- canon_d$index$offset_bytes[[j]]
    for (g in intersect(AG_STEP7E2_SENSITIVE_GROUPS, as.character(z$eligible_groups))) {
      rn <- rn + 1L
      req[[rn]] <- data.frame(
        request_id = sprintf("R%05d", rn), parent_id = as.character(z$parent_id),
        group = as.character(g), config_id = as.character(z$groups[[g]]$selected_config_id),
        h = as.integer(z$h), n_D = as.integer(z$n_D), d_offset_bytes = as.character(off),
        stringsAsFactors = FALSE
      )
      map_i[rn] <- i; map_g[rn] <- g
    }
  }
  if (!length(req)) stop("sensitive forecast bridge produced no requests", call. = FALSE)
  reqdf <- do.call(rbind, req)
  if (anyDuplicated(reqdf$request_id)) stop("sensitive bridge duplicate request_id", call. = FALSE)
  td <- tempfile("autogrey_step7e2_sensitive_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)
  req_path <- file.path(td, "requests.csv")
  out_idx <- file.path(td, "forecast_index.csv")
  out_bin <- file.path(td, "forecasts.f64le")
  utils::write.csv(reqdf, req_path, row.names = FALSE, na = "", quote = TRUE)
  z <- ag_rf_system2(
    spec,
    c(helper, "--requests", req_path, "--d-binary", canon_d$binary_path,
      "--engine", engine, "--out-index", out_idx, "--out-binary", out_bin),
    stdout = TRUE, stderr = TRUE
  )
  if (z$status != 0L || !file.exists(out_idx) || !file.exists(out_bin)) {
    stop(paste0("sensitive forecast bridge failed: ", paste(z$output, collapse = "\n")), call. = FALSE)
  }
  oi <- utils::read.csv(out_idx, stringsAsFactors = FALSE, check.names = FALSE,
                        colClasses = "character", na.strings = character(0))
  if (nrow(oi) != nrow(reqdf) || !identical(oi$request_id, reqdf$request_id) ||
      !identical(oi$parent_id, reqdf$parent_id) || !identical(oi$group, reqdf$group) ||
      !identical(oi$config_id, reqdf$config_id)) {
    stop("sensitive forecast bridge output identity/order mismatch", call. = FALSE)
  }
  allf <- ag_step7e2_read_f64le(out_bin)
  for (k in seq_len(nrow(oi))) {
    off <- suppressWarnings(as.numeric(oi$forecast_offset_bytes[[k]]))
    nf <- suppressWarnings(as.integer(oi$n_forecast[[k]]))
    if (!is.finite(off) || off < 0 || off != floor(off) || (off %% 8) != 0 || is.na(nf) || nf < 1L) {
      stop(paste0("sensitive forecast geometry: ", oi$request_id[[k]]), call. = FALSE)
    }
    lo <- as.integer(off / 8) + 1L; hi <- lo + nf - 1L
    if (lo < 1L || hi > length(allf)) stop(paste0("sensitive forecast bounds: ", oi$request_id[[k]]), call. = FALSE)
    f <- allf[lo:hi]
    if (length(f) != as.integer(decisions[[map_i[[k]]]]$h) || any(!is.finite(f))) {
      stop(paste0("sensitive forecast invalid: ", oi$request_id[[k]]), call. = FALSE)
    }
    rawf <- writeBin(as.double(f), raw(), size = 8L, endian = "little")
    got_sha <- digest::digest(rawf, algo = "sha256", serialize = FALSE)
    if (!identical(got_sha, as.character(oi$forecast_sha256[[k]]))) {
      stop(paste0("sensitive forecast SHA mismatch: ", oi$request_id[[k]]), call. = FALSE)
    }
    decisions[[map_i[[k]]]]$groups[[map_g[[k]]]]$forecast <- as.double(f)
  }
  counts <- table(factor(reqdf$group, levels = AG_STEP7E2_SENSITIVE_GROUPS))
  if (verbose) cat(sprintf(
    "INFO canonical sensitive forecast bridge requests=%d SG02=%d SG05=%d\n",
    nrow(reqdf), as.integer(counts[[1L]]), as.integer(counts[[2L]])
  ))
  list(decisions = decisions, request_count = nrow(reqdf),
       counts = setNames(as.integer(counts), AG_STEP7E2_SENSITIVE_GROUPS),
       console = z$output)
}

ag_rb2_pretarget_reproduce_canonical <- function(
    bundle = "reference/raw/AUTOGREY_REALBENCH2_RAW_RESERVATION_BUNDLE_STEP5B.zip",
    rf_helper = "reference/python/ag_step7d1_sklearn_bridge.py",
    verbose = TRUE) {
  canon_d <- ag_step7e2_build_canonical_d(bundle = bundle)
  on.exit(unlink(canon_d$root, recursive = TRUE, force = TRUE), add = TRUE)
  raw <- ag_rb2_unpack_bundle(bundle)
  on.exit(unlink(raw$root, recursive = TRUE, force = TRUE), add = TRUE)
  reservations <- ag_rb2_load_reservations(raw$reservation)
  dat <- ag_v1_load_frozen_train()
  trainfit <- ag_rb2_prepare_train_models(dat, helper = rf_helper, verbose = verbose)
  scan <- ag_rb2_scan_pretarget_canonical_d(reservations, raw$rawdir, canon_d, verbose = verbose)
  out <- ag_rb2_fit_predict_external(scan, trainfit, verbose = verbose)
  bridged <- ag_step7e2_apply_sensitive_forecast_bridge(out$decisions, canon_d, verbose = verbose)
  out$decisions <- bridged$decisions
  out$sensitive_bridge_request_count <- bridged$request_count
  out$sensitive_bridge_counts <- bridged$counts
  ids <- vapply(out$decisions, `[[`, character(1), "parent_id")
  rids <- if (length(out$refusals)) vapply(out$refusals, `[[`, character(1), "parent_id") else character(0)
  if (length(intersect(ids, rids)) || !setequal(c(ids, rids), reservations$parent_id)) {
    stop("canonical decision/refusal identity partition mismatch", call. = FALSE)
  }
  out$reservations <- reservations
  out
}
