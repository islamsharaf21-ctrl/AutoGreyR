# AutoGrey Step 7B11 — frozen structural eligibility / collision portfolio layer.
# Scientific contract source: AG_ENGINE_4FB_1R1 run_portfolio().
# This file does NOT implement selector features, target scoring, or reference models.

AG_ENGINE_VERSION <- "AG_ENGINE_4FB_1R1"
AG_GROUP_ORDER <- c(
  "SG01_CONT_GM",
  "SG02_DISCRETE_POLY",
  "SG03_FRAC_LINEAR",
  "SG04_BERNOULLI",
  "SG05_CONT_TIME_POLY",
  "SG06_CONFORMABLE",
  "SG07_ROLLING",
  "SG08_WBO",
  "SG09_GREY_MARKOV",
  "SG10_SEASONAL"
)
AG_COLLISION_TOL <- 1e-3
AG_COLLISION_SENSITIVITY <- c(1e-4, 1e-2)

ag_normalized_forecast_distance <- function(f, g, D) {
  f <- as.numeric(f); g <- as.numeric(g); D <- as.numeric(D)
  if (length(f) != length(g) || any(!is.finite(f)) || any(!is.finite(g))) {
    ag_stop("COLLISION_INPUT_INVALID")
  }
  denom <- max(mean(abs(D)), 1e-12)
  as.numeric(max(abs(f - g)) / denom)
}

ag_select_group <- function(x, h, group_id, M = NULL) {
  switch(
    as.character(group_id),
    SG01_CONT_GM = ag_select_sg01(x, h, M),
    SG02_DISCRETE_POLY = ag_select_sg02(x, h, M),
    SG03_FRAC_LINEAR = ag_select_sg03(x, h, M),
    SG04_BERNOULLI = ag_select_sg04(x, h, M),
    SG05_CONT_TIME_POLY = ag_select_sg05(x, h, M),
    SG06_CONFORMABLE = ag_select_sg06(x, h, M),
    SG07_ROLLING = ag_select_sg07(x, h, M),
    SG08_WBO = ag_select_sg08(x, h, M),
    SG09_GREY_MARKOV = ag_select_sg09(x, h, M),
    SG10_SEASONAL = ag_select_sg10(x, h, M),
    ag_stop("GROUP_UNKNOWN", as.character(group_id))
  )
}

ag_run_structural_portfolio <- function(D, h, M = NULL) {
  x <- ag_as_series(D)
  h <- as.integer(h)
  if (h < 1L) ag_stop("H_INVALID")
  if (!is.null(M)) M <- as.integer(M)

  results <- setNames(vector("list", length(AG_GROUP_ORDER)), AG_GROUP_ORDER)
  for (g in AG_GROUP_ORDER) results[[g]] <- ag_select_group(x, h, g, M)

  retained <- character(0)
  collisions <- list()
  for (g in AG_GROUP_ORDER) {
    r <- results[[g]]
    if (!isTRUE(r$eligible) || is.null(r$forecast)) next
    collided <- FALSE
    for (keep in retained) {
      d <- ag_normalized_forecast_distance(r$forecast, results[[keep]]$forecast, x)
      if (d <= AG_COLLISION_TOL) {
        collisions[[length(collisions) + 1L]] <- list(
          owner = keep,
          removed = g,
          d_inf = as.numeric(d),
          at_1e4 = isTRUE(d <= AG_COLLISION_SENSITIVITY[1L]),
          at_1e2 = isTRUE(d <= AG_COLLISION_SENSITIVITY[2L])
        )
        collided <- TRUE
        break
      }
    }
    if (!collided) retained <- c(retained, g)
  }

  pre <- AG_GROUP_ORDER[vapply(results, function(z) isTRUE(z$eligible), logical(1))]
  list(
    engine_version = AG_ENGINE_VERSION,
    n = as.integer(length(x)),
    h = as.integer(h),
    M = M,
    group_results = results,
    distinct_groups = retained,
    collisions = collisions,
    diagnostics = list(
      eligible_pre_dedup = pre,
      eligible_post_dedup = retained,
      collision_tol = AG_COLLISION_TOL
    )
  )
}

# Frozen Step5F pretarget actionability decision applied after target-free
# structural eligibility/collision resolution. This helper never opens targets.
ag_structural_actionability <- function(portfolio) {
  eligible <- as.character(portfolio$distinct_groups)
  if (!length(eligible)) {
    return(list(actionable = FALSE, eligible_groups = character(0),
                reason = "NO_ELIGIBLE_STRUCTURAL_GROUP"))
  }
  list(actionable = TRUE, eligible_groups = eligible, reason = NULL)
}
