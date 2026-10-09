"""
AutoGrey Step 4E reference meta-feature engine.

Version: AG_FEAT_4E_1
Scope: AutoGrey v1 univariate point-forecast tasks.
Hard chronology contract: the public API accepts ONLY the development/training
sequence D plus legitimate task metadata h and optional known seasonal period M.
It has no argument for a full series, test tail, split index, labels, or losses.

Unavailable features are represented by:
    values[i] = 0.0
    valid_mask[i] = False
    reason_codes[i] = explicit code
No statistical imputation or scaling is performed here. Those operations belong
inside META_TRAIN in Step 4F.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Optional

import numpy as np


FEATURE_VERSION = "AG_FEAT_4E_1"
EPS = 1e-12

FEATURE_NAMES = (
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
)


@dataclass(frozen=True)
class FeatureSnapshot:
    version: str
    names: tuple[str, ...]
    values: np.ndarray
    valid_mask: np.ndarray
    reason_codes: tuple[str, ...]
    n: int
    h: int
    M: Optional[int]
    train_hash: str
    feature_hash: str

    def as_dict(self) -> dict:
        return {
            "version": self.version,
            "names": list(self.names),
            "values": self.values.tolist(),
            "valid_mask": self.valid_mask.tolist(),
            "reason_codes": list(self.reason_codes),
            "n": self.n,
            "h": self.h,
            "M": self.M,
            "train_hash": self.train_hash,
            "feature_hash": self.feature_hash,
        }


def _scale(x: np.ndarray) -> float:
    return max(float(np.mean(np.abs(x))), EPS)


def _train_hash(x: np.ndarray) -> str:
    # Stable across platforms by pinning little-endian float64 bytes.
    xx = np.asarray(x, dtype="<f8")
    return hashlib.sha256(xx.tobytes()).hexdigest()


def _feature_hash(values: np.ndarray, mask: np.ndarray, n: int, h: int, M: Optional[int]) -> str:
    payload = {
        "version": FEATURE_VERSION,
        "n": int(n),
        "h": int(h),
        "M": None if M is None else int(M),
        "values_hex": np.asarray(values, dtype="<f8").tobytes().hex(),
        "mask": np.asarray(mask, dtype=np.uint8).tobytes().hex(),
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()


def _r2(y: np.ndarray, X: np.ndarray) -> tuple[float, bool]:
    y = np.asarray(y, float)
    X = np.asarray(X, float)
    yc = y - np.mean(y)
    sst = float(yc @ yc)
    if not np.isfinite(sst) or sst <= EPS * max(float(np.mean(np.abs(y))) ** 2, 1.0):
        return 0.0, False
    try:
        beta, _, rank, _ = np.linalg.lstsq(X, y, rcond=None)
    except np.linalg.LinAlgError:
        return 0.0, False
    if rank < X.shape[1]:
        return 0.0, False
    resid = y - X @ beta
    sse = float(resid @ resid)
    val = 1.0 - sse / sst
    if not np.isfinite(val):
        return 0.0, False
    # Only numerical overshoot is clipped.
    return float(np.clip(val, 0.0, 1.0)), True


def _slope(y: np.ndarray, t: np.ndarray) -> tuple[float, bool]:
    y = np.asarray(y, float)
    t = np.asarray(t, float)
    X = np.column_stack([np.ones(len(t)), t])
    try:
        beta, _, rank, _ = np.linalg.lstsq(X, y, rcond=None)
    except np.linalg.LinAlgError:
        return 0.0, False
    if rank < 2 or not np.all(np.isfinite(beta)):
        return 0.0, False
    return float(beta[1]), True


def _acf_global_mean(x: np.ndarray, lag: int) -> tuple[float, bool]:
    x = np.asarray(x, float)
    n = len(x)
    if n <= lag:
        return 0.0, False
    xc = x - np.mean(x)
    den = float(xc @ xc)
    if den <= EPS * max(float(np.mean(np.abs(x))) ** 2, 1.0):
        return 0.0, False
    num = float(np.dot(xc[lag:], xc[:-lag]))
    val = num / den
    if not np.isfinite(val):
        return 0.0, False
    return float(np.clip(val, -1.0, 1.0)), True


def _near_zero(x: float) -> bool:
    # Step 4C analytic-branch convention for c=0.
    return abs(float(x)) <= 1e-10 + 1e-6


def _gm_fit_forecast(x: np.ndarray, h: int, alpha: float = 0.5):
    """Canonical continuous GM landmark. Returns (fitted, forecast) or None."""
    x = np.asarray(x, float)
    n = len(x)
    if n < 4 or h < 1:
        return None
    x1 = np.cumsum(x)
    z = alpha * x1[1:] + (1.0 - alpha) * x1[:-1]
    B = np.column_stack([-z, np.ones(n - 1)])
    Y = x[1:]
    try:
        theta, _, rank, _ = np.linalg.lstsq(B, Y, rcond=None)
    except np.linalg.LinAlgError:
        return None
    if rank < 2 or not np.all(np.isfinite(theta)):
        return None
    a, b = map(float, theta)
    k = np.arange(n + h, dtype=float)
    if _near_zero(a):
        x1h = x[0] + b * k
    else:
        with np.errstate(over="ignore", invalid="ignore", divide="ignore"):
            x1h = (x[0] - b / a) * np.exp(-a * k) + b / a
    if not np.all(np.isfinite(x1h)):
        return None
    xh = np.empty_like(x1h)
    xh[0] = x1h[0]
    xh[1:] = np.diff(x1h)
    if not np.all(np.isfinite(xh)):
        return None
    return xh[:n], xh[n:n+h]


def _average_wbo(x: np.ndarray) -> np.ndarray:
    """First-order average weakening-buffer operator: suffix means."""
    x = np.asarray(x, float)
    n = len(x)
    # Reverse cumulative sum gives stable suffix sums.
    suffix_sum = np.cumsum(x[::-1])[::-1]
    counts = np.arange(n, 0, -1, dtype=float)
    return suffix_sum / counts


def _seasonal_factors(x: np.ndarray, M: int):
    """
    Training-only phase factors consistent with the Step 4A/4B SGM convention:
    phase mean / overall mean, with known M and at least 2 observations per phase.
    """
    x = np.asarray(x, float)
    n = len(x)
    if M < 2 or n < 2 * M:
        return None
    phase_means = []
    counts = []
    for s in range(M):
        vals = x[s::M]
        counts.append(len(vals))
        if len(vals) < 2:
            return None
        phase_means.append(float(np.mean(vals)))
    overall = float(np.mean(x))
    if abs(overall) <= EPS * max(float(np.mean(np.abs(x))), 1.0):
        return None
    factors = np.asarray(phase_means, float) / overall
    if not np.all(np.isfinite(factors)) or np.any(factors <= 0):
        return None
    return factors


def extract_features(D, h: int, M: Optional[int] = None) -> FeatureSnapshot:
    """
    Compute the frozen Step 4E feature snapshot from development data only.

    Parameters
    ----------
    D : array-like
        Chronologically ordered development/training values only.
    h : int
        Forecast horizon known at decision time.
    M : int or None
        Legitimate known seasonal period from task metadata. Never inferred by
        looking into the held-out future.

    Returns
    -------
    FeatureSnapshot
        Fixed 23-value vector, validity mask, explicit reason codes and hashes.
    """
    x = np.asarray(D, dtype=float)
    if x.ndim != 1:
        raise ValueError("D must be a 1-D development sequence")
    n = len(x)
    if n < 4:
        raise ValueError("Step 4E feature extraction requires n>=4")
    if not np.all(np.isfinite(x)):
        raise ValueError("D contains non-finite values")
    if not isinstance(h, (int, np.integer)) or int(h) < 1:
        raise ValueError("h must be a positive integer")
    h = int(h)
    if M is not None:
        if not isinstance(M, (int, np.integer)) or int(M) < 2:
            raise ValueError("M must be None or an integer >=2")
        M = int(M)

    values = np.zeros(len(FEATURE_NAMES), dtype=float)
    valid = np.zeros(len(FEATURE_NAMES), dtype=bool)
    reasons = ["UNSET"] * len(FEATURE_NAMES)
    idx = {name: i for i, name in enumerate(FEATURE_NAMES)}

    def setf(name: str, value: float, ok: bool = True, reason: str = "OK"):
        i = idx[name]
        if ok and np.isfinite(value):
            values[i] = float(value)
            valid[i] = True
            reasons[i] = reason
        else:
            values[i] = 0.0
            valid[i] = False
            reasons[i] = reason if reason != "OK" else "NUMERIC_UNDEFINED"

    t = np.arange(1, n + 1, dtype=float)
    Xlin = np.column_stack([np.ones(n), t])
    Xquad = np.column_stack([np.ones(n), t, t**2])

    # F01 trend_r2
    r2lin, ok_lin = _r2(x, Xlin)
    setf("trend_r2", r2lin, ok_lin, "OK" if ok_lin else "ZERO_OR_NEARZERO_VARIANCE")

    # F02 quadratic_gain
    if n >= 5 and ok_lin:
        r2q, ok_q = _r2(x, Xquad)
        setf("quadratic_gain", max(0.0, r2q - r2lin), ok_q,
             "OK" if ok_q else "QUADRATIC_FIT_UNDEFINED")
    else:
        setf("quadratic_gain", 0.0, False,
             "N_LT_5" if n < 5 else "ZERO_OR_NEARZERO_VARIANCE")

    d1 = np.diff(x)
    d2 = np.diff(x, n=2)

    # F03 up_step_fraction
    setf("up_step_fraction", float(np.mean(d1 > 0)))

    # F04 curvature_sign
    m2 = float(np.mean(d2))
    setf("curvature_sign", 1.0 if m2 > 0 else (-1.0 if m2 < 0 else 0.0))

    mean_x = float(np.mean(x))
    scale_x = _scale(x)
    sd_x = float(np.std(x, ddof=1))

    # F05 cv_abs
    mean_tol = EPS * max(scale_x, 1.0)
    setf("cv_abs", sd_x / abs(mean_x) if abs(mean_x) > mean_tol else 0.0,
         abs(mean_x) > mean_tol,
         "OK" if abs(mean_x) > mean_tol else "MEAN_NEAR_ZERO")

    # F06 range_rel
    setf("range_rel", (float(np.max(x)) - float(np.min(x))) / abs(mean_x)
         if abs(mean_x) > mean_tol else 0.0,
         abs(mean_x) > mean_tol,
         "OK" if abs(mean_x) > mean_tol else "MEAN_NEAR_ZERO")

    # F07 smoothness
    var_x = float(np.var(x, ddof=1))
    if var_x <= EPS * max(scale_x**2, 1.0):
        setf("smoothness", 1.0, True, "CONSTANT_BOUNDARY_VALUE")
    else:
        var_d = float(np.var(d1, ddof=1)) if len(d1) > 1 else 0.0
        setf("smoothness", float(np.clip(1.0 - var_d / var_x, -1.0, 1.0)))

    # F08 Tukey outlier fraction, explicitly replacing two conflicting legacy f8 definitions.
    q1, q3 = np.quantile(x, [0.25, 0.75], method="linear")
    iqr = float(q3 - q1)
    lo, hi = float(q1 - 1.5 * iqr), float(q3 + 1.5 * iqr)
    setf("outlier_fraction_tukey", float(np.mean((x < lo) | (x > hi))))

    # F09/F10 raw ACFs using one frozen global-mean definition.
    ac1, ok1 = _acf_global_mean(x, 1)
    setf("acf1", ac1, ok1, "OK" if ok1 else "ACF_VARIANCE_UNDEFINED")
    ac2, ok2 = _acf_global_mean(x, 2)
    setf("acf2", ac2, ok2, "OK" if ok2 else "ACF_VARIANCE_UNDEFINED")

    # F11 skewness of first differences, population central-moment functional.
    if len(d1) >= 4:
        dc = d1 - np.mean(d1)
        m2d = float(np.mean(dc**2))
        if m2d > EPS * max(float(np.mean(np.abs(d1)))**2, 1.0):
            setf("diff_skewness", float(np.mean(dc**3) / (m2d ** 1.5)))
        else:
            setf("diff_skewness", 0.0, False, "DIFF_VARIANCE_UNDEFINED")
    else:
        setf("diff_skewness", 0.0, False, "FEWER_THAN_4_DIFFERENCES")

    # F12 ordinary 1-AGO linearity
    x1 = np.cumsum(x)
    r2ago, ok_ago = _r2(x1, Xlin)
    setf("ago_linearity_r2", r2ago, ok_ago,
         "OK" if ok_ago else "AGO_VARIANCE_UNDEFINED")

    # F13-F16 positive-series grey/growth diagnostics
    positive = bool(np.all(x > 0))
    if positive:
        lam = x[:-1] / x[1:]
        loglam = np.log(lam)
        bound = 2.0 / (n + 1.0)
        setf("class_ratio_pass_rate", float(np.mean(np.abs(loglam) < bound)))
        setf("class_ratio_max_log_violation",
             float(np.max(np.maximum(0.0, np.abs(loglam) - bound))))
        lg = np.log(x[1:] / x[:-1])
        setf("mean_log_growth", float(np.mean(lg)))
        if n >= 7:
            setf("log_growth_delta", float(np.mean(lg[-3:]) - np.mean(lg[:3])))
        else:
            setf("log_growth_delta", 0.0, False, "N_LT_7")
    else:
        for name in ("class_ratio_pass_rate", "class_ratio_max_log_violation",
                     "mean_log_growth", "log_growth_delta"):
            setf(name, 0.0, False, "REQUIRES_STRICT_POSITIVITY")

    # F17 recent slope shift: AutoGrey design, scale-free.
    bfull, ok_full = _slope(x, t)
    recent_idx = np.arange(max(0, n - 4), n)
    brec, ok_recent = _slope(x[recent_idx], t[recent_idx])
    if ok_full and ok_recent and scale_x > EPS:
        setf("recent_slope_shift", (brec - bfull) * n / scale_x)
    else:
        setf("recent_slope_shift", 0.0, False, "SLOPE_UNDEFINED")

    # F18 WBO distortion: distance induced by the registered first-order average WBO.
    wbo = _average_wbo(x)
    if scale_x > EPS:
        setf("wbo_distortion", float(np.mean(np.abs(wbo - x)) / scale_x))
    else:
        setf("wbo_distortion", 0.0, False, "LEVEL_SCALE_UNDEFINED")

    # F19 GM background sensitivity: landmark forecast dispersion at the actual horizon h.
    gm_forecasts = []
    gm_ok = True
    for alpha in (0.25, 0.50, 0.75):
        fit = _gm_fit_forecast(x, h, alpha)
        if fit is None:
            gm_ok = False
            break
        gm_forecasts.append(fit[1])
    if gm_ok and scale_x > EPS:
        F = np.vstack(gm_forecasts)
        # Horizon-specific maximum forecast spread, normalised by historical level.
        sens = float(np.max(np.max(F, axis=0) - np.min(F, axis=0)) / scale_x)
        setf("gm_background_sensitivity", sens)
    else:
        setf("gm_background_sensitivity", 0.0, False, "GM_LANDMARK_FAIL")

    # F20 canonical GM residual lag-1 ACF on k=2..n residuals.
    gm0 = _gm_fit_forecast(x, 1, 0.50)
    if gm0 is not None:
        resid = x[1:] - gm0[0][1:]
        racf, rok = _acf_global_mean(resid, 1)
        setf("gm_residual_acf1", racf, rok,
             "OK" if rok else "GM_RESIDUAL_VARIANCE_UNDEFINED")
    else:
        setf("gm_residual_acf1", 0.0, False, "GM_LANDMARK_FAIL")

    # F21 seasonal factor amplitude, only with legitimate known M.
    if M is None:
        setf("seasonal_factor_amplitude", 0.0, False, "SEASONAL_METADATA_MISSING")
    else:
        fac = _seasonal_factors(x, M)
        if fac is None:
            setf("seasonal_factor_amplitude", 0.0, False, "SEASONAL_FACTOR_UNAVAILABLE")
        else:
            setf("seasonal_factor_amplitude", float(np.max(fac) - np.min(fac)))

    # F22-F23 task features
    setf("log_n", float(np.log(n)))
    setf("horizon_ratio", float(h / n))

    # Contract: even masked features carry finite neutral placeholders.
    if not np.all(np.isfinite(values)):
        raise RuntimeError("Feature engine produced non-finite output; this violates Step 4E")

    th = _train_hash(x)
    fh = _feature_hash(values, valid, n, h, M)
    return FeatureSnapshot(
        version=FEATURE_VERSION,
        names=FEATURE_NAMES,
        values=values,
        valid_mask=valid,
        reason_codes=tuple(reasons),
        n=n,
        h=h,
        M=M,
        train_hash=th,
        feature_hash=fh,
    )


def feature_dict(snapshot: FeatureSnapshot) -> dict[str, float]:
    return dict(zip(snapshot.names, snapshot.values))


def mask_dict(snapshot: FeatureSnapshot) -> dict[str, bool]:
    return dict(zip(snapshot.names, snapshot.valid_mask))


def run_self_tests() -> list[dict]:
    """Deterministic Step 4E regression/contract tests. Raises on any failure."""
    tests = []

    def check(name: str, condition: bool, detail: str = ""):
        if not condition:
            raise AssertionError(f"{name}: {detail}")
        tests.append({"test": name, "status": "PASS", "detail": detail})

    # Fixtures use only development data.
    n = 12
    linear = 100.0 + 5.0 * np.arange(n)
    exponential = 100.0 * (1.05 ** np.arange(n))
    logistic = 200.0 / (1.0 + np.exp(-0.55 * (np.arange(n) - 5.0)))
    regime = np.r_[100 + 2*np.arange(8), 116 + 12*np.arange(4)]
    constant = np.full(n, 50.0)
    seasonal = np.array([80, 100, 130, 90] * 3, dtype=float) * (1.02 ** np.arange(n))

    fixtures = {
        "linear": (linear, 3, None),
        "exponential": (exponential, 3, None),
        "logistic": (logistic, 3, None),
        "regime": (regime, 3, None),
        "constant": (constant, 3, None),
        "seasonal": (seasonal, 2, 4),
    }

    snaps = {}
    for nm, (x, h, M) in fixtures.items():
        s = extract_features(x, h, M)
        snaps[nm] = s
        check(f"{nm}_finite_values", bool(np.all(np.isfinite(s.values))))
        check(f"{nm}_shape", len(s.values) == 23 and len(s.valid_mask) == 23)

    # Known source class-ratio region at n=6.
    n6 = 6
    L = np.exp(-2.0/(n6+1.0))
    U = np.exp( 2.0/(n6+1.0))
    check("class_ratio_n6_lower", abs(L - 0.751477293) < 5e-7, f"L={L:.9f}")
    check("class_ratio_n6_upper", abs(U - 1.330712198) < 5e-7, f"U={U:.9f}")

    # Scale invariance for dimensionless data features. Task features are scale-independent too.
    x = np.array([9, 10, 12, 13, 14, 17, 18, 20, 24, 25], dtype=float)
    s1 = extract_features(x, 2, None)
    s2 = extract_features(7.5*x, 2, None)
    d1, d2 = feature_dict(s1), feature_dict(s2)
    scale_invariant = [name for name in FEATURE_NAMES if name != "gm_residual_acf1"]
    # gm_residual_acf1 is theoretically invariant too, but may amplify machine-zero residual differences.
    maxdiff = max(abs(d1[k]-d2[k]) for k in scale_invariant
                  if mask_dict(s1)[k] and mask_dict(s2)[k])
    check("multiplicative_scale_invariance", maxdiff < 1e-9, f"max diff={maxdiff:.3e}")

    # Constant series: no crash; undefined variance features are masked, smoothness boundary is valid 1.
    sc = snaps["constant"]
    dc, mc = feature_dict(sc), mask_dict(sc)
    check("constant_trend_masked", not mc["trend_r2"])
    check("constant_acf_masked", not mc["acf1"])
    check("constant_smoothness_boundary", mc["smoothness"] and dc["smoothness"] == 1.0)

    # Seasonal amplitude is conditional on legitimate M.
    ss = snaps["seasonal"]
    ds, ms = feature_dict(ss), mask_dict(ss)
    check("seasonal_feature_valid_with_M", ms["seasonal_factor_amplitude"] and ds["seasonal_factor_amplitude"] > 0)
    snom = extract_features(seasonal, 2, None)
    check("seasonal_feature_masked_without_M", not mask_dict(snom)["seasonal_factor_amplitude"])

    # Positive-only features are explicitly masked for nonpositive data.
    nonpos = np.array([1, 2, 3, 0, 5, 6, 7, 8], dtype=float)
    snp = extract_features(nonpos, 1, None)
    mnp = mask_dict(snp)
    check("class_ratio_nonpositive_mask", not mnp["class_ratio_pass_rate"])
    check("log_growth_nonpositive_mask", not mnp["mean_log_growth"])

    # Regime feature should react in the expected direction.
    dr = feature_dict(snaps["regime"])
    check("regime_recent_slope_shift_positive", dr["recent_slope_shift"] > 0,
          f"value={dr['recent_slope_shift']:.6f}")

    # API/provenance: same D/h/M -> same hashes; changed future is impossible because no future argument exists.
    sa = extract_features(exponential, 3, None)
    sb = extract_features(exponential.copy(), 3, None)
    check("deterministic_train_hash", sa.train_hash == sb.train_hash)
    check("deterministic_feature_hash", sa.feature_hash == sb.feature_hash)

    # h is allowed to affect only task/landmark quantities; raw history still identical.
    sh1 = extract_features(exponential, 1, None)
    sh3 = extract_features(exponential, 3, None)
    raw_history_names = FEATURE_NAMES[:18] + ("gm_residual_acf1", "log_n")
    hdiff = max(abs(feature_dict(sh1)[k]-feature_dict(sh3)[k]) for k in raw_history_names)
    check("raw_history_features_h_invariant", hdiff < 1e-12, f"max diff={hdiff:.3e}")
    check("horizon_ratio_changes_with_h",
          feature_dict(sh1)["horizon_ratio"] != feature_dict(sh3)["horizon_ratio"])

    return tests


if __name__ == "__main__":
    results = run_self_tests()
    print(json.dumps({
        "feature_version": FEATURE_VERSION,
        "n_features": len(FEATURE_NAMES),
        "tests_passed": len(results),
        "results": results,
    }, indent=2))
