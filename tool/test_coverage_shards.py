"""Small synthetic protocol/manifest/artifact controls; never runs Flutter."""
import copy
import json
import os
from pathlib import Path
import tempfile
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from tool.coverage_shard_plan import inventory
from tool.coverage_shards import (digest, event_summary, lcov_records, merge, run,
                                  sources, validate_plan, validate_receipts)


def events(path):
    return [
        dict(type='start', protocolVersion='0.1.1'),
        dict(type='suite', suite=dict(id=0, path=path)),
        dict(type='testStart', test=dict(id=1, suiteID=0, name='loading')),
        dict(type='testDone', testID=1, result='success', hidden=True, skipped=False),
        dict(type='testStart', test=dict(id=2, suiteID=0, name='visible case')),
        dict(type='testDone', testID=2, result='success', hidden=False, skipped=False),
        dict(type='testStart', test=dict(id=3, suiteID=0, name='retained skip')),
        dict(type='testDone', testID=3, result='success', hidden=False, skipped=True),
        dict(type='done', success=True),
    ]


def stream(items):
    return '\n'.join(json.dumps(e) for e in items) + '\n'


class CoverageShardsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        for folder in ['test', 'lib', 'incoming']:
            (self.root / folder).mkdir()
        for name in ['a', 'b']:
            (self.root / f'test/{name}_test.dart').write_text('void main() {}\n')
        (self.root / 'lib/a.dart').write_text('first\nsecond\nthird\n')
        for file in ['pubspec.yaml', 'pubspec.lock']:
            (self.root / file).write_text('{}\n')
        self.plan = dict(discovery=inventory(self.root), groups=[
            dict(index=0, files=['test/a_test.dart']),
            dict(index=1, files=['test/b_test.dart']),
        ])
        self.plan_bytes = json.dumps(self.plan).encode()
        self.commit = 'a' * 40
        self.receipts = []
        for i, name in enumerate(['a', 'b']):
            folder = self.root / f'incoming/shard-{i}'
            folder.mkdir()
            ev = stream(events(f'test/{name}_test.dart')).encode()
            cov = f'SF:lib/a.dart\nDA:1,{1-i}\nDA:2,{i}\nDA:3,0\nLF:3\nLH:1\nend_of_record\n'.encode()
            (folder / 'events.json').write_bytes(ev)
            (folder / 'lcov.info').write_bytes(cov)
            receipt = dict(index=i, commit=self.commit, plan_sha256=digest(self.plan_bytes),
                selected=self.plan['groups'][i]['files'], sources=sources(self.root),
                exit_code=0, events_sha256=digest(ev), lcov_sha256=digest(cov),
                **event_summary(ev.decode(), self.root, [f'test/{name}_test.dart']))
            self.receipts.append(receipt)
            (folder / 'receipt.json').write_text(json.dumps(receipt))

    def test_union_retains_zero_lines_and_exact_visible_skip_counts(self):
        text, report = merge(self.plan_bytes, self.root / 'incoming', self.root, self.commit)
        self.assertEqual(text, 'SF:lib/a.dart\nDA:1,1\nDA:2,1\nDA:3,0\nLF:3\nLH:2\nend_of_record\n')
        self.assertEqual(report['counts'], dict(passed=2, skipped=2, failed=0,
                                               hidden=2, errors_seen=0))
        self.assertEqual(report['test_files'], 2)
        self.assertTrue(report['verified'])

    def test_hidden_loaders_are_not_app_passes(self):
        result = event_summary(stream(events('test/a_test.dart')), self.root, ['test/a_test.dart'])
        self.assertEqual(result['counts']['passed'], 1)
        self.assertEqual(result['counts']['skipped'], 1)
        self.assertEqual(result['counts']['hidden'], 1)

    def test_late_error_invalidates_a_previously_hidden_result(self):
        data = events('test/a_test.dart')
        data.insert(-1, dict(type='error', testID=1))
        with self.assertRaises(ValueError):
            event_summary(stream(data), self.root, ['test/a_test.dart'])

    def test_null_false_or_missing_completion_refused(self):
        for final in [None, False, 'missing']:
            data = events('test/a_test.dart')
            if final == 'missing':
                data.pop()
            else:
                data[-1]['success'] = final
            with self.subTest(final=final), self.assertRaises(ValueError):
                event_summary(stream(data), self.root, ['test/a_test.dart'])

    def test_duplicate_and_incomplete_test_results_refused(self):
        for missing in [False, True]:
            data = events('test/a_test.dart')
            if missing:
                del data[5]
            else:
                data.insert(-1, data[5])
            with self.subTest(missing=missing), self.assertRaises(ValueError):
                event_summary(stream(data), self.root, ['test/a_test.dart'])

    def test_missing_extra_or_outside_suite_refused(self):
        for path in ['test/b_test.dart', '../outside_test.dart']:
            with self.subTest(path=path), self.assertRaises(ValueError):
                event_summary(stream(events(path)), self.root, ['test/a_test.dart'])

    def test_duplicate_suite_path_cannot_inflate_file_execution(self):
        data = events('test/a_test.dart')
        data.insert(-1, dict(type='suite', suite=dict(id=20, path='test/a_test.dart')))
        with self.assertRaises(ValueError):
            event_summary(stream(data), self.root, ['test/a_test.dart'])

    def test_source_changed_after_shard_is_refused(self):
        (self.root / 'lib/a.dart').write_text('changed\n')
        with self.assertRaises(ValueError):
            validate_receipts(self.plan, digest(self.plan_bytes), self.receipts,
                              self.root, self.commit)

    def test_test_discovery_changed_after_plan_is_refused(self):
        (self.root / 'test/new_test.dart').write_text('new')
        with self.assertRaises(ValueError):
            validate_plan(self.plan, self.root)

    def test_test_content_changed_after_plan_is_refused(self):
        (self.root / 'test/a_test.dart').write_text('changed')
        with self.assertRaises(ValueError):
            validate_plan(self.plan, self.root)

    def test_assignment_overlap_or_empty_shard_refused(self):
        for files in [[], ['test/a_test.dart']]:
            plan = copy.deepcopy(self.plan)
            plan['groups'][1]['files'] = files
            with self.subTest(files=files), self.assertRaises(ValueError):
                validate_plan(plan, self.root)

    def test_missing_and_duplicate_shard_receipts_refused(self):
        for receipts in [self.receipts[:1], [self.receipts[0]] * 2]:
            with self.subTest(size=len(receipts)), self.assertRaises(ValueError):
                validate_receipts(self.plan, digest(self.plan_bytes), receipts,
                                  self.root, self.commit)

    def test_wrong_commit_manifest_exit_or_failed_outcome_refused(self):
        for key, value in [('commit', 'b' * 40), ('plan_sha256', 'wrong'),
                           ('exit_code', 1), ('exit_code', False),
                           ('success', False), ('files_seen', [])]:
            receipts = copy.deepcopy(self.receipts)
            receipts[0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_receipts(self.plan, digest(self.plan_bytes), receipts,
                                  self.root, self.commit)

    def test_lcov_or_events_checksum_change_refused(self):
        for file in ['events.json', 'lcov.info']:
            path = self.root / 'incoming/shard-0' / file
            before = path.read_bytes()
            path.write_bytes(before + b'changed')
            with self.subTest(file=file), self.assertRaises(ValueError):
                merge(self.plan_bytes, self.root / 'incoming', self.root, self.commit)
            path.write_bytes(before)

    def test_forged_count_receipt_refused(self):
        path = self.root / 'incoming/shard-0/receipt.json'
        receipt = json.loads(path.read_text())
        receipt['counts']['passed'] += 1
        path.write_text(json.dumps(receipt))
        with self.assertRaises(ValueError):
            merge(self.plan_bytes, self.root / 'incoming', self.root, self.commit)

    def test_lcov_rejects_unknown_source_summary_drop_or_duplicate_line(self):
        valid = 'SF:lib/a.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\n'
        for text in [valid.replace('lib/a.dart', 'lib/missing.dart'),
                     valid.replace('lib/a.dart', 'pubspec.yaml'),
                     valid.replace('LH:0', 'LH:1'), valid.replace('LF:1\n', ''),
                     valid.replace('DA:1,0', 'DA:1,0\nDA:1,0'),
                     valid.replace('end_of_record\n', '')]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                lcov_records(text, self.root, sources(self.root))

    def test_failed_merge_cli_keeps_diagnostic_without_inventing_lcov(self):
        script = Path(__file__).with_name('coverage_shards.py').resolve()
        plan = self.root / 'plan.json'
        plan.write_bytes(self.plan_bytes)
        (self.root / 'incoming/shard-0/lcov.info').write_text('changed')
        output = self.root / 'coverage'
        environment = os.environ.copy()
        environment['GITHUB_SHA'] = self.commit
        result = subprocess.run([sys.executable, str(script), 'merge', '--plan', str(plan),
            '--inputs', str(self.root / 'incoming'), '--output', str(output)],
            cwd=self.root, env=environment, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        failure = json.loads((output / 'verification-failure.json').read_text())
        self.assertFalse(failure['verified'])
        self.assertIn('checksum', failure['error'])
        self.assertFalse((output / 'lcov.info').exists())

    def test_unhandled_function_branch_metadata_is_not_silently_dropped(self):
        text = 'SF:lib/a.dart\nFN:1,example\nDA:1,0\nLF:1\nLH:0\nend_of_record\n'
        with self.assertRaises(ValueError):
            lcov_records(text, self.root, sources(self.root))

    def test_absolute_repository_paths_are_rebased_without_host_path_egress(self):
        text = f'SF:{self.root.as_posix()}/lib/a.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\n'
        self.assertEqual(lcov_records(text, self.root, sources(self.root)), {'lib/a.dart': {1: 0}})

    def test_application_runner_refuses_local_execution_before_starting_process(self):
        with patch.dict(os.environ, {}, clear=True), patch('subprocess.Popen') as process:
            with self.assertRaises(ValueError):
                run(self.plan_bytes, 0, self.root, self.root / 'output', self.commit)
            process.assert_not_called()
            self.assertFalse((self.root / 'output').exists())

    def exercise_mock_runner(self, *, failed=False, drift=False):
        # Synthetic subprocess only: never sets CI for a real Flutter process.
        output = self.root / 'mock-output'
        captured = []
        def spawn(command, **kwargs):
            captured.extend(command)
            event_file = Path(next(a.split('json:', 1)[1] for a in command
                                   if a.startswith('--file-reporter=')))
            coverage_file = Path(command[command.index('--coverage-path') + 1])
            def finish():
                data = events('test/a_test.dart')
                data[-1]['success'] = not failed
                event_file.write_text(stream(data))
                coverage_file.write_text('SF:lib/a.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n')
                if drift:
                    (self.root / 'lib/a.dart').write_text('changed during synthetic process')
                return 1 if failed else 0
            return SimpleNamespace(stdout=iter(['Authored runner log\n']), wait=finish)
        environment = dict(CI='true', GITHUB_SHA=self.commit)
        with patch.dict(os.environ, environment), \
                patch('subprocess.check_output', return_value=(self.commit + '\n').encode()), \
                patch('subprocess.Popen', side_effect=spawn):
            if failed or drift:
                with self.assertRaises(ValueError):
                    run(self.plan_bytes, 0, self.root, output, self.commit)
            else:
                run(self.plan_bytes, 0, self.root, output, self.commit)
        return output, captured

    def test_mock_runner_passes_only_its_assigned_files_and_records_verified_counts(self):
        output, command = self.exercise_mock_runner()
        self.assertIn('--concurrency=1', command)
        self.assertEqual(command[-1], 'test/a_test.dart')
        self.assertNotIn('test/b_test.dart', command)
        receipt = json.loads((output / 'receipt.json').read_text())
        self.assertTrue(receipt['success'])
        self.assertEqual(receipt['counts']['passed'], 1)
        self.assertEqual(receipt['counts']['skipped'], 1)
        self.assertEqual(receipt['lcov_sha256'], digest((output / 'lcov.info').read_bytes()))

    def test_mock_failed_runner_keeps_raw_evidence_and_cannot_claim_success(self):
        output, _ = self.exercise_mock_runner(failed=True)
        receipt = json.loads((output / 'receipt.json').read_text())
        self.assertFalse(receipt['success'])
        self.assertEqual(receipt['exit_code'], 1)
        self.assertTrue((output / 'events.json').exists())
        self.assertTrue((output / 'lcov.info').exists())
        self.assertIn('Authored runner log', (output / 'stdout.log').read_text())

    def test_mock_runner_detects_source_drift_before_publishing_success(self):
        output, _ = self.exercise_mock_runner(drift=True)
        receipt = json.loads((output / 'receipt.json').read_text())
        self.assertFalse(receipt['success'])
        self.assertIn('source changed', receipt['verification_error'])


if __name__ == '__main__':
    unittest.main()
