# REALBENCH3 acquisition and local verification

## Public-release boundary
AutoGreyR does **not** bundle the five third-party REALBENCH3 source ZIP archives or the derived development/target binary payloads in the Git source tree. Record-level license/rights capture remains a release gate. The acquisition layer therefore downloads only into an **external cache path supplied by the user** and refuses an archive unless its SHA-256 matches the frozen P1 source identity.

## Frozen source identities
`reproducibility/source_registry.json` records the exact DOI, Zenodo record id, source ZIP filename, frozen P1 SHA-256, and expected TSF member for:
- car-parts monthly — DOI `10.5281/zenodo.4656021`;
- electricity hourly — DOI `10.5281/zenodo.4656140`;
- hospital monthly — DOI `10.5281/zenodo.4656014`;
- traffic hourly — DOI `10.5281/zenodo.4656132`;
- weather daily — DOI `10.5281/zenodo.4654822`.

The four repository MD5 values that were independently visible from the corresponding Zenodo record pages on 2026-10-09 are recorded as an early metadata gate. The hospital record-level current MD5 was not independently exposed by the retrieval path used for R5-B2, so its field remains `null`; **the frozen P1 SHA-256 remains the authoritative byte identity for every source**.

## Usage
Metadata-only inspection (default; writes no archive bytes):

```bash
python reproducibility/acquire_realbench3.py \
  --cache-dir /path/outside/the/repository/autogrey-cache
```

Explicit download + frozen byte verification:

```bash
python reproducibility/acquire_realbench3.py \
  --cache-dir /path/outside/the/repository/autogrey-cache \
  --download
```

The script:
1. requests the exact Zenodo record id;
2. checks DOI and expected file name;
3. captures the record-level rights/license identifiers returned by the API;
4. checks a frozen/current MD5 when independently verified in the registry;
5. downloads to a temporary `.part` file;
6. checks the full archive SHA-256 against the P1 frozen identity;
7. verifies that the expected TSF member exists;
8. records evidence without parsing TSF numeric values.

A failed hash causes the downloaded archive to be rejected and removed.

## P1 verification boundary
`reproducibility/verify_p1_rebuild.py` verifies an independently reproduced P1 seal output against:
- clean-set SHA-256 `C496055A807B9D37692A6756A137E8EF93D75E962001B42B93A9A13823DBDB7B`;
- refusal-ledger SHA-256 `606509431D83166E89E9D166FBFEC6B393A896D18B2614F45FCCB9571DD7D795`;
- 4,781 P1-clean parents;
- 19 refusals;
- frozen P1 source/horizon counts;
- source-archive identities;
- target-parse flags remaining false.

This is deliberately **not** presented as a recreated P1 reservation/contamination implementation. The exact original P1 runner is not in the recovered public-source authority and is not reconstructed from prose. Full source-to-P1 clean-room reproduction therefore remains a release blocker until that implementation is recovered or independently reimplemented under a separately authorized scientific-equivalence protocol.

The later deployed/scored population is 4,778 because three clean P1 parents were subsequently frozen as nondeployed. This verifier does not add them back or treat them as missing observations.
