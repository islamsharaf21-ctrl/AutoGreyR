from __future__ import annotations
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "reproducibility"))
import environment_preflight as ep


def test_evaluate_python_environment_exact_versions_pass():
    lock={"python_version":"3.13.5","packages":{"numpy":"2.3.5","scipy":"1.18.1"}}
    actual={"python_version":"3.13.5","packages":{"numpy":"2.3.5","scipy":"1.18.1"}}
    result=ep.evaluate_python_environment(actual,lock)
    assert result["status"] == "PASS"
    assert result["mismatches"] == []


def test_evaluate_python_environment_reports_version_mismatch():
    lock={"python_version":"3.13.5","packages":{"numpy":"2.3.5"}}
    actual={"python_version":"3.13.5","packages":{"numpy":"2.3.4"}}
    result=ep.evaluate_python_environment(actual,lock)
    assert result["status"] == "FAIL"
    assert result["mismatches"][0]["component"] == "numpy"


def test_python_lock_explicitly_marks_statsmodels_unresolved():
    lock=json.loads((ROOT/"config/environments/PYTHON_ENVIRONMENT_LOCK.json").read_text())
    assert lock["historical_statsmodels_version"] is None
    assert lock["historical_statsmodels_status"] == "UNRESOLVED_DO_NOT_INVENT"
    assert lock["p6_runtime_pip_freeze_expected_sha256"] == "869EB91027517E4F2949ABE720BEDC28B56269140EF3E9D57754999515EC3882"
    assert lock["p6_runtime_wheel_manifest_expected_sha256"] == "70C81B18FA7CC9925E79D9656943E651010FF957F1BF7B0211094E8FDF19B383"


def test_r_lock_uses_final_executed_lp64_runtime():
    lock=json.loads((ROOT/"config/environments/R_ENVIRONMENT_LOCK.json").read_text())
    assert lock["r_version"] == "4.6.1"
    assert lock["blas"]["openblas_version"] == "0.3.30"
    assert lock["blas"]["integer_interface"] == "LP64"
    assert lock["blas"]["INTERFACE64"] == 0
    assert lock["historical_preexecution_blas_label"] == "OpenBLAS_0.3.30_ILP64"
    assert lock["historical_preexecution_label_status"] == "SUPERSEDED_BY_EXECUTED_R5D_RUNTIME_EVIDENCE"


def test_renv_lock_is_json_and_has_exact_forecast_version():
    lock=json.loads((ROOT/"config/environments/renv.lock").read_text())
    assert lock["R"]["Version"] == "4.6.1"
    assert lock["Packages"]["forecast"]["Version"] == "9.0.2"
    assert lock["Packages"]["renv"]["Version"] == "1.2.3"
