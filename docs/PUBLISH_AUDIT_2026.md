# Publish audit — 2026-10-01 (splash + Play + App Store)

> **Second audit** after splash hold fix and store hardening. This is the gate before `git tag v*` triggers `build-release.yml` (APK + AAB + Windows).

## 1) Splash hold — FIXED

**Bug:** `app_controller.dart:220` used `Duration(1000)` while `gate_screens.dart` animation runs ~5400 ms. `router.dart:34-41` holds `/splash` while `snap.ready==false`, but `ready` flipped at 1s so the typed tagline (`_tagline 700 ms @ 2520 ms`) and fadeOut (`600 ms @ 4800 ms`) never showed — blank cut.

**Fix:** `flutter_app/lib/state/app_controller.dart` `remain 1000 → 5400 ms` with timeline comment. `bootstrap()` now:

```
started = now
... loadSession/loadStore ...
remain = 5400 - elapsed
if remain>0 delay(remain)
state.ready = true  → router leaves /splash
```

**Timeline (verified `gate_screens.dart`):** `kBrandName='Jathol'` (6 chars)

| t | Event |
|---|---|
| 200 ms | `_entrance.forward()` 900 ms cubic(0.34,1.56,0.64,1) → ends ~1100 ms |
| 1100 ms | `_typeDelay`, cursor on, `_blink 700 ms` |
| 1100→1820 ms | `6 × _typeSpeed 120 ms = 720 ms` typing `Jathol` |
| 1820+700 = 2520 ms | `_cursorOff`, `_showTagline`, `_tagline 700 ms` → ends ~3220 ms |
| 4800 ms | `_fadeOut 600 ms` → ends **5400 ms** |
| 5400 ms | `bootstrap` sets `ready:true`, `router.dart` redirects |

**Guard:** No other code touched. Only `Duration` + comment. `flutter analyze` clean, sideload APK boots and holds full logo→type→tagline→fade.

## 2) Google Play — 2026 compliant

| Check | Status | File |
|-------|--------|------|
| `compileSdk 36` / `targetSdk 36` / `Java 17` / `ndkVersion flutter.ndkVersion` | ✅ | `flutter_app/android/app/build.gradle.kts`, `scripts/patch_android.py` forces 36 |
| `applicationId com.jathol.orderflow`, `minSdk 23`, `namespace` | ✅ | same |
| `usesCleartextTraffic=false` + `networkSecurityConfig` base `false`, LAN-only `localhost/127.0.0.1/10.0.0.0/192.168.0.0/10.0.2.2` | ✅ | `AndroidManifest.xml`, `res/xml/network_security_config.xml` |
| `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules=@xml/backup_rules` (excludes `sharedpref/database/file` for both backup + transfer) | ✅ | `AndroidManifest.xml`, `res/xml/backup_rules.xml` (new) |
| Permissions: `camera`/`bluetooth` `required=false`, `BLUETOOTH_SCAN neverForLocation`, `FOREGROUND_SERVICE_DATA_SYNC`, no `AD_ID` (`google_analytics_adid_collection_enabled=false`) | ✅ | `AndroidManifest.xml` |
| `enableOnBackInvokedCallback=true`, `proguard-rules.pro` keeps `com.google.mlkit.**` | ✅ | same |
| **AAB** produced via `flutter build appbundle --release --no-tree-shake-icons` → `build/app/outputs/bundle/release/app-release.aab` + log + artifact `app-aab` + Release attach | ✅ | `.github/workflows/build-release.yml` patched (3 steps + `publish-release` downloads `app-aab` continue-on-error) |
| Privacy policy live HTTPS, non-geofenced, non-PDF, in listing + in-app `More→Privacy` (`kPrivacyUrl https://jathol.pages.dev/privacy`) | ✅ | `cloudflare_dashboard/public/privacy.html` 25 Aug 2026 + `website/public/privacy.html`, mirror `order-flow-v2.pages.dev/privacy` |
| Data Safety answers match APK + policy (Device ID → App functionality, encrypted, deletable; no Ads, no analytics; `Android ID = Device ID`) | ✅ | `docs/PLAY_STORE.md` table updated 2026-10-01 |
| Store graphics placeholder (`store_assets/` 512 icon + 1024×500 feature + screenshots) | ✅ docs | `store_assets/README.md` + `screenshots/` |
| 64-bit ABIs default by Flutter | ✅ | — |
| Signing: sideload `sideload/upload.p12` (JatholOrderFlowSideload) reused for AAB; Play upload key to be created separately (`play-upload.jks` not committed) | ✅ docs | `docs/PLAY_STORE.md` instructions + `SECURITY.md` |

**Remaining Play manual:** Developer account verification, 14-day closed test (personal), fill Data Safety exactly as table, upload AAB with Play App Signing, IARC rating, target 18+/business, reviewer key `TEST-1111-1111-1111`.

## 3) Apple App Store — 2026 compliant

| Check | Status | File |
|-------|--------|------|
| **iOS 26 SDK** (Xcode 16 on `macos-15`, deadline 28 Apr 2026) | ✅ doc | `docs/APP_STORE.md` — CI must use `macos-15` |
| **`PrivacyInfo.xcprivacy`** (`NSPrivacyTracking false`, `CollectedDataTypes` DeviceID + ProductInteraction AppFunctionality not linked/not tracking, `AccessedAPITypes` UserDefaults CA92.1, FileTimestamp C617.1, SystemBootTime 35F9.1, DiskSpace E174.1, ActiveKeyboards 54BD.1) | ✅ | `flutter_app/ios/Runner/PrivacyInfo.xcprivacy` (new) |
| **`Info.plist`** usage strings: Camera, Photo, LocationWhenInUse, BluetoothAlways+Peripheral, LocalNetwork, UserTracking + `ITSAppUsesNonExemptEncryption=false` + `NSAllowsLocalNetworking=true` + `NSExceptionDomains localhost` | ✅ | `flutter_app/ios/Runner/Info.plist` (new) |
| `Podfile` `platform :ios, '15.0'`, `flutter_ios_podfile_setup` (generates `Runner.xcodeproj` on CI via `flutter create --platforms=ios`) | ✅ | `flutter_app/ios/Podfile` (new) |
| Support URL `https://jathol.org/contact.html`, email `contact@jathol.org` | ✅ | `docs/APP_STORE.md` + `SECURITY.md` |
| No custom encryption → `ITSAppUsesNonExemptEncryption false` | ✅ | `Info.plist` |
| No accounts → document “license key, no Apple ID” in Review Notes | ✅ docs | `docs/APP_STORE.md` |

**Remaining App Store manual:** Apple Developer Program, `com.jathol.orderflow` App record, App Privacy labels matching manifest, screenshots 6.7" 1290×2796 + 12.9" 2048×2732, build with `flutter build ipa` on Xcode 16, reviewer notes with Wi-Fi test.

## 4) Additive-only guard

No features removed. Changed only:

- `app_controller.dart` `1000→5400` + comment
- `network_security_config.xml` `base true→false` + `127.0.0.1`/`10.0.2.2`
- `AndroidManifest.xml` `usesCleartextTraffic true→false` + `fullBackupContent` + `dataExtractionRules`
- `backup_rules.xml` new (excludes)
- `build-release.yml` +AAB
- `ios/Runner/PrivacyInfo.xcprivacy`, `Info.plist`, `Podfile` new
- `docs/PLAY_STORE.md` 2026 rewrite, `docs/APP_STORE.md` new, `store_assets/` new

All 15 feature keys frozen, `kLicenseRequireSig` untouched, `.env` not committed, palette cream/dark-green preserved.

## 5) Builds

After this audit, trigger:

```bash
git tag v1.1.86  # or next RC
git push origin v1.1.86
# CI builds: app-release.apk + app-release.aab + order-flow-windows.zip
# iOS: on mac → flutter build ipa --release --no-tree-shake-icons
```

Verify `dist/app-release.apk`, `dist/app-release.aab`, `dist/order-flow-windows.zip` attached to Release, `/privacy` returns 200, splash holds 5.4s on cold launch.

---
Audit performed 2026-10-01 MYT — ready for store submission after manual Play/App Store listing.
