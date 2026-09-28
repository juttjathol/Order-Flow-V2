## What does this change?

<!-- One paragraph. Say which device role or surface sees the difference. -->

## Why

<!-- The shop problem, the bug report, or the audit finding (e.g. S-05 in
     docs/SECURITY_AUDIT_2026-09-28.md). -->

## Additive check

This project's first rule is that changes are additive. Confirm what existing behaviour
is untouched:

- [ ] No working feature was rewritten, renamed or removed to make this fit
- [ ] No branch, tag or file was deleted (if one was: it is named below and the owner approved it)
- [ ] Plan gating is unchanged, or the change is called out below (the 15 feature keys are frozen)
- [ ] The palette stays cream + dark forest green
- [ ] Website contact stays `contact@jathol.org` only

## Localisation

- [ ] Every new user-facing string is in **both** `_en` and `_ur` in `flutter_app/lib/core/l10n.dart`
- [ ] Dynamic key families (`role_*`, `duty_*`, `course_*`, `cloud_err_*`, `mod_*`) are complete in both
- [ ] `website/public/guide.html` updated in English **and** Urdu, if a shop would need to read about this

## Checks run

- [ ] `flutter test` (all 7 files: l10n parity, reducer coverage, security hardening, POS features, money, menu parser, version sync)
- [ ] `flutter analyze` — no new warnings
- [ ] `python3 scripts/version_sync_check.py`
- [ ] `node --check` on every JS file touched
- [ ] `node cloudflare_dashboard/scripts/check-imports.mjs` (if a Pages Function changed)
- [ ] All three `download.js` copies are still byte-identical (if the download proxy changed)

## Release impact

- [ ] Version bumped in **all three** lockstep places (`pubspec.yaml`, `kAppVersion`, 3× `FALLBACK_TAG`)
- [ ] No version bump needed — docs/website/dashboard only
- [ ] Needs an APK + Windows build to reach shops (say so, and do **not** tag without the owner's go-ahead)
- [ ] Deploys to production on merge to `main` (dashboard / website) — call out anything a live shop could notice

## Device smoke test

<!-- What you actually ran, on what hardware. Static review is not a test. -->

| Role / surface | Build | Result |
| --- | --- | --- |
|  |  |  |

## Notes for the reviewer

<!-- Risks, mixed-version fleet effects (new APK ↔ old Main and vice versa),
     rollback plan, anything deliberately left for a follow-up. -->
