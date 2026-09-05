# Order Flow — Session Handoff Prompt

Paste this at the start of a new Arena chat to continue work:

---

Continue my existing project: repo `juttjathol/Order-Flow-V2`, workspace `/home/user/Order-Flow-V2`.

**Current state (as of v1.1.60):**
- Flutter POS app: station printers, cash drawer, split payment, customer display, loyalty rewards, refunds, share receipt, confetti animation.
- v1.1.59 additions: QR table ordering & guest self-order web page (`/order` on the LAN), recipe costing & margins, wastage log, suppliers & purchase orders with receiving, insights (best sellers / slow movers / profit / staff), invoice label + tax reg no on receipts, and plan-gated license enforcement (Starter/Growth/Custom/Full + per-model access). StoreGuard enforces on Main and LanServer; legacy keys (no plan) keep everything on.
- SaaS dashboard now sets plan + business models + feature checklist per license key (`POST admin/licenses` accepts `plan/allowedModels/allowedFeatures`, plus `POST admin/licenses/:id/access`); D1 auto-migrates the three new `licenses` columns.
- SaaS admin dashboard (`cloudflare_dashboard/`) — mobile-first with bottom tab bar + card layout on phones. Lives at the Cloudflare Pages project `order-flow-v2` (production branch: `main` — NOTE: during the v1.1.60 session the user temporarily flipped the *website's* Pages production branch to `arena/01a06fe3-order-flow-v2` so unmerged work previews live; restore it to `main` in the CF dashboard after the PR merges).
- Public website / user guide (`website/`) — at jathol.pages.dev (production branch: `main`). Guide at https://jathol.pages.dev/guide.
- APK download proxy at https://order-flow-v2.pages.dev/download (always latest release).
- v1.1.60 additions: **cloud networking** (custom plan) — Main opens an encrypted relay room on the Jathol Pages project (Cloudflare Pages Functions + D1 as a *transit only*: AES-GCM end-to-end between devices, rows deleted on read / expired in ~30 min / capped, room wiped on close). Stations join by pairing code and keep working on mobile data while the shop Wi-Fi is down; commands ride the existing offline queue. **Shop data is never backed up to the cloud — it lives on Main.** Also: QR kitchen fire mode (`qrFireOn` 'pay' default / 'order'), QR tickets now fire + print with the table number when paid at the counter; **branded guest page** (`qr_branding` custom feature — QrBrand editor in the QR sheet, full professional rewrite of the guest page with animations, skeletons, cart drawer, EN/UR); new feature keys `cloud_sync` + `qr_branding` synced in the dashboard (growth preset keeps the original 13; starter keeps none; custom/full get all 15). Guide §25–26 + §20 updated (EN+UR); website gained cloud/branding cards.

**Standing rules for every chat:**
1. Never touch or rewrite existing working features — every change must be additive.
2. Never delete branches, tags, or files without asking first.
3. Every app update: bump version in `flutter_app/pubspec.yaml` AND `flutter_app/lib/core/constants.dart`; update `website/public/guide.html` (EN + UR); update feature list in `website/public/index.html`; update `FALLBACK_TAG` in `website/functions/download.js`; commit → push → tag `vX.Y.Z` → wait for APK build to go green → open PR to `main` → merge (merge = last remote action in the session).
4. This platform closes GitHub access the moment a PR is merged. Do ALL GitHub work before the merge. Never merge early.
5. Verification scratch tags (`vX.Y.Z-rcN`) and any releases they auto-create are the agent's to clean up WITHOUT asking: delete them (`gh release delete <rc> --yes --cleanup-tag`, `git push origin --delete <rc tags>`, `git tag -d`) as soon as the final tag build is green — do not carry them into the next release. (Standing permission from the v1.1.59 session, 2026-09-05.)

**Open PR:** #7 — `arena/01a06fe3-order-flow-v2` → `main` — carries v1.1.59 (app + dashboard + website), the website currency engine, the hero CSS fix, the replaceState entitlements clamp, **and all v1.1.60 work (release tag v1.1.60 will point at the final branch commit; merge only after explicit owner approval)**. The *last merged* release PR was v1.1.57-era.

**Next version will be 1.1.60.**
