#!/usr/bin/env python3
"""Experimental V1 CLI preflight and one-shot delegation; no model code herein.

The original frozen V1 archive and the two experimental engine scripts remain
unchanged. Only this facade can produce its own CLI_RECEIPT.json; direct
invocations of internal scripts remain possible and prohibited by runbook.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
from importlib import metadata
import json
import math
from pathlib import Path
import platform
import subprocess
import sys
import zipfile

VERSION = "0.1.0-g3s-candidate"
SOURCE_SHA256 = "e3e78ecdb670c9ed29af875d0b41b5aaf7506eb04844d8d193d62b890307720f"
PROTOTYPE_SHA256 = "2c4f6d7f1ca9a981afdb618a9a62f0e64e612f208382cac666ede577e1ad1028"
OBSERVER_SHA256 = "b9df6ad83626f9fcb6baaa19917c161d5d187e264b039f356b1bd5e0c0068a37"
EXPECTED = {
    "python": "3.13.5",
    "numpy": "2.3.5",
    "scipy": "1.17.0",
    "scikit-learn": "1.8.0",
}
PKG_DIR = Path(__file__).resolve().parent


class ControlledStop(Exception):
    """Expected refusal surfaced as exit code 2."""


def demand(condition: bool, label: str) -> None:
    if not condition:
        raise ControlledStop(label)


def file_hash(file: Path) -> str:
    digest = hashlib.sha256()
    with file.open("rb") as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def possible_hash(file: Path) -> str:
    """Make post-run disappearance visible in the CLI receipt, not a false PASS."""
    try:
        return file_hash(file)
    except OSError:
        return "MISSING_OR_UNREADABLE"


def check_files() -> dict[str, str]:
    """Enforce unchanged observer and predictor byte identity."""
    filenames = {
        "v1_new_series_prototype.py": PROTOTYPE_SHA256,
        "run_demo_bounded.py": OBSERVER_SHA256,
    }
    found: dict[str, str] = {}
    for name, expected_hash in filenames.items():
        p = PKG_DIR / name
        demand(p.is_file(), f"STOP_MISSING_PACKAGE_FILE:{name}")
        actual = file_hash(p)
        demand(actual == expected_hash, f"STOP_MODIFIED_PACKAGE_FILE:{name}")
        found[name] = actual
    return found


def check_original_source(source: Path, crc: bool = False) -> str:
    demand(source.is_file(), "STOP_SOURCE_FILE_MISSING")
    actual = file_hash(source)
    demand(actual == SOURCE_SHA256, "STOP_ORIGINAL_V1_SOURCE_SHA256_MISMATCH")
    if crc:
        try:
            with zipfile.ZipFile(source) as z:
                demand(z.testzip() is None, "STOP_ORIGINAL_V1_SOURCE_CRC_FAILURE")
        except (zipfile.BadZipFile, OSError) as exc:
            raise ControlledStop("STOP_ORIGINAL_V1_SOURCE_ARCHIVE_INVALID") from exc
    return actual


def check_environment() -> dict[str, str]:
    actual = {"python": platform.python_version()}
    for name in ("numpy", "scipy", "scikit-learn"):
        try:
            actual[name] = metadata.version(name)
        except metadata.PackageNotFoundError:
            actual[name] = "NOT_INSTALLED"
    demand(actual == EXPECTED,
           "STOP_EXACT_PYTHON_ENVIRONMENT_REQUIRED:" + json.dumps(actual, sort_keys=True))
    return actual


def check_series_file(series: Path) -> int:
    """Reject malformed records rather than silently dropping CSV fields."""
    demand(series.is_file(), "STOP_SERIES_FILE_MISSING")
    try:
        with series.open("r", encoding="utf-8-sig", newline="") as stream:
            reader = csv.reader(stream, strict=True)
            header = next(reader, None)
            demand(header == ["value"], "STOP_INPUT_SCHEMA_EXPECTED_ONE_VALUE_COLUMN")
            count = 0
            for row in reader:
                line = reader.line_num
                demand(len(row) == 1, "STOP_INPUT_SCHEMA_EXPECTED_ONE_VALUE_COLUMN")
                val = row[0]
                demand(val.strip() != "", f"STOP_INPUT_EMPTY_ROW_{line}")
                try:
                    number = float(val)
                except ValueError as exc:
                    raise ControlledStop(f"STOP_INPUT_NONNUMERIC_ROW_{line}") from exc
                demand(math.isfinite(number), f"STOP_INPUT_NONFINITE_ROW_{line}")
                count += 1
    except UnicodeError as exc:
        raise ControlledStop("STOP_INPUT_TEXT_ENCODING_INVALID") from exc
    return count


def check_horizon(h: int, m: int | None, n: int) -> None:
    demand(h in (1, 3, 5), "STOP_HORIZON_OUTSIDE_FROZEN_V1_TRAIN_DOMAIN")
    if m is not None:
        demand(m >= 2, "STOP_SEASONAL_PERIOD_INVALID")
    demand(n >= h + 7, "STOP_SERIES_TOO_SHORT_FOR_FROZEN_ELIGIBILITY")


def doctor(args: argparse.Namespace) -> int:
    source = Path(args.source).expanduser().resolve()
    hashes = check_files()
    source_hash = check_original_source(source, crc=True)
    environment = check_environment()
    receipt = {
        "cli_version": VERSION,
        "status": "PASS_PREFLIGHT_ONLY_NO_FORECAST_RUN",
        "source_sha256": source_hash,
        "launcher_sha256": file_hash(PKG_DIR / "agv1_cli.py"),
        "package_code_sha256": hashes,
        "environment": environment,
        "scientific_scope": "EXPERIMENTAL_FULL_TRAIN_UNVALIDATED;NN5_R3_SUPERIORITY_GATE_NOT_MET",
        "self_hash_is_not_a_trust_anchor": True,
    }
    print(json.dumps(receipt, sort_keys=True, indent=2))
    return 0


def check_observer_provenance(observer_receipt: dict, source_hash: str,
                              series_hash: str) -> None:
    """Validate observer-reported provenance; a PASS label alone is not sufficient."""
    demand(observer_receipt.get("original_zip_sha256") == source_hash
           and observer_receipt.get("prototype_sha256") == PROTOTYPE_SHA256
           and observer_receipt.get("input_series_sha256") == series_hash,
           "STOP_OBSERVER_PROVENANCE_DISAGREEMENT")


def check_result_artifacts(root: Path, h: int, m: int | None, n: int,
                           source_hash: str, series_hash: str) -> dict[str, str]:
    """Post-observer end-to-end check of actual deliverables; does not fit models."""
    result = root / "RESULT"
    paths = {name: result / name for name in
             ("SELECTED_FORECAST.csv", "CANDIDATE_SCORES.csv", "RUN_RECEIPT.json")}
    demand(all(p.is_file() for p in paths.values()), "STOP_RESULT_FILES_MISSING")

    # Parse exactly the bytes whose hash is reported, rather than hashing
    # a separate read with potentially different contents.
    try:
        contents = {name: p.read_bytes() for name, p in paths.items()}
        report = json.loads(contents["RUN_RECEIPT.json"].decode("utf-8"))
    except (OSError, UnicodeError, ValueError) as exc:
        raise ControlledStop("STOP_RESULT_RECEIPT_INVALID") from exc
    demand(isinstance(report, dict), "STOP_RESULT_RECEIPT_INVALID")
    demand(report.get("source_archive_sha256") == source_hash
           and report.get("new_series_sha256") == series_hash
           and report.get("h") == h and report.get("M") == m
           and report.get("n") == n
           and report.get("train_only") is True
           and report.get("external_performance_assessed") is False
           and isinstance(report.get("candidate_count"), int)
           and not isinstance(report.get("candidate_count"), bool)
           and report["candidate_count"] > 0
           and isinstance(report.get("selected_group"), str)
           and report["selected_group"]
           and isinstance(report.get("selected_config_id"), str)
           and report["selected_config_id"],
           "STOP_RESULT_RECEIPT_DISAGREEMENT")

    def read_rows(name: str, required: set[str], refusal: str) -> list[dict[str, str]]:
        try:
            data = contents[name].decode("utf-8-sig")
            parser = csv.DictReader(io.StringIO(data, newline=""), strict=True)
            demand(parser.fieldnames is not None and
                   len(parser.fieldnames) == len(set(parser.fieldnames)) and
                   required.issubset(parser.fieldnames), refusal)
            rows = list(parser)
            demand(all(None not in row and all(v is not None for v in row.values())
                       for row in rows), refusal)
            return rows
        except (UnicodeError, csv.Error, ValueError) as exc:
            raise ControlledStop(refusal) from exc

    forecasts = read_rows(
        "SELECTED_FORECAST.csv",
        {"horizon", "forecast", "selected_group", "selected_config_id"},
        "STOP_RESULT_FORECAST_INVALID")
    demand(len(forecasts) == h, "STOP_RESULT_FORECAST_INVALID")
    predicted: list[float] = []
    for j, row in enumerate(forecasts, start=1):
        try:
            value = float(row["forecast"])
            index = int(row["horizon"])
        except (ValueError, TypeError) as exc:
            raise ControlledStop("STOP_RESULT_FORECAST_INVALID") from exc
        demand(index == j and math.isfinite(value)
               and row["selected_group"] == report["selected_group"]
               and row["selected_config_id"] == report["selected_config_id"],
               "STOP_RESULT_FORECAST_INVALID")
        predicted.append(value)

    scores = read_rows(
        "CANDIDATE_SCORES.csv",
        {"rank", "group", "selected_config_id", "predicted_log1p_regret", "forecast_values"},
        "STOP_RESULT_CANDIDATE_SCORES_INVALID")
    demand(len(scores) == report["candidate_count"], "STOP_RESULT_CANDIDATE_SCORES_INVALID")
    for j, row in enumerate(scores, start=1):
        try:
            rank = int(row["rank"])
            score = float(row["predicted_log1p_regret"])
            values = json.loads(row["forecast_values"])
            demand(isinstance(values, list) and len(values) == h and
                   all(isinstance(v, (int, float)) and not isinstance(v, bool)
                       and math.isfinite(v) for v in values),
                   "STOP_RESULT_CANDIDATE_SCORES_INVALID")
        except (ValueError, TypeError) as exc:
            raise ControlledStop("STOP_RESULT_CANDIDATE_SCORES_INVALID") from exc
        demand(rank == j and math.isfinite(score) and row["group"],
               "STOP_RESULT_CANDIDATE_SCORES_INVALID")
        if j == 1:
            demand(row["group"] == report["selected_group"] and
                   row["selected_config_id"] == report["selected_config_id"] and
                   all(abs(a - b) <= 1e-9 for a, b in zip(values, predicted)),
                   "STOP_RESULT_CANDIDATE_SCORES_INVALID")
    return {name: hashlib.sha256(content).hexdigest() for name, content in contents.items()}


def forecast(args: argparse.Namespace) -> int:
    source = Path(args.source).expanduser().resolve()
    series = Path(args.series).expanduser().resolve()
    out_root = Path(args.out_root).expanduser().resolve()
    # All controlled preflight refusals precede output directory creation.
    demand(not out_root.exists(), "STOP_OUTPUT_ROOT_ALREADY_EXISTS")
    demand(args.h in (1, 3, 5), "STOP_HORIZON_OUTSIDE_FROZEN_V1_TRAIN_DOMAIN")
    demand(args.M is None or args.M >= 2, "STOP_SEASONAL_PERIOD_INVALID")
    series_hash_before = file_hash(series) if series.is_file() else "MISSING"
    n = check_series_file(series)
    check_horizon(args.h, args.M, n)
    demand(possible_hash(series) == series_hash_before,
           "STOP_INPUT_CHANGED_DURING_PREFLIGHT")
    code_before = check_files()
    source_hash_before = check_original_source(source)
    environment = check_environment()
    launcher = PKG_DIR / "agv1_cli.py"
    launcher_hash_before = file_hash(launcher)

    cmd = [sys.executable, str(PKG_DIR / "run_demo_bounded.py"),
           "--source", str(source), "--series", str(series),
           "--h", str(args.h), "--out-root", str(out_root)]
    if args.M is not None:
        cmd.extend(["--M", str(args.M)])
    invoked_at_utc = datetime.now(timezone.utc).isoformat()
    # Exactly one subprocess request by facade. No retries, repeated model fits,
    # or second subprocess launches are initiated by this facade.
    proc = subprocess.run(cmd, check=False)

    series_hash_after = possible_hash(series)
    source_hash_after = possible_hash(source)
    launcher_hash_after = possible_hash(launcher)
    code_after = {name: possible_hash(PKG_DIR / name) for name in code_before}
    observer_receipt_path = out_root / "OBSERVER_RECEIPT.json"
    observer_receipt = None
    observer_receipt_sha256 = None
    if observer_receipt_path.is_file():
        observer_receipt_sha256 = possible_hash(observer_receipt_path)
        try:
            observer_receipt = json.loads(observer_receipt_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError):
            observer_receipt = None

    result_sha256 = None
    if series_hash_after != series_hash_before:
        status = "STOP_INPUT_CHANGED_DURING_EXECUTION"
    elif source_hash_after != source_hash_before:
        status = "STOP_SOURCE_CHANGED_DURING_EXECUTION"
    elif launcher_hash_after != launcher_hash_before:
        status = "STOP_LAUNCHER_CHANGED_DURING_EXECUTION"
    elif code_after != code_before:
        status = "STOP_ENGINE_CHANGED_DURING_EXECUTION"
    elif proc.returncode != 0:
        status = f"STOP_OBSERVER_EXIT_{proc.returncode}"
    elif not out_root.is_dir():
        status = "STOP_OUTPUT_ROOT_NOT_CREATED"
    elif not isinstance(observer_receipt, dict):
        status = "STOP_OBSERVER_RECEIPT_MISSING_OR_INVALID"
    elif (observer_receipt.get("observer_status") != "PASS_EXPERIMENTAL_UNVALIDATED"
          or observer_receipt.get("child_exit_code") != 0):
        status = "STOP_OBSERVER_RECEIPT_DISAGREEMENT"
    else:
        try:
            check_observer_provenance(observer_receipt, source_hash_before,
                                      series_hash_before)
            result_sha256 = check_result_artifacts(
                out_root, args.h, args.M, n, source_hash_before, series_hash_before)
            status = "PASS_OBSERVER_EXIT_0_EXPERIMENTAL_UNVALIDATED"
        except ControlledStop as exc:
            status = str(exc)


    receipt = {
        "cli_version": VERSION,
        "status": status,
        "invoked_at_utc": invoked_at_utc,
        "observer_invocations_requested": 1,
        "predictor_invocations_independently_verified": False,
        "observer_exit_code": proc.returncode,
        "observer_reported_child_exit_code": (
            observer_receipt.get("child_exit_code") if isinstance(observer_receipt, dict) else None),
        "observer_receipt_sha256": observer_receipt_sha256,
        "verified_result_sha256": result_sha256,
        "source_sha256_before": source_hash_before,
        "source_sha256_after": source_hash_after,
        "input_series_sha256_before": series_hash_before,
        "input_series_sha256_after": series_hash_after,
        "launcher_sha256_before": launcher_hash_before,
        "launcher_sha256_after": launcher_hash_after,
        "engine_source_sha256_before": code_before,
        "engine_source_sha256_after": code_after,
        "environment": environment,
        "h": args.h,
        "M": args.M,
        "scientific_scope": "EXPERIMENTAL_FULL_TRAIN_UNVALIDATED;NN5_R3_SUPERIORITY_GATE_NOT_MET",
        "self_hash_is_not_a_trust_anchor": True,
        "cli_receipt_not_in_original_observer_bundle": True,
    }
    # The original observer creates this directory. Never create one during
    # a refused preflight or conceal a failed observer execution.
    if out_root.is_dir():
        (out_root / "CLI_RECEIPT.json").write_text(
            json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if status.startswith("STOP_"):
        print("STOP_AGV1_CLI: " + status, file=sys.stderr, flush=True)
        return 2
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="AutoGreyR V1 EXPERIMENTAL CLI (NN5 R3 superiority gate not met)")
    parser.add_argument("--version", action="version", version=VERSION)
    commands = parser.add_subparsers(dest="command", required=True)
    doc = commands.add_parser("doctor", help="Validate environment + V1 source; no model run")
    doc.add_argument("--source", required=True)
    doc.set_defaults(handler=doctor)
    fc = commands.add_parser("forecast", help="One bounded experimental selector/forecast run")
    fc.add_argument("--source", required=True)
    fc.add_argument("--series", required=True, help="Chronological CSV, exactly one column: value")
    fc.add_argument("--h", type=int, required=True, help="Forecast horizon: 1, 3 or 5")
    fc.add_argument("--M", type=int, default=None, help="Optional seasonal period >= 2")
    fc.add_argument("--out-root", required=True, help="Output path must not already exist")
    fc.set_defaults(handler=forecast)
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except ControlledStop as exc:
        print("STOP_AGV1_CLI: " + str(exc), file=sys.stderr, flush=True)
        return 2
    except (OSError, csv.Error) as exc:
        print("STOP_AGV1_CLI_IO: " + type(exc).__name__ + ": " + str(exc),
              file=sys.stderr, flush=True)
        return 2


if __name__ == "__main__":
    sys.exit(main())
