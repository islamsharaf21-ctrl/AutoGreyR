import importlib.util
import tempfile
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCORER = ROOT / "AUTOGREY_V2_P11C_FROZEN_CONFIRMATORY_SCORING_R1.py"


def load_module():
    assert SCORER.is_file(), f"production scorer missing: {SCORER}"
    spec = importlib.util.spec_from_file_location("p11c_task1", SCORER)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


class TestRuntimeAndImmutableIO(unittest.TestCase):
    def test_runtime_rejects_wrong_python_version(self):
        m = load_module()
        with self.assertRaisesRegex(AssertionError, "Python version mismatch"):
            m.assert_runtime(python_version="3.13.4", numpy_version="2.3.5")

    def test_runtime_rejects_wrong_numpy_version(self):
        m = load_module()
        with self.assertRaisesRegex(AssertionError, "NumPy version mismatch"):
            m.assert_runtime(python_version="3.13.5", numpy_version="2.3.4")

    def test_exact_file_rejects_wrong_hash(self):
        m = load_module()
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "x.txt"
            p.write_text("abc", encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "SHA-256 mismatch"):
                m.exact_file(Path(td), "x.txt", "0" * 64)

    def test_existing_output_directory_is_rejected(self):
        m = load_module()
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "already-there"
            out.mkdir()
            with self.assertRaisesRegex(FileExistsError, "output already exists"):
                m.refuse_existing_output(out)

    def test_cli_modes_are_exactly_preflight_and_score(self):
        m = load_module()
        self.assertEqual(m.allowed_modes(), ("preflight", "score"))
        with self.assertRaises(SystemExit):
            m.parse_args(["--mode", "other", "--out", "X"])


if __name__ == "__main__":
    unittest.main()
