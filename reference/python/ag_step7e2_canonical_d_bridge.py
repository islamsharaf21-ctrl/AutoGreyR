#!/usr/bin/env python3
"""AutoGrey Step7E2 diagnostic helper: canonical development-side float64 parse only.

Reads the frozen Step5B raw reservation bundle, parses ONLY D=x[:N-h] using the
same Python float/NumPy float64 semantics as the frozen Step5F pretarget harness,
and writes a parent-index CSV plus one concatenated little-endian float64 binary.
Held-out target tokens are never converted to numeric values.
"""
from __future__ import annotations
import argparse, csv, hashlib, io, json, os, struct, tempfile, zipfile
from pathlib import Path
import numpy as np

RAW = {
  'RB2_M4_YEARLY':('m4_yearly_dataset.zip','m4_yearly_dataset.tsf'),
  'RB2_M4_QUARTERLY':('m4_quarterly_dataset.zip','m4_quarterly_dataset.tsf'),
  'RB2_M4_MONTHLY':('m4_monthly_dataset.zip','m4_monthly_dataset.tsf'),
  'RB2_TOURISM_YEARLY':('tourism_yearly_dataset.zip','tourism_yearly_dataset.tsf'),
  'RB2_TOURISM_QUARTERLY':('tourism_quarterly_dataset.zip','tourism_quarterly_dataset.tsf'),
  'RB2_TOURISM_MONTHLY':('tourism_monthly_dataset.zip','tourism_monthly_dataset.tsf'),
}
MISSING = {'?','NaN','nan','inf','-inf',''}

def sha_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def iter_reserved(zpath: Path, member: str, reserved: set[str]):
    with zipfile.ZipFile(zpath) as z:
        if z.namelist() != [member]:
            raise RuntimeError(f'unexpected ZIP member list {zpath.name}: {z.namelist()}')
        with z.open(member) as f:
            in_data=False; seen=set()
            for raw in f:
                line=raw.decode('utf-8',errors='replace').rstrip('\r\n')
                s=line.strip()
                if not in_data:
                    if s.lower()=='@data': in_data=True
                    continue
                if not s: continue
                parts=line.split(':',2)
                if len(parts)!=3: raise RuntimeError(f'malformed TSF line in {member}')
                sid=parts[0]
                if sid not in reserved: continue
                if sid in seen: raise RuntimeError(f'duplicate series id {sid}')
                seen.add(sid)
                yield sid, parts[2]
            if seen != reserved:
                raise RuntimeError(f'reserved ID recovery mismatch in {member}: missing={len(reserved-seen)} extra={len(seen-reserved)}')

def main(bundle: Path, out_index: Path, out_binary: Path):
    td=Path(tempfile.mkdtemp(prefix='ag_step7e2_d_'))
    try:
        with zipfile.ZipFile(bundle) as z: z.extractall(td)
        reservation=td/'AUTOGREY_REALBENCH2_RESERVED_IDS_STEP5B.csv'
        rawdir=td/'realbench2_raw_step5b'
        rows=[]
        with reservation.open(newline='',encoding='utf-8-sig') as f:
            rows=list(csv.DictReader(f))
        if len(rows)!=2511: raise RuntimeError(f'reservation count {len(rows)}')
        bysource={s:{} for s in RAW}
        for r in rows:
            bysource[r['source_id']][r['series_id']]=r
        out_index.parent.mkdir(parents=True,exist_ok=True)
        offset=0; index=[]; actionable_like=0
        with out_binary.open('wb') as bout:
            for source in sorted(RAW):
                fn,member=RAW[source]
                reserved=set(bysource[source])
                for sid,value_field in iter_reserved(rawdir/fn,member,reserved):
                    rr=bysource[source][sid]; h=int(rr['assigned_h'])
                    tokens=value_field.split(','); N=len(tokens); t=N-h
                    # Mirror frozen source-wide missing-token refusal without numeric target parsing.
                    if any(tok.strip() in MISSING for tok in tokens):
                        index.append({'parent_id':rr['parent_id'],'status':'SOURCE_TOKEN_REFUSAL','offset_bytes':'','n_D':max(t,0),'development_hash':''})
                        continue
                    if t < 4:
                        index.append({'parent_id':rr['parent_id'],'status':'SHORT_HISTORY_REFUSAL','offset_bytes':'','n_D':t,'development_hash':''})
                        continue
                    try:
                        # IMPORTANT: ONLY development tokens are numeric parsed.
                        D=np.asarray([float(x) for x in tokens[:t]],dtype='<f8')
                    except Exception:
                        index.append({'parent_id':rr['parent_id'],'status':'D_PARSE_REFUSAL','offset_bytes':'','n_D':t,'development_hash':''})
                        continue
                    if not np.all(np.isfinite(D)):
                        index.append({'parent_id':rr['parent_id'],'status':'D_NONFINITE_REFUSAL','offset_bytes':'','n_D':t,'development_hash':''})
                        continue
                    b=D.tobytes(order='C')
                    bout.write(b)
                    index.append({'parent_id':rr['parent_id'],'status':'D_PARSED','offset_bytes':offset,'n_D':t,'development_hash':sha_bytes(b)})
                    offset += len(b); actionable_like += 1
        with out_index.open('w',newline='',encoding='utf-8') as f:
            w=csv.DictWriter(f,fieldnames=['parent_id','status','offset_bytes','n_D','development_hash'])
            w.writeheader(); w.writerows(index)
        print(json.dumps({'reservation_count':len(rows),'d_parsed_count':actionable_like,
                          'binary_bytes':offset,'index':str(out_index),'binary':str(out_binary),
                          'numpy':np.__version__},sort_keys=True))
    finally:
        import shutil; shutil.rmtree(td,ignore_errors=True)

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('--bundle',required=True)
    ap.add_argument('--out-index',required=True)
    ap.add_argument('--out-binary',required=True)
    a=ap.parse_args(); main(Path(a.bundle),Path(a.out_index),Path(a.out_binary))
