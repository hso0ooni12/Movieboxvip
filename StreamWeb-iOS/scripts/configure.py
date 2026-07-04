#!/usr/bin/env python3
"""Configure app identity and web URL before generating the Xcode project."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "StreamWeb" / "Resources" / "AppConfig.json"
PROJECT_PATH = ROOT / "project.yml"


def fail(message: str) -> None:
    print(f"Configuration error: {message}", file=sys.stderr)
    raise SystemExit(2)


def validate_bundle_id(value: str) -> str:
    value = value.strip()
    pattern = r"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$"
    if not re.fullmatch(pattern, value):
        fail("bundle ID must look like com.yourname.app")
    return value


def validate_url(value: str) -> str:
    value = value.strip()
    parsed = urlparse(value)
    if parsed.scheme not in {"https", "http"} or not parsed.netloc:
        fail("home URL must be a complete http/https URL")
    return value


def validate_hex(value: str) -> str:
    value = value.strip().upper()
    if not re.fullmatch(r"#[0-9A-F]{6}", value):
        fail("accent color must be in #RRGGBB format")
    return value


def replace_setting(text: str, key: str, value: str) -> str:
    replacement = f"        {key}: {json.dumps(value, ensure_ascii=False)}"
    pattern = rf"^\s{{8}}{re.escape(key)}:.*$"
    updated, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if count != 1:
        fail(f"could not update {key} in project.yml")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-name", required=True)
    parser.add_argument("--home-url", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--accent-hex", default="#E50914")
    parser.add_argument("--open-external-in-safari", action="store_true")
    parser.add_argument("--disable-ad-blocking", action="store_true")
    args = parser.parse_args()

    app_name = args.app_name.strip()
    if not app_name or len(app_name) > 30:
        fail("app name must be between 1 and 30 characters")

    home_url = validate_url(args.home_url)
    bundle_id = validate_bundle_id(args.bundle_id)
    accent_hex = validate_hex(args.accent_hex)

    config = {
        "appName": app_name,
        "homeURL": home_url,
        "opensExternalHostsInSafari": args.open_external_in_safari,
        "accentHex": accent_hex,
        "adBlockingEnabled": not args.disable_ad_blocking,
    }
    CONFIG_PATH.write_text(
        json.dumps(config, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    project = PROJECT_PATH.read_text(encoding="utf-8")
    project = replace_setting(project, "PRODUCT_BUNDLE_IDENTIFIER", bundle_id)
    project = replace_setting(project, "APP_DISPLAY_NAME", app_name)
    PROJECT_PATH.write_text(project, encoding="utf-8")

    print(f"Configured {app_name} ({bundle_id}) -> {home_url}")


if __name__ == "__main__":
    main()
