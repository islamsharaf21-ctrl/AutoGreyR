#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,json,math,platform,sys
from pathlib import Path
import numpy as np

VERSION='AG_STEP7F2_PCG64_BOOTSTRAP_1'
REPS=4000
SEED=46073

def sha_bytes(b:bytes)->str: return hashlib.sha256(b).hexdigest()
def sha_file(p:Path)->str: return hashlib.sha256(p.read_bytes()).hexdigest()
def cvar90(a):
    a=np.asarray(a,dtype=np.float64)
    k=max(1,int(math.ceil(0.10*len(a))))
    return float(np.mean(np.sort(a)[-k:]))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--decisions',required=True)
    ap.add_argument('--out-csv',required=True)
    ap.add_argument('--out-json',required=True)
    a=ap.parse_args()
    rows=list(csv.DictReader(Path(a.decisions).open(encoding='utf-8',newline='')))
    if len(rows)!=2496: raise SystemExit('expected 2496 decision rows')
    pids=[r['parent_id'] for r in rows]
    if len(set(pids))!=len(pids) or pids!=sorted(pids): raise SystemExit('decision parent order/uniqueness failure')
    v=np.asarray([float(r['v1_regret']) for r in rows],dtype=np.float64)
    g=np.asarray([float(r['global_regret']) for r in rows],dtype=np.float64)
    if not np.isfinite(v).all() or not np.isfinite(g).all(): raise SystemExit('nonfinite regrets')
    rng=np.random.default_rng(SEED)
    mb=np.empty(REPS,dtype=np.float64); tb=np.empty(REPS,dtype=np.float64)
    index_hashes=[]
    for b in range(REPS):
        ix=rng.integers(0,len(v),size=len(v))
        if b<12:
            index_hashes.append(sha_bytes(np.asarray(ix,dtype='<i8').tobytes(order='C')))
        vb=v[ix]; gb=g[ix]
        mb[b]=float(np.mean(vb-gb))
        tb[b]=float(cvar90(vb)-cvar90(gb))
    out=Path(a.out_csv); out.parent.mkdir(parents=True,exist_ok=True)
    with out.open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f); w.writerow(['replicate','mean_regret_delta_primary_minus_global','cvar90_regret_delta_primary_minus_global'])
        for i in range(REPS): w.writerow([i+1,repr(float(mb[i])),repr(float(tb[i]))])
    mean_ci=[float(np.quantile(mb,q,method='linear')) for q in (0.025,0.975)]
    tail_ci=[float(np.quantile(tb,q,method='linear')) for q in (0.025,0.975)]
    summary={
      'version':VERSION,'status':'PASS','python':platform.python_version(),'numpy':np.__version__,'platform':sys.platform,
      'rng':'numpy.random.default_rng','bit_generator':type(rng.bit_generator).__name__,'seed':SEED,'replicates':REPS,'n_parents':len(v),
      'decision_input_sha256':sha_file(Path(a.decisions)),'bootstrap_csv_sha256':sha_file(out),'first12_index_i64le_sha256':index_hashes,
      'mean_delta_ci95':mean_ci,'cvar90_delta_ci95':tail_ci,
      'mean_pass':bool(mean_ci[1]<0.0),'tail_pass':bool(tail_ci[1]<=0.0),'overall_robust_superiority':bool(mean_ci[1]<0.0 and tail_ci[1]<=0.0),
      'first3_mean_delta':[float(x) for x in mb[:3]],'first3_cvar90_delta':[float(x) for x in tb[:3]],
      'ci_method':'percentile 95%, numpy quantile linear','bootstrap_type':'paired parent-cluster; one task per parent'
    }
    Path(a.out_json).write_text(json.dumps(summary,indent=2,sort_keys=True,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(summary,sort_keys=True))
if __name__=='__main__': main()
