import tempfile
import unittest
from pathlib import Path

from tool.coverage_gaps import inventory, parse_lcov, ranges


class CoverageGapsTest(unittest.TestCase):
    def test_repeated_records_merge_hits_and_preserve_unexecuted_lines(self):
        data = parse_lcov("SF:lib/a.dart\nDA:1,0\nDA:2,0\nend_of_record\n"
                          "SF:lib/a.dart\nDA:1,3\nDA:3,0,checksum\nend_of_record")
        self.assertEqual(data, {"lib/a.dart": {1: 3, 2: 0, 3: 0}})

    def test_ranges_are_sorted_unique_and_do_not_bridge_missing_lines(self):
        self.assertEqual(ranges([9, 2, 3, 3, 7]), [[2, 3], [7, 7], [9, 9]])

    def test_bad_counts_do_not_silently_improve_coverage(self):
        with self.assertRaises(ValueError):
            parse_lcov("SF:lib/a.dart\nDA:1,-1")

    def test_inventory_retains_generated_unimported_and_source_hashes(self):
        base = Path(__file__).resolve().parents[1] / "build" / "coverage-tool-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="synthetic-", dir=base) as tmp:
            root = Path(tmp)
            (root / "lib").mkdir()
            for name in ["a.dart", "main.dart", "app_localizations_en.dart"]:
                (root / "lib" / name).write_text("synthetic\n", encoding="utf-8")
            report = inventory({"lib/a.dart": {1: 1, 2: 0},
                                "lib/app_localizations_en.dart": {1: 0},
                                "../outside.dart": {1: 0}}, root)
            self.assertEqual(report["handwritten"]["percent"], 50)
            self.assertEqual(report["handwritten"]["unexecuted"], 1)
            self.assertEqual([r["path"] for r in report["unimported"]], ["lib/main.dart"])
            self.assertEqual(len(report["files"]), 2)
            self.assertTrue(all(len(r["sha256"]) == 64 for r in report["files"]))


if __name__ == "__main__":
    unittest.main()
