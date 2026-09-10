import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from tool.personal_ios import (
    APP_NAME,
    BUNDLE_ID,
    ContractError,
    PERSONAL_ENTITLEMENTS,
    PERSONAL_ICONS,
    PROJECT,
    SOURCE_INFO,
    personal_info,
    transform_project,
    validate_personal_icons,
    validate_ipa,
)


class PersonalIosContractTest(unittest.TestCase):
    def test_project_transform_removes_personal_exclusions(self) -> None:
        transformed = transform_project(PROJECT.read_text(encoding="utf-8"))
        self.assertEqual(transformed.count("PERSONAL_SIDELOAD"), 3)
        self.assertEqual(transformed.count("Runner/RunnerPersonal.entitlements"), 3)
        self.assertEqual(transformed.count("Runner/Info-Personal.plist"), 3)
        self.assertEqual(
            transformed.count("ASSETCATALOG_COMPILER_APPICON_NAME = AppIconPersonal;"),
            3,
        )
        for forbidden in (
            "\t\t\t\t5348974F2FDC19C90033A4D9 /* Embed Foundation Extensions */,\n",
            "\t\t\t\tFADE0002FADE0002FADE0002 /* Embed Watch Content */,\n",
            "\t\t\t\tB9D2F406183A5C7E92B1D3F5 /* HealthKitSleepWriter.swift in Sources */,\n",
            "\t\t\t\t60DE9D949573401269D6DF2E /* HealthRoutes.swift in Sources */,\n",
        ):
            self.assertNotIn(forbidden, transformed)

    def test_personal_info_keeps_ble_and_motion_only(self) -> None:
        source = plistlib.loads(SOURCE_INFO.read_bytes())
        info = personal_info(source)
        self.assertEqual(info["CFBundleDisplayName"], APP_NAME)
        self.assertEqual(info["CFBundleName"], APP_NAME)
        self.assertEqual(info["UIBackgroundModes"], ["bluetooth-central"])
        self.assertIn("NSMotionUsageDescription", info)
        self.assertNotIn("NSHealthShareUsageDescription", info)
        self.assertNotIn("NSSupportsLiveActivities", info)

    def test_personal_entitlements_are_empty(self) -> None:
        self.assertEqual(plistlib.loads(PERSONAL_ENTITLEMENTS.read_bytes()), {})

    def test_personal_icon_catalog_is_complete(self) -> None:
        validate_personal_icons()
        self.assertTrue((PERSONAL_ICONS / "Icon-App-1024x1024@1x.png").is_file())

    def test_ipa_validator_rejects_an_extension(self) -> None:
        source = plistlib.loads(SOURCE_INFO.read_bytes())
        info = personal_info(source)
        info["CFBundleIdentifier"] = BUNDLE_ID
        with tempfile.TemporaryDirectory() as tmp:
            ipa = Path(tmp) / "bad.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info))
                archive.writestr("Payload/Runner.app/PlugIns/Widget.appex/Info.plist", b"x")
            with self.assertRaises(ContractError):
                validate_ipa(ipa)


if __name__ == "__main__":
    unittest.main()
