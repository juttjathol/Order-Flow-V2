// Shared security helpers for Order Flow Pages Functions (import-only module;
// files starting with "_" are never routed by Cloudflare Pages).

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

export function ipOf(request) {
  return (request.headers.get("cf-connecting-ip") || request.headers.get("x-forwarded-for") || "na")
    .split(",")[0].trim();
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

// PBKDF2-SHA256 (Web Crypto) — works in Workers AND in node for the helper
// script that generates hashes.
export async function pbkdf2Hex(password, saltHex, iterations) {
  const km = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: hexToBytes(saltHex), iterations, hash: "SHA-256" },
    km, 256,
  );
  return bytesToHex(bits);
}
