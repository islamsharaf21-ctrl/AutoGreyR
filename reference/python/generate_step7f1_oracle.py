#!/usr/bin/env python3
from __future__ import annotations
import csv, json, hashlib, math, io, zipfile
from pathlib import Path
from collections import Counter, defaultdict
import numpy as np

RAW={
 'RB2_M4_YEARLY':('m4_yearly_dataset.zip','m4_yearly_dataset.tsf','4a260dc865e9b746dda7ea3a3168db4163c858f8eb494b502128e98a4175f6aa'),
 'RB2_M4_QUARTERLY':('m4_quarterly_dataset.zip','m4_quarterly_dataset.tsf','0a41bd81bd8d18ee51df83b29832d8909dc4edae9aeb2ac6f7ef21b7ef561a23'),
 'RB2_M4_MONTHLY':('m4_monthly_dataset.zip','m4_monthly_dataset.tsf','473aa4fc814b625174be2b5615959f35f85f566fbed09c30acf44c350b2a1efe'),
 'RB2_TOURISM_YEARLY':('tourism_yearly_dataset.zip','tourism_yearly_dataset.tsf','20238ddb9b11465b061bbfadcc398ef01f0896a8791199381b3edc706abf0263'),
 'RB2_TOURISM_QUARTERLY':('tourism_quarterly_dataset.zip','tourism_quarterly_dataset.tsf','fa16da64f29aa04df447756cb65a5d58f8bc3d860fc22751c76850a3ffb048c3'),
 'RB2_TOURISM_MONTHLY':('tourism_monthly_dataset.zip','tourism_monthly_dataset.tsf','6e434ad8a0ef6acb55ebee0e1d1ffe22707ea4e62c05e091326267f3a5b4a93c'),
}
GROUPS=['SG01_CONT_GM','SG02_DISCRETE_POLY','SG03_FRAC_LINEAR','SG04_BERNOULLI','SG05_CONT_TIME_POLY','SG06_CONFORMABLE','SG07_ROLLING','SG08_WBO','SG09_GREY_MARKOV','SG10_SEASONAL']
RAW_BUNDLE_SHA='85aac5e92b5d6b0db2299d319d096a5a4b274369cbfeabf7c79e2dc706b0f4f9'

def sha_file(p):
    h=hashlib.sha256();
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1<<20),b''): h.update(b)
    return h.hexdigest()
def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def stable(o,p): Path(p).write_text(json.dumps(o,indent=2,sort_keys=True,allow_nan=False)+'\n',encoding='utf-8')
def cvar90(v):
    a=np.asarray(v,float); k=max(1,int(math.ceil(.10*len(a)))); return float(np.mean(np.sort(a)[-k:]))
def metrics(rows, field):
    a=np.asarray([d[field] for d in rows],float); cf='v1_choice' if field=='v1_regret' else 'global_choice'; cc=Counter(d[cf] for d in rows)
    return {'n_tasks':len(a),'n_supported':len(a),'support_coverage':1.0,'mean_regret':float(np.mean(a)),'median_regret':float(np.median(a)),'cvar90':cvar90(a),'p90_regret':float(np.quantile(a,.9,method='linear')),'zero_regret_rate':float(np.mean(a<=1e-15)),'selection_counts':{g:int(cc[g]) for g in GROUPS if cc[g]>0}}
def mase_scale(D,M):
    x=np.asarray(D,float); lag=int(M) if M is not None else 1
    diffs=np.abs(x[lag:]-x[:-lag]); scale=float(np.mean(diffs)); eps=1e-12*max(float(np.mean(np.abs(x))),1.0)
    if not np.isfinite(scale) or scale<=eps: raise RuntimeError('LOSS_SCALE_UNDEFINED')
    return scale
def mase(y,f,D,M): return float(np.mean(np.abs(np.asarray(y,float)-np.asarray(f,float)))/mase_scale(D,M))

def iter_source(outer, source, wanted):
    fn,member,hx=RAW[source]; path='realbench2_raw_step5b/'+fn
    b=outer.read(path)
    if sha_bytes(b)!=hx: raise RuntimeError('inner raw hash '+source)
    with zipfile.ZipFile(io.BytesIO(b)) as z:
        if z.namelist()!=[member]: raise RuntimeError('member '+source)
        seen=set(); in_data=False
        for rb in z.open(member):
            line=rb.decode('utf-8',errors='replace').rstrip('\r\n'); s=line.strip()
            if not in_data:
                if s.lower()=='@data': in_data=True
                continue
            if not s: continue
            parts=line.split(':',2)
            if len(parts)!=3: raise RuntimeError('malformed')
            sid=parts[0]
            if sid not in wanted: continue
            if sid in seen: raise RuntimeError('dup')
            seen.add(sid); yield sid,parts[1],parts[2]
        if seen!=wanted: raise RuntimeError(f'id mismatch {source} missing={len(wanted-seen)}')

def main(bundle,pretarget,outdir):
    bundle=Path(bundle); pretarget=Path(pretarget); outdir=Path(outdir); outdir.mkdir(parents=True,exist_ok=True)
    if sha_file(bundle)!=RAW_BUNDLE_SHA: raise RuntimeError('outer raw bundle sha')
    pobj=json.load(open(pretarget,encoding='utf-8'))
    db={(d['source_id'],d['series_id']):d for d in pobj['decisions']}; rb={(d['source_id'],d['series_id']):d for d in pobj['refusals']}
    wanted={s:set() for s in RAW}
    for s,sid in set(db)|set(rb): wanted[s].add(sid)
    rows=[]; losses=[]; target_records=[]; forecast_records=[]; fbin=[]
    with zipfile.ZipFile(bundle) as outer:
      for source in sorted(RAW):
        for sid,start_ts,value_field in iter_source(outer,source,wanted[source]):
            key=(source,sid)
            if key in rb: continue
            d=db[key]; h=int(d['h']); t=int(d['n_D']); M=d['M']; toks=value_field.split(',')
            if len(toks)!=int(d['N']) or t!=len(toks)-h: raise RuntimeError('geometry '+d['parent_id'])
            tt=toks[t:]; tsha=sha_bytes(','.join(tt).encode('utf-8'))
            if tsha!=d['target_raw_sha256']: raise RuntimeError('target sha '+d['parent_id'])
            D=np.asarray([float(x) for x in toks[:t]],dtype='<f8'); Y=np.asarray([float(x) for x in tt],dtype='<f8')
            if not np.all(np.isfinite(D)) or not np.all(np.isfinite(Y)): raise RuntimeError('finite')
            target_records.append({'parent_id':d['parent_id'],'source_id':source,'series_id':sid,'h':h,'M':'' if M is None else int(M),'N':int(d['N']),'n_D':t,'development_sha256':sha_bytes(D.tobytes()),'target_raw_sha256':tsha,'target_float64_sha256':sha_bytes(Y.tobytes()),'mase_scale':mase_scale(D,M)})
            gl={}
            for g in GROUPS:
                if g not in d['groups']: continue
                p=d['groups'][g]; F=np.asarray(p['forecast'],dtype='<f8')
                if len(F)!=h: raise RuntimeError('forecast len')
                L=mase(Y,F,D,M); gl[g]=L
                losses.append({'parent_id':d['parent_id'],'source_id':source,'series_id':sid,'h':h,'group':g,'selected_config_id':p['selected_config_id'],'mase':L})
                off=8*sum(len(x) for x in fbin)
                fbin.append(F)
                forecast_records.append({'parent_id':d['parent_id'],'group':g,'selected_config_id':p['selected_config_id'],'h':h,'offset_bytes':off,'count':h,'forecast_sha256':sha_bytes(F.tobytes())})
            oracle=min(gl.values()); vc=d['v1_choice']; gc=d['global_choice']
            rows.append({'parent_id':d['parent_id'],'source_id':source,'dataset':d['dataset'],'series_id':sid,'frequency':d['frequency'],'h':h,'M':M,'N':int(d['N']),'n_D':t,'eligible_count':int(d['eligible_count']),'v1_choice':vc,'v1_loss_mase':float(gl[vc]),'v1_regret':max(0.,float(gl[vc]-oracle)),'global_choice':gc,'global_loss_mase':float(gl[gc]),'global_regret':max(0.,float(gl[gc]-oracle)),'eligible_oracle_mase':float(oracle)})
    rows.sort(key=lambda x:x['parent_id']); losses.sort(key=lambda x:(x['parent_id'],GROUPS.index(x['group']))); target_records.sort(key=lambda x:x['parent_id']); forecast_records.sort(key=lambda x:(x['parent_id'],GROUPS.index(x['group'])))
    # rebuild forecast binary/index sorted to same order (reparse to avoid earlier offset order dependency)
    fmap={(d['parent_id'],g):np.asarray(d['groups'][g]['forecast'],dtype='<f8') for d in pobj['decisions'] for g in d['groups']}
    off=0; frec=[]; chunks=[]
    for rec in forecast_records:
        F=fmap[(rec['parent_id'],rec['group'])]; rec=rec.copy(); rec['offset_bytes']=off; rec['count']=len(F); rec['forecast_sha256']=sha_bytes(F.tobytes()); frec.append(rec); chunks.append(F); off+=8*len(F)
    farr=np.concatenate(chunks).astype('<f8',copy=False)
    fbin_path=outdir/'AUTOGREY_STEP7F1_CANONICAL_FORECASTS_LINUX.f64le'; farr.tofile(fbin_path)
    def write_csv(path, fields, data):
        with open(path,'w',newline='',encoding='utf-8') as f:
            w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(data)
    dec_path=outdir/'AUTOGREY_STEP7F1_DECISIONS_ORACLE.csv'
    fields=['parent_id','source_id','dataset','series_id','frequency','h','M','N','n_D','eligible_count','v1_choice','v1_loss_mase','v1_regret','global_choice','global_loss_mase','global_regret','eligible_oracle_mase']
    write_csv(dec_path,fields,rows)
    loss_path=outdir/'AUTOGREY_STEP7F1_ELIGIBLE_LOSSES_ORACLE.csv'; write_csv(loss_path,['parent_id','source_id','series_id','h','group','selected_config_id','mase'],losses)
    targ_path=outdir/'AUTOGREY_STEP7F1_TARGET_OPEN_ORACLE.csv'; write_csv(targ_path,['parent_id','source_id','series_id','h','M','N','n_D','development_sha256','target_raw_sha256','target_float64_sha256','mase_scale'],target_records)
    findex=outdir/'AUTOGREY_STEP7F1_CANONICAL_FORECAST_INDEX.csv'; write_csv(findex,['parent_id','group','selected_config_id','h','offset_bytes','count','forecast_sha256'],frec)
    v1=metrics(rows,'v1_regret'); glob=metrics(rows,'global_regret')
    oracle={'checkpoint':'STEP7F1_FROZEN_TARGET_SCORING_ORACLE','status':'PASS','raw_bundle_sha256':sha_file(bundle),'pretarget_sha256':sha_file(pretarget),'actionable_count':len(rows),'eligible_action_rows':len(losses),'primary_metrics':v1,'global_metrics':glob,'estimands':{'mean_regret_delta_primary_minus_global':float(v1['mean_regret']-glob['mean_regret']),'cvar90_regret_delta_primary_minus_global':float(v1['cvar90']-glob['cvar90'])},'files':{}}
    for p in [dec_path,loss_path,targ_path,findex,fbin_path]: oracle['files'][p.name]=sha_file(p)
    op=outdir/'AUTOGREY_STEP7F1_ORACLE.json'; stable(oracle,op)
    print(json.dumps(oracle,indent=2))

if __name__=='__main__':
 import argparse
 ap=argparse.ArgumentParser(); ap.add_argument('--bundle',required=True); ap.add_argument('--pretarget',required=True); ap.add_argument('--outdir',required=True); a=ap.parse_args(); main(a.bundle,a.pretarget,a.outdir)
