#!/usr/bin/env python3
"""
Sync docs & website version on every tag.
Usage: python3 scripts/sync_docs_version.py 1.1.87
Updates: pubspec, constants, FALLBACK_TAG, guide.html, README, PLAY_STORE, APP_STORE
"""
import sys, pathlib, re
ver = sys.argv[1] if len(sys.argv) > 1 else None
if not ver:
    print("usage: sync_docs_version.py <version> e.g. 1.1.87")
    sys.exit(1)
build = ver.split(".")[-1]
pairs = [
    ("flutter_app/pubspec.yaml", r"version:\s*[0-9.]+\+[0-9]+", f"version: {ver}+{build}"),
    ("flutter_app/lib/core/constants.dart", r"kAppVersion\s*=\s*'[^']+'", f"kAppVersion = '{ver}'"),
    ("functions/download.js", r"FALLBACK_TAG\s*=\s*\"[^\"]+\"", f'FALLBACK_TAG = "v{ver}"'),
    ("website/functions/download.js", r"FALLBACK_TAG\s*=\s*\"[^\"]+\"", f'FALLBACK_TAG = "v{ver}"'),
    ("cloudflare_dashboard/functions/download.js", r"FALLBACK_TAG\s*=\s*\"[^\"]+\"", f'FALLBACK_TAG = "v{ver}"'),
]
for rel, pat, repl in pairs:
    p = pathlib.Path(rel)
    if p.exists():
        t = p.read_text(encoding="utf-8")
        nt, n = re.subn(pat, repl, t)
        if n:
            p.write_text(nt, encoding="utf-8")
            print(f"updated {rel} -> {repl}")
# README and guide
for rel in ["README.md", "website/public/guide.html", "docs/PLAY_STORE.md", "docs/APP_STORE.md"]:
    p = pathlib.Path(rel)
    if p.exists():
        t = p.read_text(encoding="utf-8")
        # replace any 1.1.\d+ with ver
        nt = re.sub(r"1\.1\.\d+", ver, t)
        if nt != t:
            p.write_text(nt, encoding="utf-8")
            print(f"updated version in {rel}")
print("sync done for", ver)
