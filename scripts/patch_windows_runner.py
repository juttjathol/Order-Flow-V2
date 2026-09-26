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
SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent  # → scripts/


def _run_version_sync() -> int:
    """Delegate to scripts/version_sync_check.py against this flutter_app."""
    import subprocess as sp

    checker = SCRIPTS_DIR / "version_sync_check.py"
    if not checker.exists():
        print("version-sync: checker script missing — skipping")
        return 0
    return sp.call([sys.executable, str(checker), str(ROOT)])


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
    # Version drift makes the in-app footer lie about the build — fail
    # the CI job instead of shipping a mislabelled exe.
    if _run_version_sync() != 0:
        sys.exit("version-sync: pubspec != kAppVersion (see scripts/version_sync_check.py)")
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
            ('window.Create(L"order_flow"', f'window.Create(L"Order Flow {version}"'),
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

    # Brand icon: replace the flutter default app_icon.ico with the shop's
    # launcher icon (same artwork as the APK) committed at
    # scripts/windows/app_icon.ico (multi-size PNG frames packed into ICO).
    ico_src = SCRIPTS_DIR / "windows" / "app_icon.ico"
    ico_dst = RUNNER / "resources" / "app_icon.ico"
    if not ico_src.exists():
        sys.exit(f"patch_windows_runner: missing brand icon {ico_src}")
    ico_dst.parent.mkdir(parents=True, exist_ok=True)
    ico_dst.write_bytes(ico_src.read_bytes())
    print(f"patch_windows_runner: brand icon installed ({ico_src.stat().st_size} bytes)")

    # permission_handler_windows compiles with the deprecated /await
    # coroutine headers, which MSVC 14.51 turns into a hard error
    # (STL1011). Silence it at the top-level windows/CMakeLists.txt BEFORE
    # add_subdirectory()/include() so all plugin targets inherit the define.
    top_cmake = ROOT / "windows" / "CMakeLists.txt"
    DEFINE = "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS"
    if top_cmake.exists():
        text = top_cmake.read_text(encoding="utf-8")
        if DEFINE in text:
            print(f"patch_windows_runner: {DEFINE} already present")
        elif "LANGUAGES CXX)\n" in text:
            text = text.replace(
                "LANGUAGES CXX)\n",
                "LANGUAGES CXX)\n\n"
                "# permission_handler_windows uses deprecated /await coroutines —\n"
                "# MSVC (STL1011) hard-errors unless silenced.\n"
                f"add_compile_definitions({DEFINE})\n",
                1,
            )
            top_cmake.write_text(text, encoding="utf-8")
            print(f"patch_windows_runner: injected {DEFINE}")
        else:
            print("patch_windows_runner: project() anchor not found — "
                  "coroutine define NOT injected (build may fail with STL1011)")


if __name__ == "__main__":
    main()
