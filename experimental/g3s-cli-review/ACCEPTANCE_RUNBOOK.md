# AutoGreyR V1 — Prespecified ten-command acceptance runbook

**DO NOT EXECUTE UNTIL THE EXACT APPROVAL TO START G4.** This is a transparent runbook for **future** tests, not a claim that these commands were executed. All forecasting uses only archived synthetic test input. Neither NN5 R1–R3 nor formal V2/V3 is run.

## Before starting

1. Read `G1_CLI_CONTRACT.md`, README and `RELEASE_CONTENTS_SHA256.txt`. Verify all outer files and original source remain byte identical. Inspect the `0.1.0-g3s-candidate` source and disclose that independent code review is still pending.
2. Python interpreter must be **3.13.5** and dependencies exact `requirements-pinned.txt`. Do not begin a run if clean environment and user evidence folder are not ready.
3. Use PowerShell in the extracted candidate root. Set the source and evidence roots separately; do not delete or overwrite an existing directory.
4. Each RUN ID means **one** top-level `agv1_cli.py` process invocation. For a successful forecast, its process tree contains **one bounded observer plus one predictor child**. Log both; no hidden retries. For a preflight refusal, there should be **no observer or predictor child**. If the actual process counts differ, STOP.
5. Preserve the separate `CLI_RECEIPT.json` from each forecast output root (it is not included in the observer evidence ZIP). Capture combined terminal stdout/stderr, `$LASTEXITCODE`, start/end UTC, full command text, frozen source/script/input hashes, and any observer receipt/evidence ZIP. File hashes alone are not proof that a test passed.
6. An observed refusal exit `2` is an expected PASS for the *refusal test*, not a successful forecast. An unexpected exit, unintended directory creation or unplanned child process is a hard STOP.

## Suggested one-invocation evidence pattern (adapt once; never wrap in a loop)

```powershell
# Set these once to local, valid paths. Do not pre-create a planned forecast output root.
$source = Join-Path $env:USERPROFILE 'Downloads\AutoGreyR-1.0.0.zip'
$ev = Join-Path $env:LOCALAPPDATA 'AutoGrey\V1_CLI_ACCEPTANCE_LEDGER_20261111'
New-Item -ItemType Directory -Force -Path $ev | Out-Null

# Example ONLY for RUN-01; execute only after explicit G4 GO.
$utcStart = (Get-Date).ToUniversalTime().ToString('o')
$result = & py -3.13 .\agv1_cli.py doctor --source $source 2>&1
$exitCode = $LASTEXITCODE
$utcEnd = (Get-Date).ToUniversalTime().ToString('o')
$result | Out-File -Encoding utf8 (Join-Path $ev 'RUN-01-terminal.txt')
"id=RUN-01;utc_start=$utcStart;utc_end=$utcEnd;exit=$exitCode" |
  Out-File -Encoding utf8 (Join-Path $ev 'RUN-01-exit.txt')
```

This is **one top-level invocation**; writing log files after the command is not another CLI invocation. For all runs, record exact command, environment, SHA, observed output, exit code and any process-tree evidence in the accompanying Excel tracker. Never substitute a screenshot or a manually typed PASS for the actual receipt.

## Block A — maximum five runs, then mandatory STOP

| RUN-ID | Top-level command (run from candidate root) | Required expected outcome | Expected child launches |
|---|---|---|---:|
| RUN-01 | `py -3.13 .\agv1_cli.py doctor --source $source` | Exit `0`; JSON `PASS_PREFLIGHT_ONLY_NO_FORECAST_RUN`; exact environment/hash; no RF fit | 0 |
| RUN-02 | `py -3.13 .\agv1_cli.py forecast --source $source --series .\example_synthetic_12.csv --h 3 --out-root "$env:LOCALAPPDATA\AutoGrey\V1_CLI_RUN02"` | Exit `0`, observer `PASS_EXPERIMENTAL_UNVALIDATED`; 3 finite forecasts, 8 candidate groups, `SG09_GREY_MARKOV`, config `S=2_EQW`; per-value abs deviation ≤ `1e-9` from archived reference | 2 |
| RUN-03 | Same as RUN-02, **only** change output root to `V1_CLI_RUN03` | Exit `0`; exact same selected group/config and forecast values within `1e-9` of RUN-02 and archived reference; own receipt | 2 |
| RUN-04 | `py -3.13 .\agv1_cli.py forecast --source $source --series .\ACCEPTANCE_FIXTURES\bad_header.csv --h 3 --out-root "$env:LOCALAPPDATA\AutoGrey\V1_CLI_RUN04"` | Exit `2`, `STOP_INPUT_SCHEMA_EXPECTED_ONE_VALUE_COLUMN`, no output root | 0 |
| RUN-05 | `py -3.13 .\agv1_cli.py forecast --source $source --series .\ACCEPTANCE_FIXTURES\nonfinite.csv --h 3 --out-root "$env:LOCALAPPDATA\AutoGrey\V1_CLI_RUN05"` | Exit `2`, `STOP_INPUT_NONFINITE_ROW_8`, no output root | 0 |

**MANDATORY AUDIT A — STOP here.** Examine five logs and launch counts; independently compare outputs and hashes; ensure full V1 source unmodified, no NN5/V2/V3/GreyModelLabR material opened, full-TRAIN scope shown, and NN5 R3 gate NOT MET preserved. User must explicitly authorize RUN-06…RUN-10. Any error before RUN-05 is an immediate STOP; do not finish block by rote.

## Block B — only after explicit audit A GO

| RUN-ID | Top-level command (run from candidate root) | Required expected outcome | Expected child launches |
|---|---|---|---:|
| RUN-06 | `py -3.13 .\agv1_cli.py forecast --source $source --series .\ACCEPTANCE_FIXTURES\short_9.csv --h 3 --out-root "$env:LOCALAPPDATA\AutoGrey\V1_CLI_RUN06"` | Exit `2`, `STOP_SERIES_TOO_SHORT_FOR_FROZEN_ELIGIBILITY`, no output root | 0 |
| RUN-07 | `py -3.13 .\agv1_cli.py forecast --source $source --series .\example_synthetic_12.csv --h 2 --out-root "$env:LOCALAPPDATA\AutoGrey\V1_CLI_RUN07"` | Exit `2`, `STOP_HORIZON_OUTSIDE_FROZEN_V1_TRAIN_DOMAIN`, no output root | 0 |
| RUN-08 | `py -3.13 .\agv1_cli.py forecast --source $tamperedSourceCopy --series .\example_synthetic_12.csv --h 3 --out-root "$env:LOCALAPPDATA\AutoGrey\V1_CLI_RUN08"` | Exit `2`, `STOP_ORIGINAL_V1_SOURCE_SHA256_MISMATCH`, no output root; original `AutoGreyR-1.0.0.zip` unchanged | 0 |
| RUN-09 | `py -3.13 .\agv1_cli.py forecast --source $source --series .\example_synthetic_12.csv --h 3 --out-root $preexistingDisposableRoot` | Exit `2`, `STOP_OUTPUT_ROOT_ALREADY_EXISTS`, sentinel unchanged | 0 |
| RUN-10 | Exact RUN-02 command on **independent Windows host**, different fresh root `V1_CLI_RUN10` | Exit `0`; complete Windows evidence with finite 3-step forecast, script/source hashes, child process receipt; within `1e-9` of archived reference in pinned environment | 2 |

Before RUN-08, prepare `$tamperedSourceCopy` by copying the source archive to a **distinct disposable location** and appending a harmless byte to the copy. Never write to or edit the original archive. Before RUN-09, create `$preexistingDisposableRoot` containing a unique sentinel file and record its SHA before and after. These fixture-preparation actions are not CLI runs but MUST be logged; any accident to the frozen source causes STOP.

**MANDATORY AUDIT B — STOP after RUN-10.** The final decision is experimental release **only** if every expected result is evidenced, all files are hash-consistent, both audit GO records are present, there were no extra/unlogged invocations, and a separate independent reviewer has cleared G3. Otherwise record `STOP_NOT_RELEASED`, with no automatic new run budget.

## Known operational limits

- RUN-01 checks distribution metadata, not a working floating-point prediction. RUN-02/03/10 make actual experimental RF refits; they are *not* real-data superiority experiments.
- Original observer's 600-second timeout is not an enforceable memory cap; monitor system resources separately on Windows.
- R3 source/result must remain immutable: 16/16, experimental mean MASE 1.9000083 vs baseline 1.5556718, 95% interval [-0.1778398, 0.8224788], superiority NOT MET.
- Linux synthetic evidence is historical. The proposed Windows acceptance must not be assumed to pass.

## Audit decision sheet

Complete one written decision per block:

```
Block: A / B
RUN IDs inspected: ________
Top-level CLI processes: ________
Observer children: ________
Predictor children: ________
All actual exit codes and receipt hashes accounted for? YES / NO
Original V1 ZIP hash unchanged? YES / NO
Any unexpected directory, retry, unapproved model or source access? YES / NO
Numerical and refusal expectations independently checked? YES / NO
Scientific negative NN5 result preserved? YES / NO
Decision: GO / HOLD / STOP
Approver and UTC timestamp: ________
Evidence paths and SHA-256 values: ________
```

## G3S direct-execution and corrected RUN-10 controls

**Do not invoke run_demo_bounded.py directly.**
**Do not invoke v1_new_series_prototype.py directly.**
These copies remain byte-identical to the experiment. Technical blocking of their direct entrypoints would change immutable source. Any direct invocation not present in the planned RUN-ID ledger requires immediate STOP, source/process accounting, and no automatic repeat.

RUN-10 uses the **same** archived `example_synthetic_12.csv` (not a different synthetic series), `h=3`, no `--M`, but a fresh output root on an independent Windows host. The archived three forecasts remain the precommitted reference.

Preflight now refuses malformed rows with extra cells or blank rows. The CLI records before/after hashes and writes a separate CLI receipt for each observer-created output directory. Unit tests are not Windows execution evidence and must never be counted as acceptance RUN-IDs.

## G3S result-verification prerequisite (static contract; no execution approval)

The operative package is `0.1.0-g3s-candidate`; verify the outer ZIP hash and manifest before RUN-01. A successful forecast receipt MUST have non-null `verified_result_sha256` covering three required deliverables and matching observer and result provenance. An observer PASS receipt alone is insufficient. If any result file is missing, its content cannot be parsed, any forecast is non-finite, the horizon/group/configuration disagrees, or source/input hashes disagree, the CLI must STOP even when the observer exits zero. This amendment does not authorize G4.
