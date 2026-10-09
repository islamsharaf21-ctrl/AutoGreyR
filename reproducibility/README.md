# Reproducibility — R5-B2

This directory implements the public-safe acquisition/checksum and environment-preflight layer for the `v2.0.0-rc1` release candidate. It does not contain third-party benchmark bytes and does not rerun P11-C.

## Commands

### Source metadata / acquisition
```bash
python reproducibility/acquire_realbench3.py --cache-dir /external/cache
python reproducibility/acquire_realbench3.py --cache-dir /external/cache --download
```
See `docs/DATA_ACQUISITION.md`.

### Verify a P1 seal result
```bash
python reproducibility/verify_p1_rebuild.py --seal-pack /path/to/AUTOGREY_V2_P1_FINAL_REALBENCH3_SEAL_PACK_2026-09-16.zip
```
This is a byte/count verification gate; it is not a recreated reservation algorithm.

### Python environment preflight
```bash
python reproducibility/environment_preflight.py
```
A mismatch is expected to return nonzero rather than silently accepting a different environment.

### R environment preflight
After restoring R 4.6.1 + the frozen package lock + final LP64 OpenBLAS runtime:
```bash
Rscript reproducibility/environment_preflight.R
```

### OpenBLAS reconstruction
```bash
bash reproducibility/build_openblas_0_3_30_lp64.sh /path/to/OpenBLAS-0.3.30.tar.gz
```

## Frozen boundary
- No target/Y numeric values are parsed by the acquisition or P1-verification layer.
- No P11-C scoring is performed.
- Source archives and generated data stay outside the Git tree.
- Known reconstruction gaps are explicit in `config/environments/ENVIRONMENT_RECONSTRUCTION_GAPS.md`.
