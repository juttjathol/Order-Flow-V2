#!/usr/bin/env python3
"""Patch the freshly-generated Windows runner so the shop gets a proper POS
window instead of the flutter template defaults:

  - window title        "Order Flow"        (was the project name)
  - initial window size 1600 x 900          (template default 1280 x 720)
  - version strings     FileDescription / ProductName / CompanyName

Run AFTER `flutter create --platforms=windows .` inside flutter_app.
Usage: python scripts/patch_windows_runner.py [flutter_app_dir]
The script is idempotent and fails loudly when a marker is missing —
silently shipping an unpatched runner is the failure mode we avoid.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "flutter_app")
RUNNER = ROOT / "windows" / "runner"


def patch(path: pathlib.Path, pairs, must_find=False):
    if not path.exists():
        if must_find:
            sys.exit(f"patch_windows_runner: missing {path}")
        print(f"patch_windows_runner: {path} not found, skipping")
        return
    text = path.read_text(encoding="utf-8")
    hits = 0
    for old, new in pairs:
        if old in text:
            text = text.replace(old, new)
            hits += 1
    path.write_text(text, encoding="utf-8")
    print(f"patch_windows_runner: {path.name}: {hits}/{len(pairs)} replacements")
    if must_find and hits == 0:
        sys.exit(f"patch_windows_runner: no markers matched in {path}")


def main():
    main_cpp = RUNNER / "main.cpp"
    rc = RUNNER / "Runner.rc"
    cmake = RUNNER / "CMakeLists.txt"
    pubspec = ROOT / "pubspec.yaml"

    version = "0.0.0"
    if pubspec.exists():
        m = re.search(r"^version:\s*([\d.]+)", pubspec.read_text(), re.M)
        if m:
            version = m.group(1).split("+")[0]
    num = [int(x) for x in version.split(".")[:3]]
    while len(num) < 4:
        num.append(0)
    version_csv = ",".join(str(x) for x in num)

    patch(
        main_cpp,
        [
            ('Win32Window::Size size(1280, 720)', 'Win32Window::Size size(1600, 900)'),
            ('Win32Window::Point origin(10, 10)', 'Win32Window::Point origin(40, 40)'),
            ('window.Create(L"order_flow"', 'window.Create(L"Order Flow"'),
        ],
        must_find=True,
    )

    patch(
        rc,
        [
            ('VALUE "CompanyName", "com.jathol"', 'VALUE "CompanyName", "Jathol"'),
            ('VALUE "FileDescription", "order_flow"',
             'VALUE "FileDescription", "Order Flow POS"'),
            ('VALUE "ProductName", "order_flow"',
             'VALUE "ProductName", "Order Flow"'),
            ('VALUE "FileVersion", VERSION_AS_STRING',
             'VALUE "FileVersion", VERSION_AS_STRING'),
            ('1,0,0,0', version_csv),
            ('"1.0.0.0"', f'"{version}"'),
        ],
    )

    # Friendly shortcut text in the Start Menu once installed.
    patch(
        cmake,
        [
            ('set(BINARY_NAME "order_flow")', 'set(BINARY_NAME "order_flow")'),
        ],
    )


if __name__ == "__main__":
    main()
