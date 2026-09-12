# AutoGrey Step 7E2 — R8 Cross-Platform Final Decision

## Decision

The byte-exact canonical platform for the two numerically sensitive structural groups remains Linux with Python 3.13.5, NumPy 2.3.5, and the frozen OpenBLAS-based reference environment. Windows is **not** claimed to be byte-identical for SG02_DISCRETE_POLY or SG05_CONT_TIME_POLY.

The R7 full target-free census showed that, under the same Python 3.13.5 / NumPy 2.3.5 versions on Windows, 2,302 of 4,826 sensitive forecast arrays differ in float64 bits from the Linux reference. The differences are localized to SG02 and SG05; all other structural groups satisfied the original Step 7E2 tolerance in the R4 audit, and all discrete pretarget identities/decisions remained exact.

## Frozen Windows qualification bounds

The bounds below were frozen **after** the complete target-free R7 platform census and before target opening. They are an implementation-platform qualification, not model tuning and not performance tuning.

- SG02_DISCRETE_POLY: max absolute difference <= 0.10 and normalized max relative difference <= 2e-5.
- SG05_CONT_TIME_POLY: max absolute difference <= 5.0 and normalized max relative difference <= 5.5e-4.

Normalization is `abs(actual - canonical) / max(1, abs(canonical))` elementwise.

The R7 observed Windows maxima were:

- SG02: max_abs = 0.077705143772618612; max_rel = 1.7488911046347191e-05.
- SG05: max_abs = 4.0; max_rel = 0.00051124744376278123.

## Acceptance invariants that remain exact

The final Step 7E2 verifier still requires exact reservation identity, actionable/refusal partition, all refusal reasons and target SHA commitments, canonical development hashes, all 2,496 eligibility sets, all 23,572 selected configuration IDs, V1/GLOBAL choices and counts, and the frozen selector-score tolerance. The eight non-sensitive groups retain their original forecast tolerance.

Held-out target tokens remain character data only. No target loss, regret, MASE, CVaR, or bootstrap calculation is permitted in Step 7E2.

## Consequence for later checkpoints

Step 7F1 must score the **frozen canonical pretarget forecasts**. The release documentation must distinguish:

1. canonical byte-exact Linux reproduction; and
2. qualified Windows numerical reproduction for SG02/SG05.

This avoids falsely presenting platform-dependent LAPACK results as byte-identical while preserving the frozen scientific design.
