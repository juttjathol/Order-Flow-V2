# Order Flow

Offline-first, multi-device POS for restaurants, retail, fast food, and services — plus a Cloudflare SaaS license dashboard.

- **Android app** (`flutter_app/`) — Main server device + Order Taker / Kitchen / Cashier / Driver (and model-specific roles)
- **SaaS dashboard** (`cloudflare_dashboard/`) — customers, license keys, device binding, revoke/delete
- **CI** (`.github/workflows/build-release.yml`) — tag `v*` → release APK

Version **1.0.0+1**.

---

## How the shop works

One phone or tablet is **Main**. It holds the license, starts a local HTTP + WebSocket server on **port 8787**, and is the source of truth for menu, stock, tables, and orders.

Other phones on the **same Wi‑Fi** join Main with the IP or QR code. They do **not** need a license key.

After the first successful online activation, Main keeps working **offline for 48 hours**. When the internet is back, the app revalidates the key. If the key was deleted or revoked in the dashboard, the Main app **locks** and only shows WhatsApp support **[@Jathol_Jutt](https://wa.me/Jathol_Jutt)**.

The currency symbol is configurable (default `Rs`) and is used on **every** price: menu, stock, tickets, charts, and receipts. Nothing is hardcoded as `$`.

---

## 1. Deploy the Cloudflare dashboard + D1

You need a Cloudflare account and [Wrangler](https://developers.cloudflare.com/workers/wrangler/).

```bash
cd cloudflare_dashboard
npm install

# Create the D1 database
npx wrangler d1 create order_flow
```

Copy the printed `database_id` into `wrangler.toml`:

```toml
[[d1_databases]]
binding = "DB"
database_name = "order_flow"
database_id = "YOUR_D1_ID"
```

Apply the schema (remote, then optional local):

```bash
npx wrangler d1 execute order_flow --remote --file=schema.sql
npx wrangler d1 execute order_flow --local --file=schema.sql
```

Set admin secrets (do not commit these):

```bash
npx wrangler pages secret put ADMIN_PASSWORD
npx wrangler pages secret put ADMIN_SECRET
```

`ADMIN_PASSWORD` is the dashboard login. `ADMIN_SECRET` signs session tokens.

Deploy Pages (static UI in `public/` + Functions in `functions/`):

```bash
npx wrangler pages deploy public --project-name order-flow-saas
```

Or connect this GitHub repo to Cloudflare Pages:

- **Project name:** `order-flow-saas` (or your own)
- **Root directory:** `cloudflare_dashboard`
- **Build output:** `public`
- Bind D1 as `DB` in the Pages project settings
- Add the same secrets in the Pages dashboard

Open the Pages URL, sign in, create a customer, generate a key.

### License API used by the app

`POST /api/v1/license/validate`

```json
{ "licenseKey": "OF-XXXX-XXXX-XXXX-XXXX", "deviceId": "uuid-from-the-phone" }
```

Successful first call **binds** `bound_device_id`. A second device using the same key receives `bound_to_other_device` until an admin resets the binding.

In the Android app, set **License API URL** on the license screen to your Pages origin, for example:

`https://order-flow-saas.pages.dev`

---

## 2. Create a GitHub tag and download the APK

The workflow `.github/workflows/build-release.yml` runs on tags matching `v*`.

```bash
git checkout arena/01a01842-order-flow-v2
git pull
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions then:

1. Installs **Java 17** and **Flutter stable**
2. Forces **compileSdk 36** and **minSdk 23**
3. Patches Android plugin namespaces if a plugin forgot them
4. Runs `flutter pub get`
5. Builds `flutter build apk --release --no-tree-shake-icons`
6. Uploads `app-release.apk` as an artifact and attaches it to the GitHub Release

Download from the **Releases** page, or from the workflow **Artifacts**.

Local build (once Flutter is installed):

```bash
cd flutter_app
flutter pub get
flutter build apk --release --no-tree-shake-icons
# output: build/app/outputs/flutter-apk/app-release.apk
```

Printing uses **network ESC/POS over TCP 9100**. The broken `blue_thermal_printer` plugin is not used.

---

## 3. License binding and device reset

| Event | Result |
| --- | --- |
| First Main phone activates a key | Key is bound to that phone’s `device_id` |
| Second phone tries the same key | Rejected (`bound_to_other_device`) |
| Admin clicks **Reset device** | `bound_device_id` is cleared; the key can activate on a new phone |
| Admin **deletes** or **revokes** the key | Next online check locks the Main app |
| Main is offline after a valid check | Works for **48 hours**, then must revalidate |

Reset path in the dashboard: **License keys → Reset device**.

Deleted/revoked Main devices only show WhatsApp support: **@Jathol_Jutt**.

---

## 4. Secondary devices connect without a key

On the license screen tap **Connect to Main** (do not paste a key).

1. Put the station on the **same Wi‑Fi** as Main
2. On Main → **Home**, read the IP or scan the QR (`orderflow://join?host=…&port=8787`)
3. Enter the IP or scan, then pick a role:
   - Restaurant: Order Taker, Kitchen, Cashier, Driver
   - Retail: Cashier, Stock clerk
   - Fast food: Order Taker, Kitchen, Cashier
   - Services: Front desk, Specialist, Cashier

Orders, menu, and stock sync over the local WebSocket in real time.

**Drivers** pair once with Main, then can change **free / busy / offline** on their own phone even off the shop network. Status syncs again when Main is reachable. Drivers never need a SaaS login.

---

## App map (Main device)

Bottom navigation:

1. **Home** — server status, IP + QR, today’s sales, open orders, sales / inventory / ticket charts
2. **Tables / Register / Queue / Appointments** — depends on business model; tables are live buttons (free / ordered / ready)
3. **Menu** — category + item grid with photos and currency prices
4. **Stock** — card list, low-stock colors, +/- adjust, auto-deduct on paid orders
5. **More** — bill profile, printers, drivers, staff, reports, backup export/import, license, roles, language, theme

Kitchen marks a ticket **ready** → every Order Taker and Main sees a banner (“Table X order is ready to serve”) and the table tile turns ready.

English and Urdu, dark/light (Suzlon-style dark green).

---

## Printing and backup

- Bill profile: logo (name), address, phone, tax ID, footer, tax %, **currency symbol**
- Kitchen ticket and payment receipt over **TCP 9100**
- **More → Export backup JSON** / **Import backup JSON** (import replaces Main shop data)

---

## Support

WhatsApp username **@Jathol_Jutt** (not a phone number): [wa.me/Jathol_Jutt](https://wa.me/Jathol_Jutt)
