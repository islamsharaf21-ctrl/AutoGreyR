import csv
import dataclasses
import sys
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path

import numpy as np

meta_path = Path(sys.argv[1])
values_path = Path(sys.argv[2])
new_path = Path(sys.argv[3])
engdir = Path(sys.argv[4])

ledger_path = Path(sys.argv[5])
edges_path = Path(sys.argv[6])
parents_path = Path(sys.argv[7])
summary_path = Path(sys.argv[8])

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

NEW = ["SG11", "SG12", "SG13"]

ALL = LEGACY + NEW

def sg_index(g):
    return int(g[2:4])

def pair_class(a,b):
    al = a in LEGACY
    bl = b in LEGACY

    if al and bl:
        return "LEGACY_LEGACY"
    if (al and not bl) or (bl and not al):
        return "LEGACY_NEW"
    return "NEW_NEW"

def owner_for_collision(a,b):
    # P4D frozen unexpected-collision priority:
    # existing SG01-SG10 beats new SG11-SG13;
    # otherwise lower SG index.
    #
    # Exact-reduction configurations were already removed before
    # within-group scoring, so this stage resolves only unexpected
    # empirical forecast collisions.
    a_legacy = a in LEGACY
    b_legacy = b in LEGACY

    if a_legacy and not b_legacy:
        return a,b

    if b_legacy and not a_legacy:
        return b,a

    if sg_index(a) < sg_index(b):
        return a,b

    return b,a


with open(meta_path, newline="", encoding="utf-8-sig") as f:
    meta = list(csv.DictReader(f))

assert len(meta) == 2596
assert len({r["parent_id"] for r in meta}) == 2596


# ------------------------------------------------------------
# D vectors only. Development targets Y are not used.
# ------------------------------------------------------------
dmap = defaultdict(list)

with open(values_path, newline="", encoding="utf-8-sig") as f:

    for r in csv.DictReader(f):

        if r["part"] != "D":
            continue

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
# Canonical R2 selected new forecasts
# ------------------------------------------------------------
newmap = defaultdict(list)

with open(new_path, newline="", encoding="utf-8-sig") as f:

    for r in csv.DictReader(f):

        key = (
            r["parent_id"],
            r["group"]
        )

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
        1 for pid,gg in newmap
        if gg == g
    )

    assert got == n, (g,got,n)


def direct_forecast(obj,h):

    if obj is None:
        return None

    if dataclasses.is_dataclass(obj):

        names = {
            f.name for f in dataclasses.fields(obj)
        }

        if "forecast" not in names:
            raise RuntimeError(
                "Legacy dataclass has no forecast: " +
                type(obj).__name__
            )

        fc = getattr(obj,"forecast")

    elif isinstance(obj,dict):

        if "forecast" not in obj:
            raise RuntimeError(
                "Legacy dictionary has no forecast"
            )

        fc = obj["forecast"]

    else:
        raise RuntimeError(
            "Unsupported legacy result type: " +
            type(obj).__name__
        )

    if fc is None:
        return None

    try:
        fc = np.asarray(
            fc,
            dtype=np.float64
        ).reshape(-1)
    except Exception:
        return None

    if len(fc) != h:
        return None

    if not np.all(np.isfinite(fc)):
        return None

    return fc


edge_rows = []
ledger_rows = []
parent_rows = []

comparison_count = Counter()
collision4 = Counter()
collision3 = Counter()
collision2 = Counter()

parents_with_primary = set()

removed_occurrences = Counter()
retained_occurrences = Counter()
available_occurrences = Counter()

resolution_counts = Counter()

legacy_ok = Counter()


for ii,m in enumerate(meta,1):

    pid = m["parent_id"]
    h = int(m["h"])

    Mtxt = (m.get("M") or "").strip()

    M = None if not Mtxt else int(float(Mtxt))

    D = dmap[pid]

    if len(D) != int(m["development_n"]):
        raise RuntimeError(
            "D length mismatch: " + pid
        )

    portfolio = eng.run_portfolio(
        D,
        h,
        M
    )

    forecasts = {}

    for g in LEGACY:

        z = portfolio.group_results.get(g)

        fc = direct_forecast(z,h)

        if fc is not None:
            forecasts[g] = fc
            legacy_ok[g] += 1

    for g in NEW:

        fc = newmap.get((pid,g))

        if fc is not None:

            if len(fc) != h:
                raise RuntimeError(
                    "New forecast length mismatch: " +
                    pid + " " + g
                )

            forecasts[g] = fc

    available = [
        g for g in ALL
        if g in forecasts
    ]

    for g in available:
        available_occurrences[g] += 1

    denom = max(
        float(np.mean(np.abs(D))),
        1e-12
    )

    # Groups that lose at least one primary collision are
    # non-selectable under the frozen pairwise owner rule.
    lost_to = defaultdict(set)

    for a,b in combinations(available,2):

        d = float(
            np.max(
                np.abs(
                    forecasts[a] -
                    forecasts[b]
                )
            ) / denom
        )

        cls = pair_class(a,b)

        comparison_count[cls] += 1

        c4 = d <= 1e-4
        c3 = d <= 1e-3
        c2 = d <= 1e-2

        collision4[cls] += int(c4)
        collision3[cls] += int(c3)
        collision2[cls] += int(c2)

        if c3:

            parents_with_primary.add(pid)

            owner,loser = owner_for_collision(a,b)

            lost_to[loser].add(owner)

            edge_rows.append({
                "parent_id":pid,
                "group_a":a,
                "group_b":b,
                "pair_class":cls,
                "d_inf":format(d,".17g"),
                "owner":owner,
                "removed_group":loser,
                "owner_rule":
                    "EXISTING_BEATS_NEW_OTHERWISE_LOWER_SG",
            })

    retained = []
    removed = []

    for g in available:

        if lost_to.get(g):
            removed.append(g)
            removed_occurrences[g] += 1
        else:
            retained.append(g)
            retained_occurrences[g] += 1

    nret = len(retained)

    if nret == 0:
        status = "ABSTAIN_NO_GREY"
    elif nret == 1:
        status = "SINGLETON_NO_SELECTOR_CALL"
    else:
        status = "SELECTOR_MAY_ACT_LATER"

    resolution_counts[status] += 1

    parent_rows.append({
        "parent_id":pid,
        "source_class":m["source_class"],
        "h":m["h"],
        "available_pre_collision":len(available),
        "retained_post_collision":nret,
        "resolution_status":status,
        "retained_groups":";".join(retained),
        "removed_groups":";".join(removed),
    })

    for g in ALL:

        available_flag = g in available
        retained_flag = g in retained

        owners = sorted(
            lost_to.get(g,set()),
            key=sg_index
        )

        if not available_flag:
            reason = "NOT_ELIGIBLE_OR_FINAL_FORECAST_FAIL"
        elif retained_flag:
            reason = "RETAINED"
        else:
            reason = "PRIMARY_COLLISION_LOSS"

        ledger_rows.append({
            "parent_id":pid,
            "group":g,
            "available_pre_collision":
                "TRUE" if available_flag else "FALSE",
            "retained_post_collision":
                "TRUE" if retained_flag else "FALSE",
            "removal_reason":reason,
            "collision_owners":
                ";".join(owners),
        })

    if ii % 100 == 0 or ii == len(meta):

        print(
            f"P4F3D2_PROGRESS={ii}/{len(meta)}",
            flush=True
        )


# ------------------------------------------------------------
# Reproduction gates against already-canonical R2 evidence
# ------------------------------------------------------------
assert comparison_count["LEGACY_NEW"] == 70272
assert collision4["LEGACY_NEW"] == 69
assert collision3["LEGACY_NEW"] == 803
assert collision2["LEGACY_NEW"] == 8201

assert collision4["NEW_NEW"] == 9
assert collision3["NEW_NEW"] == 97
assert collision2["NEW_NEW"] == 990

# Cross-primary parents only, reproducing P4-F3D1-R2
cross_primary_parents = {
    r["parent_id"]
    for r in edge_rows
    if r["pair_class"] == "LEGACY_NEW"
}

assert len(cross_primary_parents) == 450

expected_legacy = {
    "SG01_CONT_GM":2523,
    "SG02_DISCRETE_POLY":2514,
    "SG03_FRAC_LINEAR":2553,
    "SG04_BERNOULLI":2595,
    "SG05_CONT_TIME_POLY":2506,
    "SG06_CONFORMABLE":2562,
    "SG07_ROLLING":2536,
    "SG08_WBO":2500,
    "SG09_GREY_MARKOV":2456,
    "SG10_SEASONAL":830,
}

for g,n in expected_legacy.items():
    assert legacy_ok[g] == n, (g,legacy_ok[g],n)


# ------------------------------------------------------------
# Write evidence
# ------------------------------------------------------------
with open(
    edges_path,
    "w",
    newline="",
    encoding="utf-8"
) as f:

    fields = [
        "parent_id",
        "group_a",
        "group_b",
        "pair_class",
        "d_inf",
        "owner",
        "removed_group",
        "owner_rule",
    ]

    w = csv.DictWriter(
        f,
        fieldnames=fields,
        lineterminator="\n"
    )

    w.writeheader()
    w.writerows(edge_rows)


with open(
    ledger_path,
    "w",
    newline="",
    encoding="utf-8"
) as f:

    fields = [
        "parent_id",
        "group",
        "available_pre_collision",
        "retained_post_collision",
        "removal_reason",
        "collision_owners",
    ]

    w = csv.DictWriter(
        f,
        fieldnames=fields,
        lineterminator="\n"
    )

    w.writeheader()
    w.writerows(ledger_rows)


with open(
    parents_path,
    "w",
    newline="",
    encoding="utf-8"
) as f:

    fields = [
        "parent_id",
        "source_class",
        "h",
        "available_pre_collision",
        "retained_post_collision",
        "resolution_status",
        "retained_groups",
        "removed_groups",
    ]

    w = csv.DictWriter(
        f,
        fieldnames=fields,
        lineterminator="\n"
    )

    w.writeheader()
    w.writerows(parent_rows)


all_comparisons = sum(comparison_count.values())
all_c4 = sum(collision4.values())
all_c3 = sum(collision3.values())
all_c2 = sum(collision2.values())

retained_counts = [
    int(r["retained_post_collision"])
    for r in parent_rows
]

lines = [
    "AUTOGREY V2 P4-F3D2 FINAL ACTION SET RESOLUTION R1",
    "====================================================",
    "",
    "ACTIONABLE_PARENTS=2596",
    "TOTAL_GROUP_SLOTS=33748",
    "",
    f"ALL_PAIR_COMPARISONS={all_comparisons}",
    "",
    f"LEGACY_LEGACY_COMPARISONS={comparison_count['LEGACY_LEGACY']}",
    f"LEGACY_NEW_COMPARISONS={comparison_count['LEGACY_NEW']}",
    f"NEW_NEW_COMPARISONS={comparison_count['NEW_NEW']}",
    "",
    f"LEGACY_LEGACY_COLLISION_1E4={collision4['LEGACY_LEGACY']}",
    f"LEGACY_LEGACY_COLLISION_1E3={collision3['LEGACY_LEGACY']}",
    f"LEGACY_LEGACY_COLLISION_1E2={collision2['LEGACY_LEGACY']}",
    "",
    f"LEGACY_NEW_COLLISION_1E4={collision4['LEGACY_NEW']}",
    f"LEGACY_NEW_COLLISION_1E3={collision3['LEGACY_NEW']}",
    f"LEGACY_NEW_COLLISION_1E2={collision2['LEGACY_NEW']}",
    "",
    f"NEW_NEW_COLLISION_1E4={collision4['NEW_NEW']}",
    f"NEW_NEW_COLLISION_1E3={collision3['NEW_NEW']}",
    f"NEW_NEW_COLLISION_1E2={collision2['NEW_NEW']}",
    "",
    f"ALL_COLLISION_1E4={all_c4}",
    f"ALL_COLLISION_1E3={all_c3}",
    f"ALL_COLLISION_1E2={all_c2}",
    f"PARENTS_WITH_ANY_PRIMARY_COLLISION={len(parents_with_primary)}",
    "",
    f"ABSTAIN_NO_GREY={resolution_counts['ABSTAIN_NO_GREY']}",
    f"SINGLETON_NO_SELECTOR_CALL={resolution_counts['SINGLETON_NO_SELECTOR_CALL']}",
    f"SELECTOR_MAY_ACT_LATER={resolution_counts['SELECTOR_MAY_ACT_LATER']}",
    "",
    f"MIN_RETAINED_GROUPS={min(retained_counts)}",
    f"MAX_RETAINED_GROUPS={max(retained_counts)}",
    f"MEDIAN_RETAINED_GROUPS={float(np.median(retained_counts))}",
    "",
    "RETAINED_OCCURRENCES_BY_GROUP:",
]

for g in ALL:
    lines.append(
        f"{g}={retained_occurrences[g]}"
    )

lines.extend([
    "",
    "REMOVED_BY_PRIMARY_COLLISION_BY_GROUP:",
])

for g in ALL:
    lines.append(
        f"{g}={removed_occurrences[g]}"
    )

lines.extend([
    "",
    "PRIMARY_COLLISION_THRESHOLD=1e-3",
    "OWNER_RULE=EXISTING_SG01_TO_SG10_BEATS_NEW_SG11_TO_SG13_OTHERWISE_LOWER_SG_INDEX",
    "EXACT_REDUCTION_POINTS_ALREADY_REMOVED_BEFORE_INNER_SCORING=TRUE",
    "TARGET_VALUES_USED_FOR_COLLISION=FALSE",
    "SELECTOR_TRAINING_PERFORMED=FALSE",
    "FEATURE_GOVERNANCE_CHANGED=FALSE",
    "REALBENCH3_TARGETS_OPENED=FALSE",
    "",
    "P4F3D2_FINAL_ACTION_SET_RESOLUTION=PASS",
])

summary_path.write_text(
    "\n".join(lines) + "\n",
    encoding="utf-8"
)

print()
print("\n".join(lines))
