import importlib.util
import math
import tempfile
import unittest
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'AUTOGREY_V2_P11C_FROZEN_CONFIRMATORY_SCORING_R1.py'
spec = importlib.util.spec_from_file_location('p11c', SRC)
p11c = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = p11c
spec.loader.exec_module(p11c)


class TestBinaryAndMase(unittest.TestCase):
    def _write_bin(self, values):
        td = tempfile.TemporaryDirectory()
        p = Path(td.name) / 'v.bin'
        np.asarray(values, dtype='<f8').tofile(p)
        self.addCleanup(td.cleanup)
        return p

    def test_read_indexed_float64_vector_uses_declared_offset_and_count(self):
        p = self._write_bin([99.0, 1.5, 2.5, 3.5, 88.0])
        row = {'binary_offset_bytes':'8', 'binary_length_values':'3', 'binary_length_bytes':'24'}
        got = p11c.read_indexed_float64_vector(row, p)
        np.testing.assert_array_equal(got, np.array([1.5,2.5,3.5], dtype=np.float64))

    def test_read_indexed_float64_vector_rejects_misaligned_or_inconsistent_length(self):
        p = self._write_bin([1.0,2.0,3.0])
        with self.assertRaisesRegex(AssertionError, 'offset'):
            p11c.read_indexed_float64_vector({'binary_offset_bytes':'1','binary_length_values':'1','binary_length_bytes':'8'}, p)
        with self.assertRaisesRegex(AssertionError, 'length'):
            p11c.read_indexed_float64_vector({'binary_offset_bytes':'0','binary_length_values':'2','binary_length_bytes':'8'}, p)

    def test_read_indexed_float64_vector_rejects_nonfinite(self):
        p = self._write_bin([1.0, float('nan')])
        row = {'binary_offset_bytes':'0','binary_length_values':'2','binary_length_bytes':'16'}
        with self.assertRaisesRegex(AssertionError, 'non-finite'):
            p11c.read_indexed_float64_vector(row, p)

    def test_read_development_vector_uses_parent_index_and_declared_nD(self):
        p = self._write_bin([4.0,5.0,6.0])
        idx = {'P': {'parent_id':'P','n_D_token_count':'3','binary_offset_bytes':'0','binary_length_values':'3','binary_length_bytes':'24'}}
        got = p11c.read_development_vector('P', idx, p)
        np.testing.assert_array_equal(got, np.array([4.,5.,6.]))

    def test_read_target_vector_requires_exact_h(self):
        p = self._write_bin([10.0,20.0])
        idx = {'P': {'parent_id':'P','h':'3','binary_offset_bytes':'0','binary_length_values':'2','binary_length_bytes':'16'}}
        with self.assertRaisesRegex(AssertionError, 'horizon length'):
            p11c.read_target_vector('P', idx, p)

    def test_mase_scale_nonseasonal_lag1(self):
        D=np.array([1.0,3.0,6.0,10.0])
        self.assertAlmostEqual(p11c.mase_scale(D, 1), (2+3+4)/3)
        self.assertAlmostEqual(p11c.mase_scale(D, None), (2+3+4)/3)

    def test_mase_scale_seasonal_uses_M_only_when_M_gt1(self):
        D=np.array([1.,2.,4.,8.,16.,32.])
        # M=2 => mean(|4-1|, |8-2|, |16-4|, |32-8|) = 11.25
        self.assertAlmostEqual(p11c.mase_scale(D, 2), 11.25)

    def test_mase_scale_rejects_zero_or_nonfinite_without_epsilon(self):
        with self.assertRaisesRegex(AssertionError, 'DEGENERATE_MASE_SCALE'):
            p11c.mase_scale(np.array([5.,5.,5.]), 1)
        with self.assertRaisesRegex(AssertionError, 'non-finite'):
            p11c.mase_scale(np.array([1.,np.inf,3.]), 1)

    def test_mase_matches_hand_calculation(self):
        D=np.array([1.,3.,6.,10.]) # scale=3
        y=np.array([11.,14.])
        f=np.array([10.,16.]) # MAE=(1+2)/2=1.5; MASE=.5
        self.assertAlmostEqual(p11c.mase(D,y,f,1),0.5)

    def test_mase_rejects_nonfinite_and_length_mismatch(self):
        D=np.array([1.,2.,3.])
        with self.assertRaisesRegex(AssertionError, 'length'):
            p11c.mase(D,np.array([1.,2.]),np.array([1.]),1)
        with self.assertRaisesRegex(AssertionError, 'non-finite'):
            p11c.mase(D,np.array([1.,np.nan]),np.array([1.,2.]),1)


if __name__ == '__main__':
    unittest.main()
