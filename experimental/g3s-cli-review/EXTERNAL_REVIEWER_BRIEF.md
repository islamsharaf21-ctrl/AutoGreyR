# AutoGreyR V1 G3S — independent external reviewer brief

**Review type: CODE-ONLY / READ-ONLY.** Do not execute or fit forecasting models, retrain, change scripts, use NN5, or authorize any of RUN-01...RUN-10. This is an external verification gate, not a rerun of scientific results.

**Review target:** `AUTOGREYR_V1_EXPERIMENTAL_CLI_G3S_SINGLE_CORRECTION_2026-11-12.zip` (SHA-256 `924522d516a6c0a5f1a320a2780b468f8f24545abacea49ea05b580df92c05f1`). Read `G1_CLI_CONTRACT.md`, `ACCEPTANCE_RUNBOOK.md`, `README.md`, `RELEASE_STATUS.md`, `agv1_cli.py`, `tests/test_agv1_cli.py`, and the unchanged observer/predictor scripts. The original frozen V1 ZIP is a separate archived source (SHA-256 `e3e78ecdb670c9ed29af875d0b41b5aaf7506eb04844d8d193d62b890307720f`); do not modify it. Avoid cross-project substitutions.

## Decision criteria

Mark each as **PASS / BLOCK / CANNOT VERIFY**, with exact code references, before a final G3 recommendation:

1. Source custody: candidate manifest and original script hash guards; no changes to engine/feature/training science.
2. Preflight control: correct header, row width, finite values, n >= h+7, h in {1,3,5}, seasonal M >=2, fresh output, original ZIP exact hash; refusals must precede model launch.
3. Delegation and process accounting: the facade requests one observer invocation; explicitly disclose what must be independently verified on Windows about predictor child count, abort/timeout handling, and lack of automatic retries.
4. Post-run fail-closed check: observer PASS alone is insufficient; verify required result files, finite and matching forecasts, rank/config/group agreement, counts and provenance. Inspect code for malformed result paths that could spuriously return success.
5. Evidence quality: distinguish test logs asserting mocked 24/24 PASS from independently executed unit tests, and from future Windows acceptance tests. A ZIP checksum is not numerical correctness.
6. Documentation consistency: CLI candidate version, RUN-10 fixture, independent host, dependency versions, direct-internal-script prohibition, receipt outside observer ZIP, 600-second child deadline limitation.
7. Scientific boundaries: experimental NN5 R3 prespecified positive gate **NOT MET**; original frozen V1, formal V2 P11-C FAIL/CLOSED, frozen V3 SafeSelect, GreyModelLabR remain distinct.
8. Final release hold: **no model acceptance runs** until an external source review PASS *and* user authorization for RUN-01…RUN-05. G4 must still stop after five invocations for Audit A; G5 requires new authorization.

## Required reviewer response

- Reviewer name/organization or independently attributable identity and review date.
- Exact SHA-256 of the candidate reviewed.
- Each criterion 1–8 PASS/BLOCK/CANNOT VERIFY, with file and line ranges, evidence, and impact.
- Residual risk acknowledgements and whether any **new release-blocking defect** was discovered.
- Explicit decision: **G3 APPROVE / G3 HOLD — BLOCK / G3 CANNOT VERIFY**.
- Confirmation: *No forecasting or protected data execution performed; no modified original files; no new acceptance RUN-IDs consumed.*

**If BLOCK or CANNOT VERIFY:** stop. No source changes or new checkpoints without a new, explicit user decision. An external reviewer can approve the source-level gate only; Windows functionality and forecasting superiority remain separate tests/claims.
