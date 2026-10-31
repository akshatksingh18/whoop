"""Offline source/version drift guard for the two in-tree packages."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = {"whoop_protocol": "packages/protocol", "whoop_analytics": "packages/analytics"}


def source_digest(root: Path, relative: str) -> str:
    digest = hashlib.sha256()
    files = sorted((root / relative / "lib").rglob("*.dart"))
    if not files:
        raise ValueError(f"No Dart sources in {relative}")
    for path in files:
        name = path.relative_to(root / relative).as_posix().encode()
        body = path.read_bytes().replace(b"\r\n", b"\n")
        digest.update(name + b"\0" + str(len(body)).encode() + b"\0" + body + b"\0")
    return digest.hexdigest()


def algorithm_version(root: Path) -> int:
    text = (root / "lib/compute/derivation_engine.dart").read_text(encoding="utf-8")
    match = re.search(r"^const int kAlgoVersion\s*=\s*(\d+);", text, re.M)
    if not match:
        raise ValueError("Missing algorithm version")
    return int(match[1])


def block(text: str, package: str) -> str:
    match = re.search(rf"^  {re.escape(package)}:\s*\n(.*?)(?=^  \w+:|\Z)", text, re.M | re.S)
    if not match:
        raise ValueError(f"Missing package {package}")
    return match[1]


def field(text: str, name: str) -> str:
    match = re.search(rf"^\s+{name}:\s*(.+?)\s*$", text, re.M)
    if not match:
        raise ValueError(f"Missing {name}")
    return match[1].strip("\"'")


def check(root: Path = ROOT) -> None:
    if (root / "pubspec_overrides.yaml").exists():
        raise ValueError("Dependency overrides are forbidden")
    manifest = json.loads((root / "packages/algorithm-contract.json").read_text(encoding="utf-8"))
    if manifest["algorithmVersion"] != algorithm_version(root):
        raise ValueError("Algorithm version disagrees with the source contract")
    if not manifest.get("review", "").strip():
        raise ValueError("Source changes require an output/version review")
    declared = (root / "pubspec.yaml").read_text(encoding="utf-8")
    locked = (root / "pubspec.lock").read_text(encoding="utf-8")
    for package, relative in PACKAGES.items():
        if field(block(declared, package), "path") != relative:
            raise ValueError(f"Wrong declared path for {package}")
        lock = block(locked, package)
        if (field(lock, "path"), field(lock, "source"), field(lock, "relative")) != (relative, "path", "true"):
            raise ValueError(f"Wrong locked resolution for {package}")
        package_yaml = (root / relative / "pubspec.yaml").read_text(encoding="utf-8")
        if not re.search(rf"^name:\s*{re.escape(package)}\s*$", package_yaml, re.M):
            raise ValueError(f"Wrong package identity in {relative}")
        if manifest["packages"].get(package) != source_digest(root, relative):
            raise ValueError(f"{package} source changed: review outputs and kAlgoVersion before updating its digest")


if __name__ == "__main__":
    try:
        check()
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Algorithm contract failed: {error}") from error
    print("In-tree package identities, paths, source digests and algorithm version agree.")
