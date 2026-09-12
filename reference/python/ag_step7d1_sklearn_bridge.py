#!/usr/bin/env python3
"""AutoGrey Step 7D1 canonical sklearn RF bridge.

This helper is intentionally narrow. R owns all upstream feature construction,
mask handling, eligibility bits, and group/fold median preprocessing. This
process receives already-preprocessed finite float64 matrices/vectors through a
byte-stable little-endian binary contract, fits exactly the frozen
RandomForestRegressor from Step 5D-B-R2, and returns deterministic diagnostics.

Scientific design is frozen. Do not edit RF hyperparameters here independently
of the canonical Step 5D-B-R2 source.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import sys
from pathlib import Path
from typing import Any

import numpy as np
import sklearn
from sklearn.ensemble import RandomForestRegressor

VERSION = "AG_STEP7D1_SKLEARN_BRIDGE_1"
EXPECTED_PYTHON = "3.13.5"
EXPECTED_NUMPY = "2.3.5"
EXPECTED_SKLEARN = "1.8.0"
RANDOM_SEED = 62291
N_ESTIMATORS = 500
N_FEATURES = 56


def sha256_file(path: str | Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def env_report() -> dict[str, Any]:
    py = platform.python_version()
    npv = np.__version__
    skv = sklearn.__version__
    return {
        "bridge_version": VERSION,
        "python": py,
        "numpy": npv,
        "scikit_learn": skv,
        "platform": platform.platform(),
        "python_executable": sys.executable,
        "exact_frozen_versions": bool(py == EXPECTED_PYTHON and npv == EXPECTED_NUMPY and skv == EXPECTED_SKLEARN),
        "algorithm_versions_compatible": bool(npv == EXPECTED_NUMPY and skv == EXPECTED_SKLEARN),
        "expected": {
            "python": EXPECTED_PYTHON,
            "numpy": EXPECTED_NUMPY,
            "scikit_learn": EXPECTED_SKLEARN,
        },
    }


def make_model() -> RandomForestRegressor:
    return RandomForestRegressor(
        n_estimators=N_ESTIMATORS,
        criterion="squared_error",
        max_depth=None,
        min_samples_split=2,
        min_samples_leaf=0.01,
        min_weight_fraction_leaf=0.0,
        max_features="sqrt",
        max_leaf_nodes=None,
        min_impurity_decrease=0.0,
        bootstrap=True,
        oob_score=False,
        n_jobs=-1,
        random_state=RANDOM_SEED,
        verbose=0,
        warm_start=False,
        ccp_alpha=0.0,
        max_samples=None,
        monotonic_cst=None,
    )


def contract() -> dict[str, Any]:
    p = make_model().get_params(deep=False)
    # JSON normalization only; no scientific transformation.
    out = {}
    for k, v in p.items():
        if isinstance(v, (str, int, float, bool)) or v is None:
            out[k] = v
        else:
            out[k] = str(v)
    return out


def load_matrix(path: str, nrow: int, ncol: int) -> np.ndarray:
    a = np.fromfile(path, dtype="<f8")
    if a.size != nrow * ncol:
        raise RuntimeError(f"matrix size mismatch for {path}: {a.size} != {nrow*ncol}")
    a = a.reshape((nrow, ncol), order="C")
    if not np.all(np.isfinite(a)):
        raise RuntimeError(f"non-finite matrix input: {path}")
    return a


def load_vector(path: str, n: int) -> np.ndarray:
    a = np.fromfile(path, dtype="<f8")
    if a.size != n:
        raise RuntimeError(f"vector size mismatch for {path}: {a.size} != {n}")
    if not np.all(np.isfinite(a)):
        raise RuntimeError(f"non-finite vector input: {path}")
    return a


def sha_i64(a: np.ndarray) -> str:
    b = np.asarray(a, dtype="<i8").tobytes(order="C")
    return hashlib.sha256(b).hexdigest()


def tree_meta(model: RandomForestRegressor, n: int = 8) -> list[dict[str, Any]]:
    out = []
    for k, t in enumerate(model.estimators_[:n]):
        tr = t.tree_
        out.append({
            "tree_index": int(k),
            "random_state": int(t.random_state),
            "node_count": int(tr.node_count),
            "max_depth": int(tr.max_depth),
            "root_feature": int(tr.feature[0]),
            "root_threshold": float(tr.threshold[0]),
            "root_weighted_n": float(tr.weighted_n_node_samples[0]),
            "root_n_node_samples": int(tr.n_node_samples[0]),
        })
    return out


def fit_predict(req: dict[str, Any]) -> dict[str, Any]:
    env = env_report()
    if not env["algorithm_versions_compatible"]:
        raise RuntimeError(
            "Frozen RF bridge requires numpy==2.3.5 and scikit-learn==1.8.0; "
            f"got numpy={env['numpy']} sklearn={env['scikit_learn']}"
        )

    nr = int(req["n_train"])
    ne = int(req["n_eval"])
    nc = int(req["n_features"])
    if nr < 1 or ne < 1 or nc != N_FEATURES:
        raise RuntimeError(f"invalid dimensions n_train={nr}, n_eval={ne}, n_features={nc}")

    X = load_matrix(req["x_train_path"], nr, nc)
    y = load_vector(req["y_train_path"], nr)
    Xe = load_matrix(req["x_eval_path"], ne, nc)

    weight_path = req.get("weight_train_path")
    w = None if not weight_path else load_vector(weight_path, nr)
    if w is not None and np.any(w < 0):
        raise RuntimeError("sample weights must be nonnegative")

    model = make_model()
    model.fit(X, y, sample_weight=w)
    pred = np.asarray(model.predict(Xe), dtype=float)

    # First trees are diagnostic fingerprints of the canonical implementation.
    n_diag = min(12, len(model.estimators_))
    sample_hashes = [sha_i64(ix) for ix in model.estimators_samples_[:n_diag]]
    pt = []
    for t in model.estimators_[:8]:
        pt.append([float(v) for v in t.predict(Xe[: min(3, ne)])])

    return {
        "status": "PASS",
        "environment": env,
        "contract": contract(),
        "n_train": nr,
        "n_eval": ne,
        "n_features": nc,
        "effective_min_samples_leaf": int(math.ceil(0.01 * nr)),
        "mtry_sqrt": int(math.sqrt(nc)),
        "weighted": bool(w is not None),
        "predictions": [float(v) for v in pred],
        "bootstrap_index_sha256_first12": sample_hashes,
        "tree_meta_first8": tree_meta(model, 8),
        "per_tree_predictions_first8": pt,
        "input_sha256": {
            "x_train": sha256_file(req["x_train_path"]),
            "y_train": sha256_file(req["y_train_path"]),
            "x_eval": sha256_file(req["x_eval_path"]),
            "weight_train": None if w is None else sha256_file(weight_path),
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-env", action="store_true")
    ap.add_argument("--request")
    ap.add_argument("--output")
    args = ap.parse_args()
    if args.check_env:
        print(json.dumps(env_report(), sort_keys=True))
        return 0
    if not args.request or not args.output:
        ap.error("--request and --output are required unless --check-env is used")
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    try:
        out = fit_predict(req)
        Path(args.output).write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return 0
    except Exception as e:
        out = {"status": "FAIL", "error": f"{type(e).__name__}: {e}", "environment": env_report()}
        Path(args.output).write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
