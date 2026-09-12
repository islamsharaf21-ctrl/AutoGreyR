#!/usr/bin/env python3
"""AutoGrey Step7E2 R7 cross-platform numerical census.

Purpose: quantify platform-dependent float64 forecast differences for the two
sensitive structural groups (SG02, SG05) using ONLY development-side data.
Held-out target tokens are never accepted or parsed by this program.
"""
from __future__ import annotations
import argparse, csv, hashlib, importlib.util, io, json, math, sys, tempfile, contextlib
from pathlib import Path
import numpy as np

ALLOWED_GROUPS=("SG02_DISCRETE_POLY","SG05_CONT_TIME_POLY")

def sha(b:bytes)->str: return hashlib.sha256(b).hexdigest()

def load_module(path:Path,name:str):
    s=importlib.util.spec_from_file_location(name,path)
    if s is None or s.loader is None: raise RuntimeError(f"cannot load {path}")
    m=importlib.util.module_from_spec(s); sys.modules[name]=m; s.loader.exec_module(m); return m

def parse_sg02(cid:str):
    if not cid.startswith("deg="): raise RuntimeError(cid)
    body=cid[4:]
    if body=="empty": return ()
    vals=tuple(int(x) for x in body.split("."))
    if tuple(sorted(set(vals)))!=vals or any(x<1 or x>4 for x in vals): raise RuntimeError(cid)
    return vals

def run_model(engine,group,cid,D,h):
    if group=="SG02_DISCRETE_POLY": out=engine.dgpm_fit_forecast(D,h,parse_sg02(cid))
    elif group=="SG05_CONT_TIME_POLY":
        if cid.startswith("TP_alpha="): out=engine.timepower_fit_forecast(D,h,float(cid.split("=",1)[1]))
        elif cid.startswith("FOTP_order="): out=engine.fotp_fit_forecast(D,h,int(cid.split("=",1)[1]))
        else: raise RuntimeError(cid)
    else: raise RuntimeError(group)
    f=np.asarray(out.forecast,dtype="<f8")
    if f.ndim!=1 or len(f)!=h or not np.all(np.isfinite(f)): raise RuntimeError(f"bad forecast {group} {cid}")
    return f,out

def ordered_u64(x:float)->int:
    u=int(np.asarray([x],dtype=np.float64).view(np.uint64)[0])
    if u & (1<<63): return (~u) & ((1<<64)-1)
    return u | (1<<63)

def ulp_dist(a:float,b:float)->int:
    return abs(ordered_u64(float(a))-ordered_u64(float(b)))

def main(a):
    pre=json.load(open(a.pretarget,encoding="utf-8"))
    dec={d["parent_id"]:d for d in pre["decisions"]}
    with open(a.canonical_index,newline="",encoding="utf-8-sig") as f: cidx=list(csv.DictReader(f))
    if len(cidx)!=4826: raise RuntimeError(f"canonical sensitive rows {len(cidx)}")
    if sum(r['group']==ALLOWED_GROUPS[0] for r in cidx)!=2410 or sum(r['group']==ALLOWED_GROUPS[1] for r in cidx)!=2416:
        raise RuntimeError("canonical group counts")
    c_raw=Path(a.canonical_binary).read_bytes()
    if len(c_raw)%8: raise RuntimeError("canonical binary alignment")
    c_all=np.frombuffer(c_raw,dtype="<f8")

    dmod=load_module(Path(a.d_helper),"ag_r7_d_helper")
    engine=load_module(Path(a.engine),"ag_r7_engine")
    with tempfile.TemporaryDirectory(prefix="ag_step7e2_r7_") as td:
        td=Path(td); di=td/"d_index.csv"; db=td/"d.f64le"
        with contextlib.redirect_stdout(io.StringIO()): dmod.main(Path(a.bundle),di,db)
        with di.open(newline="",encoding="utf-8-sig") as f: drows=list(csv.DictReader(f))
        dmap={r['parent_id']:r for r in drows}
        d_raw=db.read_bytes(); d_all=np.frombuffer(d_raw,dtype="<f8")

        details=[]
        group_stats={g:{"arrays":0,"exact_arrays":0,"nonexact_arrays":0,"values":0,"nonexact_values":0,
                        "max_abs":0.0,"max_rel":0.0,"max_ulp":0,"worst_abs":None,"worst_rel":None,"worst_ulp":None}
                     for g in ALLOWED_GROUPS}
        for n,r in enumerate(cidx,1):
            pid=r['parent_id']; g=r['group']; cid=r['config_id']; h=int(r['h']); nf=int(r['n_forecast'])
            if g not in ALLOWED_GROUPS or h!=nf: raise RuntimeError(f"canonical metadata {pid} {g}")
            d=dec.get(pid)
            if d is None or int(d['h'])!=h or d['groups'][g]['selected_config_id']!=cid:
                raise RuntimeError(f"pretarget metadata {pid} {g}")
            dr=dmap.get(pid)
            if dr is None or dr['status']!='D_PARSED' or int(dr['n_D'])!=int(d['n_D']):
                raise RuntimeError(f"D metadata {pid}")
            off=int(dr['offset_bytes']); lo=off//8; hi=lo+int(dr['n_D']); D=np.asarray(d_all[lo:hi],dtype=float)
            f,out=run_model(engine,g,cid,D,h)
            coff=int(r['offset_bytes']); clo=coff//8; chi=clo+nf; cf=np.asarray(c_all[clo:chi],dtype=np.float64)
            if len(cf)!=nf: raise RuntimeError(f"canonical bounds {pid} {g}")
            b=f.astype('<f8',copy=False).tobytes(order='C'); got_sha=sha(b); exact=(got_sha==r['forecast_sha256'])
            absd=np.abs(f-cf); scale=np.maximum(1.0,np.abs(cf)); reld=absd/scale
            ulps=np.asarray([ulp_dist(x,y) for x,y in zip(f,cf)],dtype=object)
            max_abs=float(np.max(absd)); max_rel=float(np.max(reld)); max_ulp=max(int(x) for x in ulps)
            nonvals=sum(float(x)!=float(y) for x,y in zip(f,cf))
            cond=(out.diagnostics or {}).get('condition',None)
            st=group_stats[g]; st['arrays']+=1; st['values']+=nf
            if exact: st['exact_arrays']+=1
            else: st['nonexact_arrays']+=1
            st['nonexact_values']+=nonvals
            rec={
              'row':n,'parent_id':pid,'group':g,'config_id':cid,'h':h,'n_D':int(d['n_D']),
              'exact_sha':exact,'canonical_sha256':r['forecast_sha256'],'actual_sha256':got_sha,
              'max_abs':max_abs,'max_rel':max_rel,'max_ulp':max_ulp,'nonexact_values':nonvals,
              'condition':cond if cond is not None else '',
              'canonical_forecast_json':json.dumps([float(x) for x in cf],separators=(',',':')),
              'actual_forecast_json':json.dumps([float(x) for x in f],separators=(',',':')),
            }
            details.append(rec)
            for key,val in [('max_abs',max_abs),('max_rel',max_rel),('max_ulp',max_ulp)]:
                if val>st[key]:
                    st[key]=val; st['worst_'+key.split('_',1)[1]]=rec.copy()

    out_csv=Path(a.out_csv); out_json=Path(a.out_json); out_csv.parent.mkdir(parents=True,exist_ok=True)
    fields=['row','parent_id','group','config_id','h','n_D','exact_sha','canonical_sha256','actual_sha256','max_abs','max_rel','max_ulp','nonexact_values','condition','canonical_forecast_json','actual_forecast_json']
    with out_csv.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(details)
    buf=io.StringIO()
    with contextlib.redirect_stdout(buf): np.show_config()
    overall={
      'checkpoint':'STEP7E2_CROSSPLATFORM_R7_DIAGNOSTIC',
      'status':'BITWISE_EXACT' if all(r['exact_sha'] for r in details) else 'COMPLETE_WITH_PLATFORM_DIFFERENCES',
      'python':sys.version.split()[0],'numpy':np.__version__,'platform':sys.platform,
      'canonical_index_sha256':sha(Path(a.canonical_index).read_bytes()),
      'canonical_binary_sha256':sha(Path(a.canonical_binary).read_bytes()),
      'rows':len(details),'exact_arrays':sum(r['exact_sha'] for r in details),
      'nonexact_arrays':sum(not r['exact_sha'] for r in details),
      'groups':group_stats,'numpy_show_config':buf.getvalue(),
      'target_numeric_parsing':False,
      'out_csv':str(out_csv),
    }
    out_json.write_text(json.dumps(overall,indent=2,sort_keys=True),encoding='utf-8')
    print(json.dumps({k:overall[k] for k in ['checkpoint','status','python','numpy','platform','rows','exact_arrays','nonexact_arrays']},sort_keys=True))
    for g in ALLOWED_GROUPS:
        s=group_stats[g]
        print(f"DIAG {g} arrays={s['arrays']} exact={s['exact_arrays']} nonexact={s['nonexact_arrays']} nonexact_values={s['nonexact_values']} max_abs={s['max_abs']:.17g} max_rel={s['max_rel']:.17g} max_ulp={s['max_ulp']}")

if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--bundle',required=True); p.add_argument('--pretarget',required=True)
    p.add_argument('--d-helper',required=True); p.add_argument('--engine',required=True)
    p.add_argument('--canonical-index',required=True); p.add_argument('--canonical-binary',required=True)
    p.add_argument('--out-csv',required=True); p.add_argument('--out-json',required=True)
    main(p.parse_args())
