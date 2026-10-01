# Store assets — Play Store & App Store

This folder is the source of truth for listing graphics. The APK/AAB never contains these.

## Play Store (Google Play Console)

| File | Spec | Note |
|------|------|------|
| `icon-512.png` | 512×512 PNG, 32-bit, no alpha shadow | No Play logo, no device frame |
| `feature-graphic-1024x500.png` | 1024×500 PNG/JPG | No Play logo, keep text in safe zone (center 924×400) |
| `screenshots/phone-1-1080x1920.png` | 1080×1920 or 1080×2400 | ≥2 required, 8 max, show Light mode |
| `screenshots/phone-2-1080x1920.png` | same | e.g. Orders + Settings |
| `screenshots/tablet-1-2048x2732.png` | optional iPad | helps Discover ranking |

Export from Figma at 1× with `Order Flow` cream (#FAF7F2) + dark green (#102018) palette. Keep `Order Flow` wordmark centered.

## App Store (App Store Connect)

| File | Spec |
|------|------|
| `appstore-icon-1024.png` | 1024×1024 PNG, no alpha |
| `screenshots/iphone-6.7-1290x2796-1.png` | 1290×2796 |
| `screenshots/ipad-12.9-2048x2732-1.png` | 2048×2732 |

Generate after `flutter build ipa` on macOS 15 + Xcode 16 (iOS 26 SDK). Screenshots must be from the actual iOS build, not Android crops.

## How to use

1. Drop exports here, git add.
2. Upload to Play Console → Store listing → Graphics and to App Store Connect → Screenshots.
3. Verify `https://jathol.pages.dev/privacy` live before submitting — both stores fetch it.

No binaries are built from this folder. It is just documentation.
