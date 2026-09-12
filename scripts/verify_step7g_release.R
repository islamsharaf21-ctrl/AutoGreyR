options(warn = 1)

if (!requireNamespace("jsonlite", quietly = TRUE) ||
    !requireNamespace("digest", quietly = TRUE)) {
  stop("jsonlite and digest are required", call. = FALSE)
}

source("R/02_hash_gate.R", local = .GlobalEnv)
source("R/17_assertions.R", local = .GlobalEnv)

cat("=== AUTOGREY PUBLIC RELEASE AUDIT ===\n")

# -----------------------------------------------------------------------------
# 1) Frozen scientific critical-file hash contract.
# -----------------------------------------------------------------------------
H <- jsonlite::fromJSON("inst/extdata/expected_hashes.json", simplifyVector = FALSE)

for (p in names(H$critical_files)) {
  ag_release_expect(file.exists(p), paste0("exists_", basename(p)))
  got <- digest::digest(file = p, algo = "sha256", serialize = FALSE)
  ag_release_expect_identical(
    got,
    as.character(H$critical_files[[p]]),
    paste0("sha_", basename(p))
  )
}

# -----------------------------------------------------------------------------
# 2) Committed renv lock + actual runtime environment contract.
# -----------------------------------------------------------------------------
expected_lock_sha256 <-
  "1878fca606f6a74365baa05e7a103ee3d9f8a2a411bfc5669fadff1bc7048d59"

ag_release_expect(file.exists("renv.lock"), "renv_lock_exists")
ag_release_expect(file.exists(".Rprofile"), "rprofile_exists")
ag_release_expect(file.exists("renv/activate.R"), "renv_activate_exists")

lock_sha <- digest::digest(
  file = "renv.lock",
  algo = "sha256",
  serialize = FALSE
)
ag_release_expect_identical(
  lock_sha,
  expected_lock_sha256,
  "renv_lock_sha256_frozen"
)

L <- jsonlite::fromJSON("renv.lock", simplifyVector = FALSE)
ag_release_expect_identical(as.character(L$R$Version), "4.6.1", "renv_lock_R_4_6_1")
ag_release_expect_identical(as.character(getRversion()), "4.6.1", "runtime_R_4_6_1")

required_pkgs <- c(
  renv = "1.2.3",
  jsonlite = "2.0.0",
  digest = "0.6.39",
  testthat = "3.3.2"
)

for (nm in names(required_pkgs)) {
  rec <- L$Packages[[nm]]
  ag_release_expect(!is.null(rec), paste0("renv_has_", nm))
  ag_release_expect_identical(
    as.character(rec$Version),
    unname(required_pkgs[[nm]]),
    paste0("renv_lock_version_", nm)
  )

  ag_release_expect(
    requireNamespace(nm, quietly = TRUE),
    paste0("runtime_package_available_", nm)
  )
  ag_release_expect_identical(
    as.character(utils::packageVersion(nm)),
    unname(required_pkgs[[nm]]),
    paste0("runtime_package_version_", nm)
  )
}

rprofile_txt <- paste(readLines(".Rprofile", warn = FALSE), collapse = "\n")
ag_release_expect(
  grepl('source("renv/activate.R")', rprofile_txt, fixed = TRUE),
  "rprofile_activates_renv"
)

# -----------------------------------------------------------------------------
# 3) Integrated stage logs must carry their terminal PASS marker.
# -----------------------------------------------------------------------------
required_logs <- list(
  "outputs/logs/initialize_renv.log" = "AUTOGREY_RENV_LOCK: PASS",
  "outputs/logs/release_environment.log" = "AUTOGREY_RELEASE_ENVIRONMENT: PASS",
  "outputs/logs/unit_tests.log" = "AUTOGREY_UNIT_TESTS: PASS",
  "outputs/logs/reproduce_train_r2.log" = "AUTOGREY_REPRODUCE_TRAIN_R2: PASS",
  "outputs/logs/reproduce_realbench2_pretarget.log" = "AUTOGREY_REPRODUCE_REALBENCH2_PRETARGET: PASS",
  "outputs/logs/reproduce_realbench2_final.log" = "AUTOGREY_REPRODUCE_REALBENCH2_FINAL: PASS"
)

for (p in names(required_logs)) {
  ag_release_expect(file.exists(p), paste0("log_exists_", basename(p)))
  txt <- readLines(p, warn = FALSE)
  ag_release_expect(
    any(grepl(required_logs[[p]], txt, fixed = TRUE)),
    paste0("log_marker_", basename(p))
  )
}

# -----------------------------------------------------------------------------
# 4) Major frozen scientific checkpoint markers must remain visible.
# -----------------------------------------------------------------------------
all_logs <- unlist(
  lapply(names(required_logs), readLines, warn = FALSE),
  use.names = FALSE
)

markers <- c(
  "STEP7D2_FULL_V1_TRAIN_R2_PARITY: PASS",
  "STEP7E1_GLOBAL_RANK_V2_PARITY: PASS",
  "STEP7E2_REALBENCH2_PRETARGET_CROSSPLATFORM_PARITY_R8: PASS",
  "STEP7F1_FROZEN_TARGET_SCORING_PARITY: PASS",
  "STEP7F2_PCG64_BOOTSTRAP_PARITY: PASS"
)

for (m in markers) {
  ag_release_expect(
    any(grepl(m, all_logs, fixed = TRUE)),
    paste0("checkpoint_", gsub("[^A-Za-z0-9]+", "_", m))
  )
}

# -----------------------------------------------------------------------------
# 5) Final deterministic/inferential outputs and frozen REALBENCH2 result.
# -----------------------------------------------------------------------------
bootstrap_path <- "outputs/AUTOGREY_STEP7F2_BOOTSTRAP_R.csv"
expected_bootstrap_sha256 <-
  "b78899ea38552ca546746a7f80ef7c5b9b28e9f8fc31ed45a9bde9faa11bb5fa"

ag_release_expect(file.exists(bootstrap_path), "step7f2_bootstrap_output_exists")
ag_release_expect_identical(
  digest::digest(file = bootstrap_path, algo = "sha256", serialize = FALSE),
  expected_bootstrap_sha256,
  "step7f2_bootstrap_output_sha"
)

E <- jsonlite::fromJSON(
  "inst/extdata/expected_step5f_results.json",
  simplifyVector = FALSE
)
F <- jsonlite::fromJSON(
  "reference/frozen_step5f/AUTOGREY_REALBENCH2_RESULTS_STEP5F.json",
  simplifyVector = FALSE
)

ag_release_expect_identical(
  as.integer(F$reserved_parent_count),
  as.integer(E$reserved_parent_count),
  "reserved_2511"
)
ag_release_expect_identical(
  as.integer(F$actionable_parent_count),
  as.integer(E$actionable_parent_count),
  "actionable_2496"
)

ag_release_expect_near(
  F$primary_metrics$mean_regret,
  1.317290834344165,
  1e-15,
  "final_v1_mean_regret"
)
ag_release_expect_near(
  F$global_rank_v2_metrics$mean_regret,
  1.9289794121083974,
  1e-15,
  "final_global_mean_regret"
)
ag_release_expect_near(
  F$estimands$mean_regret_delta_primary_minus_global,
  -0.6116885777642325,
  1e-15,
  "final_mean_regret_delta"
)
ag_release_expect_near(
  unlist(F$bootstrap$mean_delta_ci95),
  c(-0.7414871255255626, -0.49395892999206054),
  1e-15,
  "final_mean_delta_ci"
)
ag_release_expect_near(
  F$primary_metrics$cvar90,
  8.297652381285300,
  1e-15,
  "final_v1_cvar90"
)
ag_release_expect_near(
  F$global_rank_v2_metrics$cvar90,
  11.127078832815650,
  1e-15,
  "final_global_cvar90"
)
ag_release_expect_near(
  F$estimands$cvar90_regret_delta_primary_minus_global,
  -2.8294264515303507,
  1e-15,
  "final_cvar90_delta"
)
ag_release_expect_near(
  unlist(F$bootstrap$cvar90_delta_ci95),
  c(-3.9434134806487116, -1.8567743134301962),
  1e-15,
  "final_cvar90_delta_ci"
)
ag_release_expect(
  isTRUE(F$final_gate$overall_robust_superiority),
  "final_overall_gate_true"
)

# -----------------------------------------------------------------------------
# 6) Public release metadata/documentation contract.
# -----------------------------------------------------------------------------
public_files <- c(
  "README.md",
  "REPRODUCIBILITY.md",
  "RELEASE_NOTES.md",
  "CITATION.cff",
  "DESCRIPTION",
  "LICENSE",
  "THIRD_PARTY_NOTICES.md"
)

for (p in public_files) {
  ag_release_expect(file.exists(p), paste0("public_file_", basename(p)))
}

readme_txt <- paste(readLines("README.md", warn = FALSE), collapse = "\n")
repro_txt <- paste(readLines("REPRODUCIBILITY.md", warn = FALSE), collapse = "\n")
notes_txt <- paste(readLines("RELEASE_NOTES.md", warn = FALSE), collapse = "\n")
cff_txt <- paste(readLines("CITATION.cff", warn = FALSE), collapse = "\n")
desc_txt <- paste(readLines("DESCRIPTION", warn = FALSE), collapse = "\n")
license_txt <- paste(readLines("LICENSE", warn = FALSE), collapse = "\n")
third_party_txt <- paste(readLines("THIRD_PARTY_NOTICES.md", warn = FALSE), collapse = "\n")

permitted_claim <-
  "V1 outperformed the frozen GLOBAL_RANK_V2 comparator on REALBENCH2 under the prespecified frozen protocol."

ag_release_expect(
  grepl(permitted_claim, readme_txt, fixed = TRUE),
  "readme_permitted_claim_present"
)
ag_release_expect(
  grepl("committed `renv.lock`", readme_txt, fixed = TRUE),
  "readme_committed_lock_workflow"
)
ag_release_expect(
  grepl("Normal public reproduction never regenerates or snapshots `renv.lock`.", repro_txt, fixed = TRUE),
  "repro_lock_policy_final"
)
ag_release_expect(
  !grepl("This candidate", notes_txt, fixed = TRUE),
  "release_notes_not_candidate"
)
ag_release_expect(
  grepl("license: MIT", cff_txt, fixed = TRUE),
  "citation_mit_license"
)
ag_release_expect(
  grepl('version: "1.0.0"', cff_txt, fixed = TRUE),
  "citation_version_1_0_0"
)
ag_release_expect(
  grepl("Package: AutoGreyR", desc_txt, fixed = TRUE),
  "description_package_name"
)
ag_release_expect(
  grepl("Version: 1.0.0", desc_txt, fixed = TRUE),
  "description_version_1_0_0"
)
ag_release_expect(
  grepl("License: MIT + file LICENSE", desc_txt, fixed = TRUE),
  "description_mit_license"
)
ag_release_expect(
  grepl("Islam.mah@zu.edu.eg", desc_txt, fixed = TRUE),
  "description_creator_email"
)
ag_release_expect(
  startsWith(license_txt, "MIT License"),
  "license_is_mit"
)
ag_release_expect(
  grepl("CC BY 4.0", third_party_txt, fixed = TRUE),
  "third_party_cc_by_4"
)
ag_release_expect(
  grepl("not relicensed under", third_party_txt, fixed = TRUE),
  "third_party_not_relicensed_under_mit"
)

# -----------------------------------------------------------------------------
# 7) Public release manifest.
# -----------------------------------------------------------------------------
manifest_path <- "AUTOGREY_PUBLIC_RELEASE_MANIFEST.json"
ag_release_expect(file.exists(manifest_path), "public_manifest_exists")

M <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
ag_release_expect_identical(
  as.character(M$schema_version),
  "1.0",
  "public_manifest_schema_1_0"
)
ag_release_expect_identical(
  as.character(M$release),
  "AutoGreyR 1.0.0",
  "public_manifest_release_1_0_0"
)
ag_release_expect(length(M$files) > 0L, "public_manifest_nonempty")

manifest_paths <- vapply(M$files, function(rec) as.character(rec$path), character(1L))
ag_release_expect(
  length(unique(manifest_paths)) == length(manifest_paths),
  "public_manifest_unique_paths"
)
ag_release_expect(
  !manifest_path %in% manifest_paths,
  "public_manifest_does_not_hash_itself"
)

required_manifest_paths <- c(
  "DESCRIPTION",
  "CITATION.cff",
  "LICENSE",
  "THIRD_PARTY_NOTICES.md",
  "README.md",
  "REPRODUCIBILITY.md",
  "RELEASE_NOTES.md",
  ".Rprofile",
  "renv/activate.R",
  "renv.lock",
  "scripts/initialize_renv.R",
  "scripts/_release_utils.R",
  "scripts/reproduce_all.R",
  "scripts/verify_step7g_release.R"
)

ag_release_expect(
  all(required_manifest_paths %in% manifest_paths),
  "public_manifest_required_paths_present"
)

for (rec in M$files) {
  p <- as.character(rec$path)
  ag_release_expect(file.exists(p), paste0("manifest_exists_", basename(p)))

  got <- digest::digest(file = p, algo = "sha256", serialize = FALSE)
  ag_release_expect_identical(
    got,
    as.character(rec$sha256),
    paste0("manifest_sha_", basename(p))
  )

  if (!is.null(rec$bytes)) {
    ag_release_expect_identical(
      as.numeric(file.info(p)$size),
      as.numeric(rec$bytes),
      paste0("manifest_bytes_", basename(p))
    )
  }
}

# -----------------------------------------------------------------------------
# 8) .Rbuildignore semantic contract.
# -----------------------------------------------------------------------------
ag_release_expect(file.exists(".Rbuildignore"), "rbuildignore_exists")
rbi <- trimws(readLines(".Rbuildignore", warn = FALSE))
rbi <- rbi[nzchar(rbi)]

required_rbi <- c(
  "^AutoGreyR\\.Rproj$",
  "^outputs$",
  "^reference$",
  "^docs$",
  "^renv$",
  "^renv\\.lock$",
  "^scripts$",
  "^AUTOGREY_.*$",
  "^README\\.md$",
  "^REPRODUCIBILITY\\.md$",
  "^RELEASE_NOTES\\.md$",
  "^\\.Rproj\\.user$",
  "^\\.Rprofile$",
  "^THIRD_PARTY_NOTICES\\.md$"
)

ag_release_expect(
  all(required_rbi %in% rbi),
  "rbuildignore_required_rules_preserved"
)

# -----------------------------------------------------------------------------
# 9) AutoGreyR.Rproj semantic contract.
# -----------------------------------------------------------------------------
ag_release_expect(file.exists("AutoGreyR.Rproj"), "rproj_exists")
rp <- trimws(readLines("AutoGreyR.Rproj", warn = FALSE))
rp <- rp[nzchar(rp)]

rproj_required <- c(
  "Version" = "1.0",
  "RestoreWorkspace" = "No",
  "SaveWorkspace" = "No",
  "AlwaysSaveHistory" = "No",
  "EnableCodeIndexing" = "Yes",
  "UseSpacesForTab" = "Yes",
  "NumSpacesForTab" = "2",
  "Encoding" = "UTF-8",
  "RnwWeave" = "Sweave",
  "LaTeX" = "pdfLaTeX"
)

for (nm in names(rproj_required)) {
  prefix <- paste0(nm, ":")
  hit <- rp[startsWith(rp, prefix)]
  ag_release_expect(length(hit) >= 1L, paste0("rproj_has_", nm))
  got <- trimws(substring(hit[[1L]], nchar(prefix) + 1L))
  ag_release_expect_identical(
    got,
    unname(rproj_required[[nm]]),
    paste0("rproj_value_", nm)
  )
}

# -----------------------------------------------------------------------------
# 10) Write final machine-readable public release audit.
# -----------------------------------------------------------------------------
dir.create("outputs", showWarnings = FALSE)

audit <- list(
  checkpoint = "AUTOGREY_PUBLIC_RELEASE_AUDIT",
  status = "PASS",
  release = "AutoGreyR 1.0.0",
  scientific_design_changed = FALSE,
  scientific_hash_contract = "inst/extdata/expected_hashes.json",
  environment = list(
    R = as.character(getRversion()),
    renv = as.character(utils::packageVersion("renv")),
    jsonlite = as.character(utils::packageVersion("jsonlite")),
    digest = as.character(utils::packageVersion("digest")),
    testthat = as.character(utils::packageVersion("testthat")),
    renv_lock_sha256 = lock_sha
  ),
  platform_contract = list(
    canonical = "Linux / Python 3.13.5 / NumPy 2.3.5 / frozen OpenBLAS lineage",
    windows = "qualified under Step7E2 R8 numerical contract"
  ),
  final_result = list(
    v1_mean_regret = as.numeric(F$primary_metrics$mean_regret),
    global_mean_regret = as.numeric(F$global_rank_v2_metrics$mean_regret),
    mean_delta = as.numeric(F$estimands$mean_regret_delta_primary_minus_global),
    mean_delta_ci95 = unlist(F$bootstrap$mean_delta_ci95),
    v1_cvar90 = as.numeric(F$primary_metrics$cvar90),
    global_cvar90 = as.numeric(F$global_rank_v2_metrics$cvar90),
    cvar90_delta = as.numeric(F$estimands$cvar90_regret_delta_primary_minus_global),
    cvar90_delta_ci95 = unlist(F$bootstrap$cvar90_delta_ci95),
    overall_robust_superiority = isTRUE(F$final_gate$overall_robust_superiority)
  ),
  permitted_claim = permitted_claim,
  bootstrap_sha256 = digest::digest(
    file = bootstrap_path,
    algo = "sha256",
    serialize = FALSE
  ),
  public_manifest_sha256 = digest::digest(
    file = manifest_path,
    algo = "sha256",
    serialize = FALSE
  ),
  rbuildignore_runtime_sha256 = digest::digest(
    file = ".Rbuildignore",
    algo = "sha256",
    serialize = FALSE
  ),
  rproj_runtime_sha256 = digest::digest(
    file = "AutoGreyR.Rproj",
    algo = "sha256",
    serialize = FALSE
  ),
  verifier_revision = "AUTOGREY_PUBLIC_VERIFIER_R1"
)

jsonlite::write_json(
  audit,
  "outputs/AUTOGREY_PUBLIC_RELEASE_AUDIT.json",
  pretty = TRUE,
  auto_unbox = TRUE,
  digits = 17
)

cat("AUTOGREY_PUBLIC_RELEASE_AUDIT: PASS\n")
