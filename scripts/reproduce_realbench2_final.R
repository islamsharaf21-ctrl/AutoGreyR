source("scripts/_release_utils.R", local=.GlobalEnv)
ag_run_release_stage("scripts/verify_step7f1_target_scoring.R", "STEP7F1_FROZEN_TARGET_SCORING_PARITY: PASS", "step7f1_target_scoring.log")
ag_run_release_stage("scripts/verify_step7f2_pcg64_bootstrap.R", "STEP7F2_PCG64_BOOTSTRAP_PARITY: PASS", "step7f2_pcg64_bootstrap.log")
cat("AUTOGREY_REPRODUCE_REALBENCH2_FINAL: PASS\n")
