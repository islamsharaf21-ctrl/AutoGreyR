# DATA NOTICE — REALBENCH3 and Third-Party Data

AutoGreyR does not own the underlying REALBENCH3 source datasets.

## Distribution policy

The public AutoGreyR source repository does **not** contain and does not redistribute:

- the five REALBENCH3 source ZIP archives;
- the derived development binary;
- the opened target binary;
- protected target indices;
- detailed rights-sensitive benchmark-derived evidence.

Instead, the repository provides:

- stable source DOIs / record identifiers;
- source filenames;
- frozen SHA-256 identities;
- visible repository MD5 checks where verified;
- citations and provenance;
- acquisition and checksum-verification tooling.

Users must obtain source records from the cited upstream repositories and comply with the applicable record/upstream terms.

## Monash distribution-level license

The Monash-University `monash_tsf` distribution currently labels the repository as Creative Commons Attribution 4.0 International (CC BY 4.0). Its dataset code also declares the Monash Time Series Forecasting Repository license as CC BY 4.0.

R5-B3 does **not** convert this distribution-level label into a legal conclusion that every upstream byte can be freely re-hosted by AutoGrey. The five datasets have heterogeneous upstream provenance.

## Frozen source records

| AutoGrey source | Frozen DOI | Upstream / provenance | AutoGrey byte redistribution |
|---|---|---|---|
| Car Parts monthly | 10.5281/zenodo.4656021 | R `expsmooth` package | NO |
| Electricity hourly | 10.5281/zenodo.4656140 | UCI ElectricityLoadDiagrams20112014 / Lai et al. | NO |
| Hospital monthly | 10.5281/zenodo.4656014 | R `expsmooth` package | NO |
| Traffic hourly | 10.5281/zenodo.4656132 | Caltrans PeMS / Lai et al. | NO |
| Weather daily | 10.5281/zenodo.4654822 | Australian Bureau of Meteorology via `bomrang` | NO |

## Upstream rights notes

- `expsmooth` package metadata states GPL (>=2) at package level. This notice does not assume that package licensing alone resolves downstream dataset redistribution.
- The current UCI ElectricityLoadDiagrams20112014 page states CC BY 4.0.
- Caltrans states that its own website information is generally considered public domain unless otherwise indicated, while PeMS access requires an account and content-specific conditions can apply.
- The Australian Bureau of Meteorology explicitly warns that not all content is licensed the same way; some content is CC BY while other data can require dataset-specific conditions or a data licence agreement.

These distinctions are why AutoGrey uses external acquisition rather than re-hosting the third-party data.

## Zenodo rights capture

Zenodo requires a license/right field for open records and states that reuse depends on the license shown in each record's Rights section. The R5-B2 acquisition script captures the record-level rights/license metadata returned by the Zenodo API at acquisition time.

During R5-B3 web review, the rendered record pages exposed the Rights section but did not expose a machine-readable license value for all five frozen pages. The release therefore does not claim an exact per-record Zenodo Rights identifier unless captured by the acquisition evidence.

## Derived AutoGrey evidence

Aggregate AutoGrey results and public-safe method/evaluation records may be distributed as AutoGrey project outputs. Detailed benchmark-derived numeric payloads remain outside the normal Git source tree unless a later rights review explicitly clears them.

## No software-license inheritance

No third-party dataset, source archive, or derived benchmark byte is licensed under the AutoGrey Apache License 2.0 merely by being referenced by this repository.
