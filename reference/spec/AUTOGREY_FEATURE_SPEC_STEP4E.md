# AutoGrey Step 4E — Frozen Meta-Feature Engine and Reliability Masks

**Feature schema:** `AG_FEAT_4E_1`  
**Date:** 2026-09-02  
**Status:** DELIVERED — waiting for user review  
**Input contract:** approved Step 4D chronology; approved Step 4B/4C gate and within-group protocol  
**Next checkpoint:** Step 4F only after approval

## 1. Purpose

Step 4E freezes one reproducible feature map for AutoGrey v1.

This is necessary because the historical expression **“the 15 AutoGrey meta-features” did not denote one invariant mapping** across the project artifacts.

Examples:

- the empirical Python package and several manuscripts used legacy `f3` as the fraction of positive first differences;
- the theory paper and current R application used `f3` as linearity of the 1-AGO sequence;
- legacy `f8` alternated between a linear-trend residual rule and an IQR-based rule;
- `f11` alternated between a Ljung–Box p-value and the raw Q statistic;
- the normalized-length anchor changed from 18 to 20;
- the terminal/initial growth feature changed its behavior at n=6/7.

Step 4E therefore does **not** preserve ambiguous `f1`–`f15` numbers as scientific identifiers.

The new rule is:

> **Feature identity is defined by a descriptive immutable name, an exact equation, a validity rule, and a versioned API.**

Legacy `f1`–`f15` labels remain only in a migration table.

---

## 2. Hard chronology contract

The public interface is:

```python
extract_features(D, h, M=None)
```

where:

- `D` is the development/training prefix only;
- `h` is the forecast horizon known at the decision origin;
- `M` is an optional legitimate known seasonal period.

There is deliberately **no argument** for:

- the complete series;
- the held-out target `Y`;
- a split index plus full series;
- model test losses;
- winner labels;
- oracle losses.

This is an engineering control against the old leakage path in which `extract_features(full_series)` was called before scoring the held-out tail.

The Step 4D assertion remains:

\[
\max(\text{feature index used}) \le t.
\]

---

## 3. Frozen output object

`AG_FEAT_4E_1` returns:

```text
version
names[23]
values[23]
valid_mask[23]
reason_codes[23]
n
h
M
train_hash
feature_hash
```

Every numeric value is finite.

When a feature is mathematically unavailable:

```text
values[i]      = 0.0
valid_mask[i]  = False
reason_codes[i]= explicit reason
```

The `0.0` is only a transport placeholder. It is **not** interpreted as the feature’s scientific value when the mask is false.

No statistical imputation, centering, scaling, winsorization, or learned transformation is performed by Step 4E.

Any such preprocessing in Step 4F must be fitted using `META_TRAIN` only.

---

## 4. Frozen feature library

The library has **23 values**:

- 11 general small-sample time-series features;
- 10 grey/mechanism-aligned features;
- 2 task features.

This count is a protocol decision, not a claim that every feature will prove predictive.

### F01 — `trend_r2`

OLS \(R^2\) of the raw development series on a linear time trend:

\[
D_t=\beta_0+\beta_1t+\varepsilon_t.
\]

If the raw variance is negligible, the feature is masked rather than calling a constant series a perfect or zero trend.

**Role:** separates approximately linear/trend-dominated series from strongly nonlinear shapes.

---

### F02 — `quadratic_gain`

\[
\max\left(0,R^2_{\rm quad}-R^2_{\rm lin}\right),
\]

where the quadratic design is \([1,t,t^2]\).

Requires `n>=5` and a valid rank-three quadratic fit.

**Role:** signal for continuous polynomial/time-forcing mechanisms.

---

### F03 — `up_step_fraction`

\[
\frac{1}{n-1}\sum_{t=2}^{n}\mathbf 1(D_t>D_{t-1}).
\]

The deliberately descriptive name avoids calling a purely increasing-direction statistic “monotonicity” in a way that would mischaracterize monotone decline.

**Role:** preserves the empirical Python/manuscript information formerly called `f3`.

---

### F04 — `curvature_sign`

\[
\operatorname{sign}\left(\operatorname{mean}(\Delta^2D)\right).
\]

Values are `-1`, `0`, or `+1`.

**Role:** coarse acceleration/saturation direction.

---

### F05 — `cv_abs`

\[
\frac{s_D}{|\bar D|}.
\]

The feature is masked when the mean level is too close to zero.

The absolute denominator is frozen to prevent negative-mean series from turning a magnitude feature negative.

---

### F06 — `range_rel`

\[
\frac{\max D-\min D}{|\bar D|}.
\]

Masked when the mean level is too close to zero.

---

### F07 — `smoothness`

\[
\operatorname{clip}\left(
1-\frac{\operatorname{Var}(\Delta D)}
        {\operatorname{Var}(D)},
-1,1
\right).
\]

For a constant series, the documented boundary value is `1`.

This is one of the few boundary defaults treated as a genuine value rather than an imputation: a constant sequence is maximally smooth under the intended interpretation.

---

### F08 — `outlier_fraction_tukey`

Using linearly interpolated quartiles,

\[
IQR=Q_3-Q_1,
\]

the feature is the fraction of observations outside

\[
[Q_1-1.5IQR,\;Q_3+1.5IQR].
\]

This replaces two incompatible legacy `f8` definitions.

It is intentionally named `tukey` so the rule cannot later be confused with the old residual-\(2SE\) feature.

---

### F09 — `acf1`

The frozen global-mean lag-1 autocorrelation functional is

\[
\hat\rho_1=
\frac{
\sum_{t=2}^{n}(D_t-\bar D)(D_{t-1}-\bar D)
}{
\sum_{t=1}^{n}(D_t-\bar D)^2
}.
\]

Masked when the denominator is degenerate.

This resolves the finite-sample difference between the empirical Python implementation and `cor()`-style pairwise formulas in the R application.

---

### F10 — `acf2`

The same global-mean formula at lag 2.

The raw value is retained.

The old `sign(rho2)` is retired because it deterministically throws away magnitude information.

---

### F11 — `diff_skewness`

For first differences \(d_t=\Delta D_t\),

\[
\frac{
E[(d-\bar d)^3]
}{
E[(d-\bar d)^2]^{3/2}
}.
\]

The exact central-moment convention is frozen.

Requires at least four first differences and non-negligible difference variance.

---

## 5. Grey-native / mechanism-aligned features

### F12 — `ago_linearity_r2`

OLS \(R^2\) of ordinary 1-AGO,

\[
D^{(1)}_t=\sum_{i=1}^{t}D_i,
\]

against time.

This preserves the theory/current-R meaning that previously collided with empirical `f3`.

So Step 4E explicitly keeps **both**:

- raw rising-step fraction (`F03`);
- AGO linearity (`F12`).

---

### F13 — `class_ratio_pass_rate`

For strictly positive \(D\),

\[
\lambda_t=\frac{D_{t-1}}{D_t},
\]

and the classical admissible interval is

\[
e^{-2/(n+1)}
<
\lambda_t
<
e^{2/(n+1)}.
\]

The feature is the fraction of adjacent ratios satisfying that interval.

The uploaded fractional-grey source reproduces the well-known n=6 interval approximately as

\[
(0.7515,1.3307),
\]

which is also encoded as a regression test.

Per Step 4B, this is a **soft feature**, not a hard exclusion criterion.

---

### F14 — `class_ratio_max_log_violation`

Define the log-space bound

\[
b_n=\frac{2}{n+1}.
\]

Then

\[
v_{\max}
=
\max_t
\max\left(0,\;|\log\lambda_t|-b_n\right).
\]

This supplies a continuous severity measure that the binary/fractional pass rate does not.

It is an AutoGrey feature design based on the class-ratio source, not a claimed published formula.

---

### F15 — `mean_log_growth`

For strictly positive data,

\[
g_t^{\log}=\log\frac{D_t}{D_{t-1}},
\]

and

\[
F15=\operatorname{mean}(g_t^{\log}).
\]

This is scale invariant and avoids division by an individual opening observation.

---

### F16 — `log_growth_delta`

For `n>=7`,

\[
F16=
\operatorname{mean}(g^{\log}_{\rm last\,3})
-
\operatorname{mean}(g^{\log}_{\rm first\,3}).
\]

At n=7 the two 3-growth windows are disjoint.

Negative values indicate decelerating log growth; positive values indicate acceleration.

This replaces the unstable legacy growth-acceleration/saturation ratios.

---

### F17 — `recent_slope_shift`

Let \(\beta_{\rm full}\) be the OLS slope on all `D` and \(\beta_{\rm recent}\) the slope on the last four observations using their original time indices.

\[
F17
=
(\beta_{\rm recent}-\beta_{\rm full})
\frac{n}{\operatorname{mean}|D|}.
\]

This is an AutoGrey design intended to expose recent regime change relevant to the rolling/update group.

It uses no future values.

---

### F18 — `wbo_distortion`

For the registered first-order average weakening buffer operator,

\[
D^{WBO}_k
=
\frac{1}{n-k+1}
\sum_{i=k}^{n}D_i,
\]

define

\[
F18=
\frac{
\operatorname{mean}|D^{WBO}-D|
}{
\operatorname{mean}|D|
}.
\]

The WBO itself is source-backed; this normalized distortion statistic is an AutoGrey feature design.

It is recomputed from the current development prefix only.

---

### F19 — `gm_background_sensitivity`

Fit the canonical continuous GM on `D` using

\[
\alpha\in\{0.25,0.50,0.75\}.
\]

Produce an h-step training-time landmark forecast from each fit.

For each horizon step, compute the spread between the three forecasts, and take the maximum spread normalized by the historical absolute level:

\[
F19
=
\frac{
\max_j
[
\max_{\alpha}\hat y_{\alpha,j}
-
\min_{\alpha}\hat y_{\alpha,j}
]
}{
\operatorname{mean}|D|
}.
\]

This is a cheap **landmark feature**.

Wen et al. (2000) motivates background-value sensitivity, but this exact statistic is an AutoGrey design.

If any of the three landmark fits is invalid, the feature is masked. There is no substitute model.

---

### F20 — `gm_residual_acf1`

Fit the canonical GM with \(\alpha=0.5\) on `D`.

Use residuals for observations 2..n and compute the frozen global-mean lag-1 autocorrelation.

The first observation is not included because its restored value is mechanically tied to the initial condition.

**Role:** cheap residual-persistence signal relevant to Grey–Markov residual dynamics.

No Markov states are fitted inside the feature extractor.

---

### F21 — `seasonal_factor_amplitude`

This feature exists only when a legitimate known period \(M\ge2\) is supplied.

Using development data only, for each phase \(s\),

\[
f_s=
\frac{\bar D_s}{\bar D},
\]

where \(\bar D_s\) is the phase-specific mean and \(\bar D\) is the overall mean.

Then

\[
F21=\max_s f_s-\min_s f_s.
\]

This uses the audited SGM seasonal-factor convention.

It requires at least two development observations per phase and finite positive factors.

If `M` is missing, the feature is masked. The period is **never inferred by peeking into the held-out target**.

---

## 6. Task features

### F22 — `log_n`

\[
F22=\log(n).
\]

This replaces legacy normalized length.

There is no arbitrary upper anchor such as 18 or 20 and no clipping.

---

### F23 — `horizon_ratio`

\[
F23=\frac{h}{n}.
\]

This makes the selector explicitly horizon-aware while still using only information available at decision time.

---

## 7. Retired legacy features / transforms

### Legacy `f11` — Ljung–Box Q1

Retired as a selector coordinate.

At lag 1,

\[
Q_1=
\frac{n(n+2)}{n-1}\hat\rho_1^2.
\]

Once `n` and `acf1` are available, Q1 is an exact deterministic transform and contributes no independent coordinate.

It may still be reported diagnostically if desired, but it is not part of `AG_FEAT_4E_1`.

### Legacy `f13` — normalized length

Retired.

Historical files used different upper anchors (18 and 20), and clipping further changed its meaning.

`log_n` is used instead.

### Legacy `f14` / `f15`

Retired.

The old features divide by an initial growth value or average initial growth. This becomes unstable when the opening growth is near zero, depends on arbitrary epsilon guards, and changed definition around n=6/7.

They are replaced by `mean_log_growth` and `log_growth_delta`.

### Legacy `f10 = sign(rho2)`

Retired as a representation.

Raw `acf2` contains the sign plus magnitude.

---

## 8. Reliability mask rules

Masked features remain in the fixed schema but are not assigned fabricated values.

Primary reason codes include:

- `ZERO_OR_NEARZERO_VARIANCE`
- `N_LT_5`
- `QUADRATIC_FIT_UNDEFINED`
- `MEAN_NEAR_ZERO`
- `ACF_VARIANCE_UNDEFINED`
- `FEWER_THAN_4_DIFFERENCES`
- `DIFF_VARIANCE_UNDEFINED`
- `AGO_VARIANCE_UNDEFINED`
- `REQUIRES_STRICT_POSITIVITY`
- `N_LT_7`
- `SLOPE_UNDEFINED`
- `LEVEL_SCALE_UNDEFINED`
- `GM_LANDMARK_FAIL`
- `GM_RESIDUAL_VARIANCE_UNDEFINED`
- `SEASONAL_METADATA_MISSING`
- `SEASONAL_FACTOR_UNAVAILABLE`
- `NUMERIC_UNDEFINED`

`CONSTANT_BOUNDARY_VALUE` is a **valid** state used for `smoothness=1`; it is not an imputation code.

---

## 9. Step 4F preprocessing rule

Step 4E freezes raw feature computation only.

Step 4F may compare preprocessing choices, but any learned transformation must obey:

```text
fit imputer/scaler on META_TRAIN only
apply unchanged to META_CAL
apply unchanged to META_TEST
apply unchanged to REAL_BENCH
```

No preprocessing statistic may be fitted on:

- `META_CAL` for primary model tuning;
- `META_TEST`;
- `REAL_BENCH`.

Validity masks are generated at extraction time from the development prefix and may not be recomputed using future observations.

---

## 10. No label-based pruning in Step 4E

The old feature-importance and bootstrap-stability results are development-only because:

1. they arose from the superseded empirical label/evaluation pipeline;
2. some of the feature definitions themselves changed across artifacts.

Therefore Step 4E does **not** say:

- “f1/f9/f15 are the best features”;
- “only 6/15 features are stable”;
- “drop the low-importance features.”

Those statements must be re-estimated after the new labels exist.

Any empirical feature ablation/stability/importance analysis in Step 4F must occur **inside `META_TRAIN` only**, with grouping by parent series.

`META_TEST` and `REAL_BENCH` evaluate a frozen pipeline; they do not redesign it.

---

## 11. Reference implementation

Reference file:

`autogrey_features_step4e.py`

The implementation:

- uses NumPy only;
- uses least squares rather than explicit normal-equation inversion for landmark fits;
- implements the Step 4C near-zero analytic branch for the canonical GM landmark;
- has no test-target input surface;
- returns fixed-width values/masks/reason codes/hashes.

This is a protocol reference implementation, not yet the production Shiny engine.

---

## 12. Deterministic test suite

The Step 4E reference implementation currently passes **27 deterministic tests**.

Fixtures cover:

- positive linear trend;
- exponential growth;
- logistic/saturating growth;
- a late regime shift;
- a constant series;
- a quarterly seasonal series.

The tests check:

1. finite fixed-width output;
2. validity-mask behavior;
3. n=6 class-ratio bounds near `(0.7515, 1.3307)`;
4. multiplicative scale invariance;
5. constant-series boundary behavior;
6. seasonal feature availability only with legitimate `M`;
7. positivity masks;
8. recent-slope-shift direction on a regime-change fixture;
9. deterministic training and feature hashes;
10. raw-history features do not change merely because `h` changes;
11. horizon-specific task/landmark coordinates may change with `h`.

A passed test suite establishes that the implementation follows this specification on the tested cases. It is not evidence that the features are predictive of model performance.

---

## 13. Feature-map relation to the v1 algorithm space

The feature design is intended to give the selector observable information aligned to the mechanisms already frozen in Step 4A:

- SG01 continuous GM: trend, AGO geometry, background sensitivity;
- SG02 discrete polynomial: trend and short-lag persistence;
- SG03 fractional accumulation: smoothness/roughness, AGO geometry;
- SG04 Bernoulli/Verhulst: curvature and growth deceleration;
- SG05 continuous time/polynomial forcing: quadratic gain and curvature;
- SG06 conformable accumulation: accumulation/smoothness signals;
- SG07 rolling: recent slope shift;
- SG08 WBO: outlier context + WBO distortion;
- SG09 Grey–Markov: canonical-GM residual persistence;
- SG10 seasonal GM: seasonal factor amplitude.

This is a design rationale, **not a proof that these features separate oracle classes**.

That empirical question belongs to Step 4F/4G.

---

## 14. Historical evidence reconciliation

The old empirical `meta_features.py` used the 15-element mapping with:

- empirical `f3 = positive-step fraction`;
- residual-2SE `f8`;
- raw `Q1`;
- normalized length with anchor 18;
- overlapping n=6 saturation windows.

The current R application/theory lineage changed several of those meanings, including:

- `f3 = AGO linearity`;
- IQR-style `f8`;
- anchor 20 in the R application;
- disjoint n>=7 saturation windows.

Step 4E treats that as a versioning failure to be corrected, not as a reason to choose one old file as automatically authoritative.

---

## 15. What Step 4E deliberately does not do

- no synthetic labels regenerated;
- no selector trained;
- no classifier/regressor chosen;
- no feature importance computed;
- no empirical feature dropped because of an old importance score;
- no abstention threshold calibrated;
- no benchmark result generated;
- no Shiny integration;
- no manuscript numerical claim changed.

---

## 16. Approval checkpoint

If Step 4E is approved, Step 4F will begin with the frozen `AG_FEAT_4E_1` output only.

Step 4F will decide, using `META_TRAIN` only:

- preprocessing of masked features;
- candidate selector architectures;
- grouped hyperparameter tuning;
- whether hard-classification, loss-vector/regret learning, or both should be compared;
- nested feature stability/redundancy/ablation;
- probability calibration and abstention on `META_CAL`.

`META_TEST` remains unopened until the full Step 4F selector/calibration pipeline is frozen.
