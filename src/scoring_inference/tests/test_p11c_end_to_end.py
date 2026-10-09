import hashlib
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
spec = importlib.util.spec_from_file_location('p11c_task8', SRC)
p11c = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = p11c
spec.loader.exec_module(p11c)

REQUIRED_OUTPUTS = [
    'AUTOGREY_V2_P11C_PARENT_SCORES_R1.csv',
    'AUTOGREY_V2_P11C_OVERALL_BOOTSTRAP_R1.csv',
    'AUTOGREY_V2_P11C_OVERALL_RESULTS_R1.json',
    'AUTOGREY_V2_P11C_SUBGROUP_RESULTS_R1.csv',
    'AUTOGREY_V2_P11C_SUBGROUP_AUDIT_R1.json',
    'AUTOGREY_V2_P11C_CONFIRMATORY_DECISION_R1.txt',
    'AUTOGREY_V2_P11C_ASSERTIONS_R1.json',
    'AUTOGREY_V2_P11C_MANIFEST_R1.sha256',
]


def fh(label):
    return hashlib.sha256(label.encode('utf-8')).hexdigest().upper()


def make_score(pid, *, source='SYN', h=1, ar=0.0, gr=1.0, am=1.0, ng=2.0):
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
        global_mase=float(gr + 1.0),
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


def make_scores(kind='full_pass', n=12):
    if kind == 'full_pass':
        vals = dict(ar=0.0, gr=1.0, am=1.0, ng=2.0)
    elif kind == 'gate_a_fail':
        vals = dict(ar=1.0, gr=0.0, am=1.0, ng=2.0)
    elif kind == 'a_pass_b_fail':
        vals = dict(ar=0.0, gr=1.0, am=2.0, ng=1.0)
    else:
        raise ValueError(kind)
    return [make_score(f'P{i:03d}', source=('S1' if i % 2 == 0 else 'S2'), h=1, **vals) for i in range(n)]


def make_scoring_state(base: Path, n=12):
    base.mkdir(parents=True, exist_ok=True)
    dev_vals = []
    tar_vals = []
    dev_index = {}
    target_index = {}
    rows = {k: [] for k in ('autogrey', 'global', 'ng10', 'subgroup', 'grey', 'actionability')}
    deployed = []
    for j in range(n):
        pid = f'P{j:03d}'
        deployed.append(pid)
        source = 'S1' if j % 2 == 0 else 'S2'
        h = 2
        D = [1.0, 3.0, 6.0, 10.0]
        y = [11.0 + j, 14.0 + j]
        dev_off = len(dev_vals) * 8
        tar_off = len(tar_vals) * 8
        dev_vals.extend(D)
        tar_vals.extend(y)
        dev_index[pid] = {
            'parent_id': pid, 'source_id': source, 'h': str(h), 'M': '1',
            'n_D_token_count': '4', 'binary_offset_bytes': str(dev_off),
            'binary_length_values': '4', 'binary_length_bytes': '32',
        }
        target_index[pid] = {
            'parent_id': pid, 'source_id': source, 'h': str(h), 'M': '1',
            'binary_offset_bytes': str(tar_off), 'binary_length_values': '2',
            'binary_length_bytes': '16',
        }
        good = y
        bad = [y[0] + 3.0, y[1] + 3.0]
        ng = [y[0] + 2.0, y[1] + 2.0]
        hgood = fh(f'{pid}|GOOD')
        hbad = fh(f'{pid}|BAD')
        hng = fh(f'{pid}|NG10')
        for step, value in enumerate(good, 1):
            rows['grey'].append({'parent_id': pid, 'source_id': source, 'h': str(h), 'group': 'SG_GOOD', 'step': str(step), 'forecast': str(value), 'forecast_sha256': hgood})
        for step, value in enumerate(bad, 1):
            rows['grey'].append({'parent_id': pid, 'source_id': source, 'h': str(h), 'group': 'SG_BAD', 'step': str(step), 'forecast': str(value), 'forecast_sha256': hbad})
        for step, value in enumerate(ng, 1):
            rows['ng10'].append({'parent_id': pid, 'source_id': source, 'h': str(h), 'status': 'OK_3OF3', 'components_successful': '3', 'used': 'T+E+A', 'component_statuses': 'OK', 'step': str(step), 'forecast': str(value), 'forecast_sha256': hng})
        rows['autogrey'].append({'parent_id': pid, 'source_id': source, 'h': str(h), 'action_count': '2', 'selection_mode': 'SELECTOR', 'selected_group': 'SG_GOOD', 'predicted_log1p_regret': '0', 'forecast_sha256': hgood})
        rows['global'].append({'parent_id': pid, 'source_id': source, 'h': str(h), 'action_count': '2', 'selection_mode': 'GLOBAL', 'selected_group': 'SG_BAD', 'forecast_sha256': hbad})
        rows['subgroup'].append({
            'parent_id': pid, 'source_id': source, 'h': str(h), 'clean_h_n': str(n), 'clean_source_n': str(n // 2), 'clean_source_x_h_n': str(n // 2),
            'selection_pair_eligible': 'TRUE', 'selection_h_n': str(n), 'selection_source_n': str(n // 2), 'selection_source_x_h_n': str(n // 2),
            'selection_h_inferential_eligible': 'FALSE', 'selection_source_inferential_eligible': 'FALSE', 'selection_source_x_h_inferential_eligible': 'FALSE',
            'practical_pair_eligible': 'TRUE', 'practical_h_n': str(n), 'practical_source_n': str(n // 2), 'practical_source_x_h_n': str(n // 2),
            'practical_h_inferential_eligible': 'FALSE', 'practical_source_inferential_eligible': 'FALSE', 'practical_source_x_h_inferential_eligible': 'FALSE',
        })
        rows['actionability'].append({
            'parent_id': pid, 'source_id': source, 'h': str(h), 'M': '1', 'n_D': '4', 'available_pre_collision': '2',
            'retained_post_collision': '2', 'resolution_status': 'SELECTOR_MAY_ACT_LATER', 'retained_groups': 'SG_BAD;SG_GOOD', 'removed_groups': '',
            'selector_pair_eligible': 'TRUE', 'practical_pair_eligible': 'TRUE', 'ng10_status': 'OK_3OF3',
        })
    dev_bin = base / 'D.bin'
    tar_bin = base / 'Y.bin'
    np.asarray(dev_vals, dtype='<f8').tofile(dev_bin)
    np.asarray(tar_vals, dtype='<f8').tofile(tar_bin)
    full = set(deployed) | {'ND001', 'ND002', 'ND003'}
    return p11c.PreflightState(
        full_parent_ids=frozenset(full),
        deployed_parent_ids=frozenset(deployed),
        nondeployed_parent_ids=('ND001', 'ND002', 'ND003'),
        files={'dev_binary': dev_bin, 'target_binary': tar_bin},
        rows=rows,
        grey_vector_hashes={(r['parent_id'], r['group']): r['forecast_sha256'] for r in rows['grey']},
        ng10_vector_hashes={r['parent_id']: r['forecast_sha256'] for r in rows['ng10']},
        target_binary_numeric_reads=0,
        development_index=dev_index,
        target_index=target_index,
    )


def load_preflight_fixture_module():
    path = ROOT / 'tests' / 'test_p11c_preflight.py'
    spec2 = importlib.util.spec_from_file_location('task8_preflight_fixture', path)
    mod = importlib.util.module_from_spec(spec2)
    sys.modules[spec2.name] = mod
    spec2.loader.exec_module(mod)
    return mod


class TestEndToEndTask8(unittest.TestCase):
    def _api(self, name):
        self.assertTrue(hasattr(p11c, name), f'Task-8 API missing: {name}')
        return getattr(p11c, name)

    def test_score_free_preflight_synthetic_run_never_reads_numeric_target_values(self):
        execute_preflight = self._api('execute_preflight')
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            state = make_scoring_state(td)
            dummy = p11c.EntryPaths(td, td, td, td, td / 'r4.zip')
            with mock.patch.object(p11c, 'verify_entry_gate', return_value=state), \
                 mock.patch.object(p11c, 'read_target_vector', side_effect=AssertionError('numeric target read forbidden')) as rt:
                returned = execute_preflight(dummy, td / 'preflight')
                rt.assert_not_called()
            self.assertIs(returned, state)
            rec = json.loads((td / 'preflight' / 'AUTOGREY_V2_P11C_PREFLIGHT_R1.json').read_text(encoding='utf-8'))
            self.assertFalse(rec['target_binary_numeric_values_read'])
            self.assertFalse(rec['scientific_scoring_performed'])
            self.assertTrue(rec['target_index_binary_slice_schema_bound'])
            self.assertEqual(state.target_binary_numeric_reads, 0)

    def test_full_scoring_synthetic_run_produces_all_required_artifacts(self):
        run_scoring_state = self._api('run_scoring_state')
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            state = make_scoring_state(td)
            out = td / 'score'
            result = run_scoring_state(state, out)
            self.assertEqual(sorted(p.name for p in out.iterdir()), sorted(REQUIRED_OUTPUTS))
            self.assertEqual(state.target_binary_numeric_reads, len(state.deployed_parent_ids))
            self.assertEqual(result['decision'].overall_status, 'PASS')
            self.assertEqual(result['subgroup_audit']['subgroup_role'], 'SECONDARY')

    def test_synthetic_negative_gate_a_result_is_preserved_without_retuning(self):
        seal = self._api('seal_scientific_outputs')
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / 'negative'
            result = seal(make_scores('gate_a_fail'), out)
            self.assertEqual(result['decision'].gate_a_confirmatory, 'FAIL')
            self.assertEqual(result['decision'].overall_status, 'FAIL')
            assertions = json.loads((out / 'AUTOGREY_V2_P11C_ASSERTIONS_R1.json').read_text(encoding='utf-8'))
            self.assertTrue(assertions['negative_or_partial_result_preserved'])
            self.assertFalse(assertions['configuration_change_allowed'])
            self.assertFalse(assertions['scientific_lock_changed'])

    def test_synthetic_a_pass_b_fail_has_frozen_confirmatory_labels(self):
        seal = self._api('seal_scientific_outputs')
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / 'partial'
            result = seal(make_scores('a_pass_b_fail'), out)
            d = result['decision']
            self.assertEqual(d.gate_a_confirmatory, 'PASS')
            self.assertEqual(d.gate_b_confirmatory, 'FAIL')
            self.assertEqual(d.gate_c_confirmatory, 'DESCRIPTIVE_NONCONFIRMATORY')
            self.assertEqual(d.overall_status, 'FAIL')
            text = (out / 'AUTOGREY_V2_P11C_CONFIRMATORY_DECISION_R1.txt').read_text(encoding='utf-8')
            self.assertIn('GATE_A_CONFIRMATORY=PASS', text)
            self.assertIn('GATE_B_CONFIRMATORY=FAIL', text)
            self.assertIn('GATE_C_CONFIRMATORY=DESCRIPTIVE_NONCONFIRMATORY', text)

    def test_synthetic_full_pass_uses_only_frozen_constrained_claim_wording(self):
        seal = self._api('seal_scientific_outputs')
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / 'pass'
            result = seal(make_scores('full_pass'), out)
            d = result['decision']
            self.assertEqual(d.overall_status, 'PASS')
            self.assertTrue(d.full_confirmation_claim_allowed)
            self.assertEqual(d.allowed_claim_text, p11c.FULL_CONFIRMATION_CLAIM)
            self.assertFalse(d.equivalence_to_ng10_claim_allowed)
            self.assertFalse(d.universal_superiority_claim_allowed)
            self.assertFalse(d.ng10_superiority_from_noninferiority_allowed)

    def test_existing_output_path_aborts_before_any_scoring(self):
        run_scoring_state = self._api('run_scoring_state')
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            state = make_scoring_state(td)
            out = td / 'already_exists'
            out.mkdir()
            sentinel = out / 'keep.txt'
            sentinel.write_text('do not overwrite\n', encoding='utf-8')
            with mock.patch.object(p11c, 'score_all_parents', side_effect=AssertionError('must not score')) as s:
                with self.assertRaises(FileExistsError):
                    run_scoring_state(state, out)
                s.assert_not_called()
            self.assertEqual(sentinel.read_text(encoding='utf-8'), 'do not overwrite\n')

    def test_tampered_input_hash_aborts_before_scoring(self):
        execute_scoring = self._api('execute_scoring')
        fixture = load_preflight_fixture_module()
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            fixture_root = td / 'fixture'
            fixture_root.mkdir()
            other_mod, paths, cfg = fixture.build_fixture(fixture_root)
            p = paths.p10 / other_mod.NAMES['p10a']
            p.write_text('tampered\n', encoding='utf-8')
            with mock.patch.object(p11c, 'score_all_parents', side_effect=AssertionError('must not score')) as s:
                with self.assertRaisesRegex(AssertionError, 'SHA-256 mismatch'):
                    execute_scoring(paths, td / 'score', config=cfg)
                s.assert_not_called()
            self.assertFalse((td / 'score').exists())

    def test_deterministic_full_synthetic_repeat_yields_identical_scientific_artifacts(self):
        run_scoring_state = self._api('run_scoring_state')
        # Independent roots keep fixture paths distinct while scientific bytes remain identical.
        with tempfile.TemporaryDirectory() as tda, tempfile.TemporaryDirectory() as tdb:
            a = Path(tda); b = Path(tdb)
            s1 = make_scoring_state(a)
            s2 = make_scoring_state(b)
            out1 = a / 'out'; out2 = b / 'out'
            run_scoring_state(s1, out1)
            run_scoring_state(s2, out2)
            for name in REQUIRED_OUTPUTS:
                self.assertEqual((out1 / name).read_bytes(), (out2 / name).read_bytes(), name)

    def test_assertions_and_decision_preserve_frozen_history_population_and_locks(self):
        seal = self._api('seal_scientific_outputs')
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / 'seal'
            seal(make_scores('full_pass'), out, full_census_n=15, deployed_n=12, nondeployed_n=3, target_numeric_reads=12)
            assertions = json.loads((out / 'AUTOGREY_V2_P11C_ASSERTIONS_R1.json').read_text(encoding='utf-8'))
            self.assertEqual(assertions['p11c0_history']['R1'], 'INCONCLUSIVE_HARNESS_ROLE_CLASSIFICATION_BUG')
            self.assertEqual(assertions['p11c0_history']['R2'], 'INCONCLUSIVE_HARNESS_POPULATION_ASSUMPTION_BUG')
            self.assertEqual(assertions['p11c0_history']['R3'], 'INCONCLUSIVE_HARNESS_SCHEMA_NAME_MISMATCH')
            self.assertEqual(assertions['p11c0_history']['R4'], 'PASS_CLOSED')
            self.assertEqual(assertions['p11c0_r4_evidence_zip_sha256'], p11c.DEFAULT_EXPECTED_HASHES['r4_evidence'])
            self.assertEqual(assertions['p11b_status'], 'PASS_CLOSED')
            self.assertEqual(assertions['realbench3_target_state'], 'PERMANENTLY_OPEN')
            self.assertEqual(assertions['population'], {'full_clean_census_n': 15, 'deployed_scoring_parent_n': 12, 'frozen_nondeployed_clean_parent_n': 3})
            self.assertEqual(assertions['subgroup_role'], 'SECONDARY')
            self.assertFalse(assertions['scientific_lock_changed'])
            self.assertTrue(assertions['p12_locked'])
            text = (out / 'AUTOGREY_V2_P11C_CONFIRMATORY_DECISION_R1.txt').read_text(encoding='utf-8')
            for needle in ('P11C0_R1=INCONCLUSIVE_HARNESS_ROLE_CLASSIFICATION_BUG', 'P11C0_R4=PASS_CLOSED', 'P11B=PASS_CLOSED', 'REALBENCH3_TARGET_STATE=PERMANENTLY_OPEN', 'FULL_CLEAN_CENSUS_N=15', 'DEPLOYED_SCORING_PARENT_N=12', 'FROZEN_NONDEPLOYED_CLEAN_PARENT_N=3', 'SUBGROUP_ROLE=SECONDARY', 'SCIENTIFIC_LOCK_CHANGED=FALSE', 'P12=LOCKED'):
                self.assertIn(needle, text)

    def test_output_manifest_hashes_all_seven_pre_manifest_artifacts_and_verifies(self):
        seal = self._api('seal_scientific_outputs')
        verify_manifest = self._api('verify_output_manifest')
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / 'manifest'
            seal(make_scores('full_pass'), out)
            manifest = out / 'AUTOGREY_V2_P11C_MANIFEST_R1.sha256'
            entries = [line.split(None, 1) for line in manifest.read_text(encoding='utf-8').splitlines() if line.strip()]
            self.assertEqual(len(entries), 7)
            self.assertEqual({name.strip() for _, name in entries}, set(REQUIRED_OUTPUTS[:-1]))
            self.assertTrue(verify_manifest(out, manifest))
            for h, name in entries:
                self.assertEqual(h, p11c.sha256(out / name.strip()))


if __name__ == '__main__':
    unittest.main()
