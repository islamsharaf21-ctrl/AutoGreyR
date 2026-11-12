# G3R correction ledger — read-only science, no-model-fit QA

**Scope:** One authorized corrective pass after G3 review. Original V1 archive and two experimental engine scripts remain byte-identical. No NN5, formal V2, V3 SafeSelect, or GreyModelLabR execution or evidence transfer.

## Disposition of G3 findings

| ID | Corrective outcome | Remaining gate |
|---|---|---|
| G3-01 | `csv.reader(strict=True)` rejects extra/blank records; test-first RED→GREEN | Independent G3 review |
| G3-02 | README and runbook prohibit direct observer/predictor invocation; external ledger treats it as unplanned STOP | **Residual:** immutable scripts still technically runnable directly; no complete technical guarantee |
| G3-03 | RUN-10 specifies **same** `example_synthetic_12.csv`, `h=3`, no `--M`, independent fresh output root and host; tracker reconciled | Windows execution untested |
| G3-04 | 17 no-model-fit unit tests, `subprocess.run` always mocked in tests that call `forecast`; initial 12 RED had six failures and three errors; final suite 17/17 | Independent review and Windows acceptance still open |
| G3-05 | Facade records pre/post input hashes (plus source/engine hashes); mismatch yields STOP and separate receipt | Endpoint checks do not prove no transient mutation |
| G3-06 | Doctor and forecast record the facade's SHA-256; external candidate ZIP hash is the actual trust anchor | No cryptographic code signing; self hash not authentication |
| G3-07 | Direct dependency pins clearly disclosed; transitive resolution not locked | Clean-environment reproducibility unqualified |
| G3-08 | Notice scope clarified: Monash datasets in separately supplied original ZIP, not this candidate | None |
| G3-09 | Doctor remains a metadata-only preflight, does not import/fit numerical models | Deliberately retained |

## Hard boundaries

- G4 RUN-01–05 **0/5**, G5 RUN-06–10 **0/5**; Audit A and B HOLD.
- New launcher tests are NOT counted among the ten acceptance runs.
- No standalone observer/predictor invocation is permitted in this release workflow. The unmodified scripts cannot enforce that policy; independent reviewer must judge this residual risk before G4.
- G3 **NOT PASSED** until independent reviewer sign-off; candidate remains **NOT RELEASED**.
- NN5 Weekly R3 completed 16/16, experimental mean MASE 1.9000083 vs CV baseline 1.5556718, paired delta +0.3443365, CI [-0.1778398, 0.8224788]; primary superiority gate **NOT MET**.

## Attached evidence

`TEST_EVIDENCE/G3R_RED.log`, `TEST_EVIDENCE/G3R_FINAL_GREEN.log`, and `TEST_EVIDENCE/G3R_NO_MODEL_TEST_EVIDENCE.json` support only facade mock tests. They are not independent source-review or Windows-run evidence.
