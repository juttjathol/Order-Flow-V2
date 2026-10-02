# App Store — iOS Publish Checklist (2026)

> **Not for GitHub APK sideload.** This doc is the gate before you submit `order_flow.ipa` to App Store Connect. Apple rejects in 2026 for a missing `PrivacyInfo.xcprivacy` faster than for a crash.

## What Apple enforces in 2026

| Gate | Rule | Order Flow status |
|------|------|-------------------|
| **iOS 26 SDK** | Builds must be compiled with **iOS 26 SDK (Xcode 16+)** effective **28 Apr 2026**. Uploads with older SDK are blocked in App Store Connect. | CI must use `macos-15` + `xcode: 16.x`. `flutter create --platforms=ios` on CI pulls the right SDK. Local dev can stay on Xcode 15, but the *upload* needs 16. |
| **PrivacyInfo.xcprivacy** | Required since **1 May 2024** for every app + every third-party SDK that uses a *required-reason API*. Since iOS 19 (Spring 2026) **every** SDK needs its own manifest, no parent-app cover. | `flutter_app/ios/Runner/PrivacyInfo.xcprivacy` checked in (see below). Each `pod` (Firebase, etc.) must also ship its own — we list ours in `Podfile.lock` and verify on each `pod install`. |
| **Required-reason APIs** | `UserDefaults` `CA92.1`, `FileTimestamp` `C617.1`, `SystemBootTime` `35F9.1`, `DiskSpace` `E174.1`, `ActiveKeyboards` `54BD.1` — declared in `PrivacyInfo.xcprivacy`. Mismatched codes → `ITMS-91061`. | Declared in `flutter_app/ios/Runner/PrivacyInfo.xcprivacy` (see file, 5 categories). No tracking domains, `NSPrivacyTracking=false`. |
| **Privacy policy URL** | Must be live HTTPS, same host as Data Safety, in `App Information > Privacy Policy URL` + in-app `More → Privacy`. | `https://jathol.org/privacy` (mirrors `order-flow-v2.pages.dev/privacy`) — live static HTML, PDPA 2010, no geofence, no PDF. |
| **App Privacy labels** | App Store Connect → `App Privacy` — every `NSPrivacyCollectedDataType` must match `PrivacyInfo.xcprivacy` + policy. `DeviceID` + `ProductInteraction` for app-functionality, `Linked=false`, `Tracking=false`. | Declared in `PrivacyInfo.xcprivacy` (2 types). Labels in Connect must be filled before first upload. |
| **App Tracking Transparency (ATT)** | Required only if you touch **IDFA** or share IDs with data brokers. We set `NSUserTrackingUsageDescription` but do **not** call `requestTrackingAuthorization` — we don’t track. If you add ads/analytics that use IDFA, you must prompt with Apple’s wording before first IDFA read. | `Info.plist` has `NSUserTrackingUsageDescription` (“This identifier is not used for tracking…”) for completeness; `NSPrivacyTracking=false` in manifest. Reviewer sees no ATT prompt, which is correct for a non-tracking POS. |
| **AI consent (5.1.2 i)** | Since **13 Nov 2025**: if you send personal data to a third-party AI (OpenAI, etc.), you must show a consent screen naming the provider + data + revocation. | We don’t call any LLM. If you add menu-scan LLM in the future, gate it behind a consent screen per guideline. |
| **Support URL** | Must be a live, monitored URL in `App Information`. | `https://jathol.org/contact.html` + `contact@jathol.org` (replies within 24h, Mon–Sat GMT+8). |
| **Account deletion** | If app creates accounts, you must offer in-app deletion. Order Flow uses **license keys, not accounts** — no Apple ID, no Sign in with Apple, no deletion flow required. Document “No accounts” in Review Notes. | Review Notes: “App uses 16-char license key on Main, stations join via IP/QR, no Apple ID, no user accounts. Test with key `TEST-1111-1111-1111` or tap ‘Connect to Main’ on same Wi-Fi.” |

## Files checked in

```
flutter_app/ios/Runner/Info.plist                 ← usage strings for Camera, Photo, Location, Bluetooth, LocalNetwork; ITSAppUsesNonExemptEncryption=false; NSAllowsLocalNetworking=true
flutter_app/ios/Runner/PrivacyInfo.xcprivacy      ← tracking=false, 2 collected types, 5 required-reason APIs
flutter_app/ios/Podfile                           ← platform :ios, '15.0', flutter_ios_podfile_setup
```

`Runner.xcodeproj` and `Flutter/AppFrameworkInfo.plist` are **generated on CI** (`flutter create --platforms=ios --org=com.jathol --project-name=order_flow .` on `macos-15`). They are not hand-edited, so no merge conflicts. The two files above are the only hand-maintained iOS source.

## How to build the IPA (when you are ready)

```bash
# On a Mac with Xcode 16 + Flutter stable
cd flutter_app
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release --no-tree-shake-icons \
  --build-name=1.1.87 --build-number=86
# Or: flutter build ios --release
open build/ios/archive/Runner.xcarchive   # Organizer → Distribute → App Store Connect
```

If you don’t have a Mac, the `build-release.yml` iOS lane (to be added) does it on `macos-15` and attaches `Runner.ipa` as an artifact. You still need **Apple Developer Program** membership (USD 99/yr) + a distribution certificate + provisioning profile for `com.jathol.orderflow`. Those live in App Store Connect, not in git.

## Reviewer checklist (what Apple actually taps)

- [ ] Launch → **Jathol splash holds 5.4s** (logo 900ms + type 720ms + tagline 700ms + fade 600ms) — no blank screen before typing finishes. `app_controller.dart` `remain 5400ms`.
- [ ] On Main: License → Activate with `TEST-1111-1111-1111` → becomes Main, server on `:8787`.
- [ ] From another phone on same Wi-Fi: License → Connect to Main → `192.168.x.x:8787` → pick role (Manager PIN `1234` after you set it in stock).
- [ ] Camera → barcode scan (grant → scan) — no crash if denied.
- [ ] Bluetooth → printers sheet → shows `sys` / `lan` on iOS (Bluetooth via `nearby` entitlement, optional).
- [ ] More → Privacy policy → opens `https://jathol.org/privacy` in-app browser.
- [ ] No ATT prompt appears (correct, we don’t track). No crash on iPad (layout `LayoutBuilder`).
- [ ] Dark mode: text stays visible (`theme.dart` 14532d/FAF7F2 contrast).
- [ ] Slow 3G: license check 20s timeout + `offline_grace` banner, not a freeze.

## Common 2026 rejections and how we avoid them

| Rejection | How we pass |
|-----------|-------------|
| **ITMS-91061 Missing privacy manifest** | `PrivacyInfo.xcprivacy` in `Runner`, 5 reason codes, `NSPrivacyTracking=false`. |
| **Guideline 5.1.1 — privacy policy** | Live URL + in-app link + labels match manifest + policy. |
| **Guideline 2.1 — crashes** | `ErrorReporter` + Sentry stub, no `allowBackup` leak, no `usesCleartextTraffic` for public domains (only LAN). |
| **Guideline 4.0 — no account deletion** | Document “No accounts, license keys only” in Review Notes. |
| **ITMS-90426 Invalid Swift support / iOS SDK** | Build with Xcode 16 / iOS 26 SDK on `macos-15`. |

## Before you click “Submit for Review”

- [ ] Apple Developer Program paid + verified
- [ ] App record in App Store Connect: `com.jathol.orderflow`, `Order Flow`, `1.1.87 (87)`, `jathol.org`, `privacy`, `contact@jathol.org`
- [ ] App Privacy answers match `PrivacyInfo.xcprivacy` + `privacy.html` (Device ID → App Functionality, not linked, not tracking)
- [ ] Screenshots: iPhone 6.7" (1290×2796) + iPad 12.9" (2048×2732), at least 1 per size, no Android nav bar
- [ ] Test device + test key in **Review Notes** + demo account if you gate anything
- [ ] No `beta`, `test`, or `demo` in display name
- [ ] Build uploaded via Xcode Organizer or `xcrun altool`, processing green, no ITMS warnings
