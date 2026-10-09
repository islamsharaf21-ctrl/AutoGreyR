import csv
import dataclasses
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

meta_path = Path(sys.argv[1])
values_path = Path(sys.argv[2])
new_path = Path(sys.argv[3])
engdir = Path(sys.argv[4])
out_path = Path(sys.argv[5])
summary_path = Path(sys.argv[6])

sys.path.insert(0, str(engdir))

import autogrey_engine_step4fb_r1 as eng

LEGACY = [
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

NEW = ["SG11","SG12","SG13"]

with open(meta_path, newline="", encoding="utf-8-sig") as f:
    meta = list(csv.DictReader(f))

with open(values_path, newline="", encoding="utf-8-sig") as f:
    vals = list(csv.DictReader(f))

with open(new_path, newline="", encoding="utf-8-sig") as f:
    new_rows = list(csv.DictReader(f))

assert len(meta) == 2596
assert len({r["parent_id"] for r in meta}) == 2596

# ------------------------------------------------------------
# Materialized D vectors
# ------------------------------------------------------------
dmap = defaultdict(list)

for r in vals:
    if r["part"] == "D":
        dmap[r["parent_id"]].append(
            (
                int(r["position"]),
                float(r["value"])
            )
        )

for pid in dmap:
    dmap[pid].sort()
    dmap[pid] = np.asarray(
        [v for _,v in dmap[pid]],
        dtype=np.float64
    )

# ------------------------------------------------------------
# Selected new forecasts
# ------------------------------------------------------------
newmap = defaultdict(list)

for r in new_rows:
    key = (r["parent_id"], r["group"])

    newmap[key].append(
        (
            int(r["step"]),
            float(r["forecast"])
        )
    )

for key in list(newmap):
    newmap[key].sort()
    newmap[key] = np.asarray(
        [v for _,v in newmap[key]],
        dtype=np.float64
    )

expected_new = {
    "SG11":2511,
    "SG12":2550,
    "SG13":2579,
}

for g,n in expected_new.items():
    got = sum(
        1 for (pid,gg) in newmap
        if gg == g
    )
    assert got == n, (g, got, n)

# ------------------------------------------------------------
# Strict legacy forecast extractor
# ------------------------------------------------------------
def direct_forecast(obj, h):

    if obj is None:
        return None, "MISSING_GROUP_RESULT"

    if dataclasses.is_dataclass(obj):

        names = {
            f.name
            for f in dataclasses.fields(obj)
        }

        if "forecast" not in names:
            raise RuntimeError(
                "Legacy group result dataclass lacks direct "
                "forecast field. TYPE=" +
                type(obj).__name__ +
                " FIELDS=" +
                ",".join(sorted(names))
            )

        fc = getattr(obj, "forecast")

    elif isinstance(obj, dict):

        if "forecast" not in obj:
            raise RuntimeError(
                "Legacy group result dict lacks forecast key. "
                "KEYS=" +
                ",".join(sorted(map(str,obj.keys())))
            )

        fc = obj["forecast"]

    else:
        raise RuntimeError(
            "Unsupported legacy group result type: " +
            type(obj).__name__
        )

    if fc is None:
        return None, "NO_FORECAST"

    try:
        arr = np.asarray(fc, dtype=np.float64).reshape(-1)
    except Exception:
        return None, "FORECAST_CAST_FAIL"

    if len(arr) != h:
        return None, "FORECAST_LENGTH_FAIL"

    if not np.all(np.isfinite(arr)):
        return None, "FORECAST_NONFINITE"

    return arr, "OK"

# ------------------------------------------------------------
# Full SG01-SG10 x SG11-SG13 census
# ------------------------------------------------------------
rows = []

legacy_ok = Counter()
legacy_fail = Counter()

comparisons = 0
parents_with_primary = set()

pair_primary = Counter()
new_primary = Counter()
legacy_primary = Counter()

for i,m in enumerate(meta, 1):

    pid = m["parent_id"]
    h = int(m["h"])

    Mtxt = (m.get("M") or "").strip()

    M = None
    if Mtxt:
        M = int(float(Mtxt))

    D = dmap[pid]

    if len(D) != int(m["development_n"]):
        raise RuntimeError(
            "D length mismatch: " + pid
        )

    z = eng.run_portfolio(D, h, M)

    if not hasattr(z, "group_results"):
        raise RuntimeError(
            "PortfolioResult lacks group_results"
        )

    gresults = z.group_results

    legacy_fc = {}

    for lg in LEGACY:

        if lg not in gresults:
            legacy_fail[(lg,"MISSING_KEY")] += 1
            continue

        fc,status = direct_forecast(
            gresults[lg],
            h
        )

        if fc is None:
            legacy_fail[(lg,status)] += 1
        else:
            legacy_ok[lg] += 1
            legacy_fc[lg] = fc

    denom = max(
        float(np.mean(np.abs(D))),
        1e-12
    )

    for ng in NEW:

        nf = newmap.get((pid,ng))

        if nf is None:
            continue

        if len(nf) != h:
            raise RuntimeError(
                "New forecast length mismatch: " +
                pid + " " + ng
            )

        for lg,lf in legacy_fc.items():

            d = float(
                np.max(np.abs(lf-nf)) /
                denom
            )

            c4 = d <= 1e-4
            c3 = d <= 1e-3
            c2 = d <= 1e-2

            comparisons += 1

            if c3:
                parents_with_primary.add(pid)
                pair_primary[(lg,ng)] += 1
                legacy_primary[lg] += 1
                new_primary[ng] += 1

            rows.append({
                "parent_id":pid,
                "legacy_group":lg,
                "new_group":ng,
                "d_inf":format(d, ".17g"),
                "collision_1e4":"TRUE" if c4 else "FALSE",
                "collision_1e3":"TRUE" if c3 else "FALSE",
                "collision_1e2":"TRUE" if c2 else "FALSE",
            })

    if i % 100 == 0 or i == len(meta):
        print(
            f"P4F3D1_PROGRESS={i}/{len(meta)}",
            flush=True
        )

fields = [
    "parent_id",
    "legacy_group",
    "new_group",
    "d_inf",
    "collision_1e4",
    "collision_1e3",
    "collision_1e2",
]

with open(out_path, "w", newline="", encoding="utf-8") as f:

    w = csv.DictWriter(
        f,
        fieldnames=fields,
        lineterminator="\n"
    )

    w.writeheader()
    w.writerows(rows)

c4 = sum(
    r["collision_1e4"] == "TRUE"
    for r in rows
)

c3 = sum(
    r["collision_1e3"] == "TRUE"
    for r in rows
)

c2 = sum(
    r["collision_1e2"] == "TRUE"
    for r in rows
)

lines = [
    "AUTOGREY V2 P4-F3D1 LEGACY-NEW COLLISION CENSUS R2",
    "===================================================",
    "",
    "ACTIONABLE_PARENTS=2596",
    "LEGACY_GROUPS=10",
    "NEW_GROUPS=3",
    f"CROSS_PAIR_COMPARISONS={comparisons}",
    "",
]

for lg in LEGACY:
    lines.append(
        f"{lg}_FORECAST_OK={legacy_ok[lg]}"
    )

lines.extend([
    "",
    f"LEGACY_NEW_COLLISION_1E4={c4}",
    f"LEGACY_NEW_COLLISION_1E3={c3}",
    f"LEGACY_NEW_COLLISION_1E2={c2}",
    f"PARENTS_WITH_PRIMARY_1E3_COLLISION={len(parents_with_primary)}",
    "",
    "PRIMARY_1E3_BY_NEW_GROUP:",
])

for ng in NEW:
    lines.append(
        f"{ng}={new_primary[ng]}"
    )

lines.append("")
lines.append("PRIMARY_1E3_BY_LEGACY_GROUP:")

for lg in LEGACY:
    lines.append(
        f"{lg}={legacy_primary[lg]}"
    )

lines.append("")
lines.append("PRIMARY_1E3_BY_PAIR:")

for lg in LEGACY:
    for ng in NEW:
        n = pair_primary[(lg,ng)]
        if n:
            lines.append(
                f"{lg}|{ng}={n}"
            )

lines.extend([
    "",
    "COLLISION_PRIMARY_THRESHOLD=1e-3",
    "COLLISION_SENSITIVITY_LOW=1e-4",
    "COLLISION_SENSITIVITY_HIGH=1e-2",
    "SELECTOR_TRAINING_PERFORMED=FALSE",
    "FEATURE_GOVERNANCE_CHANGED=FALSE",
    "REALBENCH3_TARGETS_OPENED=FALSE",
    "",
    "P4F3D1_R2_LEGACY_NEW_COLLISION_CENSUS=PASS",
])

summary_path.write_text(
    "\n".join(lines) + "\n",
    encoding="utf-8"
)

print("\n".join(lines))
