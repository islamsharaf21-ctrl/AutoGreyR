# R5-B3 Data-Rights Gate

## Gate verdict

### Public source Git repository
**PASS — SOURCE-ONLY / NO THIRD-PARTY DATA REDISTRIBUTION**

The repository may publish acquisition URLs/DOIs, citations, metadata, frozen checksums and deterministic verification tooling.

### Third-party source-archive redistribution
**HOLD**

AutoGrey must not upload the five REALBENCH3 source ZIP archives into the Git repository or ordinary software release assets under the AutoGrey software license.

### Derived benchmark numeric binaries
**HOLD / CONTROLLED**

The development binary, opened target binary, target index and rights-sensitive detailed evidence remain outside the public Git source tree.

## Evidence summary

1. Monash-University `monash_tsf` currently labels the repository distribution CC BY 4.0.
2. Zenodo states that reuse permission depends on each record's Rights/license.
3. UCI ElectricityLoadDiagrams20112014 currently states CC BY 4.0.
4. CRAN `expsmooth` package metadata states GPL (>=2) at package level.
5. Caltrans generally treats its own website information as public domain unless otherwise indicated, while PeMS access and content-specific terms can apply.
6. Bureau of Meteorology states that not all material is licensed identically and some datasets require specific terms or agreements.

Because the upstream chain is heterogeneous, non-redistribution is the safer reproducibility design.

## Operational rule

`reproducibility/acquire_realbench3.py` remains the public acquisition boundary. It must capture current rights/license metadata from the upstream API when available and reject byte identities that do not match the frozen source hashes.
