# Order-Flow BT printing & release memory — session notes (v1.1.68 → v1.1.70)

Kept so a continuation session never re-investigates closed problems.

## Shipped & field-verified
- **v1.1.68** universal Bluetooth print (held RFCOMM socket, insecure-first + reflection fallback, BLE write path, error passthrough). Closed — do not re-fix.
- **v1.1.69** (tag bfeac20): every print button routed via `prefer:deviceLocalPrinter()`; station `conn.forget` when address/paper/transport changes; paper-size chips Auto/58/76/80/100 (`PrintService.dotsForMm`: 72|76→512, 80→576, 100→720, _→384); Focus-Point receipt layout (dashed rules, Item/Qty/Amount, big Total, PAID BY, centered footer); logo alpha-composite + auto-invert; Pay & Print label + pre-bill (`receipt(preBill:true)`). Held-socket design: success path deliberately does NOT close the socket (single-connection printers).
- **v1.1.70** (tag 27a14dc, run 34942197122 green, APK 122,114,308 B, release = Latest, rc releases+tags deleted same session):
  1. Receipt: shop name ONE line (double-size only if `len <= (chars-6)~/2`), logo `_raster(..., scale: 0.8)`, `Ticket #` double-hash fixed (nextTicket() already includes '#'; guard with startsWith), ticket+time same row (time right-pad), 'Amount' column header, blank-line breathing (b.text('')) under contact block/before totals/above footer; kitchen keeps separate big ticket+time lines.
  2. Per-slip footer: `SlipTemplate.footer` (default '', persisted via toJson/fromJson/copy), `_slipEditor` gets Slip footer field (+ slip_footer/slip_footer_hint l10n EN+UR), print uses `slip.footer || (kitchen ? '' : p.footer)`; more_screen preview + receiptText use it too.
  3. QR page (assets/web/order.html): `money()` rewritten — `menu.currencyPrefix` is a BOOL (bug was `"true"+amount`), symbol from `menu.currency`, thousands separators, suffix when prefix=false; `imgAttr()` sniffs /9j/→jpeg, iVBOR→png, R0lG→gif, UklGR→webp (server data was hardcoded png MIME); ok-card shows `N × total` via `.ok-sum` (d.total from /order/submit).
  4. Split-pay + split-lines sheets now scroll (ConstrainedBox 0.92h−viewInsets + SingleChildScrollView in pay sheet; SCV in _split).
  5. Contrast/responsive: OfColors.muted #628274, mute() dark→#A9C6B7 light→#46564F; textTheme gained bodySmall/titleSmall/labelLarge/Medium/Small with explicit colors (Material defaults were invisible on dark); snackbar themed; app.dart MediaQuery builder clamps textScaler 0.9–1.35.
  6. Menu import: `_consumePrice` scan-back ≤4 tokens with Match carried out of loop (currency-word merge shifts idx — keep pm Match, don't re-match at shifted token!), trailing unit-junk after price dropped; if ZERO priced items → fallback lists readable ≤6-word rows with price:null; `menu_import` `_Draft(include: it.price != null)`; final filter only `name.length<2` (never drop price-less). 9 unit tests in test/menu_parser_test.dart must keep passing.
  7. flutter_animate `">=1.0.0 <4.0.0"` in pubspec — NOTE: 1.x only ever had 1.0.0; `^1.0.8` broke rc1 pub get (version solving). Used for home-screen stat stagger + server card; API `.animate(delay:(i*70).ms).fadeIn().slideY()`.
  8. Guide updated: banner, §9 two new bullets EN+UR, QR bullet EN+UR, Menu-scan bullet EN+UR.

## v1.1.71 (dc89f1f + fix commit; tag 'v1.1.71' on 6f0? tip after rc2 — run 34996980908 green, APK 122,179,852 B, Latest ✓, rc2 cleaned)
- QR "order doesn't push" root cause = CSS: .cartbar centered with left:50%+translateX(-50%) but @keyframes barRise ends transform:none with 'both' fill → wipe of centering → bar+Review&send half off-screen. Fixed via left:12px/right:12px + max-width + margin auto (no transform dependence).
- PDF menu import: pdfx renders PNG on TRANSPARENT canvas by default (docs confirm backgroundColor '#ffffff' fixes) → ML Kit saw blank pages. Added backgroundColor to page.render.
- try/catch patch pitfall: local vars (n, s) declared inside try went out of scope for code after the catch → rc1 compile error. Declare accumulators BEFORE try; keep everything referencing them inside.
- pdfx latest render() signature (pub docs): {required double width, required double height, format=jpeg, String? backgroundColor, Rect? cropRect, int quality=100, bool forPrint, removeTempFile} — backgroundColor exists ✓.
- Log retrieval that WORKED: gh api actions/jobs/$JOB/logs prints presigned blob URL on stderr (curl/urllib blocked!) → fetch_page(that blob URL, chunkIndex=N) chunk-by-chunk; do NOT reuse the OSS proxy URL from a previous result (signature breaks); blob URL valid ~10 min; 6 chunks total, errors near chunk 4.
- .git re-provision struck AGAIN mid-commit (commit landed on old base 143f23b while remote at 27a14dc): recovery = save commit hash, fetch+reset --hard FETCH_HEAD, git checkout $MINE -- . , re-commit (diff auto-shrinks to real changes). Verify `git status --porcelain` after checkout lists ONLY intended files.

## Standing rules (user)
- Additive-only edits; change only what was asked. l10n EN+UR parity (CI test scans `.t('key')` literals — both maps must contain every used key; when inserting lines after `'slip_heading'` style anchors, mind trailing commas!).
- Full ritual each version: pubspec version → kAppVersion → FALLBACK_TAG in 3× download.js (website/functions, root functions, cloudflare_dashboard) → commit → push branch → tag vX-rc1 → `gh run watch <id> --exit-status` (~8.5 min) → retag vX on tip → verify `gh release view vX --json assets` (field isLatest does NOT exist in this gh) → **delete rc release + rc tags local+remote** → fetch_page `https://order-flow-v2.pages.dev/download?meta=1` (works again 2026-09-15).
- No printer-name gating anywhere.
- No local Flutter SDK in sandbox — verify via CI; python anchor patches with assert count; can't run flutter test/analyze locally; node --check works for order.html script blocks; trace parser changes against test/menu_parser_test.dart by hand.

## Gotchas
- `.git` re-provisioning breaks branches: always `git ls-remote origin arena/01a06fe3-order-flow-v2` vs HEAD before committing; recover with `git fetch origin <branch> && git reset --hard FETCH_HEAD`.
- GH Actions job logs unreachable (TLS/EOF to blob hosts, gh log endpoints flake; fetch_page mangles presigned URLs) — when pub get fails, suspect the dependency constraint, verify against pub.dev API via fetch_page (public URLs work).
- l10n map insertion by regex anchors: count EN/UR occurrences, insert from last match backwards.
