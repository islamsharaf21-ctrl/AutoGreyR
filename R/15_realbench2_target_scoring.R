# AutoGrey Step 7F1 — frozen REALBENCH2 target scoring.
#
# This is a post-hoc R reproduction of the already-frozen Step5F scientific
# opening/scoring stage. It does NOT refit models, change choices, recompute
# pretarget forecasts, or run any bootstrap/RNG. The canonical pretarget
# forecasts are read from a Linux-generated float64 pack bound to the frozen
# Step5F pretarget JSON. Target tokens are hash-checked before canonical Python
# float64 parsing, matching the frozen opening chronology.

AG_STEP7F1_VERSION <- "AG_STEP7F1_FROZEN_TARGET_SCORING_R_1"
AG_STEP7F1_TARGET_HELPER <- "reference/python/ag_step7f1_target_open_bridge.py"
AG_STEP7F1_PRETARGET <- "reference/frozen_step5f/AUTOGREY_REALBENCH2_PRETARGET_STEP5F.json"
AG_STEP7F1_FORECAST_INDEX <- "reference/frozen_step7f1/AUTOGREY_STEP7F1_CANONICAL_FORECAST_INDEX.csv"
AG_STEP7F1_FORECAST_BINARY <- "reference/frozen_step7f1/AUTOGREY_STEP7F1_CANONICAL_FORECASTS_LINUX.f64le"
AG_STEP7F1_RAW_BUNDLE <- "reference/raw/AUTOGREY_REALBENCH2_RAW_RESERVATION_BUNDLE_STEP5B.zip"
AG_STEP7F1_GROUPS <- c(
  "SG01_CONT_GM", "SG02_DISCRETE_POLY", "SG03_FRAC_LINEAR",
  "SG04_BERNOULLI", "SG05_CONT_TIME_POLY", "SG06_CONFORMABLE",
  "SG07_ROLLING", "SG08_WBO", "SG09_GREY_MARKOV", "SG10_SEASONAL"
)

ag7f1_sha_file <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

ag7f1_read_f64le <- function(path) {
  if (!file.exists(path)) stop(paste0("missing float64 file: ", path), call. = FALSE)
  sz <- file.info(path)$size
  if (is.na(sz) || sz < 0 || (sz %% 8) != 0) stop(paste0("invalid float64 file size: ", path), call. = FALSE)
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  readBin(con, what = "double", n = as.integer(sz / 8), size = 8L, endian = "little")
}

ag7f1_slice_f64 <- function(values, offset_bytes, count, label = "float64") {
  off <- suppressWarnings(as.numeric(offset_bytes))
  n <- suppressWarnings(as.integer(count))
  if (!is.finite(off) || off < 0 || off != floor(off) || (off %% 8) != 0 || is.na(n) || n < 1L) {
    stop(paste0("invalid ", label, " geometry"), call. = FALSE)
  }
  lo <- as.integer(off / 8) + 1L
  hi <- lo + n - 1L
  if (lo < 1L || hi > length(values)) stop(paste0(label, " bounds failure"), call. = FALSE)
  out <- values[lo:hi]
  if (length(out) != n || any(!is.finite(out))) stop(paste0(label, " nonfinite/length failure"), call. = FALSE)
  as.double(out)
}

ag7f1_open_actionable_targets <- function(
    bundle = AG_STEP7F1_RAW_BUNDLE,
    pretarget = AG_STEP7F1_PRETARGET,
    helper = AG_STEP7F1_TARGET_HELPER) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required", call. = FALSE)
  if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required", call. = FALSE)
  spec <- ag_rf_python_spec()
  td <- tempfile("autogrey_step7f1_target_open_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  idx_path <- file.path(td, "target_open_index.csv")
  d_path <- file.path(td, "development.f64le")
  y_path <- file.path(td, "targets.f64le")
  z <- ag_rf_system2(
    spec,
    c(helper, "--bundle", bundle, "--pretarget", pretarget,
      "--out-index", idx_path, "--out-d", d_path, "--out-y", y_path),
    stdout = TRUE, stderr = TRUE
  )
  if (z$status != 0L || !file.exists(idx_path) || !file.exists(d_path) || !file.exists(y_path)) {
    unlink(td, recursive = TRUE, force = TRUE)
    stop(paste0("Step7F1 target-open bridge failed: ", paste(z$output, collapse = "\n")), call. = FALSE)
  }
  idx <- utils::read.csv(
    idx_path, stringsAsFactors = FALSE, check.names = FALSE,
    colClasses = "character", na.strings = character(0)
  )
  if (nrow(idx) != 2496L || anyDuplicated(idx$parent_id)) {
    unlink(td, recursive = TRUE, force = TRUE)
    stop("Step7F1 target-open index identity/count failure", call. = FALSE)
  }
  D <- ag7f1_read_f64le(d_path)
  Y <- ag7f1_read_f64le(y_path)
  hashes <- list(
    index_sha256 = ag7f1_sha_file(idx_path),
    d_binary_sha256 = ag7f1_sha_file(d_path),
    y_binary_sha256 = ag7f1_sha_file(y_path)
  )
  unlink(td, recursive = TRUE, force = TRUE)
  list(index = idx, D = D, Y = Y, hashes = hashes, helper_console = z$output)
}

ag7f1_load_canonical_forecasts <- function(
    index_path = AG_STEP7F1_FORECAST_INDEX,
    binary_path = AG_STEP7F1_FORECAST_BINARY) {
  idx <- utils::read.csv(
    index_path, stringsAsFactors = FALSE, check.names = FALSE,
    colClasses = "character", na.strings = character(0)
  )
  keys <- paste(idx$parent_id, idx$group, sep = "\034")
  if (nrow(idx) != 23572L || anyDuplicated(keys)) {
    stop("canonical forecast index identity/count failure", call. = FALSE)
  }
  values <- ag7f1_read_f64le(binary_path)
  map <- setNames(seq_len(nrow(idx)), keys)
  list(index = idx, values = values, map = map)
}

ag7f1_get_forecast <- function(parent_id, group, h, pack) {
  key <- paste(parent_id, group, sep = "\034")
  hit <- unname(pack$map[[key]])
  if (is.null(hit) || is.na(hit)) stop(paste0("canonical forecast key failure: ", parent_id, " / ", group), call. = FALSE)
  r <- pack$index[hit, , drop = FALSE]
  n <- suppressWarnings(as.integer(r$count[[1L]]))
  if (is.na(n) || n != as.integer(h)) stop(paste0("canonical forecast horizon mismatch: ", parent_id, " / ", group), call. = FALSE)
  ag7f1_slice_f64(pack$values, r$offset_bytes[[1L]], n, "forecast")
}

ag7f1_cvar90 <- function(x) {
  a <- as.double(x)
  if (!length(a) || any(!is.finite(a))) stop("invalid CVaR90 input", call. = FALSE)
  k <- max(1L, as.integer(ceiling(0.10 * length(a))))
  mean(sort(a, decreasing = TRUE, method = "radix")[seq_len(k)])
}

ag7f1_metrics <- function(decisions, field) {
  a <- as.double(decisions[[field]])
  choice_field <- if (identical(field, "v1_regret")) "v1_choice" else "global_choice"
  cc <- table(factor(decisions[[choice_field]], levels = AG_STEP7F1_GROUPS))
  cc <- cc[cc > 0L]
  list(
    n_tasks = as.integer(length(a)),
    n_supported = as.integer(length(a)),
    support_coverage = 1.0,
    mean_regret = as.double(mean(a)),
    median_regret = as.double(stats::median(a)),
    cvar90 = as.double(ag7f1_cvar90(a)),
    p90_regret = as.double(stats::quantile(a, probs = 0.90, names = FALSE, type = 7)),
    zero_regret_rate = as.double(mean(a <= 1e-15)),
    selection_counts = as.list(setNames(as.integer(cc), names(cc)))
  )
}

ag_step7f1_score_frozen_targets <- function(
    bundle = AG_STEP7F1_RAW_BUNDLE,
    pretarget = AG_STEP7F1_PRETARGET,
    forecast_index = AG_STEP7F1_FORECAST_INDEX,
    forecast_binary = AG_STEP7F1_FORECAST_BINARY,
    verbose = TRUE) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required", call. = FALSE)
  pobj <- jsonlite::fromJSON(pretarget, simplifyVector = FALSE)
  if (!identical(as.integer(pobj$reservation_count), 2511L) || !identical(as.integer(pobj$actionable_count), 2496L)) {
    stop("frozen pretarget counts invalid", call. = FALSE)
  }
  if (isTRUE(pobj$chronology$target_tokens_numeric_parsed) || isTRUE(pobj$chronology$outcomes_opened)) {
    stop("frozen pretarget chronology invalid", call. = FALSE)
  }
  decisions_pre <- pobj$decisions
  if (length(decisions_pre) != 2496L) stop("frozen pretarget actionable list count invalid", call. = FALSE)
  pids <- vapply(decisions_pre, function(z) as.character(z$parent_id), character(1))
  if (anyDuplicated(pids)) stop("frozen pretarget duplicate parent_id", call. = FALSE)
  pmap <- setNames(seq_along(pids), pids)

  if (verbose) cat("INFO opening actionable target tokens only after frozen commitment verification...\n")
  targ <- ag7f1_open_actionable_targets(bundle = bundle, pretarget = pretarget)
  if (verbose) cat(sprintf("INFO canonical target bridge actionable=%d D_values=%d Y_values=%d\n", nrow(targ$index), length(targ$D), length(targ$Y)))
  fpack <- ag7f1_load_canonical_forecasts(forecast_index, forecast_binary)
  if (verbose) cat(sprintf("INFO canonical Linux forecast pack eligible_actions=%d values=%d\n", nrow(fpack$index), length(fpack$values)))

  idx <- targ$index
  # Bridge output is sorted by parent_id; enforce exact same parent set as pretarget.
  if (!setequal(idx$parent_id, pids)) stop("target-open parent set mismatch", call. = FALSE)

  loss_parts <- vector("list", nrow(idx))
  dec_parts <- vector("list", nrow(idx))
  scale_rel_max <- 0

  for (i in seq_len(nrow(idx))) {
    ir <- idx[i, , drop = FALSE]
    parent_id <- ir$parent_id[[1L]]
    j <- unname(pmap[[parent_id]])
    if (is.null(j) || is.na(j)) stop(paste0("pretarget parent missing: ", parent_id), call. = FALSE)
    d <- decisions_pre[[j]]
    h <- as.integer(d$h)
    n_D <- as.integer(d$n_D)
    M <- if (is.null(d$M)) NULL else as.integer(d$M)
    if (!identical(as.character(ir$source_id[[1L]]), as.character(d$source_id)) ||
        !identical(as.character(ir$series_id[[1L]]), as.character(d$series_id)) ||
        suppressWarnings(as.integer(ir$h[[1L]])) != h ||
        suppressWarnings(as.integer(ir$n_D[[1L]])) != n_D ||
        !identical(as.character(ir$target_raw_sha256[[1L]]), as.character(d$target_raw_sha256)) ||
        !identical(as.character(ir$development_sha256[[1L]]), as.character(d$development_hash))) {
      stop(paste0("target-open metadata/commitment mismatch: ", parent_id), call. = FALSE)
    }
    D <- ag7f1_slice_f64(targ$D, ir$d_offset_bytes[[1L]], n_D, "development")
    Y <- ag7f1_slice_f64(targ$Y, ir$y_offset_bytes[[1L]], h, "target")
    scale_can <- suppressWarnings(as.double(ir$mase_scale[[1L]]))
    if (!is.finite(scale_can) || scale_can <= 0) stop(paste0("invalid canonical MASE scale: ", parent_id), call. = FALSE)
    scale_r <- ag_mase_scale(D, M)
    srel <- abs(scale_r - scale_can) / max(1.0, abs(scale_can))
    if (srel > scale_rel_max) scale_rel_max <- srel

    group_names <- names(d$groups)
    elig <- AG_STEP7F1_GROUPS[AG_STEP7F1_GROUPS %in% group_names]
    if (length(elig) != as.integer(d$eligible_count)) stop(paste0("eligible group count mismatch: ", parent_id), call. = FALSE)
    gdf <- vector("list", length(elig))
    losses <- setNames(rep(NA_real_, length(elig)), elig)
    for (k in seq_along(elig)) {
      g <- elig[[k]]
      f <- ag7f1_get_forecast(parent_id, g, h, fpack)
      L <- as.double(mean(abs(Y - f)) / scale_can)
      if (!is.finite(L)) stop(paste0("nonfinite MASE: ", parent_id, " / ", g), call. = FALSE)
      losses[[g]] <- L
      gdf[[k]] <- data.frame(
        parent_id = parent_id,
        source_id = as.character(d$source_id),
        series_id = as.character(d$series_id),
        h = h,
        group = g,
        selected_config_id = as.character(d$groups[[g]]$selected_config_id),
        mase = L,
        stringsAsFactors = FALSE
      )
    }
    loss_parts[[i]] <- do.call(rbind, gdf)
    oracle <- min(as.double(losses))
    vc <- as.character(d$v1_choice)
    gc <- as.character(d$global_choice)
    if (!(vc %in% names(losses)) || !(gc %in% names(losses))) stop(paste0("frozen choice not eligible: ", parent_id), call. = FALSE)
    dec_parts[[i]] <- data.frame(
      parent_id = parent_id,
      source_id = as.character(d$source_id),
      dataset = as.character(d$dataset),
      series_id = as.character(d$series_id),
      frequency = as.character(d$frequency),
      h = h,
      M = if (is.null(M)) NA_integer_ else M,
      N = as.integer(d$N),
      n_D = n_D,
      eligible_count = as.integer(d$eligible_count),
      v1_choice = vc,
      v1_loss_mase = as.double(losses[[vc]]),
      v1_regret = max(0.0, as.double(losses[[vc]] - oracle)),
      global_choice = gc,
      global_loss_mase = as.double(losses[[gc]]),
      global_regret = max(0.0, as.double(losses[[gc]] - oracle)),
      eligible_oracle_mase = as.double(oracle),
      stringsAsFactors = FALSE
    )
  }

  losses <- do.call(rbind, loss_parts)
  decisions <- do.call(rbind, dec_parts)
  old <- Sys.getlocale("LC_COLLATE")
  try(Sys.setlocale("LC_COLLATE", "C"), silent = TRUE)
  losses <- losses[order(losses$parent_id, match(losses$group, AG_STEP7F1_GROUPS), method = "radix"), , drop = FALSE]
  decisions <- decisions[order(decisions$parent_id, method = "radix"), , drop = FALSE]
  if (!is.na(old) && nzchar(old)) try(Sys.setlocale("LC_COLLATE", old), silent = TRUE)
  rownames(losses) <- NULL
  rownames(decisions) <- NULL

  if (nrow(losses) != 23572L || nrow(decisions) != 2496L) stop("Step7F1 scored row-count mismatch", call. = FALSE)
  v1 <- ag7f1_metrics(decisions, "v1_regret")
  global <- ag7f1_metrics(decisions, "global_regret")
  list(
    version = AG_STEP7F1_VERSION,
    target_bridge_hashes = targ$hashes,
    target_index = targ$index,
    mase_scale_max_normalized_difference = as.double(scale_rel_max),
    losses = losses,
    decisions = decisions,
    primary_metrics = v1,
    global_metrics = global,
    estimands = list(
      mean_regret_delta_primary_minus_global = as.double(v1$mean_regret - global$mean_regret),
      cvar90_regret_delta_primary_minus_global = as.double(v1$cvar90 - global$cvar90)
    )
  )
}
