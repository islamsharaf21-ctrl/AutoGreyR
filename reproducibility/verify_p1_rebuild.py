#!/usr/bin/env python3
"""Verify P1 clean/refusal outputs against frozen identities without parsing target values.

This is a verification gate, not a reconstruction of the unrecovered P1
reservation/contamination implementation.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile
from typing import Any


class VerificationError(RuntimeError):
    pass


FROZEN_P1_SPEC: dict[str, Any] = {
    "clean_sha256": "C496055A807B9D37692A6756A137E8EF93D75E962001B42B93A9A13823DBDB7B",
    "refusal_sha256": "606509431D83166E89E9D166FBFEC6B393A896D18B2614F45FCCB9571DD7D795",
    "clean_n": 4781,
    "refusal_n": 19,
    "source_counts": {
        "RB3_CARPARTS_MONTHLY": 1192,
        "RB3_ELECTRICITY_HOURLY": 300,
        "RB3_HOSPITAL_MONTHLY": 750,
        "RB3_TRAFFIC_HOURLY": 750,
        "RB3_WEATHER_DAILY": 1789,
    },
    "horizon_counts": {"1": 1595, "3": 1595, "5": 1591},
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def _falseish(value: str | None) -> bool:
    return str(value or "").strip().lower() in {"false", "0", "no", ""}


def _read_clean_metadata(path: Path) -> tuple[int, Counter[str], Counter[str], dict[str, set[str]]]:
    n = 0
    sources: Counter[str] = Counter()
    horizons: Counter[str] = Counter()
    archives: dict[str, set[str]] = {}
    with path.open(newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        required = {"source_id", "h", "target_tokens_numeric_parsed"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise VerificationError(f"clean set missing columns: {sorted(missing)}")
        for row in reader:
            n += 1
            if not _falseish(row.get("target_tokens_numeric_parsed")):
                raise VerificationError(f"target parse flag is not false for clean row {n}")
            sid = row["source_id"]
            sources[sid] += 1
            horizons[str(row["h"])] += 1
            if "raw_archive_sha256" in row:
                archives.setdefault(sid, set()).add(row["raw_archive_sha256"].lower())
    return n, sources, horizons, archives


def _read_refusal_metadata(path: Path) -> int:
    n = 0
    with path.open(newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        if "protected_target_numeric_parsed" not in (reader.fieldnames or []):
            raise VerificationError("refusal ledger missing protected_target_numeric_parsed")
        for row in reader:
            n += 1
            if not _falseish(row.get("protected_target_numeric_parsed")):
                raise VerificationError(f"target parse flag is not false for refusal row {n}")
    return n


def verify_p1_files(clean_path: Path, refusal_path: Path, spec: dict[str, Any] | None = None,
                    archive_hash_by_source: dict[str, str] | None = None) -> dict[str, Any]:
    spec = spec or FROZEN_P1_SPEC
    clean_sha = sha256_file(clean_path)
    refusal_sha = sha256_file(refusal_path)
    if clean_sha != str(spec["clean_sha256"]).upper():
        raise VerificationError(f"clean-set SHA-256 mismatch: {clean_sha} != {spec['clean_sha256']}")
    if refusal_sha != str(spec["refusal_sha256"]).upper():
        raise VerificationError(f"refusal-ledger SHA-256 mismatch: {refusal_sha} != {spec['refusal_sha256']}")
    n, source_counts, horizon_counts, archive_sets = _read_clean_metadata(clean_path)
    rn = _read_refusal_metadata(refusal_path)
    if n != int(spec["clean_n"]):
        raise VerificationError(f"clean-set count mismatch: {n} != {spec['clean_n']}")
    if rn != int(spec["refusal_n"]):
        raise VerificationError(f"refusal count mismatch: {rn} != {spec['refusal_n']}")
    expected_sources = {str(k): int(v) for k, v in spec["source_counts"].items()}
    expected_horizons = {str(k): int(v) for k, v in spec["horizon_counts"].items()}
    if dict(source_counts) != expected_sources:
        raise VerificationError(f"source counts mismatch: {dict(source_counts)} != {expected_sources}")
    if dict(horizon_counts) != expected_horizons:
        raise VerificationError(f"horizon counts mismatch: {dict(horizon_counts)} != {expected_horizons}")
    if archive_hash_by_source:
        for sid, expected in archive_hash_by_source.items():
            got = archive_sets.get(sid, set())
            if got != {expected.lower()}:
                raise VerificationError(f"raw archive identity mismatch for {sid}: {sorted(got)} != {[expected.lower()]}")
    return {
        "schema": "AUTOGREY_V2_R5B2_P1_REBUILD_VERIFICATION_R1",
        "status": "PASS",
        "clean_set_sha256": clean_sha,
        "refusal_ledger_sha256": refusal_sha,
        "clean_parents": n,
        "refusals": rn,
        "source_counts": dict(source_counts),
        "horizon_counts": dict(horizon_counts),
        "numeric_target_values_parsed": False,
        "p1_population_note": "P1 clean set has 4,781 parents; later P11-A deployment froze 3 clean parents as nondeployed, yielding 4,778 scored parents. This verifier does not add/remove parents.",
        "reservation_algorithm_recreated": False,
    }


def _archive_map(registry_path: Path) -> dict[str, str]:
    reg = json.loads(registry_path.read_text(encoding="utf-8"))
    return {s["source_id"]: s["frozen_sha256"] for s in reg["sources"]}


def verify_seal_pack(seal_pack: Path, registry_path: Path, spec: dict[str, Any] | None = None) -> dict[str, Any]:
    clean_name = "AUTOGREY_REALBENCH3_P1_FINAL_CLEAN_PARENT_SET.csv"
    refusal_name = "AUTOGREY_REALBENCH3_P1_FINAL_REFUSAL_LEDGER.csv"
    with zipfile.ZipFile(seal_pack) as zf:
        by_base = {Path(n).name: n for n in zf.namelist() if not n.endswith("/")}
        for required in (clean_name, refusal_name):
            if required not in by_base:
                raise VerificationError(f"seal pack missing {required}")
        with tempfile.TemporaryDirectory(prefix="autogrey-p1-verify-") as td:
            td = Path(td)
            clean = td / clean_name
            refusal = td / refusal_name
            clean.write_bytes(zf.read(by_base[clean_name]))
            refusal.write_bytes(zf.read(by_base[refusal_name]))
            return verify_p1_files(clean, refusal, spec, _archive_map(registry_path))


def main(argv: list[str] | None = None) -> int:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__)
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--seal-pack", type=Path)
    group.add_argument("--clean-set", type=Path)
    ap.add_argument("--refusal-ledger", type=Path)
    ap.add_argument("--registry", type=Path, default=here / "source_registry.json")
    ap.add_argument("--output", type=Path)
    args = ap.parse_args(argv)
    if args.seal_pack:
        result = verify_seal_pack(args.seal_pack, args.registry)
    else:
        if args.refusal_ledger is None:
            ap.error("--refusal-ledger is required with --clean-set")
        result = verify_p1_files(args.clean_set, args.refusal_ledger, FROZEN_P1_SPEC, _archive_map(args.registry))
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
