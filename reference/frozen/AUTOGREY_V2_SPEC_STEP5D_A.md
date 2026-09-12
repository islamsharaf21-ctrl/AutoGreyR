# AutoGrey Step 5D-A — v2 Development Corpus and Action-Risk Materialization

**Date:** 2026-09-03  
**Version:** `AG_V2_CORPUS_5DA_1R1`  
**Status:** DELIVERED  
**Selector fitted:** NO  
**Architecture search:** NO  
**CAL labels:** SEALED  
**LOCKTEST labels:** SEALED  
**REAL_BENCH-2:** NOT READ

## 1. Purpose

Step 5D-A materializes the development-side objects required by the Step 5C selector design and then stops before model fitting.

Allowed development evidence:

- all 588 previously opened synthetic AutoGrey parents;
- all 2,016 REAL_BENCH-1 parents, explicitly exploratory for v2.

The new untouched REAL_BENCH-2 is not read.

## 2. Development parent population

```text
Synthetic parents                588
REAL_BENCH-1 parents            2016
------------------------------------
Total development parents       2604

Actionable parents              2596
Explicit refusals                  8
```

The eight refusals are retained from the frozen REAL_BENCH-1 premodel-history ledger.

No parent is replaced or resampled.

## 3. Long contextual-action corpus

For every post-dedup eligible action, Step 5D-A creates one selector-side row.

Total:

```text
22,762 target-free action rows
```

Mean actions per actionable parent:

`8.768105`

Each parent contributes total action-row weight 1:

\[
w_{ig}=1/k_i.
\]

The canonical action table contains:

- 23 frozen v1 task features and masks;
- 12 Step-5C D-only action-risk features and masks/reasons;
- action group identity;
- 10 eligibility bits;
- eligible-action count;
- h context;
- known-M context;
- selected within-group configuration ID;
- deterministic selector-row hash.

It does **not** contain action loss, oracle loss, regret, or target labels.

## 4. Step 5D-A R1 chronology correction

During the first assembly attempt, a combined table would have exposed CAL and LOCKTEST losses too early.

This was corrected before any selector fitting or architecture search.

The final R1 structure is:

### All-split action table

`AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv`

Contains only selector-side D information.

No columns exist for:

- `action_loss_mase`;
- `eligible_oracle_mase`;
- `eligible_regret`;
- `target_log1p_regret`.

### TRAIN labels

`AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv`

Contains outcome labels only for `V2_TRAIN`.

### CAL

Features are materialized, but labels are omitted until Step 5D-C.

### LOCKTEST

Features are materialized, but labels are omitted until Step 5E.

The source data underlying these internal holdouts were historically opened in earlier project stages. Therefore CAL/LOCKTEST are **operational v2 holdouts**, not newly collected unseen observations. The protection is that the v2 architecture-search artifacts do not expose their outcome labels.

Transient intermediate chunk files containing non-TRAIN labels were deleted after the R1 correction.

## 5. Frozen deterministic split

Within every `source_class × h` stratum:

```text
key = SHA256(parent_id + "|34781")
```

Then:

```text
first floor(0.80*n)  -> V2_TRAIN
next  floor(0.10*n)  -> V2_CAL
remaining            -> V2_LOCKTEST
```

Result:

| Split | Parents | Actionable | Refused | Action rows | Labels exposed |
|---|---:|---:|---:|---:|---:|
| V2_TRAIN | 2077 | 2070 | 7 | 18107 | 18107 |
| V2_CAL | 252 | 251 | 1 | 2239 | 0 |
| V2_LOCKTEST | 275 | 275 | 0 | 2416 | 0 |

## 6. TRAIN five-fold assignment

Inside every `source_class × h` TRAIN stratum:

```text
key = SHA256(parent_id + "|34783")
fold = zero_based_rank mod 5
```

Parent counts:

```text
fold 0   422
fold 1   419
fold 2   415
fold 3   412
fold 4   409
```

Only these TRAIN folds may be used in Step 5D-B architecture selection.

## 7. Source composition

| Source class | Parents | Actionable | Refused | Action rows | Mean actions |
|---|---:|---:|---:|---:|---:|
| SYNTH | 588 | 588 | 0 | 5154 | 8.765 |
| M1Y | 181 | 180 | 1 | 1563 | 8.683 |
| M3Y | 645 | 645 | 0 | 5656 | 8.769 |
| M3Q | 756 | 756 | 0 | 7305 | 9.663 |
| WDI_POP | 217 | 217 | 0 | 1764 | 8.129 |
| WDI_GDP | 217 | 210 | 7 | 1320 | 6.286 |

Source identity remains metadata only and is not a selector input.

## 8. Action-risk validity

The twelve Step-5C action-risk features were successfully materialized.

Ten are valid on every action row.

Only the two peer-distance features have invalid masks:

```text
peer_min_distance_log       34 invalid
peer_median_distance_log    34 invalid
```

Those 34 rows are exactly the 34 singleton action sets.

This is structural, not missing-data failure: a singleton action has no peer forecast.

It remains:

```text
value = 0
validity mask = 0
reason = SINGLETON_ACTION_SET
```

No target-informed repair is performed.

## 9. Reproduction checks

The final corpus passes:

`93 / 93` combined assertions.

Independent checks include:

- exact 80/10/10 split recomputation in every source×h stratum;
- exact five-fold TRAIN assignment;
- feature/action row uniqueness;
- parent weights summing to 1;
- nonnegative TRAIN eligible regret;
- all action-risk numeric values finite;
- valid-config fraction in [0,1];
- peer-distance invalidity exactly matching singleton rows;
- TRAIN labels joining exactly to selector-row hashes;
- REAL_BENCH-1 TRAIN action losses matching the frozen v1 external ledger;
- overlapping synthetic TRAIN losses matching frozen Step 4F-B2 labels;
- CAL/LOCKTEST labels absent from canonical artifacts;
- CAL/LOCKTEST target hashes retained in the task ledger;
- no REAL_BENCH-2 read.

## 10. Current holdout states

```text
V2_TRAIN     LABELS_OPEN_FOR_5D_B_ARCHITECTURE_SEARCH

V2_CAL       TARGET_HASH_COMMITTED
             LABELS_OMITTED_UNTIL_5D_C

V2_LOCKTEST  TARGET_HASH_COMMITTED
             LABELS_OMITTED_UNTIL_5E

REAL_BENCH-2 UNTOUCHED_CONFIRMATORY
```

## 11. What Step 5D-A has not done

There is still no v2:

- fitted RF regressor;
- fitted tail classifier;
- tail threshold tau_h;
- lambda result;
- feature-mode result;
- pooled-vs-BY_H result;
- TRAIN OOF regret;
- TRAIN OOF CVaR90;
- architecture winner;
- CAL confidence threshold;
- LOCKTEST result.

Therefore no v2 performance result exists yet.

## 12. Next checkpoint

**Step 5D-B — TRAIN-only architecture search.**

Step 5D-B may read:

- `AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv`;
- `AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv`;
- TRAIN rows/folds only.

It must reject any attempt to use:

- CAL outcome labels;
- LOCKTEST outcome labels;
- REAL_BENCH-2.

It will evaluate the frozen GLOBAL_RANK_V2, V1_STYLE_RF_REGRET and 64 ACTION_RF configurations using five-fold TRAIN OOF predictions and the Step-5C minimax mean/CVaR90 hierarchy.

It must stop if the selected TRAIN candidate fails:

\[
ho_\mu < 1
\]

and

\[
ho_{tail} \le 1.
\]
