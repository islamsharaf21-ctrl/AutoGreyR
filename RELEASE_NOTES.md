# AutoGreyR 1.0.0 — Verified Reproduction Release
This release integrates the externally verified Step7B–Step7F2 reproduction chain into one repository and one top-level execution path.

Key release decisions:

- preserves the verified R source files for structural groups, eligibility/collisions, features, selector preprocessing, RF bridge, V1 selector, GLOBAL comparator, REALBENCH2 pretarget, target scoring, and bootstrap;
- preserves the canonical Python RF and PCG64 semantics rather than substituting non-equivalent native-R implementations;
- documents Linux as the byte-exact numerical reference and the frozen R8 Windows cross-platform qualification for SG02/SG05;
- scores the canonical forecast pack so platform numerical differences cannot alter the frozen Step5F estimand;
- treats the committed, verified R 4.6.1 `renv.lock` as the immutable environment source of truth and restores from it during reproduction;
- separates the MIT-licensed AutoGreyR software from the upstream CC BY 4.0 M4/Tourism benchmark datasets documented in `THIRD_PARTY_NOTICES.md`;
- exposes `scripts/reproduce_all.R` as the single integration entry point.

No scientific-design change is introduced in Step7G.
