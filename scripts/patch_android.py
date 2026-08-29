#!/usr/bin/env python3
"""Force compileSdk 36 / minSdk 23 and add missing Android plugin namespaces."""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path

COMPILE_SDK = 36
MIN_SDK = 23


def patch_app_gradle(root: Path) -> None:
    app = root / "flutter_app" / "android" / "app" / "build.gradle.kts"
    if not app.exists():
        app = root / "flutter_app" / "android" / "app" / "build.gradle"
    if not app.exists():
        return
    text = app.read_text(encoding="utf-8")
    text = re.sub(r"compileSdk\s*=\s*[^\n]+", f"compileSdk = {COMPILE_SDK}", text)
    text = re.sub(r"compileSdkVersion\s+[^\n]+", f"compileSdkVersion {COMPILE_SDK}", text)
    text = re.sub(r"minSdk\s*=\s*[^\n]+", f"minSdk = {MIN_SDK}", text)
    text = re.sub(r"minSdkVersion\s+[^\n]+", f"minSdkVersion {MIN_SDK}", text)
    app.write_text(text, encoding="utf-8")
    print(f"patched app gradle: {app}")


def manifest_package(android_dir: Path) -> str | None:
    for rel in (
        "src/main/AndroidManifest.xml",
        "AndroidManifest.xml",
    ):
        manifest = android_dir / rel
        if not manifest.exists():
            continue
        raw = manifest.read_text(encoding="utf-8", errors="ignore")
        m = re.search(r'package="([^"]+)"', raw)
        if m:
            return m.group(1)
    return None


def insert_namespace(text: str, namespace: str, kts: bool) -> str:
    if re.search(r"\bnamespace\b", text):
        return text
    if kts:
        injection = f'    namespace = "{namespace}"\n'
    else:
        injection = f'    namespace "{namespace}"\n'
    return re.sub(r"(android\s*\{)", r"\1\n" + injection, text, count=1)


def force_compile_sdk(text: str, kts: bool) -> str:
    # Never rewrite `compileSdk { ... }` (AGP 9 / camera_android_camerax).
    # Only numeric compileSdk / compileSdkVersion assignments.
    text = re.sub(r"compileSdkVersion\s+\d+", f"compileSdkVersion {COMPILE_SDK}", text)
    text = re.sub(r"compileSdk\s*=\s*\d+", f"compileSdk = {COMPILE_SDK}", text)
    text = re.sub(r"compileSdk\s+\d+\b", f"compileSdk {COMPILE_SDK}", text)
    text = re.sub(
        r"(compileSdk\s*\{[^}]*?\bversion\s*=\s*(?:release\s*\(\s*)?)\d+",
        rf"\g<1>{COMPILE_SDK}",
        text,
    )
    # Repair a previous bad replace: `compileSdk 36` + leftover `version = … }`
    text = re.sub(
        r"compileSdk\s+36\s*\n\s*version\s*=\s*[^\n]+\n\s*\}\s*\n",
        f"compileSdk {COMPILE_SDK}\n",
        text,
    )
    if "compileSdk" not in text and re.search(r"android\s*\{", text):
        if kts:
            text = re.sub(r"(android\s*\{)", rf"\1\n    compileSdk = {COMPILE_SDK}\n", text, count=1)
        else:
            text = re.sub(r"(android\s*\{)", rf"\1\n    compileSdkVersion {COMPILE_SDK}\n", text, count=1)
    return text


def patch_plugin_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="ignore")
    original = text
    kts = path.suffix == ".kts"
    android_dir = path.parent
    ns = manifest_package(android_dir)
    if ns:
        text = insert_namespace(text, ns, kts)
    text = force_compile_sdk(text, kts)
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"patched plugin gradle: {path}")
        return True
    return False


def iter_plugin_gradles() -> list[Path]:
    homes = [
        Path.home() / ".pub-cache",
        Path(os.environ.get("PUB_CACHE", "")),
        Path("flutter_app/.dart_tool"),
    ]
    found: list[Path] = []
    for home in homes:
        if not home or not home.exists():
            continue
        for name in ("build.gradle", "build.gradle.kts"):
            found.extend(home.rglob(f"android/{name}"))
    # unique
    uniq = []
    seen = set()
    for p in found:
        s = str(p.resolve())
        if s in seen:
            continue
        seen.add(s)
        uniq.append(p)
    return uniq


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plugins", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    patch_app_gradle(root)
    if args.plugins:
        count = 0
        for path in iter_plugin_gradles():
            if patch_plugin_file(path):
                count += 1
        print(f"plugin files changed: {count}")


if __name__ == "__main__":
    main()
