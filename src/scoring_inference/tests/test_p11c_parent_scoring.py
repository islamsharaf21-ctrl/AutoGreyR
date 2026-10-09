import csv
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'AUTOGREY_V2_P11C_FROZEN_CONFIRMATORY_SCORING_R1.py'
spec = importlib.util.spec_from_file_location('p11c_task4', SRC)
p11c = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = p11c
spec.loader.exec_module(p11c)


def fh(label):
    return hashlib.sha256(label.encode()).hexdigest().upper()


class TestParentScoring(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.addCleanup(self.td.cleanup)
        self.base = Path(self.td.name)

    def _bin(self, name, values):
        p = self.base / name
        np.asarray(values, dtype='<f8').tofile(p)
        return p

    def _state(self, *, parents=('B','A'), bad_second=False, count_mismatch=False):
        # D series: [1,3,6,10] => non-seasonal scale = 3.
        # Each parent has h=2 and a distinct target vector in the shared binary.
        dev_vals=[]; tar_vals=[]
        dev_index={}; target_index={}
        rows={k:[] for k in ('autogrey','global','ng10','subgroup','grey','actionability')}
        for j,pid in enumerate(parents):
            d=[1.,3.,6.,10.]
            y=[11.+j, 14.+j]
            doff=len(dev_vals)*8; toff=len(tar_vals)*8
            dev_vals.extend(d); tar_vals.extend(y)
            dev_index[pid]={
                'parent_id':pid,'source_id':'S2' if pid=='B' else 'S1','h':'2','M':'1',
                'n_D_token_count':'4','binary_offset_bytes':str(doff),
                'binary_length_values':'4','binary_length_bytes':'32'
            }
            target_index[pid]={
                'parent_id':pid,'source_id':'S2' if pid=='B' else 'S1','h':'2',
                'binary_offset_bytes':str(toff),'binary_length_values':'2','binary_length_bytes':'16'
            }

            source=dev_index[pid]['source_id']
            # SG01: exact-ish best; SG02: worse. AutoGrey picks SG02, GLOBAL SG01.
            g1=[11.+j, 14.+j]
            g2=[10.+j, 16.+j]
            ng=[12.+j, 13.+j]
            h1=fh(f'{pid}|SG01'); h2=fh(f'{pid}|SG02'); hn=fh(f'{pid}|NG10')
            for step,val in enumerate(g1,1):
                rows['grey'].append({'parent_id':pid,'source_id':source,'h':'2','group':'SG01','step':str(step),'forecast':str(val),'forecast_sha256':h1})
            for step,val in enumerate(g2,1):
                if bad_second and pid == parents[-1] and step == 2:
                    val = 'nan'
                rows['grey'].append({'parent_id':pid,'source_id':source,'h':'2','group':'SG02','step':str(step),'forecast':str(val),'forecast_sha256':h2})
            for step,val in enumerate(ng,1):
                rows['ng10'].append({'parent_id':pid,'source_id':source,'h':'2','status':'OK_3OF3','components_successful':'3','used':'T+E+A','component_statuses':'OK','step':str(step),'forecast':str(val),'forecast_sha256':hn})
            rows['autogrey'].append({'parent_id':pid,'source_id':source,'h':'2','action_count':'2','selection_mode':'SELECTOR','selected_group':'SG02','predicted_log1p_regret':'0.1','forecast_sha256':h2})
            rows['global'].append({'parent_id':pid,'source_id':source,'h':'2','action_count':'2','selection_mode':'GLOBAL','selected_group':'SG01','forecast_sha256':h1})
            rows['subgroup'].append({
                'parent_id':pid,'source_id':source,'h':'2','clean_h_n':'10','clean_source_n':'10','clean_source_x_h_n':'10',
                'selection_pair_eligible':'TRUE','selection_h_n':'10','selection_source_n':'10','selection_source_x_h_n':'10',
                'selection_h_inferential_eligible':'TRUE','selection_source_inferential_eligible':'TRUE','selection_source_x_h_inferential_eligible':'TRUE',
                'practical_pair_eligible':'TRUE','practical_h_n':'10','practical_source_n':'10','practical_source_x_h_n':'10',
                'practical_h_inferential_eligible':'TRUE','practical_source_inferential_eligible':'TRUE','practical_source_x_h_inferential_eligible':'TRUE'
            })
            rows['actionability'].append({
                'parent_id':pid,'source_id':source,'h':'2','M':'1','n_D':'4','available_pre_collision':'2',
                'retained_post_collision':('3' if count_mismatch else '2'),'resolution_status':'SELECTOR_MAY_ACT_LATER',
                'retained_groups':'SG01;SG02','removed_groups':'','selector_pair_eligible':'TRUE','practical_pair_eligible':'TRUE','ng10_status':'OK_3OF3'
            })

        dev_bin=self._bin('D.bin',dev_vals); tar_bin=self._bin('Y.bin',tar_vals)
        return p11c.PreflightState(
            full_parent_ids=frozenset(parents),
            deployed_parent_ids=frozenset(parents),
            nondeployed_parent_ids=(),
            files={'dev_binary':dev_bin,'target_binary':tar_bin},
            rows=rows,
            grey_vector_hashes={(r['parent_id'],r['group']):r['forecast_sha256'] for r in rows['grey']},
            ng10_vector_hashes={r['parent_id']:r['forecast_sha256'] for r in rows['ng10']},
            target_binary_numeric_reads=0,
            development_index=dev_index,
            target_index=target_index,
        )

    def test_score_parent_oracle_regret_and_practical_mase(self):
        state=self._state(parents=('A',))
        s=p11c.score_parent('A',state)
        self.assertEqual(s.parent_id,'A')
        self.assertEqual(s.eligible_action_count,2)
        self.assertEqual(s.autogrey_selected_group,'SG02')
        self.assertEqual(s.global_selected_group,'SG01')
        self.assertAlmostEqual(s.mase_scale,3.0)
        self.assertAlmostEqual(s.eligible_oracle_mase,0.0)
        self.assertAlmostEqual(s.autogrey_mase,0.5)
        self.assertAlmostEqual(s.global_mase,0.0)
        self.assertAlmostEqual(s.ng10_mase,1/3)
        self.assertAlmostEqual(s.autogrey_regret,0.5)
        self.assertAlmostEqual(s.global_regret,0.0)
        self.assertAlmostEqual(s.delta_selection_regret,0.5)
        self.assertAlmostEqual(s.delta_practical_mase,0.5-(1/3))

    def test_score_parent_uses_frozen_selected_group_vector_and_hashes(self):
        state=self._state(parents=('A',))
        s=p11c.score_parent('A',state)
        self.assertEqual(s.autogrey_forecast_sha256, fh('A|SG02'))
        self.assertEqual(s.global_forecast_sha256, fh('A|SG01'))
        self.assertEqual(s.ng10_forecast_sha256, fh('A|NG10'))
        mapping=json.loads(s.eligible_action_forecast_hashes_json)
        self.assertEqual(mapping, {'SG01':fh('A|SG01'),'SG02':fh('A|SG02')})

    def test_score_parent_rejects_retained_action_count_mismatch(self):
        state=self._state(parents=('A',), count_mismatch=True)
        with self.assertRaisesRegex(AssertionError,'retained action count mismatch'):
            p11c.score_parent('A',state)

    def test_score_all_parents_sorted_and_no_silent_deletion(self):
        state=self._state(parents=('B','A'))
        scores=p11c.score_all_parents(state)
        self.assertEqual([s.parent_id for s in scores],['A','B'])
        bad=self._state(parents=('B','A'), bad_second=True)
        with self.assertRaisesRegex(AssertionError,'non-finite'):
            p11c.score_all_parents(bad)

    def test_parent_score_table_write_reread_hash_verify(self):
        state=self._state(parents=('B','A'))
        scores=p11c.score_all_parents(state)
        out=self.base/'AUTOGREY_V2_P11C_PARENT_SCORES_R1.csv'
        digest=p11c.write_and_verify_parent_score_table(scores,out)
        self.assertTrue(out.is_file())
        self.assertEqual(digest,p11c.sha256(out))
        with out.open('r',encoding='utf-8',newline='') as f:
            rr=list(csv.DictReader(f))
        self.assertEqual([r['parent_id'] for r in rr],['A','B'])
        self.assertEqual(len(rr),2)
        self.assertIn('eligible_oracle_mase',rr[0])
        self.assertIn('delta_selection_regret',rr[0])
        self.assertIn('delta_practical_mase',rr[0])
        self.assertIn('subgroup_source_x_h',rr[0])

    def test_parent_score_table_refuses_overwrite(self):
        state=self._state(parents=('A',))
        scores=p11c.score_all_parents(state)
        out=self.base/'scores.csv'
        out.write_text('existing\n',encoding='utf-8')
        with self.assertRaises(FileExistsError):
            p11c.write_and_verify_parent_score_table(scores,out)


if __name__ == '__main__':
    unittest.main()
