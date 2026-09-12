source("scripts/_release_utils.R", local=.GlobalEnv)
ag_run_release_stage("scripts/verify_step7e2_realbench2_pretarget.R", "STEP7E2_REALBENCH2_PRETARGET_CROSSPLATFORM_PARITY_R8: PASS", "step7e2_realbench2_pretarget.log")
cat("AUTOGREY_REPRODUCE_REALBENCH2_PRETARGET: PASS\n")
