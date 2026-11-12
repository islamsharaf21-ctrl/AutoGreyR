# G3S review only — AutoGreyR V1 experimental CLI

**NOT RELEASED; NO FORECASTING SUPERIORITY CLAIM; NOT THE FROZEN V1 RELEASE.**

This subtree is a *review-only, unmerged* copy of
`AUTOGREYR_V1_EXPERIMENTAL_CLI_G3S_SINGLE_CORRECTION_2026-11-12.zip`
with candidate ZIP SHA-256:

`924522d516a6c0a5f1a320a2780b468f8f24545abacea49ea05b580df92c05f1`

It is stored here for an external reviewer to assess source only.
No review sign-off has been obtained; source contents and historical test logs do not prove runtime usability.

Read `EXTERNAL_REVIEWER_BRIEF.md`, `G1_CLI_CONTRACT.md`, `ACCEPTANCE_RUNBOOK.md`,
`RELEASE_STATUS.md`, `agv1_cli.py`, `tests/test_agv1_cli.py`, and both unchanged
internal experimental scripts. The original frozen V1 archive is **not** committed
here; its expected SHA-256 is
`e3e78ecdb670c9ed29af875d0b41b5aaf7506eb04844d8d193d62b890307720f`.

Do not modify the original release, execute protected models, or initiate
acceptance RUN-01 through RUN-05. A separately attributable reviewer decision
`APPROVE`, `BLOCK`, or `CANNOT VERIFY` is required before that next gate.

The completed NN5 Weekly R3 external pilot on 16 series had mean MASE
1.9000083 for the experimental selector versus 1.5556718 for the
precommitted baseline; **prespecified superiority gate NOT MET**.
Formal AutoGrey V2 P11-C FAIL/CLOSED, frozen V3 SafeSelect, and GreyModelLabR
are different projects.

The copy contains no original 50 MB V1 archive, no NN5 targets, and no
new forecast outputs beyond the documented historical synthetic reference.
