#!/usr/bin/env python3
from __future__ import annotations
import csv, json, hashlib, math, sys
from pathlib import Path
from collections import defaultdict, Counter
import numpy as np

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import autogrey_v2_search_step5db_r2 as r2

VERSION='AG_V2_LOCKTEST_5E_PRETARGET_1'
EXPECTED={
 'AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv':'5e943ce10c601187d46dd0f77e9059aee29c7e2710d1d8ff5acf779787983a99',
 'AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv':'77e202112c8d3de45aeebfdbe6a4c8d1ac9b725aac598af5974d46a3f5be4631',
 'AUTOGREY_V2_TASK_SPLIT_STEP5D_A.csv':'92670cd0ba8544d9f0402e27a07078f2a743f1a28ad821710bdcdc0f66c002d9',
 'autogrey_v2_search_step5db_r2.py':'a5f6e6914809bcde3667c96165984a218595c92c4cbf1d98ff4b23de50be2d23',
}
GROUPS=r2.GROUPS; GI=r2.GROUP_INDEX

def sha(p):
 h=hashlib.sha256();
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(1<<20),b''): h.update(b)
 return h.hexdigest()

def stable(obj,p):
 Path(p).write_text(json.dumps(obj,indent=2,sort_keys=True,allow_nan=False)+'\n',encoding='utf-8')

def main(inp:Path,out:Path):
 got={}
 for n,e in EXPECTED.items():
  p=inp/n; d=sha(p)
  if d!=e: raise RuntimeError(f'hash mismatch {n} {d} != {e}')
  got[n]=d
 # exact R2 winner lock
 r2sum=json.load(open('/mnt/data/autogrey_r2_run1/AUTOGREY_V2_SEARCH_SUMMARY_STEP5D_B_R2.json',encoding='utf-8'))
 if r2sum['selected']['candidate_id']!='V1_STYLE_RF_REGRET': raise RuntimeError('R2 winner mismatch')
 # load train using canonical R2 loader
 records, parents, p2r, pmeta, allrows, nontrain = r2.load_train(inp)
 arr=r2.records_to_arrays(records)
 # fit 10 full-TRAIN V1 regressors and global means
 allix=np.arange(len(records),dtype=int)
 counts=r2.group_parent_counts(allix,arr,by_h=False)
 models={}; global_means={}
 for gi,g in enumerate(GROUPS):
  ix=allix[arr['group_idx']==gi]
  if counts.get(gi,0)<r2.V1_SUPPORT_MIN_PARENTS: raise RuntimeError(f'V1 support fail {g}')
  Xtr,_,med=r2.fit_medians_and_transform(arr['X_v1'][ix],arr['X_v1'][ix][:1])
  model=r2.make_rf_regressor(r2.N_ESTIMATORS_V1,None,0.01)
  model.fit(Xtr,arr['target'][ix],sample_weight=arr['weight'][ix])
  models[gi]=(model,med)
  global_means[gi]=float(np.average(arr['regret'][ix],weights=arr['weight'][ix]))
 # locktest parent ledger
 lockmeta={}
 with open(inp/'AUTOGREY_V2_TASK_SPLIT_STEP5D_A.csv',newline='',encoding='utf-8-sig') as f:
  for row in csv.DictReader(f):
   if row['v2_split']=='V2_LOCKTEST': lockmeta[row['parent_id']]=row
 if len(lockmeta)!=275 or any(r['task_status']!='ACTIONABLE' for r in lockmeta.values()): raise RuntimeError('LOCKTEST ledger mismatch')
 # target-free locktest action rows only
 byp=defaultdict(list)
 with open(inp/'AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv',newline='',encoding='utf-8-sig') as f:
  for row in csv.DictReader(f):
   if row['v2_split']!='V2_LOCKTEST': continue
   if row['parent_id'] not in lockmeta: raise RuntimeError('action parent not in lock ledger')
   byp[row['parent_id']].append(row)
 if len(byp)!=275 or sum(map(len,byp.values()))!=2416: raise RuntimeError(f'LOCKTEST action rows mismatch {len(byp)} {sum(map(len,byp.values()))}')
 decisions=[]
 for p in sorted(lockmeta):
  rows=sorted(byp[p],key=lambda x:GI[x['action_group']])
  if len(rows)!=int(lockmeta[p]['eligible_count']): raise RuntimeError(f'eligible count mismatch {p}')
  v1scores=[]; gscores=[]
  for row in rows:
   gi=GI[row['action_group']]
   model,med=models[gi]
   x=np.asarray([r2.build_v1_features(row)],dtype=float)
   bad=~np.isfinite(x)
   if np.any(bad): x[bad]=np.take(med,np.nonzero(bad)[1])
   pred=float(model.predict(x)[0])
   v1scores.append((pred,gi,row))
   gscores.append((global_means[gi],gi,row))
  pv=min(v1scores,key=lambda t:(t[0],t[1]))
  pg=min(gscores,key=lambda t:(t[0],t[1]))
  decisions.append({
   'parent_id':p,'task_id':lockmeta[p]['task_id'],'source_class':lockmeta[p]['source_class'],
   'source_detail':lockmeta[p]['source_detail'],'development_role':lockmeta[p]['development_role'],
   'h':int(lockmeta[p]['h']),'M':(None if lockmeta[p]['M']=='' else int(float(lockmeta[p]['M']))),
   'eligible_count':int(lockmeta[p]['eligible_count']),'target_hash':lockmeta[p]['target_hash'],
   'v1_choice':pv[2]['action_group'],'v1_pred_log1p_regret':pv[0],
   'global_choice':pg[2]['action_group'],'global_train_mean_regret_score':pg[0],
  })
 obj={
  'version':VERSION,'checkpoint':'STEP_5E_PRETARGET_CHOICES_FROZEN','r2_winner':'V1_STYLE_RF_REGRET',
  'train_actionable_parents':len(parents),'train_action_rows':len(records),
  'locktest_parents':len(decisions),'locktest_action_rows':sum(map(len,byp.values())),
  'input_hashes':got,'r2_summary_sha256':sha('/mnt/data/autogrey_r2_run1/AUTOGREY_V2_SEARCH_SUMMARY_STEP5D_B_R2.json'),
  'fit':{'v1_trees_per_group':r2.N_ESTIMATORS_V1,'random_seed':r2.RANDOM_SEED,'max_features':r2.MAX_FEATURES,
         'max_depth':None,'min_samples_leaf':0.01,'support_min_parents':r2.V1_SUPPORT_MIN_PARENTS,
         'group_parent_support':{GROUPS[k]:int(v) for k,v in sorted(counts.items())}},
  'global_train_mean_regret_by_group':{GROUPS[k]:global_means[k] for k in range(len(GROUPS))},
  'choice_counts':{'v1':dict(Counter(d['v1_choice'] for d in decisions)),'global':dict(Counter(d['global_choice'] for d in decisions))},
  'decisions':decisions,
  'protected_state_at_freeze':{'CAL':'SEALED_NOT_OPENED','LOCKTEST_OUTCOMES':'SEALED_NOT_OPENED','REAL_BENCH_2':'UNTOUCHED_NOT_READ'}
 }
 out.mkdir(parents=True,exist_ok=True)
 p=out/'AUTOGREY_V2_LOCKTEST_PRETARGET_CHOICES_STEP5E.json'; stable(obj,p)
 print(json.dumps({'output':str(p),'sha256':sha(p),'locktest_parents':len(decisions),'v1_counts':obj['choice_counts']['v1'],'global_counts':obj['choice_counts']['global']},indent=2))

if __name__=='__main__':
 main(HERE,Path('/mnt/data/autogrey_step5e'))
