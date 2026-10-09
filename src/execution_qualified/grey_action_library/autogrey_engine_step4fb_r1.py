"""
AutoGrey canonical v1 forecast engine — Step 4F-B reference implementation.

Version: AG_ENGINE_4FB_1
Date: 2026-09-03

Implements the frozen v1 selection groups from Steps 4A–4C:
  SG01_CONT_GM
  SG02_DISCRETE_POLY
  SG03_FRAC_LINEAR
  SG04_BERNOULLI
  SG05_CONT_TIME_POLY
  SG06_CONFORMABLE
  SG07_ROLLING
  SG08_WBO
  SG09_GREY_MARKOV
  SG10_SEASONAL

Scientific contract:
- QR/SVD-backed numpy.linalg.lstsq; no explicit (B'B)^-1.
- no silent fallback, floor, clipping of invalid model states, or finite failure sentinel.
- exactly 3 common inner origins.
- one training-only selected configuration -> one final group forecast.
- 5% inner-loss band + frozen Step 4C simplicity ordering.
- target values are not arguments to run_portfolio().
- practical forecast collisions are resolved before any target scoring.
- reference forecasts are non-selectable.

This is a reference engine for reproducibility and label generation. It is not yet
the Shiny production engine and it contains no fitted meta-selector.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from itertools import combinations
from math import ceil
from typing import Any, Optional, Iterable

import numpy as np
from scipy.integrate import quad

ENGINE_VERSION = "AG_ENGINE_4FB_1R1"

GROUP_ORDER = (
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
)

NEAR_ATOL = 1e-10
NEAR_RTOL = 1e-6
COND_FAIL = 1e12
NGBM_ID_WARN = 1e3
NGBM_ID_FAIL = 1e4
COLLISION_TOL = 1e-3
COLLISION_SENSITIVITY = (1e-4, 1e-2)
SEASON_REDUCTION_TOL = 1e-6
MARKOV_ROW_TOL = 1e-10

# Deterministic fixed-order Gauss-Legendre nodes for source-equivalent
# integrating-factor quadrature in time-power models. This avoids adaptive
# scipy.quad pathologies on some synthetic short-series fits while evaluating
# the same definite integral.
_GL_X32, _GL_W32 = np.polynomial.legendre.leggauss(32)

GM_ALPHA_GRID = tuple(round(v, 10) for v in np.arange(0.0, 1.0001, 0.05))
# Wu et al. (2013) explicitly defines the p/q inverse operator for 0<p/q<=1
# and its printed r=0.3/.2/.1 tables reproduce with the c,d initial-condition
# correction below. The paper also reports r>1 examples, but their printed
# restoration cannot yet be reconciled with the generalized inverse convention.
# v1 therefore uses the source-reproducible fractional branch only; r=1 is
# owned by SG01 traditional GM.
FGM_R_GRID = tuple(round(v, 10) for v in np.arange(0.1, 1.0, 0.1))
NGBM_GAMMA_GRID = (
    -1.0, -0.75, -0.5, -0.25, 0.25, 0.5, 0.75,
    1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0,
)
TIMEPOWER_ALPHA_GRID = (0.25,0.5,0.75,1.25,1.5,1.75,2.0,2.25,2.5,2.75,3.0)
CFGM_ALPHA_GRID = tuple([round(v,10) for v in np.arange(0.0,1.0,0.1)] +
                        [round(v,10) for v in np.arange(1.1,2.01,0.1)])


class EngineFailure(RuntimeError):
    def __init__(self, code: str, detail: str = ""):
        self.code = str(code)
        self.detail = str(detail)
        super().__init__(f"{self.code}: {self.detail}")


@dataclass
class ModelOutput:
    forecast: np.ndarray
    fitted: np.ndarray
    params: dict[str, Any]
    diagnostics: dict[str, Any] = field(default_factory=dict)


@dataclass
class ConfigScore:
    config_id: str
    config: dict[str, Any]
    mean_inner_mase: float
    origin_losses: tuple[float, float, float]
    diagnostics: dict[str, Any] = field(default_factory=dict)


@dataclass
class GroupResult:
    group_id: str
    eligible: bool
    selected_config_id: Optional[str] = None
    selected_config: Optional[dict[str, Any]] = None
    forecast: Optional[np.ndarray] = None
    fitted: Optional[np.ndarray] = None
    inner_scores: list[ConfigScore] = field(default_factory=list)
    config_failures: dict[str, str] = field(default_factory=dict)
    diagnostics: dict[str, Any] = field(default_factory=dict)
    failure_code: Optional[str] = None
    failure_detail: str = ""


@dataclass
class PortfolioResult:
    engine_version: str
    n: int
    h: int
    M: Optional[int]
    group_results: dict[str, GroupResult]
    distinct_groups: tuple[str, ...]
    collisions: tuple[dict[str, Any], ...]
    reference_forecasts: dict[str, np.ndarray]
    reference_failures: dict[str, str]
    diagnostics: dict[str, Any] = field(default_factory=dict)


def _as_series(x: Iterable[float], min_n: int = 1) -> np.ndarray:
    a = np.asarray(x, dtype=float)
    if a.ndim != 1:
        raise EngineFailure("SERIES_NOT_1D")
    if len(a) < min_n:
        raise EngineFailure("SERIES_TOO_SHORT", f"n={len(a)} < {min_n}")
    if not np.all(np.isfinite(a)):
        raise EngineFailure("SERIES_NONFINITE")
    return a


def near(x: float, y: float = 0.0, atol: float = NEAR_ATOL, rtol: float = NEAR_RTOL) -> bool:
    return abs(float(x) - float(y)) <= atol + rtol * max(1.0, abs(float(x)), abs(float(y)))


def _cond(B: np.ndarray) -> float:
    s = np.linalg.svd(np.asarray(B, float), compute_uv=False)
    if len(s) == 0 or s[-1] <= np.finfo(float).eps * max(s[0], 1.0):
        return float("inf")
    return float(s[0] / s[-1])


def _lstsq_checked(
    B: np.ndarray,
    Y: np.ndarray,
    *,
    min_resid_df: int = 0,
    cond_fail: float = COND_FAIL,
    failure_prefix: str = "OLS",
) -> tuple[np.ndarray, dict[str, Any]]:
    B = np.asarray(B, dtype=float)
    Y = np.asarray(Y, dtype=float)
    if B.ndim != 2 or Y.ndim != 1 or B.shape[0] != len(Y):
        raise EngineFailure(f"{failure_prefix}_SHAPE")
    if not np.all(np.isfinite(B)) or not np.all(np.isfinite(Y)):
        raise EngineFailure(f"{failure_prefix}_NONFINITE")
    rows, cols = B.shape
    if rows - cols < min_resid_df:
        raise EngineFailure(
            f"{failure_prefix}_RESID_DF",
            f"rows={rows}, params={cols}, required_df={min_resid_df}",
        )
    try:
        theta, residuals, rank, svals = np.linalg.lstsq(B, Y, rcond=None)
    except np.linalg.LinAlgError as e:
        raise EngineFailure(f"{failure_prefix}_LSTSQ_FAIL", str(e))
    if int(rank) < cols:
        raise EngineFailure(f"{failure_prefix}_RANK", f"rank={rank} < {cols}")
    kappa = _cond(B)
    if not np.isfinite(kappa) or kappa >= cond_fail:
        raise EngineFailure(f"{failure_prefix}_CONDITION", f"kappa={kappa:.6g}")
    if not np.all(np.isfinite(theta)):
        raise EngineFailure(f"{failure_prefix}_PARAM_NONFINITE")
    return theta, {
        "rank": int(rank),
        "condition": kappa,
        "rows": rows,
        "params": cols,
        "resid_df": rows - cols,
    }


def inner_origins(n: int, h: int) -> tuple[int, int, int]:
    if h < 1:
        raise EngineFailure("H_INVALID")
    origins = (n - h - 2, n - h - 1, n - h)
    if origins[0] < 1:
        raise EngineFailure("INNER_ORIGINS_UNAVAILABLE", f"n={n},h={h}")
    return origins


def mase_scale(D: Iterable[float], M: Optional[int] = None) -> float:
    x = _as_series(D)
    lag = int(M) if M is not None else 1
    if lag < 1 or len(x) <= lag:
        raise EngineFailure("LOSS_SCALE_UNDEFINED", f"n={len(x)},lag={lag}")
    diffs = np.abs(x[lag:] - x[:-lag])
    scale = float(np.mean(diffs))
    eps = 1e-12 * max(float(np.mean(np.abs(x))), 1.0)
    if not np.isfinite(scale) or scale <= eps:
        raise EngineFailure("LOSS_SCALE_UNDEFINED", f"scale={scale:.6g},eps={eps:.6g}")
    return scale


def mase(y: np.ndarray, f: np.ndarray, D_scale: np.ndarray, M: Optional[int]) -> float:
    y = np.asarray(y, float)
    f = np.asarray(f, float)
    if y.shape != f.shape or not np.all(np.isfinite(y)) or not np.all(np.isfinite(f)):
        raise EngineFailure("LOSS_INPUT_INVALID")
    q = mase_scale(D_scale, M)
    return float(np.mean(np.abs(y - f)) / q)


def normalized_forecast_distance(f: np.ndarray, g: np.ndarray, D: np.ndarray) -> float:
    f = np.asarray(f, float)
    g = np.asarray(g, float)
    if f.shape != g.shape or not np.all(np.isfinite(f)) or not np.all(np.isfinite(g)):
        raise EngineFailure("COLLISION_INPUT_INVALID")
    denom = max(float(np.mean(np.abs(D))), 1e-12)
    return float(np.max(np.abs(f - g)) / denom)


def _continuous_response_constant(x1_0: float, a: float, b: float, total: int) -> np.ndarray:
    tau = np.arange(total, dtype=float)  # tau=t-1
    if near(a, 0.0):
        y = x1_0 + b * tau
    else:
        with np.errstate(over="ignore", invalid="ignore", divide="ignore"):
            y = (x1_0 - b / a) * np.exp(-a * tau) + b / a
    if not np.all(np.isfinite(y)):
        raise EngineFailure("RESPONSE_NONFINITE")
    return y


# ---------------------------------------------------------------------------
# SG01 — continuous GM with background alpha
# ---------------------------------------------------------------------------

def gm_fit_forecast(x: Iterable[float], h: int, alpha: float = 0.5) -> ModelOutput:
    x = _as_series(x, 4)
    if not (0.0 <= alpha <= 1.0):
        raise EngineFailure("GM_ALPHA_DOMAIN")
    x1 = np.cumsum(x)
    z = alpha * x1[1:] + (1.0 - alpha) * x1[:-1]
    B = np.column_stack([-z, np.ones(len(x) - 1)])
    theta, diag = _lstsq_checked(B, x[1:], failure_prefix="GM")
    a, b = map(float, theta)
    x1hat = _continuous_response_constant(float(x[0]), a, b, len(x) + h)
    xhat = np.empty_like(x1hat)
    xhat[0] = x1hat[0]
    xhat[1:] = np.diff(x1hat)
    if not np.all(np.isfinite(xhat)):
        raise EngineFailure("GM_RESTORE_NONFINITE")
    return ModelOutput(
        forecast=xhat[-h:].copy(),
        fitted=xhat[:len(x)].copy(),
        params={"a": a, "b": b, "alpha_bg": float(alpha)},
        diagnostics=diag,
    )


# ---------------------------------------------------------------------------
# SG02 — unified discrete polynomial model
# ---------------------------------------------------------------------------

def dgpm_fit_forecast(x: Iterable[float], h: int, degrees: tuple[int, ...] = ()) -> ModelOutput:
    x = _as_series(x, 4)
    degrees = tuple(sorted(set(int(d) for d in degrees)))
    if any(d < 1 or d > 4 for d in degrees):
        raise EngineFailure("DGPM_DEGREE_DOMAIN")
    x1 = np.cumsum(x)
    k = np.arange(2, len(x) + 1, dtype=float)
    cols = [x1[:-1], np.ones(len(x) - 1)]
    cols.extend(k ** d for d in degrees)
    B = np.column_stack(cols)
    theta, diag = _lstsq_checked(B, x[1:], min_resid_df=1, failure_prefix="DGPM")
    alpha = float(theta[0])
    beta0 = float(theta[1])
    beta = {d: float(theta[2 + j]) for j, d in enumerate(degrees)}

    pseudo = list(map(float, x))
    x1_prev = float(x1[-1])
    for kk in range(len(x) + 1, len(x) + h + 1):
        xnext = alpha * x1_prev + beta0 + sum(beta[d] * (float(kk) ** d) for d in degrees)
        if not np.isfinite(xnext):
            raise EngineFailure("DGPM_RESPONSE_NONFINITE")
        pseudo.append(float(xnext))
        x1_prev += float(xnext)

    # fitted values under direct structural equation; first original is anchored.
    fitted = np.empty(len(x), dtype=float)
    fitted[0] = x[0]
    for idx, kk in enumerate(range(2, len(x) + 1), start=1):
        fitted[idx] = alpha * x1[idx - 1] + beta0 + sum(beta[d] * (float(kk) ** d) for d in degrees)

    return ModelOutput(
        forecast=np.asarray(pseudo[-h:], float),
        fitted=fitted,
        params={"alpha": alpha, "beta0": beta0, "beta": beta, "degrees": degrees},
        diagnostics=diag,
    )


# ---------------------------------------------------------------------------
# SG03 — fractional AGO GM
# ---------------------------------------------------------------------------

def fractional_weights(r: float, n: int) -> np.ndarray:
    if n < 1:
        return np.zeros(0, dtype=float)
    w = np.empty(n, dtype=float)
    w[0] = 1.0
    for j in range(1, n):
        w[j] = w[j - 1] * (r + j - 1.0) / j
    if not np.all(np.isfinite(w)):
        raise EngineFailure("FGM_WEIGHT_NONFINITE")
    return w


def fractional_ago(x: Iterable[float], r: float) -> np.ndarray:
    x = _as_series(x)
    w = fractional_weights(float(r), len(x))
    out = np.convolve(x, w)[:len(x)]
    if not np.all(np.isfinite(out)):
        raise EngineFailure("FGM_OPERATOR_NONFINITE")
    return out


def fractional_iago(xr: Iterable[float], r: float) -> np.ndarray:
    xr = _as_series(xr)
    # Same recurrence with negative order. At integer r this exactly truncates
    # to the finite binomial inverse, avoiding gamma poles.
    return fractional_ago(xr, -float(r))


def fgm_fit_forecast(x: Iterable[float], h: int, r: float) -> ModelOutput:
    """
    Source-faithful Wu et al. (2013) fractional branch for 0<r<1.

    The paper first estimates a,b from the fractional grey equation, then
    explicitly re-estimates the exponential response constants c,d from
    x^(r)(2:n):
        xhat^(r)(k+1) = c * exp(-a*k) + d.
    The printed r=0.3 Table-2 fit/forecast is reproduced by this procedure.

    r=1 is deliberately NOT accepted here. Wu et al.'s printed r=1 column is
    the traditional anchored GM(1,1), which is owned by SG01.
    """
    x = _as_series(x, 4)
    r = float(r)
    if not (0.0 < r < 1.0):
        raise EngineFailure("FGM_R_V1_DOMAIN", f"v1 source-faithful branch requires 0<r<1; r={r}")

    xr = fractional_ago(x, r)

    # Grey-equation fit for a,b.
    Y = np.diff(xr)
    z = 0.5 * (xr[1:] + xr[:-1])
    B = np.column_stack([-z, np.ones(len(x) - 1)])
    theta, diag_ab = _lstsq_checked(B, Y, failure_prefix="FGM")
    a, b = map(float, theta)

    # Wu et al. initial-condition correction:
    #   xr(k+1) = c exp(-a k) + d, k=1,...,n-1
    k_fit = np.arange(1, len(x), dtype=float)
    E = np.column_stack([np.exp(-a * k_fit), np.ones(len(k_fit))])
    cd, diag_cd = _lstsq_checked(E, xr[1:], failure_prefix="FGM_CD")
    c, d = map(float, cd)

    k_all = np.arange(1, len(x) + h, dtype=float)
    xrhat = np.empty(len(x) + h, dtype=float)
    # Preserve the first accumulated observation exactly, as in the printed
    # source tables; the corrected exponential response supplies k>=2.
    xrhat[0] = xr[0]
    xrhat[1:] = c * np.exp(-a * k_all) + d
    if not np.all(np.isfinite(xrhat)):
        raise EngineFailure("FGM_RESPONSE_NONFINITE")

    xhat = fractional_iago(xrhat, r)
    if not np.all(np.isfinite(xhat)):
        raise EngineFailure("FGM_RESTORE_NONFINITE")

    diagnostics = dict(diag_ab)
    diagnostics.update({
        "cd_rank": diag_cd["rank"],
        "cd_condition": diag_cd["condition"],
        "response_convention": "WU2013_c_d_initial_condition_correction",
        "r1_owner": "SG01_CONT_GM",
    })
    return ModelOutput(
        forecast=xhat[-h:].copy(),
        fitted=xhat[:len(x)].copy(),
        params={"a": a, "b": b, "c": c, "d": d, "r": r},
        diagnostics=diagnostics,
    )


# ---------------------------------------------------------------------------
# SG04 — nonlinear Grey Bernoulli / Verhulst
# ---------------------------------------------------------------------------

def _is_integer_like(p: float) -> bool:
    return abs(float(p) - round(float(p))) <= 1e-10


def _real_power_scalar(base: float, exponent: float) -> float:
    base = float(base)
    exponent = float(exponent)
    if base > 0:
        val = base ** exponent
    elif base == 0:
        if exponent < 0:
            raise EngineFailure("NGBM_REAL_DOMAIN_FAIL", "zero base with negative power")
        val = 1.0 if exponent == 0 else 0.0
    else:
        if not _is_integer_like(exponent):
            raise EngineFailure("NGBM_REAL_DOMAIN_FAIL", f"negative base {base} ^ {exponent}")
        val = base ** int(round(exponent))
    if not np.isfinite(val):
        raise EngineFailure("NGBM_REAL_DOMAIN_FAIL", f"nonfinite power {base}^{exponent}")
    return float(val)


def ngbm_fit_forecast(x: Iterable[float], h: int, gamma: float) -> ModelOutput:
    x = _as_series(x, 4)
    if near(gamma, 1.0):
        raise EngineFailure("NGBM_GAMMA_ONE_SINGULAR")
    x1 = np.cumsum(x)
    z = 0.5 * (x1[1:] + x1[:-1])
    zg = np.asarray([_real_power_scalar(v, gamma) for v in z], dtype=float)
    B = np.column_stack([-z, zg])

    # Explicit identifiability diagnostic on L2-normalized columns.
    norms = np.linalg.norm(B, axis=0)
    if np.any(norms <= np.finfo(float).eps):
        raise EngineFailure("NGBM_IDENTIFIABILITY_FAIL", "zero design-column norm")
    kappa_id = _cond(B / norms)
    if not np.isfinite(kappa_id) or kappa_id >= NGBM_ID_FAIL:
        raise EngineFailure("NGBM_IDENTIFIABILITY_FAIL", f"kappa_id={kappa_id:.6g}")

    theta, diag = _lstsq_checked(B, x[1:], failure_prefix="NGBM")
    a, b = map(float, theta)
    power0 = 1.0 - gamma
    u0 = _real_power_scalar(float(x1[0]), power0)
    tau = np.arange(len(x) + h, dtype=float)
    y1 = np.empty(len(tau), dtype=float)
    if near(a, 0.0):
        bracket = u0 + power0 * b * tau
    else:
        bracket = (u0 - b / a) * np.exp(-a * power0 * tau) + b / a
    for i, v in enumerate(bracket):
        y1[i] = _real_power_scalar(float(v), 1.0 / power0)
    xhat = np.empty_like(y1)
    xhat[0] = y1[0]
    xhat[1:] = np.diff(y1)
    if not np.all(np.isfinite(xhat)):
        raise EngineFailure("NGBM_REAL_DOMAIN_FAIL", "restored sequence nonfinite")
    diag["kappa_id"] = float(kappa_id)
    diag["kappa_id_warning"] = bool(kappa_id >= NGBM_ID_WARN)
    return ModelOutput(
        forecast=xhat[-h:].copy(),
        fitted=xhat[:len(x)].copy(),
        params={"a": a, "b": b, "gamma": float(gamma)},
        diagnostics=diag,
    )


# ---------------------------------------------------------------------------
# SG05 — continuous time-power and FOTP whitening
# ---------------------------------------------------------------------------

def _timepower_response(x1_0: float, a: float, b: float, c: float, alpha: float, total: int) -> np.ndarray:
    """Integrating-factor response evaluated interval-by-interval.

    For a != 0:
        y(t) = exp(-a) y(t-1)
               + integral_{t-1}^t exp[-a(t-s)] [b s^alpha + c] ds.

    The unit-interval integral is evaluated by fixed 32-point Gauss-Legendre
    quadrature. This is deterministic and source-equivalent to the earlier
    adaptive definite integration, but avoids extreme adaptive-quadrature cost
    for some parameter combinations encountered during corpus generation.
    """
    ts = np.arange(1, total + 1, dtype=float)
    out = np.empty(total, dtype=float)
    out[0] = x1_0
    if near(a, 0.0):
        for i, tt in enumerate(ts[1:], start=1):
            out[i] = x1_0 + b * (tt ** (alpha + 1.0) - 1.0) / (alpha + 1.0) + c * (tt - 1.0)
    else:
        decay = float(np.exp(-a))
        if not np.isfinite(decay):
            raise EngineFailure("TIMEPOWER_RESPONSE_NONFINITE", "nonfinite unit decay")
        for i in range(1, total):
            left = float(i)       # time t-1 in 1-based clock
            right = float(i + 1)  # time t
            mid = 0.5 * (left + right)
            half = 0.5 * (right - left)
            s = mid + half * _GL_X32
            with np.errstate(over="ignore", invalid="ignore"):
                integrand = np.exp(-a * (right - s)) * (b * (s ** alpha) + c)
            if not np.all(np.isfinite(integrand)):
                raise EngineFailure("TIMEPOWER_RESPONSE_NONFINITE", "nonfinite quadrature integrand")
            integ = half * float(np.dot(_GL_W32, integrand))
            out[i] = decay * out[i-1] + integ
    if not np.all(np.isfinite(out)):
        raise EngineFailure("TIMEPOWER_RESPONSE_NONFINITE")
    return out


def timepower_fit_forecast(x: Iterable[float], h: int, alpha: float) -> ModelOutput:
    x = _as_series(x, 5)
    if alpha < 0 or near(alpha, 0.0):
        raise EngineFailure("TIMEPOWER_ALPHA_REDUCTION")
    x1 = np.cumsum(x)
    k = np.arange(2, len(x) + 1, dtype=float)
    z = 0.5 * (x1[1:] + x1[:-1])
    B = np.column_stack([-z, k ** float(alpha), np.ones(len(x) - 1)])
    theta, diag = _lstsq_checked(B, x[1:], min_resid_df=1, failure_prefix="TIMEPOWER")
    a, b, c = map(float, theta)
    y1 = _timepower_response(float(x[0]), a, b, c, float(alpha), len(x) + h)
    xhat = np.empty_like(y1)
    xhat[0] = y1[0]
    xhat[1:] = np.diff(y1)
    return ModelOutput(
        forecast=xhat[-h:].copy(),
        fitted=xhat[:len(x)].copy(),
        params={"a": a, "b": b, "c": c, "alpha": float(alpha)},
        diagnostics=diag,
    )


def _poly_eval_ascending(coeff: np.ndarray, t: np.ndarray | float) -> np.ndarray:
    coeff = np.asarray(coeff, float)
    return sum(coeff[j] * (np.asarray(t, float) ** j) for j in range(len(coeff)))


def _fotp_response(x1_0: float, a: float, c_asc: np.ndarray, total: int) -> np.ndarray:
    ts = np.arange(1, total + 1, dtype=float)
    d = len(c_asc) - 1
    if near(a, 0.0):
        out = np.full(total, x1_0, dtype=float)
        for j, cj in enumerate(c_asc):
            out += cj / (j + 1.0) * (ts ** (j + 1.0) - 1.0)
    else:
        q = np.zeros(d + 1, dtype=float)
        q_next = 0.0
        for m in range(d, -1, -1):
            q[m] = (c_asc[m] - (m + 1.0) * q_next) / a
            q_next = q[m]
        q1 = float(_poly_eval_ascending(q, 1.0))
        out = _poly_eval_ascending(q, ts) + (x1_0 - q1) * np.exp(-a * (ts - 1.0))
    if not np.all(np.isfinite(out)):
        raise EngineFailure("FOTP_RESPONSE_NONFINITE")
    return np.asarray(out, float)


def fotp_fit_forecast(x: Iterable[float], h: int, p_order: int) -> ModelOutput:
    x = _as_series(x, 5)
    p_order = int(p_order)
    if p_order < 2 or p_order > 4:
        raise EngineFailure("FOTP_ORDER_DOMAIN")
    x1 = np.cumsum(x)
    k = np.arange(2, len(x) + 1, dtype=float)
    z = 0.5 * (x1[1:] + x1[:-1])
    powers = list(range(p_order - 1, -1, -1))
    B = np.column_stack([-z] + [k ** p for p in powers])
    theta, diag = _lstsq_checked(B, x[1:], min_resid_df=1, failure_prefix="FOTP")
    a = float(theta[0])
    b_desc = np.asarray(theta[1:], float)
    c_asc = b_desc[::-1].copy()
    y1 = _fotp_response(float(x[0]), a, c_asc, len(x) + h)
    xhat = np.empty_like(y1)
    xhat[0] = y1[0]
    xhat[1:] = np.diff(y1)
    return ModelOutput(
        forecast=xhat[-h:].copy(),
        fitted=xhat[:len(x)].copy(),
        params={"a": a, "b_desc": b_desc.tolist(), "p_order": p_order},
        diagnostics=diag,
    )


# ---------------------------------------------------------------------------
# SG06 — conformable fractional GM
# ---------------------------------------------------------------------------

def conformable_cfa(x: Iterable[float], alpha: float) -> np.ndarray:
    x = _as_series(x)
    alpha = float(alpha)
    if alpha < 0:
        raise EngineFailure("CFGM_ALPHA_DOMAIN")
    if near(alpha, 0.0, atol=1e-14, rtol=0.0):
        return x.copy()
    q = int(ceil(alpha - 1e-14))
    q = max(q, 1)
    k = np.arange(1, len(x) + 1, dtype=float)
    weighted = x / (k ** (q - alpha))
    out = weighted.copy()
    for _ in range(q):
        out = np.cumsum(out)
    if not np.all(np.isfinite(out)):
        raise EngineFailure("CFGM_CFA_NONFINITE")
    return out


def conformable_cfd(xa: Iterable[float], alpha: float) -> np.ndarray:
    xa = _as_series(xa)
    alpha = float(alpha)
    if alpha < 0:
        raise EngineFailure("CFGM_ALPHA_DOMAIN")
    if near(alpha, 0.0, atol=1e-14, rtol=0.0):
        return xa.copy()
    q = int(ceil(alpha - 1e-14))
    q = max(q, 1)
    out = xa.copy()
    for _ in range(q):
        out = np.diff(out, prepend=0.0)
    k = np.arange(1, len(out) + 1, dtype=float)
    out = out * (k ** (q - alpha))
    if not np.all(np.isfinite(out)):
        raise EngineFailure("CFGM_CFD_NONFINITE")
    return out


def cfgm_fit_forecast(x: Iterable[float], h: int, alpha: float) -> ModelOutput:
    x = _as_series(x, 4)
    alpha = float(alpha)
    if alpha < 0 or alpha > 2.0 + 1e-12:
        raise EngineFailure("CFGM_ALPHA_DOMAIN")
    xa = conformable_cfa(x, alpha)
    Y = np.diff(xa)
    z = 0.5 * (xa[1:] + xa[:-1])
    B = np.column_stack([-z, np.ones(len(x) - 1)])
    theta, diag = _lstsq_checked(B, Y, failure_prefix="CFGM")
    a, b = map(float, theta)
    xahat = _continuous_response_constant(float(xa[0]), a, b, len(x) + h)
    xhat = conformable_cfd(xahat, alpha)
    return ModelOutput(
        forecast=xhat[-h:].copy(),
        fitted=xhat[:len(x)].copy(),
        params={"a": a, "b": b, "alpha": alpha},
        diagnostics=diag,
    )


# ---------------------------------------------------------------------------
# SG07 — rolling GM w=4
# ---------------------------------------------------------------------------

def rolling_gm_forecast(x: Iterable[float], h: int, w: int = 4) -> ModelOutput:
    x = _as_series(x, w)
    if w != 4:
        raise EngineFailure("ROLL_WINDOW_NOT_V1", f"w={w}")
    pseudo = list(map(float, x))
    for _ in range(h):
        window = np.asarray(pseudo[-w:], float)
        if len(window) != w:
            raise EngineFailure("ROLL_WINDOW_UNAVAILABLE")
        out = gm_fit_forecast(window, 1, 0.5)
        pseudo.append(float(out.forecast[0]))
    # Fitted values are not a single static fitted path under rolling; retain NaN-free
    # source-scale placeholders from the original history for diagnostics only.
    return ModelOutput(
        forecast=np.asarray(pseudo[-h:], float),
        fitted=x.copy(),
        params={"w": 4, "alpha_bg": 0.5},
        diagnostics={"recursive_refits": int(h), "fitted_semantics": "observed_history_placeholder"},
    )


# ---------------------------------------------------------------------------
# SG08 — average WBO + GM endpoint convention
# ---------------------------------------------------------------------------

def average_wbo(x: Iterable[float]) -> np.ndarray:
    x = _as_series(x)
    suffix = np.cumsum(x[::-1])[::-1]
    counts = np.arange(len(x), 0, -1, dtype=float)
    out = suffix / counts
    if not np.all(np.isfinite(out)):
        raise EngineFailure("WBO_NONFINITE")
    tol = 1e-12 * max(1.0, abs(float(x[-1])))
    if abs(float(out[-1]) - float(x[-1])) > tol:
        raise EngineFailure("WBO_FIXED_POINT_FAIL")
    return out


def wbo_gm_forecast(x: Iterable[float], h: int) -> ModelOutput:
    x = _as_series(x, 4)
    pseudo = list(map(float, x))
    for _ in range(h):
        d = average_wbo(np.asarray(pseudo, float))
        gm = gm_fit_forecast(d, 1, 0.5)
        pseudo.append(float(gm.forecast[0]))
    return ModelOutput(
        forecast=np.asarray(pseudo[-h:], float),
        fitted=x.copy(),
        params={"operator": "average_suffix_WBO", "alpha_bg": 0.5},
        diagnostics={
            "recursive_refits": int(h),
            "output_scale": "AutoGrey endpoint convention on original scale",
        },
    )


# ---------------------------------------------------------------------------
# SG09 — Grey-Markov
# ---------------------------------------------------------------------------

def _state_edges(resid: np.ndarray, S: int, boundary: str) -> np.ndarray:
    resid = np.asarray(resid, float)
    if S < 2:
        raise EngineFailure("MARKOV_S_DOMAIN")
    rmin, rmax = float(np.min(resid)), float(np.max(resid))
    eps = 1e-12 * max(float(np.mean(np.abs(resid))), 1.0)
    if rmax - rmin <= eps:
        raise EngineFailure("MARKOV_RESIDUAL_RANGE_DEGENERATE")
    if boundary == "EQW":
        edges = np.linspace(rmin, rmax, S + 1)
    elif boundary == "EQT":
        edges = np.quantile(resid, np.linspace(0.0, 1.0, S + 1), method="linear")
        if np.any(np.diff(edges) <= eps):
            raise EngineFailure("MARKOV_EQT_DUPLICATE_BOUNDARY")
    else:
        raise EngineFailure("MARKOV_BOUNDARY_UNKNOWN")
    return np.asarray(edges, float)


def _assign_states(values: np.ndarray, edges: np.ndarray) -> np.ndarray:
    # Internal boundaries belong to the upper/right interval. Max goes to S-1.
    return np.searchsorted(edges[1:-1], values, side="right").astype(int)


def _transition_matrix(states: np.ndarray, S: int, lag: int = 1) -> tuple[np.ndarray, np.ndarray]:
    states = np.asarray(states, int)
    counts = np.zeros((S, S), dtype=int)
    origins = np.zeros(S, dtype=int)
    if lag < 1 or len(states) <= lag:
        return np.full((S,S), np.nan), origins
    for i in range(len(states) - lag):
        a, b = int(states[i]), int(states[i + lag])
        counts[a, b] += 1
        origins[a] += 1
    P = np.full((S, S), np.nan, dtype=float)
    for i in range(S):
        if origins[i] > 0:
            P[i] = counts[i] / origins[i]
    return P, origins


def _resolve_markov_next_state(states: np.ndarray, S: int, current: int) -> tuple[int, int]:
    # Primary one-step probabilities.
    P1, origins = _transition_matrix(states, S, 1)
    if origins[current] < 2:
        raise EngineFailure("MARKOV_CURRENT_OUTGOING_TOO_FEW", f"state={current},count={origins[current]}")
    row = P1[current]
    if not np.all(np.isfinite(row)) or abs(float(np.sum(row)) - 1.0) > MARKOV_ROW_TOL:
        raise EngineFailure("MARKOV_ROW_NOT_STOCHASTIC")
    mx = float(np.max(row))
    tied = np.where(np.isclose(row, mx, atol=1e-15, rtol=0.0))[0]
    if len(tied) == 1:
        return int(tied[0]), 1

    # Source-inspired predeclared higher-lag evidence: first direct lag that
    # uniquely separates the tied candidate states. No matrix powers/smoothing.
    for lag in range(2, len(states)):
        Pm, om = _transition_matrix(states, S, lag)
        if om[current] <= 0 or not np.all(np.isfinite(Pm[current])):
            continue
        vals = Pm[current, tied]
        vmax = float(np.max(vals))
        winners = tied[np.where(np.isclose(vals, vmax, atol=1e-15, rtol=0.0))[0]]
        if len(winners) == 1:
            return int(winners[0]), lag
    raise EngineFailure("MARKOV_TIE_UNRESOLVED", f"state={current}, tied={tied.tolist()}")


def greymarkov_fit_forecast(x: Iterable[float], h: int, S: int, boundary: str) -> ModelOutput:
    x = _as_series(x, 6)
    S = int(S)
    if S > min(4, (len(x) - 1) // 2):
        raise EngineFailure("MARKOV_S_CAP", f"S={S},n={len(x)}")
    gm = gm_fit_forecast(x, h, 0.5)
    resid = x - gm.fitted
    edges = _state_edges(resid, S, boundary)
    states = _assign_states(resid, edges)

    occupied = np.unique(states)
    P1, origins = _transition_matrix(states, S, 1)
    for st in occupied:
        if origins[st] < 2:
            raise EngineFailure("MARKOV_OUTGOING_TOO_FEW", f"state={int(st)},count={int(origins[st])}")
        if not np.all(np.isfinite(P1[st])) or abs(float(np.sum(P1[st])) - 1.0) > MARKOV_ROW_TOL:
            raise EngineFailure("MARKOV_ROW_NOT_STOCHASTIC", f"state={int(st)}")

    mids = 0.5 * (edges[:-1] + edges[1:])
    current = int(states[-1])
    corrected = []
    tie_lags = []
    for j in range(h):
        nxt, used_lag = _resolve_markov_next_state(states, S, current)
        tie_lags.append(int(used_lag))
        corrected.append(float(gm.forecast[j] + mids[nxt]))
        current = nxt
    corrected = np.asarray(corrected, float)
    if not np.all(np.isfinite(corrected)):
        raise EngineFailure("MARKOV_FORECAST_NONFINITE")
    return ModelOutput(
        forecast=corrected,
        fitted=gm.fitted.copy(),
        params={"S": S, "boundary": boundary, "edges": edges.tolist()},
        diagnostics={
            "base_gm_params": gm.params,
            "state_counts": {int(s): int(np.sum(states == s)) for s in occupied},
            "outgoing_counts": {int(s): int(origins[s]) for s in occupied},
            "tie_resolution_lags": tie_lags,
            "states": states.tolist(),
        },
    )


# ---------------------------------------------------------------------------
# SG10 — seasonal GM
# ---------------------------------------------------------------------------

def seasonal_factors(x: Iterable[float], M: int) -> np.ndarray:
    x = _as_series(x)
    M = int(M)
    if M < 2:
        raise EngineFailure("SEASON_M_INVALID")
    if len(x) < 2 * M:
        raise EngineFailure("SEASON_PHASE_COUNT_TOO_FEW", f"n={len(x)},M={M}")
    means = []
    for s in range(M):
        vals = x[s::M]
        if len(vals) < 2:
            raise EngineFailure("SEASON_PHASE_COUNT_TOO_FEW", f"phase={s},count={len(vals)}")
        means.append(float(np.mean(vals)))
    overall = float(np.mean(x))
    eps = 1e-12 * max(float(np.mean(np.abs(x))), 1.0)
    if not np.isfinite(overall) or abs(overall) <= eps:
        raise EngineFailure("SEASON_OVERALL_MEAN_INVALID")
    factors = np.asarray(means, float) / overall
    if not np.all(np.isfinite(factors)) or np.any(factors <= 0):
        raise EngineFailure("SEASON_FACTOR_INVALID")
    if float(np.max(np.abs(factors - 1.0))) <= SEASON_REDUCTION_TOL:
        raise EngineFailure("SEASON_GM_REDUCTION")
    return factors


def sgm_fit_forecast(x: Iterable[float], h: int, M: int) -> ModelOutput:
    x = _as_series(x, max(4, 2 * int(M)))
    M = int(M)
    f = seasonal_factors(x, M)
    phase = np.arange(len(x)) % M
    u = x / f[phase]
    xs = np.cumsum(u)
    z = 0.5 * (xs[1:] + xs[:-1])
    B = np.column_stack([-z, np.ones(len(x) - 1)])
    theta, diag = _lstsq_checked(B, u[1:], failure_prefix="SGM")
    a, b = map(float, theta)
    xshat = _continuous_response_constant(float(xs[0]), a, b, len(x) + h)
    uhat = np.empty_like(xshat)
    uhat[0] = xshat[0]
    uhat[1:] = np.diff(xshat)
    all_phase = np.arange(len(x) + h) % M
    xhat = uhat * f[all_phase]
    if not np.all(np.isfinite(xhat)):
        raise EngineFailure("SEASON_RESTORE_NONFINITE")
    return ModelOutput(
        forecast=xhat[-h:].copy(),
        fitted=xhat[:len(x)].copy(),
        params={"a": a, "b": b, "M": M, "factors": f.tolist()},
        diagnostics=diag,
    )


# ---------------------------------------------------------------------------
# Reference tier (non-selectable)
# ---------------------------------------------------------------------------

def reference_forecasts(x: Iterable[float], h: int, M: Optional[int] = None) -> tuple[dict[str,np.ndarray],dict[str,str]]:
    x = _as_series(x)
    refs: dict[str,np.ndarray] = {}
    fails: dict[str,str] = {}

    refs["Naive"] = np.repeat(x[-1], h).astype(float)
    if len(x) >= 2:
        slope = (x[-1] - x[0]) / (len(x) - 1.0)
        refs["Drift"] = x[-1] + slope * np.arange(1, h + 1, dtype=float)
    else:
        fails["Drift"] = "REFERENCE_N_LT_2"

    if len(x) >= 6:
        try:
            from statsmodels.tsa.forecasting.theta import ThetaModel
            fit = ThetaModel(x, period=None, deseasonalize=False).fit()
            f = np.asarray(fit.forecast(h), float)
            if len(f) != h or not np.all(np.isfinite(f)):
                raise ValueError("invalid theta forecast")
            refs["Theta"] = f
        except Exception as e:
            fails["Theta"] = f"THETA_FAIL:{type(e).__name__}:{e}"
    else:
        fails["Theta"] = "REFERENCE_N_LT_6"

    if M is not None and int(M) >= 2:
        MM = int(M)
        if len(x) >= MM:
            # Map each phase to the most recent observed value of that phase.
            last_by_phase = {}
            for idx0 in range(len(x)):
                last_by_phase[idx0 % MM] = float(x[idx0])
            future = []
            for j in range(h):
                phase = (len(x) + j) % MM
                if phase not in last_by_phase:
                    raise EngineFailure("SEASONAL_NAIVE_PHASE_MISSING", f"phase={phase}")
                future.append(last_by_phase[phase])
            refs["SeasonalNaive"] = np.asarray(future, float)
        else:
            fails["SeasonalNaive"] = "REFERENCE_N_LT_M"
    return refs, fails


# ---------------------------------------------------------------------------
# Frozen within-group config generation and selection
# ---------------------------------------------------------------------------

def _all_subsets(degrees: tuple[int, ...]) -> list[tuple[int, ...]]:
    out = [()]
    for r in range(1, len(degrees) + 1):
        out.extend(tuple(c) for c in combinations(degrees, r))
    return out


def group_configs(group_id: str, n: int, h: int, M: Optional[int]) -> list[tuple[str,dict[str,Any]]]:
    origins = inner_origins(n, h)
    m_first = origins[0]
    if group_id == "SG01_CONT_GM":
        return [(f"alpha={a:.2f}", {"alpha": float(a)}) for a in GM_ALPHA_GRID]
    if group_id == "SG02_DISCRETE_POLY":
        Nmax = min(4, m_first - 4)
        if Nmax < 0:
            return []
        return [
            ("deg=" + ("empty" if not S else ".".join(map(str,S))), {"degrees": tuple(S)})
            for S in _all_subsets(tuple(range(1, Nmax + 1)))
        ]
    if group_id == "SG03_FRAC_LINEAR":
        return [(f"r={r:.1f}", {"r": float(r)}) for r in FGM_R_GRID]
    if group_id == "SG04_BERNOULLI":
        return [(f"gamma={g:g}", {"gamma": float(g)}) for g in NGBM_GAMMA_GRID]
    if group_id == "SG05_CONT_TIME_POLY":
        out = [(f"TP_alpha={a:g}", {"kind":"timepower","alpha":float(a)}) for a in TIMEPOWER_ALPHA_GRID]
        Hmax = min(4, m_first - 3)
        out += [(f"FOTP_order={p}", {"kind":"fotp","p_order":int(p)}) for p in range(2, Hmax + 1)]
        return out
    if group_id == "SG06_CONFORMABLE":
        return [(f"alpha={a:.1f}", {"alpha": float(a)}) for a in CFGM_ALPHA_GRID]
    if group_id == "SG07_ROLLING":
        return [("w=4", {"w":4})]
    if group_id == "SG08_WBO":
        return [("average_WBO", {})]
    if group_id == "SG09_GREY_MARKOV":
        Smax = min(4, (m_first - 1) // 2)
        return [(f"S={S}_{b}", {"S":S,"boundary":b})
                for S in range(2, Smax + 1) for b in ("EQW","EQT")]
    if group_id == "SG10_SEASONAL":
        if M is None:
            return []
        return [(f"M={int(M)}", {"M": int(M)})]
    raise EngineFailure("GROUP_UNKNOWN", group_id)


def _fit_config(group_id: str, x: np.ndarray, h: int, cfg: dict[str, Any], M: Optional[int]) -> ModelOutput:
    if group_id == "SG01_CONT_GM":
        return gm_fit_forecast(x, h, cfg["alpha"])
    if group_id == "SG02_DISCRETE_POLY":
        return dgpm_fit_forecast(x, h, cfg["degrees"])
    if group_id == "SG03_FRAC_LINEAR":
        return fgm_fit_forecast(x, h, cfg["r"])
    if group_id == "SG04_BERNOULLI":
        return ngbm_fit_forecast(x, h, cfg["gamma"])
    if group_id == "SG05_CONT_TIME_POLY":
        return (timepower_fit_forecast(x, h, cfg["alpha"])
                if cfg["kind"] == "timepower"
                else fotp_fit_forecast(x, h, cfg["p_order"]))
    if group_id == "SG06_CONFORMABLE":
        return cfgm_fit_forecast(x, h, cfg["alpha"])
    if group_id == "SG07_ROLLING":
        return rolling_gm_forecast(x, h, cfg["w"])
    if group_id == "SG08_WBO":
        return wbo_gm_forecast(x, h)
    if group_id == "SG09_GREY_MARKOV":
        return greymarkov_fit_forecast(x, h, cfg["S"], cfg["boundary"])
    if group_id == "SG10_SEASONAL":
        return sgm_fit_forecast(x, h, cfg["M"])
    raise EngineFailure("GROUP_UNKNOWN", group_id)


def _config_simplicity_key(group_id: str, score: ConfigScore) -> tuple:
    c = score.config
    L = score.mean_inner_mase
    cid = score.config_id
    if group_id == "SG01_CONT_GM":
        a = float(c["alpha"])
        return (0 if near(a,0.5,atol=1e-12,rtol=0) else 1, abs(a-0.5), L, cid)
    if group_id == "SG02_DISCRETE_POLY":
        S = tuple(c["degrees"])
        return (len(S), max(S) if S else 0, sum(S), L, cid)
    if group_id == "SG03_FRAC_LINEAR":
        return (L, float(c["r"]), cid)
    if group_id == "SG04_BERNOULLI":
        g = float(c["gamma"])
        return (0 if near(g,2.0,atol=1e-12,rtol=0) else 1, L, g, cid)
    if group_id == "SG05_CONT_TIME_POLY":
        if c["kind"] == "fotp":
            p = int(c["p_order"])
            params = p + 1
            return (params, 0, p, L, cid)
        return (3, 1, 999, L, cid)
    if group_id == "SG06_CONFORMABLE":
        return (L, float(c["alpha"]), cid)
    if group_id == "SG09_GREY_MARKOV":
        return (int(c["S"]), 0 if c["boundary"] == "EQW" else 1, L, cid)
    return (L, cid)


def _group_precheck(group_id: str, x: np.ndarray, h: int, M: Optional[int]) -> None:
    n = len(x)
    if n < h + 7:
        raise EngineFailure("GLOBAL_SELECTION_HISTORY_SHORT", f"n={n},h={h},requires>={h+7}")

    # 4F-B implementation finding derived from Step 4D: if seasonal MASE is
    # the common prospective loss, every earliest inner prefix must itself
    # contain at least M+1 observations to define the seasonal scale.
    if M is not None:
        MM = int(M)
        if MM < 2:
            raise EngineFailure("SEASON_M_INVALID")
        m_first = inner_origins(n,h)[0]
        if m_first <= MM:
            raise EngineFailure(
                "INNER_MASE_SCALE_HISTORY_SHORT",
                f"earliest_inner_n={m_first} must exceed M={MM}",
            )

    if group_id == "SG05_CONT_TIME_POLY" and inner_origins(n,h)[0] < 5:
        raise EngineFailure("GROUP_HISTORY_SHORT")
    if group_id == "SG09_GREY_MARKOV" and n < h + 8:
        raise EngineFailure("GROUP_HISTORY_SHORT", f"SG09 requires n>={h+8}")
    if group_id == "SG10_SEASONAL":
        if M is None:
            raise EngineFailure("SEASON_METADATA_MISSING")
        if int(M) < 2:
            raise EngineFailure("SEASON_M_INVALID")
        if inner_origins(n,h)[0] < 2 * int(M):
            raise EngineFailure("SEASON_PHASE_COUNT_TOO_FEW")


def select_group(x: Iterable[float], h: int, group_id: str, M: Optional[int] = None) -> GroupResult:
    x = _as_series(x)
    try:
        _group_precheck(group_id, x, h, M)
    except EngineFailure as e:
        return GroupResult(group_id=group_id, eligible=False, failure_code=e.code, failure_detail=e.detail)

    configs = group_configs(group_id, len(x), h, M)
    if not configs:
        return GroupResult(group_id=group_id, eligible=False, failure_code="NO_REGISTERED_CONFIG")

    origins = inner_origins(len(x), h)
    scores: list[ConfigScore] = []
    failures: dict[str,str] = {}

    for cid, cfg in configs:
        losses = []
        cfg_diag = {"origin_diagnostics": []}
        try:
            for m in origins:
                train = x[:m]
                val = x[m:m+h]
                out = _fit_config(group_id, train, h, cfg, M)
                L = mase(val, out.forecast, train, M)
                if not np.isfinite(L):
                    raise EngineFailure("INNER_LOSS_NONFINITE")
                losses.append(float(L))
                cfg_diag["origin_diagnostics"].append(out.diagnostics)
            if len(losses) != 3:
                raise EngineFailure("UNEQUAL_INNER_ORIGINS")
            scores.append(ConfigScore(
                config_id=cid,
                config=dict(cfg),
                mean_inner_mase=float(np.mean(losses)),
                origin_losses=tuple(float(v) for v in losses),
                diagnostics=cfg_diag,
            ))
        except EngineFailure as e:
            failures[cid] = f"{e.code}:{e.detail}"

    if not scores:
        return GroupResult(
            group_id=group_id, eligible=False, inner_scores=[],
            config_failures=failures, failure_code="NO_VALID_CONFIG",
            failure_detail="All frozen configurations failed at >=1 common origin."
        )

    Lmin = min(s.mean_inner_mase for s in scores)
    band = [s for s in scores if s.mean_inner_mase <= 1.05 * Lmin + 1e-15]
    chosen = min(band, key=lambda s: _config_simplicity_key(group_id, s))

    try:
        final = _fit_config(group_id, x, h, chosen.config, M)
    except EngineFailure as e:
        # No fallback to second-best config after the full-development refit
        # fails: that would be a different data-dependent selection rule.
        return GroupResult(
            group_id=group_id, eligible=False,
            selected_config_id=chosen.config_id,
            selected_config=chosen.config,
            inner_scores=scores, config_failures=failures,
            failure_code="FINAL_REFIT_FAIL",
            failure_detail=f"{e.code}:{e.detail}",
        )

    return GroupResult(
        group_id=group_id,
        eligible=True,
        selected_config_id=chosen.config_id,
        selected_config=chosen.config,
        forecast=final.forecast.copy(),
        fitted=final.fitted.copy(),
        inner_scores=scores,
        config_failures=failures,
        diagnostics={
            "Lmin": float(Lmin),
            "band_size": len(band),
            "selected_to_best_ratio": float(chosen.mean_inner_mase / max(Lmin, 1e-15)),
            "selected_inner_mase": float(chosen.mean_inner_mase),
            "config_count_registered": len(configs),
            "config_count_valid": len(scores),
            "final_model_diagnostics": final.diagnostics,
            "final_params": final.params,
            "common_origins": origins,
        },
    )


def run_portfolio(D: Iterable[float], h: int, M: Optional[int] = None) -> PortfolioResult:
    x = _as_series(D)
    h = int(h)
    if h < 1:
        raise EngineFailure("H_INVALID")
    if M is not None:
        M = int(M)

    results = {g: select_group(x, h, g, M) for g in GROUP_ORDER}

    # Forecast dedup BEFORE target access. Canonical group order is deterministic.
    retained: list[str] = []
    collisions: list[dict[str,Any]] = []
    for g in GROUP_ORDER:
        r = results[g]
        if not r.eligible or r.forecast is None:
            continue
        collided = False
        for keep in retained:
            d = normalized_forecast_distance(r.forecast, results[keep].forecast, x)
            if d <= COLLISION_TOL:
                collisions.append({
                    "owner": keep,
                    "removed": g,
                    "d_inf": float(d),
                    "at_1e4": bool(d <= COLLISION_SENSITIVITY[0]),
                    "at_1e2": bool(d <= COLLISION_SENSITIVITY[1]),
                })
                collided = True
                break
        if not collided:
            retained.append(g)

    refs, ref_fails = reference_forecasts(x, h, M)
    return PortfolioResult(
        engine_version=ENGINE_VERSION,
        n=len(x),
        h=h,
        M=M,
        group_results=results,
        distinct_groups=tuple(retained),
        collisions=tuple(collisions),
        reference_forecasts=refs,
        reference_failures=ref_fails,
        diagnostics={
            "eligible_pre_dedup": tuple(g for g in GROUP_ORDER if results[g].eligible),
            "eligible_post_dedup": tuple(retained),
            "collision_tol": COLLISION_TOL,
        },
    )


# ---------------------------------------------------------------------------
# Engineering/source regression fixtures
# ---------------------------------------------------------------------------

def run_self_tests() -> list[dict[str,Any]]:
    tests: list[dict[str,Any]] = []

    def check(name: str, condition: bool, detail: str = ""):
        if not condition:
            raise AssertionError(f"{name}: {detail}")
        tests.append({"test": name, "status": "PASS", "detail": detail})

    # 1. Fractional operator roundtrip remains general; selectable Wu-FGM v1
    #    is source-faithful 0<r<1 with c,d response correction.
    x = np.array([10.,11.,12.5,14.,16.,18.5,21.5,25.])
    for r in (0.1,0.5,0.9,1.0,1.4,2.0):
        xr = fractional_ago(x, r)
        xb = fractional_iago(xr, r)
        err = float(np.max(np.abs(xb-x)))
        check(f"fgm_roundtrip_r{r}", err < 1e-10, f"max_abs={err:.3e}")

    # At r=1 the accumulation/inverse operators reduce to ordinary AGO/IAGO,
    # but the v1 FGM model branch does not claim a second algorithmic GM vote.
    check("fgm_r1_operator_is_ago",
          np.max(np.abs(fractional_ago(x,1.0)-np.cumsum(x))) < 1e-12)
    check("fgm_r1_inverse_operator_identity",
          np.max(np.abs(fractional_iago(np.cumsum(x),1.0)-x)) < 1e-12)
    try:
        fgm_fit_forecast(x, 1, 1.0)
        check("fgm_r1_owned_by_sg01", False)
    except EngineFailure as e:
        check("fgm_r1_owned_by_sg01", e.code == "FGM_R_V1_DOMAIN", e.code)

    # Wu et al. 2013 Table 2. Train = 2001-2006, test = 2007-2009.
    # The printed r=0.3 column is reproduced to the printed 0.001 precision.
    x_wu = np.array([247.839,273.021,289.014,285.208,288.818,297.078])
    y_wu = np.array([293.662,290.404,279.143])
    wu03 = fgm_fit_forecast(x_wu, 3, 0.3)
    expected_wu03 = np.array([
        247.839,272.396,285.841,291.905,292.241,288.939,
        283.490,276.883,269.760
    ])
    got_wu03 = np.r_[wu03.fitted, wu03.forecast]
    check("fgm_wu2013_table2_r03_values",
          np.max(np.abs(got_wu03-expected_wu03)) < 5e-4,
          f"max_abs={np.max(np.abs(got_wu03-expected_wu03)):.3e}")
    fit_mape = float(np.mean(np.abs((x_wu-wu03.fitted)/x_wu))*100)
    test_mape = float(np.mean(np.abs((y_wu-wu03.forecast)/y_wu))*100)
    check("fgm_wu2013_table2_r03_fit_mape",
          abs(fit_mape-1.27) < 0.01, f"MAPE={fit_mape:.6f}")
    check("fgm_wu2013_table2_r03_test_mape",
          abs(test_mape-3.83) < 0.01, f"MAPE={test_mape:.6f}")

    # Same table: the r=1 column is exactly the ordinary anchored GM column.
    g_wu = gm_fit_forecast(x_wu, 3, 0.5)
    expected_gm1 = np.array([
        247.839,277.146,281.805,286.542,291.358,296.256,
        301.236,306.300,311.449
    ])
    got_gm1 = np.r_[g_wu.fitted,g_wu.forecast]
    check("wu2013_table2_r1_is_traditional_gm",
          np.max(np.abs(got_gm1-expected_gm1)) < 5e-4,
          f"max_abs={np.max(np.abs(got_gm1-expected_gm1)):.3e}")

    # 2. DGPM source fixture from Wei/Xie/Yang: N=2 fit first 6 predicts seventh.
    # The paper prints the sequence rounded to two decimals but derives the
    # closed-form coefficients from x(k)=exp(k)+5k+10. Use the exact generating
    # values here; fitting the rounded display values necessarily perturbs the
    # coefficients.
    kk = np.arange(1.0, 7.0)
    xdg = np.exp(kk) + 5.0 * kk + 10.0
    dg = dgpm_fit_forecast(xdg, 1, (1,2))
    check("dgpm_source_alpha", abs(dg.params["alpha"] - 1.718282) < 5e-5,
          f"alpha={dg.params['alpha']:.6f}")
    check("dgpm_source_beta0", abs(dg.params["beta0"] - 29.901100) < 5e-4,
          f"beta0={dg.params['beta0']:.6f}")
    check("dgpm_source_beta1", abs(dg.params["beta"][1] - (-7.887114)) < 5e-4,
          f"beta1={dg.params['beta'][1]:.6f}")
    check("dgpm_source_beta2", abs(dg.params["beta"][2] - (-4.295705)) < 5e-4,
          f"beta2={dg.params['beta'][2]:.6f}")
    exact7 = float(np.exp(7.0) + 5.0 * 7.0 + 10.0)
    check("dgpm_source_forecast", abs(dg.forecast[0] - exact7) < 1e-8,
          f"forecast={dg.forecast[0]:.9f}, exact={exact7:.9f}")

    # 3. NGBM reductions: gamma=0 -> GM; gamma=2 is valid named Verhulst path.
    g = gm_fit_forecast(x, 3, 0.5)
    ng0 = ngbm_fit_forecast(x, 3, 0.0)
    dist0 = normalized_forecast_distance(g.forecast, ng0.forecast, x)
    check("ngbm_gamma0_gm_identity", dist0 < 1e-10, f"d_inf={dist0:.3e}")
    ng2 = ngbm_fit_forecast(x, 3, 2.0)
    check("ngbm_gamma2_finite", np.all(np.isfinite(ng2.forecast)))
    try:
        ngbm_fit_forecast(x, 1, 1.0)
        check("ngbm_gamma1_rejected", False)
    except EngineFailure as e:
        check("ngbm_gamma1_rejected", e.code == "NGBM_GAMMA_ONE_SINGULAR", e.code)

    # 4. SG05 exact affine duplicate: time-power alpha=1 and FOTP order=2.
    tp1 = timepower_fit_forecast(x, 3, 1.0)
    fp2 = fotp_fit_forecast(x, 3, 2)
    d_aff = normalized_forecast_distance(tp1.forecast, fp2.forecast, x)
    check("sg05_affine_parameterizations_equivalent", d_aff < 1e-8, f"d_inf={d_aff:.3e}")

    # 5. CFGM source operator/parameter fixture.
    xc = np.array([55.7,59.0,62.7,61.3,61.4])
    cfa = conformable_cfa(xc, 0.59)
    expected = np.array([55.7000,100.1048,140.0668,174.7897,206.5285])
    check("cfgm_source_cfa", np.max(np.abs(cfa-expected)) < 1e-3,
          f"max_abs={np.max(np.abs(cfa-expected)):.3e}")
    cb = conformable_cfd(cfa, 0.59)
    check("cfgm_roundtrip_059", np.max(np.abs(cb-xc)) < 1e-10,
          f"max_abs={np.max(np.abs(cb-xc)):.3e}")
    cm = cfgm_fit_forecast(xc, 1, 0.59)
    check("cfgm_source_a", abs(cm.params["a"] - 0.115230) < 5e-5, f"a={cm.params['a']:.6f}")
    check("cfgm_source_b", abs(cm.params["b"] - 53.438214) < 5e-4, f"b={cm.params['b']:.6f}")
    c1 = cfgm_fit_forecast(x, 3, 1.0)
    d_c1 = normalized_forecast_distance(g.forecast, c1.forecast, x)
    check("cfgm_alpha1_gm_identity", d_c1 < 1e-10, f"d_inf={d_c1:.3e}")

    # 6. WBO fixed point and recursive forecast.
    d = average_wbo(x)
    check("wbo_fixed_point", abs(d[-1]-x[-1]) < 1e-12)
    wf = wbo_gm_forecast(x, 3)
    check("wbo_recursive_finite", len(wf.forecast)==3 and np.all(np.isfinite(wf.forecast)))

    # 7. Rolling GM exactly uses w=4 recursively.
    rg = rolling_gm_forecast(x, 3, 4)
    check("rolling_recursive_finite", len(rg.forecast)==3 and np.all(np.isfinite(rg.forecast)))
    try:
        rolling_gm_forecast(x, 1, 5)
        check("rolling_no_silent_other_window", False)
    except EngineFailure as e:
        check("rolling_no_silent_other_window", e.code == "ROLL_WINDOW_NOT_V1", e.code)

    # 8. Seasonal factor deterministic fixture and all-one reduction rejection.
    xs = np.array([8.,11.,14.,9., 8.4,11.5,14.7,9.3, 8.8,12.,15.4,9.7])
    sf = seasonal_factors(xs, 4)
    check("seasonal_factors_mean_one", abs(np.mean(sf)-1.0) < 1e-12, f"mean={np.mean(sf):.12f}")
    sm = sgm_fit_forecast(xs, 2, 4)
    check("sgm_finite", len(sm.forecast)==2 and np.all(np.isfinite(sm.forecast)))

    # Wang, Li & Pei (2018) quarterly primary-industry electricity fixture.
    sgm_train = np.array([
        19.0,26.1,31.5,21.8,
        19.5,28.0,32.0,22.0,
        19.0,27.5,33.0,21.8,
        18.9,27.2,31.5,23.8,
        17.4,26.1,34.8,21.1
    ])
    sgm_test = np.array([17.1,27.0,36.5,21.4,18.4,29.1,37.0,23.0])
    sgm_src = sgm_fit_forecast(sgm_train, 8, 4)
    fsrc = np.asarray(sgm_src.params["factors"])
    expected_f = np.array([0.74741036,1.07490040,1.29721116,0.88047809])
    check("sgm_2018_seasonal_factors",
          np.max(np.abs(fsrc-expected_f)) < 5e-8,
          f"max_abs={np.max(np.abs(fsrc-expected_f)):.3e}")
    check("sgm_2018_a",
          abs(sgm_src.params["a"] - (-3.63356e-05)) < 5e-8,
          f"a={sgm_src.params['a']:.9g}")
    check("sgm_2018_b",
          abs(sgm_src.params["b"] - 25.0735) < 5e-4,
          f"b={sgm_src.params['b']:.7f}")
    sgm_mape = float(np.mean(np.abs((sgm_test-sgm_src.forecast)/sgm_test))*100)
    check("sgm_2018_holdout_mape",
          abs(sgm_mape-6.13) < 0.01, f"MAPE={sgm_mape:.6f}")

    gm_src = gm_fit_forecast(sgm_train, 8, 0.5)
    expected_gm_forecast = np.array([
        25.17,25.14,25.12,25.09,25.06,25.04,25.01,24.99
    ])
    check("gm_2018_table5_forecast",
          np.max(np.abs(np.round(gm_src.forecast,2)-expected_gm_forecast)) < 1e-12,
          f"forecast={np.round(gm_src.forecast,2).tolist()}")
    flat_phase = np.array([10.,10.,10.,10.,11.,11.,11.,11.])
    try:
        seasonal_factors(flat_phase, 4)
        check("seasonal_all_one_reduction_rejected", False)
    except EngineFailure as e:
        check("seasonal_all_one_reduction_rejected", e.code == "SEASON_GM_REDUCTION", e.code)

    # 9. Grey-Markov engineered series: test partition mechanics/failure explicitness.
    xmk = np.array([10,12,11,14,13,16,15,18,17,20,19,22,21,24,23,26,25], dtype=float)
    # Candidate may or may not be valid under strict transition counts; either finite or explicit EngineFailure.
    try:
        mk = greymarkov_fit_forecast(xmk, 2, 2, "EQW")
        check("greymarkov_explicit_result", np.all(np.isfinite(mk.forecast)))
    except EngineFailure as e:
        check("greymarkov_explicit_result", e.code.startswith("MARKOV_"), e.code)

    # 10. Inner origins + seasonal MASE derived history correction.
    check("inner_origins_n12_h5", inner_origins(12,5) == (5,6,7), str(inner_origins(12,5)))
    rshort = select_group(np.arange(1., 18.), 3, "SG01_CONT_GM", M=12)
    check("seasonal_inner_mase_history_gate",
          (not rshort.eligible and rshort.failure_code == "INNER_MASE_SCALE_HISTORY_SHORT"),
          f"{rshort.failure_code}:{rshort.failure_detail}")

    # 11. Full group tuner: one group -> one forecast and exactly 3 origin losses per valid config.
    xlong = 50.0 * (1.03 ** np.arange(18))
    gr = select_group(xlong, 3, "SG01_CONT_GM")
    check("sg01_group_eligible", gr.eligible, f"{gr.failure_code}:{gr.failure_detail}")
    check("sg01_one_final_forecast", gr.forecast is not None and len(gr.forecast)==3)
    check("sg01_three_origin_losses", all(len(s.origin_losses)==3 for s in gr.inner_scores))

    # 12. Public engine chronology/API contract.
    import inspect
    sig = inspect.signature(run_portfolio)
    check("portfolio_api_has_no_target_argument",
          tuple(sig.parameters.keys()) == ("D","h","M"),
          str(sig))
    check("sg03_frozen_grid_count_9", len(FGM_R_GRID) == 9, str(FGM_R_GRID))
    check("sg03_frozen_grid_source_reproducible_domain",
          min(FGM_R_GRID) == 0.1 and max(FGM_R_GRID) == 0.9)

    # Portfolio never passes a target; collision/dedup outputs are finite.
    port = run_portfolio(xlong, 3)
    check("portfolio_engine_version", port.engine_version == ENGINE_VERSION)
    check("portfolio_distinct_subset",
          set(port.distinct_groups).issubset(set(port.diagnostics["eligible_pre_dedup"])))
    check("references_nonselectable_present", "Naive" in port.reference_forecasts)

    return tests


if __name__ == "__main__":
    import json
    out = run_self_tests()
    print(json.dumps({
        "engine_version": ENGINE_VERSION,
        "tests_passed": len(out),
        "results": out,
    }, indent=2))


# ===== P11 FAST FRACTIONAL HELPER =====
import numpy as np

FAST_THRESHOLD = 1024

def _next_pow2(n: int) -> int:
    if n <= 1:
        return 1
    return 1 << (int(n - 1).bit_length())

def fractional_weights_fast(r: float, n: int) -> np.ndarray:
    r = float(r)
    n = int(n)
    if n < 1:
        raise ValueError("n must be >=1")
    w = np.empty(n, dtype=np.float64)
    w[0] = 1.0
    for j in range(1, n):
        w[j] = w[j - 1] * (r + j - 1.0) / j
    if not np.all(np.isfinite(w)):
        raise FloatingPointError("fractional weight nonfinite")
    return w

def linear_convolve_fft_prefix(x, w, nout=None) -> np.ndarray:
    x = np.asarray(x, dtype=np.float64).reshape(-1)
    w = np.asarray(w, dtype=np.float64).reshape(-1)
    if len(x) == 0 or len(w) == 0:
        raise ValueError("nonempty vectors required")
    need = len(x) + len(w) - 1
    L = _next_pow2(need)
    z = np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(w, L), L)[:need]
    if nout is None:
        return z
    return z[:int(nout)]

def fractional_ago_fft(x, r: float) -> np.ndarray:
    x = np.asarray(x, dtype=np.float64).reshape(-1)
    if len(x) < 1 or not np.all(np.isfinite(x)):
        raise ValueError("finite nonempty x required")
    w = fractional_weights_fast(float(r), len(x))
    out = linear_convolve_fft_prefix(x, w, len(x))
    if not np.all(np.isfinite(out)):
        raise FloatingPointError("operator output nonfinite")
    return out

def fractional_ago_hybrid(x, r: float, threshold: int = FAST_THRESHOLD) -> np.ndarray:
    x = np.asarray(x, dtype=np.float64).reshape(-1)
    if len(x) < 1 or not np.all(np.isfinite(x)):
        raise ValueError("finite nonempty x required")
    w = fractional_weights_fast(float(r), len(x))
    if len(x) <= int(threshold):
        out = np.convolve(x, w)[:len(x)]
    else:
        out = linear_convolve_fft_prefix(x, w, len(x))
    if not np.all(np.isfinite(out)):
        raise FloatingPointError("operator output nonfinite")
    return out



# ============================================================
# P11-A2C2 SG03 long-series implementation candidate
# Short path <=1024 calls the exact canonical fractional_ago.
# Long path uses the previously qualified FFT linear convolution.
# ============================================================

_fractional_ago_p11_canonical = fractional_ago
_AG_P11_FAST_THRESHOLD = 1024

def fractional_ago(x, r):
    arr = np.asarray(x, dtype=np.float64).reshape(-1)
    if len(arr) <= _AG_P11_FAST_THRESHOLD:
        return _fractional_ago_p11_canonical(arr, r)
    return fractional_ago_fft(arr, r)

