# Manifest roles

## Authoritative for `v2.0.0-rc1`
- `PUBLIC_RELEASE_MANIFEST.sha256` — exhaustive release-file hashes except itself.
- `RC1_TAG_CONTENT_MANIFEST.sha256` — tag content identity excluding the two final hash manifests.
- `RC1_RELEASE_INVENTORY.csv` — rc1 inventory for non-final-manifest content.
- `RC1_RELEASE_CHANGE_REGISTER.csv` — R5-B5 metadata/generated changes.

## Retained lineage snapshots
`PUBLIC_TREE_INVENTORY.csv`, `PUBLIC_SOURCE_PROVENANCE.csv`, `PORTABILITY_CHANGE_REGISTER.csv`, and earlier R5-B1/R5-B2 registers remain lineage evidence. They are intentionally not rewritten to masquerade as original rc1 records.
