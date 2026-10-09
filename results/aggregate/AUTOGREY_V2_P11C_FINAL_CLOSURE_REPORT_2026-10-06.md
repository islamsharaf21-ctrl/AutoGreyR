# AutoGrey V2 P11-C — FINAL CLOSURE REPORT
**Closure date:** 2026-10-06  
**Status:** **FAIL / CLOSED**  
**Nature:** frozen confirmatory negative result

## 1. Independent ingestion evidence

The independent result-ingestion transcript reported:
- expected artifacts present: 8/8;
- governed manifest entries: 7/7 PASS;
- parent score rows: 4,778;
- overall bootstrap rows: 4,000;
- subgroup result rows: 23;
- scientific lock changed: FALSE;
- scoring rerun allowed: FALSE.

Ingestion transcript SHA-256:
`6BD8C3DE25C22D7BAA5C1817E48119CB1700B661F2E6D2A9DBE9B12B4E1BB71D`

## 2. Frozen overall result

| Estimand | Point estimate | One-sided q=.95 upper bound | Frozen threshold | Numerical status | Confirmatory status |
|---|---:|---:|---:|---|---|
| A: mean eligible regret AutoGrey − GLOBAL | 10318616.9132176 | 28928655.4862941 | < 0 | FAIL | FAIL |
| B: mean MASE AutoGrey − NG10 | 10318617.2652612 | 28928655.8424588 | < 0.05 | FAIL | DESCRIPTIVE_NONCONFIRMATORY |
| C1: CVaR90 eligible regret contrast | 103142995.905915 | 289165515.379377 | < 0 | FAIL | DESCRIPTIVE_NONCONFIRMATORY |
| C2: CVaR90 MASE AutoGrey − NG10 | 103142997.935076 | 289165517.456237 | < 0.05 | FAIL | DESCRIPTIVE_NONCONFIRMATORY |

Fixed sequence: `A -> B -> C`.

Gate A fails first. Therefore the overall confirmatory result is FAIL and later gates cannot rescue it.

## 3. Context-only two-sided 95% intervals

| Estimand | Lower | Upper |
|---|---:|---:|
| A | -0.249078379615725 | 29942253.3529747 |
| B | 0.0984442359160278 | 29942253.7161185 |
| C1 | -1.59451853644916 | 299297253.08329 |
| C2 | 0.409481761874716 | 299297255.172039 |

These are context-only and do not alter the frozen one-sided gate decisions.

## 4. Permitted scientific claim

Canonical allowed claim:
> No full-confirmation claim is authorized; preserve and report the frozen partial or negative result.

Explicitly forbidden:
- equivalence-to-NG10 claim;
- universal superiority claim;
- NG10 superiority inference from noninferiority;
- every-non-grey superiority claim;
- unqualified generalization;
- configuration change after result.

## 5. Subgroup audit

- subgroup role: SECONDARY;
- subgroup count: 23;
- inferential subgroup count: 23;
- descriptive-only subgroup count: 0;
- minimum inferential n: 30;
- bootstrap B: 4,000;
- RNG: PCG64;
- stream policy: continue caller-supplied PCG64 after overall bootstrap;
- identical sampled indices reused across all four estimands inside each subgroup replicate;
- four separate Holm families;
- Holm FWER: 0.05;
- subgroup findings may not alter the overall confirmatory classification.

## 6. Runtime/harness provenance preserved

These must not be misclassified as scientific failures or used to justify rerunning P11-C:

1. `INCONCLUSIVE_LOCAL_PACKAGE_NOT_STAGED`
   - package was initially absent from Downloads;
   - no extraction, target read, or scoring occurred.

2. Existing preflight output guard
   - preserved an already-created canonical preflight JSON;
   - preflight JSON SHA-256:
     `AB826E6A5B81810F391766450634AE4C7F8707C2D180EF0C8F28166FE9EF7505`;
   - adjudicated PASS/CLOSED;
   - numeric target reads in preflight = FALSE.

3. `INCONCLUSIVE_HARNESS_STDERR_CAPTURE`
   - outer PowerShell evidence wrapper treated a WSL localhost-proxy stderr warning as terminating;
   - sealed inner scoring nevertheless completed and wrote the full governed result set;
   - independent result ingestion verified the scientific manifest and outputs;
   - **no scoring rerun is allowed**.

## 7. Final P11-C status

`P11-C = FAIL / CLOSED`

Interpretation:
The internally pretarget-frozen confirmatory evidence does **not** support the full AutoGrey confirmation target on REALBENCH3. The failure occurs at Gate A, and all later numerical gates also fail their frozen thresholds. This negative result is preserved exactly as required.

No scientific change, retuning, replacement, exclusion, or rerun is authorized.

## 8. P12 transition

The predecessor condition is now met because P11-C evidence preservation and independent ingestion are closed.

`P12 = UNLOCKED AS NEXT CHECKPOINT ONLY / NOT STARTED`

P12 is a release/manuscript freeze stage, not an opportunity to revise the P11-C science.
