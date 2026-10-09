#!/usr/bin/env python3
"""Compare the current Python runtime to the frozen AutoGrey V2 core lock."""
from __future__ import annotations
import argparse, importlib.metadata, json, platform
from pathlib import Path
from typing import Any


def collect_python_environment() -> dict[str, Any]:
    dist_names = ["numpy", "scipy", "scikit-learn", "joblib", "threadpoolctl", "statsmodels"]
    packages: dict[str, str | None] = {}
    for name in dist_names:
        try:
            packages[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            packages[name] = None
    return {"python_version": platform.python_version(), "packages": packages}


def evaluate_python_environment(actual: dict[str, Any], lock: dict[str, Any]) -> dict[str, Any]:
    mismatches=[]
    if actual.get("python_version") != lock.get("python_version"):
        mismatches.append({"component":"python","expected":lock.get("python_version"),"actual":actual.get("python_version")})
    actual_packages=actual.get("packages",{})
    for name,expected in lock.get("packages",{}).items():
        got=actual_packages.get(name)
        if got != expected:
            mismatches.append({"component":name,"expected":expected,"actual":got})
    return {"status":"PASS" if not mismatches else "FAIL","mismatches":mismatches,"actual":actual}


def main(argv: list[str] | None=None) -> int:
    here=Path(__file__).resolve().parents[1]
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--lock",type=Path,default=here/"config/environments/PYTHON_ENVIRONMENT_LOCK.json")
    ap.add_argument("--output",type=Path)
    args=ap.parse_args(argv)
    lock=json.loads(args.lock.read_text())
    result=evaluate_python_environment(collect_python_environment(),lock)
    result["historical_statsmodels_version"]=lock.get("historical_statsmodels_version")
    result["historical_statsmodels_status"]=lock.get("historical_statsmodels_status")
    text=json.dumps(result,indent=2,sort_keys=True)+"\n"
    if args.output: args.output.write_text(text,encoding="utf-8")
    else: print(text,end="")
    return 0 if result["status"]=="PASS" else 2

if __name__=="__main__":
    raise SystemExit(main())
