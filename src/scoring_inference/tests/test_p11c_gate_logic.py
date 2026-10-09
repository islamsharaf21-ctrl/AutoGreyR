import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'AUTOGREY_V2_P11C_FROZEN_CONFIRMATORY_SCORING_R1.py'
spec = importlib.util.spec_from_file_location('p11c_task6', SRC)
p11c = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = p11c
spec.loader.exec_module(p11c)


def points(a=-0.2, b=0.01, c1=-0.3, c2=0.02):
    return p11c.OverallPointEstimates(A=float(a), B=float(b), C1=float(c1), C2=float(c2))


def constant_bootstrap(a=-0.2, b=0.01, c1=-0.3, c2=0.02, n=40):
    row = np.array([a, b, c1, c2], dtype=np.float64)
    return np.tile(row, (n, 1))


class TestGateLogic(unittest.TestCase):
    def _api(self, name):
        self.assertTrue(hasattr(p11c, name), f'Task-6 API missing: {name}')
        return getattr(p11c, name)

    def test_strict_boundaries_equality_fails_for_all_four_numerical_tests(self):
        evaluate = self._api('evaluate_gates')
        d = evaluate(points(a=0.0, b=0.05, c1=0.0, c2=0.05), constant_bootstrap(a=0.0, b=0.05, c1=0.0, c2=0.05))
        self.assertEqual(d.gate_a_numerical, 'FAIL')
        self.assertEqual(d.gate_b_numerical, 'FAIL')
        self.assertEqual(d.gate_c1_numerical, 'FAIL')
        self.assertEqual(d.gate_c2_numerical, 'FAIL')
        self.assertEqual(d.gate_c_numerical, 'FAIL')
        self.assertEqual(d.overall_status, 'FAIL')

    def test_gate_a_failure_makes_b_and_c_descriptive_even_if_numerically_pass(self):
        evaluate = self._api('evaluate_gates')
        d = evaluate(points(), constant_bootstrap(a=0.001, b=0.01, c1=-0.3, c2=0.02))
        self.assertEqual(d.gate_a_numerical, 'FAIL')
        self.assertEqual(d.gate_b_numerical, 'PASS')
        self.assertEqual(d.gate_c_numerical, 'PASS')
        self.assertEqual(d.gate_a_confirmatory, 'FAIL')
        self.assertEqual(d.gate_b_confirmatory, 'DESCRIPTIVE_NONCONFIRMATORY')
        self.assertEqual(d.gate_c_confirmatory, 'DESCRIPTIVE_NONCONFIRMATORY')
        self.assertEqual(d.overall_status, 'FAIL')

    def test_a_pass_b_fail_preserves_a_claim_and_makes_c_descriptive(self):
        evaluate = self._api('evaluate_gates')
        d = evaluate(points(), constant_bootstrap(a=-0.2, b=0.05, c1=-0.3, c2=0.02))
        self.assertEqual(d.gate_a_confirmatory, 'PASS')
        self.assertEqual(d.gate_b_numerical, 'FAIL')
        self.assertEqual(d.gate_b_confirmatory, 'FAIL')
        self.assertTrue(d.gate_a_claim_may_stand)
        self.assertEqual(d.gate_c_confirmatory, 'DESCRIPTIVE_NONCONFIRMATORY')
        self.assertEqual(d.overall_status, 'FAIL')

    def test_gate_c_is_intersection_of_c1_and_c2(self):
        evaluate = self._api('evaluate_gates')
        c1_fail = evaluate(points(), constant_bootstrap(a=-0.2, b=0.01, c1=0.0, c2=0.02))
        c2_fail = evaluate(points(), constant_bootstrap(a=-0.2, b=0.01, c1=-0.3, c2=0.05))
        both_pass = evaluate(points(), constant_bootstrap(a=-0.2, b=0.01, c1=-0.3, c2=0.02))
        self.assertEqual(c1_fail.gate_c_numerical, 'FAIL')
        self.assertEqual(c2_fail.gate_c_numerical, 'FAIL')
        self.assertEqual(both_pass.gate_c_numerical, 'PASS')

    def test_overall_pass_requires_a_b_and_c_all_confirmatory_pass(self):
        evaluate = self._api('evaluate_gates')
        d = evaluate(points(), constant_bootstrap(a=-0.2, b=0.01, c1=-0.3, c2=0.02))
        self.assertEqual(d.gate_a_confirmatory, 'PASS')
        self.assertEqual(d.gate_b_confirmatory, 'PASS')
        self.assertEqual(d.gate_c_confirmatory, 'PASS')
        self.assertEqual(d.overall_status, 'PASS')
        self.assertTrue(d.full_confirmation_claim_allowed)

    def test_negative_or_partial_result_cannot_change_configuration_or_scientific_lock(self):
        evaluate = self._api('evaluate_gates')
        for boot in (
            constant_bootstrap(a=0.1, b=0.01, c1=-0.3, c2=0.02),
            constant_bootstrap(a=-0.2, b=0.1, c1=-0.3, c2=0.02),
            constant_bootstrap(a=-0.2, b=0.01, c1=0.1, c2=0.02),
        ):
            d = evaluate(points(), boot)
            self.assertFalse(d.configuration_change_allowed)
            self.assertFalse(d.scientific_lock_changed)
            self.assertTrue(d.negative_or_partial_result_preserved)

    def test_claim_discipline_forbids_equivalence_universal_and_unsupported_superiority(self):
        evaluate = self._api('evaluate_gates')
        d = evaluate(points(), constant_bootstrap())
        self.assertFalse(d.equivalence_to_ng10_claim_allowed)
        self.assertFalse(d.universal_superiority_claim_allowed)
        self.assertFalse(d.ng10_superiority_from_noninferiority_allowed)
        self.assertFalse(d.every_non_grey_superiority_claim_allowed)
        self.assertFalse(d.unqualified_generalization_claim_allowed)
        self.assertIn('Under the frozen REALBENCH3 protocol', d.allowed_claim_text)
        self.assertIn('within 0.05 MASE', d.allowed_claim_text)

    def test_task6_writers_create_deterministic_overall_results_and_decision_artifacts(self):
        evaluate = self._api('evaluate_gates')
        write_results = self._api('write_overall_results')
        write_decision = self._api('write_confirmatory_decision')
        p = points()
        boot = constant_bootstrap()
        d = evaluate(p, boot)
        with tempfile.TemporaryDirectory() as td1, tempfile.TemporaryDirectory() as td2:
            td1 = Path(td1); td2 = Path(td2)
            r1 = td1 / 'AUTOGREY_V2_P11C_OVERALL_RESULTS_R1.json'
            q1 = td1 / 'AUTOGREY_V2_P11C_CONFIRMATORY_DECISION_R1.txt'
            r2 = td2 / r1.name; q2 = td2 / q1.name
            h_r1 = write_results(p, boot, d, r1)
            h_q1 = write_decision(d, q1)
            h_r2 = write_results(p, boot, d, r2)
            h_q2 = write_decision(d, q2)
            self.assertEqual(h_r1, h_r2)
            self.assertEqual(h_q1, h_q2)
            rec = json.loads(r1.read_text(encoding='utf-8'))
            self.assertEqual(rec['schema'], 'AUTOGREY_V2_P11C_OVERALL_RESULTS_R1')
            self.assertEqual(rec['fixed_sequence'], ['A', 'B', 'C'])
            self.assertEqual(rec['overall_status'], 'PASS')
            self.assertEqual(rec['gate_status']['C']['confirmatory'], 'PASS')
            text = q1.read_text(encoding='utf-8')
            self.assertIn('OVERALL_STATUS=PASS', text)
            self.assertIn('SCIENTIFIC_LOCK_CHANGED=FALSE', text)
            self.assertIn('CONFIGURATION_CHANGE_ALLOWED=FALSE', text)

    def test_task6_gate_logic_and_writers_do_not_read_target_vectors(self):
        evaluate = self._api('evaluate_gates')
        write_results = self._api('write_overall_results')
        write_decision = self._api('write_confirmatory_decision')
        p = points(); boot = constant_bootstrap()
        with mock.patch.object(p11c, 'read_target_vector', side_effect=AssertionError('target read forbidden')) as m:
            d = evaluate(p, boot)
            with tempfile.TemporaryDirectory() as td:
                td = Path(td)
                write_results(p, boot, d, td / 'results.json')
                write_decision(d, td / 'decision.txt')
            m.assert_not_called()


if __name__ == '__main__':
    unittest.main()
