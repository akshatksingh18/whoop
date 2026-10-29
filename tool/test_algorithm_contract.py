import json
import tempfile
import unittest
from pathlib import Path

from tool.algorithm_contract import PACKAGES, check, source_digest


class AlgorithmContractTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "lib/compute").mkdir(parents=True)
        (self.root / "lib/compute/derivation_engine.dart").write_text("const int kAlgoVersion = 99;\n")
        declared = "dependencies:\n"
        locked = "packages:\n"
        for name, relative in PACKAGES.items():
            folder = self.root / relative
            (folder / "lib").mkdir(parents=True)
            (folder / "lib/example.dart").write_bytes(b"const answer = 42;\n")
            (folder / "pubspec.yaml").write_text(f"name: {name}\n")
            declared += f"  {name}:\n    path: {relative}\n"
            locked += f"  {name}:\n    description:\n      path: {relative}\n      relative: true\n    source: path\n"
        (self.root / "pubspec.yaml").write_text(declared)
        (self.root / "pubspec.lock").write_text(locked)
        self.contract = {"algorithmVersion": 99, "review": "Synthetic baseline", "packages": {
            name: source_digest(self.root, relative) for name, relative in PACKAGES.items()
        }}
        self.save()

    def save(self):
        (self.root / "packages/algorithm-contract.json").write_text(json.dumps(self.contract))

    def test_matching_source_passes(self):
        check(self.root)

    def test_changed_source_is_rejected(self):
        (self.root / "packages/analytics/lib/example.dart").write_text("const answer = 43;\n")
        with self.assertRaisesRegex(ValueError, "source changed"):
            check(self.root)

    def test_crlf_does_not_invalidate_same_source(self):
        (self.root / "packages/analytics/lib/example.dart").write_bytes(b"const answer = 42;\r\n")
        check(self.root)

    def test_stale_version_is_rejected(self):
        self.contract["algorithmVersion"] = 98
        self.save()
        with self.assertRaisesRegex(ValueError, "version disagrees"):
            check(self.root)

    def test_stale_lock_is_rejected(self):
        path = self.root / "pubspec.lock"
        path.write_text(path.read_text().replace("path: packages/analytics", "path: elsewhere"))
        with self.assertRaisesRegex(ValueError, "locked resolution"):
            check(self.root)

    def test_override_and_missing_review_are_rejected(self):
        (self.root / "pubspec_overrides.yaml").write_text("dependency_overrides: {}\n")
        with self.assertRaisesRegex(ValueError, "overrides"):
            check(self.root)
        (self.root / "pubspec_overrides.yaml").unlink()
        self.contract["review"] = ""
        self.save()
        with self.assertRaisesRegex(ValueError, "output/version review"):
            check(self.root)
