# AutoGreyR V2 — Release Status

**Candidate:** `v2.0.0-rc1`  
**Checkpoint:** R5-B5 — rc1 package / tag decision  
**Tag decision:** **GO / AUTHORIZED**  
**Git tag actually created in this archive:** no — an archive has no canonical Git history  
**Stable:** no  
**Public source-only rc1 release:** authorized for tagging/publishing from the canonical repository commit that exactly matches this tree

## Scientific state

P11-C is **FAIL / CLOSED**, scored once. The release must not be presented as an externally validated performance improvement over immutable AutoGreyR `v1.0.0`.

No retrospective tuning, deletion, winsorization, clipping, selector/comparator replacement, gate change, bootstrap change or rescoring is authorized.

## Release engineering

### PASS / CLOSED
- R5-B0 source/private split.
- R5-B1 clean public source tree.
- R5-B2 deterministic acquisition + environment locks.
- R5-B3 public documentation + Apache-2.0 + source-only data-rights model.
- R5-B4 native Windows/WSL clean-room verification.
- R5-B5 rc1 package construction and tag-readiness verification.

### Disclosed limitations — do not silently repair
- exact original P1 end-to-end acquisition/reservation runner remains unrecovered;
- historical P6 pip-freeze/wheel bytes remain unrecovered;
- exact historical `statsmodels` version remains `UNRESOLVED_DO_NOT_INVENT`;
- P11-B irreversible-opening provenance marker remains unrecovered and must never be recreated from prose.

## Data-rights state

The repository does not bundle or redistribute REALBENCH3 source archives or derived target/development binaries.

R5-B4 captured `cc-by-4.0` at record level for all five frozen Zenodo records and verified all five frozen source-byte SHA-256 identities. AutoGrey keeps the conservative source-only/no-third-party-byte-redistribution model because upstream provenance is heterogeneous.

## Tag decision

**AUTHORIZED TAG:** `v2.0.0-rc1`

The tag must point only to a canonical Git commit whose working tree exactly matches the authoritative rc1 manifest.

**NOT AUTHORIZED:** stable tag `v2.0.0`.

No tag is fabricated inside this ZIP because doing so would create unrelated Git history.
