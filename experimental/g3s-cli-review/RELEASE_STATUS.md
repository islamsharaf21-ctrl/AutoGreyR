# Evidence-based status

- G0: archival preflight (completed in preceding audited continuity and read-only package review)
- G1: command contract **documented** in `G1_CLI_CONTRACT.md`; pre-execution audit/approval still required
- G2: portable file distribution **assembled as candidate only**; no installation or runtime claim
- G3: single corrective candidate assembled; independent code review **NOT DONE**; author's tests/self-review cannot replace independent review
- G4: RUN-01...RUN-05 **NOT EXECUTED, 0/5**
- Audit A: **HOLD**
- G5: RUN-06...RUN-10 **BLOCKED, 0/5**
- Audit B: **HOLD**
- G6: **NOT RELEASED**

## Permanent scientific outcome

The new experimental full-TRAIN V1 deployment selector did **not** meet the prespecified NN5 R3 superiority gate. Its 16/16 pilot series mean MASE was 1.9000082988805589, versus 1.5556718366590252 for the frozen CV baseline. The paired mean difference was +0.34433646222153347, 95% interval [-0.17783983375754123, 0.8224788157135322]. Do not rerun or rescue NN5 R3. Original V1 REALBENCH2, formal V2 P11-C FAIL/CLOSED, V3 SafeSelect frozen R38 STOP_NOT_PASS, and GreyModelLabR are separate authorities.

## G3R correction disposition

- Single authorized G3 corrective pass applied to facade, unit tests, documentation, and runbook only.
- These corrections are **not** a numerical acceptance run, nor independent release review.
- G4 remains 0/5, G5 0/5; no model-fit or forecasting task authorized in this pass.
- Direct execution of unchanged internal scripts remains technically possible and is an explicit residual operational risk.
- The direct dependencies are pinned; the full transitive environment is not locked.

## G3S single scoped correction (2026-11-12)

G3R review found false-success when observer exits 0 without actual result files; this was reproduced by six failing mocked tests before correction. G3S facade rejects missing/corrupt outputs and inconsistent receipt provenance; the runbook, README and G1 contract now reference operative `0.1.0-g3s-candidate`. Engine scripts remain unchanged. All acceptance RUN-01…RUN-10 are still **0/10**; independent G3 review not signed off; G4 and G5 BLOCKED; final status **NOT RELEASED**.
