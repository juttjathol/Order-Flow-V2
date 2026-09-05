# Order Flow — Session Handoff Prompt

Paste this at the start of a new Arena chat to continue work:

---

Continue my existing project: repo `juttjathol/Order-Flow-V2`, workspace `/home/user/Order-Flow-V2`.

**Current state (as of v1.1.59):**
- Flutter POS app: station printers, cash drawer, split payment, customer display, loyalty rewards, refunds, share receipt, confetti animation.
- v1.1.59 additions: QR table ordering & guest self-order web page (`/order` on the LAN), recipe costing & margins, wastage log, suppliers & purchase orders with receiving, insights (best sellers / slow movers / profit / staff), invoice label + tax reg no on receipts, and plan-gated license enforcement (Starter/Growth/Custom/Full + per-model access). StoreGuard enforces on Main and LanServer; legacy keys (no plan) keep everything on.
- SaaS dashboard now sets plan + business models + feature checklist per license key (`POST admin/licenses` accepts `plan/allowedModels/allowedFeatures`, plus `POST admin/licenses/:id/access`); D1 auto-migrates the three new `licenses` columns.
- SaaS admin dashboard (`cloudflare_dashboard/`) — mobile-first with bottom tab bar + card layout on phones. Lives at the Cloudflare Pages project `order-flow-v2` (production branch: `main`).
- Public website / user guide (`website/`) — at jathol.pages.dev (production branch: `main`). Guide at https://jathol.pages.dev/guide.
- APK download proxy at https://order-flow-v2.pages.dev/download (always latest release).

**Standing rules for every chat:**
1. Never touch or rewrite existing working features — every change must be additive.
2. Never delete branches, tags, or files without asking first.
3. Every app update: bump version in `flutter_app/pubspec.yaml` AND `flutter_app/lib/core/constants.dart`; update `website/public/guide.html` (EN + UR); update feature list in `website/public/index.html`; update `FALLBACK_TAG` in `website/functions/download.js`; commit → push → tag `vX.Y.Z` → wait for APK build to go green → open PR to `main` → merge (merge = last remote action in the session).
4. This platform closes GitHub access the moment a PR is merged. Do ALL GitHub work before the merge. Never merge early.
5. Verification scratch tags (`vX.Y.Z-rcN`) and any releases they auto-create are the agent's to clean up WITHOUT asking: delete them (`gh release delete <rc> --yes --cleanup-tag`, `git push origin --delete <rc tags>`, `git tag -d`) as soon as the final tag build is green — do not carry them into the next release. (Standing permission from the v1.1.59 session, 2026-09-05.)

**Last merged PR:** "1.1.59 — QR ordering, costing & purchasing, plan-gated licenses, pricing page" → `main`.

**Next version will be 1.1.60.**
