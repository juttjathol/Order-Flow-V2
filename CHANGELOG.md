# Changelog

Notable, user-visible changes. The authoritative per-release notes live in
[GitHub Releases](https://github.com/juttjathol/Order-Flow-V2/releases) (every release
carries `app-release.apk` + `order-flow-windows.zip`), and the full engineering session
log — including root causes and the mistakes each release was built to avoid repeating —
is in [`docs/HANDOFF.md`](docs/HANDOFF.md).

## 1.1.83 — 2026-09-28

### Security

* Browser console at `http://<main-ip>:8787/` no longer receives the manager PIN, and
  every value it renders is HTML-escaped (a poisoned dish name could previously run
  script inside the owner's console).
* LAN CORS policy now requires browsers to address Main by IP literal or `localhost`,
  closing a DNS-rebinding path to the store and its web commands.
* QR self-order flood control fixed: it keyed on a spoofable header and, worse, on the
  server's own address — which put every guest in one 60-orders-per-hour bucket and could
  lock QR ordering out shop-wide mid-service. Now per-table (seated service) plus one
  generous shop-wide cap.
* Driver pairing requires a manager/Main role; a driver can only change its own status.
* Ceilings on LAN websockets, pending approvals and websocket frame size.
* Cloud relay writes require room membership; per-device send/pull throttles; room row
  cap halved.
* Broadcast links are `https://`-only and length-capped server-side.
* License API and relay quota fixes: retention pruning no longer runs on every request.

### Fixed

* 12 strings that existed only in English now have Urdu translations (role picker,
  payment methods, printer tests, "In kitchen", "Save to book"). English and Urdu are at
  exact parity: 714 keys each.

### Docs & repo

* `docs/SECURITY_AUDIT_2026-09-28.md` — full audit with severity, evidence and status.
* `SECURITY.md`, `CONTRIBUTING.md`, issue and pull-request templates.
* `docs/HANDOFF.md` gained a **START HERE — owner directives** section; the stale
  "Open PR #7 / next version 1.1.60" lines were corrected.
* README refreshed for v1.1.82 (Windows Main, plans & per-key feature access, cloud
  networking, both release assets).

## 1.1.82 — 2026-09-26

* Fixed the dashboard "tick all" lockout: the access editor read the wrong checkbox
  selector, so saving granted **zero** features and shops on Growth/Custom/Full lost
  their extras. Repaired at six layers — dashboard selector and self-healing submit,
  license worker healing on both read and write, app-side `full` short-circuit, transient
  errors sharing the offline-grace path so they can never lock a shop, awaited
  entitlement propagation on refresh, and a scrollable license sheet whose Refresh now
  reports `Plan synced · n/15`.

## 1.1.81 — 2026-09-26

* Version drift fixed: in-app footer, LAN handshake and metadata all read `kAppVersion`,
  and `scripts/version_sync_check.py` now fails the build loudly if the three lockstep
  places disagree.
* Windows: the pubspec version is baked into the window title (`Order Flow X.Y.Z`) so a
  shop can prove which build it is actually running, and a desktop close-guard kills any
  ghost `order_flow.exe` that would hold port 8787 or block ZIP re-extraction.
* License sheet: **Refresh plan & features now**; revalidation interval cut from 15 to
  5 minutes so dashboard changes reach Main faster.
* Server resilience: watchdog retries a failed LAN server start, and a failed IP refresh
  can no longer mark a running server as stopped.

## 1.1.80 — 2026-09-26

* Windows Main branding: the shop icon is installed into the generated runner
  (`scripts/windows/app_icon.ico`), and the guide covers SmartScreen, the portable-ZIP
  update flow and the "folder in use" trap.

## 1.1.76 — 2026-09-26

* **Desktop Main**: a Windows 10/11 laptop or PC can be the Main device. Raw ESC/POS
  printing through the Windows spooler via `dart:ffi` (no new dependency), platform-aware
  printer sheet (`bt` on Android, `sys` + `lan` on Windows), desktop image picking, and
  phone-only capabilities cleanly gated off (camera barcode scan, ML Kit, Bluetooth,
  Wi-Fi info). CI gained a `windows-latest` job that produces `order-flow-windows.zip`.

## 1.1.73

* Security hardening pass (server S1–S9, app A1–A6): shared `_security.js`, token-gated
  relay diagnostics, Cloudflare-trusted client IPs with D1 rate limiting, input length
  caps, PBKDF2 clamped to 100 000 iterations, per-request CORS, admin tokens moved to
  `sessionStorage`, optional Ed25519 license signatures, LAN role allowlist with device
  approval and HMAC tokens, QR rate limits, `https://`-only pairing strings, license
  locking restricted to `not_found`/`revoked`/`expired`, hashed manager PIN with
  lockout, and `allowBackup="false"`.

## Earlier

Versions 1.0.0 → 1.1.72 (QR table ordering and the branded guest page, cloud networking,
recipe costing and margins, wastage, suppliers and purchase orders, insights, plan-gated
licensing, universal Bluetooth printing, Focus-Point receipt layout, per-slip footers,
PDF/photo menu import, the legal suite on the website, and the v1.1.61 brand refresh) are
documented in [releases](https://github.com/juttjathol/Order-Flow-V2/releases) and in
`docs/HANDOFF.md` / `docs/AGENT_MEMORY_order_flow.md`.
