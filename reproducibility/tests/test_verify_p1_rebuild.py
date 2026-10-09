from __future__ import annotations
import csv, hashlib, sys
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "reproducibility"))
import verify_p1_rebuild as vp


def _sha(p: Path): return hashlib.sha256(p.read_bytes()).hexdigest()


def _write_clean(p: Path):
    cols = ["parent_id","source_id","h","raw_archive_sha256","tsf_member","target_tokens_numeric_parsed"]
    rows = [
        ["A","RB3_WEATHER_DAILY","1","aaa","weather_dataset.tsf","False"],
        ["B","RB3_CARPARTS_MONTHLY","3","bbb","car_parts_dataset_without_missing_values.tsf","False"],
    ]
    with p.open("w", newline="", encoding="utf-8") as f:
        w=csv.writer(f); w.writerow(cols); w.writerows(rows)


def _write_refusal(p: Path):
    cols=["parent_id","source_id","h","protected_target_numeric_parsed"]
    rows=[["C","RB3_WEATHER_DAILY","5","False"]]
    with p.open("w",newline="",encoding="utf-8") as f:
        w=csv.writer(f); w.writerow(cols); w.writerows(rows)


def test_verify_p1_files_accepts_expected_hashes_counts_and_no_target_parse(tmp_path: Path):
    c=tmp_path/"clean.csv"; r=tmp_path/"refusal.csv"
    _write_clean(c); _write_refusal(r)
    spec={
        "clean_sha256": _sha(c), "refusal_sha256": _sha(r),
        "clean_n":2, "refusal_n":1,
        "source_counts":{"RB3_WEATHER_DAILY":1,"RB3_CARPARTS_MONTHLY":1},
        "horizon_counts":{"1":1,"3":1},
    }
    result=vp.verify_p1_files(c,r,spec)
    assert result["status"] == "PASS"
    assert result["numeric_target_values_parsed"] is False


def test_verify_p1_files_rejects_wrong_clean_hash(tmp_path: Path):
    c=tmp_path/"clean.csv"; r=tmp_path/"refusal.csv"
    _write_clean(c); _write_refusal(r)
    spec={"clean_sha256":"0"*64,"refusal_sha256":_sha(r),"clean_n":2,"refusal_n":1,
          "source_counts":{"RB3_WEATHER_DAILY":1,"RB3_CARPARTS_MONTHLY":1},"horizon_counts":{"1":1,"3":1}}
    with pytest.raises(vp.VerificationError, match="clean-set SHA-256 mismatch"):
        vp.verify_p1_files(c,r,spec)


def test_verify_p1_files_rejects_any_numeric_target_parse_flag(tmp_path: Path):
    c=tmp_path/"clean.csv"; r=tmp_path/"refusal.csv"
    _write_clean(c); _write_refusal(r)
    text=c.read_text(); c.write_text(text.replace("False\n", "True\n", 1))
    spec={"clean_sha256":_sha(c),"refusal_sha256":_sha(r),"clean_n":2,"refusal_n":1,
          "source_counts":{"RB3_WEATHER_DAILY":1,"RB3_CARPARTS_MONTHLY":1},"horizon_counts":{"1":1,"3":1}}
    with pytest.raises(vp.VerificationError, match="target parse flag"):
        vp.verify_p1_files(c,r,spec)
