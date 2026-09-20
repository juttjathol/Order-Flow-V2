// Shared security helpers for Order Flow Pages Functions (import-only module;
// files starting with "_" are never routed by Cloudflare Pages).

export const PBKDF2_MAX_ITERS = 100000;

// Baseline hardening headers for every API response.
export function sec() {
  return {
    "X-Content-Type-Options": "nosniff",
    "X-Robots-Tag": "noindex, nofollow",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store",
  };
}

// Fixed-window throttle per isolate (good enough to stop scripts hammering;
// Cloudflare's network-level shielding handles volumetric abuse).
const wins = new Map();
export function throttle(key, max, windowMs = 60000) {
  const now = Date.now();
  let a = wins.get(key);
  if (!a) { a = []; wins.set(key, a); }
  a.push(now);
  while (a.length && now - a[0] > windowMs) a.shift();
  if (wins.size > 5000) {
    for (const [k, v] of wins) if (!v.length || now - v[v.length - 1] > 10 * windowMs) wins.delete(k);
  }
  return a.length > max; // true → over limit
}

// Trust Cloudflare's connecting IP only. x-forwarded-for is attacker-controlled.
export function ipOf(request) {
  const v = String(request.headers.get("cf-connecting-ip") || "").trim();
  return v.split(",")[0].trim() || "na";
}

// CORS: off by default. Same-origin dashboard needs nothing; cross-origin is
// allowed only for origins explicitly listed in ALLOWED_ORIGINS (comma-sep).
export function corsFor(env, request) {
  const out = {};
  const origin = request.headers.get("origin") || "";
  const allow = String(env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
  if (origin && allow.includes(origin)) {
    out["Access-Control-Allow-Origin"] = origin;
    out["Vary"] = "Origin";
  }
  return out;
}

const enc = new TextEncoder();
export function bytesToHex(buf) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
export function hexToBytes(hexStr) {
  const out = new Uint8Array(hexStr.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hexStr.slice(i * 2, i * 2 + 2), 16);
  return out;
}

// Constant-time compare of two strings via digest — no early exit on mismatch.
export async function safeEqual(a, b) {
  const ha = new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(String(a))));
  const hb = new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(String(b))));
  let d = 0;
  for (let i = 0; i < ha.length; i++) d |= ha[i] ^ hb[i];
  return d === 0;
}

// PBKDF2-SHA256. Workers cap iterations at 100000 — clamp so login cannot 500.
export async function pbkdf2Hex(password, saltHex, iterations) {
  const iters = Math.min(Math.max(Number(iterations) || 0, 1), PBKDF2_MAX_ITERS);
  const km = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: hexToBytes(saltHex), iterations: iters, hash: "SHA-256" },
    km, 256,
  );
  return bytesToHex(bits);
}

let rateSchemaChecked = false;
export async function ensureRateLimits(db) {
  if (rateSchemaChecked || !db) return;
  try {
    await db.prepare(
      `CREATE TABLE IF NOT EXISTS rate_limits (
        k TEXT NOT NULL,
        w INTEGER NOT NULL,
        n INTEGER NOT NULL,
        PRIMARY KEY (k, w)
      )`,
    ).run();
    rateSchemaChecked = true;
  } catch {}
}

// D1 fixed-window limiter. Returns true when over limit. Fail-open on DB errors.
export async function d1Limit(db, key, max, windowMs) {
  if (!db) return false;
  await ensureRateLimits(db);
  const w = Math.floor(Date.now() / windowMs);
  try {
    await db.prepare("DELETE FROM rate_limits WHERE w < ?").bind(w - 3).run();
  } catch {}
  try {
    await db.prepare(
      "INSERT INTO rate_limits (k, w, n) VALUES (?, ?, 1) ON CONFLICT(k, w) DO UPDATE SET n = n + 1",
    ).bind(key, w).run();
    const row = await db.prepare("SELECT n FROM rate_limits WHERE k = ? AND w = ?").bind(key, w).first();
    return Number(row?.n || 0) > max;
  } catch {
    return false;
  }
}

export function licenseCanonical({
  licenseKey, deviceId, status, expiresAt, plan, features, models, signedAt, nonce,
}) {
  const f = [...(features || [])].map(String).sort().join(",");
  const m = [...(models || [])].map(String).sort().join(",");
  return `v1|${licenseKey}|${deviceId}|${status}|${expiresAt || ""}|${plan || ""}|${f}|${m}|${signedAt}|${nonce || ""}`;
}

export function publicApkRelease(release, asset) {
  if (!release || release.draft || release.prerelease) return false;
  if (/-rc\d*/i.test(String(release.tag_name || ""))) return false;
  return String(asset?.name || "") === "app-release.apk";
}
