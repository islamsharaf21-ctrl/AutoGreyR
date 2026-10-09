from __future__ import annotations
import hashlib, json, sys, zipfile
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "reproducibility"))

import acquire_realbench3 as ar


def _record(doi="10.5281/zenodo.4654822", filename="weather_dataset.zip", md5="abcd"):
    return {
        "id": 4654822,
        "doi": doi,
        "metadata": {"doi": doi, "rights": [{"id": "cc-by-4.0"}]},
        "files": [{
            "key": filename,
            "checksum": f"md5:{md5}",
            "links": {"content": "https://example.invalid/file"},
        }],
    }


def _source(md5="abcd"):
    return {
        "source_id": "RB3_WEATHER_DAILY",
        "doi": "10.5281/zenodo.4654822",
        "zenodo_record_id": 4654822,
        "filename": "weather_dataset.zip",
        "frozen_sha256": "0" * 64,
        "expected_tsf_member": "weather_dataset.tsf",
        "zenodo_md5_verified": md5,
        "redistribution_authorized": False,
    }


def test_validate_record_accepts_exact_record_and_captures_rights():
    result = ar.validate_record_metadata(_source(), _record())
    assert result["doi"] == "10.5281/zenodo.4654822"
    assert result["filename"] == "weather_dataset.zip"
    assert result["metadata_md5"] == "abcd"
    assert result["rights_ids"] == ["cc-by-4.0"]
    assert result["redistribution_authorized"] is False


def test_validate_record_rejects_doi_mismatch():
    with pytest.raises(ar.AcquisitionError, match="DOI mismatch"):
        ar.validate_record_metadata(_source(), _record(doi="10.5281/zenodo.999"))


def test_validate_record_rejects_verified_md5_mismatch():
    with pytest.raises(ar.AcquisitionError, match="MD5 mismatch"):
        ar.validate_record_metadata(_source(md5="expected"), _record(md5="actual"))


def test_verify_downloaded_archive_checks_sha_and_member(tmp_path: Path):
    z = tmp_path / "weather_dataset.zip"
    with zipfile.ZipFile(z, "w") as out:
        out.writestr("weather_dataset.tsf", "@data\nseries:1,2,3\n")
    sha = hashlib.sha256(z.read_bytes()).hexdigest()
    md5 = hashlib.md5(z.read_bytes()).hexdigest()
    src = _source(md5=md5)
    src["frozen_sha256"] = sha
    got = ar.verify_downloaded_archive(z, src)
    assert got["sha256"] == sha
    assert got["md5"] == md5
    assert got["expected_member_present"] is True


def test_verify_downloaded_archive_rejects_wrong_hash(tmp_path: Path):
    z = tmp_path / "weather_dataset.zip"
    with zipfile.ZipFile(z, "w") as out:
        out.writestr("weather_dataset.tsf", "x")
    src = _source(md5=hashlib.md5(z.read_bytes()).hexdigest())
    with pytest.raises(ar.AcquisitionError, match="SHA-256 mismatch"):
        ar.verify_downloaded_archive(z, src)


def test_verify_downloaded_archive_rejects_missing_member(tmp_path: Path):
    z = tmp_path / "weather_dataset.zip"
    with zipfile.ZipFile(z, "w") as out:
        out.writestr("wrong.tsf", "x")
    src = _source(md5=hashlib.md5(z.read_bytes()).hexdigest())
    src["frozen_sha256"] = hashlib.sha256(z.read_bytes()).hexdigest()
    with pytest.raises(ar.AcquisitionError, match="expected TSF member"):
        ar.verify_downloaded_archive(z, src)


def test_metadata_only_acquisition_writes_no_archive_bytes(tmp_path: Path):
    src=_source(md5=None)
    record=_record(md5="abcd")
    meta=tmp_path/"meta"; meta.mkdir()
    (meta/"4654822.json").write_text(json.dumps(record), encoding="utf-8")
    cache=tmp_path/"cache"
    result=ar.acquire_source(src,cache,download=False,offline_record_dir=meta)
    assert result["archive_bytes_written"] is False
    assert result["archive_verification"] is None
    assert not (cache/"sources").exists()
