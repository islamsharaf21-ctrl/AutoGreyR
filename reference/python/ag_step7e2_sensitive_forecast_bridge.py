#!/usr/bin/env python3
"""AutoGrey Step7E2 canonical sensitive-forecast bridge.

Recomputes ONLY selected SG02_DISCRETE_POLY and SG05_CONT_TIME_POLY final
forecasts from already-sealed development-side float64 D values. No target
suffix is read or accepted by this helper.
"""
from __future__ import annotations
import argparse, csv, hashlib, importlib.util, json, sys
from pathlib import Path
import numpy as np

ALLOWED_GROUPS = {"SG02_DISCRETE_POLY", "SG05_CONT_TIME_POLY"}


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def load_engine(path: Path):
    spec = importlib.util.spec_from_file_location("autogrey_engine_step7e2_bridge", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load engine: {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    version = getattr(mod, "ENGINE_VERSION", getattr(mod, "AG_ENGINE_VERSION", None))
    return mod, version


def parse_sg02_config(config_id: str) -> tuple[int, ...]:
    if not config_id.startswith("deg="):
        raise RuntimeError(f"invalid SG02 config_id: {config_id}")
    body = config_id[4:]
    if body == "empty":
        return ()
    vals = tuple(int(x) for x in body.split("."))
    if tuple(sorted(set(vals))) != vals or any(x < 1 or x > 4 for x in vals):
        raise RuntimeError(f"invalid SG02 degrees: {config_id}")
    return vals


def forecast(engine, group: str, config_id: str, D: np.ndarray, h: int) -> np.ndarray:
    if group == "SG02_DISCRETE_POLY":
        out = engine.dgpm_fit_forecast(D, h, parse_sg02_config(config_id))
    elif group == "SG05_CONT_TIME_POLY":
        if config_id.startswith("TP_alpha="):
            alpha = float(config_id.split("=", 1)[1])
            out = engine.timepower_fit_forecast(D, h, alpha)
        elif config_id.startswith("FOTP_order="):
            p = int(config_id.split("=", 1)[1])
            out = engine.fotp_fit_forecast(D, h, p)
        else:
            raise RuntimeError(f"invalid SG05 config_id: {config_id}")
    else:
        raise RuntimeError(f"group not allowed: {group}")
    f = np.asarray(out.forecast, dtype="<f8")
    if f.ndim != 1 or len(f) != h or not np.all(np.isfinite(f)):
        raise RuntimeError(f"invalid forecast: group={group} config={config_id} h={h}")
    return f


def main(requests: Path, d_binary: Path, engine_path: Path, out_index: Path, out_binary: Path):
    engine, engine_version = load_engine(engine_path)
    with requests.open(newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise RuntimeError("empty requests")
    req_ids = [r["request_id"] for r in rows]
    if len(set(req_ids)) != len(req_ids):
        raise RuntimeError("duplicate request_id")
    raw = d_binary.read_bytes()
    if len(raw) % 8:
        raise RuntimeError("development binary is not float64-aligned")
    d_all = np.frombuffer(raw, dtype="<f8")
    out_index.parent.mkdir(parents=True, exist_ok=True)
    offset = 0
    idx = []
    counts = {g: 0 for g in sorted(ALLOWED_GROUPS)}
    with out_binary.open("wb") as bout:
        for r in rows:
            group = r["group"]
            if group not in ALLOWED_GROUPS:
                raise RuntimeError(f"disallowed group: {group}")
            h = int(r["h"]); n_D = int(r["n_D"]); off = int(r["d_offset_bytes"])
            if h < 1 or n_D < 4 or off < 0 or off % 8:
                raise RuntimeError(f"invalid request geometry: {r['request_id']}")
            lo = off // 8; hi = lo + n_D
            if hi > len(d_all):
                raise RuntimeError(f"development bounds: {r['request_id']}")
            D = np.asarray(d_all[lo:hi], dtype=float)
            if len(D) != n_D or not np.all(np.isfinite(D)):
                raise RuntimeError(f"invalid development vector: {r['request_id']}")
            fcast = forecast(engine, group, r["config_id"], D, h)
            b = fcast.astype("<f8", copy=False).tobytes(order="C")
            bout.write(b)
            idx.append({
                "request_id": r["request_id"], "parent_id": r["parent_id"],
                "group": group, "config_id": r["config_id"], "h": h,
                "forecast_offset_bytes": offset, "n_forecast": len(fcast),
                "forecast_sha256": sha256_bytes(b),
            })
            offset += len(b); counts[group] += 1
    with out_index.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["request_id","parent_id","group","config_id","h","forecast_offset_bytes","n_forecast","forecast_sha256"])
        w.writeheader(); w.writerows(idx)
    print(json.dumps({"requests":len(rows),"counts":counts,"forecast_binary_bytes":offset,
                      "numpy":np.__version__,"engine_version":engine_version,
                      "out_index":str(out_index),"out_binary":str(out_binary)},sort_keys=True))

if __name__ == "__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--requests",required=True)
    ap.add_argument("--d-binary",required=True)
    ap.add_argument("--engine",required=True)
    ap.add_argument("--out-index",required=True)
    ap.add_argument("--out-binary",required=True)
    a=ap.parse_args()
    main(Path(a.requests),Path(a.d_binary),Path(a.engine),Path(a.out_index),Path(a.out_binary))
