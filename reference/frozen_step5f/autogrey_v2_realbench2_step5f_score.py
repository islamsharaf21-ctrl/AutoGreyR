#!/usr/bin/env python3
from __future__ import annotations
import csv, json, hashlib, math, sys, zipfile
from pathlib import Path
from collections import Counter, defaultdict
import numpy as np

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import autogrey_v2_search_step5db_r2 as r2
import autogrey_meta_corpus_step4fb2 as meta

VERSION='AG_V2_REALBENCH2_5F_SCORE_1'
BOOT_REPS=4000
BOOT_SEED=46073
GROUPS=r2.GROUPS
RAW={
 'RB2_M4_YEARLY':('m4_yearly_dataset.zip','m4_yearly_dataset.tsf','4a260dc865e9b746dda7ea3a3168db4163c858f8eb494b502128e98a4175f6aa'),
 'RB2_M4_QUARTERLY':('m4_quarterly_dataset.zip','m4_quarterly_dataset.tsf','0a41bd81bd8d18ee51df83b29832d8909dc4edae9aeb2ac6f7ef21b7ef561a23'),
 'RB2_M4_MONTHLY':('m4_monthly_dataset.zip','m4_monthly_dataset.tsf','473aa4fc814b625174be2b5615959f35f85f566fbed09c30acf44c350b2a1efe'),
 'RB2_TOURISM_YEARLY':('tourism_yearly_dataset.zip','tourism_yearly_dataset.tsf','20238ddb9b11465b061bbfadcc398ef01f0896a8791199381b3edc706abf0263'),
 'RB2_TOURISM_QUARTERLY':('tourism_quarterly_dataset.zip','tourism_quarterly_dataset.tsf','fa16da64f29aa04df447756cb65a5d58f8bc3d860fc22751c76850a3ffb048c3'),
 'RB2_TOURISM_MONTHLY':('tourism_monthly_dataset.zip','tourism_monthly_dataset.tsf','6e434ad8a0ef6acb55ebee0e1d1ffe22707ea4e62c05e091326267f3a5b4a93c'),
}

def sha(p:Path):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''): h.update(b)
 return h.hexdigest()

def stable(obj,p:Path):
 p.write_text(json.dumps(obj,indent=2,sort_keys=True,allow_nan=False)+'\n',encoding='utf-8')

def cvar90(vals):
 a=np.asarray(vals,dtype=float)
 if len(a)==0: raise RuntimeError('empty CVaR input')
 k=max(1,int(math.ceil(0.10*len(a))))
 return float(np.mean(np.sort(a)[-k:]))

def metrics(decisions, field):
 a=np.asarray([d[field] for d in decisions],dtype=float)
 choice_field='v1_choice' if field=='v1_regret' else 'global_choice'
 cc=Counter(d[choice_field] for d in decisions)
 return {
  'n_tasks':int(len(a)),'n_supported':int(len(a)),'support_coverage':1.0,
  'mean_regret':float(np.mean(a)),'median_regret':float(np.median(a)),
  'cvar90':cvar90(a),'p90_regret':float(np.quantile(a,0.90,method='linear')),
  'zero_regret_rate':float(np.mean(a<=1e-15)),
  'selection_counts':{g:int(cc[g]) for g in GROUPS if cc[g]>0},
 }

def subgroup(decisions,key,regfield):
 b=defaultdict(list)
 for d in decisions: b[str(d[key])].append(float(d[regfield]))
 return {k:{'n':len(v),'mean_regret':float(np.mean(v)),'median_regret':float(np.median(v)),'cvar90':cvar90(v)} for k,v in sorted(b.items())}

def iter_reserved_lines(zpath:Path,member:str,wanted:set[str]):
 with zipfile.ZipFile(zpath) as z:
  if z.namelist()!=[member]: raise RuntimeError(f'unexpected ZIP member list {zpath.name}: {z.namelist()}')
  with z.open(member) as f:
   in_data=False; seen=set()
   for raw in f:
    line=raw.decode('utf-8',errors='replace').rstrip('\r\n'); s=line.strip()
    if not in_data:
     if s.lower()=='@data': in_data=True
     continue
    if not s: continue
    parts=line.split(':',2)
    if len(parts)!=3: raise RuntimeError(f'malformed TSF line in {member}')
    sid=parts[0]
    if sid not in wanted: continue
    if sid in seen: raise RuntimeError(f'duplicate series id {sid}')
    seen.add(sid); yield sid,parts[1],parts[2]
   if seen!=wanted: raise RuntimeError(f'reserved series mismatch {member}: missing={len(wanted-seen)} extra={len(seen-wanted)}')

def main(raw_dir:Path,out:Path):
 pre=out/'AUTOGREY_REALBENCH2_PRETARGET_STEP5F.json'
 opening=out/'AUTOGREY_REALBENCH2_OPENING_LOCK_STEP5F.json'
 if not pre.exists() or not opening.exists(): raise RuntimeError('pretarget/opening lock missing')
 lock=json.load(open(opening,encoding='utf-8'))
 if lock.get('status')!='FROZEN_BEFORE_TARGET_NUMERIC_OPENING': raise RuntimeError('opening lock status invalid')
 if sha(pre)!=lock['pretarget_sha256']: raise RuntimeError('pretarget hash mismatch against opening lock')
 if lock.get('score_harness_sha256')!=sha(Path(__file__)):
  raise RuntimeError('score harness hash mismatch against opening lock')
 if lock.get('bootstrap_replicates')!=BOOT_REPS or lock.get('bootstrap_seed')!=BOOT_SEED:
  raise RuntimeError('bootstrap lock mismatch')
 pobj=json.load(open(pre,encoding='utf-8'))
 if pobj['chronology']['target_tokens_numeric_parsed'] or pobj['chronology']['outcomes_opened']:
  raise RuntimeError('pretarget chronology invalid')
 if pobj['reservation_count']!=2511 or pobj['primary_selector']!='V1_STYLE_RF_REGRET':
  raise RuntimeError('pretarget reservation/winner mismatch')
 decision_by={(d['source_id'],d['series_id']):d for d in pobj['decisions']}
 refusal_by={(d['source_id'],d['series_id']):d for d in pobj['refusals']}
 if len(decision_by)+len(refusal_by)!=2511: raise RuntimeError('pretarget partition count mismatch')
 # Verify raw bytes again immediately before formal target opening.
 for source,(fn,member,hx) in RAW.items():
  if sha(raw_dir/fn)!=hx: raise RuntimeError(f'raw hash mismatch {fn}')
 wanted_by_source={s:set() for s in RAW}
 for s,sid in set(decision_by)|set(refusal_by): wanted_by_source[s].add(sid)
 # ---- FORMAL TARGET OPENING STARTS HERE. ----
 decisions=[]; opened_count=0
 for source in sorted(RAW):
  fn,member,_=RAW[source]
  for sid,start_ts,value_field in iter_reserved_lines(raw_dir/fn,member,wanted_by_source[source]):
   key=(source,sid)
   if key in refusal_by:
    # Protocol refusals are retained and never replaced. Their targets are not needed for eligible-regret estimand.
    continue
   d=decision_by[key]; h=int(d['h']); M=d['M']; t=int(d['n_D'])
   tokens=value_field.split(',')
   if len(tokens)!=int(d['N']) or t!=len(tokens)-h: raise RuntimeError(f'length/origin mismatch {source}/{sid}')
   target_tokens=tokens[t:]
   target_raw_sha=hashlib.sha256(','.join(target_tokens).encode('utf-8')).hexdigest()
   if target_raw_sha!=d['target_raw_sha256']:
    raise RuntimeError(f'target commitment mismatch {source}/{sid}')
   try:
    D=np.asarray([float(x) for x in tokens[:t]],dtype=float)
    Y=np.asarray([float(x) for x in target_tokens],dtype=float)
   except Exception as e:
    raise RuntimeError(f'numeric open failed {source}/{sid}: {type(e).__name__}')
   if len(Y)!=h or not np.all(np.isfinite(D)) or not np.all(np.isfinite(Y)):
    raise RuntimeError(f'nonfinite/length target open {source}/{sid}')
   losses={}
   for g,pay in d['groups'].items():
    fcast=np.asarray(pay['forecast'],dtype=float)
    losses[g]=float(meta._score_vector(Y,fcast,D,M)['mase'])
   if not losses or any(not math.isfinite(v) for v in losses.values()):
    raise RuntimeError(f'invalid eligible loss set {source}/{sid}')
   oracle=float(min(losses.values())); vc=d['v1_choice']; gc=d['global_choice']
   if vc not in losses or gc not in losses: raise RuntimeError(f'frozen choice not eligible {source}/{sid}')
   vr=max(0.0,float(losses[vc]-oracle)); gr=max(0.0,float(losses[gc]-oracle))
   decisions.append({
    'parent_id':d['parent_id'],'source_id':source,'dataset':d['dataset'],'series_id':sid,'frequency':d['frequency'],
    'h':h,'M':M,'N':int(d['N']),'n_D':t,'eligible_count':int(d['eligible_count']),
    'v1_choice':vc,'v1_loss_mase':float(losses[vc]),'v1_regret':vr,
    'global_choice':gc,'global_loss_mase':float(losses[gc]),'global_regret':gr,
    'eligible_oracle_mase':oracle,
   })
   opened_count+=1
 decisions.sort(key=lambda x:x['parent_id'])
 if len(decisions)!=pobj['actionable_count'] or opened_count!=pobj['actionable_count']:
  raise RuntimeError('actionable scoring count mismatch')
 # Frozen final metrics.
 v1m=metrics(decisions,'v1_regret'); gm=metrics(decisions,'global_regret')
 observed_mean_delta=float(v1m['mean_regret']-gm['mean_regret'])
 observed_tail_delta=float(v1m['cvar90']-gm['cvar90'])
 # Paired parent bootstrap, one task per parent.
 v=np.asarray([d['v1_regret'] for d in decisions],dtype=float)
 g=np.asarray([d['global_regret'] for d in decisions],dtype=float)
 n=len(v); rng=np.random.default_rng(BOOT_SEED)
 mean_boot=np.empty(BOOT_REPS,dtype=float); tail_boot=np.empty(BOOT_REPS,dtype=float)
 for b in range(BOOT_REPS):
  ix=rng.integers(0,n,size=n)
  vb=v[ix]; gb=g[ix]
  mean_boot[b]=float(np.mean(vb-gb))
  tail_boot[b]=float(cvar90(vb)-cvar90(gb))
 mean_ci=[float(np.quantile(mean_boot,q,method='linear')) for q in (0.025,0.975)]
 tail_ci=[float(np.quantile(tail_boot,q,method='linear')) for q in (0.025,0.975)]
 mean_pass=bool(mean_ci[1] < 0.0); tail_pass=bool(tail_ci[1] <= 0.0); overall=bool(mean_pass and tail_pass)
 result={
  'version':VERSION,'checkpoint':'STEP_5F_REALBENCH2_OPENED_ONCE_FINAL','status':'PASS' if overall else 'FAIL',
  'primary_selector':'V1_STYLE_RF_REGRET','pretarget_sha256':lock['pretarget_sha256'],
  'opening_lock_sha256':sha(opening),'score_harness_sha256':sha(Path(__file__)),
  'reserved_parent_count':2511,'actionable_parent_count':len(decisions),'refusal_count':len(pobj['refusals']),
  'refusal_reasons':dict(Counter(r['reason'] for r in pobj['refusals'])),
  'primary_metrics':v1m,'global_rank_v2_metrics':gm,
  'estimands':{
   'mean_regret_delta_primary_minus_global':observed_mean_delta,
   'cvar90_regret_delta_primary_minus_global':observed_tail_delta,
  },
  'bootstrap':{
   'replicates':BOOT_REPS,'seed':BOOT_SEED,'type':'paired parent-cluster; one task per parent',
   'ci_method':'percentile 95%, numpy quantile linear','mean_delta_ci95':mean_ci,'cvar90_delta_ci95':tail_ci,
  },
  'final_gate':{
   'mean_rule':'upper 95% CI of mean-regret delta < 0','mean_pass':mean_pass,
   'tail_rule':'upper 95% CI of CVaR90-regret delta <= 0','tail_pass':tail_pass,
   'overall_robust_superiority':overall,
  },
  'diagnostics':{
   'primary_by_source':subgroup(decisions,'source_id','v1_regret'),'global_by_source':subgroup(decisions,'source_id','global_regret'),
   'primary_by_h':subgroup(decisions,'h','v1_regret'),'global_by_h':subgroup(decisions,'h','global_regret'),
  },
  'chronology':{
   'choices_and_all_eligible_forecasts_frozen_before_target_open':True,
   'target_commitments_verified_before_scoring_each_actionable_parent':True,
   'post_target_refit_or_decision_change':False,
  },
  'final_claim_rule':'Robust superiority only if both frozen mean and tail CI criteria pass. No redesign/refit after this result.'
 }
 outp=out/'AUTOGREY_REALBENCH2_RESULTS_STEP5F.json'; stable(result,outp)
 # Per-parent results CSV.
 csvp=out/'AUTOGREY_REALBENCH2_DECISIONS_STEP5F.csv'
 fields=['parent_id','source_id','dataset','series_id','frequency','h','M','N','n_D','eligible_count','v1_choice','v1_loss_mase','v1_regret','global_choice','global_loss_mase','global_regret','eligible_oracle_mase']
 with open(csvp,'w',newline='',encoding='utf-8') as f:
  w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows([{k:d[k] for k in fields} for d in decisions])
 # Full bootstrap replicate audit.
 bootp=out/'AUTOGREY_REALBENCH2_BOOTSTRAP_STEP5F.csv'
 with open(bootp,'w',newline='',encoding='utf-8') as f:
  w=csv.writer(f); w.writerow(['replicate','mean_regret_delta_primary_minus_global','cvar90_regret_delta_primary_minus_global'])
  for i in range(BOOT_REPS): w.writerow([i+1,repr(float(mean_boot[i])),repr(float(tail_boot[i]))])
 print(json.dumps({
  'result':str(outp),'result_sha256':sha(outp),'decisions_sha256':sha(csvp),'bootstrap_sha256':sha(bootp),
  'actionable':len(decisions),'refusals':len(pobj['refusals']),'primary':v1m,'global':gm,
  'mean_delta':observed_mean_delta,'mean_ci95':mean_ci,'tail_delta':observed_tail_delta,'tail_ci95':tail_ci,
  'final_gate':result['final_gate']
 },indent=2))

if __name__=='__main__':
 main(Path('/mnt/data/autogrey_step5f_raw/realbench2_raw_step5b'),Path('/mnt/data/autogrey_step5f'))
