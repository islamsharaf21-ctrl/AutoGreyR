#!/usr/bin/env python3
"""Bounded Windows observer for one experimental AutoGrey V1 new-series run.

Never modifies the original ZIP. Does not invoke protected V1/V2/V3 experiments.
Automatically uses included synthetic CSV unless --series is provided.
Uses fresh output directory; refusal on re-use; 600-second execution deadline.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import time
import zipfile

SOURCE_SHA256 = 'e3e78ecdb670c9ed29af875d0b41b5aaf7506eb04844d8d193d62b890307720f'
PROTOTYPE_SHA256 = '2c4f6d7f1ca9a981afdb618a9a62f0e64e612f208382cac666ede577e1ad1028'
DEADLINE_SECONDS = 600


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for part in iter(lambda: f.read(1024 * 1024), b''):
            h.update(part)
    return h.hexdigest()


def terminate_tree(proc):
    if os.name == 'nt':
        subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20, check=False)
    else:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if proc.poll() is None:
        proc.kill()
    proc.wait(timeout=15)


def make_bundle(root):
    path = root / 'V1_NEW_SERIES_EXECUTION_EVIDENCE.zip'
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(root.rglob('*')):
            if p.is_file() and p != path:
                z.write(p, arcname=str(p.relative_to(root)).replace('\\','/'))
    return path


def verify_result(result):
    forecast = result / 'SELECTED_FORECAST.csv'
    scores = result / 'CANDIDATE_SCORES.csv'
    receipt = result / 'RUN_RECEIPT.json'
    if not (forecast.is_file() and scores.is_file() and receipt.is_file()):
        raise RuntimeError('STOP_EXPECTED_RESULT_FILES_MISSING')
    with forecast.open(newline='', encoding='utf-8') as f:
        predictions = list(csv.DictReader(f))
    with scores.open(newline='', encoding='utf-8') as f:
        candidates = list(csv.DictReader(f))
    report = json.loads(receipt.read_text(encoding='utf-8'))
    if len(predictions) != report['h'] or len(candidates) != report['candidate_count'] or not candidates:
        raise RuntimeError('STOP_RESULT_ROW_COUNT_INCONSISTENT')
    if candidates[0]['group'] != report['selected_group']:
        raise RuntimeError('STOP_SELECTED_GROUP_DISAGREEMENT')
    if any(r['selected_group'] != report['selected_group'] for r in predictions):
        raise RuntimeError('STOP_FORECAST_GROUP_DISAGREEMENT')
    if not report.get('train_only') or report.get('external_performance_assessed') is not False:
        raise RuntimeError('STOP_SCIENTIFIC_SCOPE_DISAGREEMENT')
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', default=str(Path.home() / 'Downloads/AutoGreyR-1.0.0.zip'))
    p.add_argument('--series', default=str(Path(__file__).resolve().parent / 'example_synthetic_12.csv'))
    p.add_argument('--h', type=int, default=3)
    p.add_argument('--M', type=int, default=None)
    default_root = Path(os.environ.get('LOCALAPPDATA', str(Path.home() / 'AppData/Local'))) / 'AutoGrey/V1_NEW_SERIES_PROTOTYPE_DEMO_01'
    p.add_argument('--out-root', default=str(default_root))
    args = p.parse_args()
    source = Path(args.source).resolve()
    series = Path(args.series).resolve()
    root = Path(args.out_root).resolve()
    script = Path(__file__).resolve().parent / 'v1_new_series_prototype.py'
    if root.exists():
        raise RuntimeError('STOP_EXISTING_RUN_DIRECTORY: do not overwrite or rerun')
    if not source.is_file() or sha(source) != SOURCE_SHA256:
        raise RuntimeError('STOP_WRONG_OR_MISSING_V1_SOURCE_ARCHIVE')
    if not script.is_file() or sha(script) != PROTOTYPE_SHA256:
        raise RuntimeError('STOP_WRONG_OR_MODIFIED_NEW_SERIES_PROTOTYPE')
    if not series.is_file():
        raise RuntimeError('STOP_SERIES_MISSING')
    root.mkdir(parents=True, exist_ok=False)
    cmd = [sys.executable, str(script), '--source', str(source), '--series', str(series),
           '--h', str(args.h), '--out', str(root / 'RESULT')]
    if args.M is not None:
        cmd += ['--M', str(args.M)]
    created = time.monotonic()
    proc = None
    stdout = ''
    stderr = ''
    state = 'STOP_UNKNOWN'
    exit_code = None
    try:
        kwargs = {'start_new_session': True} if os.name != 'nt' else {'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, encoding='utf-8', errors='replace', **kwargs)
        try:
            stdout, stderr = proc.communicate(timeout=DEADLINE_SECONDS)
            exit_code = proc.returncode
            if exit_code != 0:
                state = 'STOP_SCRIPT_NONZERO_EXIT'
            elif 'V1_NEW_SERIES_PROTOTYPE=PASS_EXPERIMENTAL_NOT_EXTERNALLY_VALIDATED' not in stdout:
                state = 'STOP_SCRIPT_FINAL_MARKER_MISSING'
            else:
                report = verify_result(root / 'RESULT')
                state = 'PASS_EXPERIMENTAL_UNVALIDATED'
        except subprocess.TimeoutExpired:
            state = 'STOP_TIMEOUT_600_SECONDS'
            terminate_tree(proc)
            extra_out, extra_err = proc.communicate(timeout=5)
            stdout += extra_out or ''
            stderr += extra_err or ''
            exit_code = proc.returncode
        except Exception as e:
            state = 'STOP_POSTRUN_VERIFICATION_ERROR'
            stderr += '\n' + type(e).__name__ + ': ' + str(e)
    except Exception as e:
        state = 'STOP_LAUNCH_ERROR'
        stderr += '\n' + type(e).__name__ + ': ' + str(e)
    (root/'STDOUT.txt').write_text(stdout,encoding='utf-8')
    (root/'STDERR.txt').write_text(stderr,encoding='utf-8')
    receipt = {
        'observer_status':state,
        'child_exit_code':exit_code,
        'duration_seconds':round(time.monotonic()-created,3),
        'timeout_seconds':DEADLINE_SECONDS,
        'original_zip_sha256': SOURCE_SHA256,
        'prototype_sha256':PROTOTYPE_SHA256,
        'input_series_sha256':sha(series),
        'stdout_sha256':sha(root/'STDOUT.txt'),
        'stderr_sha256':sha(root/'STDERR.txt'),
        'scientific_status':'NEW_EXPERIMENTAL_FULL_TRAIN_FIT_NOT_EXTERNALLY_VALIDATED',
    }
    (root/'OBSERVER_RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    bundle = make_bundle(root)
    print('OBSERVER_STATUS=' + state)
    print('CHILD_EXIT_CODE=' + str(exit_code))
    print('RUN_DURATION_SECONDS=' + str(receipt['duration_seconds']))
    print('EVIDENCE_BUNDLE=' + str(bundle))
    print('EVIDENCE_SHA256=' + sha(bundle))
    if state == 'PASS_EXPERIMENTAL_UNVALIDATED':
        print('SELECTED_GROUP=' + report['selected_group'])
        print('SCIENTIFIC_SCOPE=EXPERIMENTAL_NOT_EXTERNALLY_VALIDATED')
        return 0
    print('STOP_DO_NOT_REPEAT;UPLOAD_EVIDENCE_INSTEAD')
    return 2

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print('STOP_OBSERVER_PREFLIGHT: ' + type(exc).__name__ + ': ' + str(exc),file=sys.stderr)
        sys.exit(2)
