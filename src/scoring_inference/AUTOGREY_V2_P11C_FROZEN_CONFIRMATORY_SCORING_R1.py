#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import platform
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np

EXPECTED_PYTHON_VERSION = "3.13.5"
EXPECTED_NUMPY_VERSION = "2.3.5"

NAMES = {
    "p10a":"AUTOGREY_V2_P10A_EXTERNAL_CONFIRMATION_PREREGISTRATION_LOCK_R1.json",
    "p10contract":"AUTOGREY_V2_P10B_EXECUTABLE_PRETARGET_CONTRACT_R1.json",
    "dev_index":"AUTOGREY_V2_P11A1_REALBENCH3_DEVELOPMENT_INDEX_R1.csv",
    "dev_binary":"AUTOGREY_V2_P11A1_REALBENCH3_DEVELOPMENT_FLOAT64_LE_R1.bin",
    "p11a2_evidence":"AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_R3.txt",
    "p11a2_manifest":"AUTOGREY_V2_P11A2_FINAL_MANIFEST_R3.sha256",
    "autogrey":"AUTOGREY_V2_P11A2_FINAL_AUTOGREY_DECISIONS_R3.csv",
    "global":"AUTOGREY_V2_P11A2_FINAL_GLOBAL_DECISIONS_R3.csv",
    "ng10":"AUTOGREY_V2_P11A2_FINAL_NG10_FORECASTS_R3.csv",
    "subgroup":"AUTOGREY_V2_P11A2_FINAL_SUBGROUP_LEDGER_R3.csv",
    "grey":"AUTOGREY_V2_P11A2_FINAL_GREY_ACTION_FORECASTS_R3.csv",
    "actionability":"AUTOGREY_V2_P11A2_FINAL_ACTIONABILITY_LEDGER_R3.csv",
    "target_index":"AUTOGREY_V2_P11B_REALBENCH3_TARGET_INDEX_R1.csv",
    "target_binary":"AUTOGREY_V2_P11B_REALBENCH3_TARGET_FLOAT64_LE_R1.bin",
    "target_audit":"AUTOGREY_V2_P11B_TARGET_OPENING_AUDIT_R1.json",
    "p11b_evidence":"AUTOGREY_V2_P11B_IRREVERSIBLE_TARGET_OPENING_R1.txt",
    "p11b_manifest":"AUTOGREY_V2_P11B_MANIFEST_R1.sha256",
    "r4_evidence":"AUTOGREY_V2_P11C0_R4_PASS_CLOSED_EVIDENCE.zip",
}

HEADERS = {
    "autogrey":["parent_id","source_id","h","action_count","selection_mode","selected_group","predicted_log1p_regret","forecast_sha256"],
    "global":["parent_id","source_id","h","action_count","selection_mode","selected_group","forecast_sha256"],
    "ng10":["parent_id","source_id","h","status","components_successful","used","component_statuses","step","forecast","forecast_sha256"],
    "subgroup":["parent_id","source_id","h","clean_h_n","clean_source_n","clean_source_x_h_n","selection_pair_eligible","selection_h_n","selection_source_n","selection_source_x_h_n","selection_h_inferential_eligible","selection_source_inferential_eligible","selection_source_x_h_inferential_eligible","practical_pair_eligible","practical_h_n","practical_source_n","practical_source_x_h_n","practical_h_inferential_eligible","practical_source_inferential_eligible","practical_source_x_h_inferential_eligible"],
    "grey":["parent_id","source_id","h","group","step","forecast","forecast_sha256"],
    "actionability":["parent_id","source_id","h","M","n_D","available_pre_collision","retained_post_collision","resolution_status","retained_groups","removed_groups","selector_pair_eligible","practical_pair_eligible","ng10_status"],
}

DEFAULT_EXPECTED_HASHES = {
    "p10a":"BD3BFBC446D48BFEE5A4462474CB538E3913C60A11B8DA0710103E06F23B02C4",
    "p10contract":"FD7D6FCE076F255901CE14FF138D51F6BB43CE8AA9AE381BF9048A7DB4D7269C",
    "dev_index":"8EEA756829B7A97F033EA81E5C2783528B68374A7B7549CE2D3EEA4D02D1C58B",
    "dev_binary":"98648163F9ABE781EAA03EE49FD53D9BE1A33666F0A42BF7016B332F11E536F9",
    "p11a2_evidence":"B6EE5EC236FFAF3A887ECE0206E087FF03902BC28D47C2AE67410CA5BDE6E5E1",
    "p11a2_manifest":"11A913309E28582F09D04122F930C81DC0A19CC88CF44E34661A2179768269E5",
    "autogrey":"C78A62150EFB5FD350B917AE92E6359D5487FB18F8BB4278FBC69BE70FE433A4",
    "global":"0EB66316BF9D686FDF53C84E916DDE754F669BA24648A20ED81BC9A237119FB6",
    "ng10":"80F5F47D0B59DC5B6D5086670A9DFAEFDC79BA51EBC57C3057A66F811E1308C7",
    "subgroup":"1E0E3D404FF27051B66BDDEBA69C20A0F6E54A3286DDDA901A11FB76C4902D18",
    "grey":"A46575522FE3E0E2AFFD761D99FAB7B89C40A515CC139EBB30587AE7F2BDC66A",
    "actionability":"77335A71AC5A13C58817628DCB861350861F32901E949A4395CEFD85C2405C0B",
    "target_index":"6708C88AB06C12202F8C4EA5184D953FE91E877221AE5F093738F55AD39AFD28",
    "target_binary":"7AA803C5E5ED92DD880F9FFB3A060D4D4A149997C25829BF57FABD0DCA165BEE",
    "target_audit":"46C062798B2E52B8D7143DB83540EDDFBA4F708AB5B7B9A5958A11371408360A",
    "p11b_evidence":"4812EFB9CC2DA21B1F46B44BD58B1561831B0AE70149F6ABFE1CA49192147554",
    "p11b_manifest":"FB3F2F3EE3715BC40290D279C8F577615F4783ABAB65F064450B46C82A4DA3CF",
    "r4_evidence":"FF3DE433CF3B09B28A731DCF93DF473C26DF2929567A6A03D37E96E73A916EB9",
}


@dataclass
class EntryPaths:
    p10: Path
    p11a1: Path
    p11a2: Path
    p11b: Path
    r4_evidence: Path


@dataclass
class EntryGateConfig:
    expected_hashes: dict[str,str]
    manifest_entry_n: int = 3653
    full_census_n: int = 4781
    deployed_n: int = 4778
    nondeployed_n: int = 3


@dataclass
class PreflightState:
    full_parent_ids: frozenset[str]
    deployed_parent_ids: frozenset[str]
    nondeployed_parent_ids: tuple[str, ...]
    files: dict[str, Path]
    rows: dict[str, list[dict[str,str]]]
    grey_vector_hashes: dict[tuple[str,str], str]
    ng10_vector_hashes: dict[str, str]
    target_binary_numeric_reads: int = 0
    development_index: dict[str,dict[str,str]] | None = None
    target_index: dict[str,dict[str,str]] | None = None
    autogrey_by_parent: dict[str,dict[str,str]] | None = None
    global_by_parent: dict[str,dict[str,str]] | None = None
    subgroup_by_parent: dict[str,dict[str,str]] | None = None
    actionability_by_parent: dict[str,dict[str,str]] | None = None
    grey_rows_by_parent_group: dict[tuple[str,str], list[dict[str,str]]] | None = None
    ng10_rows_by_parent: dict[str, list[dict[str,str]]] | None = None


@dataclass(frozen=True)
class ParentScore:
    parent_id: str
    source_id: str
    h: int
    M: int
    mase_scale: float
    eligible_action_count: int
    autogrey_selected_group: str
    global_selected_group: str
    eligible_oracle_mase: float
    autogrey_mase: float
    global_mase: float
    ng10_mase: float
    autogrey_regret: float
    global_regret: float
    delta_selection_regret: float
    delta_practical_mase: float
    subgroup_h: str
    subgroup_source: str
    subgroup_source_x_h: str
    autogrey_forecast_sha256: str
    global_forecast_sha256: str
    ng10_forecast_sha256: str
    eligible_action_forecast_hashes_json: str


@dataclass(frozen=True)
class OverallPointEstimates:
    A: float
    B: float
    C1: float
    C2: float


@dataclass(frozen=True)
class OverallBootstrapBounds:
    upper95: OverallPointEstimates
    context_lower95: OverallPointEstimates
    context_upper95: OverallPointEstimates
    upper_quantile: float = 0.95
    quantile_method: str = "linear"
    context_interval_only: bool = True


@dataclass(frozen=True)
class GateDecision:
    points: OverallPointEstimates
    bounds: OverallBootstrapBounds
    gate_a_numerical: str
    gate_b_numerical: str
    gate_c1_numerical: str
    gate_c2_numerical: str
    gate_c_numerical: str
    gate_a_confirmatory: str
    gate_b_confirmatory: str
    gate_c_confirmatory: str
    overall_status: str
    gate_a_claim_may_stand: bool
    full_confirmation_claim_allowed: bool
    allowed_claim_text: str
    equivalence_to_ng10_claim_allowed: bool = False
    universal_superiority_claim_allowed: bool = False
    ng10_superiority_from_noninferiority_allowed: bool = False
    every_non_grey_superiority_claim_allowed: bool = False
    unqualified_generalization_claim_allowed: bool = False
    configuration_change_allowed: bool = False
    scientific_lock_changed: bool = False
    negative_or_partial_result_preserved: bool = True


OVERALL_BOOTSTRAP_SEED = 1068199533
OVERALL_BOOTSTRAP_B = 4000
OVERALL_ESTIMAND_NAMES = ("A", "B", "C1", "C2")

P11C0_HISTORY = {
    "R1": "INCONCLUSIVE_HARNESS_ROLE_CLASSIFICATION_BUG",
    "R2": "INCONCLUSIVE_HARNESS_POPULATION_ASSUMPTION_BUG",
    "R3": "INCONCLUSIVE_HARNESS_SCHEMA_NAME_MISMATCH",
    "R4": "PASS_CLOSED",
}
TARGET_BINARY_SLICE_FIELDS = ("binary_offset_bytes", "binary_length_values", "binary_length_bytes")
PRE_MANIFEST_RESULT_FILES = (
    "AUTOGREY_V2_P11C_PARENT_SCORES_R1.csv",
    "AUTOGREY_V2_P11C_OVERALL_BOOTSTRAP_R1.csv",
    "AUTOGREY_V2_P11C_OVERALL_RESULTS_R1.json",
    "AUTOGREY_V2_P11C_SUBGROUP_RESULTS_R1.csv",
    "AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1.json",
    "AUTOGREY_V2_P11C_CONFIRMATORY_DECISION_R1.txt",
    "AUTOGREY_V2_P11C_ASSERTIONS_R1.json",
)
RESULT_MANIFEST_NAME = "AUTOGREY_V2_P11C_MANIFEST_R1.sha256"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest().upper()


def exact_file(base: Path, name: str, expected_hash: str) -> Path:
    p = Path(base) / name
    if not p.is_file():
        raise FileNotFoundError(f"missing exact file: {p}")
    got = sha256(p)
    exp = expected_hash.upper()
    if got != exp:
        raise AssertionError(f"SHA-256 mismatch for {name}: got={got} expected={exp}")
    return p


def refuse_existing_output(path: Path) -> None:
    p = Path(path)
    if p.exists():
        raise FileExistsError(f"output already exists; nothing overwritten: {p}")


def allowed_modes() -> tuple[str, str]:
    return ("preflight", "score")


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="AutoGrey V2 P11-C frozen confirmatory scoring harness")
    ap.add_argument("--mode", required=True, choices=allowed_modes())
    ap.add_argument("--out", required=True)
    ap.add_argument("--p10")
    ap.add_argument("--p11a1")
    ap.add_argument("--p11a2")
    ap.add_argument("--p11b")
    ap.add_argument("--r4-evidence")
    return ap.parse_args(argv)


def assert_runtime(*, python_version: str | None = None, numpy_version: str | None = None) -> None:
    if python_version is None:
        python_version = platform.python_version()
    if numpy_version is None:
        import numpy as np
        numpy_version = np.__version__
    if python_version != EXPECTED_PYTHON_VERSION:
        raise AssertionError(f"Python version mismatch: got={python_version} expected={EXPECTED_PYTHON_VERSION}")
    if numpy_version != EXPECTED_NUMPY_VERSION:
        raise AssertionError(f"NumPy version mismatch: got={numpy_version} expected={EXPECTED_NUMPY_VERSION}")


def _read_csv(path: Path) -> tuple[list[str], list[dict[str,str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader=csv.DictReader(f)
        header=list(reader.fieldnames or [])
        return header, list(reader)


def _parse_manifest(path: Path) -> list[tuple[str,str]]:
    entries=[]
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        s=line.strip()
        if not s or s.startswith("#"):
            continue
        m=re.match(r"^([0-9A-Fa-f]{64})\s+[* ]?(.+?)\s*$",s)
        if not m:
            raise AssertionError(f"unparseable manifest line: {line!r}")
        entries.append((m.group(1).upper(),m.group(2).strip().replace("\\","/")))
    return entries


def _resolve_manifest_member(root: Path, rel: str, expected_hash: str) -> Path:
    direct=root/rel
    if direct.is_file():
        if sha256(direct)!=expected_hash:
            raise AssertionError(f"manifest member hash mismatch: {rel}")
        return direct
    name=Path(rel).name
    hits=[]
    for p in root.rglob(name):
        if p.is_file() and sha256(p)==expected_hash:
            hits.append(p)
    if len(hits)!=1:
        raise AssertionError(f"manifest member unresolved: {rel}; exact-hash-hits={len(hits)}")
    return hits[0]


def _by_parent(rows: list[dict[str,str]], role: str) -> dict[str,dict[str,str]]:
    out={}
    for r in rows:
        pid=str(r.get("parent_id","")).strip()
        if not pid:
            raise AssertionError(f"{role}: blank parent_id")
        if pid in out:
            raise AssertionError(f"{role}: duplicate parent_id={pid}")
        out[pid]=r
    return out


def _bool(v: str, label: str) -> bool:
    s=str(v).strip().upper()
    if s=="TRUE": return True
    if s=="FALSE": return False
    raise AssertionError(f"{label}: invalid boolean {v!r}")


def _int(v: str, label: str) -> int:
    try:
        return int(str(v).strip())
    except Exception as e:
        raise AssertionError(f"{label}: invalid integer {v!r}") from e


def read_indexed_float64_vector(row: dict[str,str], binary_path: Path) -> np.ndarray:
    """Read one little-endian float64 vector using declared byte offset/count fields only."""
    required=("binary_offset_bytes","binary_length_values","binary_length_bytes")
    missing=[k for k in required if k not in row]
    if missing:
        raise AssertionError(f"binary index schema missing fields: {missing}")
    offset=_int(row["binary_offset_bytes"],"binary_offset_bytes")
    n_values=_int(row["binary_length_values"],"binary_length_values")
    n_bytes=_int(row["binary_length_bytes"],"binary_length_bytes")
    if offset < 0 or offset % 8 != 0:
        raise AssertionError(f"binary offset invalid or not float64 aligned: {offset}")
    if n_values <= 0:
        raise AssertionError(f"binary length values must be positive: {n_values}")
    if n_bytes != n_values * 8 or n_bytes % 8 != 0:
        raise AssertionError(f"binary length mismatch: values={n_values} bytes={n_bytes}")
    path=Path(binary_path)
    size=path.stat().st_size
    if offset + n_bytes > size:
        raise AssertionError(f"binary slice exceeds file length: offset={offset} bytes={n_bytes} file={size}")
    with path.open("rb") as f:
        f.seek(offset)
        raw=f.read(n_bytes)
    if len(raw)!=n_bytes:
        raise AssertionError(f"binary short read: got={len(raw)} expected={n_bytes}")
    out=np.frombuffer(raw,dtype="<f8",count=n_values).astype(np.float64,copy=True)
    if out.size != n_values:
        raise AssertionError(f"binary decoded length mismatch: got={out.size} expected={n_values}")
    if not np.all(np.isfinite(out)):
        raise AssertionError("binary vector contains non-finite float64 value")
    return out


def read_development_vector(parent_id: str, development_index: dict[str,dict[str,str]], development_binary: Path) -> np.ndarray:
    pid=str(parent_id)
    if pid not in development_index:
        raise AssertionError(f"development index missing parent_id={pid}")
    row=development_index[pid]
    out=read_indexed_float64_vector(row,development_binary)
    if "n_D_token_count" in row and str(row["n_D_token_count"]).strip()!="":
        expected=_int(row["n_D_token_count"],"n_D_token_count")
        if out.size != expected:
            raise AssertionError(f"development length mismatch parent={pid}: got={out.size} n_D={expected}")
    return out


def read_target_vector(parent_id: str, target_index: dict[str,dict[str,str]], target_binary: Path) -> np.ndarray:
    pid=str(parent_id)
    if pid not in target_index:
        raise AssertionError(f"target index missing parent_id={pid}")
    row=target_index[pid]
    out=read_indexed_float64_vector(row,target_binary)
    h=_int(row.get("h",""),"target.h")
    if out.size != h:
        raise AssertionError(f"target horizon length mismatch parent={pid}: got={out.size} h={h}")
    return out


def _effective_mase_lag(M) -> int:
    if M is None or str(M).strip()=="":
        return 1
    try:
        x=float(M)
    except Exception as e:
        raise AssertionError(f"invalid M for MASE lag: {M!r}") from e
    if not math.isfinite(x) or x <= 1:
        return 1
    if not x.is_integer():
        raise AssertionError(f"seasonal M must be integer-valued when >1: {M!r}")
    return int(x)


def mase_scale(D, M) -> float:
    arr=np.asarray(D,dtype=np.float64)
    if arr.ndim != 1 or arr.size == 0:
        raise AssertionError("development vector must be non-empty 1D")
    if not np.all(np.isfinite(arr)):
        raise AssertionError("development vector contains non-finite value")
    lag=_effective_mase_lag(M)
    if arr.size <= lag:
        raise AssertionError(f"MASE_SCALE_HISTORY_SHORT: n={arr.size} lag={lag}")
    scale=float(np.mean(np.abs(arr[lag:] - arr[:-lag]),dtype=np.float64))
    if not math.isfinite(scale) or scale <= 0.0:
        raise AssertionError(f"DEGENERATE_MASE_SCALE: scale={scale}")
    return scale


def mase(D, y, f, M) -> float:
    yy=np.asarray(y,dtype=np.float64)
    ff=np.asarray(f,dtype=np.float64)
    if yy.ndim != 1 or ff.ndim != 1 or yy.size == 0 or ff.size == 0:
        raise AssertionError("target/forecast must be non-empty 1D vectors")
    if yy.size != ff.size:
        raise AssertionError(f"target/forecast length mismatch: target={yy.size} forecast={ff.size}")
    if not np.all(np.isfinite(yy)) or not np.all(np.isfinite(ff)):
        raise AssertionError("target/forecast contains non-finite value")
    scale=mase_scale(D,M)
    value=float(np.mean(np.abs(ff-yy),dtype=np.float64)/scale)
    if not math.isfinite(value):
        raise AssertionError("MASE result non-finite")
    return value


def _recursive_key_values(obj, key: str):
    vals=[]
    if isinstance(obj,dict):
        for k,v in obj.items():
            if k==key: vals.append(v)
            vals.extend(_recursive_key_values(v,key))
    elif isinstance(obj,list):
        for v in obj: vals.extend(_recursive_key_values(v,key))
    return vals


def _assert_p11b_open_pass(audit_path: Path, evidence_path: Path) -> None:
    audit=json.loads(audit_path.read_text(encoding="utf-8-sig"))
    result_vals=_recursive_key_values(audit,"P11B_RESULT") + _recursive_key_values(audit,"p11b_result")
    open_vals=_recursive_key_values(audit,"REALBENCH3_TARGET_VALUES_OPENED") + _recursive_key_values(audit,"realbench3_target_values_opened")
    evidence=evidence_path.read_text(encoding="utf-8-sig")
    result_ok=any(str(v).upper()=="PASS" for v in result_vals) or "P11B_RESULT=PASS" in evidence
    open_ok=any(v is True or str(v).upper()=="TRUE" for v in open_vals) or "REALBENCH3_TARGET_VALUES_OPENED=TRUE" in evidence
    if not result_ok or not open_ok:
        raise AssertionError(f"P11-B opened-state audit failed: result_ok={result_ok} open_ok={open_ok}")


def _validate_vector_rows(rows: list[dict[str,str]], target: dict[str,dict[str,str]], role: str, group_field: str | None):
    grouped=defaultdict(list)
    for r in rows:
        pid=str(r["parent_id"]).strip()
        if pid not in target:
            raise AssertionError(f"{role}: parent absent from target index {pid}")
        if str(r["source_id"]).strip()!=str(target[pid]["source_id"]).strip():
            raise AssertionError(f"{role}: source mismatch {pid}")
        if _int(r["h"],f"{role}.h")!=_int(target[pid]["h"],"target.h"):
            raise AssertionError(f"{role}: h mismatch {pid}")
        key=(pid,str(r[group_field]).strip()) if group_field else (pid,)
        grouped[key].append(r)
    hashes={}
    for key,rr in grouped.items():
        pid=key[0]; h=_int(target[pid]["h"],"target.h")
        steps=sorted(_int(r["step"],f"{role}.step") for r in rr)
        if steps!=list(range(1,h+1)):
            raise AssertionError(f"{role}: step vector mismatch key={key} steps={steps} h={h}")
        hs={str(r["forecast_sha256"]).strip().upper() for r in rr}
        if "" in hs or len(hs)!=1:
            raise AssertionError(f"{role}: forecast hash inconsistency key={key}")
        hashes[key]=next(iter(hs))
    return grouped,hashes


def verify_entry_gate(paths: EntryPaths, *, config: EntryGateConfig | None = None) -> PreflightState:
    cfg=config or EntryGateConfig(dict(DEFAULT_EXPECTED_HASHES))
    exp=cfg.expected_hashes
    files={}
    files["p10a"]=exact_file(paths.p10,NAMES["p10a"],exp["p10a"])
    files["p10contract"]=exact_file(paths.p10,NAMES["p10contract"],exp["p10contract"])
    files["dev_index"]=exact_file(paths.p11a1,NAMES["dev_index"],exp["dev_index"])
    files["dev_binary"]=exact_file(paths.p11a1,NAMES["dev_binary"],exp["dev_binary"])
    files["p11a2_evidence"]=exact_file(paths.p11a2,NAMES["p11a2_evidence"],exp["p11a2_evidence"])
    files["p11a2_manifest"]=exact_file(paths.p11a2,NAMES["p11a2_manifest"],exp["p11a2_manifest"])
    files["target_index"]=exact_file(paths.p11b,NAMES["target_index"],exp["target_index"])
    files["target_binary"]=exact_file(paths.p11b,NAMES["target_binary"],exp["target_binary"])
    files["target_audit"]=exact_file(paths.p11b,NAMES["target_audit"],exp["target_audit"])
    files["p11b_evidence"]=exact_file(paths.p11b,NAMES["p11b_evidence"],exp["p11b_evidence"])
    files["p11b_manifest"]=exact_file(paths.p11b,NAMES["p11b_manifest"],exp["p11b_manifest"])
    if not Path(paths.r4_evidence).is_file():
        raise FileNotFoundError(f"missing R4 evidence: {paths.r4_evidence}")
    if sha256(paths.r4_evidence)!=exp["r4_evidence"].upper():
        raise AssertionError("SHA-256 mismatch for P11-C0 R4 evidence archive")
    files["r4_evidence"]=Path(paths.r4_evidence)
    _assert_p11b_open_pass(files["target_audit"],files["p11b_evidence"])

    manifest=_parse_manifest(files["p11a2_manifest"])
    if len(manifest)!=cfg.manifest_entry_n:
        raise AssertionError(f"P11-A2 manifest entry count={len(manifest)} expected={cfg.manifest_entry_n}")
    manifest_map={}
    for h,rel in manifest:
        p=_resolve_manifest_member(paths.p11a2,rel,h)
        manifest_map[Path(rel).name]=(h,p)

    rows={}
    for role in ("autogrey","global","ng10","subgroup","grey","actionability"):
        name=NAMES[role]
        if name not in manifest_map:
            raise AssertionError(f"canonical science file absent from P11-A2 manifest: {name}")
        mh,mp=manifest_map[name]
        if mh!=exp[role].upper():
            raise AssertionError(f"manifest hash mismatch for {name}")
        files[role]=exact_file(paths.p11a2,name,exp[role])
        header,r=_read_csv(files[role])
        if header!=HEADERS[role]:
            raise AssertionError(f"{role} schema mismatch: got={header} expected={HEADERS[role]}")
        rows[role]=r

    dev_header,dev_rows=_read_csv(files["dev_index"])
    for req in ("parent_id","source_id","h"):
        if req not in dev_header:
            raise AssertionError(f"development index missing required column {req}")
    development=_by_parent(dev_rows,"DEVELOPMENT_INDEX")

    target_header,target_rows=_read_csv(files["target_index"])
    for req in ("parent_id","source_id","h"):
        if req not in target_header:
            raise AssertionError(f"target index missing required column {req}")
    target=_by_parent(target_rows,"TARGET_INDEX")
    sub=_by_parent(rows["subgroup"],"SUBGROUP")
    act=_by_parent(rows["actionability"],"ACTIONABILITY")
    auto=_by_parent(rows["autogrey"],"AUTOGREY")
    glob=_by_parent(rows["global"],"GLOBAL")

    T,S,L,A,G=set(target),set(sub),set(act),set(auto),set(glob)
    if not (len(T)==len(S)==len(L)==cfg.full_census_n):
        raise AssertionError(f"full census count mismatch target={len(T)} subgroup={len(S)} actionability={len(L)}")
    if not (T==S==L):
        raise AssertionError("full census parent sets differ")

    ng_groups,ng_hashes=_validate_vector_rows(rows["ng10"],target,"NG10",None)
    grey_groups,grey_hashes=_validate_vector_rows(rows["grey"],target,"GREY","group")
    NG={k[0] for k in ng_groups}; GP={k[0] for k in grey_groups}
    if not (len(A)==len(G)==len(NG)==len(GP)==cfg.deployed_n):
        raise AssertionError(f"deployed parent count mismatch auto={len(A)} global={len(G)} ng10={len(NG)} grey={len(GP)} expected={cfg.deployed_n}")
    if not (A==G==NG==GP):
        raise AssertionError("deployed parent sets differ")
    if not A <= T:
        raise AssertionError("deployed parent set not subset of full census")
    excluded=tuple(sorted(T-A))
    if len(excluded)!=cfg.nondeployed_n:
        raise AssertionError(f"frozen nondeployed count={len(excluded)} expected={cfg.nondeployed_n}")

    for pid in sorted(T):
        for role,d in (("SUBGROUP",sub),("ACTIONABILITY",act)):
            if str(d[pid]["source_id"]).strip()!=str(target[pid]["source_id"]).strip() or _int(d[pid]["h"],f"{role}.h")!=_int(target[pid]["h"],"target.h"):
                raise AssertionError(f"{role}: metadata mismatch {pid}")
        ssel=_bool(sub[pid]["selection_pair_eligible"],"sub.selection_pair_eligible")
        spr=_bool(sub[pid]["practical_pair_eligible"],"sub.practical_pair_eligible")
        asel=_bool(act[pid]["selector_pair_eligible"],"act.selector_pair_eligible")
        apr=_bool(act[pid]["practical_pair_eligible"],"act.practical_pair_eligible")
        if (ssel,spr)!=(asel,apr):
            raise AssertionError(f"subgroup/actionability eligibility disagreement {pid}")
        if pid in A and not (ssel and spr):
            raise AssertionError(f"deployed parent not pair eligible {pid}")
        if pid not in A and (ssel or spr):
            raise AssertionError(f"nondeployed parent unexpectedly pair eligible {pid}")

    for role,d in (("AUTOGREY",auto),("GLOBAL",glob)):
        for pid,r in d.items():
            if str(r["source_id"]).strip()!=str(target[pid]["source_id"]).strip() or _int(r["h"],f"{role}.h")!=_int(target[pid]["h"],"target.h"):
                raise AssertionError(f"{role}: metadata mismatch {pid}")
            group=str(r["selected_group"]).strip()
            key=(pid,group)
            if key not in grey_hashes:
                raise AssertionError(f"{role}: selected frozen grey vector absent {key}")
            if str(r["forecast_sha256"]).strip().upper()!=grey_hashes[key]:
                raise AssertionError(f"{role}: decision/forecast hash mismatch {key}")

    return PreflightState(
        full_parent_ids=frozenset(T),
        deployed_parent_ids=frozenset(A),
        nondeployed_parent_ids=excluded,
        files=files,
        rows=rows,
        grey_vector_hashes=grey_hashes,
        ng10_vector_hashes={k[0]:v for k,v in ng_hashes.items()},
        target_binary_numeric_reads=0,
        development_index=development,
        target_index=target,
        autogrey_by_parent=auto,
        global_by_parent=glob,
        subgroup_by_parent=sub,
        actionability_by_parent=act,
        grey_rows_by_parent_group=grey_groups,
        ng10_rows_by_parent={k[0]:v for k,v in ng_groups.items()},
    )



PARENT_SCORE_FIELDS = [
    "parent_id","source_id","h","M","mase_scale","eligible_action_count",
    "autogrey_selected_group","global_selected_group","eligible_oracle_mase",
    "autogrey_mase","global_mase","ng10_mase","autogrey_regret","global_regret",
    "delta_selection_regret","delta_practical_mase","subgroup_h","subgroup_source",
    "subgroup_source_x_h","autogrey_forecast_sha256","global_forecast_sha256",
    "ng10_forecast_sha256","eligible_action_forecast_hashes_json",
]


def _state_parent_maps(state: PreflightState):
    auto=state.autogrey_by_parent or _by_parent(state.rows["autogrey"],"AUTOGREY")
    glob=state.global_by_parent or _by_parent(state.rows["global"],"GLOBAL")
    sub=state.subgroup_by_parent or _by_parent(state.rows["subgroup"],"SUBGROUP")
    act=state.actionability_by_parent or _by_parent(state.rows["actionability"],"ACTIONABILITY")
    grey=state.grey_rows_by_parent_group
    if grey is None:
        grey=defaultdict(list)
        for r in state.rows["grey"]:
            grey[(str(r["parent_id"]).strip(),str(r["group"]).strip())].append(r)
        grey=dict(grey)
    ng=state.ng10_rows_by_parent
    if ng is None:
        ng=defaultdict(list)
        for r in state.rows["ng10"]:
            ng[str(r["parent_id"]).strip()].append(r)
        ng=dict(ng)
    return auto,glob,sub,act,grey,ng


def _forecast_vector_from_rows(rows: list[dict[str,str]], h: int, role: str) -> np.ndarray:
    if not rows:
        raise AssertionError(f"{role}: missing forecast rows")
    ordered=sorted(rows,key=lambda r:_int(r["step"],f"{role}.step"))
    steps=[_int(r["step"],f"{role}.step") for r in ordered]
    if steps != list(range(1,h+1)):
        raise AssertionError(f"{role}: forecast step mismatch steps={steps} h={h}")
    try:
        f=np.asarray([float(str(r["forecast"]).strip()) for r in ordered],dtype=np.float64)
    except Exception as e:
        raise AssertionError(f"{role}: non-numeric forecast value") from e
    if f.size != h:
        raise AssertionError(f"{role}: forecast length mismatch got={f.size} h={h}")
    if not np.all(np.isfinite(f)):
        raise AssertionError(f"{role}: forecast contains non-finite value")
    hs={str(r["forecast_sha256"]).strip().upper() for r in ordered}
    if "" in hs or len(hs)!=1:
        raise AssertionError(f"{role}: forecast hash inconsistency")
    return f


def _mase_from_scale(y: np.ndarray, f: np.ndarray, scale: float, role: str) -> float:
    yy=np.asarray(y,dtype=np.float64); ff=np.asarray(f,dtype=np.float64)
    if yy.ndim!=1 or ff.ndim!=1 or yy.size==0 or yy.size!=ff.size:
        raise AssertionError(f"{role}: target/forecast length mismatch")
    if not np.all(np.isfinite(yy)) or not np.all(np.isfinite(ff)):
        raise AssertionError(f"{role}: target/forecast contains non-finite value")
    if not math.isfinite(scale) or scale<=0:
        raise AssertionError(f"DEGENERATE_MASE_SCALE: scale={scale}")
    out=float(np.mean(np.abs(ff-yy),dtype=np.float64)/scale)
    if not math.isfinite(out):
        raise AssertionError(f"{role}: MASE result non-finite")
    return out


def _m_value(v) -> int:
    if v is None or str(v).strip()=="":
        return 1
    x=float(v)
    if not math.isfinite(x) or not x.is_integer() or x<1:
        raise AssertionError(f"invalid parent M={v!r}")
    return int(x)


def score_parent(parent_id: str, state: PreflightState) -> ParentScore:
    pid=str(parent_id).strip()
    if pid not in state.deployed_parent_ids:
        raise AssertionError(f"parent not in frozen deployed scoring set: {pid}")
    if state.development_index is None or state.target_index is None:
        raise AssertionError("scoring state missing development/target index maps")
    if "dev_binary" not in state.files or "target_binary" not in state.files:
        raise AssertionError("scoring state missing development/target binary paths")

    auto,glob,sub,act,grey_by_key,ng_by_parent=_state_parent_maps(state)
    for role,d in (("AUTOGREY",auto),("GLOBAL",glob),("SUBGROUP",sub),("ACTIONABILITY",act)):
        if pid not in d:
            raise AssertionError(f"{role}: missing deployed parent {pid}")

    ar=act[pid]; sr=sub[pid]; aur=auto[pid]; gr=glob[pid]
    source=str(ar["source_id"]).strip()
    h=_int(ar["h"],"actionability.h")
    M=_m_value(ar.get("M"))
    if str(sr["source_id"]).strip()!=source or _int(sr["h"],"subgroup.h")!=h:
        raise AssertionError(f"subgroup/actionability metadata mismatch {pid}")
    for role,r in (("AUTOGREY",aur),("GLOBAL",gr)):
        if str(r["source_id"]).strip()!=source or _int(r["h"],f"{role}.h")!=h:
            raise AssertionError(f"{role}: metadata mismatch {pid}")

    drow=state.development_index.get(pid)
    trow=state.target_index.get(pid)
    if drow is None or trow is None:
        raise AssertionError(f"binary index missing deployed parent {pid}")
    if str(drow.get("source_id",source)).strip()!=source or _int(drow.get("h",h),"development.h")!=h:
        raise AssertionError(f"development metadata mismatch {pid}")
    if str(trow.get("source_id",source)).strip()!=source or _int(trow.get("h",h),"target.h")!=h:
        raise AssertionError(f"target metadata mismatch {pid}")
    if str(drow.get("M","")).strip() and _m_value(drow["M"])!=M:
        raise AssertionError(f"development/actionability M mismatch {pid}")

    D=read_development_vector(pid,state.development_index,state.files["dev_binary"])
    if str(ar.get("n_D","")).strip() and _int(ar["n_D"],"actionability.n_D")!=D.size:
        raise AssertionError(f"development/actionability n_D mismatch {pid}")
    scale=mase_scale(D,M)

    # This is the first numerical target access inside a future real scoring run.
    state.target_binary_numeric_reads += 1
    y=read_target_vector(pid,state.target_index,state.files["target_binary"])
    if y.size!=h:
        raise AssertionError(f"target horizon mismatch {pid}")

    group_keys=sorted(k for k in grey_by_key if k[0]==pid)
    groups=[k[1] for k in group_keys]
    if not groups:
        raise AssertionError(f"no frozen eligible grey actions for deployed parent {pid}")
    if len(set(groups))!=len(groups):
        raise AssertionError(f"duplicate frozen eligible group for parent {pid}")
    expected_count=_int(ar["retained_post_collision"],"retained_post_collision")
    if expected_count!=len(groups):
        raise AssertionError(f"retained action count mismatch parent={pid}: ledger={expected_count} forecasts={len(groups)}")
    for role,r in (("AUTOGREY",aur),("GLOBAL",gr)):
        if _int(r["action_count"],f"{role}.action_count")!=len(groups):
            raise AssertionError(f"{role}: action_count mismatch parent={pid}")

    action_mase={}
    action_hashes={}
    for key in group_keys:
        grp=key[1]
        rr=grey_by_key[key]
        fv=_forecast_vector_from_rows(rr,h,f"GREY[{pid},{grp}]")
        action_mase[grp]=_mase_from_scale(y,fv,scale,f"GREY[{pid},{grp}]")
        hs={str(r["forecast_sha256"]).strip().upper() for r in rr}
        action_hashes[grp]=next(iter(hs))

    ag=str(aur["selected_group"]).strip(); gg=str(gr["selected_group"]).strip()
    if ag not in action_mase:
        raise AssertionError(f"AUTOGREY selected group absent from frozen eligible actions: {pid}|{ag}")
    if gg not in action_mase:
        raise AssertionError(f"GLOBAL selected group absent from frozen eligible actions: {pid}|{gg}")
    if str(aur["forecast_sha256"]).strip().upper()!=action_hashes[ag]:
        raise AssertionError(f"AUTOGREY selected forecast hash mismatch {pid}|{ag}")
    if str(gr["forecast_sha256"]).strip().upper()!=action_hashes[gg]:
        raise AssertionError(f"GLOBAL selected forecast hash mismatch {pid}|{gg}")

    oracle=min(action_mase.values())
    ag_mase=action_mase[ag]; g_mase=action_mase[gg]
    ag_regret=max(0.0,ag_mase-oracle); g_regret=max(0.0,g_mase-oracle)

    if pid not in ng_by_parent:
        raise AssertionError(f"NG10: missing deployed parent {pid}")
    ngv=_forecast_vector_from_rows(ng_by_parent[pid],h,f"NG10[{pid}]")
    ng_mase=_mase_from_scale(y,ngv,scale,f"NG10[{pid}]")
    ng_hashes={str(r["forecast_sha256"]).strip().upper() for r in ng_by_parent[pid]}
    ng_hash=next(iter(ng_hashes))
    frozen_ng_hash=state.ng10_vector_hashes.get(pid)
    if frozen_ng_hash is not None and frozen_ng_hash.upper()!=ng_hash:
        raise AssertionError(f"NG10 frozen forecast hash mismatch {pid}")

    vals=(scale,oracle,ag_mase,g_mase,ng_mase,ag_regret,g_regret,ag_regret-g_regret,ag_mase-ng_mase)
    if not all(math.isfinite(float(x)) for x in vals):
        raise AssertionError(f"parent score contains non-finite value {pid}")

    return ParentScore(
        parent_id=pid, source_id=source, h=h, M=M, mase_scale=scale,
        eligible_action_count=len(groups), autogrey_selected_group=ag,
        global_selected_group=gg, eligible_oracle_mase=oracle,
        autogrey_mase=ag_mase, global_mase=g_mase, ng10_mase=ng_mase,
        autogrey_regret=ag_regret, global_regret=g_regret,
        delta_selection_regret=ag_regret-g_regret,
        delta_practical_mase=ag_mase-ng_mase,
        subgroup_h=str(h), subgroup_source=source,
        subgroup_source_x_h=f"{source}|{h}",
        autogrey_forecast_sha256=action_hashes[ag],
        global_forecast_sha256=action_hashes[gg], ng10_forecast_sha256=ng_hash,
        eligible_action_forecast_hashes_json=json.dumps(
            {g:action_hashes[g] for g in sorted(action_hashes)},
            sort_keys=True,separators=(",",":"),
        ),
    )


def score_all_parents(state: PreflightState) -> list[ParentScore]:
    ids=sorted(state.deployed_parent_ids)
    if not ids:
        raise AssertionError("frozen deployed scoring population is empty")
    scores=[]
    for pid in ids:
        scores.append(score_parent(pid,state))
    if len(scores)!=len(ids):
        raise AssertionError(f"parent score row count mismatch got={len(scores)} expected={len(ids)}")
    got=[s.parent_id for s in scores]
    if got!=ids or len(set(got))!=len(got):
        raise AssertionError("parent score IDs are not unique/sorted/exact")
    return scores


def _fmt_float(x: float) -> str:
    y=float(x)
    if not math.isfinite(y):
        raise AssertionError(f"cannot serialize non-finite parent score: {x!r}")
    return format(y,".17g")


def _parent_score_row(s: ParentScore) -> dict[str,str]:
    return {
        "parent_id":s.parent_id,"source_id":s.source_id,"h":str(s.h),"M":str(s.M),
        "mase_scale":_fmt_float(s.mase_scale),"eligible_action_count":str(s.eligible_action_count),
        "autogrey_selected_group":s.autogrey_selected_group,"global_selected_group":s.global_selected_group,
        "eligible_oracle_mase":_fmt_float(s.eligible_oracle_mase),
        "autogrey_mase":_fmt_float(s.autogrey_mase),"global_mase":_fmt_float(s.global_mase),
        "ng10_mase":_fmt_float(s.ng10_mase),"autogrey_regret":_fmt_float(s.autogrey_regret),
        "global_regret":_fmt_float(s.global_regret),"delta_selection_regret":_fmt_float(s.delta_selection_regret),
        "delta_practical_mase":_fmt_float(s.delta_practical_mase),"subgroup_h":s.subgroup_h,
        "subgroup_source":s.subgroup_source,"subgroup_source_x_h":s.subgroup_source_x_h,
        "autogrey_forecast_sha256":s.autogrey_forecast_sha256,
        "global_forecast_sha256":s.global_forecast_sha256,"ng10_forecast_sha256":s.ng10_forecast_sha256,
        "eligible_action_forecast_hashes_json":s.eligible_action_forecast_hashes_json,
    }


def write_and_verify_parent_score_table(scores: list[ParentScore], path: Path) -> str:
    p=Path(path)
    refuse_existing_output(p)
    if not scores:
        raise AssertionError("parent score table cannot be empty")
    ids=[s.parent_id for s in scores]
    if ids!=sorted(ids) or len(ids)!=len(set(ids)):
        raise AssertionError("parent score table input must be unique and sorted by parent_id")
    p.parent.mkdir(parents=True,exist_ok=True)
    with p.open("w",encoding="utf-8",newline="") as f:
        w=csv.DictWriter(f,fieldnames=PARENT_SCORE_FIELDS,lineterminator="\n")
        w.writeheader()
        for s in scores:
            w.writerow(_parent_score_row(s))
    h1=sha256(p)
    header,rows=_read_csv(p)
    if header!=PARENT_SCORE_FIELDS:
        raise AssertionError(f"parent score table schema mismatch: {header}")
    if len(rows)!=len(scores):
        raise AssertionError(f"parent score table reread row count mismatch got={len(rows)} expected={len(scores)}")
    rid=[str(r["parent_id"]).strip() for r in rows]
    if rid!=ids or len(rid)!=len(set(rid)):
        raise AssertionError("parent score table reread IDs differ from sealed score order")
    numeric=["mase_scale","eligible_oracle_mase","autogrey_mase","global_mase","ng10_mase",
             "autogrey_regret","global_regret","delta_selection_regret","delta_practical_mase"]
    for r in rows:
        for col in numeric:
            try: v=float(r[col])
            except Exception as e: raise AssertionError(f"parent score table invalid numeric {col}") from e
            if not math.isfinite(v): raise AssertionError(f"parent score table non-finite numeric {col}")
        json.loads(r["eligible_action_forecast_hashes_json"])
    h2=sha256(p)
    if h1!=h2:
        raise AssertionError("parent score table hash changed during reread verification")
    return h1


def cvar90(values) -> float:
    x=np.asarray(values,dtype=np.float64)
    if x.ndim!=1 or x.size==0:
        raise AssertionError("CVaR90 requires a non-empty one-dimensional vector")
    if not np.isfinite(x).all():
        raise AssertionError("CVaR90 values must be finite")
    k=int(math.ceil(0.10*x.size))
    tail=np.partition(x,x.size-k)[x.size-k:]
    return float(np.mean(tail,dtype=np.float64))


def _overall_score_arrays(parent_scores, *, require_unique_ids=False):
    scores=list(parent_scores)
    if not scores:
        raise AssertionError("overall estimands require at least one parent score")
    ids=[str(s.parent_id) for s in scores]
    if require_unique_ids and len(ids)!=len(set(ids)):
        raise AssertionError("overall bootstrap source requires unique parent IDs")
    ar=np.asarray([s.autogrey_regret for s in scores],dtype=np.float64)
    gr=np.asarray([s.global_regret for s in scores],dtype=np.float64)
    am=np.asarray([s.autogrey_mase for s in scores],dtype=np.float64)
    ng=np.asarray([s.ng10_mase for s in scores],dtype=np.float64)
    values=np.column_stack((ar,gr,am,ng))
    if not np.isfinite(values).all():
        raise AssertionError("overall estimand inputs must be finite")
    return scores,ar,gr,am,ng


def overall_point_estimates(parent_scores) -> OverallPointEstimates:
    _,ar,gr,am,ng=_overall_score_arrays(parent_scores)
    return OverallPointEstimates(
        A=float(np.mean(ar-gr,dtype=np.float64)),
        B=float(np.mean(am-ng,dtype=np.float64)),
        C1=float(cvar90(ar)-cvar90(gr)),
        C2=float(cvar90(am)-cvar90(ng)),
    )


def overall_bootstrap(parent_scores, rng, B=OVERALL_BOOTSTRAP_B) -> np.ndarray:
    scores,ar,gr,am,ng=_overall_score_arrays(parent_scores,require_unique_ids=True)
    try:
        B_int=int(B)
    except Exception as e:
        raise AssertionError("bootstrap replicate count must be a positive integer") from e
    if B_int!=B or B_int<=0:
        raise AssertionError("bootstrap replicate count must be a positive integer")
    n=len(scores)
    out=np.empty((B_int,4),dtype=np.float64)
    for b in range(B_int):
        idx=np.asarray(rng.integers(0,n,size=n),dtype=np.intp)
        if idx.shape!=(n,):
            raise AssertionError(f"bootstrap RNG returned wrong parent-index shape: {idx.shape}")
        # One paired parent sample feeds all four frozen estimands in this replicate.
        ar_b=ar[idx]; gr_b=gr[idx]; am_b=am[idx]; ng_b=ng[idx]
        out[b,0]=np.mean(ar_b-gr_b,dtype=np.float64)
        out[b,1]=np.mean(am_b-ng_b,dtype=np.float64)
        out[b,2]=cvar90(ar_b)-cvar90(gr_b)
        out[b,3]=cvar90(am_b)-cvar90(ng_b)
    if not np.isfinite(out).all():
        raise AssertionError("overall bootstrap produced non-finite values")
    return out


def _overall_points_from_vector(values) -> OverallPointEstimates:
    x=np.asarray(values,dtype=np.float64)
    if x.shape!=(4,) or not np.isfinite(x).all():
        raise AssertionError("overall four-statistic vector must be finite with shape (4,)")
    return OverallPointEstimates(A=float(x[0]),B=float(x[1]),C1=float(x[2]),C2=float(x[3]))


def overall_bootstrap_bounds(bootstrap_values) -> OverallBootstrapBounds:
    x=np.asarray(bootstrap_values,dtype=np.float64)
    if x.ndim!=2 or x.shape[0]==0 or x.shape[1]!=4:
        raise AssertionError("overall bootstrap must have shape (B,4)")
    if not np.isfinite(x).all():
        raise AssertionError("overall bootstrap values must be finite")
    upper=np.quantile(x,q=0.95,axis=0,method="linear")
    lower=np.quantile(x,q=0.025,axis=0,method="linear")
    upper_context=np.quantile(x,q=0.975,axis=0,method="linear")
    return OverallBootstrapBounds(
        upper95=_overall_points_from_vector(upper),
        context_lower95=_overall_points_from_vector(lower),
        context_upper95=_overall_points_from_vector(upper_context),
    )


def write_and_verify_overall_bootstrap(bootstrap_values, path: Path) -> str:
    x=np.asarray(bootstrap_values,dtype=np.float64)
    if x.ndim!=2 or x.shape[0]==0 or x.shape[1]!=4:
        raise AssertionError("overall bootstrap artifact requires shape (B,4)")
    if not np.isfinite(x).all():
        raise AssertionError("overall bootstrap artifact contains non-finite values")
    p=Path(path)
    refuse_existing_output(p)
    p.parent.mkdir(parents=True,exist_ok=True)
    fields=["replicate",*OVERALL_ESTIMAND_NAMES]
    with p.open("w",encoding="utf-8",newline="") as f:
        w=csv.DictWriter(f,fieldnames=fields,lineterminator="\n")
        w.writeheader()
        for i,row in enumerate(x,1):
            w.writerow({
                "replicate":str(i),
                "A":_fmt_float(row[0]),
                "B":_fmt_float(row[1]),
                "C1":_fmt_float(row[2]),
                "C2":_fmt_float(row[3]),
            })
    h1=sha256(p)
    header,rows=_read_csv(p)
    if header!=fields:
        raise AssertionError(f"overall bootstrap artifact schema mismatch: {header}")
    if len(rows)!=x.shape[0]:
        raise AssertionError(f"overall bootstrap artifact row count mismatch got={len(rows)} expected={x.shape[0]}")
    for i,r in enumerate(rows,1):
        if r["replicate"]!=str(i):
            raise AssertionError("overall bootstrap artifact replicate sequence mismatch")
        for name in OVERALL_ESTIMAND_NAMES:
            try: v=float(r[name])
            except Exception as e: raise AssertionError(f"overall bootstrap artifact invalid numeric {name}") from e
            if not math.isfinite(v):
                raise AssertionError(f"overall bootstrap artifact non-finite numeric {name}")
    h2=sha256(p)
    if h1!=h2:
        raise AssertionError("overall bootstrap artifact hash changed during reread verification")
    return h1

FULL_CONFIRMATION_CLAIM = (
    "Under the frozen REALBENCH3 protocol, AutoGrey demonstrates external selector-value "
    "superiority over GLOBAL together with practical mean noninferiority to NG10 within "
    "0.05 MASE and the prespecified joint tail-robustness criteria."
)


def _pass_fail(value: bool) -> str:
    return "PASS" if bool(value) else "FAIL"


def evaluate_gates(points: OverallPointEstimates, bootstrap) -> GateDecision:
    vals=np.asarray([points.A,points.B,points.C1,points.C2],dtype=np.float64)
    if vals.shape!=(4,) or not np.isfinite(vals).all():
        raise AssertionError("overall point estimates must be finite")
    bounds=overall_bootstrap_bounds(bootstrap)
    a_ok=bool(bounds.upper95.A < 0.0)
    b_ok=bool(bounds.upper95.B < 0.05)
    c1_ok=bool(bounds.upper95.C1 < 0.0)
    c2_ok=bool(bounds.upper95.C2 < 0.05)
    c_ok=bool(c1_ok and c2_ok)

    a_conf=_pass_fail(a_ok)
    if not a_ok:
        b_conf="DESCRIPTIVE_NONCONFIRMATORY"
        c_conf="DESCRIPTIVE_NONCONFIRMATORY"
    else:
        b_conf=_pass_fail(b_ok)
        c_conf=_pass_fail(c_ok) if b_ok else "DESCRIPTIVE_NONCONFIRMATORY"

    overall_ok=bool(a_ok and b_ok and c_ok)
    allowed_claim=(
        FULL_CONFIRMATION_CLAIM
        if overall_ok
        else "No full-confirmation claim is authorized; preserve and report the frozen partial or negative result."
    )
    return GateDecision(
        points=points, bounds=bounds,
        gate_a_numerical=_pass_fail(a_ok),
        gate_b_numerical=_pass_fail(b_ok),
        gate_c1_numerical=_pass_fail(c1_ok),
        gate_c2_numerical=_pass_fail(c2_ok),
        gate_c_numerical=_pass_fail(c_ok),
        gate_a_confirmatory=a_conf,
        gate_b_confirmatory=b_conf,
        gate_c_confirmatory=c_conf,
        overall_status=_pass_fail(overall_ok),
        gate_a_claim_may_stand=bool(a_ok),
        full_confirmation_claim_allowed=overall_ok,
        allowed_claim_text=allowed_claim,
    )


def _overall_points_dict(v: OverallPointEstimates) -> dict[str,float]:
    return {name:float(getattr(v,name)) for name in OVERALL_ESTIMAND_NAMES}


def _claim_discipline_dict(d: GateDecision) -> dict[str,object]:
    return {
        "full_confirmation_claim_allowed":d.full_confirmation_claim_allowed,
        "allowed_claim_text":d.allowed_claim_text,
        "equivalence_to_ng10_claim_allowed":d.equivalence_to_ng10_claim_allowed,
        "universal_superiority_claim_allowed":d.universal_superiority_claim_allowed,
        "ng10_superiority_from_noninferiority_allowed":d.ng10_superiority_from_noninferiority_allowed,
        "every_non_grey_superiority_claim_allowed":d.every_non_grey_superiority_claim_allowed,
        "unqualified_generalization_claim_allowed":d.unqualified_generalization_claim_allowed,
    }


def _gate_status_dict(d: GateDecision) -> dict[str,dict[str,str]]:
    return {
        "A":{"numerical":d.gate_a_numerical,"confirmatory":d.gate_a_confirmatory},
        "B":{"numerical":d.gate_b_numerical,"confirmatory":d.gate_b_confirmatory},
        "C1":{"numerical":d.gate_c1_numerical,"confirmatory":d.gate_c_confirmatory},
        "C2":{"numerical":d.gate_c2_numerical,"confirmatory":d.gate_c_confirmatory},
        "C":{"numerical":d.gate_c_numerical,"confirmatory":d.gate_c_confirmatory},
    }


def write_overall_results(points: OverallPointEstimates, bootstrap, decision: GateDecision, path: Path) -> str:
    bounds=overall_bootstrap_bounds(bootstrap)
    if decision.points != points or decision.bounds != bounds:
        raise AssertionError("gate decision does not match supplied points/bootstrap")
    p=Path(path)
    refuse_existing_output(p)
    p.parent.mkdir(parents=True,exist_ok=True)
    rec={
        "schema":"AUTOGREY_V2_P11C_OVERALL_RESULTS_R1",
        "fixed_sequence":["A","B","C"],
        "strict_gate_inequalities":True,
        "thresholds":{"A":0.0,"B":0.05,"C1":0.0,"C2":0.05},
        "point_estimates":_overall_points_dict(points),
        "one_sided_upper95":_overall_points_dict(bounds.upper95),
        "context_two_sided95":{
            "lower":_overall_points_dict(bounds.context_lower95),
            "upper":_overall_points_dict(bounds.context_upper95),
            "context_only":True,
        },
        "quantile":{"one_sided_q":0.95,"method":"linear"},
        "gate_status":_gate_status_dict(decision),
        "gate_a_claim_may_stand":decision.gate_a_claim_may_stand,
        "overall_status":decision.overall_status,
        "claim_discipline":_claim_discipline_dict(decision),
        "negative_or_partial_result_preserved":decision.negative_or_partial_result_preserved,
        "configuration_change_allowed":decision.configuration_change_allowed,
        "scientific_lock_changed":decision.scientific_lock_changed,
    }
    p.write_text(json.dumps(rec,indent=2,sort_keys=True)+"\n",encoding="utf-8",newline="\n")
    return sha256(p)


def write_confirmatory_decision(
    decision: GateDecision,
    path: Path,
    *,
    full_census_n: int = 4781,
    deployed_n: int = 4778,
    nondeployed_n: int = 3,
    subgroup_role: str = "SECONDARY",
) -> str:
    if int(full_census_n) != int(deployed_n) + int(nondeployed_n):
        raise AssertionError("population counts are internally inconsistent")
    if subgroup_role != "SECONDARY":
        raise AssertionError("subgroup role must remain SECONDARY")
    p=Path(path)
    refuse_existing_output(p)
    p.parent.mkdir(parents=True,exist_ok=True)
    q=decision.bounds
    rows=[
        "AUTOGREY_V2_P11C_CONFIRMATORY_DECISION_R1",
        f"P11C0_R1={P11C0_HISTORY['R1']}",
        f"P11C0_R2={P11C0_HISTORY['R2']}",
        f"P11C0_R3={P11C0_HISTORY['R3']}",
        f"P11C0_R4={P11C0_HISTORY['R4']}",
        f"P11C0_R4_EVIDENCE_ZIP_SHA256={DEFAULT_EXPECTED_HASHES['r4_evidence']}",
        "P11B=PASS_CLOSED",
        "REALBENCH3_TARGET_STATE=PERMANENTLY_OPEN",
        f"FULL_CLEAN_CENSUS_N={int(full_census_n)}",
        f"DEPLOYED_SCORING_PARENT_N={int(deployed_n)}",
        f"FROZEN_NONDEPLOYED_CLEAN_PARENT_N={int(nondeployed_n)}",
        f"SUBGROUP_ROLE={subgroup_role}",
        "FIXED_SEQUENCE=A->B->C",
        "STRICT_GATE_INEQUALITIES=TRUE",
        f"POINT_A={_fmt_float(decision.points.A)}",
        f"POINT_B={_fmt_float(decision.points.B)}",
        f"POINT_C1={_fmt_float(decision.points.C1)}",
        f"POINT_C2={_fmt_float(decision.points.C2)}",
        f"UPPER95_A={_fmt_float(q.upper95.A)}",
        f"UPPER95_B={_fmt_float(q.upper95.B)}",
        f"UPPER95_C1={_fmt_float(q.upper95.C1)}",
        f"UPPER95_C2={_fmt_float(q.upper95.C2)}",
        f"CONTEXT_LOWER95_A={_fmt_float(q.context_lower95.A)}",
        f"CONTEXT_LOWER95_B={_fmt_float(q.context_lower95.B)}",
        f"CONTEXT_LOWER95_C1={_fmt_float(q.context_lower95.C1)}",
        f"CONTEXT_LOWER95_C2={_fmt_float(q.context_lower95.C2)}",
        f"CONTEXT_UPPER95_A={_fmt_float(q.context_upper95.A)}",
        f"CONTEXT_UPPER95_B={_fmt_float(q.context_upper95.B)}",
        f"CONTEXT_UPPER95_C1={_fmt_float(q.context_upper95.C1)}",
        f"CONTEXT_UPPER95_C2={_fmt_float(q.context_upper95.C2)}",
        f"GATE_A_NUMERICAL={decision.gate_a_numerical}",
        f"GATE_B_NUMERICAL={decision.gate_b_numerical}",
        f"GATE_C1_NUMERICAL={decision.gate_c1_numerical}",
        f"GATE_C2_NUMERICAL={decision.gate_c2_numerical}",
        f"GATE_C_NUMERICAL={decision.gate_c_numerical}",
        f"GATE_A_CONFIRMATORY={decision.gate_a_confirmatory}",
        f"GATE_B_CONFIRMATORY={decision.gate_b_confirmatory}",
        f"GATE_C_CONFIRMATORY={decision.gate_c_confirmatory}",
        f"GATE_A_CLAIM_MAY_STAND={'TRUE' if decision.gate_a_claim_may_stand else 'FALSE'}",
        f"OVERALL_STATUS={decision.overall_status}",
        f"FULL_CONFIRMATION_CLAIM_ALLOWED={'TRUE' if decision.full_confirmation_claim_allowed else 'FALSE'}",
        f"ALLOWED_CLAIM_TEXT={decision.allowed_claim_text}",
        "EQUIVALENCE_TO_NG10_CLAIM_ALLOWED=FALSE",
        "UNIVERSAL_SUPERIORITY_CLAIM_ALLOWED=FALSE",
        "NG10_SUPERIORITY_FROM_NONINFERIORITY_ALLOWED=FALSE",
        "EVERY_NON_GREY_SUPERIORITY_CLAIM_ALLOWED=FALSE",
        "UNQUALIFIED_GENERALIZATION_CLAIM_ALLOWED=FALSE",
        "NEGATIVE_OR_PARTIAL_RESULT_PRESERVED=TRUE",
        "CONFIGURATION_CHANGE_ALLOWED=FALSE",
        "SCIENTIFIC_LOCK_CHANGED=FALSE",
        "P12=LOCKED",
    ]
    p.write_text("\n".join(rows)+"\n",encoding="utf-8",newline="\n")
    return sha256(p)



SUBGROUP_BOOTSTRAP_B = 4000
SUBGROUP_MIN_INFERENTIAL_N = 30
SUBGROUP_DIMENSIONS = (
    ("horizon", "subgroup_h"),
    ("source", "subgroup_source"),
    ("source_x_h", "subgroup_source_x_h"),
)
SUBGROUP_HOLM_FAMILY_ORDER = ("A", "C1", "B", "C2")
SUBGROUP_HOLM_FAMILY_LABELS = {
    "A": "selection_mean_regret",
    "C1": "selection_cvar90_regret",
    "B": "practical_mean_mase",
    "C2": "practical_cvar90_mase",
}
SUBGROUP_RESULT_FIELDS = [
    "dimension", "label", "n", "inference_allowed", "subgroup_role",
    "point_A", "point_B", "point_C1", "point_C2",
    "raw_p_A", "raw_p_B", "raw_p_C1", "raw_p_C2",
    "holm_p_A", "holm_p_B", "holm_p_C1", "holm_p_C2",
    "holm_reject_A", "holm_reject_B", "holm_reject_C1", "holm_reject_C2",
]


def holm_adjust(pvalues):
    p=np.asarray(list(pvalues),dtype=np.float64)
    if p.ndim!=1:
        raise AssertionError("Holm p-values must be one-dimensional")
    if p.size==0:
        return []
    if not np.isfinite(p).all() or np.any(p < 0.0) or np.any(p > 1.0):
        raise AssertionError("Holm p-values must be finite in [0,1]")
    order=np.argsort(p,kind="stable")
    ps=p[order]
    m=int(ps.size)
    adj_sorted=np.empty(m,dtype=np.float64)
    running=0.0
    for i,val in enumerate(ps):
        candidate=min(1.0,float((m-i)*val))
        running=max(running,candidate)
        adj_sorted[i]=running
    adjusted=np.empty(m,dtype=np.float64)
    adjusted[order]=adj_sorted
    return [float(x) for x in adjusted]


def _subgroup_bootstrap_values(scores, rng, index_hasher: hashlib._Hash | None = None) -> np.ndarray:
    members,ar,gr,am,ng=_overall_score_arrays(scores,require_unique_ids=True)
    n=len(members)
    out=np.empty((SUBGROUP_BOOTSTRAP_B,4),dtype=np.float64)
    for b in range(SUBGROUP_BOOTSTRAP_B):
        idx=np.asarray(rng.integers(0,n,size=n),dtype=np.intp)
        if idx.shape!=(n,):
            raise AssertionError(f"subgroup bootstrap RNG returned wrong parent-index shape: {idx.shape}")
        if np.any(idx < 0) or np.any(idx >= n):
            raise AssertionError("subgroup bootstrap RNG returned out-of-range parent index")
        if index_hasher is not None:
            index_hasher.update(np.asarray(idx,dtype="<i8").tobytes(order="C"))
        ar_b=ar[idx]; gr_b=gr[idx]; am_b=am[idx]; ng_b=ng[idx]
        # A single paired-parent draw feeds all four frozen subgroup estimands.
        out[b,0]=np.mean(ar_b-gr_b,dtype=np.float64)
        out[b,1]=np.mean(am_b-ng_b,dtype=np.float64)
        out[b,2]=cvar90(ar_b)-cvar90(gr_b)
        out[b,3]=cvar90(am_b)-cvar90(ng_b)
    if not np.isfinite(out).all():
        raise AssertionError("subgroup bootstrap produced non-finite values")
    return out


def _json_state_sha256(state) -> str:
    raw=json.dumps(state,sort_keys=True,separators=(",",":"),default=int).encode("utf-8")
    return hashlib.sha256(raw).hexdigest().upper()


def run_subgroups(parent_scores, rng) -> tuple[list[dict[str,object]], dict[str,object]]:
    scores=list(parent_scores)
    if not scores:
        raise AssertionError("subgroup analysis requires at least one parent score")
    ids=[str(s.parent_id) for s in scores]
    if len(ids)!=len(set(ids)):
        raise AssertionError("subgroup analysis source requires unique parent IDs")
    bitgen=getattr(rng,"bit_generator",None)
    bitgen_name=type(bitgen).__name__ if bitgen is not None else ""
    if bitgen_name!="PCG64":
        raise AssertionError(f"subgroup bootstrap requires PCG64; got={bitgen_name or 'NONE'}")
    state_before=_json_state_sha256(bitgen.state)
    rows=[]
    labels_by_dimension={}
    index_hasher=hashlib.sha256()

    for dimension,attr in SUBGROUP_DIMENSIONS:
        grouped=defaultdict(list)
        for score in scores:
            label=str(getattr(score,attr)).strip()
            if not label:
                raise AssertionError(f"empty frozen subgroup label for {dimension}: {score.parent_id}")
            grouped[label].append(score)
        labels=sorted(grouped)
        labels_by_dimension[dimension]=labels
        for label in labels:
            members=sorted(grouped[label],key=lambda x:str(x.parent_id))
            points=overall_point_estimates(members)
            n=len(members)
            inferential=bool(n >= SUBGROUP_MIN_INFERENTIAL_N)
            row={
                "dimension":dimension,
                "label":label,
                "n":n,
                "inference_allowed":inferential,
                "subgroup_role":"SECONDARY",
                "point_A":float(points.A),
                "point_B":float(points.B),
                "point_C1":float(points.C1),
                "point_C2":float(points.C2),
            }
            for name in OVERALL_ESTIMAND_NAMES:
                row[f"raw_p_{name}"]=None
                row[f"holm_p_{name}"]=None
                row[f"holm_reject_{name}"]=None
            if inferential:
                index_hasher.update(dimension.encode("utf-8")+b"\0"+label.encode("utf-8")+b"\0")
                boot=_subgroup_bootstrap_values(members,rng,index_hasher)
                for j,name in enumerate(OVERALL_ESTIMAND_NAMES):
                    nonnegative=int(np.count_nonzero(boot[:,j] >= 0.0))
                    row[f"raw_p_{name}"]=float((1+nonnegative)/(SUBGROUP_BOOTSTRAP_B+1))
            rows.append(row)

    inferential_rows=[r for r in rows if bool(r["inference_allowed"])]
    for family in SUBGROUP_HOLM_FAMILY_ORDER:
        adjusted=holm_adjust([r[f"raw_p_{family}"] for r in inferential_rows])
        for row,adj in zip(inferential_rows,adjusted):
            row[f"holm_p_{family}"]=float(adj)
            row[f"holm_reject_{family}"]=bool(adj <= 0.05)

    audit={
        "schema":"AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1",
        "subgroup_role":"SECONDARY",
        "dimension_order":[x[0] for x in SUBGROUP_DIMENSIONS],
        "labels_by_dimension":labels_by_dimension,
        "labels_processed_lexicographically":True,
        "inferential_min_n":SUBGROUP_MIN_INFERENTIAL_N,
        "n_below_threshold_descriptive_only":True,
        "bootstrap_B":SUBGROUP_BOOTSTRAP_B,
        "rng_bit_generator":bitgen_name,
        "rng_stream_policy":"CONTINUE_CALLER_SUPPLIED_PCG64_AFTER_OVERALL_BOOTSTRAP",
        "rng_state_before_sha256":state_before,
        "rng_state_after_sha256":_json_state_sha256(bitgen.state),
        "same_sampled_indices_for_all_four_stats":True,
        "one_sided_p_formula":"(1 + count(diff >= 0)) / (B + 1)",
        "holm_fwer":0.05,
        "holm_family_order":list(SUBGROUP_HOLM_FAMILY_ORDER),
        "holm_family_labels":dict(SUBGROUP_HOLM_FAMILY_LABELS),
        "subgroup_n":len(rows),
        "inferential_subgroup_n":len(inferential_rows),
        "descriptive_only_subgroup_n":len(rows)-len(inferential_rows),
        "subgroup_resample_index_sha256":index_hasher.hexdigest().upper(),
        "may_alter_overall_confirmatory_classification":False,
        "scientific_lock_changed":False,
    }
    return rows,audit


def _subgroup_csv_value(value):
    if value is None:
        return ""
    if isinstance(value,bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value,float):
        return _fmt_float(value)
    return str(value)


def write_and_verify_subgroup_results(rows, path: Path) -> str:
    records=list(rows)
    if not records:
        raise AssertionError("subgroup results cannot be empty")
    p=Path(path)
    refuse_existing_output(p)
    p.parent.mkdir(parents=True,exist_ok=True)
    with p.open("w",encoding="utf-8",newline="") as f:
        w=csv.DictWriter(f,fieldnames=SUBGROUP_RESULT_FIELDS,lineterminator="\n")
        w.writeheader()
        for row in records:
            missing=[k for k in SUBGROUP_RESULT_FIELDS if k not in row]
            if missing:
                raise AssertionError(f"subgroup result row missing fields: {missing}")
            w.writerow({k:_subgroup_csv_value(row[k]) for k in SUBGROUP_RESULT_FIELDS})
    h1=sha256(p)
    header,reread=_read_csv(p)
    if header!=SUBGROUP_RESULT_FIELDS:
        raise AssertionError(f"subgroup results schema mismatch: {header}")
    if len(reread)!=len(records):
        raise AssertionError(f"subgroup results row count mismatch got={len(reread)} expected={len(records)}")
    observed=[(r["dimension"],r["label"]) for r in reread]
    expected=[(str(r["dimension"]),str(r["label"])) for r in records]
    if observed!=expected:
        raise AssertionError("subgroup results row order changed during reread")
    h2=sha256(p)
    if h1!=h2:
        raise AssertionError("subgroup results hash changed during reread verification")
    return h1


def write_subgroup_audit(audit, path: Path) -> str:
    record=dict(audit)
    if record.get("schema")!="AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1":
        raise AssertionError("subgroup audit schema mismatch")
    if record.get("subgroup_role")!="SECONDARY":
        raise AssertionError("subgroup audit must remain SECONDARY")
    if bool(record.get("may_alter_overall_confirmatory_classification")):
        raise AssertionError("subgroups may not alter overall confirmatory classification")
    p=Path(path)
    refuse_existing_output(p)
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(record,indent=2,sort_keys=True)+"\n",encoding="utf-8",newline="\n")
    reread=json.loads(p.read_text(encoding="utf-8"))
    if reread!=record:
        raise AssertionError("subgroup audit changed during reread verification")
    return sha256(p)


def _assert_binary_slice_schema(index: dict[str,dict[str,str]] | None, role: str) -> None:
    if not index:
        raise AssertionError(f"{role} index is missing or empty")
    for pid,row in index.items():
        missing=[name for name in TARGET_BINARY_SLICE_FIELDS if name not in row or str(row[name]).strip()==""]
        if missing:
            raise AssertionError(f"{role} binary index schema missing fields for {pid}: {missing}")
        offset=_int(row["binary_offset_bytes"],f"{role}.binary_offset_bytes")
        n_values=_int(row["binary_length_values"],f"{role}.binary_length_values")
        n_bytes=_int(row["binary_length_bytes"],f"{role}.binary_length_bytes")
        if offset < 0 or offset % 8 != 0:
            raise AssertionError(f"{role} binary offset invalid or not float64 aligned: {pid}|{offset}")
        if n_values <= 0 or n_bytes != n_values*8:
            raise AssertionError(f"{role} binary length contract invalid: {pid}")


def execute_preflight(paths: EntryPaths, output_dir: Path, *, config: EntryGateConfig | None = None) -> PreflightState:
    out=Path(output_dir)
    refuse_existing_output(out)
    state=verify_entry_gate(paths,config=config)
    if state.target_binary_numeric_reads != 0:
        raise AssertionError("score-free preflight numerically read target values")
    _assert_binary_slice_schema(state.development_index,"development")
    _assert_binary_slice_schema(state.target_index,"target")
    out.mkdir(parents=True)
    rec={
        "schema":"AUTOGREY_V2_P11C_PREFLIGHT_R1",
        "status":"PASS",
        "realbench3_target_state":"PERMANENTLY_OPEN",
        "full_clean_census_n":len(state.full_parent_ids),
        "deployed_scoring_parent_n":len(state.deployed_parent_ids),
        "frozen_nondeployed_clean_parent_n":len(state.nondeployed_parent_ids),
        "development_index_binary_slice_schema_bound":True,
        "target_index_binary_slice_schema_bound":True,
        "target_binary_numeric_values_read":False,
        "scientific_scoring_performed":False,
        "scientific_lock_changed":False,
        "p12_locked":True,
    }
    p=out/"AUTOGREY_V2_P11C_PREFLIGHT_R1.json"
    p.write_text(json.dumps(rec,indent=2,sort_keys=True)+"\n",encoding="utf-8",newline="\n")
    return state


def _population_counts(full_census_n, deployed_n, nondeployed_n, score_n):
    dep=score_n if deployed_n is None else int(deployed_n)
    full=dep if full_census_n is None else int(full_census_n)
    nondep=(full-dep) if nondeployed_n is None else int(nondeployed_n)
    if dep != score_n:
        raise AssertionError(f"deployed population count does not match parent scores: {dep}!={score_n}")
    if full != dep + nondep or min(full,dep,nondep) < 0:
        raise AssertionError("population counts are internally inconsistent")
    return full,dep,nondep


def write_assertions(
    decision: GateDecision,
    subgroup_audit: dict[str,object],
    artifact_hashes: dict[str,str],
    path: Path,
    *,
    full_census_n: int,
    deployed_n: int,
    nondeployed_n: int,
    target_numeric_reads: int,
) -> str:
    if subgroup_audit.get("subgroup_role") != "SECONDARY":
        raise AssertionError("subgroup role must remain SECONDARY")
    if bool(subgroup_audit.get("may_alter_overall_confirmatory_classification")):
        raise AssertionError("subgroups may not alter overall confirmatory classification")
    if decision.scientific_lock_changed or decision.configuration_change_allowed:
        raise AssertionError("scientific lock/configuration changed")
    p=Path(path)
    refuse_existing_output(p)
    p.parent.mkdir(parents=True,exist_ok=True)
    b=decision.bounds
    rec={
        "schema":"AUTOGREY_V2_P11C_ASSERTIONS_R1",
        "p11c0_history":dict(P11C0_HISTORY),
        "p11c0_r4_evidence_zip_sha256":DEFAULT_EXPECTED_HASHES["r4_evidence"],
        "p11b_status":"PASS_CLOSED",
        "realbench3_target_state":"PERMANENTLY_OPEN",
        "population":{
            "full_clean_census_n":int(full_census_n),
            "deployed_scoring_parent_n":int(deployed_n),
            "frozen_nondeployed_clean_parent_n":int(nondeployed_n),
        },
        "target_binary_numeric_parent_reads":int(target_numeric_reads),
        "point_estimates":_overall_points_dict(decision.points),
        "one_sided_upper95":_overall_points_dict(b.upper95),
        "context_two_sided95":{
            "lower":_overall_points_dict(b.context_lower95),
            "upper":_overall_points_dict(b.context_upper95),
            "context_only":True,
        },
        "gate_status":_gate_status_dict(decision),
        "overall_status":decision.overall_status,
        "fixed_sequence":["A","B","C"],
        "strict_gate_inequalities":True,
        "subgroup_role":"SECONDARY",
        "subgroups_may_alter_overall_confirmatory_classification":False,
        "negative_or_partial_result_preserved":decision.negative_or_partial_result_preserved,
        "configuration_change_allowed":decision.configuration_change_allowed,
        "scientific_lock_changed":decision.scientific_lock_changed,
        "claim_discipline":_claim_discipline_dict(decision),
        "artifact_sha256":dict(sorted(artifact_hashes.items())),
        "p12_locked":True,
    }
    p.write_text(json.dumps(rec,indent=2,sort_keys=True)+"\n",encoding="utf-8",newline="\n")
    reread=json.loads(p.read_text(encoding="utf-8"))
    if reread != rec:
        raise AssertionError("assertions artifact changed during reread verification")
    return sha256(p)


def verify_output_manifest(output_dir: Path, manifest_path: Path | None = None) -> bool:
    out=Path(output_dir)
    man=Path(manifest_path) if manifest_path is not None else out/RESULT_MANIFEST_NAME
    entries=_parse_manifest(man)
    names=[Path(rel).name for _,rel in entries]
    if names != sorted(PRE_MANIFEST_RESULT_FILES):
        raise AssertionError(f"result manifest member set/order mismatch: {names}")
    for expected,rel in entries:
        p=out/Path(rel).name
        if not p.is_file():
            raise FileNotFoundError(f"result manifest member missing: {p}")
        got=sha256(p)
        if got != expected.upper():
            raise AssertionError(f"result manifest member hash mismatch: {p.name}")
    return True


def write_output_manifest(output_dir: Path, manifest_path: Path | None = None) -> str:
    out=Path(output_dir)
    man=Path(manifest_path) if manifest_path is not None else out/RESULT_MANIFEST_NAME
    refuse_existing_output(man)
    lines=[]
    for name in sorted(PRE_MANIFEST_RESULT_FILES):
        p=out/name
        if not p.is_file():
            raise FileNotFoundError(f"cannot seal manifest; required output missing: {p}")
        lines.append(f"{sha256(p)}  {name}")
    man.write_text("\n".join(lines)+"\n",encoding="utf-8",newline="\n")
    verify_output_manifest(out,man)
    return sha256(man)


def _seal_scientific_outputs_prepared(
    parent_scores,
    out: Path,
    *,
    full_census_n: int,
    deployed_n: int,
    nondeployed_n: int,
    target_numeric_reads: int,
):
    scores=sorted(list(parent_scores),key=lambda x:str(x.parent_id))
    if not scores:
        raise AssertionError("cannot seal an empty parent score population")
    ids=[str(s.parent_id) for s in scores]
    if len(ids) != len(set(ids)):
        raise AssertionError("cannot seal duplicate parent score IDs")
    full,dep,nondep=_population_counts(full_census_n,deployed_n,nondeployed_n,len(scores))
    artifact_hashes={}
    parent_path=out/PRE_MANIFEST_RESULT_FILES[0]
    artifact_hashes[parent_path.name]=write_and_verify_parent_score_table(scores,parent_path)

    rng=np.random.default_rng(OVERALL_BOOTSTRAP_SEED)
    points=overall_point_estimates(scores)
    boot=overall_bootstrap(scores,rng)
    bootstrap_path=out/PRE_MANIFEST_RESULT_FILES[1]
    artifact_hashes[bootstrap_path.name]=write_and_verify_overall_bootstrap(boot,bootstrap_path)
    decision=evaluate_gates(points,boot)
    overall_path=out/PRE_MANIFEST_RESULT_FILES[2]
    artifact_hashes[overall_path.name]=write_overall_results(points,boot,decision,overall_path)

    subgroup_rows,subgroup_audit=run_subgroups(scores,rng)
    subgroup_path=out/PRE_MANIFEST_RESULT_FILES[3]
    subgroup_audit_path=out/PRE_MANIFEST_RESULT_FILES[4]
    artifact_hashes[subgroup_path.name]=write_and_verify_subgroup_results(subgroup_rows,subgroup_path)
    artifact_hashes[subgroup_audit_path.name]=write_subgroup_audit(subgroup_audit,subgroup_audit_path)

    decision_path=out/PRE_MANIFEST_RESULT_FILES[5]
    artifact_hashes[decision_path.name]=write_confirmatory_decision(
        decision,decision_path,
        full_census_n=full,deployed_n=dep,nondeployed_n=nondep,subgroup_role="SECONDARY",
    )
    assertions_path=out/PRE_MANIFEST_RESULT_FILES[6]
    artifact_hashes[assertions_path.name]=write_assertions(
        decision,subgroup_audit,artifact_hashes,assertions_path,
        full_census_n=full,deployed_n=dep,nondeployed_n=nondep,target_numeric_reads=target_numeric_reads,
    )
    manifest_hash=write_output_manifest(out)
    return {
        "decision":decision,
        "subgroup_audit":subgroup_audit,
        "artifact_hashes":dict(artifact_hashes),
        "manifest_sha256":manifest_hash,
        "output_dir":out,
    }


def seal_scientific_outputs(
    parent_scores,
    output_dir: Path,
    *,
    full_census_n: int | None = None,
    deployed_n: int | None = None,
    nondeployed_n: int | None = None,
    target_numeric_reads: int = 0,
):
    scores=sorted(list(parent_scores),key=lambda x:str(x.parent_id))
    out=Path(output_dir)
    refuse_existing_output(out)
    full,dep,nondep=_population_counts(full_census_n,deployed_n,nondeployed_n,len(scores))
    out.mkdir(parents=True)
    return _seal_scientific_outputs_prepared(
        scores,out,full_census_n=full,deployed_n=dep,nondeployed_n=nondep,target_numeric_reads=int(target_numeric_reads),
    )


def run_scoring_state(state: PreflightState, output_dir: Path, *, marker_callback=None):
    out=Path(output_dir)
    refuse_existing_output(out)
    _assert_binary_slice_schema(state.development_index,"development")
    _assert_binary_slice_schema(state.target_index,"target")
    if state.target_binary_numeric_reads != 0:
        raise AssertionError("scoring state already contains numeric target reads")
    out.mkdir(parents=True)
    if marker_callback is not None:
        marker_callback()
    scores=score_all_parents(state)
    if state.target_binary_numeric_reads != len(scores):
        raise AssertionError(
            f"successful parent scoring target-read count mismatch: reads={state.target_binary_numeric_reads} scores={len(scores)}"
        )
    return _seal_scientific_outputs_prepared(
        scores,out,
        full_census_n=len(state.full_parent_ids),
        deployed_n=len(state.deployed_parent_ids),
        nondeployed_n=len(state.nondeployed_parent_ids),
        target_numeric_reads=state.target_binary_numeric_reads,
    )


def execute_scoring(
    paths: EntryPaths,
    output_dir: Path,
    *,
    config: EntryGateConfig | None = None,
    marker_callback=None,
):
    out=Path(output_dir)
    refuse_existing_output(out)
    state=verify_entry_gate(paths,config=config)
    if state.target_binary_numeric_reads != 0:
        raise AssertionError("entry gate numerically read target values before scoring")
    _assert_binary_slice_schema(state.development_index,"development")
    _assert_binary_slice_schema(state.target_index,"target")
    return run_scoring_state(state,out,marker_callback=marker_callback)


def _entry_paths_from_args(args) -> EntryPaths:
    missing=[n for n in ("p10","p11a1","p11a2","p11b","r4_evidence") if getattr(args,n,None) is None]
    if missing:
        raise AssertionError(f"preflight requires paths: {','.join(missing)}")
    return EntryPaths(Path(args.p10),Path(args.p11a1),Path(args.p11a2),Path(args.p11b),Path(args.r4_evidence))


def main(argv=None) -> int:
    args=parse_args(argv)
    assert_runtime()
    print(f"P11C_MODE={args.mode.upper()}")
    print("REALBENCH3_TARGET_STATE=PERMANENTLY_OPEN")
    print("P12=LOCKED")
    paths=_entry_paths_from_args(args)
    if args.mode=="preflight":
        state=execute_preflight(paths,Path(args.out))
        print("P11C_ENTRY_GATE=PASS")
        print(f"P11C_FULL_CENSUS_N={len(state.full_parent_ids)}")
        print(f"P11C_DEPLOYED_PARENT_N={len(state.deployed_parent_ids)}")
        print(f"P11C_FROZEN_NONDEPLOYED_N={len(state.nondeployed_parent_ids)}")
        print("P11C_TARGET_INDEX_BINARY_SLICE_SCHEMA_BOUND=TRUE")
        print("P11C_TARGET_BINARY_NUMERIC_VALUES_READ=FALSE")
        print("P11C_SCIENTIFIC_SCORING=FALSE")
        print("P11C_PREFLIGHT_RESULT=PASS")
        return 0
    result=execute_scoring(
        paths,Path(args.out),
        marker_callback=lambda: print("P11C_NUMERIC_TARGET_SCORING_START=TRUE",flush=True),
    )
    print("P11C_ENTRY_GATE=PASS")
    print(f"P11C_OVERALL_STATUS={result['decision'].overall_status}")
    print(f"P11C_RESULT_MANIFEST_SHA256={result['manifest_sha256']}")
    print("SCIENTIFIC_LOCK_CHANGED=FALSE")
    print("P12=LOCKED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
