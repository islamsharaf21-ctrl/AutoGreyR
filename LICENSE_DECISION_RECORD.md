# Software License Decision Record — Apache License 2.0

**Checkpoint:** R5-B3 — Public Release Documentation + License / Data-Rights Gate  
**Date:** 2026-10-09  
**Status:** AUTHORIZED / LOCKED

## Decision

The corresponding author explicitly confirmed that the necessary author/coauthor/institutional authority exists to release the **original AutoGrey V2 software code** under the **Apache License 2.0**.

The standard Apache License 2.0 text is activated in the repository as `LICENSE`.

## Scope

The Apache License 2.0 applies to original AutoGrey V2 software source and project-authored software documentation to the extent owned/licensable by the project authors.

It does **not** relicense:

- REALBENCH3 or any other third-party dataset;
- third-party source archives;
- Python, R, OpenBLAS or other dependencies;
- third-party papers, documentation, trademarks or other external materials.

Those materials retain their upstream terms. See `DATA_NOTICE.md` and `THIRD_PARTY_NOTICES.md`.

## Data boundary

The public source repository continues to use the R5-B3 **source-only / no-third-party-data-redistribution** model. Dataset bytes are not bundled merely because the software is now Apache-2.0 licensed.

## Scientific boundary

This licensing action changes no scientific source, result, selector, comparator, action group, benchmark population, bootstrap, gate or conclusion.

P11-C remains **FAIL / CLOSED** and is not rerun.
