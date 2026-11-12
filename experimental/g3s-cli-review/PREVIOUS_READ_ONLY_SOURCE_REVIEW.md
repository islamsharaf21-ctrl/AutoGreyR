# AutoGreyR V1 — G3S read-only source review and finite decision

**Date:** 2026-11-12. **Reviewed artifact:** `AUTOGREYR_V1_EXPERIMENTAL_CLI_G3S_SINGLE_CORRECTION_2026-11-12.zip` (SHA-256 `924522d516a6c0a5f1a320a2780b468f8f24545abacea49ea05b580df92c05f1`).

**Reviewer independence:** This inspection was performed by the same assistant that prepared earlier iterations. It is a distinct read-only code inspection, **NOT** an independent-person or external sign-off. The user-established independent G3 requirement is **NOT SATISFIED**.

**Decision:** **G3 HOLD / NO NUMERICAL AUTHORIZATION / NOT RELEASED.** No newly discovered source-level release blocker in the reviewed G3S false-success paths. The earlier G3R-R1 and G3R-R2 corrections are consistent with the actual G3S source and documentation; independent reviewer approval and Windows usability evidence are still absent. Do not infer predictive superiority or automatic permission for RUN-01…RUN-05.

## Reproducible read-only observations

- G3S ZIP: 32 entries, ZIP CRC test PASS, manifest 31/31 SHA-256 matches.
- Original `AutoGreyR-1.0.0.zip`: SHA-256 `e3e78ecdb670c9ed29af875d0b41b5aaf7506eb04844d8d193d62b890307720f`; archive CRC PASS, 177 entries. This is the **original frozen V1** and is separate from the new deployment selector.
- Unchanged experimental observer `run_demo_bounded.py`: SHA-256 `b9df6ad83626f9fcb6baaa19917c161d5d187e264b039f356b1bd5e0c0068a37`.
- Unchanged experimental predictor `v1_new_series_prototype.py`: SHA-256 `2c4f6d7f1ca9a981afdb618a9a62f0e64e612f208382cac666ede577e1ad1028`.
- G3S CLI facade SHA-256 `71a6199ec36a4718c0c5590891e50c94a7adf8b9ccfec16868dcb40710976f16`.
- AST parse (without import/execution) PASS for facade, observer, predictor and tests.
- Archived G3S regression log reports `Ran 24 tests ... OK`; the tests mock the observer, so that is not an observed forecasting run, independent sign-off, or Windows evidence. The archived RED log contains six relevant failure cases in the prior G3R facade; this review did not rerun either suite.
- The saved synthetic `REFERENCE_OUTPUT` was independently parsed **as data only**: 3 chronological finite forecasts; 8 ranked candidate rows; matching first-place SG09_GREY_MARKOV / S=2_EQW; selected forecast matches the first ranked candidate's forecast values. No RF fitting, forecasting, or RUN-ID invocation occurred.
- The complete G3S handoff archive CRC and its internal manifest match. Existing tracker showed RUN-01…RUN-10 not executed, G4=0/5 and G5=0/5; Audit A/B HOLD.

## Line-linked source review

| Finding | Code/document evidence | Assessment |
|---|---|---|
| G3R-R1 false-success without files | `agv1_cli.py:163–249` checks three result files, parseable h-step finite forecasts, candidate score count and first-ranked forecast agreement; `:295–321` calls checks before PASS | **Corrected in the inspected source path.** Not a Windows runtime demonstration. |
| Observer provenance | `agv1_cli.py:154–160, 313–321` confirms original source, input and predictor hash labels; `:179–192` confirms result receipt source/input/h/n/M and train-only scope | **Scope-consistent.** Trusts observer-reported fields plus file identities rather than an external signing authority. |
| Immutable source and input | `agv1_cli.py:62–100, 252–269, 281–303` checks original hashes, exact declared environment and endpoint hashes | **Scoped source guard present.** Endpoint hashes do not prevent temporary modifications or changes after check. |
| Strict input refusal | `agv1_cli.py:103–133, 252–267` checks header, row width, blank/nonfinite values, h/M domain and minimum history before subprocess | **Visible in source.** No new acceptance-run refusal was executed. |
| G3R-R2 version drift | `agv1_cli.py:24`, `README.md:7`, `ACCEPTANCE_RUNBOOK.md:7,99`, `G1_CLI_CONTRACT.md:4,58` | **Reconciled to** `0.1.0-g3s-candidate` as operative version. Earlier versions remain historical. |
| Process accounting | `agv1_cli.py:279, 328–329`, `run_demo_bounded.py:115–119` | Facade requests one observer; it does **not** independently prove only one predictor was launched. Retain external Windows process-tree evidence requirement. |
| External receipts | `agv1_cli.py:324–354`, `README.md:61–64` | `CLI_RECEIPT.json` is outside the observer evidence ZIP. Collect separately; self-hash is not an independent signature. |
| Runtime and dependency bounds | `agv1_cli.py:91–100`, `run_demo_bounded.py:119–134`, `README.md:64` | Direct deps pinned; transitive lock absent. Observer timeout is child-focused, not whole-command deadline. Explicitly unqualified. |

## Residual risks and scope judgments

1. **Independent review unmet (gating).** A new report from the same authoring assistant cannot satisfy the prior independent-review requirement. Send the unchanged G3S candidate, G1 contract, acceptance runbook, this report and hashes to a separate technically qualified reviewer. Require a signed conclusion (PASS, BLOCK, or CANNOT VERIFY) with line references; a claim of file integrity alone is insufficient.
2. **Windows runtime unverified (acceptance scope).** G4/G5 are the already planned reproducibility and refusal exercise. Do not convert mocked unit tests or Python AST checks into Windows PASS.
3. **Provenance and execution boundaries remain procedural.** The two unchanged scripts are directly executable; transitive dependencies are not fully locked; system-level process counting and tamper protection remain unproven. They are *disclosed residual risks*, not new scientific test results.
4. **No verified new release blocker in this inspection.** Lack of a newly found source defect is not certification that none exists. In particular, the five-run plan intentionally checks end-to-end behavior that static inspection cannot establish.
5. **No new correction cycle authorized.** If an external reviewer identifies an important defect, stop and ask for an explicit scope decision instead of automatically building G3T or running G4.

## Exact finite next decision

**STOP at G3.** Do not change the candidate and do not run numerical tests until a genuinely separate reviewer has independently ruled on it. If that reviewer signs PASS, the user must **separately** authorize **only RUN-01 through RUN-05**, and stop after five runs for Audit A. RUN-06 through RUN-10 require a further GO. On any unexpected failure, stop immediately and record evidence; no automatic rerun, target peeking, or rescue experiments.

**Permanent scientific results:** Original frozen V1's historical REALBENCH2 result is separate. Experimental NN5 Weekly R3 is COMPLETE: 16/16 series; experimental mean MASE 1.9000082988805589, CV baseline 1.5556718366590252; paired delta +0.34433646222153347; 95% bootstrap interval [-0.17783983375754123, 0.8224788157135322]; **PRESPECIFIED SUPERIORITY GATE NOT MET**. Formal V2 P11-C FAIL/CLOSED; V3 SafeSelect R38 STOP_NOT_PASS; GreyModelLabR excluded.
