# AutoGrey Step 7E2 — REALBENCH2 PRETARGET reproduction.
#
# Frozen chronology: the held-out suffix x[(N-h+1):N] is NEVER numeric-parsed.
# It remains an opaque character-token vector used only for missing-token checks
# and its SHA-256 commitment. Only D = x[1:(N-h)] is converted to double.
# No losses, regret, target scoring, bootstrap, or post-target fitting occurs here.

AG_RB2_PRETARGET_VERSION <- "AG_STEP7E2_REALBENCH2_PRETARGET_R_1"
AG_RB2_RAW_BUNDLE_SHA256 <- "85aac5e92b5d6b0db2299d319d096a5a4b274369cbfeabf7c79e2dc706b0f4f9"
AG_RB2_RESERVATION_SHA256 <- "a2d50a39a49f891ca9f1f50e9018340e28294a3ac0265fd1dccde373e94beac3"
AG_RB2_RAW <- list(
  RB2_M4_YEARLY=list(file="m4_yearly_dataset.zip",member="m4_yearly_dataset.tsf",sha="4a260dc865e9b746dda7ea3a3168db4163c858f8eb494b502128e98a4175f6aa"),
  RB2_M4_QUARTERLY=list(file="m4_quarterly_dataset.zip",member="m4_quarterly_dataset.tsf",sha="0a41bd81bd8d18ee51df83b29832d8909dc4edae9aeb2ac6f7ef21b7ef561a23"),
  RB2_M4_MONTHLY=list(file="m4_monthly_dataset.zip",member="m4_monthly_dataset.tsf",sha="473aa4fc814b625174be2b5615959f35f85f566fbed09c30acf44c350b2a1efe"),
  RB2_TOURISM_YEARLY=list(file="tourism_yearly_dataset.zip",member="tourism_yearly_dataset.tsf",sha="20238ddb9b11465b061bbfadcc398ef01f0896a8791199381b3edc706abf0263"),
  RB2_TOURISM_QUARTERLY=list(file="tourism_quarterly_dataset.zip",member="tourism_quarterly_dataset.tsf",sha="fa16da64f29aa04df447756cb65a5d58f8bc3d860fc22751c76850a3ffb048c3"),
  RB2_TOURISM_MONTHLY=list(file="tourism_monthly_dataset.zip",member="tourism_monthly_dataset.tsf",sha="6e434ad8a0ef6acb55ebee0e1d1ffe22707ea4e62c05e091326267f3a5b4a93c")
)

ag_rb2_sha_file <- function(path) digest::digest(file=path,algo="sha256",serialize=FALSE)
ag_rb2_sha_ascii <- function(x) digest::digest(charToRaw(enc2utf8(as.character(x))),algo="sha256",serialize=FALSE)

ag_rb2_unpack_bundle <- function(bundle, exdir=tempfile("autogrey_rb2_raw_")) {
  if (!file.exists(bundle)) stop("REALBENCH2 raw reservation bundle missing",call.=FALSE)
  if (!identical(ag_rb2_sha_file(bundle),AG_RB2_RAW_BUNDLE_SHA256)) stop("REALBENCH2 raw bundle SHA mismatch",call.=FALSE)
  dir.create(exdir,recursive=TRUE,showWarnings=FALSE)
  utils::unzip(bundle,exdir=exdir)
  reservation=file.path(exdir,"AUTOGREY_REALBENCH2_RESERVED_IDS_STEP5B.csv")
  rawdir=file.path(exdir,"realbench2_raw_step5b")
  if (!file.exists(reservation) || !dir.exists(rawdir)) stop("raw bundle layout mismatch",call.=FALSE)
  if (!identical(ag_rb2_sha_file(reservation),AG_RB2_RESERVATION_SHA256)) stop("reservation SHA mismatch",call.=FALSE)
  for (s in names(AG_RB2_RAW)) {
    z=file.path(rawdir,AG_RB2_RAW[[s]]$file)
    if (!file.exists(z) || !identical(ag_rb2_sha_file(z),AG_RB2_RAW[[s]]$sha)) stop(paste0("raw source SHA mismatch: ",s),call.=FALSE)
  }
  list(root=exdir,reservation=reservation,rawdir=rawdir)
}

ag_rb2_load_reservations <- function(path) {
  r=utils::read.csv(path,header=TRUE,stringsAsFactors=FALSE,check.names=FALSE,colClasses="character",na.strings=character(0))
  if (nrow(r)!=2511L) stop("expected exactly 2,511 reserved parents",call.=FALSE)
  if (anyDuplicated(r$parent_id) || anyDuplicated(paste(r$source_id,r$series_id,sep="\034"))) stop("reservation identity duplicate",call.=FALSE)
  h=suppressWarnings(as.integer(r$assigned_h))
  if (anyNA(h) || !identical(as.integer(table(factor(h,levels=c(1L,3L,5L)))),c(860L,818L,833L))) stop("frozen reservation horizon counts mismatch",call.=FALSE)
  r$h_int=h
  r$M_int=ifelse(r$M=="",NA_integer_,suppressWarnings(as.integer(r$M)))
  r
}

ag_rb2_read_reserved_source <- function(zpath, member, reserved_ids) {
  listed=utils::unzip(zpath,list=TRUE)$Name
  if (length(listed)!=1L || !identical(listed[[1L]],member)) stop(paste0("unexpected ZIP member list: ",basename(zpath)),call.=FALSE)
  td=tempfile("autogrey_tsf_"); dir.create(td,recursive=TRUE)
  on.exit(unlink(td,recursive=TRUE,force=TRUE),add=TRUE)
  utils::unzip(zpath,files=member,exdir=td,junkpaths=TRUE)
  fp=file.path(td,basename(member))
  # Latin-1 provides a one-byte-preserving decode for arbitrary non-UTF8 comments.
  # All frozen @data identifiers and numeric tokens are ASCII.
  lines=readLines(fp,warn=FALSE,encoding="latin1")
  data_at=which(tolower(trimws(lines))=="@data")
  if (length(data_at)!=1L) stop(paste0("TSF @data marker mismatch: ",member),call.=FALSE)
  dlines=lines[(data_at+1L):length(lines)]
  dlines=dlines[nzchar(trimws(dlines))]
  want=setNames(rep(TRUE,length(reserved_ids)),reserved_ids)
  out=vector("list",length(reserved_ids)); names(out)=reserved_ids
  seen=character(0)
  for (line in dlines) {
    # Python split(':',2): preserve any later colons inside the value field.
    pos=gregexpr(":",line,fixed=TRUE)[[1L]]
    if (length(pos)<2L || pos[1L]<1L) stop(paste0("malformed TSF line in ",member),call.=FALSE)
    p1=pos[1L]; p2=pos[2L]
    sid=substr(line,1L,p1-1L)
    if (!(sid %in% names(want))) next
    if (sid %in% seen) stop(paste0("duplicate series id ",sid),call.=FALSE)
    start_ts=substr(line,p1+1L,p2-1L)
    value_field=substr(line,p2+1L,nchar(line,type="bytes"))
    out[[sid]]=list(series_id=sid,start_timestamp=start_ts,value_field=value_field)
    seen=c(seen,sid)
  }
  if (!setequal(seen,reserved_ids)) stop(sprintf("reserved ID recovery mismatch: missing=%d extra=%d",length(setdiff(reserved_ids,seen)),length(setdiff(seen,reserved_ids))),call.=FALSE)
  out
}

ag_rb2_prepare_train_models <- function(dat, helper="reference/python/ag_step7d1_sklearn_bridge.py", verbose=TRUE) {
  full_global=ag_global_full_train_rank(dat)
  models=vector("list",length(AG_V1_GROUPS)); names(models)=AG_V1_GROUPS
  support=integer(length(AG_V1_GROUPS)); names(support)=AG_V1_GROUPS
  # At this stage we prepare each group's transformed TRAIN matrix + target/weight.
  # Actual sklearn fitting is batched together with all external eval rows later.
  for (gi in seq_along(AG_V1_GROUPS)) {
    ix=which(dat$group_idx==gi)
    support[gi]=length(unique(dat$parent[ix]))
    if (support[gi] < AG_V1_SUPPORT_MIN_PARENTS) stop(paste0("V1 full-TRAIN support fail: ",AG_V1_GROUPS[gi]),call.=FALSE)
    med=ag_v1_fit_medians(dat$Xraw[ix,,drop=FALSE])
    Xtr=ag_v1_apply_medians(dat$Xraw[ix,,drop=FALSE],med)
    models[[gi]]=list(train_index=ix,medians=med,Xtrain=Xtr,target=dat$target[ix],weight=dat$weight[ix])
    if (verbose) cat(sprintf("INFO prepared final V1 group=%s train_rows=%d parents=%d\n",AG_V1_GROUPS[gi],length(ix),support[gi]))
  }
  list(models=models,support=support,global=full_global,helper=helper)
}

ag_rb2_scan_pretarget <- function(reservations,rawdir,verbose=TRUE) {
  items=list(); refusals=list(); ii=0L; rrn=0L
  sources=sort(names(AG_RB2_RAW),method="radix")
  for (source in sources) {
    rs=reservations[reservations$source_id==source,,drop=FALSE]
    recovered=ag_rb2_read_reserved_source(file.path(rawdir,AG_RB2_RAW[[source]]$file),AG_RB2_RAW[[source]]$member,rs$series_id)
    if (verbose) cat(sprintf("INFO pretarget source=%s reserved=%d\n",source,nrow(rs)))
    for (j in seq_len(nrow(rs))) {
      r=rs[j,,drop=FALSE]; sid=r$series_id[[1L]]; z=recovered[[sid]]
      h=r$h_int[[1L]]; M=if (is.na(r$M_int[[1L]])) NULL else r$M_int[[1L]]
      tokens=strsplit(z$value_field,",",fixed=TRUE)[[1L]]
      N=length(tokens); t=N-h
      missing_marker=trimws(tokens) %in% c("?","NaN","nan","inf","-inf","")
      if (any(missing_marker)) {
        rrn=rrn+1L; refusals[[rrn]]=list(parent_id=r$parent_id[[1L]],source_id=source,series_id=sid,h=h,M=M,N=N,reason="SOURCE_MISSING_OR_NONFINITE_TOKEN")
        next
      }
      # IMPORTANT: target_tokens are character strings and are never passed to as.numeric/as.double.
      target_tokens=if (t>=0L) tokens[(t+1L):N] else tokens
      target_raw_sha=ag_rb2_sha_ascii(paste(target_tokens,collapse=","))
      if (t<4L) {
        rrn=rrn+1L; refusals[[rrn]]=list(parent_id=r$parent_id[[1L]],source_id=source,series_id=sid,h=h,M=M,N=N,reason="INSUFFICIENT_HISTORY_N_MINUS_H_LT_4",target_raw_sha256=target_raw_sha)
        next
      }
      D=suppressWarnings(as.double(tokens[seq_len(t)]))
      if (length(D)!=t || any(!is.finite(D))) {
        rrn=rrn+1L; refusals[[rrn]]=list(parent_id=r$parent_id[[1L]],source_id=source,series_id=sid,h=h,M=M,N=N,reason="D_PARSE_FAIL",target_raw_sha256=target_raw_sha)
        next
      }
      got=tryCatch({snap=ag_extract_features(D,h,M); port=ag_run_structural_portfolio(D,h,M); list(snap=snap,port=port)},error=function(e)e)
      if (inherits(got,"error")) {
        rrn=rrn+1L; refusals[[rrn]]=list(parent_id=r$parent_id[[1L]],source_id=source,series_id=sid,h=h,M=M,N=N,reason=paste0("PRETARGET_ENGINE_OR_FEATURE_FAIL:",class(got)[1L]),target_raw_sha256=target_raw_sha)
        next
      }
      eligible=as.character(got$port$distinct_groups)
      if (!length(eligible)) {
        rrn=rrn+1L; refusals[[rrn]]=list(parent_id=r$parent_id[[1L]],source_id=source,series_id=sid,h=h,M=M,N=N,reason="NO_ELIGIBLE_STRUCTURAL_GROUP",target_raw_sha256=target_raw_sha)
        next
      }
      if (any(!eligible %in% AG_V1_GROUPS)) stop(paste0("unknown eligible group: ",r$parent_id[[1L]]),call.=FALSE)
      eb=as.double(AG_V1_GROUPS %in% eligible)
      x=ag_v1_build_from_snapshot(got$snap$values,got$snap$valid,eb)
      groups=vector("list",length(eligible)); names(groups)=eligible
      for (g in eligible) {
        gr=got$port$group_results[[g]]
        f=as.double(gr$forecast)
        if (length(f)!=h || any(!is.finite(f))) stop(paste0("nonfinite target-free forecast: ",r$parent_id[[1L]]," ",g),call.=FALSE)
        groups[[g]]=list(selected_config_id=as.character(gr$selected_config_id),forecast=f)
      }
      ii=ii+1L
      items[[ii]]=list(parent_id=r$parent_id[[1L]],source_id=source,dataset=r$dataset[[1L]],series_id=sid,frequency=r$frequency[[1L]],M=M,h=h,N=N,n_D=t,start_timestamp=z$start_timestamp,
                       development_hash=agf_train_hash(D),feature_hash_r=got$snap$feature_hash,target_raw_sha256=target_raw_sha,
                       eligible_count=length(eligible),eligible_groups=eligible,Xraw=as.double(x),groups=groups)
    }
  }
  list(items=items,refusals=refusals)
}

ag_rb2_fit_predict_external <- function(scan, trainfit, verbose=TRUE) {
  items=scan$items
  # Preallocate one score vector per item, named by eligible group.
  score=list(); for (i in seq_along(items)) score[[i]]=setNames(rep(NA_real_,length(items[[i]]$eligible_groups)),items[[i]]$eligible_groups)
  bootstrap_first=setNames(rep(NA_character_,length(AG_V1_GROUPS)),AG_V1_GROUPS)
  for (gi in seq_along(AG_V1_GROUPS)) {
    g=AG_V1_GROUPS[[gi]]
    hit=which(vapply(items,function(z) g %in% z$eligible_groups,logical(1)))
    if (!length(hit)) stop(paste0("no REALBENCH2 eval rows for supported group: ",g),call.=FALSE)
    Xev=do.call(rbind,lapply(hit,function(i) items[[i]]$Xraw))
    Xev=ag_v1_apply_medians(Xev,trainfit$models[[gi]]$medians)
    if (verbose) cat(sprintf("INFO fitting final V1 group=%s train_rows=%d external_eval=%d\n",g,nrow(trainfit$models[[gi]]$Xtrain),nrow(Xev)))
    ans=ag_rf_fit_predict_sklearn(trainfit$models[[gi]]$Xtrain,trainfit$models[[gi]]$target,trainfit$models[[gi]]$weight,Xev,helper=trainfit$helper)
    pv=ag_v1_numvec(ans$predictions)
    if (length(pv)!=length(hit) || any(!is.finite(pv))) stop(paste0("external RF prediction failure: ",g),call.=FALSE)
    for (k in seq_along(hit)) score[[hit[[k]]]][[g]]=pv[[k]]
    bootstrap_first[[g]]=as.character(unlist(ans$bootstrap_index_sha256_first12,use.names=FALSE)[1L])
  }
  decisions=vector("list",length(items))
  global_means=trainfit$global$means
  for (i in seq_along(items)) {
    z=items[[i]]; elig=z$eligible_groups; sc=score[[i]]; gi=match(elig,AG_V1_GROUPS)
    if (any(!is.finite(sc))) stop(paste0("missing V1 external score: ",z$parent_id),call.=FALSE)
    ov=order(as.double(sc),gi,method="radix"); vg=elig[ov[1L]]
    gs=global_means[gi]; og=order(as.double(gs),gi,method="radix"); gg=elig[og[1L]]
    gp=z$groups
    for (g in elig) {
      gp[[g]]$v1_pred_log1p_regret=as.double(sc[[g]])
      gp[[g]]$global_train_mean_regret=as.double(global_means[[g]])
    }
    decisions[[i]]=list(parent_id=z$parent_id,source_id=z$source_id,dataset=z$dataset,series_id=z$series_id,frequency=z$frequency,M=z$M,h=z$h,N=z$N,n_D=z$n_D,start_timestamp=z$start_timestamp,
                        development_hash=z$development_hash,feature_hash_r=z$feature_hash_r,target_raw_sha256=z$target_raw_sha256,
                        eligible_count=z$eligible_count,eligible_groups=elig,v1_choice=vg,v1_pred_log1p_regret=as.double(sc[[vg]]),
                        global_choice=gg,global_train_mean_regret_score=as.double(global_means[[gg]]),groups=gp)
  }
  old=Sys.getlocale("LC_COLLATE"); try(Sys.setlocale("LC_COLLATE","C"),silent=TRUE)
  ord=order(vapply(decisions,`[[`,character(1),"parent_id"),method="radix"); decisions=decisions[ord]
  if (!is.na(old)&&nzchar(old)) try(Sys.setlocale("LC_COLLATE",old),silent=TRUE)
  refusals=scan$refusals
  if (length(refusals)) {
    old=Sys.getlocale("LC_COLLATE"); try(Sys.setlocale("LC_COLLATE","C"),silent=TRUE)
    refusals=refusals[order(vapply(refusals,`[[`,character(1),"parent_id"),method="radix")]
    if (!is.na(old)&&nzchar(old)) try(Sys.setlocale("LC_COLLATE",old),silent=TRUE)
  }
  list(decisions=decisions,refusals=refusals,bootstrap_first=bootstrap_first,global_means=global_means,global_support=trainfit$global$support,global_rank=trainfit$global$rank)
}

ag_rb2_pretarget_reproduce <- function(bundle="reference/raw/AUTOGREY_REALBENCH2_RAW_RESERVATION_BUNDLE_STEP5B.zip",
                                       helper="reference/python/ag_step7d1_sklearn_bridge.py",verbose=TRUE) {
  raw=ag_rb2_unpack_bundle(bundle)
  on.exit(unlink(raw$root,recursive=TRUE,force=TRUE),add=TRUE)
  reservations=ag_rb2_load_reservations(raw$reservation)
  dat=ag_v1_load_frozen_train()
  trainfit=ag_rb2_prepare_train_models(dat,helper=helper,verbose=verbose)
  scan=ag_rb2_scan_pretarget(reservations,raw$rawdir,verbose=verbose)
  out=ag_rb2_fit_predict_external(scan,trainfit,verbose=verbose)
  ids=vapply(out$decisions,`[[`,character(1),"parent_id"); rids=if(length(out$refusals)) vapply(out$refusals,`[[`,character(1),"parent_id") else character(0)
  if (length(intersect(ids,rids)) || !setequal(c(ids,rids),reservations$parent_id)) stop("decision/refusal identity partition mismatch",call.=FALSE)
  out$reservations=reservations
  out
}
