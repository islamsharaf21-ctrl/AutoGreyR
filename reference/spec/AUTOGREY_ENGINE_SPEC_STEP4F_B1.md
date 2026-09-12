# AutoGrey Step 4F-B1 — Canonical Executable Forecast Engine

**Engine version:** `AG_ENGINE_4FB_1`  
**Date:** 2026-09-03  
**Status:** DELIVERED — canonical reference engine frozen; no scientific labels/selectors/results yet  
**Engine SHA-256:** `3a9b7495801a22f5ab585468f819bfa56a5642f0e170b051815533e2c2066162`  
**Prerequisites:** approved Steps 4A–4F-A  
**Next checkpoint:** Step 4F-B2 — clean Step-4D label-corpus generation

## 1. Purpose

Step 4F-B1 converts the source-of-truth design into one executable reference engine.

The engine is deliberately separated from the meta-selector. Its public portfolio API is:

```python
run_portfolio(D, h, M=None)
```

There is deliberately no argument for the held-out target, winner labels, group test losses, or selector output. Gating, training-only configuration selection, refitting, forecasting, and forecast deduplication therefore finish before Step 4D opens a target.

## 2. Common group contract

Every v1 selection group must:

1. receive development data `D`;
2. build exactly the frozen Step-4C configuration set;
3. score configurations at exactly three common inner origins;
4. compute each inner MASE denominator from that origin's training prefix only;
5. reject a configuration if any common-origin result is invalid;
6. construct the 5% near-optimal band;
7. apply the group-specific simplicity rule;
8. refit one chosen configuration on all `D`;
9. return one h-step forecast or an explicit failure;
10. never fall back after a final-refit failure.

The portfolio then performs forecast collision detection before target scoring:

`d_inf(f,g|D) = max_j |f_j-g_j| / max(mean(|D|), 1e-12)`

with primary threshold `1e-3`.

## 3. Numerical estimation

Linear fits use `numpy.linalg.lstsq`. The engine does not explicitly compute `(B'B)^-1 B'Y`.

Each fit checks rank and condition number. The common hard condition threshold is `1e12`. NGBM additionally uses the Step-4C column-normalized identifiability check.

## 4. SG01 — continuous GM

Frozen background grid:

`alpha_bg = 0.00, 0.05, ..., 1.00`

with canonical midpoint `0.50`.

For `a≈0`, the engine uses the analytic response limit rather than dividing by a small `a`.

The test suite reproduces the traditional-GM forecasts printed in the Wang seasonal study.

## 5. SG02 — discrete polynomial group

Direct structure:

`x0(k) = alpha*x1(k-1) + beta0 + sum_{j in S} beta_j*k^j`.

Candidate structures are all subsets of degrees `1..Nmax`, with `Nmax=min(4,m_first-4)`. Empty set is DGM; `{1}` is NDGM.

The Wei–Xie–Yang generating example `x(k)=exp(k)+5k+10` reproduces its coefficients and seventh-point forecast.

## 6. SG03 — corrected Wu fractional accumulation model

### 6.1 Source-fidelity correction

The earlier engine used correct generalized-binomial fractional accumulation/inverse operators but treated the response as ordinary anchored GM.

For the source-reproducible fractional branch, Wu et al. estimate `a,b` from the fractional grey equation and then use an initial-condition correction:

`xhat^(r)(k+1) = c * exp(-a*k) + d`.

The B1 engine therefore:

1. computes fractional AGO;
2. estimates `a,b`;
3. estimates `c,d` from accumulated observations 2..n;
4. generates the corrected accumulated response;
5. applies the generalized-binomial inverse.

### 6.2 Frozen v1 range

Selectable SG03 values are:

`r = {0.1, 0.2, ..., 0.9}`

so SG03 now has 9 configurations, not 19.

`r=1` belongs to SG01. The source's printed `r=1` column is traditional anchored GM.

The paper reports examples above 1, but AutoGrey has not reconciled the printed restoration behavior sufficiently to justify a source-faithful v1 implementation. Therefore `r>1` is deferred rather than guessed.

### 6.3 Correct nesting wording

At `r=1`, fractional AGO/IAGO and the grey equation reduce to ordinary AGO/IAGO and the traditional GM equation.

AutoGrey does **not** claim that the complete Wu `c,d`-corrected fractional response procedure is a second algorithmically identical GM implementation. SG01 owns the `r=1` action.

### 6.4 Source regression fixture

For Wu Table 2, `r=0.3`:

- maximum absolute difference from printed fitted/forecast values: about `2.74e-4`;
- training MAPE: `1.266621%` versus printed `1.27%`;
- forecast MAPE: `3.827045%` versus printed `3.83%`.

The source's `r=1` printed column is reproduced by SG01 traditional GM to printed precision.

## 7. SG04 — NGBM / Verhulst

The frozen Bernoulli grid excludes `gamma=0` (SG01 reduction) and `gamma=1` (non-identifiable).

The engine checks real-power validity, column-normalized identifiability, rank/conditioning, and the analytic `a≈0` branch. `gamma=2` remains the named Verhulst specification inside SG04.

A primary NGBM numerical table is not yet frozen as a B1 source regression fixture; that caveat remains explicit.

## 8. SG05 — continuous time/polynomial forcing

For `GM(1,1,t^alpha)`, arbitrary noninteger alpha uses the exact integrating-factor definite integral.

FOTP uses an exact polynomial particular solution plus the homogeneous exponential.

The duplicated affine structure is verified numerically:

`time-power alpha=1 == FOTP order 2`

to floating-point error; only FOTP order 2 gets that opportunity.

The previously pending anti-degeneracy guard is now measurable:

`min d_inf[time-power alpha=.25, GM] = 0.015698`

on the frozen panel, above the collision threshold `0.001`.

This is an engineering guard result, not a published GM(t^alpha) numerical reproduction. A primary source numerical fixture remains pending.

## 9. SG06 — conformable fractional GM

The engine implements the audited CFA/CFD definitions, including higher-order conformable branches.

At `alpha=.59`, the source accumulated sequence and source `a,b` are reproduced; CFA→CFD round trip is also tested.

`alpha=1` is owned by SG01.

## 10. SG07 — rolling GM

v1 uses exactly `w=4`.

For multi-step forecasting the engine predicts one step, appends its own prediction, rolls the four-point window, refits, and repeats.

No silent window shrink is allowed.

## 11. SG08 — average WBO + GM

The average weakening buffer is the suffix mean and the fixed-point identity `d_t(t)=x_t` is asserted.

Multi-step prediction uses the already frozen AutoGrey endpoint convention: forecast the transformed endpoint, append that value as the next original-scale endpoint, recompute the WBO, refit, and repeat.

The output mapping remains explicitly an AutoGrey design convention, not a source theorem.

## 12. SG09 — Grey–Markov

The engine uses canonical GM trend plus residual-state correction with `EQW` or `EQT` partitions and state counts `S=2..4` subject to the frozen caps.

It enforces outgoing-transition counts, stochastic rows, and explicit tie failure. No smoothing and no GM fallback are introduced.

The mechanism was source-audited earlier. B1 contains strict engineered executable tests; it does not claim a new reproduction of every old application table.

## 13. SG10 — seasonal GM

Known-M seasonal factors are training-only phase mean divided by overall mean.

The Wang–Li–Pei fixture reproduces:

- factors `(0.74741036, 1.07490040, 1.29721116, 0.88047809)`;
- `a_s ≈ -3.63356e-05`;
- `b_s ≈ 25.0735185`;
- clean 2015–2016 holdout MAPE `6.125544% ≈ 6.13%`.

## 14. New known-seasonal history rule

Step 4D defines seasonal-task MASE with lag `M`, and every inner origin computes the denominator from its own training prefix.

The earliest inner training length is:

`m_first = n - h - 2`.

A lag-M MASE denominator requires:

`m_first > M`.

Therefore every group evaluated on a known-M task receives the task-level floor:

`n >= h + M + 3`

in addition to its own group floor.

Examples:

- ordinary/core group on monthly `M=12`: `n >= h+15`;
- SG09: `n >= max(h+8, h+M+3)`;
- SG10 retains the stronger two-cycle condition `n >= max(h+7, h+2+2M)`.

This is derived from the approved evaluation chronology, not claimed as a grey-model theorem.

## 15. Reference tier

The portfolio separately returns Naive, Drift, Theta, and Seasonal Naive where eligible.

They are not in the AutoGrey group action set.

## 16. Test status

The final engine passes **51 deterministic/source/contract tests with 0 failures**.

Coverage includes:

- fractional AGO/IAGO round trips;
- Wu-2013 FGM source reproduction;
- r=1 SG01 ownership;
- DGPM exact source example;
- NGBM reduction/identifiability cases;
- SG05 affine equivalence and separation;
- CFGM source example and inverse;
- WBO fixed point;
- rolling-window refusal;
- Wang-2018 SGM source example;
- Grey–Markov explicit result/failure behavior;
- common inner origins;
- known-seasonal MASE history floor;
- one-group-one-forecast;
- no-target public API;
- SG03 grid count/domain;
- forecast deduplication;
- non-selectable reference output.

Passing these tests demonstrates implementation agreement on the tested rules/fixtures. It is not forecasting-performance evidence.

## 17. Smoke panel

Four engineering fixtures were passed through the whole portfolio:

- 18-point exponential;
- 18-point curved;
- 18-point late-regime change;
- 24-point quarterly seasonal.

The exponential fixture intentionally produced several practical forecast collisions, exercising the deduplication gate.

The curved/regime fixtures retained all nine non-seasonal groups.

The quarterly fixture retained all ten groups.

No target or benchmark accuracy was used.

## 18. Explicit remaining evidence caveats

- SG04: primary-paper numerical table not yet frozen as an engine regression fixture.
- SG05: source equations/structural tests pass, but a primary GM(t^alpha) numerical regression fixture remains pending.
- SG08: future endpoint output mapping is an AutoGrey convention.
- SG09: source mechanism audited; B1 engine does not claim a fresh reproduction of every original application fixture.
- SG03 r>1: deferred.

No caveat may be silently changed during label generation. Any change requires a new engine version/hash.

## 19. What B1 does not do

- no meta label corpus generated;
- no held-out label target opened;
- no selector trained;
- no META_CAL threshold fitted;
- no META_TEST opened;
- no REAL_BENCH opened;
- no Shiny integration;
- no manuscript performance result rewritten.

## 20. Next checkpoint

Step 4F-B2 will generate the clean parent-grouped meta-label corpus using:

- `AG_ENGINE_4FB_1`;
- `AG_FEAT_4E_1`;
- approved Step-4D chronology and assertions.

Only after that corpus passes audit will Step 4F-C fit the selectors.
