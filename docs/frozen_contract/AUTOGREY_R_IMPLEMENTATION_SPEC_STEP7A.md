# AutoGrey Step 7A — Frozen R Reproduction Implementation Specification

**Status:** STEP 7A SPECIFICATION COMPLETE — NO MODEL CODE WRITTEN  
**Date:** 2026-09-06  
**Scientific state:** FROZEN at Step 6F / canonical experiment Step 5F  
**Next permitted checkpoint after explicit user continuation:** Step 7B — deterministic grey-engine implementation and fixtures.

## 1. Purpose

This document is the implementation contract for the R reproduction layer. It translates the frozen AutoGrey v2 scientific design into R engineering requirements. It does **not** reopen model design, candidate selection, eligibility rules, tuning grids, features, training labels, selector architecture, evaluation metrics, bootstrap design, or final conclusions.

The R layer must reproduce the canonical Step 5F experiment; it must not create a new experiment under the same version label.

## 2. Verified source chain

### 2.1 Step 6F handoff received

- Uploaded handoff core: `AUTOGREY_R_REPRODUCTION_HANDOFF_CORE_STEP6F.zip`
- Verified SHA-256: `3f68a5c65c7c85377b52322cfe08fb0c6426bc655a805d46786026e46b211050`
- The core contains the Step 6F R handoff, audit, tracker, source-of-truth registry, manuscript/supporting information, Step 5F final package and manifest, and bibliography.

### 2.2 Exact raw reservation bundle verified

Canonical Step 6F/5F requirement:

- Required logical bundle: `AUTOGREY_REALBENCH2_RAW_RESERVATION_BUNDLE_STEP5B(1).zip`
- SHA-256: `85aac5e92b5d6b0db2299d319d096a5a4b274369cbfeabf7c79e2dc706b0f4f9`

The saved workspace copy named `AUTOGREY_REALBENCH2_RAW_RESERVATION_BUNDLE_STEP5B(1)(1).zip` has the **same byte-level SHA-256** and size `38,466,292` bytes, therefore it is the same frozen object despite the duplicate-safe filename suffix.

Verified inner raw objects:

| Raw object | SHA-256 | Bytes |
|---|---|---:|
| M4 monthly | `473aa4...` | 28,235,874 |
| M4 quarterly | `0a41bd...` | 7,031,886 |
| M4 yearly | `4a260d...` | 2,785,010 |
| Tourism monthly | `6e434a...` | 199,791 |
| Tourism quarterly | `fa16da...` | 93,833 |
| Tourism yearly | `20238d...` | 36,749 |

The full hashes remain authoritative in the Step 5F raw verification artifact and must be checked programmatically in the R test `test-raw-hashes.R` before any target values are parsed.

### 2.3 Reservation chronology preserved

The raw reservation ledger states that before reservation freeze:

- target values were not parsed;
- series values were not parsed;
- series lengths were not parsed;
- features were not computed;
- eligibility was not computed;
- forecasts/performance were not computed.

Frozen reservation facts:

- parents reserved: **2,511**;
- unique parents: **2,511**;
- horizon set: **{1, 3, 5}**;
- horizon counts: **860 / 818 / 833**;
- sampling seed: **88127**;
- horizon-assignment seed: **51431**;
- M4: deterministic hash sample of 400 parents per frequency;
- Tourism: all parents.

The R workflow must preserve the same pre-target chronology.

## 3. Canonical Step 5F scientific outputs to reproduce

These values are acceptance targets, not tunable goals.

- Primary selector: `V1_STYLE_RF_REGRET`
- Comparator: `GLOBAL_RANK_V2`
- Reserved parents: **2,511**
- Actionable parents: **2,496**
- Refusals: **15**
- Refusal reason: `NO_ELIGIBLE_STRUCTURAL_GROUP`
- Mean regret, V1: **1.317290834344165**
- Mean regret, GLOBAL: **1.928979412108397**
- Mean delta (V1 − GLOBAL): **−0.611688577764232**
- 95% paired parent-cluster bootstrap CI: **[−0.741487125525563, −0.493958929992061]**
- CVaR90, V1: **8.297652381285300**
- CVaR90, GLOBAL: **11.127078832815650**
- CVaR90 delta: **−2.829426451530351**
- 95% bootstrap CI: **[−3.943413480648712, −1.856774313430196]**
- Bootstrap replications: **4,000**
- Bootstrap seed: **46073**
- Final gate: **PASS**

The Step 6F handoff requires final numerical equality to the frozen acceptance values to tolerance `< 1e-10` where specified.

## 4. Frozen scientific invariants — MUST NOT CHANGE

1. Exactly ten structural groups, in frozen canonical order:
   - `SG01_CONT_GM`
   - `SG02_DISCRETE_POLY`
   - `SG03_FGM`
   - `SG04_NGBM`
   - `SG05_TIME_POWER`
   - `SG06_CONFORMABLE`
   - `SG07_ROLLING_GM`
   - `SG08_AVERAGE_GM`
   - `SG09_GREY_MARKOV`
   - `SG10_SEASONAL_GM`
2. Final selector remains `V1_STYLE_RF_REGRET`.
3. Comparator remains `GLOBAL_RANK_V2`.
4. Source identity is not a selector feature.
5. No horizon-5 ban.
6. No post-hoc clipping of forecasts/losses to rescue invalid states.
7. No post-hoc structural-group removal.
8. Refusals remain refusals; no fallback/replacement model is inserted.
9. Confidence remains `NOT_APPLICABLE_ARCHITECTURALLY` where frozen as such.
10. CVaR90 is the arithmetic mean of the worst `ceiling(0.10*N)` parent regrets.
11. Bootstrap is paired parent-cluster bootstrap, 4,000 replications, seed 46073.
12. Final superiority requires both frozen confirmatory CI gates to pass.
13. Any scientific modification must be a **new AutoGrey version/study**, never a silent R-port change.

## 5. Frozen grey-engine implementation contract

Canonical Python engine version: `AG_ENGINE_4FB_1R1`  
Canonical engine SHA-256: `01c745d8a627748f82916a576efbee231a2f87d66c314d57947dbede67974`

Global implementation rules:

- fitting uses numerically stable least-squares (`lstsq` semantics; no matrix inverse shortcut);
- no silent model fallback;
- no invalid-state floor/clipping workaround;
- three common inner origins are used for structural-group tuning;
- one training-only configuration is selected per group;
- candidates within the 5% inner-loss band are resolved by the frozen simplicity rule;
- target values are not inputs to structural selection;
- forecast collisions are resolved before target scoring;
- reference forecasts are non-selectable;
- condition failure threshold: `1e12`;
- collision tolerance: `1e-3`;
- collision sensitivity values retained for diagnostics: `1e-4` and `1e-2`;
- final-refit failure makes the group ineligible; do not fall back to the second-best configuration.

### 5.1 Frozen grids / principal group rules

- **SG01 continuous GM:** background coefficient alpha `0, 0.05, ..., 1`; canonical alpha 0.5 wins within the 5% band under the frozen simplicity priority.
- **SG02 discrete polynomial:** all admissible subsets/degrees under frozen `Nmax=min(4,m_first-4)`, maximum 16, with fewer-term simplicity priority.
- **SG03 fractional GM:** `r={0.1,...,0.9}` only; `r=1` belongs to SG01; no `r>1` expansion.
- **SG04 NGBM:** gamma grid `{-1,-0.75,-0.5,-0.25,0.25,0.5,0.75,1.25,1.5,1.75,2,2.25,2.5,2.75,3}`; gamma 0 and 1 excluded; gamma 2 is Verhulst-preferred inside the frozen band; preserve kappa/validity gates.
- **SG05 time-power:** alpha `{0.25,0.5,0.75,1.25,1.5,1.75,2,2.25,2.5,2.75,3}` plus frozen FOTP orders; alpha 1 duplicate excluded; simpler parameterization wins inside band.
- **SG06 conformable:** alpha `{0,0.1,...,0.9,1.1,...,2.0}`; alpha 1 duplicate excluded; source-faithful CFA/CFD implementation only.
- **SG07 rolling GM:** window `w=4`, recursive refit, no shrinkage.
- **SG08 average GM:** frozen WBO+GM construction, recomputed on each prefix; preserve endpoint/original-scale convention.
- **SG09 Grey-Markov:** states 2–4 × frozen EQW/EQT construction; preserve transition-support rules; no GM fallback; unresolved modal tie = candidate failure.
- **SG10 seasonal GM:** requires known `M>=2`; deterministic SGM; at least two cycles/phase; all-one seasonal-factor reduction is excluded under frozen tolerance.

The full source code and Step 4B/4C registry sheets are normative if this summary and implementation detail ever appear ambiguous.

## 6. Frozen feature-engine contract

Canonical feature engine version: `AG_FEAT_4E_1`  
Canonical feature-engine SHA-256: `bbbd645cffae6462eb50cbb9ff5fb902912e6204df1ab5a9a316428d58b7a113`

Exactly 23 feature values, in frozen order:

1. `trend_r2`
2. `quadratic_gain`
3. `up_step_fraction`
4. `curvature_sign`
5. `cv_abs`
6. `range_rel`
7. `smoothness`
8. `outlier_fraction_tukey`
9. `acf1`
10. `acf2`
11. `diff_skewness`
12. `ago_linearity_r2`
13. `class_ratio_pass_rate`
14. `class_ratio_max_log_violation`
15. `mean_log_growth`
16. `log_growth_delta`
17. `recent_slope_shift`
18. `wbo_distortion`
19. `gm_background_sensitivity`
20. `gm_residual_acf1`
21. `seasonal_factor_amplitude`
22. `log_n`
23. `horizon_ratio`

Rules:

- inputs are training prefix `D`, horizon `h`, and frozen frequency/seasonality metadata `M`; target values are not used;
- each feature has a validity bit;
- an invalid/unavailable feature stores value 0 and validity `FALSE` at the 4E layer;
- no imputation occurs in Step 4E;
- imputation for selector fitting is group/fold-specific and fitted only from the relevant training records;
- feature vectors and masks are fixed width and frozen order;
- source identity is excluded.

## 7. Frozen V1 selector contract

Canonical Step 5D-B-R2 selector SHA-256: `a5f6e6914809bcde3667c96165984a218595c92c4cbf1d98ff4b23de50be2d23`

### 7.1 Inputs

Per parent/action, V1 receives exactly **56 inputs**:

- 23 feature values;
- 23 corresponding validity bits;
- 10 structural-group eligibility bits.

Reason-code strings and source identity are not model inputs.

### 7.2 Architecture

- ten separate random-forest regressors, one per structural group;
- target for group `g`: frozen regret transformation `log1p(max(0, L_g - L_oracle_eligible))`;
- 500 trees per V1 group regressor;
- `criterion = squared_error`;
- `max_depth = None`;
- `min_samples_split = 2`;
- `min_samples_leaf = 0.01` (scikit-learn fractional semantics must be reproduced, not approximately reinterpreted);
- `max_features = sqrt`;
- `bootstrap = TRUE`;
- no OOB scoring;
- no pruning (`ccp_alpha=0`);
- full bootstrap sample (`max_samples=None`);
- random seed **62291**;
- final deterministic action tie-break: lowest predicted score, then frozen group index.

### 7.3 Preprocessing

For each group/fold/final fit independently:

- replace invalid/non-finite feature values using the median estimated from that training subset only;
- if a column has no finite training values, use 0;
- no feature scaling;
- append masks and eligibility bits after constructing the feature values;
- preserve frozen parent weighting.

### 7.4 Cross-language RF warning

The canonical selector was produced by scikit-learn 1.8.0. `ranger` is locked in Step 7A as the **first native-R implementation candidate**, not as permission to alter the selector. Random-forest tree growth, bootstrap RNG, split tie-breaking, `min_samples_leaf` semantics, missing-value handling, and floating-point ordering can differ across libraries.

Therefore Step 7D must establish deterministic fixture parity before any full-run claim. If `ranger` differs, diagnose and reproduce the canonical implementation behavior; do **not** retune the forest or change the frozen selector.

## 8. Frozen final scoring contract

Canonical Python scorer SHA-256: `c5a6d8...` (full hash is stored in Step 6F/5F manifests and must be copied verbatim into `expected_hashes.json`).

For each actionable parent:

1. open target only after the pre-target choice object and all opening-lock hashes verify;
2. calculate each eligible structural group's frozen MASE using the frozen training-prefix scale;
3. eligible oracle loss = minimum loss across distinct eligible groups;
4. selector regret = `max(0, selected_loss - eligible_oracle_loss)`;
5. GLOBAL comparator uses its frozen train-derived group ranking and same eligible action set;
6. refusals are omitted from actionable scoring but retained in counts and decisions; no replacements.

### 8.1 MASE

- no epsilon is inserted into the MASE denominator to change frozen eligibility/loss behavior;
- seasonal lag is `M` when known/eligible as frozen, otherwise 1 under the canonical rules;
- outer evaluation uses training prefix `D` only for scaling.

### 8.2 CVaR90

For `N` actionable parent regrets:

- sort parent regrets descending;
- `k = ceiling(0.10*N)`;
- CVaR90 = arithmetic mean of the worst `k` values.

### 8.3 Paired parent-cluster bootstrap

- replications: 4,000;
- seed: 46073;
- resample parent indices with replacement, sample size `N`;
- compute paired mean-regret delta and paired CVaR90 delta per replicate;
- 95% percentile interval uses NumPy `quantile(..., method='linear')` semantics; R `quantile(type=7)` is mathematically corresponding for a fixed replicate vector, but the **resampling RNG sequence must also match** for exact canonical reproduction.

The canonical Python scorer uses NumPy `default_rng(46073)` (PCG64 family). Base-R Mersenne-Twister with the same integer seed is **not** equivalent and must not be presented as exact reproduction. Step 7D/7F must implement or otherwise verify a NumPy-compatible resampling sequence before asserting `<1e-10` CI equality.

## 9. Exact provenance hashes that must be gated before computation

At minimum the R assertions layer must verify the frozen hashes for:

- raw reservation bundle: `85aac5e92b5d6b0db2299d319d096a5a4b274369cbfeabf7c79e2dc706b0f4f9`;
- frozen reservation IDs: `a2d50...`;
- Step 5D-A action table: `5e943...`;
- Step 5D-A TRAIN labels: `77e202...`;
- Step 4F-B R1 grey engine: `01c745d8a627748f82916a576efbee231a2f87d66c314d57947dbede67974`;
- Step 4E feature engine: `bbbd645cffae6462eb50cbb9ff5fb902912e6204df1ab5a9a316428d58b7a113`;
- Step 5D-B-R2 selector code: `a5f6e6914809bcde3667c96165984a218595c92c4cbf1d98ff4b23de50be2d23`;
- Step 5E LOCKTEST result: `59d6...`;
- Step 5F final result: `8126fc...`;
- Step 5F decisions: `f62d93...`;
- Step 5F bootstrap output: `b78899...`;
- Step 5F pre-target object: `9a5c9...`;
- Step 5F opening lock: `5b1e9...`;
- Step 5F final package: `fc4e26204da5da807a922835b55012976d401894e4db2c231a4a9a7bb11c5242`.

Abbreviated hashes in this prose are **not** implementation values. The R repository must import the complete values from the canonical Step 5F manifest/raw-verification artifacts into `inst/extdata/expected_hashes.json` before tests are enabled.

## 10. Required repository architecture (frozen handoff)

```text
AutoGreyR/
  README.md
  LICENSE
  CITATION.cff
  DESCRIPTION
  renv.lock
  R/
    01_utils.R
    02_hash_gate.R
    03_data_io.R
    04_mase.R
    05_grey_common.R
    06_structural_groups.R
    07_features.R
    08_eligibility.R
    09_collisions.R
    10_v1_preprocess.R
    11_v1_selector.R
    12_global_rank.R
    13_regret.R
    14_bootstrap.R
    15_assertions.R
  scripts/
    reproduce_train_r2.R
    reproduce_realbench2_pretarget.R
    reproduce_realbench2_final.R
    reproduce_all.R
  tests/testthat/
    test-grey-model-fixtures.R
    test-feature-fixtures.R
    test-eligibility.R
    test-group-collisions.R
    test-v1-selector.R
    test-regret.R
    test-cvar90.R
    test-bootstrap-seed.R
    test-raw-hashes.R
    test-step5f-final.R
  inst/extdata/
    expected_step5f_results.json
    expected_hashes.json
  manuscript/
    figures/
    tables/
```

Step 7A creates **none of the model-code files** above. This tree is only the implementation target for later checkpoints.

## 11. Dependency policy

The declared Step 7A R baseline is:

- R 4.6.1;
- renv 1.2.3;
- ranger 0.18.0;
- jsonlite 2.0.0;
- digest 0.6.39;
- testthat 3.3.2.

Direct dependencies are intentionally minimal. Base R is preferred for CSV/ZIP/I/O, linear algebra and deterministic transformations unless the canonical semantics require otherwise. Transitive dependencies must be captured by a real `renv::snapshot()` in an R-capable environment; they are not fabricated in Step 7A.

The machine-readable companion `AUTOGREY_R_DEPENDENCY_LOCK_STEP7A.json` is a **declared dependency contract**, not a generated `renv.lock`.

## 12. Step 7A acceptance / stop conditions

Step 7A is complete only if all statements below are true:

- [x] Step 6F handoff read.
- [x] Step 5F final package/manifest read.
- [x] exact raw bundle found and SHA-256 verified.
- [x] six inner raw-object hashes verified.
- [x] reservation ledger/assertions read without parsing numeric TSF target values.
- [x] frozen source chain (action table, TRAIN labels, engine, features, R2 selector, Step 5E result) hash-verified.
- [x] frozen ten-group, feature, selector, scoring and bootstrap contracts extracted.
- [x] R implementation specification written.
- [x] dependency contract written.
- [x] no grey-model R implementation written.
- [x] no feature/selector R implementation written.
- [x] no scientific design parameter changed.
- [x] no Step 7B work started.
- [ ] real `renv.lock` instantiated and verified — **deferred because this execution environment has no R installation; this is an engineering-environment task, not a scientific-design change.**

## 13. Known parity risks carried forward (not design questions)

| Risk | Level | Required treatment |
|---|---|---|
| scikit-learn RF vs native R forest tree construction/RNG | HIGH | deterministic fixture comparison first; reproduce canonical semantics; never retune science |
| NumPy PCG64 bootstrap sequence vs base-R RNG | HIGH | implement/verify NumPy-compatible index stream before exact CI claim |
| least-squares/SVD tolerance differences | MEDIUM | fixture tests against canonical engine; use stable QR/SVD and explicit tolerances |
| floating-point tie ordering | MEDIUM | frozen numeric tolerance + canonical group-index tie-break |
| JSON number serialization/hash commitments | MEDIUM | canonical byte/hex serialization fixtures before hash claims |
| TSF text/token parsing differences | MEDIUM | preserve exact target token commitments and opening chronology |

These are reproduction engineering risks. None authorizes a scientific change.

---

**STEP 7A STOP:** The next action is Step 7B only after the user explicitly says to continue.
