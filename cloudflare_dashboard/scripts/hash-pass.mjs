#!/usr/bin/env node
// Generate ADMIN_PASSWORD_HASH for the Order Flow dashboard.
//   node scripts/hash-pass.mjs 'the admin password'
// then set it as a Pages env secret:  wrangler pages secret put ADMIN_PASSWORD_HASH
// Cloudflare Workers PBKDF2 is capped at 100000 iterations — hashes made with
// 250000 must be regenerated.
const pw = process.argv[2] || await new Promise((res) => {
  process.stdout.write("Admin password: ");
  let d = ""; process.stdin.on("data", (c) => { d += c; if (d.includes("\n")) res(d.trim()); });
});
if (!pw) { console.error("empty password"); process.exit(1); }
const iterations = 100000;
const salt = globalThis.crypto.getRandomValues(new Uint8Array(16));
const saltHex = [...salt].map((b) => b.toString(16).padStart(2, "0")).join("");
const km = await globalThis.crypto.subtle.importKey("raw", new TextEncoder().encode(pw), "PBKDF2", false, ["deriveBits"]);
const bits = await globalThis.crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations, hash: "SHA-256" }, km, 256);
const hashHex = [...new Uint8Array(bits)].map((b) => b.toString(16).padStart(2, "0")).join("");
console.log(`ADMIN_PASSWORD_HASH=pbkdf2-sha256$${iterations}$${saltHex}$${hashHex}`);
