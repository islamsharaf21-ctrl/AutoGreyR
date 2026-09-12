# AutoGrey Step 7E1 — frozen GLOBAL_RANK_V2 reproduction.
#
# Pure-R deterministic comparator. No features, RF, target-free external data,
# REALBENCH2 targets, or bootstrap are used here.

AG_GLOBAL_RANK_VERSION <- "AG_STEP7E1_GLOBAL_RANK_R_1"
AG_GLOBAL_SUPPORT_MIN_PARENTS <- 30L
AG_GLOBAL_FOLDS <- 0:4

ag_global_group_stats <- function(parent, group_idx, regret, weight, indices) {
  ii <- as.integer(indices)
  if (!length(ii)) stop("GLOBAL stats require nonempty training indices", call. = FALSE)
  if (any(!is.finite(regret[ii])) || any(!is.finite(weight[ii])) || any(weight[ii] <= 0)) {
    stop("GLOBAL stats require finite regret and positive weights", call. = FALSE)
  }
  support <- integer(length(AG_V1_GROUPS))
  means <- rep(NA_real_, length(AG_V1_GROUPS))
  names(support) <- names(means) <- AG_V1_GROUPS
  for (gi in seq_along(AG_V1_GROUPS)) {
    ix <- ii[group_idx[ii] == gi]
    support[gi] <- length(unique(parent[ix]))
    if (support[gi] >= AG_GLOBAL_SUPPORT_MIN_PARENTS && length(ix) > 0L) {
      means[gi] <- stats::weighted.mean(regret[ix], weight[ix])
    }
  }
  supported <- which(is.finite(means))
  rank_idx <- supported[order(means[supported], supported, method = "radix")]
  list(support = support, means = means, rank = AG_V1_GROUPS[rank_idx])
}

ag_global_choose <- function(group_idx, group_means) {
  gi <- as.integer(group_idx)
  if (!length(gi) || anyNA(gi) || any(gi < 1L | gi > length(AG_V1_GROUPS))) {
    stop("invalid GLOBAL eligible group indices", call. = FALSE)
  }
  s <- as.double(group_means[gi])
  if (any(!is.finite(s))) return(list(supported = FALSE, group = NA_character_, group_idx = NA_integer_, score = NA_real_))
  o <- order(s, gi, method = "radix")
  j <- o[1L]
  list(supported = TRUE, group = AG_V1_GROUPS[gi[j]], group_idx = gi[j], score = s[j])
}

ag_global_oof <- function(dat, verbose = TRUE) {
  if (length(dat$parent) != 18107L || length(dat$parents) != 2070L) stop("invalid frozen TRAIN arrays", call. = FALSE)
  decisions <- vector("list", length(dat$parents))
  di <- 0L
  audit <- vector("list", length(AG_GLOBAL_FOLDS))
  for (fold in AG_GLOBAL_FOLDS) {
    tr <- which(dat$fold != fold)
    st <- ag_global_group_stats(dat$parent, dat$group_idx, dat$regret, dat$weight, tr)
    vp <- dat$parents[vapply(dat$parents, function(p) dat$fold[dat$idx_by_parent[[p]][1L]] == fold, logical(1))]
    if (verbose) cat(sprintf("INFO GLOBAL fold=%d train_rows=%d validation_parents=%d rank=%s\n",
                             fold, length(tr), length(vp), paste(st$rank, collapse = " < ")))
    audit[[fold + 1L]] <- list(fold = fold, support = st$support, means = st$means, rank = st$rank,
                                train_rows = length(tr), validation_parent_count = length(vp))
    for (p in vp) {
      di <- di + 1L
      ix <- dat$idx_by_parent[[p]]
      z <- ag_global_choose(dat$group_idx[ix], st$means)
      if (!z$supported) {
        decisions[[di]] <- list(parent_id = p, fold = fold, supported = 0L, choice = NA_character_, regret = NA_real_, score = NA_real_)
      } else {
        hit <- ix[dat$group_idx[ix] == z$group_idx]
        if (length(hit) != 1L) stop(paste0("GLOBAL action identity failure: ", p), call. = FALSE)
        decisions[[di]] <- list(parent_id = p, fold = fold, supported = 1L, choice = z$group,
                                regret = dat$regret[hit], score = z$score)
      }
    }
  }
  if (di != length(dat$parents)) stop("GLOBAL OOF did not cover all frozen parents", call. = FALSE)
  d <- decisions[seq_len(di)]
  dec <- data.frame(
    parent_id = vapply(d, `[[`, character(1), "parent_id"),
    fold = as.integer(vapply(d, `[[`, integer(1), "fold")),
    supported = as.integer(vapply(d, `[[`, integer(1), "supported")),
    choice = vapply(d, function(z) if (is.na(z$choice)) NA_character_ else z$choice, character(1)),
    regret = as.double(vapply(d, `[[`, numeric(1), "regret")),
    global_score = as.double(vapply(d, `[[`, numeric(1), "score")),
    stringsAsFactors = FALSE
  )
  # Canonical output order is parent_id ascending under C collation.
  old <- Sys.getlocale("LC_COLLATE"); try(Sys.setlocale("LC_COLLATE", "C"), silent = TRUE)
  dec <- dec[order(dec$parent_id, method = "radix"), , drop = FALSE]
  rownames(dec) <- NULL
  if (!is.na(old) && nzchar(old)) try(Sys.setlocale("LC_COLLATE", old), silent = TRUE)
  list(decisions = dec, fold_audit = audit)
}

ag_global_metrics_core <- function(decisions) {
  ok <- decisions$supported == 1L
  reg <- decisions$regret[ok]
  if (!length(reg)) stop("no supported GLOBAL decisions", call. = FALSE)
  k <- ceiling(0.10 * length(reg))
  cnt <- table(factor(decisions$choice[ok], levels = AG_V1_GROUPS))
  list(
    n_tasks = nrow(decisions), n_supported = sum(ok), support_coverage = mean(ok),
    mean_regret = mean(reg), median_regret = stats::median(reg),
    cvar90 = mean(sort(reg, decreasing = TRUE)[seq_len(k)]),
    p90_regret = as.double(stats::quantile(reg, 0.90, type = 7, names = FALSE)),
    zero_regret_rate = mean(reg <= 1e-15),
    selection_counts = setNames(as.integer(cnt), AG_V1_GROUPS)
  )
}

ag_global_full_train_rank <- function(dat) {
  st <- ag_global_group_stats(dat$parent, dat$group_idx, dat$regret, dat$weight, seq_along(dat$parent))
  if (length(st$rank) != length(AG_V1_GROUPS)) stop("full TRAIN GLOBAL ranking lacks supported groups", call. = FALSE)
  st
}
