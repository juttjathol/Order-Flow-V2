# Changelog

Notable, user-visible changes. The authoritative per-release notes live in
[GitHub Releases](https://github.com/juttjathol/Order-Flow-V2/releases) (every release
carries `app-release.apk` + `order-flow-windows.zip`), and the full engineering session
log — including root causes and the mistakes each release was built to avoid repeating —
is in [`docs/HANDOFF.md`](docs/HANDOFF.md).

## 1.1.96 — 2026-10-31

* **More reliability:** errors persist in an offline outbox and flush on resume; failed printer jobs are saved for retry; cloud sync status is visible.
* **Safer exports:** password-encrypted AES-GCM backups with restore, plus 30-day orders CSV and daily sales PDF.
* **Better shift close:** cash-denomination counter, counted-vs-expected variance, and saved Z-report reconciliation.
* **Sharper operations:** split exact item quantities into a new ticket; share the read-only menu from Android; existing table move/merge retained.
* **License fixes:** targeted broadcasts reach the correct shop; paused licenses show a dedicated EN/UR gate and recover after resuming.
* **Build hardening:** Android 15 release health fixes from v1.1.95 retained; public download fallbacks now point to v1.1.96.

## 1.1.95 — 2026-10-30

### Stock that thinks in recipes
* **Stock engine (add-on)** — order-taker tiles show exactly how many more servings your inventory can make: buns 3 + patties 2 → burger badge says **"2 left"** (badge appears at ≤5). Turned on by your plan features (`stock_engine`).
* **Buy list** — last 7 days of sales per ingredient → exact "buy +X kg" sized for the next week, one tap to send to your supplier on WhatsApp.

### Money, delivery & insight
* **Khata (credit) ledger** — a "Khata / credit" payment method writes the ticket on the customer's tab; live red balances in Customers, **Receive payment**, and a one-tap **WhatsApp the balance** (EN/UR).
* **Delivery dispatch board** — delivery tickets flow **Queued → Out for delivery → Delivered ✓**, drivers assigned right on the card.
* **Menu engineering** — 30-day sales × recipe margins grade every dish ⭐ star / 🐴 plowhorse / 🧩 puzzle / 🐕 dog, with a "needs costing" list for un-costed items.

### New channels
* **Kiosk mode** — a wall tablet becomes a self-order station: pick items, send straight to kitchen, thanks banner; **manager PIN** locks the exit (rides the QR ordering add-on).
* **Loyalty QR on receipts** — receipts print the customer's QR; staff scan it next visit to attach the customer instantly — points and khata follow automatically.
* **Read-only menu link** — More → QR copies a **live view-only menu link** (prices + sold-out state, no ordering) for WhatsApp status or Instagram bio.

### Android release health
* Play Console advisories closed: **edge-to-edge** status/nav bars on SDK 35+ devices, memory-safe image decoding, and a ProGuard/R8 slim-down so release optimisation stays fully on.

## 1.1.94 — 2026-10-29

### Plans, rebuilt around your shop
* **Starter is now Professional — PKR 2,000/month** — one plan with every pro feature: 15 gated features on, including QR table ordering, the branded QR page and third-party channels (previously Customize-only).
* **Cloud networking is now an add-on — +PKR 500/month** — a locked cloud row opens a request sheet in-app (WhatsApp) or by email; once issued, it switches straight on for your key.
* **Customize = your custom POS** — the let's-talk plan (all 16 features, cloud included) now explicitly builds a tailored POS for your business: workflows, branding and hardware.
* Billing currency is **PKR** — site price widget, terms, guide, README and the admin dashboard presets all moved in lockstep (internal key name `starter` stays stable for existing licenses).

## 1.1.93 — 2026-10-28

### Getting started
* **Try the demo** — the license screen gets a no-key walkthrough: a seeded café opens with sample tables, menu and tickets, the guided tour runs inside it, and one tap exits and wipes everything. APK + web.
* **Guided tour v2** — spotlight steps point at the real controls (hero card, Room QR, first table tile, the menu Add button, More rows), switch tabs on their own, scroll targets into view, and dock the bubble beside the button.

### Smarter surfaces
* **Best-seller 🔥 badge** on menu pick cards (web register + APK order screen): top 3 items by qty paid today.

### Trust & store hygiene
* **Demo is not a free POS**: demo shops cap at 10 live orders and never touch a printer; cloud rooms and multi-terminal stay license-gated by design.
* **Play Console**: unused location permissions removed from the manifest; Data-safety docs updated. Plan copy synced — full plan is 16 features (site previously said 15).
* **Web audit**: every button verified wired; stray `</div>` and dead handlers removed.

## 1.1.92 — 2026-10-26

### Devices & team
* **Named stations** — APK connect screen and the web join page now ask "This device's name" (Danial, Ali, Kitchen phone…). It rides in the hello message on both LAN and the cloud room, so Main's Stations panel shows names instead of raw binding ids. Web Main can rename any station in place (✏️ pen); the device itself re-announces the new name on the next hello.

### Orders & timing
* Prepared/ready/served timers everywhere now read **h:mm:ss live** (1 Hz) — APK kitchen cards, floor map, home tickets and web live board, kitchen column, and pay list.
* **Ready-alert latency fixed for web-Main rooms**: a cloud-only Android station was going quiet because its LAN-reconnect cadence throttled the room relay to 30 s polling; now a pure-cloud station keeps the relay hot. And when the web app presses "ready", the snapshot-diff detects the ready transition and phones flash a banner + phone alert even with no LAN.

### First run
* **Bubble coachmark tour** — six cards walk Home → Room QR (pairing) → Floor → Menu → More on both the APK and the web PWA; runs once per device and replays from More → Guided tour. EN + اردو.

### Visual overhaul (brand hexes untouched)
* Hairline card borders, softer shadows, tinted state bands on table tiles (gold = busy, mint = ready), tabular-numeral amounts on stats/hero, uppercase micro-labels for section headers, hover lift on menu cards, friendlier form focus states, scheme-matched scrollbars.

## 1.1.84 — 2026-09-29

### Splash

* New splash screen — radial glow (`#0d2420 → #050a08 → #020404`), pulsing rings, `logo.png` entrance (`cubic(0.34,1.56,0.64,1)`), `Jathol` typed (`1100ms` delay, `120ms`/letter, cursor `3×36 #2fffa0` blink `0.7s`), `ORDER FLOW` tagline fade, `fadeOut 0.6s at 4.8s` — matches `src/App.tsx` + `src/index.css` exactly, using your uploaded logo as-is (`flutter_app/assets/brand/logo.png`). Only `SplashScreen` touched.

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
