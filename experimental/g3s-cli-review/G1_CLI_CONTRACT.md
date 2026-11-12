# G1 — Frozen CLI interface and release acceptance contract

**Project:** AutoGreyR V1 *experimental full-TRAIN deployment selector* only  
**Operative interface implementation:** `0.1.0-g3s-candidate` (G2 and G3R versions retained as historical amendments)  
**Decision date:** 2026-11-11  
**Status:** Interface documented; numerical acceptance **NOT STARTED**.  
**Source authority:** Original AutoGreyR v1.0.0 source ZIP and the separately archived V1 experimental prototype from the audited 2026-11-11 continuity archive.

## Scope and command contract

This is a portable ZIP containing Python source, not a published Python package. An unchanged original V1 ZIP must be supplied separately. Nothing is installed except the specifically pinned Python dependencies and no original source is modified.

```
py -3.13 agv1_cli.py doctor --source "C:\\...\\AutoGreyR-1.0.0.zip"
py -3.13 agv1_cli.py forecast --source "C:\\...\\AutoGreyR-1.0.0.zip" --series "C:\\...\\input.csv" --h 3 --out-root "C:\\...\\fresh-out"
```

- `doctor` is strictly non-model-fitting: checks package script SHA-256, the original ZIP SHA-256 and CRC, and Python plus three dependency versions. Success exits `0` with JSON `PASS_PREFLIGHT_ONLY_NO_FORECAST_RUN`; refusal exits `2`.
- `forecast` requires all four options (`--source`, `--series`, `--h`, `--out-root`), accepts optional `--M` integer of at least 2, and forwards once to **unchanged** `run_demo_bounded.py`, which launches **unchanged** `v1_new_series_prototype.py` once. Those existing scripts remain the sole model-fit/forecast logic.
- Input is one UTF-8/UTF-8-BOM CSV column **exactly `value`**, chronological oldest to newest, finite numeric values and at least `h+7` rows. Horizon domain is `{1,3,5}`. Missing, mismatched, existing output directories and invalid source identity are **controlled refusals before any new output directory is created**.
- `forecast` success has the observer's existing result files under `fresh-out/RESULT/`, logs, `OBSERVER_RECEIPT.json` and the evidence ZIP. It must not overwrite any existing run directory. The observer enforces 600-second execution timeout; this is **not** a memory/CPU cap.
- Exact dependency versions: CPython `3.13.5`; NumPy `2.3.5`; SciPy `1.17.0`; scikit-learn `1.8.0`. No silent automatic installation/fallback. System environments with other versions are out of scope.
- Original ZIP must have SHA-256 `e3e78ecdb670c9ed29af875d0b41b5aaf7506eb04844d8d193d62b890307720f`. The frozen Python engines and train files inside the original archive are independently hash checked by the unchanged predictor during the model run.

## Known scientific status (immutable)

Original V1 historical REALBENCH2 result and the experimental new-series selector are **different evaluations**. The original frozen V1 final-fit state is *NOT_FIT_R2_OOF_SEARCH_ONLY*. The prototype fits separate full-TRAIN RFs for each eligible structural group on each invocation, using 18,107 frozen TRAIN actions from 2,070 parents. It is not production-ready.

NN5 Weekly R3 external pilot was already completed (16/16 series, three-week horizon): mean MASE **1.9000082988805589** for experimental selector versus **1.5556718366590252** for the precommitted CV statistical baseline; paired difference **+0.34433646222153347**, bootstrap 95% interval **[-0.17783983375754123, 0.8224788157135322]**. **The prespecified positive superiority gate was NOT MET.** It is prohibited to rerun R1/R2/R3, create rescue R4, use protected NN5 targets to adjust this CLI, or import evidence from formal V2, V3 or GreyModelLabR.

## Controls and stop conditions

1. No new numerical forecast testing until an explicit GO for RUN-01 through RUN-05; stop for independent audit after exactly five top-level planned RUN-ID submissions. No spontaneous retry.
2. No RUN-06 through RUN-10 without a further explicit Audit A GO. Stop after RUN-10 for Audit B. Unexpected failure causes immediate STOP before any five-run boundary.
3. A RUN-ID is one **top-level user-facing invocation** of `agv1_cli.py`. Log underlying processes separately: success in `forecast` spawns **one** observer subprocess and **one** predictor subprocess; no additional forecasts or repeats are authorized. Counts of each process and all subprocess failures must be preserved; do not misreport process counts as ten total OS processes.
4. Refusal commands count as RUN-IDs despite exiting nonzero. An error, an absent receipt, an extra launch, a timeout or wrong numeric result is a STOP requiring disposition; failures cannot be silently rerun.
5. Run-02/03 use the same archived 12-row synthetic reference, `h=3`, no `--M`; must select `SG09_GREY_MARKOV`, config `S=2_EQW`, three forecast values within absolute `1e-9` of archived references. Candidate scores need numerical (not byte) repeatability.
6. The portable candidate is not a release until independent source review, user Windows test, all 10 acceptance tests, two approved five-run audits, full logs and manifest exist. Do not describe as `PASS` based on static inspection.

## Input exceptions and known limitations

The upfront validation added by this facade corrects the **output-directory-on-invalid-input** behavior of the unmodified observer. No source code changes occur in either original observer or predictor. It is deliberately fail-closed. Environment/version checks use installed distribution metadata and may still require an actual smoke run to confirm binary compatibility; they are not independent runtime validation. No persisted fitted RF, hyperparameter improvement, forecast intervals, batch jobs, GUI, resource-memory bound or predictive superiority is claimed.

## Acceptance status as of this document

- Contract: **G1 DOCUMENTED**.
- Candidate static assembly: **G2 CANDIDATE**, separate artifact.
- Independent G3 review: **NOT DONE**; an author's static self-check is not independent verification.
- New acceptance RUN-01…RUN-10: **0/10**.
- Audit A: **HOLD**. Audit B: **HOLD**. Final release: **NOT RELEASED**.

## G3R implementation amendment (does not change scientific scope)

The corrected facade is version `0.1.0-g3r-candidate`, superseding the G2 implementation while preserving this G1 command interface. It adds strict single-field CSV record validation and separate pre/post invocation provenance (the output-root `CLI_RECEIPT.json`). Direct internal execution is prohibited by the acceptance protocol but technically remains possible because the two scripts are byte-preserved. The 10-run schedule and archived NN5 result are unchanged.

## G3S bounded result-verification amendment

`0.1.0-g3s-candidate` preserves `doctor` / `forecast` signatures and the immutable experimental engine. It adds independent facade validation of deliverable presence, parseable finite `h`-step forecasts, selected group/config agreement, candidate-score shape, and source/input/observer provenance. Exit 0 requires actual deliverables, not merely subprocess exit 0 and a success marker. The original G2/G3R interface history remains documented above. This is an experimental candidate, not the frozen V1 original release.
