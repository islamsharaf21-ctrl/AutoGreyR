# AutoGreyR V1 — G3S single-scope correction disposition (2026-11-12)

**Status: CANDIDATE ONLY; G3 independent sign-off NOT DONE; G4/G5 BLOCKED; 0/10 acceptance invocations; final release NOT AUTHORIZED.**

## Authority and scope

This one authorized correction addresses only G3R-R1 (observer false-success) and G3R-R2 (candidate version wording). The original frozen V1 archive, experimental observer and predictor code, 12-row historical reference outputs, prior NN5 R3 evidence, formal V2 P11-C FAIL/CLOSED, and frozen V3 SafeSelect remain untouched. No NN5 or other forecasting experiment was executed. Tests mock `subprocess.run` for the full `forecast` path.

## G3R-R1, test-first evidence

- At the original G3R launcher, six newly added regression tests returned false PASS (RED). See `TEST_EVIDENCE/G3S_RED.log`. These cover missing outputs, missing candidate scores, nonfinite forecast, wrong horizon, incorrect report input hash, and incorrect observer input hash.
- The new G3S facade separately verifies `OBSERVER_RECEIPT.json` provenance (`original_zip_sha256`, `prototype_sha256`, `input_series_sha256`) and checks the required contents of `RESULT/SELECTED_FORECAST.csv`, `RESULT/CANDIDATE_SCORES.csv`, and `RESULT/RUN_RECEIPT.json` after the observer exits. It requires finite h-step forecasts, consistent group/configuration and candidate score shape, expected input/source SHA, declared horizon/history length and train-only scientific scope.
- Only after these checks succeed does it issue a facade-level PASS. Verified SHA-256 values of the actual parsed result-file bytes are recorded in `CLI_RECEIPT.json`; failed validation produces a distinct `STOP_...` reason and exit 2.
- `TEST_EVIDENCE/G3S_FINAL_GREEN.log` documents **24/24 passing mocked no-model tests**, including the regression tests and a version-document test. The unchanged child engine is never executed by this suite.

## G3R-R2 documentation reconciliation

- Operative facade version: `0.1.0-g3s-candidate`.
- README, G1 contract and acceptance runbook now point to G3S, with G2/G3R historical lineage retained but no stale G2 instruction for future acceptance.
- RUN-10 remains the original synthetic 12-row series on an independent Windows host, without an additional experimental dataset.

## Preserved residual risks

The original engine scripts can be run directly; this is an explicit procedural prohibition rather than a technical block. The `doctor` command does not run numerical models, direct dependencies are pinned but their complete transitive environment is not, the observer timeout does not cover all launcher stages, a self-hash is not code signing, and a post-run validation cannot prevent later file tampering. This correction was tested in a non-Windows environment; Windows runtime is **NOT VERIFIED**. The review is by the same assistant, **not an independent external reviewer**.

## Final G3S evidence and stopping rule

This correction pass is CLOSED after TDD and packaging. A subsequent independent G3 review is required before any GO/authorization for RUN-01–RUN-05. There is no automatic further correction pass, additional tests, expansion of scientific goals, or acceptance invocation. If an independent reviewer finds a release blocker, record it, keep G3 HOLD, and request one explicit decision instead of silently cycling.

### Fixed scientific status

Historical V1 REALBENCH2 positive regret comparison belongs to the original frozen V1 study only. The new experimental full-TRAIN deployment selector did **not** meet the precommitted NN5 Weekly R3 positive gate: 16/16 scored, mean MASE 1.9000082988805589 versus CV baseline 1.5556718366590252; paired mean delta +0.34433646222153347; bootstrap 95% CI [-0.17783983375754123, 0.8224788157135322]. This finding is immutable. Formal V2 P11-C FAIL/CLOSED; V3 SafeSelect R38 STOP_NOT_PASS; GreyModelLabR excluded.
