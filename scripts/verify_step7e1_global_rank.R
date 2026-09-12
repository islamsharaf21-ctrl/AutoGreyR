# AutoGrey Step 7E1 — GLOBAL_RANK_V2 parity verifier.
options(warn = 1)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required")
if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required")
source("R/08_features.R", local = .GlobalEnv)
source("R/09_v1_preprocess.R", local = .GlobalEnv)
source("R/11_v1_selector.R", local = .GlobalEnv)
source("R/12_global_rank.R", local = .GlobalEnv)
sha256_file <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
pass <- function(n, d="") cat(sprintf("PASS %-68s%s\n", n, if(nzchar(d)) paste0(" ",d) else ""))
assert_true <- function(n,x,d="") {if(!isTRUE(x)) stop(sprintf("FAIL %s%s",n,if(nzchar(d)) paste0(": ",d) else ""),call.=FALSE);pass(n,d)}
assert_equal <- function(n,a,e) {if(!identical(a,e)) stop(sprintf("FAIL %s",n),call.=FALSE);pass(n)}
assert_close <- function(n,a,e,tol=1e-12) {a<-as.double(a);e<-as.double(e); if(length(a)!=length(e)) stop(sprintf("FAIL %s length",n),call.=FALSE); d<-if(length(a))max(abs(a-e)) else 0; if(!is.finite(d)||d>tol) stop(sprintf("FAIL %s max_abs=%.17g > %.17g",n,d,tol),call.=FALSE);pass(n,sprintf("max_abs=%.3e",d))}
assert_rel <- function(n,a,e,rtol=2e-12) {a<-as.double(a);e<-as.double(e); if(length(a)!=length(e)) stop(sprintf("FAIL %s length",n),call.=FALSE); den<-pmax(1,abs(e)); d<-if(length(a))max(abs(a-e)/den) else 0; if(!is.finite(d)||d>rtol) stop(sprintf("FAIL %s max_rel=%.17g > %.17g",n,d,rtol),call.=FALSE);pass(n,sprintf("max_rel=%.3e",d))}
strvec <- function(x) as.character(unlist(x,use.names=FALSE))
numvec <- function(x) as.double(unlist(x,use.names=FALSE))
EXPECTED <- list(
 selector="a5f6e6914809bcde3667c96165984a218595c92c4cbf1d98ff4b23de50be2d23",
 action="5e943ce10c601187d46dd0f77e9059aee29c7e2710d1d8ff5acf779787983a99",
 labels="77e202112c8d3de45aeebfdbe6a4c8d1ac9b725aac598af5974d46a3f5be4631",
 r11="4892929fed7b8b62bb6b1009192a6777e04e9bcccc9785a61b0b3776ff07b828",
 global="8e2e37df62383285922fa6e887aefcd2143ac0653a7b6e39602637fec1870daa"
)
assert_equal("canonical_selector_source_sha256",sha256_file("reference/python/autogrey_v2_search_step5db_r2.py"),EXPECTED$selector)
assert_equal("frozen_action_table_sha256",sha256_file("reference/frozen/AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv"),EXPECTED$action)
assert_equal("frozen_train_labels_sha256",sha256_file("reference/frozen/AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv"),EXPECTED$labels)
assert_equal("step7d2_v1_selector_source_preservation",sha256_file("R/11_v1_selector.R"),EXPECTED$r11)
assert_equal("canonical_global_oof_sha256",sha256_file("reference/frozen/AUTOGREY_V2_GLOBAL_OOF_STEP5D_B_R2.json"),EXPECTED$global)
oracle <- jsonlite::fromJSON("inst/extdata/global_rank_reference_fixture_step7e1.json",simplifyVector=FALSE)
assert_equal("oracle_checkpoint",oracle$checkpoint,"STEP7E1_GLOBAL_RANK_V2_PARITY")
assert_true("global_support_floor_30",AG_GLOBAL_SUPPORT_MIN_PARENTS==30L)
assert_true("global_has_no_rf_or_features",identical(oracle$global_contract$rf_used,FALSE)&&identical(oracle$global_contract$features_used,FALSE))
cat("INFO rebuilding frozen TRAIN arrays for GLOBAL_RANK_V2...\n")
dat <- ag_v1_load_frozen_train()
assert_true("train_action_rows_18107",length(dat$parent)==18107L)
assert_true("train_parents_2070",length(dat$parents)==2070L)
# Support-floor semantic fixture: 29 parents rejected, 30 accepted.
sp <- c(paste0("a",seq_len(29)),paste0("b",seq_len(30)))
gi <- c(rep(1L,29),rep(2L,30)); rr<-c(rep(1,29),rep(2,30)); ww<-rep(1,length(sp))
sts <- ag_global_group_stats(sp,gi,rr,ww,seq_along(sp))
assert_true("support_29_rejected",is.na(sts$means[1]))
assert_close("support_30_accepted_mean",sts$means[2],2,0)
# Exact and near-tie semantics.
m <- rep(NA_real_,10); m[4]<-0.5;m[6]<-0.5
z <- ag_global_choose(c(6L,4L),m); assert_equal("exact_tie_lower_frozen_group_index",z$group,"SG04_BERNOULLI")
m[4]<-0.5000000000001;m[6]<-0.5
z <- ag_global_choose(c(4L,6L),m); assert_equal("near_but_not_equal_no_tolerance_tie",z$group,"SG06_CONFORMABLE")
cat("\n=== GLOBAL_RANK_V2 OOF REPRODUCTION ===\n")
g <- ag_global_oof(dat,verbose=TRUE)
can <- jsonlite::fromJSON("reference/frozen/AUTOGREY_V2_GLOBAL_OOF_STEP5D_B_R2.json",simplifyVector=FALSE)
cd <- can$decisions
cp <- vapply(cd,`[[`,character(1),"parent_id"); cf<-as.integer(vapply(cd,`[[`,numeric(1),"fold")); cs<-as.integer(vapply(cd,`[[`,numeric(1),"supported")); cc<-vapply(cd,`[[`,character(1),"choice"); cr<-as.double(vapply(cd,`[[`,numeric(1),"regret"))
assert_equal("global_parent_ids_2070_exact",g$decisions$parent_id,cp)
assert_equal("global_fold_identity_exact",g$decisions$fold,cf)
assert_equal("global_support_identity_exact",g$decisions$supported,cs)
assert_equal("global_choices_2070_of_2070_exact",g$decisions$choice,cc)
assert_close("global_regret_identity",g$decisions$regret,cr,0)
met <- ag_global_metrics_core(g$decisions); cm<-can$metrics
assert_true("global_supported_2070",met$n_supported==2070L)
for(n in c("support_coverage","mean_regret","median_regret","cvar90","p90_regret","zero_regret_rate")) assert_close(paste0("global_metric_",n),met[[n]],as.double(cm[[n]]),1e-12)
want_counts <- setNames(integer(10),AG_V1_GROUPS); for(n in names(cm$selection_counts)) want_counts[n]<-as.integer(cm$selection_counts[[n]])
assert_equal("global_selection_counts_exact",met$selection_counts,want_counts)
# Fold-level means/ranks/support from independent Python oracle.
for(f in 0:4){o<-oracle$fold_oracle[[f+1L]]; a<-g$fold_audit[[f+1L]]; assert_equal(sprintf("fold%d_rank_exact",f),as.character(a$rank),strvec(o$rank)); ws<-as.integer(unlist(o$train_parent_support[AG_V1_GROUPS],use.names=FALSE)); assert_equal(sprintf("fold%d_support_exact",f),as.integer(a$support),ws); wm<-as.double(unlist(o$weighted_mean_regret[AG_V1_GROUPS],use.names=FALSE)); assert_rel(sprintf("fold%d_weighted_means",f),a$means,wm,2e-12)}
cat(sprintf("INFO GLOBAL OOF mean=%.15f CVaR90=%.15f p90=%.15f\n",met$mean_regret,met$cvar90,met$p90_regret))
cat("\n=== FULL-TRAIN GLOBAL RANK FOR PRETARGET HANDOFF ===\n")
ft <- ag_global_full_train_rank(dat); fo<-oracle$full_train_rank
assert_equal("full_train_rank_exact",as.character(ft$rank),strvec(fo$rank))
assert_equal("full_train_support_exact",as.integer(ft$support),as.integer(unlist(fo$train_parent_support[AG_V1_GROUPS],use.names=FALSE)))
assert_rel("full_train_weighted_means",ft$means,as.double(unlist(fo$weighted_mean_regret[AG_V1_GROUPS],use.names=FALSE)),2e-12)
cat(sprintf("INFO full TRAIN rank: %s\n",paste(ft$rank,collapse=" < ")))
dir.create("outputs",showWarnings=FALSE)
utils::write.csv(g$decisions,"outputs/AUTOGREY_STEP7E1_GLOBAL_OOF_DECISIONS_R.csv",row.names=FALSE,na="")
jsonlite::write_json(list(version=AG_GLOBAL_RANK_VERSION,metrics=met,full_train_rank=list(rank=ft$rank,means=as.list(ft$means),support=as.list(ft$support))),"outputs/AUTOGREY_STEP7E1_GLOBAL_METRICS_AND_RANK_R.json",auto_unbox=TRUE,pretty=TRUE,digits=17,null="null")
cat("INFO wrote Step7E1 outputs.\n")
cat("INFO REALBENCH2 PRETARGET and target opening remain NOT STARTED.\n")
cat("\nSTEP7E1_GLOBAL_RANK_V2_PARITY: PASS\n")
