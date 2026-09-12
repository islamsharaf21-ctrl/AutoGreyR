#!/usr/bin/env python3
"""Step 7D1 verifier-only cross-language input comparator.

This helper does not fit a model and does not alter the frozen selector. It
reconstructs the canonical Step5D-B-R2 V1 group/fold inputs directly from the
frozen CSVs with the canonical Python source, then compares them numerically and
by row identity with the R-produced finite float64 inputs.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

import numpy as np

VERSION = "AG_STEP7D1_INPUT_COMPARE_1"


def sha256_file(path: str | Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_matrix(path: str | Path, nrow: int, ncol: int) -> np.ndarray:
    a = np.fromfile(path, dtype="<f8")
    if a.size != nrow * ncol:
        raise RuntimeError(f"matrix size mismatch: {a.size} != {nrow*ncol}")
    return a.reshape((nrow, ncol), order="C")


def load_vector(path: str | Path, n: int) -> np.ndarray:
    a = np.fromfile(path, dtype="<f8")
    if a.size != n:
        raise RuntimeError(f"vector size mismatch: {a.size} != {n}")
    return a


def compare_numeric(a: np.ndarray, b: np.ndarray) -> dict[str, Any]:
    if a.shape != b.shape:
        return {"shape_equal": False, "shape_r": list(a.shape), "shape_python": list(b.shape)}
    d = np.abs(a - b)
    neq = a != b
    return {
        "shape_equal": True,
        "shape_r": list(a.shape),
        "shape_python": list(b.shape),
        "exact_equal": bool(np.array_equal(a, b)),
        "n_nonexact": int(np.count_nonzero(neq)),
        "max_abs": float(np.max(d)) if d.size else 0.0,
        "mean_abs": float(np.mean(d)) if d.size else 0.0,
        "all_finite_r": bool(np.all(np.isfinite(a))),
        "all_finite_python": bool(np.all(np.isfinite(b))),
    }


def import_selector(path: Path):
    spec = importlib.util.spec_from_file_location("autogrey_step5db_r2_for_compare", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import selector source: {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def compare(req: dict[str, Any]) -> dict[str, Any]:
    selector_path = Path(req["selector_path"])
    frozen_dir = Path(req["frozen_dir"])
    mod = import_selector(selector_path)
    records, parents, parent_to_rows, parent_meta, _, _ = mod.load_train(frozen_dir)
    arr = mod.records_to_arrays(records)

    group = str(req["group"])
    fold = int(req["fold"])
    parent = str(req["parent_id"])
    gi = mod.GROUP_INDEX[group]

    tr_all = np.flatnonzero(arr["fold"] != fold)
    tr = tr_all[arr["group_idx"][tr_all] == gi]
    ei = np.asarray([i for i, r in enumerate(records) if r["parent_id"] == parent and r["group"] == group], dtype=int)
    if ei.size != int(req["n_eval"]):
        raise RuntimeError(f"canonical eval row count mismatch: {ei.size} != {req['n_eval']}")
    Xtr_py, Xev_py, med_py = mod.fit_medians_and_transform(arr["X_v1"][tr], arr["X_v1"][ei])
    y_py = arr["target"][tr]
    w_py = arr["weight"][tr]

    nr = int(req["n_train"]); ne = int(req["n_eval"]); nc = int(req["n_features"])
    Xtr_r = load_matrix(req["x_train_path"], nr, nc)
    Xev_r = load_matrix(req["x_eval_path"], ne, nc)
    y_r = load_vector(req["y_train_path"], nr)
    w_r = load_vector(req["weight_train_path"], nr)
    med_r = load_vector(req["medians_path"], nc)

    r_parent_ids = Path(req["train_parent_ids_path"]).read_text(encoding="utf-8").splitlines()
    py_parent_ids = [records[int(i)]["parent_id"] for i in tr]
    order_equal = r_parent_ids == py_parent_ids
    first_order_mismatch = None
    if not order_equal:
        lim = min(len(r_parent_ids), len(py_parent_ids))
        for k in range(lim):
            if r_parent_ids[k] != py_parent_ids[k]:
                first_order_mismatch = {"index_0based": k, "r": r_parent_ids[k], "python": py_parent_ids[k]}
                break
        if first_order_mismatch is None and len(r_parent_ids) != len(py_parent_ids):
            first_order_mismatch = {"index_0based": lim, "r_len": len(r_parent_ids), "python_len": len(py_parent_ids)}

    return {
        "status": "PASS",
        "version": VERSION,
        "group": group,
        "fold": fold,
        "parent_id": parent,
        "canonical_n_train": int(tr.size),
        "canonical_n_eval": int(ei.size),
        "row_order_exact": bool(order_equal),
        "first_row_order_mismatch": first_order_mismatch,
        "x_train": {**compare_numeric(Xtr_r, Xtr_py), "r_sha256": sha256_file(req["x_train_path"]), "python_sha256": hashlib.sha256(np.asarray(Xtr_py, dtype="<f8").tobytes(order="C")).hexdigest()},
        "x_eval": {**compare_numeric(Xev_r, Xev_py), "r_sha256": sha256_file(req["x_eval_path"]), "python_sha256": hashlib.sha256(np.asarray(Xev_py, dtype="<f8").tobytes(order="C")).hexdigest()},
        "y_train": {**compare_numeric(y_r, y_py), "r_sha256": sha256_file(req["y_train_path"]), "python_sha256": hashlib.sha256(np.asarray(y_py, dtype="<f8").tobytes(order="C")).hexdigest()},
        "weight_train": {**compare_numeric(w_r, w_py), "r_sha256": sha256_file(req["weight_train_path"]), "python_sha256": hashlib.sha256(np.asarray(w_py, dtype="<f8").tobytes(order="C")).hexdigest()},
        "medians": {**compare_numeric(med_r, med_py), "python_sha256": hashlib.sha256(np.asarray(med_py, dtype="<f8").tobytes(order="C")).hexdigest()},
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    try:
        req = json.loads(Path(args.request).read_text(encoding="utf-8"))
        out = compare(req)
        Path(args.output).write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return 0
    except Exception as e:
        Path(args.output).write_text(json.dumps({"status": "FAIL", "error": f"{type(e).__name__}: {e}"}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
