#!/usr/bin/env python3
from __future__ import annotations

import os
os.environ["OMP_NUM_THREADS"] = "1"
os.environ["OPENBLAS_NUM_THREADS"] = "1"
os.environ["MKL_NUM_THREADS"] = "1"
os.environ["VECLIB_MAXIMUM_THREADS"] = "1"
os.environ["NUMEXPR_NUM_THREADS"] = "1"

import argparse
import concurrent.futures
import csv
import dataclasses
import hashlib
import importlib.util
import io
import json
import platform
import shutil
import subprocess
import sys
import zipfile
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path

import numpy as np
import sklearn
import scipy
import joblib
import threadpoolctl
from sklearn.ensemble import RandomForestRegressor

GROUPS = [
    "SG01_CONT_GM","SG02_DISCRETE_POLY","SG03_FRAC_LINEAR","SG04_BERNOULLI",
    "SG05_CONT_TIME_POLY","SG06_CONFORMABLE","SG07_ROLLING","SG08_WBO",
    "SG09_GREY_MARKOV","SG10_SEASONAL","SG11_SELF_MEMORY","SG12_FRAC_DYNAMIC",
    "SG13_FRAC_BERNOULLI",
]
LEGACY = GROUPS[:10]
GIDX = {g:i for i,g in enumerate(GROUPS)}

EXPECTED = {
    "lock": "54D2CA4024510992BF494C82DA6F729423461E3893508524EB439659986E693F",
    "index": "8EEA756829B7A97F033EA81E5C2783528B68374A7B7549CE2D3EEA4D02D1C58B",
    "binary": "98648163F9ABE781EAA03EE49FD53D9BE1A33666F0A42BF7016B332F11E536F9",
    "p10_final": "35A97B99D62D00E3C5FC44E4611513281B4690DDF1E48105348315FDCEE420E3",
    "p1_seal": "04B3E677CA3DC0B0F9E8B6074656E1233769F70E3D76493CEDA83AAAE4EAE882",
    "p1_refusal_member": "606509431D83166E89E9D166FBFEC6B393A896D18B2614F45FCCB9571DD7D795",
    "p5_schema": "3ED14225EFC4FA9030BF114A466D1FBF410F47FE8CBE054AF446C4775E099D59",
    "p5_matrix": "507CEA9A4878ADFD7454E9E80B129006995E7E7A3F30E642AD1CE1A8AE10093B",
    "p6b_labels": "ECF821876B86C0A2B62A01E49ABBE539CFE616731C9D72EDF1DE6971C51F6435",
    "p7b_selector": "825F1DAF2B29EDD31FF4F5449ACEFDBD769EA36084C7224346D0A77FA623E3BB",
    "p7b_global": "91137509FD59059530E531E5FA75DB372C565024DF0BAE245C62A1D9373E7933",
    "p3_harness": "3CD58049273A796F3C4D8C726528571F17D51F59DC74E6688874F826024FC8B0",
    "p3_worker": "243FD64F99F3B0BB69492AE34876B156E2F8ABEDBF9152499EA271DDF789A45A",
    "c4_freeze": "7FCE8B071503D277425685BFA43569219D7AB9DBC8A227467342D7ACA1B0F774",
    "engine": "FC421E18E44C527C38E8DEDD3C30DE42506FA269AAD1498BAA56521DF21AA0F3",
    "sg11": "6F7AF041001107E06E444990EC9F7C21D8D0E2A1F360BB6A4DE98C4D23AD848C",
    "sg12": "8AEE4DFE49DF95DE9E9A15B123B2887A2AD66AF7C5695E837FB3807786E399F0",
    "sg13": "1E0C5710A82134ED8C08F27D856D560F3F7D2B524F5937BCD2E21F5074A8B618",
    "features": "BBBD645CFFAE6462EB50CBB9FF5FB902912E6204DF1AB5A9A316428D58B7A113",
    "r_preflight": "26B57ADA1A08CFC40CD11187A2C41BC34A8196D1E3504DD2880E1E39DEACFAD6",
    "newgroup_worker_r2": "F8E50E535E35F9D654EE55C21B2F8E23BA4F6C7E7698DF2641F492124F8C0F80",
    "r1_evidence": "F00AD7CEC6236E1DE87980901CD37B1A55B2C3A9E786B711729D16937828061F",
    "r2_evidence": "664A00306D57776C7C5D3FB469E14B18B41112025E3A5E3214A8761818FBE3EF",
    "r3_repair_lock": "4C7AD9E479EF946F04CE14F5059DB133EFFB17710E3947211AD4111C7B8208C2",
}

# Public-release portability adapter. Defaults preserve the frozen directory names,
# while environment variables allow a clean-room user/home without changing algorithms.
PUBLIC_HOME = Path(os.environ.get("AUTOGREY_WSL_HOME", str(Path.home()))).expanduser()
FROZEN_P3_RLIB = os.environ.get("AUTOGREY_P3_RLIB", str(PUBLIC_HOME / "autogrey_v2_p3_r5_rlib"))
FROZEN_P3_EMPTY_SITE = os.environ.get("AUTOGREY_P3_EMPTY_SITE", str(PUBLIC_HOME / "autogrey_v2_p3_r5_empty_site"))
FROZEN_P3_R_LD_LIBRARY_PATH = os.environ.get(
    "AUTOGREY_P3_R_LD_LIBRARY_PATH",
    f"{PUBLIC_HOME}/autogrey_v2_p3_r5_openblas_shim:/opt/autogrey-openblas-0.3.30-lp64-skylakex/lib:/usr/lib/R/lib",
)
FROZEN_P3_LD_LIBRARY_PATH = os.environ.get(
    "AUTOGREY_P3_LD_LIBRARY_PATH",
    f"{PUBLIC_HOME}/autogrey_v2_p3_r5_openblas_shim:/opt/autogrey-openblas-0.3.30-lp64-skylakex/lib",
)
EXPECTED_P6_PYTHON = Path(
    os.environ.get("AUTOGREY_P6_PYTHON", str(PUBLIC_HOME / ".autogrey_p6_selector" / "venv-py3135" / "bin" / "python"))
).expanduser()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest().upper()


def sha_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest().upper()


def json_dump(path: Path, obj):
    path.write_text(json.dumps(obj, sort_keys=True, indent=2, allow_nan=False) + "\n", encoding="utf-8", newline="\n")


def read_csv(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows, fields):
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def zip_member_bytes_by_basename(zip_path: Path, basename: str) -> bytes:
    with zipfile.ZipFile(zip_path, "r") as z:
        hits=[]
        for info in z.infolist():
            if info.is_dir():
                continue
            bname=info.filename.replace("\\", "/").rsplit("/",1)[-1]
            if bname == basename:
                hits.append(info.filename)
        if len(hits) != 1:
            raise AssertionError(f"R2 evidence member {basename!r}: expected exactly one hit, got {len(hits)}")
        return z.read(hits[0])


def require_r3_matches_r2_member(r3_path: Path, r2_zip: Path, r2_basename: str, label: str):
    ref=zip_member_bytes_by_basename(r2_zip,r2_basename)
    got=sha256(r3_path); exp=sha_bytes(ref)
    if got != exp:
        raise AssertionError(f"R3/R2 pre-repair reproduction mismatch {label}: {got} != {exp}")
    return got


def seed_r3_checkpoints_from_r2_evidence(r2_zip: Path, out: Path, idx):
    checkpoint_dir=out / "NEWGROUP_CHECKPOINTS_R2"
    checkpoint_dir.mkdir(parents=True,exist_ok=True)
    imported=0
    for cid,start in enumerate(range(1,len(idx)+1,R2_CHUNK_SIZE),1):
        end=min(len(idx),start+R2_CHUNK_SIZE-1)
        sl=idx[start-1:end]
        ap,fp,cp,lp=_chunk_paths(checkpoint_dir,cid)
        names={
          ap:f"CHUNK_{cid:03d}_AUDIT.csv",
          fp:f"CHUNK_{cid:03d}_FORECASTS.csv",
          cp:f"CHUNK_{cid:03d}_COMMIT.json",
        }
        for dest,bname in names.items():
            b=zip_member_bytes_by_basename(r2_zip,bname)
            if dest.exists() and dest.read_bytes()!=b:
                raise AssertionError(f"existing R3 checkpoint differs from preserved R2 evidence: {dest.name}")
            if not dest.exists():
                dest.write_bytes(b)
        if not _valid_committed_chunk(cp,ap,fp,sl,start,end):
            raise AssertionError(f"imported R2 checkpoint failed validation: chunk {cid}")
        imported += 1
    if imported != 48:
        raise AssertionError(f"expected 48 imported R2 checkpoint chunks, got {imported}")
    print(f"P11A2_R3_IMPORTED_R2_CHECKPOINT_CHUNKS={imported}",flush=True)
    return imported


FLOAT32_MAX = float(np.finfo(np.float32).max)


def predict_with_representability_adapter(model, X, predictor_ids, parent_ids, group, audit_rows):
    raw=np.asarray(X,dtype=np.float64)
    if not np.all(np.isfinite(raw)):
        raise AssertionError("selector adapter received nonfinite post-imputation matrix")
    adapted=raw.copy()
    bad=np.argwhere(np.abs(raw) > FLOAT32_MAX)
    for i,j in bad:
        rv=float(raw[i,j])
        av=float(np.copysign(FLOAT32_MAX,rv))
        checked=0
        for est in model.estimators_:
            t=est.tree_
            nodes=np.flatnonzero(t.feature == int(j))
            if nodes.size:
                th=np.asarray(t.threshold[nodes],dtype=np.float64)
                if np.any((rv <= th) != (av <= th)):
                    raise AssertionError(f"representability adapter branch mismatch {group} {parent_ids[int(i)]} {predictor_ids[int(j)]}")
                checked += int(nodes.size)
        adapted[int(i),int(j)] = av
        audit_rows.append({
            "group":group,"parent_id":parent_ids[int(i)],"predictor_id":predictor_ids[int(j)],
            "raw_float64":format(rv,".17g"),"adapted_prediction_boundary_value":format(av,".17g"),
            "tree_threshold_nodes_checked":checked,"branch_equivalent":"TRUE",
        })
    if np.any(np.abs(adapted) > FLOAT32_MAX) or not np.all(np.isfinite(adapted)):
        raise AssertionError("representability adapter did not produce finite float32-representable input")
    return np.asarray(model.predict(adapted),dtype=np.float64), int(len(bad))


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, str(path))
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def direct_forecast(obj, h):
    if obj is None:
        return None
    if dataclasses.is_dataclass(obj):
        names = {f.name for f in dataclasses.fields(obj)}
        if "forecast" not in names:
            return None
        fc = getattr(obj, "forecast")
    elif isinstance(obj, dict):
        fc = obj.get("forecast")
    else:
        return None
    if fc is None:
        return None
    try:
        z = np.asarray(fc, dtype=np.float64).reshape(-1)
    except Exception:
        return None
    if len(z) != h or not np.all(np.isfinite(z)):
        return None
    return z


def canonical_forecast_hash(x):
    s = ",".join(format(float(v), ".17g") for v in np.asarray(x, dtype=np.float64).reshape(-1))
    return hashlib.sha256(s.encode("utf-8")).hexdigest().upper()


def le_f64_bytes(x):
    return np.ascontiguousarray(np.asarray(x, dtype="<f8")).tobytes()


def medians(X):
    out = np.zeros(X.shape[1], dtype=np.float64)
    for j in range(X.shape[1]):
        z = X[:, j]
        good = np.isfinite(z)
        out[j] = float(np.median(z[good])) if np.any(good) else 0.0
    return out


def impute(X, med):
    z = np.asarray(X, dtype=np.float64).copy()
    rr, cc = np.where(~np.isfinite(z))
    if len(rr):
        z[rr, cc] = med[cc]
    if not np.all(np.isfinite(z)):
        raise AssertionError("imputation left nonfinite")
    return z


def forest_fingerprint(model, med, group):
    h = hashlib.sha256()
    h.update(group.encode())
    h.update(le_f64_bytes(med))
    h.update(json.dumps(model.get_params(deep=False), sort_keys=True, default=str).encode())
    for est in model.estimators_:
        t = est.tree_
        for arr in (t.children_left,t.children_right,t.feature,t.threshold,t.value,t.impurity,t.n_node_samples,t.weighted_n_node_samples):
            a = np.ascontiguousarray(arr)
            h.update(str(a.dtype).encode())
            h.update(str(a.shape).encode())
            h.update(a.tobytes())
    return h.hexdigest().upper()


def sg_index(g):
    return int(g[2:4])


def owner_for_collision(a, b):
    al = a in LEGACY
    bl = b in LEGACY
    if al and not bl:
        return a, b
    if bl and not al:
        return b, a
    return (a, b) if sg_index(a) < sg_index(b) else (b, a)


def pair_class(a, b):
    al = a in LEGACY
    bl = b in LEGACY
    if al and bl:
        return "LEGACY_LEGACY"
    if al != bl:
        return "LEGACY_NEW"
    return "NEW_NEW"


def booltxt(x):
    return "TRUE" if x else "FALSE"


def read_p1_refusals(seal_zip: Path):
    found = None
    with zipfile.ZipFile(seal_zip, "r") as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            b = z.read(info.filename)
            if sha_bytes(b) == EXPECTED["p1_refusal_member"]:
                found = b
                break
    if found is None:
        raise AssertionError("P1 refusal ledger member missing")
    return list(csv.DictReader(io.StringIO(found.decode("utf-8-sig"))))



NEW_GROUPS = GROUPS[10:]
R2_CHUNK_SIZE = 100
R2_MAX_PARALLEL_R_WORKERS = 4

def _chunk_paths(checkpoint_dir: Path, chunk_id: int):
    stem = f"CHUNK_{chunk_id:03d}"
    return (checkpoint_dir / f"{stem}_AUDIT.csv", checkpoint_dir / f"{stem}_FORECASTS.csv",
            checkpoint_dir / f"{stem}_COMMIT.json", checkpoint_dir / f"{stem}.log")

def _validate_newgroup_chunk(audit_path: Path, forecast_path: Path, idx_slice):
    if not audit_path.is_file() or not forecast_path.is_file():
        raise AssertionError("checkpoint chunk output missing")
    audit = read_csv(audit_path)
    forecasts = read_csv(forecast_path)
    expected_keys = [(r["parent_id"], g) for r in idx_slice for g in NEW_GROUPS]
    got_keys = [(r["parent_id"], r["group"]) for r in audit]
    if got_keys != expected_keys:
        raise AssertionError("checkpoint audit key/order mismatch")
    meta_local = {r["parent_id"]: (r["source_id"], int(r["h"])) for r in idx_slice}
    f_by = defaultdict(list)
    for r in forecasts:
        k = (r["parent_id"], r["group"])
        if r["parent_id"] not in meta_local or r["group"] not in NEW_GROUPS:
            raise AssertionError("checkpoint forecast foreign key")
        if r["source_id"] != meta_local[r["parent_id"]][0] or int(r["h"]) != meta_local[r["parent_id"]][1]:
            raise AssertionError("checkpoint forecast metadata mismatch")
        val = float(r["forecast"])
        if not np.isfinite(val):
            raise AssertionError("checkpoint nonfinite forecast")
        f_by[k].append((int(r["step"]), val))
    for a in audit:
        k=(a["parent_id"], a["group"]); h=meta_local[a["parent_id"]][1]
        rows=sorted(f_by.get(k, []))
        if a["final_status"] == "OK":
            if [x[0] for x in rows] != list(range(1,h+1)):
                raise AssertionError(f"checkpoint successful forecast shape mismatch {k}")
        elif rows:
            raise AssertionError(f"checkpoint failed status unexpectedly has forecast {k}")
    return audit, forecasts

def _valid_committed_chunk(commit_path: Path, audit_path: Path, forecast_path: Path, idx_slice, start_row: int, end_row: int):
    if not commit_path.is_file():
        return False
    try:
        c=json.loads(commit_path.read_text(encoding="utf-8"))
        if c.get("schema") != "AUTOGREY_V2_P11A2_FINAL_R2_CHUNK_COMMIT" or int(c.get("start_row")) != start_row or int(c.get("end_row")) != end_row:
            return False
        if c.get("audit_sha256") != sha256(audit_path) or c.get("forecast_sha256") != sha256(forecast_path):
            return False
        a,f=_validate_newgroup_chunk(audit_path,forecast_path,idx_slice)
        return int(c.get("audit_rows")) == len(a) and int(c.get("forecast_rows")) == len(f)
    except Exception:
        return False

def run_checkpointed_newgroups(rscript: str, P, idx, r_env, out: Path):
    checkpoint_dir=out / "NEWGROUP_CHECKPOINTS_R2"
    checkpoint_dir.mkdir(parents=True,exist_ok=True)
    chunks=[]
    cid=0
    for start in range(1,len(idx)+1,R2_CHUNK_SIZE):
        cid += 1; end=min(len(idx),start+R2_CHUNK_SIZE-1)
        chunks.append((cid,start,end,idx[start-1:end]))
    complete=[]; pending=[]
    for cid,start,end,sl in chunks:
        ap,fp,cp,lp=_chunk_paths(checkpoint_dir,cid)
        if _valid_committed_chunk(cp,ap,fp,sl,start,end):
            complete.append(cid)
        else:
            for p in (ap,fp,cp):
                if p.exists(): p.unlink()
            pending.append((cid,start,end,sl))
    print(f"P11A2_R3_CHECKPOINT_CHUNKS_TOTAL={len(chunks)}",flush=True)
    print(f"P11A2_R3_CHECKPOINT_CHUNKS_REUSED={len(complete)}",flush=True)
    print(f"P11A2_R3_CHECKPOINT_CHUNKS_PENDING={len(pending)}",flush=True)

    def one(job):
        cid,start,end,sl=job
        ap,fp,cp,lp=_chunk_paths(checkpoint_dir,cid)
        at=checkpoint_dir/f"CHUNK_{cid:03d}_AUDIT.tmp.csv"
        ft=checkpoint_dir/f"CHUNK_{cid:03d}_FORECASTS.tmp.csv"
        for p in (at,ft):
            if p.exists(): p.unlink()
        proc=subprocess.run([rscript,"--vanilla",str(P["newgroup-worker"]),str(P["index"]),str(P["binary"]),
            str(P["sg11"]),str(P["sg12"]),str(P["sg13"]),str(start),str(end),str(at),str(ft)],
            text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=r_env)
        lp.write_text(proc.stdout or "",encoding="utf-8",newline="\n")
        if proc.returncode != 0:
            raise RuntimeError(f"R2 new-group chunk {cid} rows {start}-{end} failed rc={proc.returncode}; log={lp}")
        arows,frows=_validate_newgroup_chunk(at,ft,sl)
        os.replace(at,ap); os.replace(ft,fp)
        marker={"schema":"AUTOGREY_V2_P11A2_FINAL_R2_CHUNK_COMMIT","chunk_id":cid,"start_row":start,"end_row":end,
            "parent_n":end-start+1,"audit_rows":len(arows),"forecast_rows":len(frows),
            "audit_sha256":sha256(ap),"forecast_sha256":sha256(fp),"worker_sha256":EXPECTED["newgroup_worker_r2"],
            "REALBENCH3_TARGET_VALUES_OPENED":False}
        json_dump(cp,marker)
        return cid,start,end,len(arows),len(frows)

    if pending:
        failures=[]
        with concurrent.futures.ThreadPoolExecutor(max_workers=R2_MAX_PARALLEL_R_WORKERS) as ex:
            futs={ex.submit(one,j):j for j in pending}
            for fut in concurrent.futures.as_completed(futs):
                job=futs[fut]
                try:
                    cid,start,end,na,nf=fut.result()
                    complete.append(cid)
                    print(f"P11A2_R3_CHUNK_COMMITTED={cid}/{len(chunks)} ROWS={start}-{end} AUDIT={na} FORECAST={nf} COMPLETE_CHUNKS={len(complete)}",flush=True)
                except Exception as e:
                    failures.append((job,e))
                    print(f"P11A2_R3_CHUNK_ERROR={job[0]}:{type(e).__name__}:{e}",file=sys.stderr,flush=True)
        if failures:
            raise RuntimeError(f"{len(failures)} R2 new-group chunk(s) failed; completed chunks remain resumable")

    audit_all=[]; forecast_all=[]
    for cid,start,end,sl in chunks:
        ap,fp,cp,lp=_chunk_paths(checkpoint_dir,cid)
        if not _valid_committed_chunk(cp,ap,fp,sl,start,end):
            raise AssertionError(f"R2 checkpoint validation failed at chunk {cid}")
        a,f=_validate_newgroup_chunk(ap,fp,sl)
        audit_all.extend(a); forecast_all.extend(f)
    expected_keys=[(r["parent_id"],g) for r in idx for g in NEW_GROUPS]
    if [(r["parent_id"],r["group"]) for r in audit_all] != expected_keys:
        raise AssertionError("R2 merged audit order mismatch")
    out_audit=out/"AUTOGREY_V2_P11A2_FINAL_NEWGROUP_CONFIG_AUDIT_R3.csv"
    out_fc=out/"AUTOGREY_V2_P11A2_FINAL_NEWGROUP_FORECASTS_R3.csv"
    write_csv(out_audit,audit_all,["parent_id","group","eligible_config_count","selected_config_id","selected_inner_loss","final_status"])
    write_csv(out_fc,forecast_all,["parent_id","source_id","h","group","step","forecast"])
    print(f"P11A2_R3_NEWGROUP_MERGE_AUDIT_ROWS={len(audit_all)}",flush=True)
    print(f"P11A2_R3_NEWGROUP_MERGE_FORECAST_ROWS={len(forecast_all)}",flush=True)
    return out_audit,out_fc,len(chunks)

def main():
    ap = argparse.ArgumentParser()
    for x in [
        "lock","index","binary","p10-final","p1-seal","p5-schema","p5-matrix","p6b-labels",
        "p7b-selector","p7b-global","p3-harness","p3-worker","c4-freeze","engine","sg11","sg12",
        "sg13","features","r-preflight","newgroup-worker","r3-repair-lock","r1-evidence","r2-evidence","outdir"
    ]:
        ap.add_argument("--" + x, required=True)
    a = ap.parse_args()
    out = Path(a.outdir)
    first_start = not out.exists()
    if first_start:
        out.mkdir(parents=True)
    else:
        final_evidence = out / "AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_R3.txt"
        final_manifest = out / "AUTOGREY_V2_P11A2_FINAL_MANIFEST_R3.sha256"
        if final_evidence.exists() or final_manifest.exists():
            print(f"STOP_FINAL_EVIDENCE_ALREADY_EXISTS={out}")
            print("Nothing overwritten.")
            return 90
    (out / "P3_RAW_BATCHES").mkdir(exist_ok=True)

    keys = [
        "lock","index","binary","p10-final","p1-seal","p5-schema","p5-matrix","p6b-labels",
        "p7b-selector","p7b-global","p3-harness","p3-worker","c4-freeze","engine","sg11","sg12",
        "sg13","features","r-preflight","newgroup-worker","r3-repair-lock","r1-evidence","r2-evidence"
    ]
    P = {k: Path(getattr(a, k.replace("-", "_"))) for k in keys}
    gate_map = {
        "lock":"lock", "index":"index","binary":"binary","p10-final":"p10_final","p1-seal":"p1_seal",
        "p5-schema":"p5_schema","p5-matrix":"p5_matrix","p6b-labels":"p6b_labels",
        "p7b-selector":"p7b_selector","p7b-global":"p7b_global","p3-harness":"p3_harness",
        "p3-worker":"p3_worker","c4-freeze":"c4_freeze","engine":"engine","sg11":"sg11",
        "sg12":"sg12","sg13":"sg13","features":"features","r-preflight":"r_preflight",
        "newgroup-worker":"newgroup_worker_r2","r3-repair-lock":"r3_repair_lock","r1-evidence":"r1_evidence","r2-evidence":"r2_evidence",
    }

    lines = [
        "AUTOGREY V2 P11-A2 FINAL TARGET-FREE PRODUCTION R3",
        "===================================================",
        "",
        "CHECKPOINT=V2-P11A2_FINAL_TARGET_FREE_PRODUCTION",
        "REALBENCH3_TARGET_VALUES_OPENED=FALSE",
        "REALBENCH3_NUMERIC_TARGET_PARSE=FALSE",
        "REALBENCH3_TARGET_SCORING=FALSE",
        "P11_B=LOCKED",
        "R1_CLASSIFICATION=INCONCLUSIVE_RUNTIME_PRACTICALITY_TERMINATION",
        "R1_PROGRESS_AT_TERMINATION=3600/4781",
        "R2_CLASSIFICATION=INCONCLUSIVE_FLOAT32_SELECTOR_INPUT_REPRESENTABILITY_ERROR",
        "R3_REPAIR_SCOPE=SELECTOR_INPUT_NUMERIC_REPRESENTABILITY_ONLY",
        "R3_RAW_FEATURE_MATRIX_CHANGED=FALSE",
        "",
        "===== INPUT IDENTITY GATE =====",
    ]
    for argk, exk in gate_map.items():
        got = sha256(P[argk])
        lines.append(f"{argk.upper().replace('-', '_')}_SHA256={got}")
        if got != EXPECTED[exk]:
            raise AssertionError(f"{argk} hash mismatch: {got} != {EXPECTED[exk]}")

    lock = json.loads(P["lock"].read_text(encoding="utf-8"))
    if lock.get("checkpoint") != "V2-P11A2_FINAL_TARGET_FREE_PRODUCTION" or lock.get("REALBENCH3_TARGET_VALUES_OPENED") is not False:
        raise AssertionError("bad P11-A2 final scientific lock")
    repair = json.loads(P["r3-repair-lock"].read_text(encoding="utf-8"))
    if repair.get("schema") != "AUTOGREY_V2_P11A2_FINAL_SELECTOR_REPRESENTABILITY_REPAIR_LOCK_R3" or repair.get("scientific_lock_r1_sha256") != EXPECTED["lock"]:
        raise AssertionError("bad P11-A2 final R3 selector representability repair lock")
    if repair.get("r2_evidence_sha256") != EXPECTED["r2_evidence"]:
        raise AssertionError("R3 repair lock R2 evidence identity mismatch")
    if repair.get("REALBENCH3_TARGET_VALUES_OPENED") is not False or repair.get("P11_B") != "LOCKED":
        raise AssertionError("R3 repair lock violates target boundary")
    c4 = json.loads(P["c4-freeze"].read_text(encoding="utf-8"))
    if c4.get("classification") != "PASS" or c4.get("safety", {}).get("REALBENCH3_TARGETS_OPENED") is not False:
        raise AssertionError("P11-A2C4 freeze is not PASS/unopened")
    if c4["frozen_implementation_identities"]["engine_sg03_sha256"] != EXPECTED["engine"]:
        raise AssertionError("C4 engine identity mismatch")
    if c4["frozen_implementation_identities"]["sg12_candidate_sha256"] != EXPECTED["sg12"]:
        raise AssertionError("C4 SG12 identity mismatch")
    if c4["frozen_implementation_identities"]["sg13_candidate_sha256"] != EXPECTED["sg13"]:
        raise AssertionError("C4 SG13 identity mismatch")
    if (P["p3-harness"].parent / P["p3-worker"].name).resolve() != P["p3-worker"].resolve():
        raise AssertionError("P3 harness/worker are not the exact sibling pair")
    lines.append("INPUT_IDENTITY_GATE=PASS")
    resume_state = out / "AUTOGREY_V2_P11A2_FINAL_R3_RESUME_STATE.json"
    state_obj = {
        "schema":"AUTOGREY_V2_P11A2_FINAL_R3_RESUME_STATE",
        "scientific_lock_sha256":EXPECTED["lock"],"r3_repair_lock_sha256":EXPECTED["r3_repair_lock"],
        "r1_evidence_sha256":EXPECTED["r1_evidence"],"r2_evidence_sha256":EXPECTED["r2_evidence"],"chunk_size":R2_CHUNK_SIZE,
        "max_parallel_r_workers":R2_MAX_PARALLEL_R_WORKERS,"REALBENCH3_TARGET_VALUES_OPENED":False
    }
    if resume_state.exists():
        if json.loads(resume_state.read_text(encoding="utf-8")) != state_obj:
            raise AssertionError("R3 resume-state identity mismatch")
        lines.append("R3_RESUME_STATE=VERIFIED")
    else:
        json_dump(resume_state,state_obj)
        lines.append("R3_RESUME_STATE=CREATED")

    versions = (platform.python_version(), np.__version__, sklearn.__version__, scipy.__version__, joblib.__version__, threadpoolctl.__version__)
    if Path(sys.executable).resolve() != EXPECTED_P6_PYTHON.resolve():
        raise AssertionError(f"wrong Python executable: {sys.executable}; expected={EXPECTED_P6_PYTHON}")
    if versions != ("3.13.5","2.3.5","1.8.0","1.18.1","1.6.0","3.7.0"):
        raise AssertionError(f"Python runtime mismatch: {versions}")
    lines += ["", "===== PYTHON RUNTIME GATE =====", f"PYTHON={sys.executable}", f"VERSIONS={'|'.join(versions)}", "PYTHON_RUNTIME_GATE=PASS"]

    idx = read_csv(P["index"])
    if len(idx) != 4781 or len({r["parent_id"] for r in idx}) != 4781:
        raise AssertionError("P11-A1 index count/uniqueness mismatch")
    if any(str(r["target_tokens_numeric_parsed"]).strip().upper() != "FALSE" for r in idx):
        raise AssertionError("target parse flag is not FALSE")
    if sum(int(r["binary_length_values"]) for r in idx) != 47000025:
        raise AssertionError("development value total mismatch")

    mm = np.memmap(P["binary"], dtype="<f8", mode="r")
    Dmap = {}
    meta = {}
    d_hash_ok = 0
    for i, r in enumerate(idx, 1):
        off = int(r["binary_offset_bytes"]) // 8
        n = int(r["binary_length_values"])
        D = np.asarray(mm[off:off+n], dtype=np.float64)
        if len(D) != n or not np.all(np.isfinite(D)):
            raise AssertionError(f"invalid D slice: {r['parent_id']}")
        dh = hashlib.sha256(D.astype("<f8", copy=False).tobytes()).hexdigest().upper()
        if dh != r["development_float64_le_sha256"].upper():
            raise AssertionError(f"D hash mismatch: {r['parent_id']}")
        d_hash_ok += 1
        pid = r["parent_id"]
        Dmap[pid] = D
        mt = (r.get("M") or "").strip()
        M = None if mt == "" else int(float(mt))
        meta[pid] = {
            "source_id": r["source_id"], "h": int(r["h"]), "M": M, "n_D": n,
            "frequency": r.get("frequency", ""), "dataset": r.get("dataset", "")
        }
    lines += ["", "===== P11-A1 DEVELOPMENT VERIFY =====", f"CLEAN_PARENT_N={len(idx)}", f"D_HASH_MATCH_N={d_hash_ok}", "TARGET_NUMERIC_PARSE=FALSE"]

    census = [
        {
            "parent_id": r["parent_id"], "source_id": r["source_id"], "h": r["h"], "M": r.get("M", ""),
            "n_D": r["n_D_token_count"], "frequency": r.get("frequency", ""), "dataset": r.get("dataset", ""),
            "development_float64_le_sha256": r["development_float64_le_sha256"],
        }
        for r in idx
    ]
    out_census = out / "AUTOGREY_V2_P11A2_FINAL_CLEAN_PARENT_CENSUS_R3.csv"
    write_csv(out_census, census, list(census[0]))

    rscript = shutil.which("Rscript")
    if not rscript:
        raise FileNotFoundError("Rscript not found")
    r_env = os.environ.copy()
    r_env.update({
        "R_LIBS_USER": FROZEN_P3_RLIB,
        "R_LIBS_SITE": FROZEN_P3_EMPTY_SITE,
        "R_LD_LIBRARY_PATH": FROZEN_P3_R_LD_LIBRARY_PATH,
        "LD_LIBRARY_PATH": FROZEN_P3_LD_LIBRARY_PATH,
        "OMP_NUM_THREADS":"1","OPENBLAS_NUM_THREADS":"1","MKL_NUM_THREADS":"1",
        "VECLIB_MAXIMUM_THREADS":"1","NUMEXPR_NUM_THREADS":"1","TZ":"UTC","LANG":"C","LC_ALL":"C",
    })
    cp = subprocess.run([rscript, "--vanilla", str(P["r-preflight"])], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=r_env)
    print(cp.stdout, end="" if cp.stdout.endswith("\n") else "\n", flush=True)
    if cp.returncode != 0:
        raise RuntimeError(f"R runtime preflight failed rc={cp.returncode}")

    print("===== IMPORTING + VERIFYING P11-A2 R2 COMMITTED NEW-GROUP CHECKPOINTS =====", flush=True)
    imported_r2_chunks = seed_r3_checkpoints_from_r2_evidence(P["r2-evidence"], out, idx)
    print("===== RUNNING P11-A2 R3 CHECKPOINTED NEW-GROUP D-ONLY CONFIG SELECTION =====", flush=True)
    # Runtime syntax parse for the new execution-only worker before any chunk is launched.
    parse_expr = f"parse(file={json.dumps(str(P['newgroup-worker']))})"
    cp_parse = subprocess.run([rscript,"--vanilla","-e",parse_expr], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=r_env)
    if cp_parse.returncode != 0:
        print(cp_parse.stdout, file=sys.stderr, flush=True)
        raise RuntimeError(f"R2 new-group worker parse failed rc={cp_parse.returncode}")
    out_new_audit, out_new_fc, newgroup_chunk_n = run_checkpointed_newgroups(rscript,P,idx,r_env,out)

    require_r3_matches_r2_member(out_new_audit,P["r2-evidence"],"AUTOGREY_V2_P11A2_FINAL_NEWGROUP_CONFIG_AUDIT_R2.csv","NEWGROUP_CONFIG_AUDIT")
    require_r3_matches_r2_member(out_new_fc,P["r2-evidence"],"AUTOGREY_V2_P11A2_FINAL_NEWGROUP_FORECASTS_R2.csv","NEWGROUP_FORECASTS")
    new_audit = read_csv(out_new_audit)
    new_fc_rows = read_csv(out_new_fc)
    if len(new_audit) != 4781 * 3:
        raise AssertionError(f"new-group audit rows={len(new_audit)}")
    newmap = defaultdict(list)
    for r in new_fc_rows:
        newmap[(r["parent_id"], r["group"])].append((int(r["step"]), float(r["forecast"])))
    for k in list(newmap):
        newmap[k] = np.asarray([v for _, v in sorted(newmap[k])], dtype=np.float64)

    eng = load_module(P["engine"], "autogrey_engine_step4fb_r1_p11a2_final_r2")
    action_forecasts = {}
    parent_rows = []
    group_rows = []
    edge_rows = []
    comparison_count = Counter()
    collision4 = Counter()
    collision3 = Counter()
    collision2 = Counter()
    available_occ = Counter()
    retained_occ = Counter()
    removed_occ = Counter()

    for ii, r in enumerate(idx, 1):
        pid = r["parent_id"]
        m = meta[pid]
        D = Dmap[pid]
        h = m["h"]
        M = m["M"]
        portfolio = eng.run_portfolio(D, h, M)
        forecasts = {}
        for g in LEGACY:
            fc = direct_forecast(portfolio.group_results.get(g), h)
            if fc is not None:
                forecasts[g] = fc
        for g in GROUPS[10:]:
            fc = newmap.get((pid, g))
            if fc is not None:
                if len(fc) != h or not np.all(np.isfinite(fc)):
                    raise AssertionError(f"invalid new-group forecast: {pid} {g}")
                forecasts[g] = fc
        available = [g for g in GROUPS if g in forecasts]
        for g in available:
            available_occ[g] += 1
        denom = max(float(np.mean(np.abs(D))), 1e-12)
        lost_to = defaultdict(set)
        for ga, gb in combinations(available, 2):
            d = float(np.max(np.abs(forecasts[ga] - forecasts[gb])) / denom)
            cls = pair_class(ga, gb)
            comparison_count[cls] += 1
            collision4[cls] += int(d <= 1e-4)
            collision3[cls] += int(d <= 1e-3)
            collision2[cls] += int(d <= 1e-2)
            if d <= 1e-3:
                ow, loser = owner_for_collision(ga, gb)
                lost_to[loser].add(ow)
                edge_rows.append({
                    "parent_id": pid, "group_a": ga, "group_b": gb, "pair_class": cls,
                    "d_inf": format(d, ".17g"), "owner": ow, "removed_group": loser,
                    "owner_rule": "EXISTING_BEATS_NEW_OTHERWISE_LOWER_SG",
                })
        retained, removed = [], []
        for g in available:
            if lost_to.get(g):
                removed.append(g)
                removed_occ[g] += 1
            else:
                retained.append(g)
                retained_occ[g] += 1
        nret = len(retained)
        status = "ABSTAIN_NO_GREY" if nret == 0 else ("SINGLETON_NO_SELECTOR_CALL" if nret == 1 else "SELECTOR_MAY_ACT_LATER")
        parent_rows.append({
            "parent_id": pid, "source_id": m["source_id"], "h": h, "M": "" if M is None else M,
            "n_D": m["n_D"], "available_pre_collision": len(available), "retained_post_collision": nret,
            "resolution_status": status, "retained_groups": ";".join(retained), "removed_groups": ";".join(removed),
        })
        for g in GROUPS:
            av = g in available
            rt = g in retained
            owners = sorted(lost_to.get(g, set()), key=sg_index)
            reason = "NOT_ELIGIBLE_OR_FINAL_FORECAST_FAIL" if not av else ("RETAINED" if rt else "PRIMARY_COLLISION_LOSS")
            group_rows.append({
                "parent_id": pid, "group": g, "available_pre_collision": booltxt(av),
                "retained_post_collision": booltxt(rt), "removal_reason": reason, "collision_owners": ";".join(owners),
            })
        for g in retained:
            action_forecasts[(pid, g)] = np.asarray(forecasts[g], dtype=np.float64)
        if ii % 25 == 0 or ii == len(idx):
            print(f"P11A2_GREY_ACTION_PROGRESS={ii}/{len(idx)}", flush=True)

    out_action = out / "AUTOGREY_V2_P11A2_FINAL_ACTIONABILITY_LEDGER_R3.csv"
    out_group = out / "AUTOGREY_V2_P11A2_FINAL_GROUP_ACTION_LEDGER_R3.csv"
    out_edges = out / "AUTOGREY_V2_P11A2_FINAL_COLLISION_EDGES_R3.csv"
    write_csv(out_action, parent_rows, list(parent_rows[0]))
    write_csv(out_group, group_rows, list(group_rows[0]))
    write_csv(out_edges, edge_rows, ["parent_id","group_a","group_b","pair_class","d_inf","owner","removed_group","owner_rule"])
    r2_preselector_repro = {
        "actionability": require_r3_matches_r2_member(out_action,P["r2-evidence"],"AUTOGREY_V2_P11A2_FINAL_ACTIONABILITY_LEDGER_R2.csv","ACTIONABILITY_LEDGER"),
        "group_action": require_r3_matches_r2_member(out_group,P["r2-evidence"],"AUTOGREY_V2_P11A2_FINAL_GROUP_ACTION_LEDGER_R2.csv","GROUP_ACTION_LEDGER"),
        "collision_edges": require_r3_matches_r2_member(out_edges,P["r2-evidence"],"AUTOGREY_V2_P11A2_FINAL_COLLISION_EDGES_R2.csv","COLLISION_EDGES"),
    }

    feature = load_module(P["features"], "autogrey_features_step4e_p11a2_final")
    if str(feature.FEATURE_VERSION) != "AG_FEAT_4E_1" or len(feature.FEATURE_NAMES) != 23:
        raise AssertionError("feature authority mismatch")
    schema = read_csv(P["p5-schema"])
    pred = [r["predictor_id"] for r in schema]
    expected_ids = [f"F{i:02d}_VALUE" for i in range(1,24)] + [f"F{i:02d}_VALID" for i in range(1,24)] + [f"SG{i:02d}_SELECTABLE" for i in range(1,14)]
    if pred != expected_ids:
        raise AssertionError("59-coordinate schema/order mismatch")

    pmap = {r["parent_id"]: r for r in parent_rows}
    Xf = np.empty((4781, 59), dtype=np.float64)
    matrix_rows = []
    for i, r in enumerate(idx):
        pid = r["parent_id"]
        m = meta[pid]
        snap = feature.extract_features(Dmap[pid], m["h"], m["M"])
        vals = np.asarray(snap.values, dtype=np.float64).copy()
        valid = np.asarray(snap.valid_mask, dtype=bool)
        vals[~valid] = np.nan
        retained = {x for x in pmap[pid]["retained_groups"].split(";") if x}
        sel = np.asarray([1.0 if g in retained else 0.0 for g in GROUPS])
        Xf[i, 0:23] = vals
        Xf[i, 23:46] = valid.astype(float)
        Xf[i, 46:59] = sel
        row = {
            "parent_id": pid, "source_id": m["source_id"], "h": m["h"], "M": "" if m["M"] is None else m["M"],
            "development_n": m["n_D"], "train_hash": snap.train_hash, "feature_hash": snap.feature_hash,
        }
        for j, c in enumerate(pred):
            row[c] = "" if j < 23 and np.isnan(Xf[i, j]) else (format(float(Xf[i, j]), ".17g") if j < 23 else str(int(Xf[i, j])))
        matrix_rows.append(row)
        if (i + 1) % 100 == 0 or i + 1 == len(idx):
            print(f"P11A2_FEATURE_PROGRESS={i+1}/{len(idx)}", flush=True)
    out_matrix = out / "AUTOGREY_V2_P11A2_FINAL_META_FEATURE_MATRIX_59_R3.csv"
    write_csv(out_matrix, matrix_rows, list(matrix_rows[0]))
    r2_preselector_repro["meta_feature_matrix"] = require_r3_matches_r2_member(out_matrix,P["r2-evidence"],"AUTOGREY_V2_P11A2_FINAL_META_FEATURE_MATRIX_59_R2.csv","META_FEATURE_MATRIX")
    print("P11A2_R3_PRESELECTOR_R2_REPRODUCTION=PASS",flush=True)

    train_rows = read_csv(P["p5-matrix"])
    trainX = {
        rr["parent_id"]: np.asarray([np.nan if (rr[c] or "").strip() == "" else float(rr[c]) for c in pred], dtype=np.float64)
        for rr in train_rows
    }
    labels = defaultdict(list)
    for rr in read_csv(P["p6b-labels"]):
        labels[rr["action_group"]].append({
            "pid": rr["parent_id"], "y": float(rr["target_log1p_regret"]), "weight": float(rr["action_row_weight"]),
        })
    p7id = json.loads(P["p7b-selector"].read_text(encoding="utf-8"))
    rfparams = dict(
        n_estimators=500, criterion="squared_error", max_depth=8, min_samples_split=2,
        min_samples_leaf=0.01, max_features="sqrt", bootstrap=True, oob_score=False,
        n_jobs=1, random_state=62291, max_samples=None, ccp_alpha=0.0,
    )
    pred_mu = defaultdict(dict)
    adapter_rows = []
    selector_identity = {
        "schema": "AUTOGREY_V2_P11A2_FINAL_SELECTOR_IDENTITY_R3", "selector": "RF_D8_L001",
        "groups": {}, "realbench3_parent_count": 4781, "realbench3_targets_opened": False,
    }
    for gi, g in enumerate(GROUPS, 1):
        rr = labels[g]
        gp = [z["pid"] for z in rr]
        Xt = np.vstack([trainX[p] for p in gp])
        med = medians(Xt)
        model = RandomForestRegressor(**rfparams)
        model.fit(impute(Xt, med), np.asarray([z["y"] for z in rr]), sample_weight=np.asarray([z["weight"] for z in rr]))
        fp = forest_fingerprint(model, med, g)
        exp = p7id["groups"][g]["forest_fingerprint_sha256"]
        if fp != exp:
            raise AssertionError(f"selector fingerprint mismatch {g}: {fp} != {exp}")
        Xreal = impute(Xf, med)
        mu, adapted_n = predict_with_representability_adapter(model,Xreal,pred,[r["parent_id"] for r in idx],g,adapter_rows)
        for i, r in enumerate(idx):
            pred_mu[r["parent_id"]][g] = float(mu[i])
        selector_identity["groups"][g] = {
            "forest_fingerprint_sha256": fp,
            "median_sha256": hashlib.sha256(le_f64_bytes(med)).hexdigest().upper(),
            "train_rows": len(rr), "distinct_train_parents": len(set(gp)), "representability_adapted_cells": adapted_n,
        }
        print(f"P11A2_SELECTOR_FIT={gi}/13|{g}|FOREST_SHA256={fp}", flush=True)
    out_adapter = out / "AUTOGREY_V2_P11A2_FINAL_SELECTOR_REPRESENTABILITY_ADAPTER_AUDIT_R3.csv"
    write_csv(out_adapter, adapter_rows, ["group","parent_id","predictor_id","raw_float64","adapted_prediction_boundary_value","tree_threshold_nodes_checked","branch_equivalent"])
    if not adapter_rows:
        raise AssertionError("R3 repair expected at least one float32-overrange selector input but found none")
    if not all(r["branch_equivalent"] == "TRUE" for r in adapter_rows):
        raise AssertionError("R3 adapter audit contains non-equivalent branch")
    selector_identity["representability_adapter"]={
        "policy":"prediction-boundary-only; raw feature matrix unchanged",
        "float32_max":format(FLOAT32_MAX,".17g"),
        "audit_rows":len(adapter_rows),
        "unique_parent_predictor_cells":len({(r["parent_id"],r["predictor_id"]) for r in adapter_rows}),
        "all_tree_threshold_branch_equivalent":True,
        "audit_sha256":sha256(out_adapter),
    }
    out_selector = out / "AUTOGREY_V2_P11A2_FINAL_SELECTOR_IDENTITY_R3.json"
    json_dump(out_selector, selector_identity)

    gr = read_csv(P["p7b-global"])
    gr.sort(key=lambda r: int(r["rank"]))
    grank = [r["group"] for r in gr]
    if len(grank) != 13 or set(grank) != set(GROUPS):
        raise AssertionError("GLOBAL rank invalid")

    action_rows, auto_rows, global_rows = [], [], []
    parent_status = {r["parent_id"]: r for r in parent_rows}
    for r in idx:
        pid = r["parent_id"]
        m = meta[pid]
        retained = [g for g in parent_status[pid]["retained_groups"].split(";") if g]
        for g in retained:
            fc = action_forecasts[(pid, g)]
            fh = canonical_forecast_hash(fc)
            for step, val in enumerate(fc, 1):
                action_rows.append({
                    "parent_id": pid, "source_id": m["source_id"], "h": m["h"], "group": g,
                    "step": step, "forecast": format(float(val), ".17g"), "forecast_sha256": fh,
                })
        if not retained:
            continue
        if len(retained) == 1:
            ag = retained[0]
            mode = "SINGLETON_NO_SELECTOR_CALL"
            predloss = ""
        else:
            avail = sorted((pred_mu[pid][g], GIDX[g], g) for g in retained)
            ag = avail[0][2]
            mode = "RF_D8_L001"
            predloss = format(avail[0][0], ".17g")
        gg = next(g for g in grank if g in set(retained))
        afc = action_forecasts[(pid, ag)]
        gfc = action_forecasts[(pid, gg)]
        auto_rows.append({
            "parent_id": pid, "source_id": m["source_id"], "h": m["h"], "action_count": len(retained),
            "selection_mode": mode, "selected_group": ag, "predicted_log1p_regret": predloss,
            "forecast_sha256": canonical_forecast_hash(afc),
        })
        global_rows.append({
            "parent_id": pid, "source_id": m["source_id"], "h": m["h"], "action_count": len(retained),
            "selection_mode": "SINGLETON" if len(retained) == 1 else "GLOBAL_RANK_V3_13G_FULL_TRAIN",
            "selected_group": gg, "forecast_sha256": canonical_forecast_hash(gfc),
        })

    out_grey = out / "AUTOGREY_V2_P11A2_FINAL_GREY_ACTION_FORECASTS_R3.csv"
    out_auto = out / "AUTOGREY_V2_P11A2_FINAL_AUTOGREY_DECISIONS_R3.csv"
    out_global = out / "AUTOGREY_V2_P11A2_FINAL_GLOBAL_DECISIONS_R3.csv"
    write_csv(out_grey, action_rows, ["parent_id","source_id","h","group","step","forecast","forecast_sha256"])
    write_csv(out_auto, auto_rows, ["parent_id","source_id","h","action_count","selection_mode","selected_group","predicted_log1p_regret","forecast_sha256"])
    write_csv(out_global, global_rows, ["parent_id","source_id","h","action_count","selection_mode","selected_group","forecast_sha256"])

    deploy = [r for r in idx if int(parent_status[r["parent_id"]]["retained_post_collision"]) >= 1]
    batches, cur, cur_vals = [], [], 0
    for r in deploy:
        n = int(r["binary_length_values"])
        if cur and (len(cur) >= 250 or cur_vals + n > 2_000_000):
            batches.append(cur)
            cur, cur_vals = [], 0
        cur.append(r)
        cur_vals += n
    if cur:
        batches.append(cur)

    methods = "NG01_NAIVE,NG02_SNAIVE,NG07_THETA,NG08_ETS_AUTO,NG09_ARIMA_AUTO"
    rawrows, batch_audit = [], []
    tmp = out / "_P3_TEMP"
    tmp.mkdir(exist_ok=True)
    for bi, batch in enumerate(batches, 1):
        series, vcount = [], 0
        for r in batch:
            pid = r["parent_id"]
            m = meta[pid]
            vcount += m["n_D"]
            series.append({
                "parent_id": pid, "source_id": m["source_id"], "h": m["h"],
                "M": 1 if m["M"] is None else m["M"], "n_D": m["n_D"],
                "development": [float(v) for v in Dmap[pid]],
            })
        payload = {"protocol": "AUTOGREY_V2_P3_DEVELOPMENT_ONLY_R1", "series": series}
        inp = tmp / f"P3_INPUT_{bi:03d}.json"
        rawp = out / "P3_RAW_BATCHES" / f"P3_RAW_{bi:03d}.json"
        json_dump(inp, payload)
        input_sha = sha256(inp)
        reused_p3 = False
        if rawp.exists():
            try:
                raw_existing=json.loads(rawp.read_text(encoding="utf-8"))
                ids_expected=[str(x["parent_id"]) for x in batch]
                ids_got=[str(x.get("parent_id")) for x in raw_existing.get("rows",[])]
                if raw_existing.get("protocol")=="AUTOGREY_V2_P3_HARNESS_OUTPUT_R5D" and raw_existing.get("target_blind_schema") is True and ids_got==ids_expected:
                    raw=raw_existing; reused_p3=True
                    print(f"===== P3 BATCH {bi}/{len(batches)} REUSED VERIFIED RAW =====",flush=True)
            except Exception:
                reused_p3=False
        if not reused_p3:
            cp = subprocess.run([rscript, "--vanilla", str(P["p3-harness"]), str(inp), str(rawp), methods], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=r_env)
            print(f"===== P3 BATCH {bi}/{len(batches)} =====", flush=True)
            print(cp.stdout, end="" if cp.stdout.endswith("\n") else "\n", flush=True)
            if cp.returncode != 0:
                raise RuntimeError(f"P3 batch {bi} failed rc={cp.returncode}")
            raw = json.loads(rawp.read_text(encoding="utf-8"))
        else:
            class CP: returncode=0
            cp=CP()
        if raw.get("protocol") != "AUTOGREY_V2_P3_HARNESS_OUTPUT_R5D":
            raise AssertionError(f"wrong P3 output protocol in batch {bi}")
        if raw.get("target_blind_schema") is not True:
            raise AssertionError(f"P3 batch {bi} output is not target blind")
        env3 = raw.get("direct_environment", {})
        if str(env3.get("R")) != "4.6.1":
            raise AssertionError(f"P3 batch {bi} R runtime mismatch: {env3}")
        rows = raw.get("rows", [])
        if len(rows) != len(batch):
            raise AssertionError(f"P3 batch schema/count mismatch {bi}")
        rawrows.extend(rows)
        batch_audit.append({
            "batch": bi, "parent_n": len(batch), "development_value_n": vcount,
            "input_payload_sha256": input_sha, "raw_output_sha256": sha256(rawp), "p3_exit_code": cp.returncode,
        })
        inp.unlink()
    shutil.rmtree(tmp, ignore_errors=True)
    out_batch = out / "AUTOGREY_V2_P11A2_FINAL_P3_BATCH_AUDIT_R3.csv"
    write_csv(out_batch, batch_audit, ["batch","parent_n","development_value_n","input_payload_sha256","raw_output_sha256","p3_exit_code"])
    if len(rawrows) != len(deploy):
        raise AssertionError("combined P3 parent count mismatch")

    ng10_rows, ngstatus, tech_ref = [], {}, []
    seen = set()
    for row in rawrows:
        pid = str(row["parent_id"])
        if pid in seen:
            raise AssertionError(f"duplicate P3 parent {pid}")
        seen.add(pid)
        ng = row.get("NG10_STATCOMB3")
        if not isinstance(ng, dict):
            raise AssertionError(f"missing NG10 object {pid}")
        status = str(ng.get("status"))
        ngstatus[pid] = status
        used = ng.get("used", [])
        if isinstance(used, str):
            used = [used]
        used = ";".join(str(x) for x in used)
        cs = int(ng.get("components_successful", 0))
        fc = np.asarray(ng.get("forecast", []), dtype=np.float64).reshape(-1)
        compstat = ";".join(
            f"{mid}:{row.get('methods', {}).get(mid, {}).get('status', 'MISSING')}"
            for mid in ["NG01_NAIVE","NG02_SNAIVE","NG07_THETA","NG08_ETS_AUTO","NG09_ARIMA_AUTO"]
        )
        if status == "NO_FORECAST":
            tech_ref.append({"parent_id": pid, "scope":"REALBENCH3_CLEAN", "method":"NG10_STATCOMB3", "reason":"NO_FORECAST", "details":compstat})
            continue
        if len(fc) != meta[pid]["h"] or not np.all(np.isfinite(fc)):
            raise AssertionError(f"invalid NG10 forecast {pid}")
        fh = canonical_forecast_hash(fc)
        rfh = ng.get("forecast_sha256")
        if rfh is not None and str(rfh).upper() != fh:
            raise AssertionError(f"NG10 forecast hash mismatch {pid}")
        for step, val in enumerate(fc, 1):
            ng10_rows.append({
                "parent_id":pid,"source_id":meta[pid]["source_id"],"h":meta[pid]["h"],"status":status,
                "components_successful":cs,"used":used,"component_statuses":compstat,"step":step,
                "forecast":format(float(val),".17g"),"forecast_sha256":fh,
            })
    out_ng10 = out / "AUTOGREY_V2_P11A2_FINAL_NG10_FORECASTS_R3.csv"
    write_csv(out_ng10, ng10_rows, ["parent_id","source_id","h","status","components_successful","used","component_statuses","step","forecast","forecast_sha256"])

    auto_by = {r["parent_id"]: r for r in auto_rows}
    global_by = {r["parent_id"]: r for r in global_rows}
    action_final = []
    for r in parent_rows:
        pid = r["parent_id"]
        nret = int(r["retained_post_collision"])
        sel_ok = nret >= 2 and pid in auto_by and pid in global_by
        prac_ok = nret >= 1 and pid in auto_by and ngstatus.get(pid, "NO_FORECAST") != "NO_FORECAST"
        z = dict(r)
        z.update({
            "selector_pair_eligible": booltxt(sel_ok), "practical_pair_eligible": booltxt(prac_ok),
            "ng10_status": ngstatus.get(pid, "NOT_RUN_NO_GREY"),
        })
        action_final.append(z)
    write_csv(out_action, action_final, list(action_final[0]))

    clean_source = Counter(meta[p]["source_id"] for p in meta)
    clean_h = Counter(meta[p]["h"] for p in meta)
    clean_cross = Counter((meta[p]["source_id"], meta[p]["h"]) for p in meta)
    selids = {r["parent_id"] for r in action_final if r["selector_pair_eligible"] == "TRUE"}
    pracids = {r["parent_id"] for r in action_final if r["practical_pair_eligible"] == "TRUE"}

    def pop_counts(ids):
        return (
            Counter(meta[p]["source_id"] for p in ids),
            Counter(meta[p]["h"] for p in ids),
            Counter((meta[p]["source_id"], meta[p]["h"]) for p in ids),
        )

    ss, sh, sc = pop_counts(selids)
    ps, ph, pc = pop_counts(pracids)
    sub_rows = []
    for r in idx:
        pid = r["parent_id"]
        s = meta[pid]["source_id"]
        h = meta[pid]["h"]
        sub_rows.append({
            "parent_id":pid,"source_id":s,"h":h,
            "clean_h_n":clean_h[h],"clean_source_n":clean_source[s],"clean_source_x_h_n":clean_cross[(s,h)],
            "selection_pair_eligible":booltxt(pid in selids),"selection_h_n":sh[h],"selection_source_n":ss[s],"selection_source_x_h_n":sc[(s,h)],
            "selection_h_inferential_eligible":booltxt(sh[h]>=30),"selection_source_inferential_eligible":booltxt(ss[s]>=30),"selection_source_x_h_inferential_eligible":booltxt(sc[(s,h)]>=30),
            "practical_pair_eligible":booltxt(pid in pracids),"practical_h_n":ph[h],"practical_source_n":ps[s],"practical_source_x_h_n":pc[(s,h)],
            "practical_h_inferential_eligible":booltxt(ph[h]>=30),"practical_source_inferential_eligible":booltxt(ps[s]>=30),"practical_source_x_h_inferential_eligible":booltxt(pc[(s,h)]>=30),
        })
    out_sub = out / "AUTOGREY_V2_P11A2_FINAL_SUBGROUP_LEDGER_R3.csv"
    write_csv(out_sub, sub_rows, list(sub_rows[0]))

    p1ref = read_p1_refusals(P["p1-seal"])
    refusal_rows = []
    for rr in p1ref:
        refusal_rows.append({
            "parent_id":rr.get("parent_id",""),"scope":"P1_INITIAL_RESERVATION","method":"P1_RESERVATION",
            "reason":rr.get("reason_code", rr.get("reason", "P1_REFUSAL")),
            "details":json.dumps(rr, sort_keys=True, separators=(",",":")),
        })
    for r in action_final:
        if int(r["retained_post_collision"]) == 0:
            refusal_rows.append({
                "parent_id":r["parent_id"],"scope":"REALBENCH3_CLEAN","method":"GREY_ACTION_SET",
                "reason":"ABSTAIN_NO_GREY","details":"no retained grey action after frozen collision resolution",
            })
    refusal_rows.extend(tech_ref)
    out_ref = out / "AUTOGREY_V2_P11A2_FINAL_REFUSAL_LEDGER_R3.csv"
    write_csv(out_ref, refusal_rows, ["parent_id","scope","method","reason","details"])

    status_counts = Counter(r["resolution_status"] for r in action_final)
    ngcounts = Counter(ngstatus.values())
    assertions = {
        "schema":"AUTOGREY_V2_P11A2_FINAL_ASSERTIONS_R3",
        "input_identity_gate":True,"python_runtime_gate":True,"r_runtime_gate":True,
        "clean_parent_n":4781,"d_hash_match_n":4781,"target_numeric_parse":False,"target_scoring":False,
        "realbench3_targets_opened":False,"r1_classification":"INCONCLUSIVE_RUNTIME_PRACTICALITY_TERMINATION",
        "r1_preserved_evidence_sha256":EXPECTED["r1_evidence"],"r2_execution_only_repair":True,"r3_selector_representability_repair":True,
        "r2_newgroup_chunk_size":R2_CHUNK_SIZE,"r2_parallel_r_workers":R2_MAX_PARALLEL_R_WORKERS,
        "newgroup_audit_rows":len(new_audit),
        "actionability_status_counts":dict(status_counts),"selection_pair_n":len(selids),"practical_pair_n":len(pracids),
        "grey_action_forecast_rows":len(action_rows),"autogrey_decision_n":len(auto_rows),"global_decision_n":len(global_rows),
        "ng10_status_counts":dict(ngcounts),"ng10_forecast_parent_n":len({r['parent_id'] for r in ng10_rows}),
        "p1_refusal_n":len(p1ref),"combined_refusal_rows":len(refusal_rows),
        "selector_fingerprints_match_p7b":True,"collision_primary_threshold":1e-3,
        "r3_imported_r2_checkpoint_chunks":imported_r2_chunks,
        "r3_preselector_r2_exact_reproduction":True,
        "r3_preselector_reproduction_sha256":r2_preselector_repro,
        "r3_raw_feature_matrix_changed":False,
        "r3_representability_adapter_audit_rows":len(adapter_rows),
        "r3_representability_unique_cells":len({(r["parent_id"],r["predictor_id"]) for r in adapter_rows}),
        "r3_all_adapter_tree_branches_equivalent":all(r["branch_equivalent"]=="TRUE" for r in adapter_rows),
        "no_confidence_abstention":True,"p11_b_locked":True,
        "collision_counts":{
            "comparisons":dict(comparison_count),"at_1e4":dict(collision4),"at_1e3":dict(collision3),"at_1e2":dict(collision2)
        },
        "available_occurrences":dict(available_occ),"retained_occurrences":dict(retained_occ),"removed_occurrences":dict(removed_occ),
    }
    out_assert = out / "AUTOGREY_V2_P11A2_FINAL_ASSERTIONS_R3.json"
    json_dump(out_assert, assertions)

    out_evidence = out / "AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_R3.txt"
    lines += [
        "", "===== FINAL TARGET-FREE PRODUCTION SUMMARY =====",
        "CLEAN_PARENT_N=4781",
        f"P1_PRESERVED_REFUSAL_N={len(p1ref)}",
        f"ACTIONABILITY_STATUS_COUNTS={';'.join(f'{k}:{v}' for k,v in sorted(status_counts.items()))}",
        f"SELECTION_PAIR_N={len(selids)}",
        f"PRACTICAL_PAIR_N={len(pracids)}",
        f"GREY_ACTION_FORECAST_ROWS={len(action_rows)}",
        f"AUTOGREY_DECISION_N={len(auto_rows)}",
        f"GLOBAL_DECISION_N={len(global_rows)}",
        f"NG10_STATUS_COUNTS={';'.join(f'{k}:{v}' for k,v in sorted(ngcounts.items()))}",
        f"NG10_FORECAST_PARENT_N={len({r['parent_id'] for r in ng10_rows})}",
        f"NEWGROUP_AUDIT_ROWS={len(new_audit)}",
        f"R3_IMPORTED_R2_NEWGROUP_CHUNK_N={imported_r2_chunks}",
        f"R3_NEWGROUP_CHUNK_SIZE={R2_CHUNK_SIZE}",
        "R1_CLASSIFICATION=INCONCLUSIVE_RUNTIME_PRACTICALITY_TERMINATION",
        f"R1_PRESERVED_EVIDENCE_SHA256={EXPECTED['r1_evidence']}",
        "R2_CLASSIFICATION=INCONCLUSIVE_FLOAT32_SELECTOR_INPUT_REPRESENTABILITY_ERROR",
        f"R2_PRESERVED_EVIDENCE_SHA256={EXPECTED['r2_evidence']}",
        "R3_PRESELECTOR_R2_EXACT_REPRODUCTION=PASS",
        "R3_RAW_FEATURE_MATRIX_CHANGED=FALSE",
        f"R3_REPRESENTABILITY_ADAPTER_AUDIT_ROWS={len(adapter_rows)}",
        f"R3_REPRESENTABILITY_UNIQUE_CELLS={len({(r['parent_id'],r['predictor_id']) for r in adapter_rows})}",
        "R3_ALL_ADAPTER_TREE_BRANCHES_EQUIVALENT=TRUE",
        f"COLLISION_EDGE_ROWS={len(edge_rows)}",
        "REALBENCH3_NUMERIC_TARGET_PARSE=FALSE",
        "REALBENCH3_TARGET_SCORING=FALSE",
        "REALBENCH3_TARGET_VALUES_OPENED=FALSE",
        "P11A2_FINAL_CLASSIFICATION=PASS",
        "P11A2_FINAL_REVISION=R3",
        "SCIENTIFIC_LOCK_CHANGED=FALSE",
        "NEXT_STEP=SEPARATE_HASH_INGEST_VERIFICATION_BEFORE_P11B",
        "P11_B=LOCKED",
    ]
    out_evidence.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    out_manifest = out / "AUTOGREY_V2_P11A2_FINAL_MANIFEST_R3.sha256"
    generated = [p for p in out.rglob("*") if p.is_file() and p != out_manifest]
    out_manifest.write_text(
        "\n".join(f"{sha256(p)}  {p.relative_to(out).as_posix()}" for p in sorted(generated)) + "\n",
        encoding="utf-8", newline="\n"
    )

    print("\n".join(lines[-25:]))
    print(f"OUTPUT_DIR={out}")
    print(f"EVIDENCE_SHA256={sha256(out_evidence)}")
    print(f"MANIFEST_SHA256={sha256(out_manifest)}")
    print("REALBENCH3_TARGET_VALUES_OPENED=FALSE")
    print("P11_B=LOCKED")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(f"P11A2_FINAL_HARNESS_ERROR={type(e).__name__}: {e}", file=sys.stderr)
        print("REALBENCH3_TARGET_VALUES_OPENED=FALSE", file=sys.stderr)
        print("P11_B=LOCKED", file=sys.stderr)
        raise SystemExit(3)
