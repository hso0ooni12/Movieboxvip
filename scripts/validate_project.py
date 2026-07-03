#!/usr/bin/env python3
"""Fast structural validation that runs on Linux or macOS."""

from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_FILES = [
    "project.yml",
    "StreamWeb/Info.plist",
    "StreamWeb/Browser/AdBlocker.swift",
    "StreamWeb/Resources/AppConfig.json",
    "StreamWeb/Resources/AdBlockRules.json",
    "StreamWeb/Resources/PrivacyInfo.xcprivacy",
    "StreamWeb/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    ".github/workflows/ci.yml",
    ".github/workflows/build-ipa.yml",
]


def main() -> None:
    missing = [path for path in REQUIRED_FILES if not (ROOT / path).exists()]
    if missing:
        print("Missing required files:\n- " + "\n- ".join(missing), file=sys.stderr)
        raise SystemExit(1)

    config = json.loads((ROOT / "StreamWeb/Resources/AppConfig.json").read_text())
    required_config = {
        "appName",
        "homeURL",
        "opensExternalHostsInSafari",
        "accentHex",
        "adBlockingEnabled",
    }
    if set(config) != required_config:
        raise SystemExit(f"AppConfig.json keys must be exactly: {sorted(required_config)}")
    if not isinstance(config["adBlockingEnabled"], bool):
        raise SystemExit("adBlockingEnabled must be true or false")

    ad_rules = json.loads((ROOT / "StreamWeb/Resources/AdBlockRules.json").read_text())
    if not isinstance(ad_rules, list) or len(ad_rules) < 10:
        raise SystemExit("AdBlockRules.json must contain a non-trivial JSON rule list")
    for index, rule in enumerate(ad_rules):
        if not isinstance(rule, dict) or "trigger" not in rule or "action" not in rule:
            raise SystemExit(f"Invalid ad-blocking rule at index {index}")

    for relative in ["StreamWeb/Info.plist", "StreamWeb/Resources/PrivacyInfo.xcprivacy"]:
        with (ROOT / relative).open("rb") as handle:
            plistlib.load(handle)

    icon_manifest = json.loads(
        (ROOT / "StreamWeb/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json").read_text()
    )
    for image in icon_manifest.get("images", []):
        filename = image.get("filename")
        if filename and not (ROOT / "StreamWeb/Resources/Assets.xcassets/AppIcon.appiconset" / filename).exists():
            raise SystemExit(f"Missing app icon: {filename}")

    swift_files = list((ROOT / "StreamWeb").rglob("*.swift"))
    if not swift_files:
        raise SystemExit("No Swift files found")

    signed_workflow = ROOT / ".github/workflows/publish-testflight.yml"
    if signed_workflow.exists():
        raise SystemExit("Cloud-signing workflow should not exist in the unsigned-only project")

    workflow_text = (ROOT / ".github/workflows/build-ipa.yml").read_text()
    required_workflow_markers = [
        "Build Unsigned IPA",
        "CODE_SIGNING_ALLOWED=NO",
        "CODE_SIGNING_REQUIRED=NO",
        "Payload",
        "unsigned-ipa",
    ]
    for marker in required_workflow_markers:
        if marker not in workflow_text:
            raise SystemExit(f"Unsigned IPA workflow is missing: {marker}")

    print(
        f"Project structure is valid ({len(swift_files)} Swift files, "
        f"{len(ad_rules)} ad-blocking rules)."
    )


if __name__ == "__main__":
    main()
