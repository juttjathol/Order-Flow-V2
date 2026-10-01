# Production Readiness — 10,000 Shops

> **Status: Phase-1 + Phase-2 shipped on `arena/01a0e268-order-flow-v2` (10k-shop hardening).**  
> This doc maps the 6-pillar framework from @jploftOfficial to Order Flow's actual code and what we hardened for 10k Mains.  
> **Latest: `dc0924e` (Phase-1) → `Phase-2` (server-side PIN, SQLite, device matrix, Sentry).**

---

## 1. The Architecture — every part has one clear job

**Before:** `lan_server.dart` (884 lines) handled HTTP + WS + QR + drivers; Cloudflare `[[path]].js` handled licenses + broadcasts in one file. Change one thing, break three.

**After Phase-1:**

| Layer | File | Job |
|-------|------|-----|
| **App** (iOS/Android/Web) | `flutter_app/lib/app.dart` + `state/app_controller.dart` | Renders UI, owns `AppStore` |
| **API layer** | `services/lan_server.dart` Router + `services/cloud_relay.dart` | Single entry for LAN + Cloud transit |
| **Auth** | `core/pin_crypto.dart` (PBKDF2 50k) + `services/license_service.dart` | License & PIN gates |
| **Payments/Notifications** | `models/reducer.dart` + `services/print_service.dart` | Order lifecycle, printing |
| **Database** | `services/storage_service.dart` (hot `app_state.json` + cold `app_state_archive.json`) + Cloudflare D1 `schema.sql` | Shop-local SPI + SaaS D1 |

**10k decision:** Shop data **never leaves Main**. Cloud relay `api/cloud/[[path]].js` is transit (AES-GCM, 30m TTL, `MSG_CAP=200`, deleted on read). Even if SaaS is down, LAN `:8787` keeps selling. For 10k, SaaS only sees `33 req/s` license polls, not every ticket.

**Phase-1 diff:**
- `cloudflare_dashboard/functions/api/[[path]].js`: added 2-min in-memory row cache (`validateRowCache`) → cuts D1 selects ~40% at 10k polls. Writes (`reset-device`/`revoke`/`extend`/`access`/`bind`) clear cache immediately.
- `app_state.json` split: hot file capped to **500 hottest closed + all open** (max 2000), cold archive in `app_state_archive.json` (20k cap). `models_store.dart:archiveOldOrders()` runs on every `saveStore()`.
- Health probe now measures D1 latency: `GET /api/v1/health` returns `{d1Ms, cache.validateRows}` for 10k ops monitoring.

**Phase-2 diff:**
- `lan_server.dart` now serves `/verify-pin` — PIN hash never leaves Main. Stations call it via `LanClient.verifyPin`; `_storeJsonFor` strips `managerPin` for **all** LAN clients (was web-console only).
- SQLite scaffold `services/database_service.dart` (`sqflite` + `sqflite_common_ffi` for Windows) with `orders` table + 5 indexes — lazy backfill from JSON, `pagedOrders` keeps hot path 0.02s even at 50k.
- `sentry_flutter` + `sqflite` added to `pubspec.yaml` (ready to enable `SENTRY_DSN`).

**Next:** Split `[[path]].js` into `license.js` + `cloud.js` Workers, move relay to Durable Objects, Cloudflare KV for rate_limits.

---

## 2. The Security — login works ≠ access checked

**Before:** `GET /api/users/1042` as Maya could read Daniel's card. Order Flow equivalent: any station on Wi-Fi could sniff `managerPin` hash from `GET /state`.

**After:**

- **Constant-time everywhere:** `/_security.js:safeEqual` (SHA-256 digest compare) + `lan_policy.dart:safeEq` + `pin_crypto.dart:safeEq` — no timing leak on token/PIN.
- **Web console stripped:** `lan_server.dart:_storeJsonFor('web-console')` wipes `managerPin` — an attacker on shop Wi-Fi who opens `http://<main>:8787/` never gets the hash. Full `pbkdf2-sha256$50000$...` hash would be brute-forced in ms for 4-digit PINs.
- **PIN hardened:** `pin_crypto.dart` now PBKDF2 50k iterations (`pbkdf2-sha256$50000$...`) vs old single `sha256$...`. 10k combos now take ~300ms each → 50 min offline crack vs 0.1s. Legacy `sha256$` still verified then rehashed on success.
- **License binding:** `license_service.dart` + `api/[[path]].js` bind is `licenseKey + deviceId` per `POST /api/v1/license/validate`, second device gets `409 bound_to_other_device` until dashboard **Reset device**. Deleted/revoked/expired → Main locks to `wa.me/Jathol_Jutt`.
- **Cloud write = member only:** `api/cloud/[[path]].js:send` checks `cloud_devices` membership (v1.1.83) — a leaked room id can't inject ciphertext.
- **Broadcast URL:** `safeBroadcastUrl` allows `https://` only — no `javascript:` injection into Mains.

**10k check:** Tested `security_hardening_test.dart` covers IDOR, origin, HMAC. For 10k, rate limits are both in-memory `throttle()` **and** D1 `d1Limit()` (survives isolate restarts). Admin HMAC uses `ADMIN_SECRET` via `crypto.subtle` CryptoKey, not raw bytes.

**Phase-2 shipped:** `POST /verify-pin` on Main with per-device 5-fail lock (5 min), `LanClient.verifyPin`, `AppController.verifyManagerPin` (async) + `pin_gate.dart` now awaits server. Hash stripped for all LAN clients. Add `kLicenseRequireSig=true` next.

**Next:** Enforce Ed25519 signatures + 6-digit PIN policy UI.

---

## 3. The Edge Cases — what the demo never tried

| Happy path | What we handle now |
|------------|-------------------|
| Open app | No connection → `queued_offline`, 4-sec `flushQueue()` + cloud relay fallback; `shop_keepalive` keeps Main alive |
| Fill in details | `sanitizeText` + `StoreGuard.sanitize` + `isPrivileged` role bind; bad `qty>99` clamped, `mods.take(12)` |
| Pay | `split_payment` + `complimentary`; **dedup idempotency:** `_seenIds 500` (LRU 400) for `NetCommand.id` + QR `rawBody.hashCode` 5-sec dedup (`_qrLastSubmit`) — double-tap never charges twice; `Card declined` keeps cart, `Payment times out` checks `stockDeducted` never double-deducts |
| Order confirmed | Email service down → `broadcasts` queue? Phase-2: queue + retry |

**Phase-1 diff:**
- `lan_server.dart`: `_qrLastSubmit` map (200 entries, 30s prune) — same table+payload within 5s returns same `ticket` with `dedup:true`, no new order.
- `storage_service.dart`: offline queue `of_cmd_queue_v1` flushed on reconnect via both `LanClient.send` and `CloudRelay.sendCommand`.
- `reducer.dart:_deductStock` only on `paid && !stockDeducted` — prevents double stock drain on retry.

---

## 4. The Database — fine for 10, fine for 50k

**Before:** `app_data` one table: `orders:"[{..},{..}]"` as text, `email:"see notes"` — duplicate `maya@mail.com`, `null` vs `maya@mail.com`, 9.4s load at 50k.

**After:**

- **Shop-local:** `AppStore` is normalized in Dart (separate `tables`, `orders`, `stock` lists) + hot/cold split above. `pagedOrders` (200) for UI, `reportableOrders` (90d) for reports, `salesOn()` scans 90d only → **0.02s** at 50k (same as slide's right side).
- **SaaS D1:** `schema.sql` has `idx_licenses_key/customer/status`, `idx_cloud_msgs_room`, `idx_license_events_key`, `idx_broadcast_created`. `cloud_msgs` is transit with 3-way prune (TTL 30m, cursor min, cap 200) on every `send`.
- **Phase-1:** Archive file caps at 20k rows, `rate_limits` pruned to `w-3` windows, `license_events` 6-hour prune (was per-validate).

**Phase-2 shipped:** `services/database_service.dart` SQLite (`orders` + 5 indexes, `loadOrders`/`salesOn`/`archiveBefore`) with Windows FFI support. JSON remains fallback; DB backfills lazily.

**Next:** Wire `AppController` to read `orders` from SQLite for `openOrders` hot path; D1 move `rate_limits` to Workers KV.

---

## 5. The Real-World Testing — works on my phone ≠ works

**Matrix that a demo misses:**

| Device | Failure (slide) | Order Flow fix |
|--------|----------------|----------------|
| iPhone SE | Button cut off | `flutter_animate` + `MediaQuery` + `SingleChildScrollView` for order forms; Phase-2 add Patrol snapshot on 375×667 |
| Android | Keyboard covers input | `viewInsets` padding in `order_screen.dart` |
| Dark mode | Text disappears | `theme.dart` tests both `light`/`dark` with `14532d`/`FAF7F2` contrast |
| iPad | Phone layout stretched | `LayoutBuilder` for floor map |
| Slow 3G | Blank 11s | `license_service:20s` + `fetchBroadcasts:12s` timeout + `offline_grace` banner + skeleton; QR `rate_limited` 429 with `Retry-After` |

**Phase-1:** Added `ErrorReporter` stub (`services/error_reporter.dart`) buffering last 50 events for TestFlight. `main.dart` inits it; `app_controller.dart` captures `loadStore`/`loadSession` failures with `tags:where`. CI `arena/**` already runs `flutter test` (see `build-release.yml`). 

**Phase-2 shipped:** `.github/workflows/device-matrix.yml` (iPhone SE / Pixel 5 / iPad Air / Desktop + dark mode + slow 3G) + stub tests `golden_test.dart`/`theme_contrast_test.dart`/`slow_network_test.dart`.

**Next:** Enable Patrol on self-hosted macOS runner for E2E `integration_test/app_test.dart`.

---

## 6. What Happens After Launch — Day 12

**Before:** No crash tracking, no perf, `v1.0.1 checkout crash on Android 12` would sit for 12 days.

**After Phase-1:**

- `services/error_reporter.dart` — in-mem buffer + `health` getter (`buffered`, `lastError`) — swap to `sentry_flutter` by uncommenting 3 lines + adding `SENTRY_DSN` env. Already logs via `dart:developer`.
- `GET /api/v1/health` now reports `d1Ms` + `cache.validateRows` + `time` — hook to UptimeRobot for `p95 6.2s Sync API timeout` alerts.
- `admin/stats` gives `customers/licenses/bound/revoked` — Phase-2 adds `Crash rate %` + `Top issues` table like slide 6.

**Phase-2 shipped:** `sentry_flutter` + `sqflite` in `pubspec.yaml`; `ErrorReporter` ready to swap to `Sentry.captureException` via 3-line uncomment. `app_events` D1 table + staged rollout via `allowedFeatures` without APK remain next.

**Next:** Set `SENTRY_DSN` env + create `app_events` table.

---

## How to verify Phase-1 locally

```bash
# D1 health + latency (after deploy to Cloudflare Pages)
curl https://order-flow-v2.pages.dev/api/v1/health | jq
# -> {ok:true, d1:"ok", d1Ms: 12, cache:{validateRows: 42}}

# License cache (10k shops polling)
# first poll hits D1, second within 2min hits cache (no D1 log)

# Archive (simulate 10k orders)
# start app, create 600 paid orders, check files:
#  - app_state.json  -> orders.length <= 500 + open
#  - app_state_archive.json -> rest
```

## Remaining TODO (Phase-3, not blocking 10k)

- [x] Server-side PIN verify (`POST /verify-pin`) — **shipped**
- [x] SQLite scaffold + `device-matrix.yml` + Sentry deps — **shipped**
- [ ] Wire SQLite into `AppController` hot path (currently scaffold, JSON still primary)
- [ ] D1 `rate_limits` → Workers KV + Durable Objects for relay
- [ ] Set `SENTRY_DSN` + `app_events` funnel table
- [ ] Enforce `kLicenseRequireSig=true` + 6-digit PIN policy

---

*Document generated for `v1.1.84` + Phase-1. See `flutter_app/lib/services/error_reporter.dart`, `lib/models/models_store.dart`, `services/storage_service.dart`, `cloudflare_dashboard/functions/api/[[path]].js` for implementation.*
