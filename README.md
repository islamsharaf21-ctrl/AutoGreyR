# AutoGreyR — Frozen Experiment Reproduction Release
AutoGreyR is the R-controlled reproducibility layer for the frozen AutoGrey experiment. AutoGrey treats cross-family grey-model choice as an algorithm-selection / meta-learning problem rather than proposing another single grey equation.

This repository is a **reproduction release**, not a redesign. The scientific choices were frozen before the Step 7 reproduction work: ten structural groups, eligibility/collision rules, 23 target-free features, 56 selector inputs, V1_STYLE_RF_REGRET, GLOBAL_RANK_V2, REALBENCH2 reservations, MASE/regret/CVaR90 definitions, and the 4,000-replicate paired bootstrap.

## Verified frozen result

On the locked REALBENCH2 protocol:

- actionable parents: 2,496 of 2,511 reserved;
- V1 mean regret: 1.317290834344165;
- GLOBAL mean regret: 1.9289794121083974;
- mean-regret delta (V1 - GLOBAL): -0.6116885777642325;
- 95% paired bootstrap CI: [-0.7414871255255626, -0.49395892999206054];
- V1 CVaR90: 8.297652381285300;
- GLOBAL CVaR90: 11.127078832815650;
- CVaR90 delta: -2.8294264515303507;
- 95% paired bootstrap CI: [-3.9434134806487116, -1.8567743134301962].

Both frozen inferential gates pass. V1 outperformed the frozen GLOBAL_RANK_V2 comparator on REALBENCH2 under the prespecified frozen protocol. This is not a universal claim over all forecasters or datasets.

## Canonical and qualified platforms

The frozen canonical numerical reference is Linux with Python 3.13.5 / NumPy 2.3.5 and the recorded OpenBLAS path. Windows with the same Python/NumPy versions is qualified under `AUTOGREY_STEP7E2_PLATFORM_CONTRACT_R8.json` for the numerically sensitive SG02/SG05 forecasts. All discrete eligibility, configuration, selector, and comparator decisions remain exact.

The random-forest and PCG64 portions deliberately use the frozen Python implementations. Native `ranger` and base-R RNG are **not** substituted because that would change the locked estimator or resampling stream.

## Exact release environment

Initial release parity is locked to:

- R 4.6.1
- renv 1.2.3
- jsonlite 2.0.0
- digest 0.6.39
- testthat 3.3.2
- Python 3.13.5
- NumPy 2.3.5
- SciPy 1.17.0
- scikit-learn 1.8.0

The committed `renv.lock` is the immutable environment source of truth for this release. `scripts/initialize_renv.R` restores the locked packages, verifies R 4.6.1 and the required package versions, verifies the lockfile SHA-256, and fails if the lockfile changes. Normal public reproduction does not regenerate or snapshot `renv.lock`.

## One-entry reproduction

Open `AutoGreyR.Rproj`. Set `AUTOGREY_PYTHON` to the already-verified Python 3.13.5 executable if it is not found automatically, for example on Windows:

```r
candidate <- file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Python", "Python313", "python.exe")
Sys.setenv(AUTOGREY_PYTHON = candidate)
```

Then run:

```r
source("scripts/reproduce_all.R")
```

Required final line:

```text
AUTOGREY_STEP7G_REPRODUCE_ALL: PASS
```

The script restores and verifies the committed `renv.lock`, tests the frozen fixtures, reruns TRAIN/R2, GLOBAL_RANK_V2, REALBENCH2 pretarget parity, deterministic target scoring, exact PCG64 inference, and finally audits the public release tree.

## Main entry points

- `scripts/reproduce_train_r2.R` — full V1 TRAIN/R2 + GLOBAL reproduction.
- `scripts/reproduce_realbench2_pretarget.R` — target-free REALBENCH2 R8 parity.
- `scripts/reproduce_realbench2_final.R` — frozen target scoring + PCG64 inference.
- `scripts/reproduce_all.R` — complete AutoGreyR 1.0.0 public reproduction and release audit.

See `REPRODUCIBILITY.md` for chronology, platform semantics, and interpretation boundaries.

## License and third-party data

AutoGreyR-owned software and original documentation are distributed under the MIT License in `LICENSE`.

The bundled M4 and Tourism benchmark datasets retain their upstream Creative Commons Attribution 4.0 International (CC BY 4.0) terms and are not relicensed under MIT.

See `THIRD_PARTY_NOTICES.md` for dataset attribution, Zenodo identifiers, and redistribution information.
