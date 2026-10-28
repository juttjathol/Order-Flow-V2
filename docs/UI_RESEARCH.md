# UI research notes — v1.1.93 (Task: open-source POS patterns → design tunes)

Sources skimmed (open-source POS + POS-UI guidance):

- `Abody-Aho/restaurant-pos` (Flutter, Arabic-first) — split 70/30 menu grid +
  live receipt panel, horizontal category tabs, automatic **Best Seller**
  badges, big one-tap print.
- `evan361425/flutter-pos-system` — offline-first, responsive width bands,
  privacy-first (no remote PII) — matches our no-cloud-storage promise.
- POS-UI best practices (2026 roundups) — large touch targets, fewest taps
  per transaction, colors that *mean* something (green/red only as signals),
  home dashboard = 5–7 decision metrics, not a data wall.

What we already do well: 5-tab shell with decision-first home, live table
colors (free/busy/ready), big 40px+ primary buttons, RTL Urdu everywhere.

## Applied this release
- **Best-seller 🔥 badge** on the menu pick cards (web register grid + APK
  order picker): top 3 by qty paid today. Same position (card corner) on both
  surfaces so staff learn it once.
- Guided tour now points AT the controls (v2) rather than centring bubbles —
  "tour targets the button" is the number-one force for fewer training taps.

## Parked (future)
- 70/30 landscape register split on tablet web (APK has the tablet rail).
- Skeleton shimmer on data loads (currently instant/blank).
- Haptic tick on add-to-ticket for Android (APK buzzes on ticket only).
