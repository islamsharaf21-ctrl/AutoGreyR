# AutoGrey V2 environment reconstruction

## Python selector/runtime lock
The frozen P6/P7 evidence identifies:
- Python `3.13.5`;
- NumPy `2.3.5`;
- SciPy `1.18.1`;
- scikit-learn `1.8.0`;
- joblib `1.6.0`;
- threadpoolctl `3.7.0`;
- selector seed `62291`;
- `n_jobs=1`.

These values are in `config/environments/PYTHON_ENVIRONMENT_LOCK.json` and `PYTHON_FROZEN_CORE_REQUIREMENTS.txt`.

The historical P6 pip-freeze and wheel-manifest bytes are not present in the recovered controlled public evidence, although their frozen hashes are known and retained. The historical `statsmodels` version is also unresolved. It is therefore **not** guessed or silently pinned. `statsmodels` appears only in the non-selectable Python reference-tier Theta helper; the frozen P3 NG10 comparator itself was R/`forecast` based.

`python reproducibility/environment_preflight.py` compares a candidate environment with the exact known core versions and reports every mismatch.

## R runtime lock
The final executed P3 R5D evidence identifies:
- R `4.6.1`;
- `forecast 9.0.2` and the complete 47-package R5 user-library inventory;
- frozen direct pins listed in `R_ENVIRONMENT_LOCK.json`;
- one-thread numerical policy;
- OpenBLAS `0.3.30`, `TARGET=SKYLAKEX`, `DYNAMIC_ARCH=0`, `INTERFACE64=0`, LP64;
- OpenBLAS source SHA-256 `27342cff518646afb4c2b976d809102e368957974c250a25ccc965e53063c95d`.

The earlier preexecution package-lock label `OpenBLAS_0.3.30_ILP64` is preserved as historical evidence, but the final build and runtime-smoke artifacts prove that the execution-qualified R5D environment used **LP64**. The public reconstruction lock therefore follows the executed LP64 environment; this is a release-documentation correction, not a scientific change.

`config/environments/renv.lock` is a reconstruction lock generated from the final R5D package inventory and the frozen 2026-03-18 Posit CRAN snapshot label. It must be exercised in a clean R 4.6.1 environment during R5-B4; R is not installed in the current verification container.

`reproducibility/build_openblas_0_3_30_lp64.sh` fails closed on the OpenBLAS source hash before building with the final R5D options.

## Clean-room requirement
Environment locks are evidence of what to recreate; they are not themselves proof that a clean room can restore every dependency. R5-B4 must perform the actual fresh restoration, native R/PowerShell syntax/runtime checks, and smoke tests before any stable release decision.
