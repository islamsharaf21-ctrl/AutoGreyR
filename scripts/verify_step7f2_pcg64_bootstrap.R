options(warn = 1)
if (!requireNamespace("digest", quietly=TRUE) || !requireNamespace("jsonlite", quietly=TRUE)) stop("Packages digest and jsonlite are required", call.=FALSE)
sha <- function(p) digest::digest(file=p,algo="sha256",serialize=FALSE)
pass <- function(x, extra="") cat(sprintf("PASS %-68s%s\n",x,if(nzchar(extra)) paste0(" ",extra) else ""))
fail <- function(x, extra="") stop(sprintf("FAIL %s%s",x,if(nzchar(extra)) paste0(" ",extra) else ""),call.=FALSE)
exact <- function(label,a,b) { if(!identical(a,b)) fail(label,paste0("actual=",paste(a,collapse=",")," expected=",paste(b,collapse=","))); pass(label) }
near <- function(label,a,b,tol=5e-12) { d=max(abs(as.double(a)-as.double(b))); if(!is.finite(d)||d>tol) fail(label,sprintf("max_abs=%.17g tol=%.17g",d,tol)); pass(label,sprintf("max_abs=%.3e",d)) }

# Source the closed deterministic scoring stack and exact Python launcher bridge.
for (p in c("R/01_utils.R","R/04_mase.R","R/05_grey_common.R","R/10_v1_rf_bridge.R","R/15_realbench2_target_scoring.R","R/16_bootstrap.R")) source(p,local=.GlobalEnv)
A <- jsonlite::fromJSON("AUTOGREY_STEP7F2_ASSERTIONS.json",simplifyVector=FALSE)
O <- jsonlite::fromJSON("AUTOGREY_STEP7F2_ORACLE_AUDIT.json",simplifyVector=FALSE)
R5 <- jsonlite::fromJSON("reference/frozen_step5f/AUTOGREY_REALBENCH2_RESULTS_STEP5F.json",simplifyVector=FALSE)

# Frozen lineage / source preservation.
exact("decision_oracle_sha256",sha("reference/frozen_step7f1/AUTOGREY_STEP7F1_DECISIONS_ORACLE.csv"),as.character(A$frozen$decision_sha256))
exact("frozen_step5f_bootstrap_sha256",sha("reference/frozen_step5f/AUTOGREY_REALBENCH2_BOOTSTRAP_STEP5F.csv"),as.character(A$frozen$bootstrap_sha256))
exact("frozen_step5f_results_sha256",sha("reference/frozen_step5f/AUTOGREY_REALBENCH2_RESULTS_STEP5F.json"),as.character(A$frozen$step5f_results_sha256))
exact("preserve_06_structural_groups.R",sha("R/06_structural_groups.R"),"3c8dfb520d7409c6bf6dfd93a74aecb6a0281e39e4797de0ed6f49b9d059f188")
exact("preserve_07_eligibility_collision.R",sha("R/07_eligibility_collision.R"),"ec10d3b12120ef36c51167721f890bbee93c5e3ad08b85b7bf0ce9a2d3ed7409")
exact("preserve_08_features.R",sha("R/08_features.R"),"30dbb8b2b19f6b6cde51fb7d5da3e51ced51004d8a973986107c3724be2e28f4")
exact("preserve_09_v1_preprocess.R",sha("R/09_v1_preprocess.R"),"5a37921120fe2a9db910deaf68244b0a675fc3c6d0ec2cb8dc02ed95e85318f5")
exact("preserve_10_v1_rf_bridge.R",sha("R/10_v1_rf_bridge.R"),"a64ea65d477b88b70f654398831c169bb7c649ceb4432ee373d2d3077dd18d0b")
exact("preserve_11_v1_selector.R",sha("R/11_v1_selector.R"),"4892929fed7b8b62bb6b1009192a6777e04e9bcccc9785a61b0b3776ff07b828")
exact("preserve_12_global_rank.R",sha("R/12_global_rank.R"),"fb18da88a3dcee86e97b050dc053679c5c54878855a4152bd4cc1e9201be0ebd")
exact("preserve_13_realbench2_pretarget.R",sha("R/13_realbench2_pretarget.R"),"a0f584c784cfd86d66926cdaa40ea63489efda67c45ff5d14aab04327dbe2271")
exact("preserve_14_step7e2_canonical_bridge.R",sha("R/14_step7e2_canonical_bridge.R"),"7c773506d8f6a5436192f98010d8b8678610d2beb5230213ce8095ee46e75192")
exact("preserve_step7f1_scoring_source",sha("R/15_realbench2_target_scoring.R"),as.character(A$frozen$step7f1_source_sha256))
exact("step7f2_python_bridge_sha256",sha("reference/python/ag_step7f2_pcg64_bootstrap.py"),as.character(A$frozen$bridge_sha256))
exact("step7f2_R16_sha256",sha("R/16_bootstrap.R"),as.character(A$frozen$r16_sha256))
# Core contract bound to original Step5F result/lock.
exact("bootstrap_replicates_4000",as.integer(R5$bootstrap$replicates),4000L)
exact("bootstrap_seed_46073",as.integer(R5$bootstrap$seed),46073L)
exact("bootstrap_type",as.character(R5$bootstrap$type),"paired parent-cluster; one task per parent")
exact("bootstrap_ci_method",as.character(R5$bootstrap$ci_method),"percentile 95%, numpy quantile linear")
exact("step5f_final_mean_pass",isTRUE(R5$final_gate$mean_pass),TRUE)
exact("step5f_final_tail_pass",isTRUE(R5$final_gate$tail_pass),TRUE)
exact("step5f_final_overall_pass",isTRUE(R5$final_gate$overall_robust_superiority),TRUE)

# No native R RNG is permitted for the canonical PCG64 experiment.
r16txt <- paste(readLines("R/16_bootstrap.R",warn=FALSE),collapse="\n")
for (needle in c("sample(","sample.int(","runif(","rnorm(","set.seed(","RNGkind(")) if(grepl(needle,r16txt,fixed=TRUE)) fail("no_native_R_rng_source_guard",needle)
pass("no_native_R_rng_source_guard")

cat("INFO checking frozen Python/NumPy environment for PCG64 bootstrap...\n")
env <- ag_rf_check_environment()
cat(sprintf("INFO python=%s numpy=%s sklearn=%s launcher=%s\n",env$python,env$numpy,env$scikit_learn,env$launcher_source))
exact("python_version_frozen",as.character(env$python),"3.13.5")
exact("numpy_version_frozen",as.character(env$numpy),"2.3.5")
exact("sklearn_version_frozen",as.character(env$scikit_learn),"1.8.0")

cat("\n=== STEP 7F2 DETERMINISTIC INPUT RECHECK ===\n")
# Re-run Step7F1 deterministic scoring so the bootstrap is not accepted on an unchecked input lineage.
S <- ag_step7f1_score_frozen_targets(verbose=FALSE)
refd <- utils::read.csv("reference/frozen_step7f1/AUTOGREY_STEP7F1_DECISIONS_ORACLE.csv",stringsAsFactors=FALSE,check.names=FALSE,na.strings=c(""))
exact("step7f1_recheck_rows_2496",nrow(S$decisions),2496L)
exact("step7f1_recheck_parent_ids",as.character(S$decisions$parent_id),as.character(refd$parent_id))
near("step7f1_recheck_v1_regret",S$decisions$v1_regret,refd$v1_regret,5e-12)
near("step7f1_recheck_global_regret",S$decisions$global_regret,refd$global_regret,5e-12)
near("step7f1_recheck_oracle_mase",S$decisions$eligible_oracle_mase,refd$eligible_oracle_mase,5e-12)

cat("\n=== STEP 7F2 EXACT NUMPY PCG64 BOOTSTRAP ===\n")
B <- ag_step7f2_run_pcg64_bootstrap()
exact("bridge_status",as.character(B$summary$status),"PASS")
exact("bridge_rng",as.character(B$summary$rng),"numpy.random.default_rng")
exact("bridge_bit_generator",as.character(B$summary$bit_generator),"PCG64")
exact("bridge_seed",as.integer(B$summary$seed),46073L)
exact("bridge_replicates",as.integer(B$summary$replicates),4000L)
exact("bridge_n_parents",as.integer(B$summary$n_parents),2496L)
exact("bridge_decision_input_sha256",as.character(B$summary$decision_input_sha256),as.character(A$frozen$decision_sha256))
exact("bridge_bootstrap_csv_sha256",as.character(B$summary$bootstrap_csv_sha256),as.character(A$frozen$bootstrap_sha256))
exact("R_received_bootstrap_csv_sha256",as.character(B$hashes$csv_sha256),as.character(A$frozen$bootstrap_sha256))
exact("bootstrap_rows_4000",nrow(B$data),4000L)
exact("replicate_ids_1_to_4000",as.integer(B$data$replicate),seq_len(4000L))
# Exact RNG-stream fingerprints for the first 12 parent-index arrays.
exact("first12_PCG64_index_hashes",unlist(B$summary$first12_index_i64le_sha256,use.names=FALSE),unlist(O$first12_index_i64le_sha256,use.names=FALSE))
# First replicates give readable numeric fingerprints in addition to whole-file SHA.
near("first3_mean_delta",unlist(B$summary$first3_mean_delta),unlist(O$first3_mean_delta),0)
near("first3_cvar90_delta",unlist(B$summary$first3_cvar90_delta),unlist(O$first3_cvar90_delta),0)
near("mean_delta_ci95",unlist(B$summary$mean_delta_ci95),unlist(A$frozen_ci$mean_delta_ci95),5e-15)
near("cvar90_delta_ci95",unlist(B$summary$cvar90_delta_ci95),unlist(A$frozen_ci$cvar90_delta_ci95),5e-15)
exact("mean_rule_pass",isTRUE(B$summary$mean_pass),TRUE)
exact("tail_rule_pass",isTRUE(B$summary$tail_pass),TRUE)
exact("overall_robust_superiority",isTRUE(B$summary$overall_robust_superiority),TRUE)

# Fresh-process repeat: exact whole-bootstrap CSV SHA must reproduce again.
cat("INFO repeating full 4000-replicate PCG64 bootstrap in a fresh Python process...\n")
B2 <- ag_step7f2_run_pcg64_bootstrap()
exact("repeat_bootstrap_csv_sha256",as.character(B2$summary$bootstrap_csv_sha256),as.character(B$summary$bootstrap_csv_sha256))
exact("repeat_first12_PCG64_index_hashes",unlist(B2$summary$first12_index_i64le_sha256,use.names=FALSE),unlist(B$summary$first12_index_i64le_sha256,use.names=FALSE))
near("repeat_mean_delta_ci95",unlist(B2$summary$mean_delta_ci95),unlist(B$summary$mean_delta_ci95),0)
near("repeat_cvar90_delta_ci95",unlist(B2$summary$cvar90_delta_ci95),unlist(B$summary$cvar90_delta_ci95),0)

# Persist R-facing audit copies. The canonical CSV bytes are written exactly as returned by Python.
dir.create("outputs",showWarnings=FALSE)
writeBin(B$csv_raw,"outputs/AUTOGREY_STEP7F2_BOOTSTRAP_R.csv")
summary_out <- list(
 checkpoint="STEP7F2_PCG64_BOOTSTRAP",status="PASS",replicates=4000L,seed=46073L,
 rng="numpy.random.default_rng / PCG64",bootstrap_csv_sha256=as.character(B$summary$bootstrap_csv_sha256),
 mean_delta_ci95=unlist(B$summary$mean_delta_ci95),cvar90_delta_ci95=unlist(B$summary$cvar90_delta_ci95),
 mean_pass=TRUE,tail_pass=TRUE,overall_robust_superiority=TRUE,
 step7g_started=FALSE
)
jsonlite::write_json(summary_out,"outputs/AUTOGREY_STEP7F2_BOOTSTRAP_R.json",pretty=TRUE,auto_unbox=TRUE,digits=17)
exact("output_bootstrap_bytes_preserved",sha("outputs/AUTOGREY_STEP7F2_BOOTSTRAP_R.csv"),as.character(A$frozen$bootstrap_sha256))
pass("step7f2_outputs_written")
cat(sprintf("INFO mean delta CI95=[%.15f, %.15f]\n",B$summary$mean_delta_ci95[[1]],B$summary$mean_delta_ci95[[2]]))
cat(sprintf("INFO CVaR90 delta CI95=[%.15f, %.15f]\n",B$summary$cvar90_delta_ci95[[1]],B$summary$cvar90_delta_ci95[[2]]))
cat("INFO Both frozen inferential gates pass; Step7G release assembly remains NOT STARTED.\n\n")
cat("STEP7F2_PCG64_BOOTSTRAP_PARITY: PASS\n")
