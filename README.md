# Order Flow

[![Latest release](https://img.shields.io/github/v/release/juttjathol/Order-Flow-V2?label=release&color=14532d)](https://github.com/juttjathol/Order-Flow-V2/releases/latest)
[![Build Release APK + Windows](https://github.com/juttjathol/Order-Flow-V2/actions/workflows/build-release.yml/badge.svg)](https://github.com/juttjathol/Order-Flow-V2/actions/workflows/build-release.yml)
[![Runs on](https://img.shields.io/badge/Main_on-Android_%7C_Windows_10--11-14532d)](#how-the-shop-works)
[![Shop UI](https://img.shields.io/badge/UI-English_%7C_%D8%A7%D8%B1%D8%AF%D9%88-b45309)](https://jathol.org/guide)
[![Download](https://img.shields.io/badge/download-jathol.org%2Fdownload-0ea5e9)](https://jathol.org/download)

Offline-first multi-device POS for restaurants, retail, fast food, and services, plus a Cloudflare license dashboard.

- **Android app** (`flutter_app/`) — Main server + Order Taker / Kitchen / Cashier / Driver
- **Windows Main** — the same Main server in `order_flow.exe` for Windows 10/11 laptops (v1.1.76+)
- **SaaS dashboard** (`cloudflare_dashboard/`) — customers, keys, device bind / reset / revoke, plans & per-key feature access, push broadcasts
- **APK + Windows ZIP** — create a GitHub Release tag `v1.1.84` (or any `v*`) and the Action attaches `app-release.apk` and `order-flow-windows.zip`
- **Public website** (`website/`) — Jathol.pages.dev + full user guide (`/guide`)

Version **1.1.84+84**.

You only need two things after this repo is on GitHub:

1. Connect the repo to **Cloudflare Pages** (dashboard clicks, no terminal)
2. Create a **GitHub Release** with tag `v1.0.0` (the Action builds the APK + Windows ZIP)

---

## 1. Deploy the SaaS dashboard (Cloudflare website only)

1. Open [Cloudflare Dashboard](https://dash.cloudflare.com) → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**.
2. Select the `juttjathol/Order-Flow-V2` repo.
3. Set:
   - **Project name:** `order-flow-saas`
   - **Production branch:** `main`
   - **Root directory:** `cloudflare_dashboard`
   - **Build command:** leave empty
   - **Build output directory:** `public`
4. **Save and Deploy**.
5. **D1 database**
   - Workers & Pages → **D1** → **Create database** named `order_flow`
   - Open the database → **Console**
   - Paste everything from [`cloudflare_dashboard/schema.sql`](cloudflare_dashboard/schema.sql) and run it
   - Back on the Pages project → **Settings** → **Bindings** → **Add** → **D1 database**
     - Variable name: `DB`
     - Database: `order_flow`
6. **Secrets** (Pages project → **Settings** → **Environment variables** / **Secrets**, Production):
   - `ADMIN_PASSWORD` — dashboard login password
   - `ADMIN_SECRET` — long random string used to sign admin sessions
7. **Retry deployment** so the binding and secrets apply.
8. Open `https://order-flow-saas.pages.dev` (or your Pages URL), sign in, create a customer, generate a license key.

In the Android app license screen, set **License API URL** to that Pages origin.

### License API

`POST /api/v1/license/validate`

```json
{ "licenseKey": "OF-XXXX-XXXX-XXXX-XXXX", "deviceId": "uuid-from-the-phone" }
```

First success **binds** the device. A second device is rejected until you click **Reset device**. Delete or revoke the key and the Main app locks to WhatsApp **@Jathol_Jutt**.

### Plans & per-key access (v1.1.59+, hardened v1.1.82)

Every key carries a **plan** — Starter / Growth / Custom / Full — plus the **business models** it may run and a **15-extra feature checklist** (QR ordering, station printers, loyalty, refunds, purchases, cloud sync, branded QR page, …) editable from the dashboard's **Access…** dialog:

- **Starter** — core billing only, no gated extras.
- **Growth** — the original 13 extras (cloud networking + branded QR page stay Custom/Full-only).
- **Custom** — hand-pick exactly what the key unlocks.
- **Full** — everything on, always (the contract; `[]` can never lock a full key out).

A Key's plan lands on the shop's Main at the next online check (every ~15 min), or instantly when someone taps **More → License → Refresh plan & features** in the app, then propagates to every station over LAN. The worker heals any empty-feature row written for a paid plan (v1.1.82 dashboard bug signature) — saving zero extras on Growth/Custom/Full falls back to the plan preset instead of locking a shop out.

---

## 2. Get the APK + Windows ZIP — publish a GitHub Release tag

GitHub Actions (`.github/workflows/build-release.yml`) installs Java 17 + Flutter stable, patches the Android and Windows builds, and attaches **`app-release.apk`** (Android) and **`order-flow-windows.zip`** (Windows 10/11 Main, portable — unzip and run `order_flow.exe`) to the Release.

After that, every release is tag-only (no terminal):

1. Open the repo → **Releases** → **Draft a new release**
2. **Choose a tag** → type `v1.0.0` → **Create new tag** on `main`
3. Title: `Order Flow 1.0.0`
4. **Publish release**

Refresh the Release page after the Action finishes (Actions tab → **Build Release APK + Windows**).

The website's download proxy (`/download`) always serves the latest release — homepage links never go stale.

Every push to an `arena/**` branch also runs analysis and tests, so changes are verified green before they reach a release tag.

---

## How the shop works

One device is **Main**. It holds the license and runs the local server on **port 8787** — an Android phone **or a Windows laptop** (`order_flow.exe` from the release ZIP; see guide §27).

Other phones on the **same Wi‑Fi** tap **Connect to Main** (IP or QR). They do **not** need a key.

After the first online activation, Main works **offline for 48 hours**. When the internet returns it rechecks the key. Transient hiccups (server busy, rate-limited, signature check glitch, maintenance pages) never lock a working shop — only a deleted, revoked or expired key does, and that Main **locks** to WhatsApp **[@Jathol_Jutt](https://wa.me/Jathol_Jutt)**.

Currency is configurable (default `Rs`) and is used on **every** price. Nothing is hardcoded as `$`.

### License binding

| Event | Result |
| --- | --- |
| First Main device activates a key | Bound to that device |
| Second device uses the same key | Rejected until **Reset device** |
| Admin deletes or revokes the key | Main app locks |
| Offline after a valid check | Works 48 hours |
| Plan edited on the dashboard | Main picks it up in ≤15 min, or instantly via **Refresh plan & features** |

### Secondary devices (no key)

License screen → **Connect to Main** → same Wi‑Fi → IP or QR from Main → Home → pick a role:

- Restaurant: Order Taker, Kitchen, Cashier, Driver
- Retail: Cashier, Stock clerk
- Fast food: Order Taker, Kitchen, Cashier
- Services: Front desk, Specialist, Cashier

**Drivers** pair once, then set free / busy / offline even off the shop Wi‑Fi. No SaaS login.

### Cloud networking (Custom plan)

When the shop Wi‑Fi dies mid-service, stations can ride an **encrypted cloud relay** instead of the LAN (v1.1.60+): Main opens a room, stations join with a pairing code, and orders reach Main over any connection. Messages are end-to-end encrypted between your devices, deleted on read, and expire in ~30 minutes — **shop data is never backed up to the cloud**.

---

## Main app tabs

1. **Home** — server, IP + QR, sales, open orders, charts, broadcasts from the dashboard
2. **Tables / Register / Queue / Appointments** — live table map with busy clocks and search (free / ordered / ready)
3. **Menu** — photos + currency prices; **Menu Scan** imports a menu from a photo or PDF entirely on-device
4. **Stock** — cards, low-stock, auto-deduct on paid orders, suppliers & purchase orders, wastage log, recipe costing
5. **More** — bill profile, printers, drivers, reports & shift close, backup, license & plan extras, language, theme

Kitchen **ready** notifies every Order Taker and Main. English + Urdu. Dark / light green theme.

Printing is network ESC/POS on **TCP 9100**, Bluetooth (Classic + Low-Energy), or — on Windows Main — any installed **Windows printer** (USB thermal works with the built-in *Generic / Text Only* driver). **Every station can use its own printer** (printer icon in the station top bar), independent of Main. A **cash drawer** (RJ11 kick port on the receipt printer) opens automatically on cash payments only; card / wallet / other never open it. Payments support **split tender** (two methods on one sale), receipts can be **shared on WhatsApp/SMS**, paid orders can be **refunded** (stock returns), saved customers earn **loyalty points** automatically, and any screen can become a **customer display** with a giant animated total. Backup is JSON export / import.

The full walkthrough lives on the website: **https://jathol.pages.dev/guide** (English + Urdu).

---

## Support

WhatsApp **@Jathol_Jutt** (username, not a phone number): [wa.me/Jathol_Jutt](https://wa.me/Jathol_Jutt)
