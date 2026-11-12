"""No-model-fit tests: subprocess.run is mocked for every forecast invocation."""
import contextlib
import hashlib
import io
import json
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agv1_cli as cli


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


class CLIControlTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.work = Path(self.dir.name)
        self.source = self.work / 'frozen-original.zip'
        with zipfile.ZipFile(self.source, 'w') as z:
            z.writestr('test-source.txt', 'NOT_REAL_V1_DATA_FOR_UNIT_TESTS')
        self.source_patch = mock.patch.object(cli, 'SOURCE_SHA256', sha(self.source))
        self.source_patch.start()
        self.addCleanup(self.source_patch.stop)
        self.env_patch = mock.patch.object(cli, 'check_environment', return_value=dict(cli.EXPECTED))
        self.env_patch.start()
        self.addCleanup(self.env_patch.stop)
        self.series = self.work / 'values.csv'
        self.series.write_text('value\n' + ''.join(f'{i}\n' for i in range(100,112)), encoding='utf-8')
        self.out = self.work / 'fresh-output'

    def forecast_args(self, **kw):
        from argparse import Namespace
        d = dict(source=str(self.source), series=str(self.series), h=3,
                 M=None, out_root=str(self.out))
        d.update(kw)
        return Namespace(**d)

    def test_exact_one_column_rejects_extra_row_cell(self):
        self.series.write_text('value\n100,999\n101\n', encoding='utf-8')
        with self.assertRaisesRegex(cli.ControlledStop, 'STOP_INPUT_SCHEMA_EXPECTED_ONE_VALUE_COLUMN'):
            cli.check_series_file(self.series)

    def test_exact_one_column_rejects_blank_physical_row(self):
        self.series.write_text('value\n100\n\n102\n', encoding='utf-8')
        with self.assertRaises(cli.ControlledStop):
            cli.check_series_file(self.series)

    def test_bom_valid_input_is_accepted(self):
        self.series.write_text('value\n100\n101\n', encoding='utf-8-sig')
        self.assertEqual(cli.check_series_file(self.series), 2)

    def test_nonfinite_value_is_refused(self):
        self.series.write_text('value\n100\nnan\n', encoding='utf-8')
        with self.assertRaisesRegex(cli.ControlledStop, 'STOP_INPUT_NONFINITE_ROW_3'):
            cli.check_series_file(self.series)

    def test_bad_row_refusal_is_before_observer_or_output_creation(self):
        self.series.write_text('value\n100,999\n', encoding='utf-8')
        with mock.patch.object(cli.subprocess, 'run') as runner:
            with self.assertRaisesRegex(cli.ControlledStop, 'STOP_INPUT_SCHEMA'):
                cli.forecast(self.forecast_args())
            runner.assert_not_called()
        self.assertFalse(self.out.exists())

    def test_existing_output_is_not_modified_or_launched(self):
        self.out.mkdir()
        sentinel = self.out / 'sentinel.txt'
        sentinel.write_text('do not touch', encoding='utf-8')
        with mock.patch.object(cli.subprocess, 'run') as runner:
            with self.assertRaisesRegex(cli.ControlledStop, 'STOP_OUTPUT_ROOT_ALREADY_EXISTS'):
                cli.forecast(self.forecast_args())
            runner.assert_not_called()
        self.assertEqual(sentinel.read_text(encoding='utf-8'), 'do not touch')

    def test_doctor_includes_launcher_identity_and_does_not_launch_models(self):
        with mock.patch.object(cli.subprocess, 'run') as runner, \
             contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(cli.doctor(self.forecast_args()), 0)
            runner.assert_not_called()
        receipt = json.loads(output.getvalue())
        self.assertEqual(receipt['status'], 'PASS_PREFLIGHT_ONLY_NO_FORECAST_RUN')
        self.assertEqual(receipt['launcher_sha256'], sha(cli.PKG_DIR / 'agv1_cli.py'))

    def write_fake_results(self):
        """Use archived CSV fixture shapes, never execute the forecasting engine."""
        ref = cli.PKG_DIR / 'REFERENCE_OUTPUT'
        result = self.out / 'RESULT'
        result.mkdir(parents=True, exist_ok=True)
        for name in ('SELECTED_FORECAST.csv', 'CANDIDATE_SCORES.csv'):
            shutil.copyfile(ref / name, result / name)
        report = json.loads((ref / 'RUN_RECEIPT.json').read_text(encoding='utf-8'))
        report['source_archive_sha256'] = cli.SOURCE_SHA256
        report['new_series_sha256'] = sha(self.series)
        (result / 'RUN_RECEIPT.json').write_text(json.dumps(report), encoding='utf-8')
        return result

    def fake_observer(self, *, modify_series=False, modify_source=False, with_results=True,
                      bad_forecast=None, bad_report_input=False, bad_observer_input=False):
        def fake_run(cmd, check):
            self.assertEqual(check, False)
            self.assertEqual(Path(cmd[1]).name, 'run_demo_bounded.py')
            self.assertEqual(cmd.count('--out-root'), 1)
            self.out.mkdir()
            (self.out / 'OBSERVER_RECEIPT.json').write_text(json.dumps({
                'observer_status': 'PASS_EXPERIMENTAL_UNVALIDATED',
                'child_exit_code': 0,
                'original_zip_sha256': cli.SOURCE_SHA256,
                'prototype_sha256': cli.PROTOTYPE_SHA256,
                'input_series_sha256': '0'*64 if bad_observer_input else sha(self.series),
            }), encoding='utf-8')
            if with_results:
                result = self.write_fake_results()
                if bad_report_input:
                    report_path = result / 'RUN_RECEIPT.json'
                    report = json.loads(report_path.read_text(encoding='utf-8'))
                    report['new_series_sha256'] = '0'*64
                    report_path.write_text(json.dumps(report), encoding='utf-8')
                if bad_forecast is not None:
                    (result / 'SELECTED_FORECAST.csv').write_text(bad_forecast, encoding='utf-8')
            if modify_series:
                self.series.write_text(self.series.read_text(encoding='utf-8')+'200\n', encoding='utf-8')
            if modify_source:
                with self.source.open('ab') as f:
                    f.write(b'tampered')
            return subprocess.CompletedProcess(cmd, 0)
        return fake_run

    def assert_mocked_stop(self, observer, expected_status):
        with mock.patch.object(cli.subprocess, 'run', side_effect=observer) as runner:
            self.assertEqual(cli.forecast(self.forecast_args()), 2)
            runner.assert_called_once()
        receipt = json.loads((self.out / 'CLI_RECEIPT.json').read_text(encoding='utf-8'))
        self.assertEqual(receipt['status'], expected_status)
        return receipt

    def test_false_success_receipt_without_result_files_must_stop(self):
        receipt = self.assert_mocked_stop(
            self.fake_observer(with_results=False), 'STOP_RESULT_FILES_MISSING')
        self.assertEqual(receipt['observer_exit_code'], 0)

    def test_false_success_with_nonfinite_forecast_must_stop(self):
        malformed = ('horizon,forecast,selected_group,selected_config_id,scientific_status\n'
                     '1,nan,SG09_GREY_MARKOV,S=2_EQW,EXPERIMENTAL_UNVALIDATED\n'
                     '2,201,SG09_GREY_MARKOV,S=2_EQW,EXPERIMENTAL_UNVALIDATED\n'
                     '3,213,SG09_GREY_MARKOV,S=2_EQW,EXPERIMENTAL_UNVALIDATED\n')
        self.assert_mocked_stop(self.fake_observer(bad_forecast=malformed),
                                'STOP_RESULT_FORECAST_INVALID')

    def test_false_success_with_wrong_forecast_horizon_must_stop(self):
        malformed = ('horizon,forecast,selected_group,selected_config_id,scientific_status\n'
                     '2,191,SG09_GREY_MARKOV,S=2_EQW,EXPERIMENTAL_UNVALIDATED\n'
                     '3,201,SG09_GREY_MARKOV,S=2_EQW,EXPERIMENTAL_UNVALIDATED\n'
                     '4,213,SG09_GREY_MARKOV,S=2_EQW,EXPERIMENTAL_UNVALIDATED\n')
        self.assert_mocked_stop(self.fake_observer(bad_forecast=malformed),
                                'STOP_RESULT_FORECAST_INVALID')

    def test_false_success_with_report_input_disagreement_must_stop(self):
        self.assert_mocked_stop(self.fake_observer(bad_report_input=True),
                                'STOP_RESULT_RECEIPT_DISAGREEMENT')

    def test_false_success_with_observer_input_disagreement_must_stop(self):
        self.assert_mocked_stop(self.fake_observer(bad_observer_input=True),
                                'STOP_OBSERVER_PROVENANCE_DISAGREEMENT')

    def test_false_success_with_missing_scores_must_stop(self):
        def fake_missing_scores(cmd, check):
            result = self.write_fake_results()
            (result / 'CANDIDATE_SCORES.csv').unlink()
            self.out.mkdir(exist_ok=True)
            (self.out / 'OBSERVER_RECEIPT.json').write_text(json.dumps({
                'observer_status': 'PASS_EXPERIMENTAL_UNVALIDATED', 'child_exit_code': 0,
                'original_zip_sha256': cli.SOURCE_SHA256,
                'prototype_sha256': cli.PROTOTYPE_SHA256,
                'input_series_sha256': sha(self.series),
            }),encoding='utf-8')
            return subprocess.CompletedProcess(cmd, 0)
        self.assert_mocked_stop(fake_missing_scores, 'STOP_RESULT_FILES_MISSING')

    def test_forecast_makes_exactly_one_mocked_observer_call_and_writes_receipt(self):
        with mock.patch.object(cli.subprocess, 'run', side_effect=self.fake_observer()) as runner:
            self.assertEqual(cli.forecast(self.forecast_args()), 0)
            runner.assert_called_once()
        receipt = json.loads((self.out / 'CLI_RECEIPT.json').read_text(encoding='utf-8'))
        self.assertEqual(receipt['status'], 'PASS_OBSERVER_EXIT_0_EXPERIMENTAL_UNVALIDATED')
        self.assertEqual(receipt['input_series_sha256_before'], sha(self.series))
        self.assertEqual(receipt['input_series_sha256_after'], sha(self.series))
        self.assertEqual(receipt['launcher_sha256_before'], sha(cli.PKG_DIR / 'agv1_cli.py'))
        self.assertEqual(receipt['launcher_sha256_after'], sha(cli.PKG_DIR / 'agv1_cli.py'))
        self.assertEqual(receipt['observer_invocations_requested'], 1)
        self.assertEqual(receipt['observer_exit_code'], 0)
        self.assertEqual(receipt['observer_reported_child_exit_code'], 0)

    def test_input_changed_during_observer_causes_stop_receipt(self):
        with mock.patch.object(cli.subprocess, 'run', side_effect=self.fake_observer(modify_series=True)) as runner:
            self.assertEqual(cli.forecast(self.forecast_args()), 2)
            runner.assert_called_once()
        receipt = json.loads((self.out / 'CLI_RECEIPT.json').read_text(encoding='utf-8'))
        self.assertEqual(receipt['status'], 'STOP_INPUT_CHANGED_DURING_EXECUTION')
        self.assertNotEqual(receipt['input_series_sha256_before'], receipt['input_series_sha256_after'])

    def test_source_changed_during_observer_causes_stop_receipt(self):
        with mock.patch.object(cli.subprocess, 'run', side_effect=self.fake_observer(modify_source=True)) as runner:
            self.assertEqual(cli.forecast(self.forecast_args()), 2)
            runner.assert_called_once()
        receipt = json.loads((self.out / 'CLI_RECEIPT.json').read_text(encoding='utf-8'))
        self.assertEqual(receipt['status'], 'STOP_SOURCE_CHANGED_DURING_EXECUTION')

    def test_observer_reports_failure_causes_stop(self):
        def fail_run(cmd, check):
            self.out.mkdir()
            (self.out / 'OBSERVER_RECEIPT.json').write_text(json.dumps({
                'observer_status':'STOP_SCRIPT_NONZERO_EXIT','child_exit_code':3,
            }),encoding='utf-8')
            return subprocess.CompletedProcess(cmd, 2)
        with mock.patch.object(cli.subprocess, 'run', side_effect=fail_run) as runner:
            self.assertEqual(cli.forecast(self.forecast_args()), 2)
            runner.assert_called_once()
        self.assertIn('STOP_OBSERVER_EXIT_2', (self.out/'CLI_RECEIPT.json').read_text(encoding='utf-8'))

    def test_mismatched_original_archive_refused_before_launch(self):
        with mock.patch.object(cli, 'SOURCE_SHA256', '0' * 64), \
             mock.patch.object(cli.subprocess, 'run') as runner:
            with self.assertRaisesRegex(cli.ControlledStop, 'STOP_ORIGINAL_V1_SOURCE_SHA256_MISMATCH'):
                cli.forecast(self.forecast_args())
            runner.assert_not_called()
        self.assertFalse(self.out.exists())

    def test_wrong_horizon_refused_before_launch(self):
        with mock.patch.object(cli.subprocess, 'run') as runner:
            with self.assertRaisesRegex(cli.ControlledStop, 'STOP_HORIZON_OUTSIDE_FROZEN_V1_TRAIN_DOMAIN'):
                cli.forecast(self.forecast_args(h=2))
            runner.assert_not_called()
        self.assertFalse(self.out.exists())

    def test_short_series_refused_before_launch(self):
        self.series.write_text('value\n' + ''.join(f'{i}\n' for i in range(9)), encoding='utf-8')
        with mock.patch.object(cli.subprocess, 'run') as runner:
            with self.assertRaisesRegex(cli.ControlledStop, 'STOP_SERIES_TOO_SHORT_FOR_FROZEN_ELIGIBILITY'):
                cli.forecast(self.forecast_args())
            runner.assert_not_called()
        self.assertFalse(self.out.exists())

    def test_empty_cells_are_refused(self):
        self.series.write_text('value\n100\n\n', encoding='utf-8')
        with self.assertRaises(cli.ControlledStop):
            cli.check_series_file(self.series)

    def test_observer_missing_receipt_is_stop_not_success(self):
        def missing_receipt(cmd, check):
            self.out.mkdir()
            return subprocess.CompletedProcess(cmd, 0)
        with mock.patch.object(cli.subprocess, 'run', side_effect=missing_receipt) as runner:
            self.assertEqual(cli.forecast(self.forecast_args()), 2)
            runner.assert_called_once()
        receipt = json.loads((self.out/'CLI_RECEIPT.json').read_text(encoding='utf-8'))
        self.assertEqual(receipt['status'], 'STOP_OBSERVER_RECEIPT_MISSING_OR_INVALID')

    def test_current_docs_name_the_actual_candidate_version(self):
        for name in ('README.md', 'G1_CLI_CONTRACT.md', 'ACCEPTANCE_RUNBOOK.md'):
            contents = (cli.PKG_DIR / name).read_text(encoding='utf-8')
            self.assertIn(cli.VERSION, contents, msg=name)
        self.assertNotIn('Inspect the `0.1.0-g2-candidate` source',
                         (cli.PKG_DIR / 'ACCEPTANCE_RUNBOOK.md').read_text(encoding='utf-8'))

    def test_runbook_and_readme_warn_against_direct_script_execution(self):
        for name in ('README.md', 'ACCEPTANCE_RUNBOOK.md'):
            content = (cli.PKG_DIR / name).read_text(encoding='utf-8').lower()
            self.assertIn('do not invoke run_demo_bounded.py directly', content)
            self.assertIn('do not invoke v1_new_series_prototype.py directly', content)


if __name__ == '__main__':
    unittest.main()
