# Environment locks

R5-B2 adds public reconstruction records without overwriting the historical frozen P3 evidence already retained in this directory.

Authoritative reconstruction files:
- `PYTHON_ENVIRONMENT_LOCK.json`
- `PYTHON_FROZEN_CORE_REQUIREMENTS.txt`
- `R_ENVIRONMENT_LOCK.json`
- `R_FROZEN_PACKAGE_INVENTORY.csv`
- `renv.lock`
- `ENVIRONMENT_RECONSTRUCTION_GAPS.md`

Historical `AUTOGREY_V2_P3_*` records are preserved for provenance. Where the old preexecution `OpenBLAS_0.3.30_ILP64` label conflicts with later executed R5D evidence, the executed LP64 evidence controls reproduction and the discrepancy is documented rather than erased.
