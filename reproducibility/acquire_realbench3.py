#!/usr/bin/env python3
"""Public-safe REALBENCH3 source acquisition and byte-identity verification.

This layer verifies repository metadata and archive bytes. It deliberately does
not parse TSF numeric series values and does not implement P1 reservation logic.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import urllib.request
import zipfile
from typing import Any, Callable


class AcquisitionError(RuntimeError):
    pass


def _digest(path: Path, algorithm: str) -> str:
    h = hashlib.new(algorithm)
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().lower()


def _normalize_checksum(value: str | None) -> tuple[str | None, str | None]:
    if not value:
        return None, None
    if ":" in value:
        alg, digest = value.split(":", 1)
        return alg.lower(), digest.lower()
    return None, value.lower()


def _rights_ids(metadata: dict[str, Any]) -> list[str]:
    rights = metadata.get("rights") or []
    out: list[str] = []
    if isinstance(rights, dict):
        rights = [rights]
    for item in rights:
        if isinstance(item, dict):
            val = item.get("id") or item.get("title")
            if val:
                out.append(str(val))
        elif item:
            out.append(str(item))
    lic = metadata.get("license")
    if isinstance(lic, dict):
        val = lic.get("id") or lic.get("title")
        if val and str(val) not in out:
            out.append(str(val))
    elif lic and str(lic) not in out:
        out.append(str(lic))
    return out


def validate_record_metadata(source: dict[str, Any], record: dict[str, Any]) -> dict[str, Any]:
    expected_doi = str(source["doi"]).lower()
    got_doi = str(record.get("doi") or record.get("metadata", {}).get("doi") or "").lower()
    if got_doi != expected_doi:
        raise AcquisitionError(f"DOI mismatch: {got_doi!r} != {expected_doi!r}")

    files = record.get("files") or []
    matches = [f for f in files if f.get("key") == source["filename"] or f.get("filename") == source["filename"]]
    if len(matches) != 1:
        raise AcquisitionError(f"expected exactly one file named {source['filename']!r}; found {len(matches)}")
    f = matches[0]
    alg, metadata_digest = _normalize_checksum(f.get("checksum"))
    if alg not in {None, "md5"}:
        raise AcquisitionError(f"unexpected repository checksum algorithm: {alg}")
    verified_md5 = source.get("zenodo_md5_verified")
    if verified_md5 and metadata_digest and metadata_digest.lower() != str(verified_md5).lower():
        raise AcquisitionError(f"MD5 mismatch: metadata={metadata_digest} expected={verified_md5}")

    links = f.get("links") or {}
    content_url = links.get("content") or links.get("self")
    if not content_url:
        raise AcquisitionError("repository file metadata has no content/self URL")
    return {
        "source_id": source["source_id"],
        "doi": source["doi"],
        "record_id": record.get("id"),
        "filename": source["filename"],
        "metadata_md5": metadata_digest,
        "content_url": content_url,
        "rights_ids": _rights_ids(record.get("metadata") or {}),
        "redistribution_authorized": bool(source.get("redistribution_authorized", False)),
    }


def verify_downloaded_archive(path: Path, source: dict[str, Any]) -> dict[str, Any]:
    got_sha = _digest(path, "sha256")
    expected_sha = str(source["frozen_sha256"]).lower()
    if got_sha != expected_sha:
        raise AcquisitionError(f"SHA-256 mismatch: {got_sha} != {expected_sha}")
    got_md5 = _digest(path, "md5")
    expected_md5 = source.get("zenodo_md5_verified")
    if expected_md5 and got_md5 != str(expected_md5).lower():
        raise AcquisitionError(f"MD5 mismatch: {got_md5} != {str(expected_md5).lower()}")
    try:
        with zipfile.ZipFile(path) as zf:
            members = zf.namelist()
    except zipfile.BadZipFile as exc:
        raise AcquisitionError(f"not a valid ZIP archive: {path}") from exc
    expected_member = source["expected_tsf_member"]
    if expected_member not in members:
        raise AcquisitionError(f"expected TSF member {expected_member!r} not present")
    return {
        "sha256": got_sha,
        "md5": got_md5,
        "expected_member": expected_member,
        "expected_member_present": True,
        "tsf_numeric_values_parsed": False,
    }


def load_registry(path: Path) -> dict[str, Any]:
    obj = json.loads(path.read_text(encoding="utf-8"))
    ids = [s["source_id"] for s in obj["sources"]]
    if len(ids) != len(set(ids)):
        raise AcquisitionError("duplicate source_id in registry")
    return obj


def fetch_record(record_id: int, opener: Callable[..., Any] = urllib.request.urlopen) -> dict[str, Any]:
    url = f"https://zenodo.org/api/records/{record_id}"
    req = urllib.request.Request(url, headers={"User-Agent": "AutoGreyR-v2-reproducibility/rc1"})
    with opener(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_to(url: str, destination: Path, opener: Callable[..., Any] = urllib.request.urlopen) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    tmp = destination.with_suffix(destination.suffix + ".part")
    if tmp.exists():
        tmp.unlink()
    req = urllib.request.Request(url, headers={"User-Agent": "AutoGreyR-v2-reproducibility/rc1"})
    try:
        with opener(req, timeout=120) as resp, tmp.open("wb") as fh:
            shutil.copyfileobj(resp, fh, length=1024 * 1024)
        os.replace(tmp, destination)
    except Exception:
        if tmp.exists():
            tmp.unlink()
        raise


def acquire_source(source: dict[str, Any], cache_dir: Path, *, download: bool,
                   offline_record_dir: Path | None = None) -> dict[str, Any]:
    if offline_record_dir is not None:
        record_path = offline_record_dir / f"{source['zenodo_record_id']}.json"
        if not record_path.is_file():
            raise AcquisitionError(f"offline metadata file missing: {record_path}")
        record = json.loads(record_path.read_text(encoding="utf-8"))
        metadata_origin = str(record_path)
    else:
        record = fetch_record(int(source["zenodo_record_id"]))
        metadata_origin = f"https://zenodo.org/api/records/{source['zenodo_record_id']}"
    meta = validate_record_metadata(source, record)
    result: dict[str, Any] = {
        **meta,
        "metadata_origin": metadata_origin,
        "download_requested": bool(download),
        "archive_verification": None,
        "archive_bytes_written": False,
        "record_level_license_captured": bool(meta["rights_ids"]),
        "repository_distribution_decision": "DO_NOT_BUNDLE_SOURCE_ARCHIVE",
    }
    if download:
        archive = cache_dir / "sources" / source["filename"]
        if archive.exists():
            verified = verify_downloaded_archive(archive, source)
        else:
            download_to(meta["content_url"], archive)
            try:
                verified = verify_downloaded_archive(archive, source)
            except Exception:
                archive.unlink(missing_ok=True)
                raise
        result["archive_path"] = str(archive.resolve())
        result["archive_verification"] = verified
        result["archive_bytes_written"] = True
    return result


def main(argv: list[str] | None = None) -> int:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--registry", type=Path, default=here / "source_registry.json")
    ap.add_argument("--source", action="append", help="source_id; repeat, or omit for all")
    ap.add_argument("--cache-dir", type=Path, required=True, help="external cache directory; must be outside Git for real data")
    ap.add_argument("--download", action="store_true", help="download and verify archive bytes; default is metadata-only")
    ap.add_argument("--offline-record-dir", type=Path, help="directory of <record_id>.json metadata fixtures")
    args = ap.parse_args(argv)
    reg = load_registry(args.registry)
    selected = set(args.source or [s["source_id"] for s in reg["sources"]])
    known = {s["source_id"] for s in reg["sources"]}
    unknown = selected - known
    if unknown:
        raise AcquisitionError(f"unknown source_id(s): {sorted(unknown)}")
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    results = [acquire_source(s, args.cache_dir, download=args.download, offline_record_dir=args.offline_record_dir)
               for s in reg["sources"] if s["source_id"] in selected]
    evidence = {
        "schema": "AUTOGREY_V2_R5B2_ACQUISITION_EVIDENCE_R1",
        "metadata_only": not args.download,
        "numeric_tsf_values_parsed": False,
        "sources": results,
    }
    out = args.cache_dir / "AUTOGREY_V2_R5B2_ACQUISITION_EVIDENCE_R1.json"
    out.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
