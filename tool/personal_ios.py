#!/usr/bin/env python3
"""Verify the personal iPhone project and its sideload artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import struct
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj"
SOURCE_INFO = ROOT / "ios" / "Runner" / "Info.plist"
ENTITLEMENTS = ROOT / "ios" / "Runner" / "Runner.entitlements"
ACCEPTED_BUILDS = ROOT / "tool" / "personal_ios_accepted_builds.json"
APP_ICONS = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
APP_NAME = "WHOOP"
BUNDLE_ID = "com.akshat.personal.whoop"

# The Xcode project holds exactly these targets: the app and its unit tests.
# No extension, Watch app, widget or Live Activity is built or embedded:
# Sideloadly's free signing provisions only the app's own App ID.
PROJECT_TARGETS = ["Runner", "RunnerTests"]

# Build 86 (Akshat's approval): bounded BGAppRefreshTask/BGProcessingTask
# opportunities supplement BLE wakes and foreground catch-up. Exactly these
# two identifiers and modes; neither is a correctness requirement (iOS grants
# no schedule).
try:
    from .legacy_identifiers import BG_TASK_IDS, RETIRED_INFO_KEYS
except ImportError:
    from legacy_identifiers import BG_TASK_IDS, RETIRED_INFO_KEYS
BACKGROUND_MODES = {"bluetooth-central", "location", "audio", "fetch", "processing"}

_FORBIDDEN_INFO_KEYS = {
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
    "NSSupportsLiveActivities",
    "WhoopAppGroupIdentifier",
    "WHOOPWorkoutLiveActivity",
    "FirebaseCrashlyticsCollectionEnabled",
}

# NSLocationAlwaysAndWhenInUseUsageDescription is REQUIRED from build 86 (Akshat's
# approval): Pushups Home auto-pause asks for Always so region events arrive while
# WHOOP is closed. Route recording still asks for While-In-Use only.
_REQUIRED_INFO_KEYS = (
    "NSAccessorySetupBluetoothServices",
    "NSBluetoothAlwaysUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSMotionUsageDescription",
    "UIFileSharingEnabled",
)


class ContractError(RuntimeError):
    pass


def validate_personal_icons() -> None:
    contents_path = APP_ICONS / "Contents.json"
    if not contents_path.is_file():
        raise ContractError("app icon catalog is missing")
    contents = json.loads(contents_path.read_text(encoding="utf-8"))
    filenames = {
        image.get("filename")
        for image in contents.get("images", [])
        if image.get("filename")
    }
    if not filenames or "Icon-App-1024x1024@1x.png" not in filenames:
        raise ContractError("app icon catalog has no marketing icon")
    missing = sorted(name for name in filenames if not (APP_ICONS / name).is_file())
    if missing:
        raise ContractError(f"app icon files are missing: {missing}")
    for image in contents["images"]:
        filename = image.get("filename")
        if not filename:
            continue
        size = float(image["size"].split("x", 1)[0])
        scale = int(image["scale"].removesuffix("x"))
        expected = round(size * scale)
        data = (APP_ICONS / filename).read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
            raise ContractError(f"app icon is not a PNG: {filename}")
        width, height, _, color_type, _, _, _ = struct.unpack(">IIBBBBB", data[16:29])
        if (width, height) != (expected, expected):
            raise ContractError(
                f"app icon {filename} is {width}x{height}, expected {expected}x{expected}"
            )
        if color_type in {4, 6}:
            raise ContractError(f"app icon must not contain alpha: {filename}")


def validate_new_build_identity(
    pubspec_text: str | None = None,
    accepted: dict[str, object] | None = None,
) -> tuple[str, str]:
    """Refuse a version/build pair already assigned to an accepted personal IPA."""
    text = pubspec_text if pubspec_text is not None else (ROOT / "pubspec.yaml").read_text(
        encoding="utf-8"
    )
    match = re.search(r"^version:\s*([^\s+]+)\+(\d+)\s*$", text, re.MULTILINE)
    if not match:
        raise ContractError("pubspec version must use VERSION+INTEGER_BUILD")
    version, build = match.groups()
    ledger = accepted
    if ledger is None:
        ledger = json.loads(ACCEPTED_BUILDS.read_text(encoding="utf-8"))
    used = {
        (str(item["version"]), str(item["build"]))
        for item in ledger.get("acceptedBuilds", [])
    }
    if (version, build) in used:
        raise ContractError(
            f"personal build {version}+{build} is already accepted; bump pubspec before building"
        )
    return version, build


def validate_project(text: str) -> None:
    """Refuse a project that would build or embed anything beyond Runner."""
    targets = re.search(r"\ttargets = \(\n(.*?)\n\t\t\t\);", text, re.S)
    if not targets:
        raise ContractError("project has no target list")
    names = re.findall(r"/\* (.+?) \*/", targets.group(1))
    if names != PROJECT_TARGETS:
        raise ContractError(f"project targets are {names}, expected {PROJECT_TARGETS}")
    for forbidden in (".appex", "Embed Foundation Extensions", "Embed Watch Content",
                      "GoogleService-Info.plist", "flutterfire", "HealthKit",
                      "ALTERNATE_APPICON_NAMES", "PERSONAL_SIDELOAD"):
        if forbidden in text:
            raise ContractError(f"project still mentions {forbidden}")
    for setting, count in (
        ("\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;", 3),
        ("\t\t\t\tINFOPLIST_FILE = Runner/Info.plist;", 3),
        ("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", 3),
    ):
        if text.count(setting) != count:
            raise ContractError(f"expected {count} Runner configurations with {setting.strip()}")


def validate_info(info: dict[str, object], resolved_bundle_id: str | None = BUNDLE_ID) -> None:
    if resolved_bundle_id is not None and info.get("CFBundleIdentifier") != resolved_bundle_id:
        raise ContractError(
            f"bundle id is {info.get('CFBundleIdentifier')!r}, expected {resolved_bundle_id!r}"
        )
    if info.get("CFBundleDisplayName") != APP_NAME or info.get("CFBundleName") != APP_NAME:
        raise ContractError(f"app name must be {APP_NAME}")
    modes = info.get("UIBackgroundModes") or []
    if len(modes) != len(BACKGROUND_MODES) or set(modes) != BACKGROUND_MODES:
        raise ContractError("UIBackgroundModes must be exactly " + ", ".join(sorted(BACKGROUND_MODES)))
    if info.get("BGTaskSchedulerPermittedIdentifiers") != BG_TASK_IDS:
        raise ContractError(
            "BGTaskSchedulerPermittedIdentifiers must be exactly " + ", ".join(BG_TASK_IDS)
        )
    for key in _FORBIDDEN_INFO_KEYS:
        if key in info:
            raise ContractError(f"forbidden Info.plist key remains: {key}")
    for key in _REQUIRED_INFO_KEYS:
        if key not in info:
            raise ContractError(f"required Info.plist key is missing: {key}")


def check_project() -> None:
    validate_new_build_identity()
    validate_project(PROJECT.read_text(encoding="utf-8"))
    if plistlib.loads(ENTITLEMENTS.read_bytes()):
        raise ContractError("Runner entitlements must remain empty")
    validate_info(plistlib.loads(SOURCE_INFO.read_bytes()), resolved_bundle_id=None)
    validate_personal_icons()


def _ipa_info(archive: zipfile.ZipFile) -> tuple[str, dict[str, object]]:
    infos = [
        name
        for name in archive.namelist()
        if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)
    ]
    if len(infos) != 1:
        raise ContractError(f"expected one root app Info.plist, found {len(infos)}")
    return infos[0], plistlib.loads(archive.read(infos[0]))


def validate_ipa(path: Path) -> dict[str, object]:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        _, info = _ipa_info(archive)
        forbidden_paths = [
            name
            for name in names
            if "/watch/" in name.lower()
            or ".appex/" in name.lower()
            or "/plugins/" in name.lower()
            or name.lower().endswith("embedded.mobileprovision")
            or name.lower().endswith("googleService-info.plist".lower())
            or name.lower().endswith((".db", ".sqlite", ".jsonl", ".env"))
        ]
        if forbidden_paths:
            raise ContractError(f"forbidden payload entries: {forbidden_paths[:5]}")
        validate_info(info)
        return info


def write_manifest(ipa: Path, output: Path, source_revision: str) -> None:
    info = validate_ipa(ipa)
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    payload = {
        "profile": "personal-sideload",
        "appName": APP_NAME,
        "bundleId": BUNDLE_ID,
        "version": version,
        "build": build,
        "sourceRevision": source_revision,
        "builtAtUtc": datetime.now(timezone.utc).isoformat(),
        "sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
        "capabilities": {
            "bluetoothCentral": True,
            "coreBluetoothRestoration": True,
            "phonePedometer": True,
            "filesSharing": True,
            "healthKit": False,
            "locationRoutes": True,
            # Read from the packaged Info.plist, not written by hand: build 86
            # shipped processing while this line still said False.
            "backgroundProcessing": "processing" in (info.get("UIBackgroundModes") or []),
            "backgroundRefresh": "fetch" in (info.get("UIBackgroundModes") or []),
            "homeRegionAlwaysLocation": "NSLocationAlwaysAndWhenInUseUsageDescription" in info,
            "firebaseInitialization": False,
            "healthDataContribution": False,
            "watch": False,
            "widgets": False,
            "liveActivities": False,
        },
    }
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    validate = sub.add_parser("validate")
    validate.add_argument("ipa", type=Path)
    manifest = sub.add_parser("manifest")
    manifest.add_argument("ipa", type=Path)
    manifest.add_argument("output", type=Path)
    manifest.add_argument("--source-revision", required=True)
    args = parser.parse_args()

    try:
        if args.command == "check":
            check_project()
        elif args.command == "validate":
            validate_ipa(args.ipa)
        else:
            write_manifest(args.ipa, args.output, args.source_revision)
    except (ContractError, OSError, plistlib.InvalidFileException, zipfile.BadZipFile) as exc:
        print(f"personal iOS contract failed: {exc}", file=sys.stderr)
        return 1
    print(f"personal iOS {args.command}: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
