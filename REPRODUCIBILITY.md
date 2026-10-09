# Reproducing the AutoGrey V2 Public Research Release

This document describes the public reproducibility boundary. It does not authorize a P11-C rerun.

## 1. Create the software environment

Read `docs/ENVIRONMENT_RECONSTRUCTION.md`.

The evidence-derived frozen Python core is:

- Python 3.13.5
- NumPy 2.3.5
- SciPy 1.18.1
- scikit-learn 1.8.0
- joblib 1.6.0
- threadpoolctl 3.7.0
- selector seed 62291
- `n_jobs=1`

The historical `statsmodels` version is unresolved and is deliberately not invented.

The frozen executed R environment is based on R 4.6.1 plus the package inventory and OpenBLAS 0.3.30 LP64 contract in `config/environments/`.

## 2. Acquire external benchmark sources

Read `DATA_NOTICE.md` and `docs/DATA_ACQUISITION.md`.

Do not place third-party data inside the Git repository.

Use `reproducibility/acquire_realbench3.py` with a cache directory outside the repository. The script verifies record/file identity and the frozen P1 SHA-256 before accepting an archive.

## 3. Verify a P1 reconstruction

`reproducibility/verify_p1_rebuild.py` checks a reproduced P1 seal against the frozen clean-set/refusal hashes and P1 counts.

This is verification, not a reconstructed reservation algorithm. The exact original P1 acquisition/reservation runner remains unrecovered.

## 4. Public synthetic / static verification

Run the public-safe tests and environment preflight without opening protected REALBENCH3 targets.

## 5. Protected historical result

P11-C was scored once and is closed. Public aggregate result artifacts are evidence of that frozen evaluation; the release is not an instruction to rerun or redesign it.

## 6. Clean-room gate

R5-B4 will perform the final clean-room release verification after the software license is authorized.
