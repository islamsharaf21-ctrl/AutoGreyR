import csv
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'AUTOGREY_V2_P11C_FROZEN_CONFIRMATORY_SCORING_R1.py'
spec = importlib.util.spec_from_file_location('p11c_task5', SRC)
p11c = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = p11c
spec.loader.exec_module(p11c)


def make_score(pid, *, ar, gr, am, gm, ng):
    return p11c.ParentScore(
        parent_id=pid,
        source_id='SYNTHETIC',
        h=1,
        M=1,
        mase_scale=1.0,
        eligible_action_count=2,
        autogrey_selected_group='SG01',
        global_selected_group='SG02',
        eligible_oracle_mase=0.0,
        autogrey_mase=float(am),
        global_mase=float(gm),
        ng10_mase=float(ng),
        autogrey_regret=float(ar),
        global_regret=float(gr),
        delta_selection_regret=float(ar - gr),
        delta_practical_mase=float(am - ng),
        subgroup_h='1',
        subgroup_source='SYNTHETIC',
        subgroup_source_x_h='SYNTHETIC|1',
        autogrey_forecast_sha256='A' * 64,
        global_forecast_sha256='B' * 64,
        ng10_forecast_sha256='C' * 64,
        eligible_action_forecast_hashes_json='{"SG01":"' + ('A' * 64) + '","SG02":"' + ('B' * 64) + '"}',
    )


class ScriptedRNG:
    def __init__(self, indices):
        self.indices = np.asarray(indices, dtype=np.int64)
        self.calls = []
        self.i = 0

    def integers(self, low, high=None, size=None):
        self.calls.append((low, high, size))
        if size != self.indices.shape[1]:
            raise AssertionError(f'unexpected bootstrap size {size!r}; expected {self.indices.shape[1]!r}')
        if self.i >= self.indices.shape[0]:
            raise AssertionError('too many bootstrap draws')
        row = self.indices[self.i].copy()
        self.i += 1
        return row


class TestOverallBootstrap(unittest.TestCase):
    def _api(self, name):
        self.assertTrue(hasattr(p11c, name), f'Task-5 API missing: {name}')
        return getattr(p11c, name)

    def _scores(self):
        return [
            make_score('P1', ar=1, gr=0, am=4, gm=3, ng=5),
            make_score('P2', ar=2, gr=1, am=3, gm=2, ng=2),
            make_score('P3', ar=3, gr=1, am=2, gm=2, ng=2),
            make_score('P4', ar=4, gr=1, am=1, gm=1, ng=0),
        ]

    def test_cvar90_divisible_by_10_uses_worst_ceil_ten_percent(self):
        cvar90 = self._api('cvar90')
        values = np.arange(1.0, 21.0)
        self.assertEqual(cvar90(values), 19.5)

    def test_cvar90_not_divisible_by_10_uses_ceiling(self):
        cvar90 = self._api('cvar90')
        values = np.arange(1.0, 12.0)
        self.assertEqual(cvar90(values), 10.5)

    def test_four_point_estimands_match_hand_fixture(self):
        overall_point_estimates = self._api('overall_point_estimates')
        got = overall_point_estimates(self._scores())
        self.assertAlmostEqual(got.A, 1.75)
        self.assertAlmostEqual(got.B, 0.25)
        self.assertAlmostEqual(got.C1, 3.0)
        self.assertAlmostEqual(got.C2, -1.0)

    def test_same_sampled_parent_indices_feed_all_four_statistics(self):
        overall_bootstrap = self._api('overall_bootstrap')
        overall_point_estimates = self._api('overall_point_estimates')
        scores = self._scores()[:3]
        indices = np.array([[0, 0, 1], [2, 2, 0]], dtype=np.int64)
        rng = ScriptedRNG(indices)
        got = overall_bootstrap(scores, rng, B=2)
        self.assertEqual(rng.calls, [(0, 3, 3), (0, 3, 3)])
        for b in range(2):
            sampled = [scores[i] for i in indices[b]]
            expected = overall_point_estimates(sampled)
            np.testing.assert_array_equal(
                got[b], np.array([expected.A, expected.B, expected.C1, expected.C2], dtype=np.float64)
            )

    def test_default_rng_is_pcg64_and_seed_replay_is_deterministic(self):
        overall_bootstrap = self._api('overall_bootstrap')
        scores = self._scores()
        rng1 = np.random.default_rng(1068199533)
        rng2 = np.random.default_rng(1068199533)
        self.assertEqual(type(rng1.bit_generator).__name__, 'PCG64')
        a = overall_bootstrap(scores, rng1, B=37)
        b = overall_bootstrap(scores, rng2, B=37)
        np.testing.assert_array_equal(a, b)

    def test_default_bootstrap_has_exactly_4000_four_statistic_replicates(self):
        overall_bootstrap = self._api('overall_bootstrap')
        got = overall_bootstrap(self._scores(), np.random.default_rng(1068199533))
        self.assertEqual(got.shape, (4000, 4))

    def test_bounds_use_numpy_linear_quantiles_and_context_interval_is_context_only(self):
        overall_bootstrap_bounds = self._api('overall_bootstrap_bounds')
        boot = np.arange(40.0, dtype=np.float64).reshape(10, 4)
        real_quantile = np.quantile
        calls = []

        def recording_quantile(a, q, *args, **kwargs):
            calls.append((q, kwargs.get('axis'), kwargs.get('method')))
            return real_quantile(a, q, *args, **kwargs)

        with mock.patch.object(p11c.np, 'quantile', side_effect=recording_quantile):
            summary = overall_bootstrap_bounds(boot)

        self.assertEqual(calls, [
            (0.95, 0, 'linear'),
            (0.025, 0, 'linear'),
            (0.975, 0, 'linear'),
        ])
        np.testing.assert_array_equal(
            np.array([summary.upper95.A, summary.upper95.B, summary.upper95.C1, summary.upper95.C2]),
            real_quantile(boot, q=0.95, axis=0, method='linear'),
        )
        self.assertTrue(summary.context_interval_only)
        self.assertEqual(summary.quantile_method, 'linear')
        self.assertEqual(summary.upper_quantile, 0.95)

    def test_deterministic_synthetic_replay_writes_identical_bootstrap_artifact_hash(self):
        overall_bootstrap = self._api('overall_bootstrap')
        write_bootstrap = self._api('write_and_verify_overall_bootstrap')
        scores = self._scores()
        a = overall_bootstrap(scores, np.random.default_rng(1068199533))
        b = overall_bootstrap(scores, np.random.default_rng(1068199533))
        with tempfile.TemporaryDirectory() as td:
            p1 = Path(td) / 'replay1' / 'AUTOGREY_V2_P11C_OVERALL_BOOTSTRAP_R1.csv'
            p2 = Path(td) / 'replay2' / 'AUTOGREY_V2_P11C_OVERALL_BOOTSTRAP_R1.csv'
            h1 = write_bootstrap(a, p1)
            h2 = write_bootstrap(b, p2)
            self.assertEqual(h1, h2)
            self.assertEqual(p1.read_bytes(), p2.read_bytes())
            with p1.open('r', encoding='utf-8', newline='') as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(len(rows), 4000)
            self.assertEqual(list(rows[0]), ['replicate', 'A', 'B', 'C1', 'C2'])

    def test_task5_functions_do_not_read_real_target_vectors(self):
        overall_point_estimates = self._api('overall_point_estimates')
        overall_bootstrap = self._api('overall_bootstrap')
        with mock.patch.object(p11c, 'read_target_vector', side_effect=AssertionError('numeric target access forbidden')) as read_target:
            scores = self._scores()
            overall_point_estimates(scores)
            overall_bootstrap(scores, np.random.default_rng(1068199533), B=5)
            read_target.assert_not_called()


if __name__ == '__main__':
    unittest.main()
