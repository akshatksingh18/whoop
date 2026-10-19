import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from tool.personal_ios import (
    APP_ICONS,
    APP_NAME,
    BUNDLE_ID,
    ContractError,
    ENTITLEMENTS,
    PROJECT,
    SOURCE_INFO,
    validate_info,
    validate_ipa,
    validate_new_build_identity,
    validate_personal_icons,
    validate_project,
)


def _app_info() -> dict[str, object]:
    info = plistlib.loads(SOURCE_INFO.read_bytes())
    info["CFBundleIdentifier"] = BUNDLE_ID
    return info


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

    def test_project_builds_only_the_app(self) -> None:
        text = PROJECT.read_text(encoding="utf-8")
        validate_project(text)
        self.assertIn("BgSyncScheduler.swift in Sources", text)
        # Re-adding an extension target is refused.
        widened = text.replace(
            "\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,\n",
            "\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,\n"
            "\t\t\t\t5348973A2FDC19C80033A4D9 /* OpenStrapWidgetExtension */,\n",
        )
        self.assertNotEqual(widened, text)
        with self.assertRaises(ContractError):
            validate_project(widened)

    def test_info_keeps_ble_and_motion_only(self) -> None:
        info = _app_info()
        validate_info(info)
        self.assertEqual(info["CFBundleDisplayName"], APP_NAME)
        self.assertEqual(info["CFBundleName"], APP_NAME)
        self.assertIn("NSMotionUsageDescription", info)
        self.assertNotIn("NSHealthShareUsageDescription", info)
        self.assertNotIn("NSSupportsLiveActivities", info)
        self.assertNotIn("OpenStrapAppGroupIdentifier", info)

    def test_info_location_keys(self) -> None:
        # Route recording uses While-In-Use; Pushups Home auto-pause (build 86, Akshat's
        # approval) asks for Always, so both descriptions ship and say what each is for.
        info = _app_info()
        self.assertIn("NSLocationWhenInUseUsageDescription", info)
        always = info["NSLocationAlwaysAndWhenInUseUsageDescription"]
        self.assertIn("Home", always)
        self.assertIn("never uploaded", always)
        missing = dict(info)
        del missing["NSLocationAlwaysAndWhenInUseUsageDescription"]
        with self.assertRaises(ContractError):
            validate_info(missing)

    def test_background_task_contract_is_exact(self) -> None:
        # Build 86: the two task identifiers and modes, nothing wider.
        info = _app_info()
        widened = dict(info, UIBackgroundModes=info["UIBackgroundModes"] + ["remote-notification"])
        with self.assertRaises(ContractError):
            validate_info(widened)
        missing = dict(info)
        missing.pop("BGTaskSchedulerPermittedIdentifiers")
        with self.assertRaises(ContractError):
            validate_info(missing)

    def test_entitlements_are_empty(self) -> None:
        self.assertEqual(plistlib.loads(ENTITLEMENTS.read_bytes()), {})

    def test_icon_catalog_is_complete(self) -> None:
        validate_personal_icons()
        self.assertTrue((APP_ICONS / "Icon-App-1024x1024@1x.png").is_file())

    def test_ipa_validator_refuses_any_extension(self) -> None:
        # Sideloadly's free signing provisions only the app's own App ID, so an
        # embedded extension (even the old workout Live Activity) is refused.
        info = _app_info()
        info.update(CFBundleVersion="95", CFBundleShortVersionString="0.9.62")
        extension = dict(CFBundleIdentifier=BUNDLE_ID + ".activity", CFBundleVersion="95",
            CFBundleShortVersionString="0.9.62", CFBundleExecutable="Activity",
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
            self.assertEqual(validate_ipa(plain)["CFBundleVersion"], "95")


if __name__ == "__main__":
    unittest.main()
