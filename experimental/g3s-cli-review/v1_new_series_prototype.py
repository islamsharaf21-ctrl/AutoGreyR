#!/usr/bin/env python3
r"""AutoGreyR V1: NEW, EXPERIMENTAL full-TRAIN fit and new-series forecast.

This file is NOT part of the frozen AutoGreyR v1.0.0 scientific release.
It imports unmodified Python source from that ZIP, loads and validates all
18,107 V2_TRAIN action rows, fits group-specific RFs on all available TRAIN
rows belonging to each eligible group, then selects among the structurally eligible
forecasting groups for ONE user-provided series. No CAL/LOCKTEST/REALBENCH
outcomes are read. It is not externally validated, and must not be presented
as historical OOF performance or predictive superiority.

Usage (Windows Python 3.13.5 with frozen numpy/scipy/scikit-learn):
  py -3.13 v1_new_series_prototype.py \
    --source "C:\Users\YOUR_USER\Downloads\AutoGreyR-1.0.0.zip" \
    --series example_synthetic_12.csv --h 3 --out selected_demo
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import math
import platform
from pathlib import Path
import sys
import tempfile
import zipfile

EXPECTED_SOURCE_SHA256 = 'e3e78ecdb670c9ed29af875d0b41b5aaf7506eb04844d8d193d62b890307720f'
EXPECTED_INTERNAL_SHA256 = {
    'reference/python/autogrey_engine_step4fb_r1.py': '01c745d8a627748748f82916a576efbee231a2f87d66c314d57947dbede67974',
    'reference/python/autogrey_features_step4e.py': 'bbbd645cffae6462eb50cbb9ff5fb902912e6204df1ab5a9a316428d58b7a113',
    'reference/python/autogrey_v2_search_step5db_r2.py': 'a5f6e6914809bcde3667c96165984a218595c92c4cbf1d98ff4b23de50be2d23',
    'reference/frozen/AUTOGREY_V2_ACTION_TABLE_STEP5D_A.csv': '5e943ce10c601187d46dd0f77e9059aee29c7e2710d1d8ff5acf779787983a99',
    'reference/frozen/AUTOGREY_V2_TRAIN_LABELS_STEP5D_A.csv': '77e202112c8d3de45aeebfdbe6a4c8d1ac9b725aac598af5974d46a3f5be4631',
}
REQUIRED_PY = '3.13.5'
REQUIRED_NP = '2.3.5'
REQUIRED_SCIPY = '1.17.0'
REQUIRED_SK = '1.8.0'
EXPERIMENT_ID = 'AG_V1_NEW_SERIES_FULL_TRAIN_PROTOTYPE_01'


def sha_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''):
            h.update(b)
    return h.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def load_module(mod_name: str, path: Path):
    spec = importlib.util.spec_from_file_location(mod_name, path)
    require(spec is not None and spec.loader is not None, f'cannot load module: {path}')
    mod = importlib.util.module_from_spec(spec)
    sys.modules[mod_name] = mod
    spec.loader.exec_module(mod)
    return mod


def read_chronological_series(path: Path):
    """Strict one-column numeric CSV, heading 'value', oldest to newest."""
    import numpy as np
    require(path.is_file(), 'STOP_INPUT_FILE_MISSING')
    with path.open('r', encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        require(reader.fieldnames == ['value'], 'STOP_INPUT_SCHEMA_EXPECTED_ONE_VALUE_COLUMN')
        rows = []
        for i, r in enumerate(reader, start=2):
            s = r.get('value')
            require(s is not None and s.strip() != '', f'STOP_INPUT_EMPTY_ROW_{i}')
            try:
                v = float(s)
            except ValueError as exc:
                raise RuntimeError(f'STOP_INPUT_NONNUMERIC_ROW_{i}') from exc
            require(math.isfinite(v), f'STOP_INPUT_NONFINITE_ROW_{i}')
            rows.append(v)
    return np.array(rows, dtype=np.float64)


def environment_gate():
    import numpy as np
    import scipy
    import sklearn
    actual = {
        'python': platform.python_version(),
        'numpy': np.__version__,
        'scipy': scipy.__version__,
        'scikit_learn': sklearn.__version__,
    }
    expected = {
        'python': REQUIRED_PY,
        'numpy': REQUIRED_NP,
        'scipy': REQUIRED_SCIPY,
        'scikit_learn': REQUIRED_SK,
    }
    require(actual == expected, f'STOP_FROZEN_ENVIRONMENT_MISMATCH actual={actual} expected={expected}')
    return actual


def extract_pinned_inputs(source_zip: Path, temp: Path):
    require(source_zip.is_file(), 'STOP_SOURCE_MISSING')
    require(sha_file(source_zip) == EXPECTED_SOURCE_SHA256, 'STOP_SOURCE_SHA256_MISMATCH')
    with zipfile.ZipFile(source_zip, 'r') as z:
        require(z.testzip() is None, 'STOP_ARCHIVE_CRC_FAILURE')
        for name, digest in EXPECTED_INTERNAL_SHA256.items():
            try:
                contents = z.read(name)
            except KeyError as exc:
                raise RuntimeError(f'STOP_ARCHIVE_MEMBER_MISSING {name}') from exc
            require(hashlib.sha256(contents).hexdigest() == digest, f'STOP_INTERNAL_SHA256_MISMATCH {name}')
            # Use known relative fixed paths only, never a member-supplied path.
            dest = temp.joinpath(*name.split('/'))
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(contents)
    return {
        'engine': temp / 'reference/python/autogrey_engine_step4fb_r1.py',
        'features': temp / 'reference/python/autogrey_features_step4e.py',
        'search': temp / 'reference/python/autogrey_v2_search_step5db_r2.py',
        'train_dir': temp / 'reference/frozen',
    }


def run(args):
    import numpy as np

    source_zip = Path(args.source).expanduser().resolve(strict=False)
    input_file = Path(args.series).expanduser().resolve(strict=False)
    outdir = Path(args.out).expanduser().resolve(strict=False)
    require(not outdir.exists(), 'STOP_OUTPUT_DIRECTORY_ALREADY_EXISTS')
    require(1 <= args.h <= 5 and args.h in (1, 3, 5), 'STOP_HORIZON_OUTSIDE_FROZEN_V1_TRAIN_DOMAIN')
    if args.M is not None:
        require(args.M >= 2, 'STOP_SEASONAL_PERIOD_INVALID')
    x = read_chronological_series(input_file)
    # Prespecified refusal eligibility: development n >= h + 7.
    require(len(x) >= args.h + 7, 'STOP_SERIES_TOO_SHORT_FOR_FROZEN_ELIGIBILITY')

    env = environment_gate()
    print('PRECHECK_ENVIRONMENT=PASS', flush=True)
    print(f'INPUT_SHA256={sha_file(input_file)}', flush=True)

    with tempfile.TemporaryDirectory(prefix='autogrey_v1_newseries_') as td:
        paths = extract_pinned_inputs(source_zip, Path(td))
        print('PRECHECK_FROZEN_SOURCE_AND_TRAIN=PASS', flush=True)
        engine = load_module('ag_v1_engine_frozen', paths['engine'])
        features = load_module('ag_v1_features_frozen', paths['features'])
        search = load_module('ag_v1_search_frozen', paths['search'])

        # New-series target-free features and structural actions come only from x.
        f = features.extract_features(x, args.h, args.M)
        portfolio = engine.run_portfolio(x, args.h, args.M)
        groups = tuple(portfolio.distinct_groups)
        require(len(groups) > 0, 'STOP_NO_ELIGIBLE_DISTINCT_STRUCTURAL_GROUPS')
        require(tuple(features.FEATURE_NAMES) == tuple(search.ALL_V1_FEATURES),
                'STOP_FEATURE_ORDER_MISMATCH')
        require(tuple(engine.GROUP_ORDER) == tuple(search.GROUPS),
                'STOP_GROUP_ORDER_MISMATCH')
        raw = np.concatenate([
            np.where(f.valid_mask, f.values, np.nan),
            f.valid_mask.astype(np.float64),
            np.array([float(g in groups) for g in search.GROUPS], dtype=np.float64),
        ])[None, :]
        require(raw.shape == (1, 56), 'STOP_RAW_FEATURE_WIDTH_NOT_56')
        print(f'NEW_SERIES_STRUCTURAL_GROUPS={len(groups)}', flush=True)

        # TRAIN ONLY. Original load_train joins frozen labels to matching TRAIN
        # actions by row hash and refuses unmatched labels and duplicate rows.
        records, parents, parent_to_rows, meta, all_rows, excluded = search.load_train(paths['train_dir'])
        require(len(records) == 18107 and len(parents) == 2070, 'STOP_FROZEN_TRAIN_COUNT_MISMATCH')
        require(all(r['fold'] in (0,1,2,3,4) for r in records), 'STOP_FROZEN_FOLD_INVALID')
        require(all(len(r['x_v1']) == 56 for r in records), 'STOP_TRAIN_FEATURE_WIDTH_NOT_56')
        print(f'TRAIN_ROWS={len(records)};TRAIN_PARENTS={len(parents)};NON_TRAIN_ROWS_EXCLUDED={excluded}', flush=True)

        ranked = []
        # Lazy group-specific full-TRAIN fit: same result as fitting all 10
        # independently; unused group models are not trained or serialized.
        for g in groups:
            group_records = [r for r in records if r['group'] == g]
            n_parents = len({r['parent_id'] for r in group_records})
            require(n_parents >= search.V1_SUPPORT_MIN_PARENTS, f'STOP_GROUP_TRAIN_SUPPORT {g}')
            X = np.asarray([r['x_v1'] for r in group_records], dtype=np.float64)
            y = np.asarray([r['target'] for r in group_records], dtype=np.float64)
            weights = np.asarray([r['weight'] for r in group_records], dtype=np.float64)
            require(np.all(np.isfinite(y)) and np.all(np.isfinite(weights)), f'STOP_TRAIN_NONFINITE {g}')
            require(np.all(weights >= 0) and y.min() >= 0, f'STOP_TRAIN_INVALID_TARGET_OR_WEIGHT {g}')
            Xtr, Xev, med = search.fit_medians_and_transform(X, raw)
            require(np.all(np.isfinite(Xtr)) and np.all(np.isfinite(Xev)), f'STOP_PREPROCESS_NONFINITE {g}')
            model = search.make_rf_regressor(500, None, 0.01)
            model.fit(Xtr, y, sample_weight=weights)
            pred = float(model.predict(Xev)[0])
            require(math.isfinite(pred), f'STOP_PREDICTION_NONFINITE {g}')
            forecast = portfolio.group_results[g].forecast
            require(forecast is not None and len(forecast) == args.h and np.all(np.isfinite(forecast)),
                    f'STOP_GROUP_FORECAST_INVALID {g}')
            ranked.append({
                'group': g,
                'group_index': search.GROUP_INDEX[g],
                'predicted_log1p_regret': pred,
                'forecast': [float(v) for v in forecast],
                'config_id': portfolio.group_results[g].selected_config_id,
                'n_train_actions': len(group_records),
                'n_train_parents': n_parents,
            })
            print(f'GROUP_FIT={g};PREDICTED_TARGET={pred:.12g};TRAIN_ACTIONS={len(group_records)}', flush=True)

        ranked.sort(key=lambda r: (r['predicted_log1p_regret'], r['group_index']))
        chosen = ranked[0]
        require(chosen['group'] in groups, 'STOP_SELECTED_GROUP_INELIGIBLE')

        receipt = {
            'experiment_id': EXPERIMENT_ID,
            'status': 'PASS_FUNCTIONAL_PROTOTYPE_UNVALIDATED',
            'scientific_status': 'EXPERIMENTAL_FULL_TRAIN_FINAL_FIT_NOT_ORIGINAL_OOF_NOT_EXTERNAL_VALIDATION',
            'source_archive_sha256': EXPECTED_SOURCE_SHA256,
            'original_train_rows': 18107,
            'original_train_parents': 2070,
            'train_only': True,
            'new_series_sha256': sha_file(input_file),
            'n': len(x), 'h': args.h, 'M': args.M,
            'environment': env,
            'feature_version': f.version,
            'feature_hash': f.feature_hash,
            'eligible_distinct_groups': list(groups),
            'selected_group': chosen['group'],
            'selected_config_id': chosen['config_id'],
            'selected_predicted_log1p_regret': chosen['predicted_log1p_regret'],
            'candidate_count': len(ranked),
            'fitting_policy': 'One RF per eligible structural group, all frozen TRAIN action rows in group; group median imputation; sklearn 500 trees; seed 62291; min_samples_leaf=0.01; max_features=sqrt; sample weights frozen',
            'outputs_are_tested_forecasts': False,
            'external_performance_assessed': False,
        }
        # Atomic writes are unnecessary when output directory is absent until
        # all fits/validation finish; never overwrite an existing output dir.
        outdir.mkdir(parents=True, exist_ok=False)
        with (outdir / 'SELECTED_FORECAST.csv').open('w', newline='', encoding='utf-8') as stream:
            writer = csv.writer(stream)
            writer.writerow(['horizon', 'forecast', 'selected_group', 'selected_config_id', 'scientific_status'])
            for step, value in enumerate(chosen['forecast'], 1):
                writer.writerow([step, format(value, '.17g'), chosen['group'], chosen['config_id'], 'EXPERIMENTAL_UNVALIDATED'])
        with (outdir / 'CANDIDATE_SCORES.csv').open('w', newline='', encoding='utf-8') as stream:
            writer = csv.writer(stream)
            writer.writerow(['rank','group','selected_config_id','predicted_log1p_regret','n_train_actions','n_train_parents','forecast_values'])
            for i,r in enumerate(ranked, 1):
                writer.writerow([i,r['group'],r['config_id'],format(r['predicted_log1p_regret'],'.17g'),r['n_train_actions'],r['n_train_parents'],json.dumps(r['forecast'])])
        (outdir / 'RUN_RECEIPT.json').write_text(json.dumps(receipt, indent=2, ensure_ascii=False, allow_nan=False)+'\n',encoding='utf-8')
        print('SELECTED_GROUP=' + chosen['group'])
        print('SELECTED_FORECAST=' + ','.join(format(v,'.9g') for v in chosen['forecast']))
        print('OUTPUT_DIRECTORY=' + str(outdir))
        print('V1_NEW_SERIES_PROTOTYPE=PASS_EXPERIMENTAL_NOT_EXTERNALLY_VALIDATED')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', required=True, help='Exact untouched AutoGreyR-1.0.0.zip')
    parser.add_argument('--series', required=True, help='CSV of one column named value; chronological order')
    parser.add_argument('--h', required=True, type=int, help='Horizon (1, 3 or 5)')
    parser.add_argument('--M', default=None, type=int, help='Seasonal period if known (>=2), else omit')
    parser.add_argument('--out', required=True, help='Fresh output directory (must not already exist)')
    args = parser.parse_args()
    try:
        run(args)
        return 0
    except Exception as exc:
        print(f'STOP_V1_NEW_SERIES_PROTOTYPE: {type(exc).__name__}: {exc}', file=sys.stderr, flush=True)
        return 2


if __name__ == '__main__':
    sys.exit(main())
