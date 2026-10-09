# THIRD-PARTY NOTICES

This file records third-party components and data sources referenced by the AutoGreyR V2 public-source candidate. It is not a substitute for the upstream licenses or terms.

## REALBENCH3 source data

See `DATA_NOTICE.md` and `docs/REALBENCH3_RIGHTS_REGISTER.csv`.

### Monash Time Series Forecasting Repository
Creators include Rakshitha Godahewa, Christoph Bergmeir, Geoff Webb, Rob J. Hyndman and Pablo Montero-Manso.

The Monash distribution is labeled CC BY 4.0. AutoGrey does not bundle its data archives.

### Car Parts / Hospital
Source lineage: R package `expsmooth`, version 2.3 lineage. CRAN package metadata states GPL (>=2). AutoGrey cites and acquires externally; it does not redistribute those source archives.

### Electricity
Source lineage includes UCI ElectricityLoadDiagrams20112014 and Lai et al. The current UCI dataset page states CC BY 4.0.

### Traffic
Source lineage includes Caltrans Performance Measurement System (PeMS) and Lai et al. AutoGrey does not republish the source traffic archive.

### Weather
Source lineage includes the Australian Bureau of Meteorology, accessed by the source archive through the `bomrang` lineage. Bureau data can carry content-specific terms; AutoGrey does not republish the source weather archive.

## Runtime dependencies

AutoGreyR depends on third-party Python and R packages. Those packages retain their own upstream licenses and are not relicensed by AutoGreyR.

The public environment files pin or document versions for reproduction. They do not vendor third-party wheels/packages in this source tree.

## OpenBLAS

The R environment reconstruction uses OpenBLAS 0.3.30 LP64 in the frozen executed configuration. OpenBLAS retains its upstream license.

## No endorsement

Reference to third-party names, repositories, packages or datasets does not imply endorsement of AutoGreyR by those parties.
