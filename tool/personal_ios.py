#!/usr/bin/env python3
"""Prepare and verify the deterministic personal iPhone sideload artifact."""

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
PERSONAL_INFO = ROOT / "ios" / "Runner" / "Info-Personal.plist"
PERSONAL_ENTITLEMENTS = ROOT / "ios" / "Runner" / "RunnerPersonal.entitlements"
ACCEPTED_BUILDS = ROOT / "tool" / "personal_ios_accepted_builds.json"
PERSONAL_ICONS = (
    ROOT
    / "ios"
    / "Runner"
    / "Assets.xcassets"
    / "AppIconPersonal.appiconset"
)
APP_NAME = "WHOOP"
BUNDLE_ID = "com.akshat.personal.whoop"

_REMOVE_ONCE = (
    # Runner target: do not build or embed extension companions. The workout
    # Live Activity extension is excluded again from build 81: Sideloadly's free
    # signing provisions only the app's App ID, so iOS killed the extension at
    # launch (CODESIGNING "Invalid Page") and the activity never drew.
    '\t\t\t\t5348974F2FDC19C90033A4D9 /* Embed Foundation Extensions */,\n',
    '\t\t\t\tFADE0002FADE0002FADE0002 /* Embed Watch Content */,\n',
    '\t\t\t\t5348974D2FDC19C90033A4D9 /* PBXTargetDependency */,\n',
    '\t\t\t\tFADE0004FADE0004FADE0004 /* PBXTargetDependency */,\n',
    # Personal build has no Firebase resource generator or symbol uploader.
    '\t\t\t\t47E3AF2498550A854A4821B6 /* Ensure GoogleService-Info.plist */,\n',
    '\t\t\t\tAEFDDC7BFE6597FE6A6F1BB9 /* FlutterFire: "flutterfire upload-crashlytics-symbols" */,\n',
    '\t\t\t\t511D97990D2F790E7357E9B4 /* GoogleService-Info.plist in Resources */,\n',
    # Native surfaces excluded by the personal capability contract.
    '\t\t\t\tBEEF00000000000000000002 /* BreathingLiveActivityBridge.swift in Sources */,\n',
    '\t\t\t\t53962E962FF6EE120061A61B /* WatchBridge.swift in Sources */,\n',
    '\t\t\t\t53962E972FF6EE120061A61B /* OpenStrapIntents.swift in Sources */,\n',
    '\t\t\t\t60DE9D949573401269D6DF2E /* HealthRoutes.swift in Sources */,\n',
    '\t\t\t\tB9D2F406183A5C7E92B1D3F5 /* HealthKitSleepWriter.swift in Sources */,\n',
)

_RUNNER_CONFIGS = (
    ("249021D4217E4FDB00AE95B9", "Profile"),
    ("97C147061CF9000F007C117D", "Debug"),
    ("97C147071CF9000F007C117D", "Release"),
)

# Build 86 (Akshat's approval): bounded BGAppRefreshTask/BGProcessingTask
# opportunities supplement BLE wakes and foreground catch-up. Exactly these
# two identifiers and modes; no extension, App Group or HealthKit comes with
# them, and neither is a correctness requirement (iOS grants no schedule).
PERSONAL_BG_TASK_IDS = ["wtf.openstrap.edge.bgsync", "wtf.openstrap.edge.refresh"]
PERSONAL_BACKGROUND_MODES = ["bluetooth-central", "location", "audio", "fetch", "processing"]

_FORBIDDEN_INFO_KEYS = {
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
    # NSLocationAlwaysAndWhenInUseUsageDescription is REQUIRED from build 86 (Akshat's
    # approval): Pushups Home auto-pause asks for Always so region events arrive while WHOOP is
    # closed. Route recording still asks for While-In-Use only (lib/gps/gps_source.dart).
    "NSSupportsLiveActivities",
    "OpenStrapAppGroupIdentifier",
    "OpenStrapWorkoutLiveActivity",
}


class ContractError(RuntimeError):
    pass


def _replace_exact(text: str, old: str, new: str, count: int) -> str:
    found = text.count(old)
    if found != count:
        raise ContractError(f"expected {count} copies of {old!r}, found {found}")
    return text.replace(old, new)


def _add_personal_condition(text: str, config_id: str, name: str) -> str:
    start_marker = f"\t\t{config_id} /* {name} */ = {{"
    start = text.find(start_marker)
    if start < 0:
        raise ContractError(f"missing Runner {name} configuration {config_id}")
    end = text.find("\n\t\t};", start)
    if end < 0:
        raise ContractError(f"unterminated Runner {name} configuration {config_id}")
    block = text[start:end]
    needle = "\t\t\t\tSWIFT_VERSION = 5.0;"
    if block.count(needle) != 1:
        raise ContractError(f"Runner {name} configuration has unexpected Swift settings")
    replacement = (
        '\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) PERSONAL_SIDELOAD";\n'
        + needle
    )
    block = block.replace(needle, replacement)
    icon_setting = "\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"
    if block.count(icon_setting) != 1:
        raise ContractError(f"Runner {name} configuration has unexpected app icon settings")
    block = block.replace(
        icon_setting,
        "\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIconPersonal;",
    )
    return text[:start] + block + text[end:]


def validate_personal_icons() -> None:
    contents_path = PERSONAL_ICONS / "Contents.json"
    if not contents_path.is_file():
        raise ContractError("personal app icon catalog is missing")
    contents = json.loads(contents_path.read_text(encoding="utf-8"))
    filenames = {
        image.get("filename")
        for image in contents.get("images", [])
        if image.get("filename")
    }
    if not filenames or "Icon-App-1024x1024@1x.png" not in filenames:
        raise ContractError("personal app icon catalog has no marketing icon")
    missing = sorted(name for name in filenames if not (PERSONAL_ICONS / name).is_file())
    if missing:
        raise ContractError(f"personal app icon files are missing: {missing}")
    for image in contents["images"]:
        filename = image.get("filename")
        if not filename:
            continue
        size = float(image["size"].split("x", 1)[0])
        scale = int(image["scale"].removesuffix("x"))
        expected = round(size * scale)
        data = (PERSONAL_ICONS / filename).read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
            raise ContractError(f"personal app icon is not a PNG: {filename}")
        width, height, _, color_type, _, _, _ = struct.unpack(">IIBBBBB", data[16:29])
        if (width, height) != (expected, expected):
            raise ContractError(
                f"personal app icon {filename} is {width}x{height}, expected {expected}x{expected}"
            )
        if color_type in {4, 6}:
            raise ContractError(f"personal app icon must not contain alpha: {filename}")


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


def transform_project(text: str) -> str:
    """Return the personal Runner project, refusing unknown upstream drift."""
    for line in _REMOVE_ONCE:
        text = _replace_exact(text, line, "", 1)
    text = _replace_exact(
        text,
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;",
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/RunnerPersonal.entitlements;",
        3,
    )
    text = _replace_exact(
        text,
        "\t\t\t\tINFOPLIST_FILE = Runner/Info.plist;",
        "\t\t\t\tINFOPLIST_FILE = Runner/Info-Personal.plist;",
        3,
    )
    for config_id, name in _RUNNER_CONFIGS:
        text = _add_personal_condition(text, config_id, name)
    # Keep exactly the local workout activity; no home widgets, breathing
    # activity or App Group dependency in the personal extension.
    text = _replace_exact(text,
        "CODE_SIGN_ENTITLEMENTS = OpenStrapWidgetExtension.entitlements;",
        "CODE_SIGN_ENTITLEMENTS = Runner/RunnerPersonal.entitlements;", 3)
    text = _replace_exact(text,
        'PRODUCT_BUNDLE_IDENTIFIER = "$(APP_WIDGET_BUNDLE_IDENTIFIER)";',
        'PRODUCT_BUNDLE_IDENTIFIER = "$(APP_BUNDLE_IDENTIFIER).activity";', 3)
    # Synchronized source membership is explicit and checked for upstream drift.
    excluded = sorted(p.name for p in (ROOT / "ios" / "OpenStrapWidget").glob("*.swift")
        if p.name not in {"OpenStrapWidgetBundle.swift", "OpenStrapWidgetLiveActivity.swift"})
    needle = "membershipExceptions = (\n\t\t\t\tInfo.plist,"
    text = _replace_exact(text, needle, needle + "".join(
        "\n\t\t\t\t" + name + "," for name in excluded), 1)
    for config_id in ("534897502FDC19C90033A4D9", "534897512FDC19C90033A4D9", "534897522FDC19C90033A4D9"):
        # Set the condition only on the widget extension's three blocks.
        marker = config_id + " /* "
        start = text.find(marker, text.find("/* Begin XCBuildConfiguration section */"))
        if start < 0: raise ContractError("missing widget configuration " + config_id)
        end = text.find("\n\t\t};", start)
        block = text[start:end]
        needle = "SWIFT_VERSION = 5.0;"
        if block.count(needle) != 1: raise ContractError("widget Swift settings changed")
        block = block.replace(needle, 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) PERSONAL_SIDELOAD";\n\t\t\t\t' + needle)
        text = text[:start] + block + text[end:]
    return text


def personal_info(source: dict[str, object]) -> dict[str, object]:
    """Derive the minimal Info.plist while keeping the generated ASK declarations."""
    out = dict(source)
    for key in _FORBIDDEN_INFO_KEYS:
        out.pop(key, None)
    out["CFBundleDisplayName"] = APP_NAME
    out["CFBundleName"] = APP_NAME
    out["OpenStrapPersonalSideload"] = True
    out["FlutterDeepLinkingEnabled"] = False
    out["CFBundleURLTypes"] = [{"CFBundleURLName": BUNDLE_ID, "CFBundleURLSchemes": ["whoop"]}]
    # "location" added alongside the existing bluetooth-central mode: this plus While-In-Use
    # authorization is what lets a run stay tracked with the screen locked, per gps_source.dart.
    # Always is asked for only by Pushups Home auto-pause (region monitoring, build 86).
    out["UIBackgroundModes"] = list(PERSONAL_BACKGROUND_MODES)
    out["BGTaskSchedulerPermittedIdentifiers"] = list(PERSONAL_BG_TASK_IDS)
    validate_info(out, resolved_bundle_id=None)
    return out


def validate_info(info: dict[str, object], resolved_bundle_id: str | None = BUNDLE_ID) -> None:
    if resolved_bundle_id is not None and info.get("CFBundleIdentifier") != resolved_bundle_id:
        raise ContractError(
            f"bundle id is {info.get('CFBundleIdentifier')!r}, expected {resolved_bundle_id!r}"
        )
    if info.get("OpenStrapPersonalSideload") is not True:
        raise ContractError("personal-build marker is missing")
    if info.get("CFBundleDisplayName") != APP_NAME or info.get("CFBundleName") != APP_NAME:
        raise ContractError(f"personal app name must be {APP_NAME}")
    if info.get("UIBackgroundModes") != PERSONAL_BACKGROUND_MODES:
        raise ContractError(
            "UIBackgroundModes must be exactly " + ", ".join(PERSONAL_BACKGROUND_MODES)
        )
    if info.get("BGTaskSchedulerPermittedIdentifiers") != PERSONAL_BG_TASK_IDS:
        raise ContractError(
            "BGTaskSchedulerPermittedIdentifiers must be exactly " + ", ".join(PERSONAL_BG_TASK_IDS)
        )
    for key in _FORBIDDEN_INFO_KEYS:
        if key in info:
            raise ContractError(f"forbidden Info.plist key remains: {key}")
    for key in (
        "NSAccessorySetupBluetoothServices",
        "NSBluetoothAlwaysUsageDescription",
        "NSLocationWhenInUseUsageDescription",
        "NSLocationAlwaysAndWhenInUseUsageDescription",
        "NSMotionUsageDescription",
        "UIFileSharingEnabled",
    ):
        if key not in info:
            raise ContractError(f"required Info.plist key is missing: {key}")


def check_project() -> None:
    validate_new_build_identity()
    transformed = transform_project(PROJECT.read_text(encoding="utf-8"))
    if transformed.count("PERSONAL_SIDELOAD") != 6:
        raise ContractError("Runner and workout extension configurations must define PERSONAL_SIDELOAD")
    entitlements = plistlib.loads(PERSONAL_ENTITLEMENTS.read_bytes())
    if entitlements:
        raise ContractError("personal Runner entitlements must remain empty")
    source = plistlib.loads(SOURCE_INFO.read_bytes())
    personal_info(source)
    validate_personal_icons()


def prepare() -> None:
    transformed = transform_project(PROJECT.read_text(encoding="utf-8"))
    PROJECT.write_text(transformed, encoding="utf-8")
    source = plistlib.loads(SOURCE_INFO.read_bytes())
    with PERSONAL_INFO.open("wb") as handle:
        plistlib.dump(personal_info(source), handle, sort_keys=False)
    widget_info = ROOT / "ios" / "OpenStrapWidget" / "Info.plist"
    extension = plistlib.loads(widget_info.read_bytes())
    extension.pop("OpenStrapAppGroupIdentifier", None)
    widget_info.write_bytes(plistlib.dumps(extension, sort_keys=False))


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
            "backgroundProcessing": False,
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
    sub.add_parser("prepare")
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
        elif args.command == "prepare":
            prepare()
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
