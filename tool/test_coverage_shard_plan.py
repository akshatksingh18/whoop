"""Bounded planner fixtures, not a full application suite."""
import math
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from tool.coverage_shard_plan import inventory, partition


class ShardPlanTest(unittest.TestCase):
    def test_cli_creates_manifest_parent_and_refuses_stale_output(self):
        script = Path(__file__).with_name('coverage_shard_plan.py').resolve()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'test').mkdir()
            for name in ['a', 'b']:
                (root / f'test/{name}_test.dart').write_text('void main() {}')
            costs = root / 'costs.json'
            costs.write_text(json.dumps({'seconds': {'test/a_test.dart': 40}}))
            output = root / 'generated/plan.json'
            command = [sys.executable, str(script), '--root', str(root), '--count', '2',
                       '--costs', str(costs), '--output', str(output)]
            first = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            payload = json.loads(output.read_text())
            self.assertEqual(sum(len(g['files']) for g in payload['groups']), 2)
            self.assertEqual(payload['groups'][0]['estimated_seconds'], 40)
            self.assertFalse(payload['runtime_verified'])
            before = output.read_bytes()
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(output.read_bytes(), before)

    def test_complete_disjoint_deterministic_partition(self):
        paths = [f'test/case_{i}_test.dart' for i in range(17)]
        first = partition(paths, 3)
        self.assertEqual(first, partition(reversed(paths), 3))
        assigned = [p for g in first for p in g['files']]
        self.assertEqual(sorted(assigned), sorted(paths))
        self.assertEqual(len(set(assigned)), len(paths))
        self.assertTrue(all(g['files'] for g in first))

    def test_long_files_are_balanced_without_changing_file_contents(self):
        paths = [f'test/{i}_test.dart' for i in range(6)]
        costs = dict(zip(paths, [40, 30, 20, 10, 10, 10]))
        groups = partition(paths, 3, costs)
        self.assertEqual([g['estimated_seconds'] for g in groups], [40, 40, 40])

    def test_duplicate_file_refused(self):
        with self.assertRaises(ValueError):
            partition(['test/a_test.dart'] * 2, 1)

    def test_empty_or_invalid_count_refused(self):
        for paths, count in [([], 1), (['test/a_test.dart'], 0),
                             (['test/a_test.dart'], 2)]:
            with self.subTest(count=count), self.assertRaises(ValueError):
                partition(paths, count)

    def test_noncanonical_or_outside_path_refused(self):
        for path in ['lib/a_test.dart', 'test/../a_test.dart',
                     'test\\a_test.dart', 'test//a_test.dart', '/test/a_test.dart']:
            with self.subTest(path=path), self.assertRaises(ValueError):
                partition([path], 1)

    def test_invalid_duration_refused(self):
        for cost in [0, -1, math.inf, math.nan, True, '4']:
            with self.subTest(cost=cost), self.assertRaises(ValueError):
                partition(['test/a_test.dart'], 1, {'test/a_test.dart': cost})

    def test_nested_discovery_hashes_and_line_endings(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = root / 'test' / 'nested'
            folder.mkdir(parents=True)
            test = folder / 'a_test.dart'
            test.write_bytes(b'void main() {}\r\n')
            (folder / 'helper.dart').write_text('helper')
            entries = inventory(root)
            self.assertEqual([e['path'] for e in entries], ['test/nested/a_test.dart'])
            test.write_bytes(b'void main() {}\n')
            self.assertEqual(entries, inventory(root))
            test.write_text('void main() { changed(); }')
            self.assertNotEqual(entries, inventory(root))


if __name__ == '__main__':
    unittest.main()
