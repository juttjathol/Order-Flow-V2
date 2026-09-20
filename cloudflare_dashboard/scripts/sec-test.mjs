#!/usr/bin/env node
import assert from "node:assert/strict";
import { generateKeyPairSync, sign as nodeSign, verify as nodeVerify } from "node:crypto";
import {
  corsFor, ipOf, licenseCanonical, pbkdf2Hex, PBKDF2_MAX_ITERS, publicApkRelease, throttle,
} from "../functions/_security.js";

function hdr(map) {
  return { headers: { get: (k) => map[k.toLowerCase()] ?? map[k] ?? null } };
}

// ipOf trusts only cf-connecting-ip
{
  assert.equal(ipOf(hdr({ "cf-connecting-ip": "1.2.3.4", "x-forwarded-for": "9.9.9.9" })), "1.2.3.4");
  assert.equal(ipOf(hdr({ "x-forwarded-for": "9.9.9.9" })), "na");
}

// CORS: empty ALLOWED_ORIGINS → no ACAO
{
  const r = corsFor({ ALLOWED_ORIGINS: "" }, hdr({ origin: "https://evil.example" }));
  assert.equal(r["Access-Control-Allow-Origin"], undefined);
  const ok = corsFor({ ALLOWED_ORIGINS: "https://jathol.org" }, hdr({ origin: "https://jathol.org" }));
  assert.equal(ok["Access-Control-Allow-Origin"], "https://jathol.org");
}

// throttle trips
{
  const k = "t-" + Date.now();
  for (let i = 0; i < 3; i++) assert.equal(throttle(k, 3, 60000), false);
  assert.equal(throttle(k, 3, 60000), true);
}

// PBKDF2 clamp
{
  assert.equal(PBKDF2_MAX_ITERS, 100000);
  const hex = await pbkdf2Hex("pw", "aabbccddeeff00112233445566778899", 250000);
  assert.equal(hex.length, 64);
}

// APK release filter
{
  const good = { draft: false, prerelease: false, tag_name: "v1.1.72" };
  const asset = { name: "app-release.apk" };
  assert.equal(publicApkRelease(good, asset), true);
  assert.equal(publicApkRelease({ ...good, draft: true }, asset), false);
  assert.equal(publicApkRelease({ ...good, prerelease: true }, asset), false);
  assert.equal(publicApkRelease({ ...good, tag_name: "v1.1.73-rc1" }, asset), false);
  assert.equal(publicApkRelease(good, { name: "app.apk" }), false);
  assert.equal(publicApkRelease(good, { name: "Order-Flow.apk" }), false);
}

// canonical + Ed25519
{
  const canon = licenseCanonical({
    licenseKey: "OF-AAAA-BBBB-CCCC-DDDD",
    deviceId: "dev1",
    status: "active",
    expiresAt: "2030-01-01T00:00:00.000Z",
    plan: "growth",
    features: ["b", "a"],
    models: ["retail", "restaurant"],
    signedAt: "2026-01-01T00:00:00.000Z",
    nonce: "abc",
  });
  assert.equal(
    canon,
    "v1|OF-AAAA-BBBB-CCCC-DDDD|dev1|active|2030-01-01T00:00:00.000Z|growth|a,b|restaurant,retail|2026-01-01T00:00:00.000Z|abc",
  );
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const sig = nodeSign(null, Buffer.from(canon), privateKey);
  assert.equal(nodeVerify(null, Buffer.from(canon), publicKey, sig), true);
  assert.equal(nodeVerify(null, Buffer.from(canon + "x"), publicKey, sig), false);
}

console.log("sec-test.mjs ok");
