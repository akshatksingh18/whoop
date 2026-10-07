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
    validate_new_build_identity,
    validate_personal_icons,
    validate_ipa,
)


class PersonalIosContractTest(unittest.TestCase):
    def test_accepted_personal_build_identity_cannot_be_reused(self) -> None:
        ledger = {
            "acceptedBuilds": [
                {"version": "0.9.30", "build": "63"},
            ]
        }
        with self.assertRaises(ContractError):
            validate_new_build_identity("version: 0.9.30+63\n", ledger)
        self.assertEqual(
            validate_new_build_identity("version: 0.9.31+64\n", ledger),
            ("0.9.31", "64"),
        )

    def test_project_transform_removes_personal_exclusions(self) -> None:
        transformed = transform_project(PROJECT.read_text(encoding="utf-8"))
        self.assertEqual(transformed.count("PERSONAL_SIDELOAD"), 6)
        self.assertEqual(transformed.count("Runner/RunnerPersonal.entitlements"), 6)
        self.assertEqual(transformed.count("Runner/Info-Personal.plist"), 3)
        self.assertEqual(
            transformed.count("ASSETCATALOG_COMPILER_APPICON_NAME = AppIconPersonal;"),
            3,
        )
        for forbidden in (
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
        self.assertEqual(info["UIBackgroundModes"], ["bluetooth-central", "location", "audio"])
        self.assertIn("NSMotionUsageDescription", info)
        self.assertNotIn("NSHealthShareUsageDescription", info)
        # Build 81: no lock-screen extension, so no Live Activity support.
        self.assertNotIn("NSSupportsLiveActivities", info)
        self.assertNotIn("OpenStrapWorkoutLiveActivity", info)

    def test_personal_info_gps_stays_while_in_use_only(self) -> None:
        # The GPS-experiment reopening's one hard constraint: permission stays at While-In-Use,
        # matching lib/gps/gps_source.dart's own design. A future change that widens this to
        # Always must not slip through this contract test unnoticed.
        source = plistlib.loads(SOURCE_INFO.read_bytes())
        info = personal_info(source)
        self.assertIn("NSLocationWhenInUseUsageDescription", info)
        self.assertNotIn("NSLocationAlwaysAndWhenInUseUsageDescription", info)

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

    def test_even_the_workout_activity_extension_is_refused(self) -> None:
        # Build 81 dropped it: Sideloadly's free signing never provisions it.
        info = personal_info(plistlib.loads(SOURCE_INFO.read_bytes()))
        info.update(CFBundleIdentifier=BUNDLE_ID, CFBundleVersion="81", CFBundleShortVersionString="0.9.48")
        extension = dict(CFBundleIdentifier=BUNDLE_ID + ".activity", CFBundleVersion="81",
            CFBundleShortVersionString="0.9.48", CFBundleExecutable="Activity",
            NSExtension={"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"})
        with tempfile.TemporaryDirectory() as tmp:
            ipa = Path(tmp) / "activity.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/", b"")
                archive.writestr("Payload/Runner.app/", b"")
                archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info))
                root = "Payload/Runner.app/PlugIns/OpenStrapWidgetExtension.appex/"
                archive.writestr(root + "Info.plist", plistlib.dumps(extension))
                archive.writestr(root + "Activity", b"fixture executable")
            with self.assertRaises(ContractError):
                validate_ipa(ipa)
            plain = Path(tmp) / "plain.ipa"
            with zipfile.ZipFile(plain, "w") as archive:
                archive.writestr("Payload/", b"")
                archive.writestr("Payload/Runner.app/", b"")
                archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info))
            self.assertEqual(validate_ipa(plain)["CFBundleVersion"], "81")


if __name__ == "__main__":
    unittest.main()
