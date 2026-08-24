# Google Play — later publish checklist

This is **not** required for GitHub APK sideload builds. When we tag a new APK, ask:

> Does this update also need to go to Play Store (AAB + Play signing + store listing)?

## Already in the app (v1.1.7+)

- `applicationId` `com.jathol.orderflow`
- `targetSdk` / `compileSdk` **36** (Android 16) — meets the 31 Aug 2026 Play rule for new apps/updates
- Camera / Bluetooth marked **not required**
- Bluetooth scan **neverForLocation**
- Foreground service `ShopKeepAliveService` declared as `dataSync`
- No advertising ID collection flag
- Public privacy policy: https://order-flow-v2.pages.dev/privacy
- In-app **More → Privacy policy**

## You still do in Play Console (account, not code)

1. Developer account (~USD 25) + ID / business verification
2. Personal accounts: 14-day closed test before production
3. Upload an **AAB** (not only APK) with **Play App Signing**
4. Store listing: name (30), short desc (80), full desc (4000), 512×512 icon, 1024×500 feature graphic, ≥2 phone screenshots
5. Content rating (IARC questionnaire)
6. Target audience (18+ / business is fine)
7. Data safety form (must match the privacy page)
8. Ads declaration: **no ads**
9. Privacy policy URL: `https://order-flow-v2.pages.dev/privacy`
10. Contact email that you actually read
11. App access: reviewer can use a test license key or “no login / enter this key”
12. Production release after review (can take days)

## Data safety answers (current product)

| Data | Collected? | Shared? | Why |
| --- | --- | --- | --- |
| Device or other IDs | Yes (random device ID + license key) | Only to Jathol license API | App functionality |
| Photos / media | No (menu photos stay on device) | No | |
| Location | Approximate may be used by Android for Wi‑Fi IP | No | App functionality |
| Advertising ID | No | No | |
| Financial / sales | No (stays on shop LAN) | No | |

Declare Android ID / device ID as a device identifier.

## Not for sideload APKs

Play needs a **release keystore** and an **AAB**. GitHub Actions currently attaches a debug-signed APK. Before first Play upload we must add a Play signing key (you keep the upload key; never commit the password).

## After Cloudflare Pages deploy

`/privacy` only works once this branch (or main) is deployed to Pages. Until then the in-app link 404s.
