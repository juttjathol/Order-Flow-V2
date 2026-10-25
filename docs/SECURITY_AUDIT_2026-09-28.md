# Order Flow — security & feature audit (2026-09-28)

Auditor: Arena agent session `arena/01a0e268-order-flow-v2`
Scope: everything in this repo — Cloudflare Pages Functions (license API, cloud relay,
download proxy), the SaaS admin dashboard front end, the Flutter POS app (LAN server,
license service, cloud relay client, bundled web assets), Android/Windows packaging,
CI workflows, and the public website.

**Method & honest limits.** This sandbox has no Flutter/Dart SDK and no Android/Windows
device, so nothing here was verified by *running* the app. Evidence is static source
review plus machine-checkable contracts (feature-key sets, version lockstep, l10n parity,
asset existence, JS syntax, live HTTP checks of the deployed site). Anything marked
**needs device test** at the end must be smoke-tested on a real build before it is
trusted in a shop.

---

## 1. Summary

| ID | Severity | Component | Finding | Status |
|----|----------|-----------|---------|--------|
| S-01 | **High** | `flutter_app/assets/web/index.html` | Stored XSS: every store value was interpolated into `innerHTML` unescaped (dish/category/staff/driver/table names, ticket numbers, currency symbol, base64 images). The console holds `OF_TOKEN`, so one poisoned dish name = create orders, mark them paid, rewrite prices, change the shop profile. | **Fixed** (staged, needs build) |
| S-02 | **High** | `lan_server.dart` `/state`, WS `hello`/`state` | The manager PIN (`profile.managerPin`) was sent to **every** LAN client, including the unauthenticated browser console. A legacy plaintext PIN was handed over verbatim; a hashed one is a single round of SHA-256 over a 4–6 digit PIN = milliseconds of offline brute force. | **Fixed for the web console** (staged, needs build). Stations still receive it by design — see S-03. |
| S-03 | **High** | `lan_server.dart` `_dashboard` + `core/pin_crypto.dart` | The owner web console at `http://<main-ip>:8787/` embeds a valid token in its HTML for **anyone on the shop Wi-Fi**, with no pairing and no server-side PIN. That client may run `kWebCommands`: `createOrder`, `addLine`, `setOrderStatus` (incl. `paid`), `setProfile`, `upsertProduct`, `setModel`. Its `needPin()` also returns `true` immediately when the PIN is hashed, and it is client-side only. | **Needs owner decision** — see §5 roadmap (opt-in console lock + server-side PIN). Not silently changed, because locking the console would break a working feature for existing shops. |
| S-04 | **High** | `core/lan_policy.dart` `corsOriginOk` | DNS-rebinding: the check was `origin == 'http://$host'`, and both values come from the same request. An attacker page whose domain resolves to the Main device's LAN IP passes the check, then reads the whole store and issues web commands with the token from `/`. | **Fixed** (staged, needs build): browser callers must address Main by IP literal / `localhost`. Native apps (no `Origin`) unaffected. Regression tests added. |
| S-05 | Medium | `lan_server.dart` `_qrSubmit` | QR flood control was broken two ways: the "per IP" bucket keyed on the client-controlled `x-real-ip` header (trivially rotated), and its fallback was `req.requestedUri.host` — **the server's own address** — so every guest shared one 60-orders/hour bucket and QR ordering locked the whole shop out mid-service. Takeaway-only shops were worse: no table id collapsed them into a single 12/hour bucket. | **Fixed** (staged, needs build): per-table 24/h for seated service, no per-table cap for takeaway/queue shops, one shop-wide 900/h flood cap. Spoofable header no longer used. |
| S-06 | Medium | `lan_server.dart` `_driverStatus` | Any authenticated client could call `pairDriver` (only the `multi_terminal` plan was checked), and a paired driver could flip **another** driver's status because `deviceId` came from the request body. | **Fixed** (staged, needs build): `pairDriver` requires role `main`/`manager`; `setDriverStatus` forces the caller's own device id. |
| S-07 | Medium | `lan_server.dart` `_onWs`, `_deviceAllowed` | No ceilings: unbounded websocket set, unbounded `pending`/`_waiting` maps, no frame-size limit on the WS path (`/command` caps at 32 KB, WS capped nothing), and every unknown `hello` fired an approval notification on Main → memory exhaustion + notification spam from one laptop on the Wi-Fi. | **Fixed** (staged, needs build): 64 sockets, 24 waiting, 64 KB frame cap. |
| S-08 | Medium | `functions/api/cloud/[[path]].js` | Relay write access was **room-id-only**: `/send` did not check membership, so a leaked room id (or an ex-station) could inject or flood ciphertext — and because the room keeps only the newest N rows, flooding could evict real orders before stations pulled them. `/pull` had no per-device rate limit at all. | **Fixed** (live): `/send` now requires a `cloud_devices` row for that room+device; per-device send/pull throttles added; row cap 400 → 200. Backward compatible — every shipped client joins before it sends. |
| S-09 | Medium | `functions/api/[[path]].js` | Broadcast links were stored and served unvalidated, and the app opens them. A `javascript:` / `file:` / `content:` / `intent:` URL created by any admin session (or a stolen one) would be an injection primitive into every installed Main. | **Fixed** (live): `https://` only, max 500 chars, control characters stripped, title/message capped, tag allowlisted; the public feed also re-filters legacy rows. |
| S-10 | Low | `lan_server.dart` `_clientFromReq` | LAN bearer token compared with `!=` (timing). | **Fixed** (staged): `safeEq` constant-time compare. |
| S-11 | Low | `functions/api/cloud/[[path]].js` | `pruneIdleRooms()` ran three correlated subqueries on **every** relay request; `/open` and `/join` had only per-isolate in-memory throttles (reset whenever an isolate dies). | **Fixed** (live): sweep at most once per isolate per 10 min; D1-backed limits on open/join; joiner identity strings bounded. |
| S-12 | Low | `functions/api/[[path]].js` | `pruneLicenseEvents()` ran a full-table `DELETE` scan inside **every** `validate` call (one per device every ~5 min). | **Fixed** (live): once per isolate per 6 h, identical 90-day retention, a large slice of D1 quota back. |
| S-13 | Low | `.github/workflows/build-release.yml` | The release workflow only builds — it never runs `flutter analyze` or `flutter test`, and no `arena/**` workflow exists. All 7 test files (including `l10n_parity_test.dart`, written specifically to stop the two silent-breakage classes) have **never run in CI**. That is how S-14 shipped. | **Needs owner decision** — `.github/workflows` is off-limits by standing directive. See §5. |
| S-14 | Low (UX) | `core/l10n.dart` | 12 keys existed only in English (`role_manager`, `role_manager_hint`, `inventory_cards`, `order_cards`, `kot_age`, `save_customer`, `test_kitchen`, `test_receipt`, `last_print`, `complimentary`, `extend_ok`, `lock_now`). Urdu shops saw English leaking into the role picker, payment methods and printer tests. The parity test missed them because `role_manager` is reached via `t('role_${r.name}')`, not a literal. | **Fixed** (staged, needs build): EN 714 / UR 714, zero diff, verified by script. |
| S-15 | Info | `AndroidManifest.xml` | `<data android:scheme="orderflow" android:host="join"/>` is declared and exported, but nothing in the app consumes an incoming link (no `app_links`/`uni_links`, no intent handling in `MainActivity.kt`). Tapping a join link opens the app and does nothing — the QR flow works only because the app scans and parses the text itself. | **Reported**, not changed (dead-but-harmless; implementing the handler is a feature). |
| S-16 | Info | `network_security_config.xml` | `base-config cleartextTrafficPermitted="true"` applies globally, not just to the LAN domain rules below it. Accepted risk (LAN POS is plaintext by design), but the base config could be tightened to `false` with the private-range `domain-config` left open. | **Reported**, not changed — tightening it risks breaking a shop's LAN traffic without a device to test on. |
| S-17 | Info | `license_service.dart` | Signature check is opportunistic: `kLicenseRequireSig = false`, and a response with the `signature` field stripped skips verification entirely (downgrade). Correct for deployments without `LICENSE_SIGNING_KEY`, but it means the Ed25519 layer is advisory until the flag is flipped. | **Accepted** by standing directive ("don't flip `kLicenseRequireSig`"). |

---

## 2. What was already solid (verified, not assumed)

* **Feature-key contract is consistent across all three codebases** — `kFeatureCatalog`
  (app), `FEATURE_KEYS`/`CORE_FEATURE_KEYS` (license worker) and `FEATURES` (dashboard
  editor) are the *same 15 keys in the same order*; `MODEL_KEYS` matches the dashboard's
  `MODELS` (restaurant / retail / fastfood / services). This is exactly the contract that
  broke in v1.1.82, so it is now machine-checked in this audit.
* **Version lockstep** — `pubspec.yaml` `1.1.82+82`, `kAppVersion` `1.1.82`, all three
  `FALLBACK_TAG` copies `v1.1.82`; `scripts/version_sync_check.py` passes.
* **Admin dashboard front end** — every `innerHTML` interpolation goes through `esc()`;
  token in `sessionStorage` with a one-time `localStorage` migration; strict CSP
  (`script-src 'self'`, `frame-ancestors 'none'`), `X-Frame-Options: DENY`, HSTS,
  `noindex`, `Permissions-Policy` locked down.
* **License API** — PBKDF2 clamped to 100 000 iterations, constant-time compares,
  HMAC session tokens keyed only by `ADMIN_SECRET`, per-IP D1 rate limits on
  `validate`/`login`, input length caps, `bound_device_id` never echoed back,
  DB errors mapped to support-safe codes, `not_found` logging throttled, 90-day event
  retention, CORS off unless the origin is explicitly allowlisted, `ipOf` trusts only
  `cf-connecting-ip`.
* **Cloud relay design** — room ids are 256-bit random with no list/query endpoint;
  payloads are AES-GCM end-to-end (the server only ever sees ciphertext); rows are
  deleted once every device has read past them, hard-expire in ~30 min, and the room is
  wiped on close; idle rooms are swept after 24 h; `diag` requires `DIAG_TOKEN`.
  Nothing is a backup, as documented.
* **Guest QR page** (`assets/web/order.html`) — already escapes everything
  (`escapeHtml`), prices are computed **server-side** from the store (a guest cannot
  post their own price), qty clamped 1–99, 40 lines / 12 mods / 16 KB body caps,
  `sanitizeText` on names and notes, closed when the shift is closed or the plan lacks
  `qr_ordering`.
* **Download proxy** — skips draft/prerelease/`-rcN`, requires the exact asset name
  `app-release.apk`, per-IP burst limits, 45 s meta cache, errors logged server-side only.
  It already supports `GITHUB_TOKEN` (relevant to §6).
* **Android packaging** — `allowBackup="false"`, ML Kit declared barcode-only,
  analytics ADID collection disabled, service not exported.
* **Third-party disclosure** — `open.er-api.com` (currency) and `cdn.jsdelivr.net`
  (three.js) are both named in the privacy policy; no IP-geolocation third party remains.
* **Live deployment checks** — `https://jathol.org/guide.html` serves the v1.1.82 banner;
  `https://jathol.org/download?meta=1` reports `v1.1.82`; release `v1.1.82` is *Latest*
  with `app-release.apk` (117.2 MB) and `order-flow-windows.zip` (18.1 MB).

---

## 3. Changes made in this audit

### Live now (deploy from `main`, no build required)

* `cloudflare_dashboard/functions/api/cloud/[[path]].js` — S-08, S-11.
* `cloudflare_dashboard/functions/api/[[path]].js` — S-09, S-12 (+ `publicLicense` no
  longer computes `accessOf()` twice).
* All JS re-checked with `node --check`; `scripts/check-imports.mjs` still passes.

### Staged on the arena branch (needs an APK + Windows build to reach shops)

* `flutter_app/assets/web/index.html` — S-01 (new `esc()` helper; every interpolation
  escaped, including base64 image data and ids inside `onclick` attributes).
  The bundled `<script>` block passes `node --check`.
* `flutter_app/lib/services/lan_server.dart` — S-02, S-05, S-06, S-07, S-10.
* `flutter_app/lib/core/lan_policy.dart` — S-04 (`authorityIsIpLiteral`).
* `flutter_app/lib/core/l10n.dart` — S-14 (12 Urdu strings).
* `flutter_app/test/security_hardening_test.dart` — 2 new tests: DNS-rebinding rejection
  and `authorityIsIpLiteral` coverage (10 tests in the file now). The 5 pre-existing
  `corsOriginOk` assertions still hold unchanged.

Backward compatibility: nothing above changes a protocol field, a stored schema, or a
command name. Old APKs talking to a new Main keep working (they receive the same store
JSON; only the browser console's copy loses `managerPin`). New APKs talking to an old
Main are unaffected. The relay's membership rule matches what every shipped client
already does (Main is inserted by `/open`, stations by `/join`).

---

## 4. Housekeeping

Done (standing rule 5 — verification scratch tags, no releases attached, no effect on
any app or the website; the download proxy skips `-rcN` by design):

* deleted remote tags `v1.1.76-rc1`, `v1.1.76-rc2`, `v1.1.76-rc3`, `v1.1.76-rc4`.

Proposed, **not** done (each needs your OK — nothing here is safe to assume):

| Item | Why it is a candidate | Risk if removed |
|------|----------------------|-----------------|
| tag `main` → `6c11968` | A tag with the same name as the default branch. It already bit this session: `git fetch origin main:main` resolved the *tag*, was rejected as non-fast-forward, and made `git rev-parse main` ambiguous. | None known (workflows trigger on `v*` only; Pages uses branches), but its purpose is undocumented — that is why it was not deleted. |
| tag `arena/01a01f91-order-flow-v2` | A tag shaped like a branch name — almost certainly an accidental `git tag`. | None known. |
| 7 stale remote branches (`arena/01a01842…`, `arena/01a01f91…`, `arena/01a067e1…`, `arena/01a06851…`, `arena/01a06fe3…`, `arena/01a0d3b9…`, `backup/pre-audit-143f23b`) | All merged or superseded; they clutter the branch list and keep old Cloudflare Pages preview deployments alive. | Standing rule 2 forbids deleting branches without asking. `backup/pre-audit-143f23b` looks deliberate — keep it unless you say otherwise. |
| `ci_logs.txt` (0 bytes, tracked) | Empty scratch file at the repo root. | None. |
| `scripts/github/build-release.yml` | A copy of the workflow kept for the old "create the file by hand" flow; the new README no longer references it. | Keep if you still onboard a fresh fork by hand. |
| root `functions/` vs `website/functions/` vs `cloudflare_dashboard/functions/download.js` | Three identical copies of the download proxy by design (three Pages projects). | **Do not remove** — each copy is deployed by a different project. Left untouched. |

Not touched at all: `.github/workflows/*` (standing directive), anything under
`website/public/` that the live site serves, the three download-proxy copies, and all
release tags/assets.

---

## 5. Roadmap — the two things that need your decision

1. **Owner web console lock (S-03).** Recommended design, opt-in so no shop breaks:
   a `webConsoleLock` flag in settings (default **off** = today's behaviour). When on,
   `/` stops embedding `OF_TOKEN` and instead shows a 6-digit challenge that Main
   displays under *More → Web console*; the browser POSTs it once and gets a
   short-lived token. Needs a settings toggle, a Main-side sheet, 4–6 new l10n keys
   (EN + UR) and one new LAN route — a real feature, so it waits for your go-ahead.
2. **Server-side manager PIN (S-02/S-03 completion).** Commands that need manager
   authority (`voidOrder`, `refundOrder`, `closeDay`, `setProfile`, `upsertProduct`)
   accept an optional `pin`; Main verifies it with `PinCrypto` before applying. Absent
   `pin` → allowed (old APKs keep working) unless a new `pinStrict` flag is on. Then
   `managerPin` can be redacted for *stations* too, and `PinCrypto` can move from a
   single SHA-256 round to PBKDF2/HMAC-SHA256 (~100 k iterations) with transparent
   re-hash on the next successful verify — the same migration pattern already used for
   plaintext PINs.
3. **CI that runs the tests (S-13).** One workflow with `flutter analyze` + `flutter test`
   on pushes to `main` and `arena/**` would have caught S-14 and would catch every future
   l10n/reducer drift. Blocked only by your "don't touch `.github/workflows`" directive —
   say the word and it is a 30-line file.

---

## 6. Needs a device test before you trust it in a shop

Static review cannot prove runtime behaviour. After the next build, smoke-test:

1. **Browser console** on the LAN: `http://<main-ip>:8787/` loads, shows live orders,
   can create/pay a ticket, and `store.profile.managerPin` is now an empty string in the
   `/state` response (DevTools → Network).
2. **DNS-rebinding guard**: open the console by IP (must work) and, if you ever use a
   hostname/mDNS name for Main, confirm you do not need to (browsers will now be refused).
3. **Stations**: pair a phone as cashier/kitchen/driver; confirm the PIN prompt still
   appears for void/refund/close-day (stations still receive the hash) and that state
   sync is unchanged.
4. **QR ordering**: guest page on the shop Wi-Fi, submit a dine-in order (table required)
   and a takeaway order in a shop with no tables — neither may hit a rate limit at 13 or
   61 orders any more; 25+ orders on one table in an hour must still be refused.
5. **Drivers**: a paired driver flips only its own status; a cashier station can no longer
   pair a driver.
6. **Urdu UI**: switch the app to Urdu and check the role picker (Manager + its hint),
   payment methods (Complimentary), printer test buttons, "In kitchen", "Save to book".
7. **Cloud networking** (Custom plan): Main opens a room, a station joins by code on
   mobile data with the Wi-Fi off, an order reaches Main; then confirm a station that left
   the room can no longer post to it (`not_member`).
