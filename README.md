# Order Flow

Offline-first multi-device POS for restaurants, retail, fast food, and services, plus a Cloudflare license dashboard.

- **Android app** (`flutter_app/`) — Main server + Order Taker / Kitchen / Cashier / Driver
- **SaaS dashboard** (`cloudflare_dashboard/`) — customers, keys, device bind / reset / revoke
- **APK** — create a GitHub Release tag `v1.1.58` (or any `v*`) and download `app-release.apk`
- **Public website** (`website/`) — Jathol.pages.dev + full user guide (`/guide`)

Version **1.1.58+58**.

You only need two things after this repo is on GitHub:

1. Connect the repo to **Cloudflare Pages** (dashboard clicks, no terminal)
2. Create a **GitHub Release** with tag `v1.0.0` (the Action builds the APK)

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

First success **binds** the phone. A second phone is rejected until you click **Reset device**. Delete or revoke the key and the Main app locks to WhatsApp **@Jathol_Jutt**.

---

## 2. Get the APK — publish a GitHub Release tag

The Arena GitHub app cannot create workflow files. Add the builder **once** with this pre-filled page (filename and YAML are already filled in):

**[Create `.github/workflows/build-release.yml` — then click “Commit changes”](https://github.com/juttjathol/Order-Flow-V2/new/main?filename=.github/workflows/build-release.yml)**

Paste is not required if the editor opened with the file name. If the box is empty, copy [`scripts/github/build-release.yml`](scripts/github/build-release.yml) into it and commit to `main`.

After that, every release is tag-only (no terminal):

1. Open the repo → **Releases** → **Draft a new release**
2. **Choose a tag** → type `v1.0.0` → **Create new tag** on `main`
3. Title: `Order Flow 1.0.0`
4. **Publish release**

GitHub Actions (`.github/workflows/build-release.yml`) then:

- Installs Java 17 + Flutter stable
- Forces compileSdk **36** and minSdk **23**
- Patches plugin namespaces
- Builds `flutter build apk --release --no-tree-shake-icons`
- Attaches **`app-release.apk`** to that Release

Every push to an `arena/**` branch also runs `.github/workflows/build-arena.yml` (analyze → tests → release APK → downloadable artifact), so changes are verified green before they ever reach a release tag.

Refresh the Release page after the Action finishes (Actions tab → **Build Release APK**).

Later versions: publish `v1.0.1`, `v1.1.0`, …

---

## How the shop works

One device is **Main**. It holds the license and runs the local server on **port 8787**.

Other phones on the **same Wi‑Fi** tap **Connect to Main** (IP or QR). They do **not** need a key.

After the first online activation, Main works **offline for 48 hours**. When the internet returns it rechecks the key. If the key was deleted or revoked, Main **locks** and only shows WhatsApp **[@Jathol_Jutt](https://wa.me/Jathol_Jutt)**.

Currency is configurable (default `Rs`) and is used on **every** price. Nothing is hardcoded as `$`.

### License binding

| Event | Result |
| --- | --- |
| First Main phone activates a key | Bound to that phone |
| Second phone uses the same key | Rejected until **Reset device** |
| Admin deletes or revokes the key | Main app locks |
| Offline after a valid check | Works 48 hours |

### Secondary devices (no key)

License screen → **Connect to Main** → same Wi‑Fi → IP or QR from Main → Home → pick a role:

- Restaurant: Order Taker, Kitchen, Cashier, Driver
- Retail: Cashier, Stock clerk
- Fast food: Order Taker, Kitchen, Cashier
- Services: Front desk, Specialist, Cashier

**Drivers** pair once, then set free / busy / offline even off the shop Wi‑Fi. No SaaS login.

---

## Main app tabs

1. **Home** — server, IP + QR, sales, open orders, charts
2. **Tables / Register / Queue / Appointments** — live buttons (free / ordered / ready)
3. **Menu** — photos + currency prices
4. **Stock** — cards, low-stock, auto-deduct on paid orders
5. **More** — bill profile, printers, drivers, reports, backup, license, language, theme

Kitchen **ready** notifies every Order Taker and Main. English + Urdu. Dark / light green theme.

Printing is network ESC/POS on **TCP 9100** or Bluetooth. **Every station can use its own printer** (printer icon in the station top bar — Bluetooth or LAN), independent of Main. A **cash drawer** (RJ11 kick port on the receipt printer) opens automatically on cash payments only; card / wallet / other never open it. Payments support **split tender** (two methods on one sale), receipts can be **shared on WhatsApp/SMS**, paid orders can be **refunded** (stock returns), saved customers earn **loyalty points** automatically, and any screen can become a **customer display** with a giant animated total. Backup is JSON export / import.

The full walkthrough lives on the website: **https://jathol.pages.dev/guide** (English + Urdu).

---

## Support

WhatsApp **@Jathol_Jutt** (username, not a phone number): [wa.me/Jathol_Jutt](https://wa.me/Jathol_Jutt)
