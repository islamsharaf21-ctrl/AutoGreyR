#!/usr/bin/env python3
"""AutoGrey Step 7F1 canonical target-opening bridge.

Reproduction purpose only. It enforces the frozen Step5F target commitments before
numeric parsing and outputs canonical Python float64 D/Y arrays for actionable
parents. Refusal targets are never numerically parsed because they are outside the
frozen eligible-regret estimand.

No model fitting, forecasting, model selection, regret calculation, bootstrap, or
post-target decision mutation occurs here.
"""
from __future__ import annotations
import argparse, csv, hashlib, io, json, math, zipfile
from pathlib import Path
import numpy as np

VERSION='AG_STEP7F1_TARGET_OPEN_BRIDGE_1'
RAW_BUNDLE_SHA='85aac5e92b5d6b0db2299d319d096a5a4b274369cbfeabf7c79e2dc706b0f4f9'
RAW={
 'RB2_M4_YEARLY':('m4_yearly_dataset.zip','m4_yearly_dataset.tsf','4a260dc865e9b746dda7ea3a3168db4163c858f8eb494b502128e98a4175f6aa'),
 'RB2_M4_QUARTERLY':('m4_quarterly_dataset.zip','m4_quarterly_dataset.tsf','0a41bd81bd8d18ee51df83b29832d8909dc4edae9aeb2ac6f7ef21b7ef561a23'),
 'RB2_M4_MONTHLY':('m4_monthly_dataset.zip','m4_monthly_dataset.tsf','473aa4fc814b625174be2b5615959f35f85f566fbed09c30acf44c350b2a1efe'),
 'RB2_TOURISM_YEARLY':('tourism_yearly_dataset.zip','tourism_yearly_dataset.tsf','20238ddb9b11465b061bbfadcc398ef01f0896a8791199381b3edc706abf0263'),
 'RB2_TOURISM_QUARTERLY':('tourism_quarterly_dataset.zip','tourism_quarterly_dataset.tsf','fa16da64f29aa04df447756cb65a5d58f8bc3d860fc22751c76850a3ffb048c3'),
 'RB2_TOURISM_MONTHLY':('tourism_monthly_dataset.zip','tourism_monthly_dataset.tsf','6e434ad8a0ef6acb55ebee0e1d1ffe22707ea4e62c05e091326267f3a5b4a93c'),
}

def sha_file(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1<<20),b''): h.update(b)
    return h.hexdigest()
def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def mase_scale(D,M):
    lag=int(M) if M is not None else 1
    diffs=np.abs(D[lag:]-D[:-lag]); scale=float(np.mean(diffs)); eps=1e-12*max(float(np.mean(np.abs(D))),1.0)
    if not np.isfinite(scale) or scale<=eps: raise RuntimeError('LOSS_SCALE_UNDEFINED')
    return scale

def iter_source(outer, source, wanted):
    fn,member,hx=RAW[source]; b=outer.read('realbench2_raw_step5b/'+fn)
    if sha_bytes(b)!=hx: raise RuntimeError(f'raw source SHA mismatch {source}')
    with zipfile.ZipFile(io.BytesIO(b)) as z:
        if z.namelist()!=[member]: raise RuntimeError(f'unexpected member list {source}')
        seen=set(); in_data=False
        for rb in z.open(member):
            line=rb.decode('utf-8',errors='replace').rstrip('\r\n'); s=line.strip()
            if not in_data:
                if s.lower()=='@data': in_data=True
                continue
            if not s: continue
            parts=line.split(':',2)
            if len(parts)!=3: raise RuntimeError(f'malformed TSF line {source}')
            sid=parts[0]
            if sid not in wanted: continue
            if sid in seen: raise RuntimeError(f'duplicate series {source}/{sid}')
            seen.add(sid); yield sid,parts[1],parts[2]
        if seen!=wanted: raise RuntimeError(f'reserved series mismatch {source}: missing={len(wanted-seen)}')

def main(bundle,pretarget,out_index,out_d,out_y):
    bundle=Path(bundle); pretarget=Path(pretarget); out_index=Path(out_index); out_d=Path(out_d); out_y=Path(out_y)
    if sha_file(bundle)!=RAW_BUNDLE_SHA: raise RuntimeError('raw bundle SHA mismatch')
    pobj=json.load(open(pretarget,encoding='utf-8'))
    if pobj['chronology']['target_tokens_numeric_parsed'] or pobj['chronology']['outcomes_opened']:
        raise RuntimeError('pretarget chronology invalid')
    decisions={(d['source_id'],d['series_id']):d for d in pobj['decisions']}
    refusals={(d['source_id'],d['series_id']):d for d in pobj['refusals']}
    if len(decisions)!=2496 or len(refusals)!=15: raise RuntimeError('pretarget partition mismatch')
    wanted={s:set() for s in RAW}
    for s,sid in set(decisions)|set(refusals): wanted[s].add(sid)
    parsed=[]
    with zipfile.ZipFile(bundle) as outer:
      for source in sorted(RAW):
        for sid,start_ts,value_field in iter_source(outer,source,wanted[source]):
            key=(source,sid)
            if key in refusals:
                continue  # protocol refusal targets remain unopened in reproduction too
            d=decisions[key]; h=int(d['h']); t=int(d['n_D']); M=d['M']; toks=value_field.split(',')
            if len(toks)!=int(d['N']) or t!=len(toks)-h: raise RuntimeError(f'geometry mismatch {d["parent_id"]}')
            target_tokens=toks[t:]
            target_raw_sha=sha_bytes(','.join(target_tokens).encode('utf-8'))
            if target_raw_sha!=d['target_raw_sha256']:
                raise RuntimeError(f'target commitment mismatch {d["parent_id"]}')
            # FORMAL REPRODUCTION TARGET OPENING OCCURS ONLY AFTER THE HASH CHECK ABOVE.
            try:
                D=np.asarray([float(x) for x in toks[:t]],dtype='<f8')
                Y=np.asarray([float(x) for x in target_tokens],dtype='<f8')
            except Exception as e:
                raise RuntimeError(f'numeric open failed {d["parent_id"]}: {type(e).__name__}')
            if len(Y)!=h or not np.all(np.isfinite(D)) or not np.all(np.isfinite(Y)):
                raise RuntimeError(f'nonfinite/length target open {d["parent_id"]}')
            parsed.append((d,D,Y,target_raw_sha,mase_scale(D,M)))
    parsed.sort(key=lambda z:z[0]['parent_id'])
    if len(parsed)!=2496: raise RuntimeError('actionable target-open count mismatch')
    d_chunks=[]; y_chunks=[]; rows=[]; doff=0; yoff=0
    for d,D,Y,tsha,scale in parsed:
        d_chunks.append(D); y_chunks.append(Y)
        rows.append({
          'parent_id':d['parent_id'],'source_id':d['source_id'],'series_id':d['series_id'],
          'h':int(d['h']),'M':'' if d['M'] is None else int(d['M']),'N':int(d['N']),'n_D':int(d['n_D']),
          'd_offset_bytes':doff,'d_count':len(D),'y_offset_bytes':yoff,'y_count':len(Y),
          'development_sha256':sha_bytes(D.tobytes()),'target_raw_sha256':tsha,
          'target_float64_sha256':sha_bytes(Y.tobytes()),'mase_scale':scale
        })
        doff+=8*len(D); yoff+=8*len(Y)
    darr=np.concatenate(d_chunks).astype('<f8',copy=False); yarr=np.concatenate(y_chunks).astype('<f8',copy=False)
    out_index.parent.mkdir(parents=True,exist_ok=True)
    darr.tofile(out_d); yarr.tofile(out_y)
    fields=list(rows[0].keys())
    with open(out_index,'w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
    print(json.dumps({'version':VERSION,'status':'PASS','actionable':len(rows),'d_values':int(darr.size),'y_values':int(yarr.size),'index_sha256':sha_file(out_index),'d_binary_sha256':sha_file(out_d),'y_binary_sha256':sha_file(out_y),'targets_opened_actionable_only':True,'refusal_targets_numeric_parsed':False},sort_keys=True))

if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--bundle',required=True); ap.add_argument('--pretarget',required=True); ap.add_argument('--out-index',required=True); ap.add_argument('--out-d',required=True); ap.add_argument('--out-y',required=True); a=ap.parse_args(); main(a.bundle,a.pretarget,a.out_index,a.out_d,a.out_y)
