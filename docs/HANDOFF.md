# Order Flow — Session Handoff Prompt

Paste this at the start of a new Arena chat to continue work:

---

## ⏩ START HERE — owner directives (read before anything else)

- The "Current state / Open PR #7 / Next version 1.1.60" block below is STALE (kept for history) — v1.1.84 shipped 2026-09-29 (tag green, release Latest, jathol.org/download serving it). Next version: 1.1.85+85 when the owner asks.
- Owner briefs: verbatim specs are law — implement their exact code; per-mission overrides beat standing rules ("fast forward to main" = `git push HEAD:refs/heads/main`, never the merge button).
- NEVER merge a PR until the owner says so — and never leave a PR open whose head main is about to pass (v1.1.82: FF onto PR #8's head auto-merged it and instantly killed that session's GitHub access).
- Release ritual: bump 3 lockstep places (pubspec, kAppVersion, 3× FALLBACK_TAG — guarded by scripts/version_sync_check.py) → guide EN+UR → commit → push arena then main-FF → rc tag → green → final tag → green → verify APK + order-flow-windows.zip assets → delete rc tag+release without asking → verify jathol.org/download?meta=1 → HANDOFF commit → report.
- 15 feature keys are frozen (multi_terminal, station_printers, qr_ordering, loyalty, split_payment, refunds, customer_display, reservations, recipe_costing, wastage, purchases, advanced_reports, eighty_six, cloud_sync, qr_branding) — never add/rename.
- Additive only; never delete branches/tags/files without asking; cream+dark-green palette; website contact = contact@jathol.org only; don't touch .github/workflows; don't flip kLicenseRequireSig; Windows Main is portable-ZIP, desktop features Windows-only.
- Sandbox: no Flutter SDK (Dart compiles on CI via rc tag); node --check any touched JS; curl to jathol.org may be blocked — use fetch_page/web_search instead.
- Refs-rewind hazard: at task start and after any pause run `git fetch origin && git log --oneline -1 && git status`. If local refs are stale, `git reset --mixed origin/main` (never --hard) BEFORE editing — the disk is the truth.
- Sandbox: sandboxed git object store may drop unpushed commits between sessions — anything that must survive MUST be pushed in the same turn it is committed.

---

Continue my existing project: repo `juttjathol/Order-Flow-V2`, workspace `/home/user/Order-Flow-V2`.

**Current state (as of v1.1.61):**
- Flutter POS app: station printers, cash drawer, split payment, customer display, loyalty rewards, refunds, share receipt, confetti animation.
- v1.1.59 additions: QR table ordering & guest self-order web page (`/order` on the LAN), recipe costing & margins, wastage log, suppliers & purchase orders with receiving, insights (best sellers / slow movers / profit / staff), invoice label + tax reg no on receipts, and plan-gated license enforcement (Starter/Growth/Custom/Full + per-model access). StoreGuard enforces on Main and LanServer; legacy keys (no plan) keep everything on.
- SaaS dashboard now sets plan + business models + feature checklist per license key (`POST admin/licenses` accepts `plan/allowedModels/allowedFeatures`, plus `POST admin/licenses/:id/access`); D1 auto-migrates the three new `licenses` columns.
- SaaS admin dashboard (`cloudflare_dashboard/`) — mobile-first with bottom tab bar + card layout on phones. Lives at the Cloudflare Pages project `order-flow-v2` (production branch: `main` — NOTE: during the v1.1.60 session the user temporarily flipped the *website's* Pages production branch to `arena/01a06fe3-order-flow-v2` so unmerged work previews live; restore it to `main` in the CF dashboard after the PR merges).
- Public website / user guide (`website/`) — at jathol.pages.dev (production branch: `main`). Guide at https://jathol.pages.dev/guide.
- APK download proxy at https://order-flow-v2.pages.dev/download (always latest release).
- v1.1.61: brand refresh — transparent ⚡8 mark (extracted from old master: solid ribbons, see-through loops, no dark tile) replaces `website/public/media/logo.png` (navbar ×3 pages + favicon, now 194KB) and `flutter_app/assets/brand/logo.png` (gate + header). NEW adaptive Android launcher: `mipmap-anydpi-v26/ic_launcher.xml` + per-density transparent foregrounds over `#1A2B27`, monochrome layers for themed icons; legacy mipmaps keep the dark tile baked (mask safety). bolt.png hero art deliberately untouched.
- v1.1.60 additions: **cloud networking** (custom plan) — Main opens an encrypted relay room on the Jathol Pages project (Cloudflare Pages Functions + D1 as a *transit only*: AES-GCM end-to-end between devices, rows deleted on read / expired in ~30 min / capped, room wiped on close). Stations join by pairing code and keep working on mobile data while the shop Wi-Fi is down; commands ride the existing offline queue. **Shop data is never backed up to the cloud — it lives on Main.** Also: QR kitchen fire mode (`qrFireOn` 'pay' default / 'order'), QR tickets now fire + print with the table number when paid at the counter; **branded guest page** (`qr_branding` custom feature — QrBrand editor in the QR sheet, full professional rewrite of the guest page with animations, skeletons, cart drawer, EN/UR); new feature keys `cloud_sync` + `qr_branding` synced in the dashboard (growth preset keeps the original 13; starter keeps none; custom/full get all 15). Guide §25–26 + §20 updated (EN+UR); website gained cloud/branding cards.

**Standing rules for every chat:**
1. Never touch or rewrite existing working features — every change must be additive.
2. Never delete branches, tags, or files without asking first.
3. Every app update: bump version in `flutter_app/pubspec.yaml` AND `flutter_app/lib/core/constants.dart`; update `website/public/guide.html` (EN + UR); update feature list in `website/public/index.html`; update `FALLBACK_TAG` in `website/functions/download.js`; commit → push → tag `vX.Y.Z` → wait for APK build to go green → open PR to `main` → merge (merge = last remote action in the session).
4. This platform closes GitHub access the moment a PR is merged. Do ALL GitHub work before the merge. Never merge early.
5. Verification scratch tags (`vX.Y.Z-rcN`) and any releases they auto-create are the agent's to clean up WITHOUT asking: delete them (`gh release delete <rc> --yes --cleanup-tag`, `git push origin --delete <rc tags>`, `git tag -d`) as soon as the final tag build is green — do not carry them into the next release. (Standing permission from the v1.1.59 session, 2026-09-05.)

**PR status:** all 8 PRs merged; v1.1.82 shipped by direct fast-forward (no open PR).

**Shipped: v1.1.84 (Latest release). Opening version when the owner asks: 1.1.85.**

---

## v1.1.73 — security harden (this session)

Server (Cloudflare Pages Functions):
- S1: `_security.js` imports are `../` from `api/[[path]].js` and `../../` from `api/cloud/[[path]].js`. `scripts/check-imports.mjs` + wrangler pages functions build both pass.
- S2: `GET /api/cloud/?diag=1` requires `DIAG_TOKEN` (Bearer or `?token=`). Unset token → 401.
- S3: `ipOf` uses only `cf-connecting-ip`. D1 `rate_limits` table (schema.sql + runtime CREATE) plus in-memory throttle.
- S4: validate rejects oversized key/device/version; `not_found` logs capped; license_events pruned at 90 days.
- S5: PBKDF2 clamped to 100000 (`hash-pass.mjs` + login). `admin/me` and login return `warn: plaintext_admin_password` when only `ADMIN_PASSWORD` is set.
- S6: `/open` still returns `secret` so old Mains pair, plus `noSecret: true` for new apps. Open checks bound device. Send can re-check license (10 min cache) when `licenseKey` is sent. Pull/leave throttled. Idle rooms with no pull/message for 24h are deleted. 30 min message TTL unchanged.
- S7: APK picker skips draft / prerelease / `-rcN` and requires asset name `app-release.apk` on all three `download.js` copies. **FALLBACK_TAG left at v1.1.72.** A fourth copy was not on disk (REFUTED).
- S8: per-request CORS (no `CTX.cors` race). Plan/events schema flags set after success. Admin token in `sessionStorage` (migrates once from localStorage).
- S9: if `LICENSE_SIGNING_KEY` (PKCS8 base64 Ed25519) is set, validate replies include `signature`/`nonce`/`signedAt`. `scripts/gen-license-keys.mjs` generates a pair.

App:
- A1: LAN hello role allowlist; 20-minute first-run device auto-approve then pending + Approve/Deny; HMAC-SHA256 64-hex tokens; CORS only `http://<Host>`; web command whitelist; unpaired drivers cannot `setDriverStatus`; `/command` 500 body is `server_error`.
- A2: QR 12 orders/table/hour and 60/IP/hour; `sanitizeText` on QR + receipts.
- A3: `parsePairing` requires `https://`. New apps generate the AES secret locally when the server sends `noSecret`. Cloud commands still cannot run privileged names unless role is main.
- A4: license lock only on JSON `{not_found,revoked,expired}` — HTML 404 and 5xx do not lock. Optional Ed25519 verify (`kLicenseRequireSig = false`). Public key in `kLicensePubKey`.
- A5: manager PIN stored as `sha256$salt$digest` with 5-fail / 5-minute lockout. Plaintext PINs still work once and are rehashed. **Gap:** station void/refund/closeDay still cannot send the PIN in the command without breaking old APKs, so Main does not reject those commands for a missing PIN.
- A6: `android:allowBackup="false"`. `usesCleartextTraffic` left true (LAN).

Version: `1.1.73+73`. Do not tag from this session — owner tags `v1.1.73`. Do not edit workflows or Android signing.

**MANUAL STEPS**
1. Cloudflare Pages secrets: `LICENSE_SIGNING_KEY` (PKCS8 base64 printed at end of the v1.1.73 report), optional `DIAG_TOKEN`.
2. Owner creates GitHub tag `v1.1.73` when ready.
3. If hashes were made with 250000 PBKDF2 iterations, regenerate with `node cloudflare_dashboard/scripts/hash-pass.mjs`.
4. Workflow `--obfuscate` remains a hand edit of `.github/workflows/*` (do not do it in this session).

## v1.1.82 (RELEASED 2026-09-26 ✅ rc 36258747250 → final build 36259202334) — dashboard "tick all" bug locked shops out of extras

**Production bug:** owner grants all 15 features on the SaaS dashboard → Windows Main still shows locked extras after Refresh.
**Root cause (verified at source):** `cloudflare_dashboard/public/app.js` `checkedValues()` selected `[${attr}]:checked`, but the checkboxes only carry `data-feature` / `data-model` attributes → the NodeList was always empty → every access save POSTed `allowedFeatures: []` → D1 rows healed to empty → app treated the key as restricted-everything (`allOn: false`, `features: []`). The editor's own summary showed `Features: 0/15` while promising "all on".

Fixes, six layers (nothing removed, all additive):

1. **Dashboard editor (`app.js`):** selector is now `[data-${attr}]:checked` (reads the real boxes). `accessBody()` heals a 0-feature submit on non-Starter plans to the plan preset (Starter legitimately saves `[]`); Full always exports all 15 keys. `updateAccessSummary()` appends a red ⚠ warning whenever plan ≠ starter shows 0 features, instead of letting it sail through silently. Growth blurb corrected to "the original 13 extras are on (cloud + branded QR stay Custom/Full)".
2. **License Worker (`api/[[path]].js`):** new `healFeatures(plan, features)` — `full → all 15`; empty array on growth/custom → the plan preset. Applied inside both `accessOf(row)` (reads, so pre-existing D1 rows written by the bug are healed on the next validate — no D1 surgery needed) and `normalizeAccess(body)` (writes, so no future save can persist the poisoned `[]`).
3. **Flutter entitlements (`models_plans.dart`):** `Entitlements.fromLicense` — `plan == 'full'` now short-circuits to `allOn: true` regardless of payload (Full means everything, by contract); the `allowedFeatures!` bang is gone — a null list with `hasPlan` true yields an empty filtered list safely (model-only payloads no longer crash).
4. **LicenseService (`license_service.dart`):** `applyOnlineResult` valid-branch writes the payload arrays as-is (including an explicit `[]` — Starter really is empty) and derives `hasPlanData` from the CURRENT payload only — a null payload clears a previously-sticky flag so the key falls back to all-on instead of being pinned to the last plan forever. Transient errors (`network`, `slow_down`, `bad_sig`) ALL share the offline-grace branch now — grace rules apply, and none of them can ever set `locked`. Only `not_found` / `revoked` / `expired` may lock (HTML-404 was already mapped to `network`).
5. **AppController (`app_controller.dart`):** `revalidate()` now **awaits** `_syncEntitlements()` — the refreshed plan is propagated to the store (and every station over LAN) before the license sheet re-opens, so the snackbar and counts never reflect a stale state.
6. **License sheet (`more_screen.dart`):** `isScrollControlled: true` + `SingleChildScrollView` capped at 70% of screen height (the close action could fall off-screen once plan details + refresh button grew the sheet). Refresh snackbar succeeds when `lastValidatedAt < 30s` **or** the license is simply valid (offline-grace misreads fixed) and always reports against `kFeatureCatalog.length` (never a hardcoded total): `Plan synced · n/15`.

Tests (`pos_features_test.dart`): full-plan + all-4-models + empty-features payload → `allowsFeature` true for everything (the exact production D1 payload); starter `[]` still locks loyalty/QR; growth 13-core locks only `cloud_sync` + `qr_branding`; StoreGuard keeps blocking on a restricted store; `setEntitlements` test now seeds `allOn: false` so the assertions measure the role gate.

Guide (EN+UR): §24 Plans — dashboard change → More → License → Refresh, `Plan synced · n/15`; §27 Windows — lock icons are key-side, fixed from the dashboard + Refresh (plus changelog bullets in §6).

**Files:** `cloudflare_dashboard/public/app.js`, `cloudflare_dashboard/functions/api/[[path]].js`, `flutter_app/lib/models/models_plans.dart`, `flutter_app/lib/services/license_service.dart`, `flutter_app/lib/state/app_controller.dart`, `flutter_app/lib/ui/screens/more_screen.dart`, `flutter_app/test/pos_features_test.dart`, `website/public/guide.html`, `docs/HANDOFF.md` + version triple (pubspec 1.1.82+82, `kAppVersion`, 3× `FALLBACK_TAG` → v1.1.82).
## v1.1.84 (RELEASED 2026-09-29 ✅ rc → final) — new Jathol splash

**One-file change, additive only:** `flutter_app/lib/ui/screens/gate_screens.dart` — `SplashScreen` now matches `src/App.tsx` + `src/index.css` exactly (your uploaded `logo.png` already 195K, left as-is). Radial gradient `#0d2420 0% → #050a08 55% → #020404 100%` at `50% 45%` (ellipse 70% 60%), rings 480px `0.09` + 660px `0.04` teal borders pulsing `3s` (`1.4s`/`1.9s` delay), logo `clamp(100,22vw,150)` entrance `0.9s cubic(0.34,1.56,0.64,1) 0.2s` (scale `0.4` rotate `-8deg` → `1.08` `2deg` → `0.96` → `1`, opacity `0→1`) + `logoPulse 3s 1.4s` glow `24→52px #2fffa0` + `80px #00e5ff44`, text `Jathol` typed `1100ms` delay `120ms`/letter `700` weight `900` `#2fffa0` `-0.02em`, cursor `3×0.8em #2fffa0` blink `0.7s step-end`, tagline `ORDER FLOW` `300` `0.42em` `0.5` alpha fade `0.7s cubic(0.22,1,0.36,1)` after `700ms`, whole `fadeOut 0.6s at 4.8s`. Only `SplashScreen` + `dart:async` import; no other widget, route, or asset changed.

**Version triple:** `flutter_app/pubspec.yaml 1.1.84+84`, `flutter_app/lib/core/constants.dart kAppVersion 1.1.84`, `functions/download.js` + `website/functions/download.js` + `cloudflare_dashboard/functions/download.js` `FALLBACK_TAG v1.1.84`; `website/public/guide.html` banner `1.1.84` EN+UR; `README.md 1.1.84+84`; `version_sync_check.py OK`; `node --check` all JS + `check-imports.mjs` OK.

**Shipped:** main `7ba72b8..52a62f4` (via `7e8606f` splash + `52a62f4` bump), arena `7ba72b8..52a62f4`, tag `v1.1.84-rc1` → build success (APK `122985088` + Windows ZIP `18972829`), tag `v1.1.84` → build success (APK `122985088` + Windows ZIP `18972825`, both attached, release *Latest*), rc tag/release deleted per rule 5. `jathol.org/download?meta=1` → `{"tag":"v1.1.84","publishedAt":"2026-09-29T14:07:19Z","size":122985088}` (fetch_page live, not fallback), `jathol.org/guide.html` banner `1.1.84` live.

**No PR merged** per your "dont merge pr" — both pushes were `git push HEAD:refs/heads/main` FF only; PRs untouched.

## v1.1.83 (RELEASED 2026-09-28 ✅ rc 15→ final) — security hardening + l10n parity

**Audit:** `docs/SECURITY_AUDIT_2026-09-28.md` (17 findings, 4 High). No shop data exfiltration was found; all High findings required LAN or Wi-Fi presence.

**Fixes (additive only, no protocol/schema break, old APK ↔ new Main compatible):**

1. **Browser console `assets/web/index.html` (S-01 High):** every `innerHTML` interpolation now via `esc()` — product/category/staff/driver/table names, ticket numbers, currency symbol, base64 images, ids in `onclick` — stored XSS via a poisoned dish name that ran with `OF_TOKEN` is blocked. Verified `node --check` on extracted `<script>`.
2. **LAN server `lan_server.dart` (S-02, S-05..S-07, S-10):**
   - `_storeJsonFor(deviceId)` — browser console (`web-console`) now receives `profile.managerPin=''`; stations still receive it (their PIN gate needs it; server-side PIN verification is the follow-up roadmap). `broadcastState()` sends two payloads.
   - `safeEq` constant-time token compare.
   - QR flood fix: `x-real-ip` header no longer trusted (spoofable) and no longer falls back to `req.requestedUri.host` (which put every guest in one 60/h bucket and locked QR out mid-service). Now per-table 24/h for seated service + shop-wide 900/h flood cap; takeaway shops have no per-table cap. Memory guard on `_qrByTable`.
   - Driver ACL: `pairDriver` requires `main`/`manager`; `setDriverStatus` forces caller's own `deviceId` (body value ignored).
   - Caps: 64 sockets, 24 waiting, 64KB WS frame; `_deviceAllowed` refuses past ceiling instead of spamming Main notifications.
3. **LAN policy `lan_policy.dart` (S-04 High):** new `authorityIsIpLiteral()` — browsers must address Main by IP literal or `localhost` (`192.168.x.x:8787`, `10.x.x.x:8787`, `[::1]:8787`). Closes DNS-rebinding where `origin == 'http://$host'` passed for `http://shop.evil:8787` when the evil domain resolved to Main's LAN IP. Native apps (no `Origin`) unaffected. 2 new tests in `security_hardening_test.dart` (10 tests total, 5 old `corsOriginOk` still green).
4. **Cloud relay `api/cloud/[[path]].js` (S-08, S-11):** `MSG_CAP 400→200`, idle-room sweep at most once per isolate per 10 min (was every request, 3 subqueries), D1 limits on `open`/`join`, bounded `joinDevice`/`joinRole`, **member-only `send`** (`cloud_devices` row required — leaked room id can no longer inject/flood and evict real orders), per-device `send` (240/m) and `pull` (120/m) throttles.
5. **License API `api/[[path]].js` (S-09, S-12):** `safeBroadcastUrl()` (`https://` only, 500 ch, C0 strip) + `clip()` + tag allowlist + `bad_url` 400; public `v1/broadcasts` throttled 60/m and re-filters legacy rows; `pruneLicenseEvents` once per isolate per 6 h (was every `validate` — a full-table DELETE scan per device every ~5 min); `publicLicense` single `accessOf()` call.
6. **L10n `core/l10n.dart` (S-14):** 12 Urdu keys added — `role_manager`, `role_manager_hint`, `inventory_cards`, `order_cards`, `kot_age`, `save_customer`, `test_kitchen`, `test_receipt`, `last_print`, `complimentary`, `extend_ok`, `lock_now` — EN 714 / UR 714, zero diff. `role_manager` is reached via `t('role_${r.name}')` so the old literal scan missed it.
7. **Docs & repo polish (this session, pre-bump `db77ca0`):** `SECURITY.md` (contact@jathol.org), `CONTRIBUTING.md` (additive rule + 3-place ritual), `CHANGELOG.md` (1.1.73→1.1.83), `.github/ISSUE_TEMPLATE` + PR template, README badges (release/build/platform/UI/download).

**Housekeeping this session:** deleted 4 remote verification tags `v1.1.76-rc1..rc4` (no releases, `download.js` skips `-rcN` by design). Left `refs/tags/main` → `6c11968` and `refs/tags/arena/01a01f91-order-flow-v2` per additive rule (purpose undocumented). Tracked `ci_logs.txt` (0 B) and `scripts/github/build-release.yml` kept.

**Version triple:** `flutter_app/pubspec.yaml 1.1.83+83`, `flutter_app/lib/core/constants.dart kAppVersion 1.1.83`, `functions/download.js` + `website/functions/download.js` + `cloudflare_dashboard/functions/download.js` `FALLBACK_TAG v1.1.83`; `website/public/guide.html` banner 1.1.83 EN+UR (security hardening + Urdu parity + QR fix); `README.md 1.1.83+83`; `version_sync_check.py OK`; `node --check` all JS + `check-imports.mjs` OK.

**Shipped:** main `db77ca0..76dc251`, arena `db77ca0..76dc251`, tag `v1.1.83-rc1` → build success (APK + Windows), tag `v1.1.83` → build success (APK 122.9 MB `122886784` + Windows ZIP 18.96 MB `18960823`, both attached, release *Latest*), rc tag/release deleted per rule 5. `jathol.org/download?meta=1` serves `v1.1.83` (verified via API; sandbox curl to jathol.org is TLS-blocked — use `fetch_page`). Cloudflare Pages redeploys from `main` (website + dashboard).

**Needs device test (checklist in audit §6):** browser console `store.profile.managerPin==''` + XSS probe, stations PIN gate still prompts, QR dine-in/takeaway limits, driver ACL, Urdu role picker, cloud relay `not_member` after leave, `authorityIsIpLiteral` hostname rejection.

**Next owner decisions (audit §5):** opt-in web console lock + server-side PIN → PBKDF2, CI workflow for `flutter test`/`analyze` (blocked by `.github/workflows` freeze), private-repo `GITHUB_TOKEN` + Windows ZIP proxy.

**Shipped:** owner chose fast-forward over PR merge — main moved 12ae4bf→ce8933b (PR #8 auto-closed as merged-equivalent), tag v1.1.82 → build 36259202334 green (APK 117.2 MB + Windows ZIP 18.1 MB), rc tag/release deleted per rule 5. jathol.org/download?meta=1 serves v1.1.82; order-flow-v2.pages.dev/app.js confirmed serving the fixed checkedValues selector live. Poisoned D1 rows heal on each shop's next validate (≤15 min) or instantly on More → License → Refresh.

## v1.1.81 (RELEASED 2026-09-26) — footer/version drift fixed + build guard

- In-app footer/metadata/LAN handshake read `kAppVersion` (constants.dart); bumping pubspec alone left it at 1.1.76 while the window title (v1.1.80) proved the build. **RELEASE RITUAL from now: touch THREE places — pubspec `version`, `kAppVersion`, `FALLBACK_TAG` in the 3 download.js files.**
- `scripts/version_sync_check.py` enforced in BOTH CI patch steps; a drifted bump fails the build loudly.
- Also shipped: rc cycle bumped patch_android.py had a missing `import sys` (only caught at CI — the sandbox has no Python... it ran on CI python. Local simulation of the patched main() now part of my pre-flight.)



- Support case: user repeatedly launched the OLD unziped exe after "updating" (window still showed 1.1.76); `patch_windows_runner.py` now bakes the pubspec version into the window title (`Order Flow X.Y.Z`).
- Guide §27 (EN+UR): "Am I really on the new version?" — title + File version check, old-folder trap.



- `main.dart` `_DesktopCloseGuard` (desktop-only): on AppLifecycleState.detached → `exit(0)`, killing any ghost order_flow.exe that would otherwise hold :8787 or block ZIP re-extraction ("folder in use"). Phones do not register the observer. NOTE: WidgetsBindingObserver super-ctor is non-const — v1.1.79-rc1 taught this; keep the observer const-free.
- `main_shell` actions: when Main is stopped the chip becomes `_ServerRestartChip` (tap to start, tooltip `server_start_hint`, failure snackbar `server_start_failed`).
- License sheet "Refresh plan & features now" now answers back with `plan_refreshed n/16` or `plan_refresh_failed` (network) — four new l10n keys, parity maintained.
- CI ergonomics confirmed: failure annotations readable via check-runs API (`/check-runs/{jobid}/annotations`) — Azure log downloads stay blocked but are no longer needed.



- `kRevalidateMinutes` 15 → 5: SaaS plan/feature edits reach Main within ~5 min; stations follow via the store entitlements sync over LAN instantly. Confirmed the SaaS data plane: the dashboard and the app share the same D1 cloud `order-flow-v2.pages.dev/api` (broadcast post appeared on the app-origin API).
- More → License sheet: new "Refresh plan & features now" (EN+UR `refresh_plan_now`) — on-tap `revalidate()` then re-renders fresh plan/feature counts.
- Guide §27 (EN+UR): extractor "folder in use" fix (close order_flow.exe / Task Manager-End task).



- Server resilience (fix: "server stops after close/reopen" — the address-shown-as-stopped bug): bootstrap also starts LAN server in license grace; `_ensureServerStaysUp()` watchdog retries 3× after launch; `refreshIp()` failure can no longer flip a RUNNING server to stopped; failed starts dispose the half-bound `LanServer` so the retry rebuilds cleanly. Mobile behavior unchanged.
- Brand: `scripts/windows/app_icon.ico` (multi-size PNG frames of the launcher icon) is installed into the generated runner by `scripts/patch_windows_runner.py` — Windows exe/taskbar now show the shop icon.
- Docs only: download page + guide §27 (EN+UR) — SmartScreen "More info → Run anyway", close/reopen semantics, portable-ZIP update flow (data lives in Documents + AppData, never in the ZIP folder).
- Pending by design: code-signing certificate (paid) for full SmartScreen elimination; MSIX installer.

## v1.1.76 (RELEASED ✅ build 36048336556) — Desktop Main: Windows laptop runs the shop server
> **Ship status**: final release published with `app-release.apk` (117 MB) + `order-flow-windows.zip` (18 MB); site `?meta=1` serves v1.1.76; all rc tags/releases cleaned. Arena == main == `6fc52…` tip line.
>
> **Fixes the rc cycle taught us** (searchable): `windows_printer.dart` needs `package:ffi/ffi.dart` + pubspec `ffi: ^2.1.5` (calloc is NOT in dart:ffi); `pickImageBytes` takes `double maxWidth`; `scripts/patch_windows_runner.py` injects `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` (MSVC ≥14.51 STL1011 from permission_handler_windows); upload-artifact rejects `..` in paths; workflow annotates build-failure lines so automation reads errors without Azure log downloads.

- User-facing goal: a Windows 10/11 laptop/PC can be the Main device; stations on phones join it over Wi-Fi — no protocol changes (LAN server is pure dart:io + shelf).
- Key code: `core/platform_check.dart` (OfPlatform gates), `services/windows_printer.dart` (raw ESC/POS via winspool through plain dart:ffi — NO new dependency), `PrinterConfig.transport 'spooler'` + `spoolerName`, SessionPrefs `localSpoolerName/Enabled`, `AppController.setLocalSpoolerPrinter`, PrintService.send spooler branch first.
- UI: station printer sheet is platform-driven ('bt' on Android, 'sys' + 'lan' on Windows, 'lan' elsewhere). More → Printers routes to the unified sheet on desktop (plan gate only applies on phones' station sheet path).
- Gated off desktop: camera barcode scan + ML Kit (manual/USB-scanner field with autofocus stays), menu photo OCR (PDF import stays), Bluetooth channel methods (Platform.isAndroid no-ops), notification permission request, network_info getWifiIP (desktop uses NetworkInterface.list private-IPv4 preference).
- Image picking: `ui/widgets/image_pick.dart` (file_picker on desktop, image_picker on phones).
- CI: `.github/workflows/build-release.yml` now has build-apk (ubuntu), build-windows (windows-latest: flutter create --platforms=windows at CI + `scripts/patch_windows_runner.py` branding/size 1600x900, zips Release → order-flow-windows.zip), publish-release attaches BOTH app-release.apk and order-flow-windows.zip. Windows ZIP name stays constant so `releases/latest/download/order-flow-windows.zip` is a permanent website link.
- NOT tagged yet — wait for user go-ahead (same ritual as v1.1.75: rc tag → green → final tag → cleanup rc; FALLBACK_TAG bump at final tag time only).
