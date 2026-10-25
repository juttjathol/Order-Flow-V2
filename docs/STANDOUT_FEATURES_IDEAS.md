# Standout Features — ideas to make Order Flow unforgettable

> **Goal:** features that a shop owner remembers after a 3-day trial and that no ₹79 POS nearby offers. All are additive, offline-first, and can ship as **Customize add-ons** so Starter stays simple.

## How we chose them
- **Demo-able in 30 seconds** — a visitor sees the magic before the kettle boils.
- **Offline-first** — works on LAN even when the internet is down.
- **Revenue or time saved** — either more sales or fewer steps per ticket.
- **No new hardware** — uses the phone/tablet the shop already has.

---

### 1) **Live Table Busy-Clocks + Heatmap (ship: v1.1.88)**
- **What:** Every occupied table shows `mm:ss` busy time, turns amber at 25m, red at 45m. Floor map can toggle a **heatmap** (darker = longer). One tap filters “Busy >30m”.
- **Why it stands out:** No POS shows *how long* a table has been busy at a glance. Managers spot stuck tables without walking the floor.
- **Tech:** `_FloorClock` already drives per-second tick; add `Color.lerp` by duration and a `CustomPainter` heat overlay. Zero network.
- **Plan:** Starter.

### 2) **Voice Add-to-Cart (ship: v1.1.90)**
- **What:** Hold mic on the order screen, say “two chicken biryani extra spice” → items appear, spice modifier auto-ticked. Urdu + English. Works offline via on-device `speech_to_text`.
- **Why:** Waiters with hands full, loud kitchens — voice is faster than tapping.
- **Tech:** `speech_to_text` (on-device) + simple `MenuProduct.name` fuzzy match. No cloud LLM, no audio stored.
- **Plan:** Customize (needs Mic permission).

### 3) **Smart Upsell Nudge (ship: v1.1.89)**
- **What:** When a ticket has `Biryani` and no `Raita`, a gentle chip “Add raita? +Rs 80 — 1 tap” slides in. Rules are 5 editable pairs (e.g., `burger → fries`, `chai → biscuit`). Tracks extra revenue.
- **Why:** Directly lifts average ticket; shop sees ₹₹₹ in reports.
- **Tech:** Pure rule engine on `order.lines`, no ML. `flutter_animate` chip. Report: `upsell_added`.
- **Plan:** Starter.

### 4) **One-Tap Seat-Split (ship: v1.1.88)**
- **What:** Split a table’s bill by seat (1..8). Each seat gets its own mini-ticket, can pay separately (cash/card), reprint individually. Animated seat cards.
- **Why:** Groups hate awkward splitting; this is 3 taps vs. mental maths.
- **Tech:** Extends existing `evenSplit` + `split_payment`; new `SeatSplit` model, no extra hardware.
- **Plan:** Starter.

### 5) **Kitchen Load Balancer (ship: v1.1.91)**
- **What:** When two kitchen stations are online, orders auto-route to the station with fewer open tickets (or by course: grill vs. fry). Station header shows “3 / 5 / 2” load.
- **Why:** Kitchens stay calm during rush; no manual drag.
- **Tech:** `kitchenTarget` already picks per-station printers; add `load = openOrders.where(stationId).length` and pick min.
- **Plan:** Customize (needs multi_terminal).

### 6) **Wastage Forecaster (ship: v1.1.92)**
- **What:** “You normally waste 3.2 kg chicken on Mondays — today you have 5 kg on hand. Suggest: push chicken tikka.” Card on the Stock screen, uses last 8 weeks.
- **Why:** Saves waste money; feels like an AI without the AI cost.
- **Tech:** `waste` + `orders` history → simple moving average. No internet. Shown as `OfCard animate`.
- **Plan:** Customize (needs wastage + recipe_costing).

### 7) **Offline QR Pay Stub (ship: v1.1.89)**
- **What:** Every receipt prints a QR that encodes `{ticketNo, total, shopId}`. Customer scans later on any phone → opens `/receipt/verify` which proves the bill even though the shop was offline when printed. No payment inside, just verifiable stub.
- **Why:** Stops “fake receipt” disputes; works completely offline (QR is just data, verification is online-later).
- **Tech:** `qr_flutter` already in pubspec; encode JSON + `HMAC` with shop secret. Verification endpoint is static.
- **Plan:** Starter.

### 8) **Regular Radar — privacy-friendly (ship: v1.1.93)**
- **What:** Opt-in: when a phone number repeats ≥3 times, the customer chip shows “Regular — 4 visits, last: Chicken Karahi”. No photo, no ID. Staff can greet by name.
- **Why:** Personal touch without creepy tracking; builds loyalty.
- **Tech:** `ShopCustomer` already stores `phone`; just count `orders.where(phone).length`. Consent toggle in Customers.
- **Plan:** Starter (needs loyalty).

### 9) **WhatsApp Broadcast Offers (ship: v1.1.90)**
- **What:** From More → Customers → “Send offer” → picks a broadcast template (“20% off biryani this weekend”) which opens a pre-filled WhatsApp to selected customers (one draft per customer, user taps Send). No bulk spam API, just drafts.
- **Why:** Direct revenue from existing customers, no new tool.
- **Tech:** `url_launcher` `wa.me` with text, reuses `kLicenseWhatsAppUrl` pattern. Respects consent.
- **Plan:** Customize.

### 10) **Magic 86 Shake (ship: v1.1.88)**
- **What:** Shake the phone on the Menu screen to instantly see only 86’d items; shake again to clear. Haptic + confetti when all 86 cleared.
- **Why:** Delightful, memorable, and solves a real “where is the 86?” walk.
- **Tech:** `sensors_plus` shake detector + existing `eightySix` logic + `confetti.dart`.
- **Plan:** Starter.

---

## Ranking for next sprint

| Priority | Feature | Effort | Revenue signal |
|----------|---------|--------|----------------|
| P0 | Busy-clocks heatmap | S | Time saved |
| P0 | Smart Upsell Nudge | S | +3–7% ticket |
| P1 | Seat-Split | M | happier groups |
| P1 | Offline QR Pay Stub | S | trust |
| P1 | Magic 86 Shake | S | delight |
| P2 | Voice Add-to-Cart | M | speed |
| P2 | WhatsApp Offers | M | repeat sales |
| P2 | Kitchen Load Balancer | M | kitchen calm |
| P3 | Wastage Forecaster | M | waste saved |
| P3 | Regular Radar | S | loyalty |

*All can be built with today’s stack: `flutter_animate`, `sensors_plus`/`speech_to_text`, `qr_flutter`, `fl_chart`, no new backend.*

## How to ship one as a demo this week
Pick **Smart Upsell Nudge** — add a `suggestPair` list in `BillProfile`, a `UpsellChip` widget in `order_screen.dart` that watches `order.lines`, and a report counter. It’s 1 model, 1 widget, 1 gate — demo-able in an afternoon and immediately monetizable as a `Starter` win.
