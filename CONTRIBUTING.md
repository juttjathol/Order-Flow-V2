# Contributing

Order Flow is a production POS: real shops trade on it every day, so the rules below
exist to keep a change from taking a till offline. They apply to everyone, including the
maintainers' own agents.

## The one rule that matters most

**Every change is additive.** Do not rewrite or "tidy" a working feature to make a new
one fit. If a fix genuinely requires changing behaviour that shops already rely on, say
so explicitly in the pull request description and wait for the owner's decision.

## Getting set up

```bash
git clone https://github.com/juttjathol/Order-Flow-V2.git
cd Order-Flow-V2/flutter_app
flutter pub get
flutter test          # 7 test files — see "Checks you must run"
flutter analyze
```

There is no local build service: the Android APK and the Windows ZIP are produced by
`.github/workflows/build-release.yml`, which runs only on a `v*` tag (or a manual
`workflow_dispatch`).

## What lives where

| Path | Deploys as | Notes |
|------|-----------|-------|
| `flutter_app/` | Android APK + Windows ZIP via a release tag | Main server + stations |
| `cloudflare_dashboard/` | Cloudflare Pages project `order-flow-v2` (branch `main`) | Admin dashboard + license API + cloud relay + download proxy |
| `website/` | Cloudflare Pages project for jathol.org (branch `main`) | Marketing site, user guide, download proxy copy |
| `functions/` | Third copy of the download proxy | **Keep all three `download.js` copies byte-identical** |
| `scripts/` | CI + release helpers | `version_sync_check.py`, `patch_android.py`, `patch_windows_runner.py` |
| `docs/` | Not deployed | `HANDOFF.md` is the session log; `SECURITY_AUDIT_*` are audit reports |

Pushing to `main` redeploys the dashboard and the website immediately. There is no
staging environment, so treat a `main` push as a release.

## Checks you must run before proposing a change

1. `flutter test` — in particular:
   * `l10n_parity_test.dart` — every `t('key')` literal resolves in **both** English and
     Urdu, dynamic key families are complete in both, and every `NetCommand` name the UI
     sends has a `case` in `reducer.dart` (an unhandled command is a silently dead
     button).
   * `security_hardening_test.dart` — LAN role allowlist, CORS/DNS-rebinding policy,
     privileged-command rules, PIN hashing, pairing-string validation.
   * `pos_features_test.dart` — plan/feature gating (Starter / Growth / Custom / Full).
   * `app_version_sync_test.dart` — the version triple is in lockstep.
2. `python3 scripts/version_sync_check.py` — passes only if `pubspec.yaml`,
   `kAppVersion` and all three `FALLBACK_TAG` copies agree.
3. `node --check` on every JavaScript file you touched, plus
   `node cloudflare_dashboard/scripts/check-imports.mjs` if you touched a Pages Function.
4. If you touched the download proxy: `diff` all three copies and confirm they are
   identical.

## Release ritual

The version lives in **three lockstep places** — bumping one and not the others produces
an app that reports the wrong version everywhere except the window title:

1. `flutter_app/pubspec.yaml` → `version: X.Y.Z+build`
2. `flutter_app/lib/core/constants.dart` → `kAppVersion`
3. `functions/download.js`, `website/functions/download.js`,
   `cloudflare_dashboard/functions/download.js` → `FALLBACK_TAG`

Then: update the user guide (`website/public/guide.html`, English **and** Urdu) and the
feature list on `website/public/index.html` → commit → push the working branch →
tag `vX.Y.Z-rc1` → wait for the build to go green → re-tag the final `vX.Y.Z` on the tip
→ confirm both `app-release.apk` and `order-flow-windows.zip` are attached and the
release is *Latest* → delete the `-rc` tags and any release they created → confirm
`https://jathol.org/download?meta=1` reports the new tag → write the session summary into
`docs/HANDOFF.md`.

Merging to `main` is the **last** action of a release and only ever happens on the
owner's explicit instruction.

## Conventions

* **Localisation parity is not optional.** Every user-facing string goes into both maps
  in `flutter_app/lib/core/l10n.dart` (`_en` and `_ur`). Urdu is a first-class UI, and
  the map is RTL-aware.
* **Palette**: cream + dark forest green (`OfColors`). Do not introduce a new accent.
* **Plans**: the 15 feature keys in `kFeatureCatalog` are frozen and must stay in sync
  with `FEATURE_KEYS` in the license worker and `FEATURES` in the dashboard editor. Add a
  key only with the owner's explicit approval — it changes what paid shops can do.
* **Contact**: the website uses `contact@jathol.org` only. No WhatsApp links on the site.
* Do not commit secrets, `.dev.vars`, keystores, or real license keys.

## Bugs and ideas

Use the issue templates. A good POS bug report says which **device role** saw it
(Main / cashier / kitchen / driver / station), the **business model** in use, the exact
**version**, and what the receipt or screen actually showed.

Security problems go to **contact@jathol.org**, not to a public issue — see
[SECURITY.md](SECURITY.md).
