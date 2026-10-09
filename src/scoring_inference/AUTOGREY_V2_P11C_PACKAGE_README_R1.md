# AutoGrey V2 P11-C — Frozen Confirmatory Scoring Package R1

## Scope

This is the frozen executable P11-C package produced after implementation Tasks 1–8. It is designed for the already-open REALBENCH3 target state and must not be used to redesign, retune, refit, replace parents, change comparators, alter the noninferiority margin, change CVaR90, change bootstrap settings, or change subgroup rules.

**REALBENCH3 is permanently OPEN.**  
**P12 remains LOCKED until P11-C evidence ingestion is independently verified.**

## Frozen execution order

1. Verify the package ZIP SHA-256 against its external `.sha256` sidecar.
2. Extract the ZIP to a new directory only.
3. Verify `AUTOGREY_V2_P11C_PACKAGE_MANIFEST_R1.sha256` and the critical members.
4. Run `RUN_AUTOGREY_V2_P11C_PREFLIGHT_R1.ps1` only.
5. Inspect `${AUTOGREY_DOWNLOADS}\AUTOGREY_V2_P11C_PREFLIGHT_R1_OUTPUT\AUTOGREY_V2_P11C_PREFLIGHT_R1.json` and preserve the console output.
6. Only if the score-free preflight is PASS, run `RUN_AUTOGREY_V2_P11C_SCORING_R1.ps1` once.
7. Preserve the scoring console output and the complete immutable scoring output directory.
8. Independently verify `AUTOGREY_V2_P11C_MANIFEST_R1.sha256` inside the scoring output.
9. Do not unlock P12 until evidence ingestion/verification is separately closed.

## Frozen local paths

- P10 / P11-A1 workspace: `${AUTOGREY_WORKSPACE}`
- P11-A2 Final R3: `${AUTOGREY_WORKSPACE}\AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_R3`
- P11-B opened-target output: `${AUTOGREY_P11B_DIR}`
- P11-C0 R4 sealed evidence: `${AUTOGREY_R4_EVIDENCE}`
- Frozen Python runtime: `${AUTOGREY_WSL_PYTHON}`

## Score-free preflight guarantees

The preflight verifies exact identities, manifests, schemas, parent-set alignment, forecast linkage, the 4,781/4,778/3 population contract, and the declared float64 binary-slice schema. It must not numerically read target values and must not compute MASE, regret, CVaR90, bootstrap values, or gate results.

## Real scoring outputs

A successful scoring run creates one new immutable output directory containing exactly these canonical scientific outputs:

1. `AUTOGREY_V2_P11C_PARENT_SCORES_R1.csv`
2. `AUTOGREY_V2_P11C_OVERALL_BOOTSTRAP_R1.csv`
3. `AUTOGREY_V2_P11C_OVERALL_RESULTS_R1.json`
4. `AUTOGREY_V2_P11C_SUBGROUP_RESULTS_R1.csv`
5. `AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1.json`
6. `AUTOGREY_V2_P11C_CONFIRMATORY_DECISION_R1.txt`
7. `AUTOGREY_V2_P11C_ASSERTIONS_R1.json`
8. `AUTOGREY_V2_P11C_MANIFEST_R1.sha256`

The scoring output path is never overwritten.

## Frozen scientific settings

- deployed scoring population: 4,778 parents;
- CVaR90: mean of worst `ceil(0.10*N)`;
- RNG: NumPy `default_rng` / PCG64;
- seed: `1068199533`;
- bootstrap replicates: 4,000;
- one paired parent draw per replicate shared by A/B/C1/C2;
- one-sided upper bound: q=0.95, NumPy `method="linear"`;
- fixed sequence: A → B → C, where C requires C1 and C2;
- Gate A/C1 threshold: 0;
- Gate B/C2 threshold: +0.05 MASE;
- subgroup analysis: secondary only, n>=30 for inference, four separate Holm families at FWER 0.05.

## Claim discipline

A full PASS authorizes only the frozen constrained claim embedded in the scorer. It does not authorize equivalence to NG10, universal superiority, superiority to NG10 merely from noninferiority, superiority to every non-grey method, or unqualified generalization beyond the reserved REALBENCH3 population. Negative and partial outcomes are preserved without retuning.

## Construction status

This package was constructed and tested only with synthetic fixtures. Package construction did **not** run the user's real score-free preflight, did **not** numerically read the real P11-B targets, and did **not** run the real 4,778-parent P11-C scoring command.
