# AutoGreyR V1 — experimental portable CLI (G3S single-scope correction candidate only)

**STATUS: NOT RELEASED / G3S CANDIDATE; independent G3 sign-off pending. No forecast-superiority claim.**

This is a new command-line facade for the archived experimental V1 full-TRAIN new-series selector. It is **not** the original frozen AutoGreyR v1.0.0 release, not formal AutoGrey V2, not V3 SafeSelect, and not GreyModelLabR. The NN5 R3 completed external pilot **did not meet its prespecified superiority criterion**.

**Operative launcher version:** `0.1.0-g3s-candidate`. Older G2/G3R files are retained as history, not as the release candidate.

## Included files

- `agv1_cli.py`: new stdlib-only preflight and delegation facade (`doctor` / `forecast`)
- `run_demo_bounded.py`, `v1_new_series_prototype.py`: byte-for-byte copies of **unchanged** 2026-11-10 experimental scripts
- `example_synthetic_12.csv`: existing harmless 12-row synthetic example
- `ACCEPTANCE_FIXTURES/extra_cell.csv`: malformed CSV reserved for unit tests only, not an eleventh acceptance run
- `G3R_REVIEW_DISPOSITION.md`, `G3S_CORRECTION_DISPOSITION.md`, `TEST_EVIDENCE/`: historical and current correction evidence (not independent reviewer approval)
- `REFERENCE_OUTPUT/`: saved already-observed reference, not fresh validation
- `G1_CLI_CONTRACT.md`, `ACCEPTANCE_RUNBOOK.md`, `requirements-pinned.txt`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `RELEASE_CONTENTS_SHA256.txt`: interface, evidence and provenance

## Windows setup (manual, not run by this package)

A separate untouched `AutoGreyR-1.0.0.zip` is required. Its SHA-256 is:

`e3e78ecdb670c9ed29af875d0b41b5aaf7506eb04844d8d193d62b890307720f`

Use Python **3.13.5**. Dependencies are pinned to NumPy **2.3.5**, SciPy **1.17.0**, scikit-learn **1.8.0**. Installing them is a user-controlled operation; this package will never install packages automatically.

```powershell
# Commands are instructions only; they are NOT evidence of successful execution.
py -3.13 --version
py -3.13 -m pip install -r .\requirements-pinned.txt
py -3.13 .\agv1_cli.py doctor --source "$env:USERPROFILE\Downloads\AutoGreyR-1.0.0.zip"
```

**STOP after the first acceptance block:** Do not launch any of the runbook's numerical forecasting commands until the run plan and evidence-capture process are approved. Do not perform R1/R2/R3 again or use NN5 targets to change outputs.

## Exact standalone commands

```powershell
py -3.13 .\agv1_cli.py doctor --source "$env:USERPROFILE\Downloads\AutoGreyR-1.0.0.zip"
py -3.13 .\agv1_cli.py forecast --source "$env:USERPROFILE\Downloads\AutoGreyR-1.0.0.zip" --series .\example_synthetic_12.csv --h 3 --out-root "$env:LOCALAPPDATA\AutoGrey\V1_CLI_ACCEPTANCE_RUN02"
```

A successful **forecast** launches a bounded observer and one child predictor, refits group-specific RFs from the original frozen TRAIN data and records resulting forecasts under a fresh output root. **A successful `doctor` does no model fitting.** A controlled refusal exits `2` and should not create an output root.

`doctor` checks original archive CRC/hash and pinned library metadata but does not prove that the predictor executes correctly. Forecast accuracy is not guaranteed. The original observer enforces 600 seconds, not a strict memory limit.

## Why no original V1 ZIP is embedded

The original 50 MB archive is provided **separately**, exactly as previously frozen; it contains historical third-party datasets and accompanying attribution notices. This candidate includes a copy of the original MIT license and third-party notice but does not repackage those datasets or claim authorship of them. Always inspect the source license/notice when redistributing the original archive.

## Current evidence

Archived 12-row synthetic result: `SG09_GREY_MARKOV`, `S=2_EQW`, forecasts **191.78061952188762, 201.61437976145692, 213.53111696175176** (archived, not freshly rerun). The NN5 pilot's observed MASE 1.9000 is worse on average than its precommitted CV-selected baseline 1.5557; its 95% paired bootstrap interval spans zero. **Primary superiority gate NOT MET**. Do not relabel a packaging PASS as statistical validation.

This is the G3S correction of the G3R candidate (which superseded G2); acceptance execution budget remains zero. No planned G4/G5 acceptance invocations have been made in producing this candidate. Status: **G1 documented; G2 files assembled; G3 independent review pending; 0/10 acceptance runs.**

## G3S operational controls (no model-fit tests)

- **Do not invoke run_demo_bounded.py directly.** This is an immutable internal implementation script.
- **Do not invoke v1_new_series_prototype.py directly.** This is an immutable internal implementation script.
- Direct execution cannot be technically blocked without modifying these immutable files. Any such unplanned execution is an immediate STOP; count it in the external ledger and do not perform further runs. A facade receipt alone does **not** prove absence of direct execution: inspect OS process evidence.
- `CLI_RECEIPT.json` is written separately in the observer output directory after the subprocess returns (including recorded failures where the output directory exists); it is **not** in the original observer evidence ZIP. Preserve both.
- The CLI records input, original source, launcher, and engine hashes before/after invocation. Equality is an endpoint check, not proof that a file could never have changed temporarily. Self-hashing is not signature verification; trust the externally recorded candidate ZIP SHA-256.
- `requirements-pinned.txt` pins three **direct** dependencies only; transitive packages are not locked. The `doctor` command checks installed metadata, not numerical imports or runtime success.
- Automated facade unit tests (`python -m unittest discover -s tests -v`) mock subprocess execution. These do not fit models and do not count as RUN-01...RUN-10. They are distinct from actual acceptance.

## G3S post-observer delivery verification

The facade now checks the observer's reported source, prototype and input SHA-256 values, then requires and parses `RESULT/SELECTED_FORECAST.csv`, `RESULT/CANDIDATE_SCORES.csv`, and `RESULT/RUN_RECEIPT.json`. A success requires matching horizon, input and source identities, train-only scientific scope, finite forecasts, valid candidate scores and consistent selected group/configuration. It records hashes of the exact verified result-file bytes in `CLI_RECEIPT.json`. A missing, malformed or inconsistent deliverable becomes `STOP_...` with exit code 2, even if the observer exited zero.

This is endpoint-level defense, not a guarantee against mutation after validation, OS-level direct-script execution, or numerical predictive superiority. No model execution was performed to qualify G3S; independent review and planned Windows acceptance are still required.
