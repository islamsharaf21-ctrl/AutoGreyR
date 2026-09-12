#!/usr/bin/env python3
from __future__ import annotations
import csv, json, hashlib, math, sys, zipfile
from pathlib import Path
from collections import Counter
import numpy as np

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import autogrey_v2_search_step5db_r2 as r2
import autogrey_engine_step4fb_r1 as engine
import autogrey_features_step4e as feat

VERSION='AG_V2_REALBENCH2_5F_PRETARGET_R1'
EXPECTED={
 'train_action':'5e943ce10c601187d46dd0f77e9059aee29c7e2710d1d8ff5acf779787983a99',
 'train_labels':'77e202112c8d3de45aeebfdbe6a4c8d1ac9b725aac598af5974d46a3f5be4631',
 'reservation':'a2d50a39a49f891ca9f1f50e9018340e28294a3ac0265fd1dccde373e94beac3',
 'r2':'a5f6e6914809bcde3667c96165984a218595c92c4cbf1d98ff4b23de50be2d23',
 'engine':'01c745d8a627748748f82916a576efbee231a2f87d66c314d57947dbede67974',
 'features':'bbbd645cffae6462eb50cbb9ff5fb902912e6204df1ab5a9a316428d58b7a113',
 'step5e':'59d6fb217c16b1a3960332281c14a6139c23314e59b2905702595e0f960d7422',
}
RAW={
 'RB2_M4_YEARLY':('m4_yearly_dataset.zip','m4_yearly_dataset.tsf','4a260dc865e9b746dda7ea3a3168db4163c858f8eb494b502128e98a4175f6aa'),
 'RB2_M4_QUARTERLY':('m4_quarterly_dataset.zip','m4_quarterly_dataset.tsf','0a41bd81bd8d18ee51df83b29832d8909dc4edae9aeb2ac6f7ef21b7ef561a23'),
 'RB2_M4_MONTHLY':('m4_monthly_dataset.zip','m4_monthly_dataset.tsf','473aa4fc814b625174be2b5615959f35f85f566fbed09c30acf44c350b2a1efe'),
 'RB2_TOURISM_YEARLY':('tourism_yearly_dataset.zip','tourism_yearly_dataset.tsf','20238ddb9b11465b061bbfadcc398ef01f0896a8791199381b3edc706abf0263'),
 'RB2_TOURISM_QUARTERLY':('tourism_quarterly_dataset.zip','tourism_quarterly_dataset.tsf','fa16da64f29aa04df447756cb65a5d58f8bc3d860fc22751c76850a3ffb048c3'),
 'RB2_TOURISM_MONTHLY':('tourism_monthly_dataset.zip','tourism_monthly_dataset.tsf','6e434ad8a0ef6acb55ebee0e1d1ffe22707ea4e62c05e091326267f3a5b4a93c'),
}
GROUPS=r2.GROUPS; GI=r2.GROUP_INDEX

def sha(p:Path):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''): h.update(b)
 return h.hexdigest()

def stable(obj,p:Path):
 p.write_text(json.dumps(obj,indent=2,sort_keys=True,allow_nan=False)+'\n',encoding='utf-8')

def make_v1_row(snapshot, eligible):
 fd=feat.feature_dict(snapshot); md=feat.mask_dict(snapshot); row={}
 for name in r2.ALL_V1_FEATURES:
  row[f'feat__{name}']=repr(float(fd[name])); row[f'valid__{name}']='1' if md[name] else '0'
 for g in GROUPS: row[f'elig__{g}']='1' if g in eligible else '0'
 return row

def iter_tsf_reserved(zpath:Path, member:str, reserved:set[str]):
 """Yield only reserved series. Held-out target tokens remain strings, never float-parsed here."""
 with zipfile.ZipFile(zpath) as z:
  if z.namelist()!=[member]: raise RuntimeError(f'unexpected ZIP member list {zpath.name}: {z.namelist()}')
  with z.open(member) as f:
   in_data=False
   seen=set()
   for raw in f:
    line=raw.decode('utf-8',errors='replace').rstrip('\r\n')
    s=line.strip()
    if not in_data:
     if s.lower()=='@data': in_data=True
     continue
    if not s: continue
    # TSF has two attributes then the series-value field.
    parts=line.split(':',2)
    if len(parts)!=3: raise RuntimeError(f'malformed TSF line in {member}')
    sid=parts[0]
    if sid not in reserved: continue
    if sid in seen: raise RuntimeError(f'duplicate series id {sid}')
    seen.add(sid)
    yield sid,parts[1],parts[2]
   if seen!=reserved: raise RuntimeError(f'reserved ID recovery mismatch in {member}: missing={len(reserved-seen)} extra={len(seen-reserved)}')

def main(train_dir:Path,raw_dir:Path,reservation_path:Path,step5e_result:Path,out:Path):
 # Immutable lineage/hash checks before any RB2 parsing.
 checks={
  'train_action':train_dir/'AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv',
  'train_labels':train_dir/'AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv',
  'reservation':reservation_path,
  'r2':HERE/'autogrey_v2_search_step5db_r2.py',
  'engine':HERE/'autogrey_engine_step4fb_r1.py',
  'features':HERE/'autogrey_features_step4e.py',
  'step5e':step5e_result,
 }
 got={k:sha(p) for k,p in checks.items()}
 for k,e in EXPECTED.items():
  if got[k]!=e: raise RuntimeError(f'hash mismatch {k}: {got[k]} != {e}')
 s5e=json.load(open(step5e_result,encoding='utf-8'))
 if not s5e['gate']['overall_pass'] or s5e['primary_selector']!='V1_STYLE_RF_REGRET': raise RuntimeError('Step5E gate/winner mismatch')
 for source,(fn,member,hx) in RAW.items():
  p=raw_dir/fn
  if sha(p)!=hx: raise RuntimeError(f'raw hash mismatch {fn}')
 # Reservation ledger (target-free): exact 2,511 parents.
 reservations=[]
 with open(reservation_path,newline='',encoding='utf-8-sig') as f:
  for row in csv.DictReader(f): reservations.append(row)
 if len(reservations)!=2511: raise RuntimeError(f'reservation count {len(reservations)}')
 bysource={s:{} for s in RAW}
 for row in reservations:
  s=row['source_id']; sid=row['series_id']
  if s not in RAW or sid in bysource[s]: raise RuntimeError('reservation identity error')
  bysource[s][sid]=row
 if Counter(int(r['assigned_h']) for r in reservations)!=Counter({1:860,3:818,5:833}): raise RuntimeError('frozen horizon counts mismatch')
 # Fit exact final V1 and GLOBAL reference from all actionable TRAIN.
 records,parents,_,_,_,_=r2.load_train(train_dir)
 arr=r2.records_to_arrays(records); allix=np.arange(len(records),dtype=int)
 models={}; global_means={}; supports={}
 counts=r2.group_parent_counts(allix,arr,by_h=False)
 for gi,g in enumerate(GROUPS):
  ix=allix[arr['group_idx']==gi]
  if counts.get(gi,0)<r2.V1_SUPPORT_MIN_PARENTS: raise RuntimeError(f'V1 TRAIN support fail {g}')
  Xtr,_,med=r2.fit_medians_and_transform(arr['X_v1'][ix],arr['X_v1'][ix][:1])
  model=r2.make_rf_regressor(r2.N_ESTIMATORS_V1,None,0.01)
  model.fit(Xtr,arr['target'][ix],sample_weight=arr['weight'][ix])
  models[gi]=(model,med)
  global_means[gi]=float(np.average(arr['regret'][ix],weights=arr['weight'][ix]))
  supports[g]=int(counts[gi])
 # D-side only parse -> features, eligibility, forecasts, choices. Target tokens stay opaque strings.
 decisions=[]; refusals=[]; source_seen=Counter(); h_seen=Counter(); action_rows=0
 for source in sorted(RAW):
  fn,member,_=RAW[source]; reserved=set(bysource[source])
  for sid,start_ts,value_field in iter_tsf_reserved(raw_dir/fn,member,reserved):
   rr=bysource[source][sid]; p=rr['parent_id']; h=int(rr['assigned_h']); M=None if rr['M']=='' else int(rr['M'])
   tokens=value_field.split(','); N=len(tokens); t=N-h
   if any(tok.strip() in ('?','NaN','nan','inf','-inf','') for tok in tokens):
    # @missing false in all six frozen assets; no imputation allowed.
    refusals.append({'parent_id':p,'source_id':source,'series_id':sid,'h':h,'M':M,'N':N,'reason':'SOURCE_MISSING_OR_NONFINITE_TOKEN'})
    continue
   target_tokens=tokens[t:] if t>=0 else tokens
   target_raw_sha=hashlib.sha256(','.join(target_tokens).encode('utf-8')).hexdigest()
   if t<4:
    refusals.append({'parent_id':p,'source_id':source,'series_id':sid,'h':h,'M':M,'N':N,'reason':'INSUFFICIENT_HISTORY_N_MINUS_H_LT_4','target_raw_sha256':target_raw_sha})
    continue
   try:
    D=np.asarray([float(x) for x in tokens[:t]],dtype=float)
   except Exception:
    refusals.append({'parent_id':p,'source_id':source,'series_id':sid,'h':h,'M':M,'N':N,'reason':'D_PARSE_FAIL','target_raw_sha256':target_raw_sha}); continue
   if not np.all(np.isfinite(D)):
    refusals.append({'parent_id':p,'source_id':source,'series_id':sid,'h':h,'M':M,'N':N,'reason':'D_NONFINITE','target_raw_sha256':target_raw_sha}); continue
   try:
    snap=feat.extract_features(D,h,M)
    port=engine.run_portfolio(D,h,M)
   except Exception as e:
    refusals.append({'parent_id':p,'source_id':source,'series_id':sid,'h':h,'M':M,'N':N,'reason':'PRETARGET_ENGINE_OR_FEATURE_FAIL:'+type(e).__name__,'target_raw_sha256':target_raw_sha}); continue
   eligible=list(port.distinct_groups)
   if not eligible:
    refusals.append({'parent_id':p,'source_id':source,'series_id':sid,'h':h,'M':M,'N':N,'reason':'NO_ELIGIBLE_STRUCTURAL_GROUP','target_raw_sha256':target_raw_sha}); continue
   if any(g not in GROUPS for g in eligible): raise RuntimeError(f'unknown group {p}')
   row=make_v1_row(snap,set(eligible)); x=np.asarray([r2.build_v1_features(row)],dtype=float)
   vs=[]; gs=[]; group_payload={}
   for g in eligible:
    gi=GI[g]; model,med=models[gi]; xx=x.copy(); bad=~np.isfinite(xx)
    if np.any(bad): xx[bad]=np.take(med,np.nonzero(bad)[1])
    pred=float(model.predict(xx)[0]); vs.append((pred,gi,g)); gs.append((global_means[gi],gi,g))
    gr=port.group_results[g]
    fcast=np.asarray(gr.forecast,dtype=float)
    if len(fcast)!=h or not np.all(np.isfinite(fcast)): raise RuntimeError(f'nonfinite target-free forecast {p} {g}')
    group_payload[g]={'selected_config_id':gr.selected_config_id,'forecast':[float(v) for v in fcast],
                      'v1_pred_log1p_regret':pred,'global_train_mean_regret':global_means[gi]}
   pv=min(vs,key=lambda q:(q[0],q[1])); pg=min(gs,key=lambda q:(q[0],q[1]))
   decisions.append({
    'parent_id':p,'source_id':source,'dataset':rr['dataset'],'series_id':sid,'frequency':rr['frequency'],
    'M':M,'h':h,'N':N,'n_D':t,'start_timestamp':start_ts,
    'development_hash':snap.train_hash,'feature_hash':snap.feature_hash,'target_raw_sha256':target_raw_sha,
    'eligible_count':len(eligible),'eligible_groups':eligible,
    'v1_choice':pv[2],'v1_pred_log1p_regret':pv[0],
    'global_choice':pg[2],'global_train_mean_regret_score':pg[0],
    'groups':group_payload,
   })
   source_seen[source]+=1; h_seen[h]+=1; action_rows+=len(eligible)
 # Every reserved parent must be represented exactly once as decision or refusal.
 ids={d['parent_id'] for d in decisions}; rids={d['parent_id'] for d in refusals}; expected_ids={r['parent_id'] for r in reservations}
 if ids & rids or ids|rids != expected_ids: raise RuntimeError('decision/refusal identity partition mismatch')
 decisions.sort(key=lambda d:d['parent_id']); refusals.sort(key=lambda d:d['parent_id'])
 obj={
  'version':VERSION,'checkpoint':'STEP_5F_REALBENCH2_PRETARGET_FROZEN','primary_selector':'V1_STYLE_RF_REGRET',
  'reservation_count':2511,'actionable_count':len(decisions),'refusal_count':len(refusals),'action_rows':action_rows,
  'frozen_horizon_counts_all_reserved':dict(sorted(Counter(int(r['assigned_h']) for r in reservations).items())),
  'actionable_horizon_counts':dict(sorted(h_seen.items())),'actionable_source_counts':dict(sorted(source_seen.items())),
  'input_hashes':got,'raw_hashes':{s:RAW[s][2] for s in sorted(RAW)},
  'fit':{'v1_trees_per_group':r2.N_ESTIMATORS_V1,'random_seed':r2.RANDOM_SEED,'max_features':r2.MAX_FEATURES,
         'max_depth':None,'min_samples_leaf':0.01,'support_min_parents':r2.V1_SUPPORT_MIN_PARENTS,
         'group_parent_support':supports,'global_train_mean_regret_by_group':{GROUPS[k]:global_means[k] for k in range(len(GROUPS))}},
  'choice_counts':{'v1':dict(Counter(d['v1_choice'] for d in decisions)),'global':dict(Counter(d['global_choice'] for d in decisions))},
  'refusals':refusals,'decisions':decisions,
  'chronology':{'target_tokens_numeric_parsed':False,'target_losses_computed':False,'outcomes_opened':False,
                'all_group_forecasts_frozen_from_D_only':True},
  'post_freeze_rule':'After SHA-256 commitment of this object, target tokens may be numeric-parsed once for final scoring. No selector/forecast refit or decision change.'
 }
 out.mkdir(parents=True,exist_ok=True)
 op=out/'AUTOGREY_REALBENCH2_PRETARGET_STEP5F.json'; stable(obj,op)
 print(json.dumps({'output':str(op),'sha256':sha(op),'actionable':len(decisions),'refusals':len(refusals),
                   'v1_counts':obj['choice_counts']['v1'],'global_counts':obj['choice_counts']['global'],
                   'refusal_reasons':dict(Counter(r['reason'] for r in refusals))},indent=2))

if __name__=='__main__':
 main(Path('/mnt/data/autogrey_r2_work'),Path('/mnt/data/autogrey_step5f_raw/realbench2_raw_step5b'),
      Path('/mnt/data/autogrey_step5f_raw/AUTOGREY_REALBENCH2_RESERVED_IDS_STEP5B.csv'),
      Path('/mnt/data/autogrey_step5e/AUTOGREY_V2_LOCKTEST_RESULTS_STEP5E.json'),
      Path('/mnt/data/autogrey_step5f'))
