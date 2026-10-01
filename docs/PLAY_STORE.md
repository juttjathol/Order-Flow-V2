# Google Play — publish checklist (2026)

> **Sideload APKs (`v1.1.85` tag) do NOT need this.** This doc is the gate before you upload `app-release.aab` to Play Console.

## 2026 gates you must clear (what changed)

| Gate | Rule (2026) | Order Flow status |
|------|--------------|-------------------|
| **Target API 35/36** | New apps & updates must target **API 35 (Android 15)** — Aug 2025 for new, Nov 2025 for updates. **API 36 (Android 16)** required by **31 Aug 2026**, extensions to 1 Nov 2026 only on request. | `compileSdk 36` + `targetSdk 36` in `flutter_app/android/app/build.gradle.kts` (`namespace com.jathol.orderflow`, `ndkVersion = flutter.ndkVersion`, `Java 17`). CI `patch_android.py` forces 36 on all plugins. Meets both 35 and 36 floors. |
| **Data Safety** | Must declare **every** data type you *or any SDK* collects, how it’s used, and who you share with. April 2025 clarifies: **Android ID = Device ID**, and sharing includes SDK vendors that use data for their own purposes (ads, profiling). Google cross-checks the APK and suspends mismatches. | See “Data safety answers” below — `Device ID` (random `of_hardware_device_id` + `licenseKey`) → App functionality, encrypted in transit, user can reset via WhatsApp @Jathol_Jutt. No Advertising ID, no analytics. Must be re-audited on every SDK bump (e.g., `google_mlkit`, `sentry`). |
| **Privacy policy URL** | Must be live HTTPS, public, non-geofenced, non-PDF, same host as Data Safety, in **Store listing → Privacy policy** + **in-app** (More → Privacy). | `https://jathol.pages.dev/privacy` (primary) + `https://order-flow-v2.pages.dev/privacy` (mirror). Static HTML, last updated **25 Aug 2026** (`cloudflare_dashboard/public/privacy.html` + `website/public/privacy.html`), PDPA 2010, no geofence. In-app `kPrivacyUrl` → `https://jathol.pages.dev/privacy`. |
| **Feature graphic / icons** | `1024×500` PNG/JPG mandatory + `512×512` high-res icon (no Play logo) + ≥2 phone screenshots (8 max, at least one per device type). | Icons: `flutter_app/android/app/src/main/res/mipmap-*` (anydpi `ic_launcher.xml` + foreground 108dp). **Store graphics not in repo** — add `store_assets/` (see below) before first upload. |
| **AAB + Play Signing** | Play **requires AAB**, not APK. Upload via **Play App Signing** (you keep upload key, Play keeps signing key). GitHub Actions currently builds `app-release.apk` only — `app-release.aab` added in this patch (`flutter build appbundle`). | `build-release.yml` now has `Build release AAB (Play Store)` → `build/app/outputs/bundle/release/app-release.aab` → artifact `app-aab` → attached to GitHub Release alongside APK + Windows. Signing uses `sideload/upload.p12` (`JatholOrderFlowSideload`) — for Play, create a separate upload keystore and never commit its password (store in Play Console + GitHub Secrets `PLAY_UPLOAD_*`). |
| **Permissions** | Request only what’s needed; background location / nearby devices heavily reviewed. Use `neverForLocation` where possible. | `AndroidManifest.xml`: `CAMERA`, `ACCESS_FINE/COARSE_LOCATION`, `NEARBY_WIFI_DEVICES` + `BLUETOOTH_SCAN neverForLocation`, `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `BLUETOOTH_CONNECT`. `camera` + `bluetooth` marked `required=false`. `google_analytics_adid_collection_enabled=false`. `allowBackup=false`. `networkSecurityConfig` base `cleartextTrafficPermitted=false` (only `localhost`/`127.0.0.1`/`10.x`/`192.168.x` LAN). |
| **64-bit + App Integrity** | 64-bit ABIs required; Play Integrity API recommended. | Flutter builds `arm64-v8a` + `x86_64` by default; `shelf` LAN server is pure Dart. |
| **Government ID / finance** | If you collect government IDs or finance data, extra verification + encryption. | We don’t — shop POS keeps sales on device; license key is not a government ID. |

## Already in the app (verified 2026-10-01)

- `applicationId` `com.jathol.orderflow`
- `targetSdk` / `compileSdk` **36** (Android 16) — meets 31 Aug 2026 rule
- `minSdk 23` (Android 6.0) — covers 99% of POS tablets
- Camera / Bluetooth `required=false`
- Bluetooth scan `neverForLocation`
- Foreground service `ShopKeepAliveService` as `dataSync` (Android 14+ compliant)
- No advertising ID (`google_analytics_adid_collection_enabled=false`)
- `enableOnBackInvokedCallback=true`
- Privacy policy live + in-app `More → Privacy policy`
- `proguard-rules.pro` keeps `com.google.mlkit.**` for barcode

## You still do in Play Console (account, not code)

1. **Developer account** (~USD 25) + ID / business verification (24–48h)
2. **Closed test** (14 days) for personal accounts before production
3. Upload an **AAB** with **Play App Signing** (not the sideload APK)
4. Store listing: `Order Flow` (30), short desc 80 chars, full desc 4000, `512×512` icon, `1024×500` feature graphic, ≥2 phone screenshots
5. Content rating (IARC) — questionnaire
6. Target audience: `18+` / Business (`Order Flow is a business POS`)
7. **Data safety form** — fill exactly as “Data safety answers” below, keep in sync with `privacy.html`
8. Ads: **No ads**
9. Privacy policy URL: `https://jathol.pages.dev/privacy`
10. Contact email: `contact@jathol.org` (monitored, Mon–Sat GMT+8)
11. App access: “No login — enter 16-char license key on Main, or ‘Connect to Main’ via IP/QR. Test key: `TEST-1111-1111-1111` (or WhatsApp @Jathol_Jutt).”
12. Production release → review (1–7 days for new apps, hours for updates)

## Data safety answers (current product, 2026-10-01)

| Data type | Collected? | Shared? | Purpose | Encrypted? | Deletion |
|-----------|------------|---------|---------|------------|----------|
| **Device or other IDs** — `Android ID` / `Device ID` (`of_hardware_device_id` + `licenseKey`) | **Yes** — random UUID stored in `SharedPreferences` + key you type | **No** — only to Jathol license API (`order-flow-v2.pages.dev`) for activation, not to SDK vendors for their own use | **App functionality** (binds one key to one Main) | Yes (HTTPS) | Yes — uninstall clears it; reset binding via WhatsApp |
| **App activity** — `app interactions` (screen views, button taps) | No (no analytics) | No | — | — | — |
| **App info & performance** — `crash logs` | No (Sentry stub, DSN empty) — if you set `SENTRY_DSN`, then Yes → `Crash logs` → App functionality, encrypted | No | — | — | — |
| **Photos / media** | **No** — menu photos stay in `getApplicationDocumentsDirectory()` on device, never uploaded | No | — | — | — |
| **Location** — `Approximate location` | **System-derived only** — Android may expose IP-derived location to `network_info_plus` for `getWifiIP`; we do not send it anywhere | No | App functionality (find Main on LAN) | — | — |
| **Financial** | No — sales, stock, customers stay on shop LAN + archive JSON/SQLite | No | — | — | — |
| **Advertising ID** | **No** — `google_analytics_adid_collection_enabled=false`, no AdMob | No | — | — | — |

> Declare **Android ID** under **Device or other IDs**. If you enable `SENTRY_DSN`, update this table to `Crash logs: Yes, App functionality`.

## Store assets you must add before first upload

```
store_assets/
  feature-graphic-1024x500.png   # 1024×500, PNG/JPG, no Play logo
  icon-512.png                   # 512×512, PNG, no shadow, no Play logo
  screenshots/
    phone-1-1080x1920.png
    phone-2-1080x1920.png
    tablet-1-2048x2732.png (optional but recommended)
```

These are **not** in the APK — they live only in Play Console. Keep the source in `store_assets/` (gitignored LFS if large) so the listing is reproducible.

## AAB signing for Play

- **Sideload** (`sideload/upload.p12`, `JatholOrderFlowSideload`) — used by GitHub Actions for APK/AAB attached to GitHub Releases. Fine for direct download.
- **Play upload** — generate a **new** upload keystore (do not reuse `upload.p12`):
  ```bash
  keytool -genkey -v -keystore play-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload -storepass "$(pass show play/storepass)" -keypass "$(pass show play/keypass)"
  ```
  Upload `play-upload.jks` to **Play Console → Setup → App signing → Upload key**, store passwords in **GitHub Secrets** `PLAY_UPLOAD_STORE_PASSWORD` / `PLAY_UPLOAD_KEY_PASSWORD` / `PLAY_UPLOAD_KEY_ALIAS`, and modify `build-release.yml` to use them for `appbundle` only. **Never commit the passwords.**

## After deploy

- `/privacy` only works after Cloudflare Pages `order-flow-v2` + `jathol` deploy. Verify `https://jathol.pages.dev/privacy` returns 200 before submitting.
- Data Safety + privacy policy must match **exactly** — re-audit on every SDK bump (check `flutter_app/pubspec.yaml` + `pubspec.lock` + `build.gradle.kts` `implementation("com.google.mlkit:barcode-scanning")`).

