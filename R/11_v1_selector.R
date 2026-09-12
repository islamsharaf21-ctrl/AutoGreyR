# AutoGrey Step 7D2 — full frozen V1 TRAIN/R2 OOF reproduction.
#
# This layer does NOT change the selector. It orchestrates the already-verified
# Step7C2 56-input preprocessing and Step7D1 sklearn bridge across every frozen
# TRAIN fold/group combination, then applies the canonical minimum-predicted-
# target / group-index decision rule.

AG_V1_FULL_OOF_VERSION <- "AG_STEP7D2_FULL_V1_OOF_R_1"
AG_V1_FULL_OOF_FOLDS <- 0:4
AG_V1_SUPPORT_MIN_PARENTS <- 20L

ag_v1_numvec <- function(x) as.double(unlist(x, use.names = FALSE))

ag_v1_load_frozen_train <- function(
    action_csv = "reference/frozen/AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv",
    labels_csv = "reference/frozen/AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv") {
  if (!file.exists(action_csv) || !file.exists(labels_csv)) stop("frozen TRAIN inputs missing", call. = FALSE)
  action <- utils::read.csv(action_csv, header = TRUE, stringsAsFactors = FALSE,
                            check.names = FALSE, colClasses = "character",
                            na.strings = character(0))
  labels <- utils::read.csv(labels_csv, header = TRUE, stringsAsFactors = FALSE,
                            check.names = FALSE, colClasses = "character",
                            na.strings = character(0))
  train <- action[action$v2_split == "V2_TRAIN", , drop = FALSE]
  if (nrow(train) != 18107L || nrow(labels) != 18107L) stop("expected exactly 18,107 TRAIN action/label rows", call. = FALSE)
  if (anyDuplicated(labels$selector_row_hash)) stop("duplicate frozen TRAIN label hash", call. = FALSE)
  mi <- match(train$selector_row_hash, labels$selector_row_hash)
  if (anyNA(mi)) stop("TRAIN action row missing frozen TRAIN label", call. = FALSE)
  if (!setequal(train$selector_row_hash, labels$selector_row_hash)) stop("TRAIN action/label hash sets differ", call. = FALSE)
  lab <- labels[mi, , drop = FALSE]
  if (!identical(train$parent_id, lab$parent_id) || !identical(train$action_group, lab$action_group)) {
    stop("action/label join identity mismatch", call. = FALSE)
  }
  h1 <- suppressWarnings(as.integer(as.double(train$h)))
  h2 <- suppressWarnings(as.integer(as.double(lab$h)))
  f1 <- suppressWarnings(as.integer(as.double(train$train_cv_fold)))
  f2 <- suppressWarnings(as.integer(as.double(lab$train_cv_fold)))
  if (!identical(h1, h2) || !identical(f1, f2)) stop("action/label horizon/fold mismatch", call. = FALSE)
  wa <- suppressWarnings(as.double(train$action_row_weight))
  wl <- suppressWarnings(as.double(lab$action_row_weight))
  if (any(!is.finite(wa)) || any(wa <= 0) || max(abs(wa - wl)) > 1e-15) stop("action/label weight mismatch", call. = FALSE)
  regret <- suppressWarnings(as.double(lab$eligible_regret))
  target <- suppressWarnings(as.double(lab$target_log1p_regret))
  if (any(!is.finite(regret)) || any(regret < -1e-12) || any(!is.finite(target))) stop("invalid frozen TRAIN regret/target", call. = FALSE)
  regret <- pmax(0, regret)
  if (max(abs(target - log1p(regret))) > 1e-10) stop("target_log1p_regret mismatch", call. = FALSE)

  # Canonical Python order: parent_id, then frozen SG01..SG10 group index.
  old_collate <- Sys.getlocale("LC_COLLATE")
  try(Sys.setlocale("LC_COLLATE", "C"), silent = TRUE)
  gi <- match(train$action_group, AG_V1_GROUPS)
  if (anyNA(gi)) stop("unknown structural group", call. = FALSE)
  ord <- order(train$parent_id, gi, method = "radix")
  train <- train[ord, , drop = FALSE]
  lab <- lab[ord, , drop = FALSE]
  gi <- gi[ord]
  if (!is.na(old_collate) && nzchar(old_collate)) try(Sys.setlocale("LC_COLLATE", old_collate), silent = TRUE)

  Xraw <- ag_v1_build_matrix_from_action_table(train)
  fold <- suppressWarnings(as.integer(as.double(train$train_cv_fold)))
  target <- suppressWarnings(as.double(lab$target_log1p_regret))
  regret <- pmax(0, suppressWarnings(as.double(lab$eligible_regret)))
  weight <- suppressWarnings(as.double(train$action_row_weight))
  parent <- as.character(train$parent_id)
  group <- as.character(train$action_group)
  parents <- unique(parent)
  if (length(parents) != 2070L) stop("expected exactly 2,070 TRAIN parents", call. = FALSE)
  idx_by_parent <- split(seq_len(nrow(train)), factor(parent, levels = parents))
  # Every parent must occupy exactly one frozen fold and its action weights sum to 1.
  for (p in parents) {
    ix <- idx_by_parent[[p]]
    if (length(unique(fold[ix])) != 1L) stop(paste0("parent spans folds: ", p), call. = FALSE)
    if (abs(sum(weight[ix]) - 1) > 5e-12) stop(paste0("parent weights do not sum to 1: ", p), call. = FALSE)
  }
  list(action = train, labels = lab, Xraw = Xraw, fold = fold, group_idx = gi,
       group = group, parent = parent, parents = parents, idx_by_parent = idx_by_parent,
       target = target, regret = regret, weight = weight)
}

ag_v1_full_oof <- function(dat,
                           helper = "reference/python/ag_step7d1_sklearn_bridge.py",
                           verbose = TRUE) {
  n <- length(dat$parent)
  if (n != 18107L || nrow(dat$Xraw) != n || ncol(dat$Xraw) != 56L) stop("invalid full TRAIN arrays", call. = FALSE)
  pred <- rep(NA_real_, n)
  model_audit <- vector("list", 50L)
  ai <- 0L
  supported_model <- matrix(FALSE, nrow = 5L, ncol = length(AG_V1_GROUPS),
                            dimnames = list(as.character(0:4), AG_V1_GROUPS))

  for (fold in AG_V1_FULL_OOF_FOLDS) {
    tr_all <- which(dat$fold != fold)
    for (gi in seq_along(AG_V1_GROUPS)) {
      g <- AG_V1_GROUPS[[gi]]
      tr <- tr_all[dat$group_idx[tr_all] == gi]
      ev <- which(dat$fold == fold & dat$group_idx == gi)
      n_parent_train <- length(unique(dat$parent[tr]))
      ai <- ai + 1L
      if (verbose) cat(sprintf("INFO full V1 fold=%d group=%s n_train=%d n_eval=%d parents=%d\n",
                               fold, g, length(tr), length(ev), n_parent_train))
      if (n_parent_train < AG_V1_SUPPORT_MIN_PARENTS || length(tr) == 0L) {
        model_audit[[ai]] <- list(fold = fold, group = g, supported = FALSE,
                                  n_train = length(tr), n_eval = length(ev), train_parent_count = n_parent_train)
        next
      }
      if (length(ev) == 0L) stop(sprintf("frozen fold/group has zero eval rows: fold=%d group=%s", fold, g), call. = FALSE)
      prep <- ag_v1_fit_medians_and_transform(dat$Xraw[tr, , drop = FALSE], dat$Xraw[ev, , drop = FALSE])
      ans <- ag_rf_fit_predict_sklearn(prep$train, dat$target[tr], dat$weight[tr], prep$eval, helper = helper)
      pv <- ag_v1_numvec(ans$predictions)
      if (length(pv) != length(ev) || any(!is.finite(pv))) stop("RF prediction length/finiteness failure", call. = FALSE)
      pred[ev] <- pv
      supported_model[fold + 1L, gi] <- TRUE
      model_audit[[ai]] <- list(
        fold = fold, group = g, supported = TRUE, n_train = length(tr), n_eval = length(ev),
        train_parent_count = n_parent_train,
        effective_min_samples_leaf = as.integer(ans$effective_min_samples_leaf),
        bootstrap_hash_first = as.character(unlist(ans$bootstrap_index_sha256_first12, use.names = FALSE)[1L]),
        median_vector = as.double(prep$medians)
      )
    }
  }
  if (ai != 50L) stop("expected exactly 50 fold/group model opportunities", call. = FALSE)

  decisions <- vector("list", length(dat$parents))
  for (k in seq_along(dat$parents)) {
    p <- dat$parents[[k]]
    ix <- dat$idx_by_parent[[p]]
    fold <- dat$fold[ix[1L]]
    all_supported <- all(vapply(ix, function(i) supported_model[fold + 1L, dat$group_idx[i]], logical(1)))
    if (!all_supported || any(!is.finite(pred[ix]))) {
      decisions[[k]] <- list(parent_id = p, fold = fold, supported = 0L,
                             choice = NA_character_, regret = NA_real_, predicted_score = NA_real_)
      next
    }
    o <- order(pred[ix], dat$group_idx[ix], method = "radix")
    best <- ix[o[1L]]
    decisions[[k]] <- list(parent_id = p, fold = fold, supported = 1L,
                           choice = dat$group[best], regret = dat$regret[best],
                           predicted_score = pred[best])
  }
  dec <- data.frame(
    parent_id = vapply(decisions, `[[`, character(1), "parent_id"),
    fold = as.integer(vapply(decisions, `[[`, integer(1), "fold")),
    supported = as.integer(vapply(decisions, `[[`, integer(1), "supported")),
    choice = vapply(decisions, function(z) if (is.na(z$choice)) NA_character_ else z$choice, character(1)),
    regret = as.double(vapply(decisions, `[[`, numeric(1), "regret")),
    predicted_score = as.double(vapply(decisions, `[[`, numeric(1), "predicted_score")),
    stringsAsFactors = FALSE
  )
  list(decisions = dec, action_predictions = pred, model_audit = model_audit,
       supported_model = supported_model)
}

ag_v1_metrics_core <- function(decisions) {
  ok <- decisions$supported == 1L
  reg <- decisions$regret[ok]
  if (!length(reg)) stop("no supported V1 decisions", call. = FALSE)
  k <- ceiling(0.10 * length(reg))
  worst <- sort(reg, decreasing = TRUE)[seq_len(k)]
  counts <- table(factor(decisions$choice[ok], levels = AG_V1_GROUPS))
  list(
    n_tasks = nrow(decisions), n_supported = sum(ok), support_coverage = mean(ok),
    mean_regret = mean(reg), median_regret = stats::median(reg),
    cvar90 = mean(worst), p90_regret = as.double(stats::quantile(reg, 0.90, type = 7, names = FALSE)),
    zero_regret_rate = mean(reg <= 1e-15),
    selection_counts = setNames(as.integer(counts), AG_V1_GROUPS)
  )
}
