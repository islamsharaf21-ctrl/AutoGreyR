import csv
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'AUTOGREY_V2_P11C_FROZEN_CONFIRMATORY_SCORING_R1.py'
spec = importlib.util.spec_from_file_location('p11c_task7', SRC)
p11c = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = p11c
spec.loader.exec_module(p11c)


def make_score(pid, *, source='SYN', h=1, ar=0.0, gr=1.0, am=1.0, gm=1.5, ng=2.0):
    return p11c.ParentScore(
        parent_id=pid,
        source_id=source,
        h=int(h),
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
        subgroup_h=str(h),
        subgroup_source=source,
        subgroup_source_x_h=f'{source}|{h}',
        autogrey_forecast_sha256='A' * 64,
        global_forecast_sha256='B' * 64,
        ng10_forecast_sha256='C' * 64,
        eligible_action_forecast_hashes_json='{"SG01":"' + ('A' * 64) + '","SG02":"' + ('B' * 64) + '"}',
    )


class CountingRNG:
    def __init__(self, n):
        self.n = n
        self.calls = []
        self.i = 0
        self.bit_generator = np.random.PCG64(123)

    def integers(self, low, high=None, size=None):
        self.calls.append((low, high, size))
        if size != self.n:
            raise AssertionError(f'unexpected size={size}; expected={self.n}')
        # Alternate deterministic paired-parent samples. One call per replicate is the contract.
        if self.i % 2 == 0:
            out = np.arange(self.n, dtype=np.int64)
        else:
            out = np.arange(self.n - 1, -1, -1, dtype=np.int64)
        self.i += 1
        return out


class TestSubgroups(unittest.TestCase):
    def _api(self, name):
        self.assertTrue(hasattr(p11c, name), f'Task-7 API missing: {name}')
        return getattr(p11c, name)

    def test_holm_adjust_matches_step_down_adjusted_pvalues(self):
        holm_adjust = self._api('holm_adjust')
        got = holm_adjust([0.01, 0.04, 0.03])
        np.testing.assert_allclose(got, [0.03, 0.06, 0.06], rtol=0, atol=0)

    def test_dimensions_are_frozen_order_and_labels_lexicographic(self):
        run_subgroups = self._api('run_subgroups')
        scores = [
            make_score('p1', source='B', h=2),
            make_score('p2', source='A', h=1),
            make_score('p3', source='B', h=1),
            make_score('p4', source='A', h=2),
        ]
        rows, audit = run_subgroups(scores, np.random.default_rng(1068199533))
        got = [(r['dimension'], r['label']) for r in rows]
        self.assertEqual(got, [
            ('horizon', '1'), ('horizon', '2'),
            ('source', 'A'), ('source', 'B'),
            ('source_x_h', 'A|1'), ('source_x_h', 'A|2'), ('source_x_h', 'B|1'), ('source_x_h', 'B|2'),
        ])
        self.assertEqual(audit['dimension_order'], ['horizon', 'source', 'source_x_h'])

    def test_n_below_30_is_descriptive_only(self):
        run_subgroups = self._api('run_subgroups')
        rows, audit = run_subgroups([make_score(f'p{i:02d}') for i in range(29)], np.random.default_rng(3))
        for r in rows:
            self.assertFalse(r['inference_allowed'])
            self.assertEqual(r['n'], 29)
            for name in ('A', 'B', 'C1', 'C2'):
                self.assertIsInstance(r[f'point_{name}'], float)
                self.assertIsNone(r[f'raw_p_{name}'])
                self.assertIsNone(r[f'holm_p_{name}'])
                self.assertIsNone(r[f'holm_reject_{name}'])
        self.assertEqual(audit['inferential_subgroup_n'], 0)

    def test_inferential_pvalue_uses_frozen_plus_one_formula(self):
        run_subgroups = self._api('run_subgroups')
        # Every contrast is exactly -1. Every bootstrap replicate is therefore <0,
        # so count(diff >= 0)=0 and p=1/(4000+1).
        scores = [make_score(f'p{i:02d}', ar=0, gr=1, am=1, ng=2) for i in range(30)]
        rows, _ = run_subgroups(scores, np.random.default_rng(77))
        for r in rows:
            self.assertTrue(r['inference_allowed'])
            for name in ('A', 'B', 'C1', 'C2'):
                self.assertEqual(r[f'raw_p_{name}'], 1.0 / 4001.0)

    def test_one_subgroup_draw_per_replicate_is_shared_across_all_four_statistics(self):
        run_subgroups = self._api('run_subgroups')
        scores = [make_score(f'p{i:02d}') for i in range(30)]
        rng = CountingRNG(30)
        rows, audit = run_subgroups(scores, rng)
        # Three inferential subgroup rows exist: one horizon, one source, one source_x_h.
        self.assertEqual(len(rows), 3)
        self.assertEqual(len(rng.calls), 3 * 4000)
        self.assertTrue(all(call == (0, 30, 30) for call in rng.calls))
        self.assertTrue(audit['same_sampled_indices_for_all_four_stats'])

    def test_rng_stream_is_caller_supplied_and_can_continue_after_overall_bootstrap(self):
        run_subgroups = self._api('run_subgroups')
        overall_bootstrap = self._api('overall_bootstrap')
        scores = [make_score(f'p{i:02d}', ar=(i % 5) / 10, gr=1, am=1 + (i % 7) / 10, ng=2) for i in range(30)]

        rng1 = np.random.default_rng(1068199533)
        overall_bootstrap(scores, rng1)  # consumes the frozen overall 4000-replicate stream first
        rows1, audit1 = run_subgroups(scores, rng1)

        rng2 = np.random.default_rng(1068199533)
        overall_bootstrap(scores, rng2)
        rows2, audit2 = run_subgroups(scores, rng2)
        self.assertEqual(rows1, rows2)
        self.assertEqual(audit1['subgroup_resample_index_sha256'], audit2['subgroup_resample_index_sha256'])

        fresh = np.random.default_rng(1068199533)
        _, audit_fresh = run_subgroups(scores, fresh)
        self.assertNotEqual(audit1['subgroup_resample_index_sha256'], audit_fresh['subgroup_resample_index_sha256'])
        self.assertEqual(audit1['rng_stream_policy'], 'CONTINUE_CALLER_SUPPLIED_PCG64_AFTER_OVERALL_BOOTSTRAP')

    def test_holm_is_applied_separately_to_four_frozen_families(self):
        run_subgroups = self._api('run_subgroups')
        holm_adjust = self._api('holm_adjust')
        scores = []
        for source, shift in [('A', -0.3), ('B', 0.2)]:
            for i in range(30):
                # Different families receive deliberately different contrast patterns.
                scores.append(make_score(
                    f'{source}{i:02d}', source=source, h=1,
                    ar=0.2 + (i % 3) * 0.1,
                    gr=0.5,
                    am=1.0 + (i % 4) * 0.1 + shift,
                    ng=1.3,
                ))
        rows, audit = run_subgroups(scores, np.random.default_rng(1234))
        inferential = [r for r in rows if r['inference_allowed']]
        self.assertEqual(audit['holm_family_order'], ['A', 'C1', 'B', 'C2'])
        self.assertEqual(audit['holm_fwer'], 0.05)
        for family in ('A', 'C1', 'B', 'C2'):
            raw = [r[f'raw_p_{family}'] for r in inferential]
            expected = holm_adjust(raw)
            got = [r[f'holm_p_{family}'] for r in inferential]
            np.testing.assert_allclose(got, expected, rtol=0, atol=0)

    def test_subgroups_are_secondary_and_do_not_mutate_overall_decision(self):
        run_subgroups = self._api('run_subgroups')
        evaluate_gates = self._api('evaluate_gates')
        points = p11c.OverallPointEstimates(A=-0.2, B=0.0, C1=-0.1, C2=0.0)
        boot = np.tile(np.array([-0.1, 0.01, -0.05, 0.02], dtype=float), (4000, 1))
        before = evaluate_gates(points, boot)
        scores = [make_score(f'p{i:02d}') for i in range(30)]
        _, audit = run_subgroups(scores, np.random.default_rng(99))
        after = evaluate_gates(points, boot)
        self.assertEqual(before, after)
        self.assertEqual(audit['subgroup_role'], 'SECONDARY')
        self.assertFalse(audit['may_alter_overall_confirmatory_classification'])

    def test_task7_writers_are_deterministic_and_do_not_read_real_targets(self):
        run_subgroups = self._api('run_subgroups')
        write_results = self._api('write_and_verify_subgroup_results')
        write_audit = self._api('write_subgroup_audit')
        scores = [make_score(f'p{i:02d}') for i in range(30)]
        with mock.patch.object(p11c, 'read_target_vector', side_effect=AssertionError('real target access forbidden')) as rt:
            rows1, audit1 = run_subgroups(scores, np.random.default_rng(5))
            rows2, audit2 = run_subgroups(scores, np.random.default_rng(5))
            rt.assert_not_called()
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            h1 = write_results(rows1, td / 'r1' / 'AUTOGREY_V2_P11C_SUBGROUP_RESULTS_R1.csv')
            h2 = write_results(rows2, td / 'r2' / 'AUTOGREY_V2_P11C_SUBGROUP_RESULTS_R1.csv')
            a1 = write_audit(audit1, td / 'r1' / 'AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1.json')
            a2 = write_audit(audit2, td / 'r2' / 'AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1.json')
            self.assertEqual(h1, h2)
            self.assertEqual(a1, a2)
            self.assertEqual((td/'r1'/'AUTOGREY_V2_P11C_SUBGROUP_RESULTS_R1.csv').read_bytes(),
                             (td/'r2'/'AUTOGREY_V2_P11C_SUBGROUP_RESULTS_R1.csv').read_bytes())
            self.assertEqual((td/'r1'/'AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1.json').read_bytes(),
                             (td/'r2'/'AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1.json').read_bytes())
            with (td/'r1'/'AUTOGREY_V2_P11C_SUBGROUP_RESULTS_R1.csv').open(newline='', encoding='utf-8') as f:
                csv_rows = list(csv.DictReader(f))
            self.assertTrue(csv_rows)
            audit_json = json.loads((td/'r1'/'AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1.json').read_text(encoding='utf-8'))
            self.assertEqual(audit_json['bootstrap_B'], 4000)
            self.assertEqual(audit_json['rng_bit_generator'], 'PCG64')


if __name__ == '__main__':
    unittest.main()
