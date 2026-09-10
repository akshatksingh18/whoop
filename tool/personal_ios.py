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
    # Runner target: do not build or embed extension companions.
    '\t\t\t\t5348974F2FDC19C90033A4D9 /* Embed Foundation Extensions */,\n',
    '\t\t\t\tFADE0002FADE0002FADE0002 /* Embed Watch Content */,\n',
    '\t\t\t\t5348974D2FDC19C90033A4D9 /* PBXTargetDependency */,\n',
    '\t\t\t\tFADE0004FADE0004FADE0004 /* PBXTargetDependency */,\n',
    # Personal build has no Firebase resource generator or symbol uploader.
    '\t\t\t\t47E3AF2498550A854A4821B6 /* Ensure GoogleService-Info.plist */,\n',
    '\t\t\t\tAEFDDC7BFE6597FE6A6F1BB9 /* FlutterFire: "flutterfire upload-crashlytics-symbols" */,\n',
    '\t\t\t\t511D97990D2F790E7357E9B4 /* GoogleService-Info.plist in Resources */,\n',
    # Native surfaces excluded by the personal capability contract.
    '\t\t\t\t534897A72FDC2B310033A4D9 /* LiveActivityBridge.swift in Sources */,\n',
    '\t\t\t\tBEEF00000000000000000002 /* BreathingLiveActivityBridge.swift in Sources */,\n',
    '\t\t\t\t53962E962FF6EE120061A61B /* WatchBridge.swift in Sources */,\n',
    '\t\t\t\t53962E972FF6EE120061A61B /* OpenStrapIntents.swift in Sources */,\n',
    '\t\t\t\t0BGTASK00000000000000001 /* BgSyncScheduler.swift in Sources */,\n',
    '\t\t\t\t60DE9D949573401269D6DF2E /* HealthRoutes.swift in Sources */,\n',
    '\t\t\t\tB9D2F406183A5C7E92B1D3F5 /* HealthKitSleepWriter.swift in Sources */,\n',
)

_RUNNER_CONFIGS = (
    ("249021D4217E4FDB00AE95B9", "Profile"),
    ("97C147061CF9000F007C117D", "Debug"),
    ("97C147071CF9000F007C117D", "Release"),
)

_FORBIDDEN_INFO_KEYS = {
    "BGTaskSchedulerPermittedIdentifiers",
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSSupportsLiveActivities",
    "OpenStrapAppGroupIdentifier",
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
    return text


def personal_info(source: dict[str, object]) -> dict[str, object]:
    """Derive the minimal Info.plist while keeping the generated ASK declarations."""
    out = dict(source)
    for key in _FORBIDDEN_INFO_KEYS:
        out.pop(key, None)
    out["CFBundleDisplayName"] = APP_NAME
    out["CFBundleName"] = APP_NAME
    out["OpenStrapPersonalSideload"] = True
    out["UIBackgroundModes"] = ["bluetooth-central"]
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
    if info.get("UIBackgroundModes") != ["bluetooth-central"]:
        raise ContractError("UIBackgroundModes must contain only bluetooth-central")
    for key in _FORBIDDEN_INFO_KEYS:
        if key in info:
            raise ContractError(f"forbidden Info.plist key remains: {key}")
    for key in (
        "NSAccessorySetupBluetoothServices",
        "NSBluetoothAlwaysUsageDescription",
        "NSMotionUsageDescription",
        "UIFileSharingEnabled",
    ):
        if key not in info:
            raise ContractError(f"required Info.plist key is missing: {key}")


def check_project() -> None:
    transformed = transform_project(PROJECT.read_text(encoding="utf-8"))
    if transformed.count("PERSONAL_SIDELOAD") != 3:
        raise ContractError("all three Runner configurations must define PERSONAL_SIDELOAD")
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
        lowered = [name.lower() for name in names]
        forbidden_paths = [
            name
            for name in names
            if "/watch/" in name.lower()
            or ".appex/" in name.lower()
            or name.lower().endswith("embedded.mobileprovision")
            or name.lower().endswith("googleService-info.plist".lower())
            or name.lower().endswith((".db", ".sqlite", ".jsonl", ".env"))
        ]
        if forbidden_paths:
            raise ContractError(f"forbidden payload entries: {forbidden_paths[:5]}")
        if any("payload/runner.app/plugins/" in name for name in lowered):
            raise ContractError("extension PlugIns directory remains in payload")
        _, info = _ipa_info(archive)
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
            "locationRoutes": False,
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
