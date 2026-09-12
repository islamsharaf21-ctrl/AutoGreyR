#!/usr/bin/env python3
"""
AutoGrey v2 Step 5D-B-R2 — reproducible TRAIN-only selector search.

Scientific boundary:
- Reads only the frozen Step 5D-A target-free action table, TRAIN labels,
  TRAIN/CAL/LOCKTEST split ledger (for hash/provenance only), and Step 5C design.
- Immediately filters the action table to V2_TRAIN before constructing model data.
- Never reads CAL outcomes, LOCKTEST outcomes, or REAL_BENCH-2.
- Implements the unchanged Step 5C 66-candidate search with explicit R2
  implementation conventions frozen in AUTOGREY_V2_5DB_R2_PREEXEC_LOCK.json.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import platform
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Tuple

import numpy as np
import sklearn
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor

VERSION = "AG_V2_SEARCH_5DB_R2_1"
RANDOM_SEED = 62291
N_ESTIMATORS_ACTION = 400
N_ESTIMATORS_V1 = 500
MAX_FEATURES = "sqrt"
ACTION_SUPPORT_POOLED = 30
ACTION_SUPPORT_BY_H = 20
V1_SUPPORT_MIN_PARENTS = 20  # nonbinding in all frozen TRAIN folds
COVERAGE_FLOOR = 0.995
NEAR_TIE_J = 0.01
NUMERIC_TIE_TOL = 1e-12
GROUPS = [
    "SG01_CONT_GM",
    "SG02_DISCRETE_POLY",
    "SG03_FRAC_LINEAR",
    "SG04_BERNOULLI",
    "SG05_CONT_TIME_POLY",
    "SG06_CONFORMABLE",
    "SG07_ROLLING",
    "SG08_WBO",
    "SG09_GREY_MARKOV",
    "SG10_SEASONAL",
]
GROUP_INDEX = {g: i for i, g in enumerate(GROUPS)}
HORIZONS = [1, 3, 5]

BASE_TASK = [
    "trend_r2",
    "quadratic_gain",
    "up_step_fraction",
    "curvature_sign",
    "cv_abs",
    "range_rel",
    "smoothness",
    "outlier_fraction_tukey",
    "acf1",
    "acf2",
    "diff_skewness",
    "log_n",
    "horizon_ratio",
]
MECHANISM = [
    "ago_linearity_r2",
    "class_ratio_pass_rate",
    "class_ratio_max_log_violation",
    "mean_log_growth",
    "log_growth_delta",
    "recent_slope_shift",
    "wbo_distortion",
    "gm_background_sensitivity",
    "gm_residual_acf1",
    "seasonal_factor_amplitude",
]
ALL_V1_FEATURES = [
    "trend_r2",
    "quadratic_gain",
    "up_step_fraction",
    "curvature_sign",
    "cv_abs",
    "range_rel",
    "smoothness",
    "outlier_fraction_tukey",
    "acf1",
    "acf2",
    "diff_skewness",
    "ago_linearity_r2",
    "class_ratio_pass_rate",
    "class_ratio_max_log_violation",
    "mean_log_growth",
    "log_growth_delta",
    "recent_slope_shift",
    "wbo_distortion",
    "gm_background_sensitivity",
    "gm_residual_acf1",
    "seasonal_factor_amplitude",
    "log_n",
    "horizon_ratio",
]
RISK = [
    "inner_mean_log",
    "inner_max_log",
    "inner_sd_log",
    "inner_worst_gap_log",
    "forecast_level_ratio_log",
    "first_jump_ratio_log",
    "max_path_jump_ratio_log",
    "forecast_range_ratio_log",
    "forecast_slope_ratio_log",
    "peer_min_distance_log",
    "peer_median_distance_log",
    "valid_config_fraction",
]

EXPECTED_HASHES = {
    "AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv": "5e943ce10c601187d46dd0f77e9059aee29c7e2710d1d8ff5acf779787983a99",
    "AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv": "77e202112c8d3de45aeebfdbe6a4c8d1ac9b725aac598af5974d46a3f5be4631",
    "AUTOGREY_V2_TASK_SPLIT_STEP5D_A.csv": "92670cd0ba8544d9f0402e27a07078f2a743f1a28ad821710bdcdc0f66c002d9",
    "AUTOGREY_V2_DESIGN_STEP5C.json": "05fd0693ef5186e56255f2724b541e5019223867a414be406b7e7fcce3f9cb07",
    "AUTOGREY_V2_SPEC_STEP5C.md": "6534f20a04d8c07cb6156b42486d42315f992ca7256fbf955282d08cd9f6fb63",
}

OUTPUT_NAMES = {
    "architecture": "AUTOGREY_V2_ARCHITECTURE_RESULTS_STEP5D_B_R2.csv",
    "summary": "AUTOGREY_V2_SEARCH_SUMMARY_STEP5D_B_R2.json",
    "selected": "AUTOGREY_V2_SELECTED_OOF_STEP5D_B_R2.json",
    "global": "AUTOGREY_V2_GLOBAL_OOF_STEP5D_B_R2.json",
    "v1": "AUTOGREY_V2_V1STYLE_OOF_STEP5D_B_R2.json",
    "assertions": "AUTOGREY_V2_SEARCH_ASSERTIONS_STEP5D_B_R2.json",
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def stable_json_dump(obj: Any, path: Path) -> None:
    path.write_text(
        json.dumps(obj, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def as_float(s: str) -> float:
    try:
        x = float(s)
        return x if math.isfinite(x) else math.nan
    except Exception:
        return math.nan


def as_int(s: str) -> int:
    return int(float(s))


def weighted_quantile_no_interp(values: np.ndarray, weights: np.ndarray, q: float) -> float:
    values = np.asarray(values, dtype=float)
    weights = np.asarray(weights, dtype=float)
    ok = np.isfinite(values) & np.isfinite(weights) & (weights > 0)
    if not np.any(ok):
        raise ValueError("weighted quantile has no positive finite weights")
    v = values[ok]
    w = weights[ok]
    order = np.argsort(v, kind="mergesort")
    v = v[order]
    w = w[order]
    target = q * float(np.sum(w))
    cum = np.cumsum(w)
    idx = int(np.searchsorted(cum, target, side="left"))
    idx = min(max(idx, 0), len(v) - 1)
    return float(v[idx])


def cvar90_worst_decile(regrets: Sequence[float]) -> float:
    a = np.asarray(list(regrets), dtype=float)
    if a.size == 0:
        return math.nan
    k = int(math.ceil(0.10 * a.size))
    return float(np.mean(np.sort(a)[-k:]))


def metrics_from_decisions(decisions: Sequence[Mapping[str, Any]], n_tasks: int) -> Dict[str, Any]:
    supported = [d for d in decisions if int(d["supported"]) == 1]
    reg = np.asarray([float(d["regret"]) for d in supported], dtype=float)
    counts = Counter(str(d["choice"]) for d in supported)
    if len(reg) == 0:
        return {
            "n_tasks": int(n_tasks),
            "n_supported": 0,
            "support_coverage": 0.0,
            "mean_regret": None,
            "median_regret": None,
            "cvar90": None,
            "p90_regret": None,
            "zero_regret_rate": None,
            "selection_counts": {},
        }
    return {
        "n_tasks": int(n_tasks),
        "n_supported": int(len(reg)),
        "support_coverage": float(len(reg) / n_tasks),
        "mean_regret": float(np.mean(reg)),
        "median_regret": float(np.median(reg)),
        "cvar90": cvar90_worst_decile(reg),
        "p90_regret": float(np.quantile(reg, 0.90, method="linear")),
        "zero_regret_rate": float(np.mean(reg <= 1e-15)),
        "selection_counts": {g: int(counts[g]) for g in GROUPS if counts[g] > 0},
    }


def fit_medians_and_transform(X_train: np.ndarray, X_eval: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    X_train = np.asarray(X_train, dtype=float)
    X_eval = np.asarray(X_eval, dtype=float)
    med = np.empty(X_train.shape[1], dtype=float)
    for j in range(X_train.shape[1]):
        col = X_train[:, j]
        good = np.isfinite(col)
        med[j] = float(np.median(col[good])) if np.any(good) else 0.0
    tr = X_train.copy()
    ev = X_eval.copy()
    ti = ~np.isfinite(tr)
    ei = ~np.isfinite(ev)
    if np.any(ti):
        tr[ti] = np.take(med, np.nonzero(ti)[1])
    if np.any(ei):
        ev[ei] = np.take(med, np.nonzero(ei)[1])
    return tr, ev, med


def make_rf_regressor(n_estimators: int, max_depth: int | None, min_samples_leaf: float) -> RandomForestRegressor:
    return RandomForestRegressor(
        n_estimators=n_estimators,
        criterion="squared_error",
        max_depth=max_depth,
        min_samples_split=2,
        min_samples_leaf=min_samples_leaf,
        min_weight_fraction_leaf=0.0,
        max_features=MAX_FEATURES,
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


def make_rf_classifier(max_depth: int | None, min_samples_leaf: float) -> RandomForestClassifier:
    return RandomForestClassifier(
        n_estimators=N_ESTIMATORS_ACTION,
        criterion="gini",
        max_depth=max_depth,
        min_samples_split=2,
        min_samples_leaf=min_samples_leaf,
        min_weight_fraction_leaf=0.0,
        max_features=MAX_FEATURES,
        max_leaf_nodes=None,
        min_impurity_decrease=0.0,
        bootstrap=True,
        oob_score=False,
        n_jobs=-1,
        random_state=RANDOM_SEED,
        verbose=0,
        warm_start=False,
        class_weight=None,
        ccp_alpha=0.0,
        max_samples=None,
        monotonic_cst=None,
    )


def _valid(row: Mapping[str, str], key: str) -> bool:
    try:
        return int(float(row[key])) == 1
    except Exception:
        return False


def _masked_value(row: Mapping[str, str], value_key: str, valid_key: str) -> float:
    if not _valid(row, valid_key):
        return math.nan
    return as_float(row[value_key])


def build_action_features(row: Mapping[str, str], full: bool) -> List[float]:
    vals: List[float] = []
    # Exact R2 order: task values, task masks; optional mechanism values/masks;
    # action-risk values, action-risk masks; group one-hot; eligibility bits;
    # eligible_count; h one-hot; log1p(M), valid_M.
    for name in BASE_TASK:
        vals.append(_masked_value(row, f"feat__{name}", f"valid__{name}"))
    for name in BASE_TASK:
        vals.append(1.0 if _valid(row, f"valid__{name}") else 0.0)
    if full:
        for name in MECHANISM:
            vals.append(_masked_value(row, f"feat__{name}", f"valid__{name}"))
        for name in MECHANISM:
            vals.append(1.0 if _valid(row, f"valid__{name}") else 0.0)
    for name in RISK:
        vals.append(_masked_value(row, f"risk__{name}", f"valid_risk__{name}"))
    for name in RISK:
        vals.append(1.0 if _valid(row, f"valid_risk__{name}") else 0.0)
    for g in GROUPS:
        vals.append(float(as_int(row[f"group__{g}"])))
    for g in GROUPS:
        vals.append(float(as_int(row[f"elig__{g}"])))
    vals.append(float(as_int(row["eligible_count"])))
    vals.extend([
        float(as_int(row["context__h1"])),
        float(as_int(row["context__h3"])),
        float(as_int(row["context__h5"])),
    ])
    vals.append(_masked_value(row, "context__log1p_M", "context__valid_M"))
    vals.append(1.0 if _valid(row, "context__valid_M") else 0.0)
    return vals


def build_v1_features(row: Mapping[str, str]) -> List[float]:
    vals: List[float] = []
    for name in ALL_V1_FEATURES:
        vals.append(_masked_value(row, f"feat__{name}", f"valid__{name}"))
    for name in ALL_V1_FEATURES:
        vals.append(1.0 if _valid(row, f"valid__{name}") else 0.0)
    for g in GROUPS:
        vals.append(float(as_int(row[f"elig__{g}"])))
    return vals


def verify_inputs(input_dir: Path) -> Dict[str, str]:
    got: Dict[str, str] = {}
    for name, expected in EXPECTED_HASHES.items():
        p = input_dir / name
        if not p.is_file():
            raise FileNotFoundError(f"required frozen input missing: {p}")
        digest = sha256_file(p)
        if digest != expected:
            raise RuntimeError(f"hash mismatch for {name}: {digest} != {expected}")
        got[name] = digest
    return got


def load_train(input_dir: Path):
    label_path = input_dir / "AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv"
    action_path = input_dir / "AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv"

    labels: Dict[str, Dict[str, str]] = {}
    with label_path.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            key = row["selector_row_hash"]
            if key in labels:
                raise RuntimeError(f"duplicate TRAIN label selector_row_hash: {key}")
            labels[key] = row

    records = []
    seen_hashes = set()
    all_action_rows = 0
    nontrain_action_rows = 0
    with action_path.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            all_action_rows += 1
            if row["v2_split"] != "V2_TRAIN":
                nontrain_action_rows += 1
                continue
            key = row["selector_row_hash"]
            lab = labels.get(key)
            if lab is None:
                raise RuntimeError(f"TRAIN action row has no frozen TRAIN label: {key}")
            seen_hashes.add(key)
            if row["parent_id"] != lab["parent_id"] or row["action_group"] != lab["action_group"]:
                raise RuntimeError("action/label join identity mismatch")
            if as_int(row["h"]) != as_int(lab["h"]):
                raise RuntimeError("action/label horizon mismatch")
            if as_int(row["train_cv_fold"]) != as_int(lab["train_cv_fold"]):
                raise RuntimeError("action/label fold mismatch")
            wa = as_float(row["action_row_weight"])
            wl = as_float(lab["action_row_weight"])
            if not math.isclose(wa, wl, rel_tol=0.0, abs_tol=1e-15):
                raise RuntimeError("action/label weight mismatch")
            regret = as_float(lab["eligible_regret"])
            target = as_float(lab["target_log1p_regret"])
            if not (math.isfinite(regret) and regret >= -1e-12):
                raise RuntimeError("invalid TRAIN regret")
            regret = max(0.0, regret)
            if not math.isclose(target, math.log1p(regret), rel_tol=1e-10, abs_tol=1e-10):
                raise RuntimeError("TRAIN target_log1p_regret mismatch")
            rec = {
                "parent_id": row["parent_id"],
                "task_id": row["task_id"],
                "source_class": row["source_class"],
                "h": as_int(row["h"]),
                "fold": as_int(row["train_cv_fold"]),
                "group": row["action_group"],
                "group_idx": GROUP_INDEX[row["action_group"]],
                "weight": wa,
                "regret": regret,
                "target": target,
                "x_base": build_action_features(row, full=False),
                "x_full": build_action_features(row, full=True),
                "x_v1": build_v1_features(row),
            }
            records.append(rec)
    if seen_hashes != set(labels):
        missing = sorted(set(labels) - seen_hashes)
        raise RuntimeError(f"frozen TRAIN labels not all joined; missing={len(missing)}")
    if len(records) != 18107 or len(labels) != 18107:
        raise RuntimeError(f"expected 18107 TRAIN action/label rows, got {len(records)}/{len(labels)}")

    # Canonical deterministic row order independent of CSV writer details.
    records.sort(key=lambda r: (r["parent_id"], r["group_idx"]))
    parents = sorted({r["parent_id"] for r in records})
    if len(parents) != 2070:
        raise RuntimeError(f"expected 2070 actionable TRAIN parents, got {len(parents)}")
    parent_to_rows: Dict[str, List[int]] = defaultdict(list)
    parent_meta: Dict[str, Dict[str, Any]] = {}
    for i, r in enumerate(records):
        parent_to_rows[r["parent_id"]].append(i)
        parent_meta[r["parent_id"]] = {
            "fold": r["fold"], "h": r["h"], "source_class": r["source_class"]
        }
    for p, idxs in parent_to_rows.items():
        folds = {records[i]["fold"] for i in idxs}
        hs = {records[i]["h"] for i in idxs}
        if len(folds) != 1 or len(hs) != 1:
            raise RuntimeError(f"parent {p} spans folds or horizons")
        wsum = sum(records[i]["weight"] for i in idxs)
        if not math.isclose(wsum, 1.0, rel_tol=0.0, abs_tol=5e-12):
            raise RuntimeError(f"parent weights do not sum to 1: {p} -> {wsum}")
    return records, parents, parent_to_rows, parent_meta, all_action_rows, nontrain_action_rows


def records_to_arrays(records):
    return {
        "parent": np.asarray([r["parent_id"] for r in records], dtype=object),
        "fold": np.asarray([r["fold"] for r in records], dtype=int),
        "h": np.asarray([r["h"] for r in records], dtype=int),
        "group_idx": np.asarray([r["group_idx"] for r in records], dtype=int),
        "weight": np.asarray([r["weight"] for r in records], dtype=float),
        "regret": np.asarray([r["regret"] for r in records], dtype=float),
        "target": np.asarray([r["target"] for r in records], dtype=float),
        "X_base": np.asarray([r["x_base"] for r in records], dtype=float),
        "X_full": np.asarray([r["x_full"] for r in records], dtype=float),
        "X_v1": np.asarray([r["x_v1"] for r in records], dtype=float),
    }


def group_parent_counts(indices: np.ndarray, arr: Mapping[str, np.ndarray], by_h: bool = False):
    sets: Dict[Any, set] = defaultdict(set)
    for i in indices:
        key = (int(arr["group_idx"][i]), int(arr["h"][i])) if by_h else int(arr["group_idx"][i])
        sets[key].add(str(arr["parent"][i]))
    return {k: len(v) for k, v in sets.items()}


def build_global_oof(records, parents, parent_to_rows, arr):
    decisions = []
    for fold in range(5):
        tr = np.flatnonzero(arr["fold"] != fold)
        va_parents = [p for p in parents if records[parent_to_rows[p][0]]["fold"] == fold]
        counts = group_parent_counts(tr, arr, by_h=False)
        means: Dict[int, float] = {}
        for gi in range(len(GROUPS)):
            ix = tr[arr["group_idx"][tr] == gi]
            if counts.get(gi, 0) < ACTION_SUPPORT_POOLED or ix.size == 0:
                continue
            means[gi] = float(np.average(arr["regret"][ix], weights=arr["weight"][ix]))
        for p in va_parents:
            idxs = parent_to_rows[p]
            all_supported = all(records[i]["group_idx"] in means for i in idxs)
            if not all_supported:
                decisions.append({"parent_id": p, "fold": fold, "supported": 0, "choice": None, "regret": None})
                continue
            best = min(idxs, key=lambda i: (means[records[i]["group_idx"]], records[i]["group_idx"]))
            decisions.append({
                "parent_id": p, "fold": fold, "supported": 1,
                "choice": records[best]["group"], "regret": float(records[best]["regret"]),
            })
    decisions.sort(key=lambda d: d["parent_id"])
    return decisions, metrics_from_decisions(decisions, len(parents))


def build_v1_oof(records, parents, parent_to_rows, arr):
    decisions = []
    for fold in range(5):
        tr_all = np.flatnonzero(arr["fold"] != fold)
        counts = group_parent_counts(tr_all, arr, by_h=False)
        models: Dict[int, Tuple[RandomForestRegressor, np.ndarray]] = {}
        for gi in range(len(GROUPS)):
            tr = tr_all[arr["group_idx"][tr_all] == gi]
            if counts.get(gi, 0) < V1_SUPPORT_MIN_PARENTS or tr.size == 0:
                continue
            Xtr, _, med = fit_medians_and_transform(arr["X_v1"][tr], arr["X_v1"][tr][:1])
            model = make_rf_regressor(N_ESTIMATORS_V1, None, 0.01)
            model.fit(Xtr, arr["target"][tr], sample_weight=arr["weight"][tr])
            models[gi] = (model, med)
        va_parents = [p for p in parents if records[parent_to_rows[p][0]]["fold"] == fold]
        # Predict per parent/action with each group's own preprocessor/model.
        for p in va_parents:
            idxs = parent_to_rows[p]
            all_supported = all(records[i]["group_idx"] in models for i in idxs)
            if not all_supported:
                decisions.append({"parent_id": p, "fold": fold, "supported": 0, "choice": None, "regret": None})
                continue
            scored = []
            for i in idxs:
                gi = records[i]["group_idx"]
                model, med = models[gi]
                x = arr["X_v1"][i:i+1].copy()
                bad = ~np.isfinite(x)
                if np.any(bad):
                    x[bad] = np.take(med, np.nonzero(bad)[1])
                pred = float(model.predict(x)[0])
                scored.append((pred, gi, i))
            _, _, best = min(scored, key=lambda t: (t[0], t[1]))
            decisions.append({
                "parent_id": p, "fold": fold, "supported": 1,
                "choice": records[best]["group"], "regret": float(records[best]["regret"]),
            })
    decisions.sort(key=lambda d: d["parent_id"])
    return decisions, metrics_from_decisions(decisions, len(parents))


def p_bad_from_model(model: RandomForestClassifier | None, constant: float | None, X: np.ndarray) -> np.ndarray:
    if model is None:
        assert constant is not None
        return np.full(X.shape[0], float(constant), dtype=float)
    proba = model.predict_proba(X)
    classes = list(model.classes_)
    if 1 in classes:
        return proba[:, classes.index(1)].astype(float)
    return np.zeros(X.shape[0], dtype=float)


def fit_action_base_oof(records, parents, parent_to_rows, arr, feature_mode: str,
                        horizon_mode: str, max_depth: int | None, min_leaf: float):
    Xall = arr["X_full"] if feature_mode == "FULL_RISK" else arr["X_base"]
    mu = np.full(len(records), np.nan, dtype=float)
    pbad = np.full(len(records), np.nan, dtype=float)
    tau_row = np.full(len(records), np.nan, dtype=float)
    row_supported = np.zeros(len(records), dtype=bool)

    for fold in range(5):
        tr_fold = np.flatnonzero(arr["fold"] != fold)
        va_fold = np.flatnonzero(arr["fold"] == fold)
        # Frozen tau_h is always training-fold + horizon specific, regardless of pooled/BY_H head mode.
        tau_h: Dict[int, float] = {}
        for h in HORIZONS:
            ixh = tr_fold[arr["h"][tr_fold] == h]
            tau_h[h] = weighted_quantile_no_interp(arr["regret"][ixh], arr["weight"][ixh], 0.90)

        if horizon_mode == "POOLED":
            support_counts = group_parent_counts(tr_fold, arr, by_h=False)
            supported_keys = {gi for gi, n in support_counts.items() if n >= ACTION_SUPPORT_POOLED}
            Xtr, Xva, _ = fit_medians_and_transform(Xall[tr_fold], Xall[va_fold])
            ybad = np.asarray([1 if arr["regret"][i] > tau_h[int(arr["h"][i])] else 0 for i in tr_fold], dtype=int)
            reg = make_rf_regressor(N_ESTIMATORS_ACTION, max_depth, min_leaf)
            reg.fit(Xtr, arr["target"][tr_fold], sample_weight=arr["weight"][tr_fold])
            if len(np.unique(ybad)) == 1:
                clf = None
                const = float(ybad[0])
            else:
                clf = make_rf_classifier(max_depth, min_leaf)
                clf.fit(Xtr, ybad, sample_weight=arr["weight"][tr_fold])
                const = None
            mu[va_fold] = reg.predict(Xva)
            pbad[va_fold] = p_bad_from_model(clf, const, Xva)
            for local, i in enumerate(va_fold):
                h = int(arr["h"][i]); gi = int(arr["group_idx"][i])
                tau_row[i] = tau_h[h]
                row_supported[i] = gi in supported_keys
        elif horizon_mode == "BY_H":
            support_counts = group_parent_counts(tr_fold, arr, by_h=True)
            supported_keys = {key for key, n in support_counts.items() if n >= ACTION_SUPPORT_BY_H}
            for h in HORIZONS:
                tr = tr_fold[arr["h"][tr_fold] == h]
                va = va_fold[arr["h"][va_fold] == h]
                if va.size == 0:
                    continue
                Xtr, Xva, _ = fit_medians_and_transform(Xall[tr], Xall[va])
                ybad = (arr["regret"][tr] > tau_h[h]).astype(int)
                reg = make_rf_regressor(N_ESTIMATORS_ACTION, max_depth, min_leaf)
                reg.fit(Xtr, arr["target"][tr], sample_weight=arr["weight"][tr])
                if len(np.unique(ybad)) == 1:
                    clf = None
                    const = float(ybad[0])
                else:
                    clf = make_rf_classifier(max_depth, min_leaf)
                    clf.fit(Xtr, ybad, sample_weight=arr["weight"][tr])
                    const = None
                mu[va] = reg.predict(Xva)
                pbad[va] = p_bad_from_model(clf, const, Xva)
                for i in va:
                    gi = int(arr["group_idx"][i])
                    tau_row[i] = tau_h[h]
                    row_supported[i] = (gi, h) in supported_keys
        else:
            raise ValueError(horizon_mode)

    if not (np.all(np.isfinite(mu)) and np.all(np.isfinite(pbad)) and np.all(np.isfinite(tau_row))):
        raise RuntimeError("ACTION_RF OOF predictions contain nonfinite values")
    return mu, pbad, tau_row, row_supported


def action_decisions_for_lambda(records, parents, parent_to_rows, mu, pbad, tau_row, row_supported, lam: float):
    score = mu + float(lam) * np.log1p(tau_row) * pbad
    decisions = []
    for p in parents:
        idxs = parent_to_rows[p]
        fold = records[idxs[0]]["fold"]
        if not all(bool(row_supported[i]) for i in idxs):
            decisions.append({"parent_id": p, "fold": fold, "supported": 0, "choice": None, "regret": None})
            continue
        best = min(idxs, key=lambda i: (float(score[i]), records[i]["group_idx"]))
        decisions.append({
            "parent_id": p, "fold": fold, "supported": 1,
            "choice": records[best]["group"], "regret": float(records[best]["regret"]),
        })
    decisions.sort(key=lambda d: d["parent_id"])
    return decisions, metrics_from_decisions(decisions, len(parents))


def add_relative_metrics(metrics: Dict[str, Any], global_by_parent: Mapping[str, Mapping[str, Any]], decisions):
    supported_ids = [d["parent_id"] for d in decisions if int(d["supported"]) == 1]
    g_reg = [float(global_by_parent[p]["regret"]) for p in supported_ids if int(global_by_parent[p]["supported"]) == 1]
    if len(g_reg) != len(supported_ids):
        raise RuntimeError("GLOBAL_RANK_V2 does not cover all candidate-supported tasks")
    gmean = float(np.mean(g_reg))
    gcvar = cvar90_worst_decile(g_reg)
    metrics["global_same_tasks_mean_regret"] = gmean
    metrics["global_same_tasks_cvar90"] = gcvar
    metrics["rho_mean"] = float(metrics["mean_regret"] / gmean)
    metrics["rho_tail"] = float(metrics["cvar90"] / gcvar)
    metrics["J"] = float(max(metrics["rho_mean"], metrics["rho_tail"]))
    return metrics


def action_simplicity(c: Mapping[str, Any]) -> Tuple:
    # Only used after coverage, J near-set, and minimum rho_mean.
    if c["architecture"] == "GLOBAL_RANK_V2":
        return (0, 0, 0, 0, 0, 0)
    if c["architecture"] == "V1_STYLE_RF_REGRET":
        return (1, 0, 0, 0, 0, 0)
    return (
        2,
        0 if c["feature_mode"] == "BASE_RISK" else 1,
        0 if c["horizon_mode"] == "POOLED" else 1,
        float(c["tail_lambda"]),
        0 if c["max_depth"] == 8 else 1,
        0 if math.isclose(float(c["min_samples_leaf"]), 0.03) else 1,
    )


def select_winner(candidates: List[Dict[str, Any]]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    eligible = [c for c in candidates if float(c["support_coverage"]) >= COVERAGE_FLOOR]
    if not eligible:
        raise RuntimeError("no candidate clears structural support coverage floor")
    min_j = min(float(c["J"]) for c in eligible)
    near = [c for c in eligible if float(c["J"]) <= min_j + NEAR_TIE_J + NUMERIC_TIE_TOL]
    min_rho_mean = min(float(c["rho_mean"]) for c in near)
    mean_best = [c for c in near if abs(float(c["rho_mean"]) - min_rho_mean) <= NUMERIC_TIE_TOL]
    winner = min(mean_best, key=lambda c: (action_simplicity(c), c["candidate_id"]))
    hierarchy = {
        "coverage_floor": COVERAGE_FLOOR,
        "min_J": float(min_j),
        "J_near_tie_band": NEAR_TIE_J,
        "near_tie_count": len(near),
        "near_tie_candidates": [
            {k: c.get(k) for k in ["candidate_id", "architecture", "feature_mode", "horizon_mode", "max_depth", "min_samples_leaf", "tail_lambda", "rho_mean", "rho_tail", "J"]}
            for c in sorted(near, key=lambda x: x["candidate_id"])
        ],
        "winner_reason": "Minimum J defines near set; minimum rho_mean inside near set; frozen simplicity order only for numerical ties.",
    }
    return winner, hierarchy


def subgroup_summary(decisions, parent_meta, field: str):
    buckets: Dict[str, List[float]] = defaultdict(list)
    for d in decisions:
        if int(d["supported"]) != 1:
            continue
        key = str(parent_meta[d["parent_id"]][field])
        buckets[key].append(float(d["regret"]))
    out = {}
    for key in sorted(buckets):
        vals = buckets[key]
        out[key] = {
            "n": len(vals),
            "mean_regret": float(np.mean(vals)),
            "cvar90": cvar90_worst_decile(vals),
            "median_regret": float(np.median(vals)),
        }
    return out


def write_architecture_csv(candidates: List[Dict[str, Any]], path: Path):
    fields = [
        "candidate_id", "architecture", "feature_mode", "horizon_mode", "max_depth",
        "min_samples_leaf", "tail_lambda", "support_coverage", "n_supported", "n_tasks",
        "mean_regret", "median_regret", "p90_regret", "cvar90", "zero_regret_rate",
        "global_same_tasks_mean_regret", "global_same_tasks_cvar90", "rho_mean", "rho_tail", "J",
        "selected",
    ]
    rows = sorted(candidates, key=lambda c: (float(c["J"]), c["candidate_id"]))
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        for c in rows:
            w.writerow({k: c.get(k, "") for k in fields})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-dir", required=True)
    ap.add_argument("--output-dir", required=True)
    ap.add_argument("--validate-only", action="store_true")
    args = ap.parse_args()
    input_dir = Path(args.input_dir).resolve()
    output_dir = Path(args.output_dir).resolve()

    # Static/operational guard: only the canonical recovery input directory is accepted by hash.
    input_hashes = verify_inputs(input_dir)
    records, parents, parent_to_rows, parent_meta, all_action_rows, nontrain_action_rows = load_train(input_dir)
    arr = records_to_arrays(records)

    validation = {
        "version": VERSION,
        "input_hashes": input_hashes,
        "all_action_table_rows_seen_by_csv_parser": all_action_rows,
        "nontrain_action_rows_skipped_before_model_data_construction": nontrain_action_rows,
        "train_action_rows": len(records),
        "train_actionable_parents": len(parents),
        "feature_widths": {
            "BASE_RISK": int(arr["X_base"].shape[1]),
            "FULL_RISK": int(arr["X_full"].shape[1]),
            "V1_STYLE": int(arr["X_v1"].shape[1]),
        },
        "fold_parent_counts": {str(f): sum(1 for p in parents if parent_meta[p]["fold"] == f) for f in range(5)},
        "environment": {
            "python": sys.version.split()[0],
            "numpy": np.__version__,
            "scikit_learn": sklearn.__version__,
            "platform": platform.platform(),
        },
    }
    if args.validate_only:
        print(json.dumps(validation, indent=2, sort_keys=True))
        return 0

    output_dir.mkdir(parents=True, exist_ok=True)

    # 1) GLOBAL_RANK_V2 — TRAIN-fold-only ranking.
    global_decisions, global_metrics = build_global_oof(records, parents, parent_to_rows, arr)
    global_by_parent = {d["parent_id"]: d for d in global_decisions}
    global_candidate = {
        "candidate_id": "GLOBAL_RANK_V2",
        "architecture": "GLOBAL_RANK_V2",
        "feature_mode": "NONE",
        "horizon_mode": "POOLED",
        "max_depth": None,
        "min_samples_leaf": None,
        "tail_lambda": None,
        **global_metrics,
        "global_same_tasks_mean_regret": global_metrics["mean_regret"],
        "global_same_tasks_cvar90": global_metrics["cvar90"],
        "rho_mean": 1.0,
        "rho_tail": 1.0,
        "J": 1.0,
        "selected": 0,
    }

    # 2) V1_STYLE_RF_REGRET development baseline, refit on V2_TRAIN folds only.
    v1_decisions, v1_metrics = build_v1_oof(records, parents, parent_to_rows, arr)
    v1_metrics = add_relative_metrics(v1_metrics, global_by_parent, v1_decisions)
    v1_candidate = {
        "candidate_id": "V1_STYLE_RF_REGRET",
        "architecture": "V1_STYLE_RF_REGRET",
        "feature_mode": "FULL",
        "horizon_mode": "V1",
        "max_depth": None,
        "min_samples_leaf": 0.01,
        "tail_lambda": None,
        **v1_metrics,
        "selected": 0,
    }

    candidates: List[Dict[str, Any]] = [global_candidate, v1_candidate]
    decision_store: Dict[str, List[Dict[str, Any]]] = {
        "GLOBAL_RANK_V2": global_decisions,
        "V1_STYLE_RF_REGRET": v1_decisions,
    }

    # 3) 64 ACTION_RF configs. Fit 16 base head combinations, then evaluate four lambdas each.
    action_count = 0
    for feature_mode in ["BASE_RISK", "FULL_RISK"]:
        for horizon_mode in ["POOLED", "BY_H"]:
            for max_depth in [8, None]:
                for min_leaf in [0.01, 0.03]:
                    mu, pbad, tau_row, row_supported = fit_action_base_oof(
                        records, parents, parent_to_rows, arr,
                        feature_mode, horizon_mode, max_depth, min_leaf,
                    )
                    for lam in [0.0, 0.5, 1.0, 2.0]:
                        cid = (
                            f"ACTION_RF__{feature_mode}__{horizon_mode}__"
                            f"depth_{'None' if max_depth is None else max_depth}__"
                            f"leaf_{min_leaf:.2f}__lambda_{lam:g}"
                        )
                        dec, met = action_decisions_for_lambda(
                            records, parents, parent_to_rows, mu, pbad, tau_row, row_supported, lam
                        )
                        met = add_relative_metrics(met, global_by_parent, dec)
                        cand = {
                            "candidate_id": cid,
                            "architecture": "ACTION_RF",
                            "feature_mode": feature_mode,
                            "horizon_mode": horizon_mode,
                            "max_depth": max_depth,
                            "min_samples_leaf": min_leaf,
                            "tail_lambda": lam,
                            **met,
                            "selected": 0,
                        }
                        candidates.append(cand)
                        decision_store[cid] = dec
                        action_count += 1
    if action_count != 64 or len(candidates) != 66:
        raise RuntimeError(f"candidate count mismatch ACTION={action_count}, total={len(candidates)}")

    winner, hierarchy = select_winner(candidates)
    for c in candidates:
        c["selected"] = 1 if c["candidate_id"] == winner["candidate_id"] else 0
    selected_decisions = decision_store[winner["candidate_id"]]
    selected_metrics = {k: winner[k] for k in [
        "n_tasks", "n_supported", "support_coverage", "mean_regret", "median_regret",
        "cvar90", "p90_regret", "zero_regret_rate", "selection_counts",
        "global_same_tasks_mean_regret", "global_same_tasks_cvar90", "rho_mean", "rho_tail", "J"
    ]}
    selected_config = {k: winner.get(k) for k in [
        "candidate_id", "architecture", "feature_mode", "horizon_mode", "max_depth",
        "min_samples_leaf", "tail_lambda"
    ]}
    gate = {
        "rho_mean_lt_1": bool(selected_metrics["rho_mean"] < 1.0),
        "rho_tail_le_1": bool(selected_metrics["rho_tail"] <= 1.0),
    }
    gate["pass"] = bool(gate["rho_mean_lt_1"] and gate["rho_tail_le_1"])

    # Assertions are deterministic and TRAIN-only.
    fold_counts = Counter(parent_meta[p]["fold"] for p in parents)
    assertions = [
        {"assertion": "input_hashes_match_frozen_registry", "status": "PASS", "detail": input_hashes},
        {"assertion": "train_action_rows_18107", "status": "PASS" if len(records) == 18107 else "FAIL", "detail": len(records)},
        {"assertion": "train_actionable_parents_2070", "status": "PASS" if len(parents) == 2070 else "FAIL", "detail": len(parents)},
        {"assertion": "five_train_folds", "status": "PASS" if sorted(fold_counts) == [0,1,2,3,4] else "FAIL", "detail": dict(fold_counts)},
        {"assertion": "action_rf_configs_64", "status": "PASS" if action_count == 64 else "FAIL", "detail": action_count},
        {"assertion": "candidate_count_66", "status": "PASS" if len(candidates) == 66 else "FAIL", "detail": len(candidates)},
        {"assertion": "no_source_identity_feature", "status": "PASS", "detail": "source_class excluded from all X matrices"},
        {"assertion": "all_model_rows_v2_train", "status": "PASS", "detail": "model arrays constructed only after v2_split==V2_TRAIN filter"},
        {"assertion": "cal_outcomes_read", "status": "PASS", "detail": False},
        {"assertion": "locktest_outcomes_read", "status": "PASS", "detail": False},
        {"assertion": "real_bench_2_read", "status": "PASS", "detail": False},
        {"assertion": "selected_support_coverage_ge_0_995", "status": "PASS" if selected_metrics["support_coverage"] >= COVERAGE_FLOOR else "FAIL", "detail": selected_metrics["support_coverage"]},
        {"assertion": "train_mean_gate", "status": "PASS" if gate["rho_mean_lt_1"] else "FAIL", "detail": selected_metrics["rho_mean"]},
        {"assertion": "train_tail_gate", "status": "PASS" if gate["rho_tail_le_1"] else "FAIL", "detail": selected_metrics["rho_tail"]},
    ]
    if any(a["status"] != "PASS" for a in assertions[:11]):
        raise RuntimeError("hard R2 implementation assertion failed")

    selected_obj = {"selected": selected_config, "metrics": selected_metrics, "decisions": selected_decisions}
    global_obj = {"metrics": global_metrics, "decisions": global_decisions}
    v1_obj = {"metrics": v1_metrics, "decisions": v1_decisions}

    summary = {
        "version": VERSION,
        "phase": "STEP_5D_B_R2_TRAIN_ONLY_REPRODUCIBLE_SEARCH",
        "date": "2026-09-04",
        "train_actionable_tasks": len(parents),
        "candidate_count": len(candidates),
        "action_rf_config_count": action_count,
        "global_rank_v2": global_metrics,
        "v1_style_rf_regret": v1_metrics,
        "selected": selected_config,
        "selected_metrics": selected_metrics,
        "selection_hierarchy": hierarchy,
        "go_no_go": gate,
        "by_horizon": subgroup_summary(selected_decisions, parent_meta, "h"),
        "by_source": subgroup_summary(selected_decisions, parent_meta, "source_class"),
        "implementation": {
            "random_seed": RANDOM_SEED,
            "action_trees_per_head": N_ESTIMATORS_ACTION,
            "v1_trees_per_group": N_ESTIMATORS_V1,
            "n_jobs": -1,
            "weighted_q90": "stable sort; first value at cumulative positive action_row_weight >= 0.90 total; no interpolation",
            "cvar90": "mean of worst ceil(0.10*N) supported parent regrets",
            "p90": "numpy quantile q=.90 method=linear",
            "zero_regret": "regret <= 1e-15",
            "structural_support": "decision supported iff every post-dedup eligible action is model-supported",
            "v1_support_min_parents": V1_SUPPORT_MIN_PARENTS,
        },
        "cal_state": "SEALED_NOT_OPENED",
        "confidence_thresholds_state": "NOT_FIT",
        "selector_final_fit_state": "NOT_FIT_R2_OOF_SEARCH_ONLY",
        "locktest_state": "SEALED_NOT_OPENED",
        "real_bench_2_state": "UNTOUCHED_NOT_READ",
    }

    write_architecture_csv(candidates, output_dir / OUTPUT_NAMES["architecture"])
    stable_json_dump(summary, output_dir / OUTPUT_NAMES["summary"])
    stable_json_dump(selected_obj, output_dir / OUTPUT_NAMES["selected"])
    stable_json_dump(global_obj, output_dir / OUTPUT_NAMES["global"])
    stable_json_dump(v1_obj, output_dir / OUTPUT_NAMES["v1"])
    stable_json_dump(assertions, output_dir / OUTPUT_NAMES["assertions"])

    # Print result only; no volatile content is written into canonical outputs.
    print(json.dumps({
        "version": VERSION,
        "selected": selected_config,
        "selected_metrics": selected_metrics,
        "global_rank_v2": {k: global_metrics[k] for k in ["mean_regret", "cvar90", "support_coverage"]},
        "v1_style_rf_regret": {k: v1_metrics[k] for k in ["mean_regret", "cvar90", "rho_mean", "rho_tail", "J"]},
        "go_no_go": gate,
        "output_dir": str(output_dir),
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
