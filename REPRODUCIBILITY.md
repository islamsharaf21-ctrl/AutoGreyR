# AutoGreyR Reproducibility Contract

## Scientific boundary

Step 7 is a reproduction layer for the already-frozen AutoGrey experiment. It does not authorize model-family changes, new grids, new features, new eligibility rules, selector retuning, target-dependent selection, refusal fallback, alternate regret definitions, or alternate bootstrap designs.

## Chronology

1. TRAIN structural actions/labels are frozen.
2. V1 selector and GLOBAL comparator are reproduced from TRAIN only.
3. REALBENCH2 reserved series are processed target-free; eligibility, configurations, forecasts, and choices are frozen.
4. Held-out targets are opened only after commitment verification.
5. All eligible MASE values and selected regrets are computed with the frozen forecasts.
6. Paired parent-level inference uses NumPy `default_rng(46073)` / PCG64 for exactly 4,000 replicates.

The Step 7F reproduction is an audit of the original Step5F opening, not a second blind experiment.

## Cross-language numerical semantics

Controlled fixtures established native-R parity for the structural engine. A full REALBENCH2 census found platform-dependent least-squares differences concentrated in SG02_DISCRETE_POLY and SG05_CONT_TIME_POLY. The final contract therefore distinguishes:

- **canonical byte-exact reference:** frozen Linux/Python numerical outputs;
- **Windows qualified reproduction:** exact discrete decisions plus the fixed R8 numerical bounds for SG02/SG05;
- **final scoring:** canonical frozen forecast pack, preventing platform approximations from changing the estimand.

The R8 platform bounds were frozen using target-free forecasts before Step7F scoring and may not be widened after observing outcomes.

## Random forest semantics

The canonical V1 estimator is scikit-learn 1.8.0 `RandomForestRegressor` with 500 trees, seed 62291, `max_features='sqrt'`, bootstrap enabled, and the frozen sample-weight behavior. `ranger::case.weights` was rejected as a canonical substitute because it changes bootstrap sampling semantics.

## Bootstrap semantics

The final paired bootstrap uses the canonical NumPy PCG64 stream, not R Mersenne-Twister. The verifier checks the original 4,000-row bootstrap CSV SHA-256 and the first 12 complete resampling-index hashes, then repeats the bootstrap in a fresh process.

## Lockfile policy

The committed `renv.lock` is the immutable environment source of truth. `scripts/reproduce_all.R` first runs `scripts/initialize_renv.R`, which activates the project environment, restores packages from the committed lock, verifies R 4.6.1 and the required package versions, verifies the lockfile SHA-256, and fails if the lockfile changes. Normal public reproduction never regenerates or snapshots `renv.lock`.

## Interpretation boundary

The verified conclusion is comparative and protocol-specific: the frozen V1 AutoGrey selector has lower mean and CVaR90 regret than the frozen GLOBAL_RANK_V2 comparator on REALBENCH2, with both paired 95% bootstrap intervals below zero. No universal forecasting-superiority claim is licensed by this package.
