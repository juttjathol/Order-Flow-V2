#!/usr/bin/env python3
"""Fail the build loudly when pubspec.yaml's version and kAppVersion
(lib/core/constants.dart) drift apart.

History: v1.1.76 shipped with pubspec=1.1.76 but kAppVersion stuck at an
older value — the in-app footer then mislabelled an otherwise-correct
build and support got confusing fast. This check runs inside the CI
patch steps (both APK and Windows jobs) so a version bump that forgets
one side can never reach a release.
"""

from __future__ import annotations

import pathlib
import re
import sys


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "flutter_app")
    pubspec = root / "pubspec.yaml"
    consts = root / "lib" / "core" / "constants.dart"
    m = re.search(r"^version:\s*([0-9.]+)", pubspec.read_text(), re.M)
    k = re.search(r"kAppVersion\s*=\s*'([0-9.]+)'", consts.read_text())
    if not m or not k:
        print("version-sync: unable to parse pubspec version or kAppVersion", file=sys.stderr)
        return 1
    if m.group(1) != k.group(1):
        print(
            f"version-sync: pubspec={m.group(1)} but kAppVersion={k.group(1)} — "
            "bump both in the same release",
            file=sys.stderr,
        )
        return 1
    print(f"version-sync OK ({m.group(1)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
