source("scripts/_release_utils.R", local=.GlobalEnv)
ag_run_release_stage("scripts/verify_step7d2_full_v1_train.R", "STEP7D2_FULL_V1_TRAIN_R2_PARITY: PASS", "step7d2_full_v1_train.log")
ag_run_release_stage("scripts/verify_step7e1_global_rank.R", "STEP7E1_GLOBAL_RANK_V2_PARITY: PASS", "step7e1_global_rank.log")
cat("AUTOGREY_REPRODUCE_TRAIN_R2: PASS\n")
