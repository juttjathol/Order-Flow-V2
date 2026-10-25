# Security policy

Order Flow runs the till in real shops, so security reports are treated as urgent.

## Reporting a vulnerability

**Please do not open a public GitHub issue for a security problem.**

Email **contact@jathol.org** with:

* what you found, and the exact version (`Order Flow → More → About`, or the window
  title on Windows: `Order Flow X.Y.Z`);
* the smallest possible reproduction — request, payload, or steps on a device;
* whether you tested it against a live shop (please don't; a local Main + one station is
  enough);
* how you would like to be credited, if at all.

We aim to acknowledge within **24 hours** and to ship a fix, or a documented mitigation,
as a new release tag. Release history is public, so fixes land quickly and visibly.

## Threat model (what is in scope)

| Surface | Trust boundary | In scope |
|---------|----------------|----------|
| LAN server on Main (`:8787`) | Anyone associated to the shop Wi-Fi | Privilege escalation between roles, unauthenticated reads/writes, PIN or key disclosure, XSS in the bundled web console, resource exhaustion |
| Guest QR ordering page | Any customer on the Wi-Fi, no credentials | Price manipulation, order injection, flooding, cross-site tricks against the cashier console |
| Cloud relay (`order-flow-v2.pages.dev/api/cloud`) | Internet | Room isolation, ciphertext confidentiality, replay/flood, quota exhaustion |
| License API + admin dashboard | Internet | Auth bypass, session theft, key enumeration, plan/feature tampering, stored XSS |
| Android / Windows packaging | Device | Backup/extraction of shop data, exported components, cleartext policy |

Out of scope: attacks that need physical access to an unlocked Main device, social
engineering of shop staff, or a compromised Cloudflare/GitHub account.

## Design notes worth knowing before you dig

* **Shop data never lives in the cloud.** The relay is transit only: AES-GCM
  end-to-end between devices, rows deleted once every device has read past them, hard
  expiry around 30 minutes, room wiped on close, idle rooms swept after 24 h. There is
  no list or query endpoint — a room is addressable only by its 256-bit random id.
* **LAN tokens** are `HMAC-SHA256(deviceId|role)` under a per-process random secret,
  compared in constant time, and roles are bound server-side: a station cannot claim to
  be `main` or `manager`.
* **Prices are computed on Main.** The guest page sends product ids, quantities and
  modifier ids — never amounts.
* **License enforcement** locks only on `not_found` / `revoked` / `expired`. Network
  errors, rate limits and signature hiccups fall back to a 48-hour offline grace period,
  so a flaky link can never lock a trading shop out.
* **Admin sessions** are HMAC tokens keyed by `ADMIN_SECRET` (never by the password),
  stored in `sessionStorage`, with PBKDF2-SHA256 password hashing and per-IP D1 rate
  limits on login and validation.

## Supported versions

Only the latest release tag is supported. The APK and the Windows ZIP are rebuilt from
`main` for every release, and the download proxy
(`https://jathol.org/download`) always serves the newest one.

## Past audits

* [`docs/SECURITY_AUDIT_2026-09-28.md`](docs/SECURITY_AUDIT_2026-09-28.md) — full
  findings list with severity, evidence and fix status.
* `docs/HANDOFF.md` → *v1.1.73 — security harden* — the earlier server/app hardening
  pass (S1–S9, A1–A6).
