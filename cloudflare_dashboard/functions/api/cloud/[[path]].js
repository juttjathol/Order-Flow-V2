// v1.1.60 — Cloud relay for Order Flow ("cloud networking", custom plan).
//
// This is a TRANSIT, not a store: every message is AES-GCM encrypted by the
// devices (the server never sees plaintext content), rows are deleted as soon
// as every joined device has read past them, they hard-expire in ~30 minutes
// regardless, and closing the room deletes everything. The shop's persistent
// data lives ONLY on the Main device — by design, per the customer need:
// "cloud is to run the system, never to back it up".
//
// Isolation: a room is addressable ONLY by its unguessable 256-bit random id;
// there is no list/query endpoint of any kind. Rooms open only for licenses
// whose plan includes the "cloud_sync" feature.

import { sec, throttle, ipOf, corsFor, d1Limit } from "../../_security.js";

const PLAN_FEATURE_KEY = "cloud_sync";
const MSG_TTL_MS = 30 * 60 * 1000; // rows never live longer than ~30 min
const MSG_CAP = 400; // newest-rows cap per room
const MAX_DEVICES = 16;
const MAX_MSG_LEN = 1_300_000; // encrypted payload size cap

function j(status, body, extra = {}, cors = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...sec(), ...cors, ...extra },
  });
}

// Never hand raw DB errors to a client — map to support-safe codes.
function safeErr(e) {
  const m = String((e && e.message) || e || "").toLowerCase();
  if (/quota|over_|exceed/.test(m)) return "quota";
  if (/no such table|no such column/.test(m)) return "schema";
  if (/busy|lock/.test(m)) return "busy";
  return "db_err";
}

function hex(buf) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(text) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return hex(d);
}

function randomHex(bytes) {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return hex(a);
}

// 6-char human code without ambiguous glyphs (0/O, 1/I).
function randomCode() {
  const abc = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const a = new Uint8Array(6);
  crypto.getRandomValues(a);
  return [...a].map((b) => abc[b % abc.length]).join("");
}

let cloudSchemaChecked = false;
async function ensureCloudSchema(db) {
  if (cloudSchemaChecked) return;
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS cloud_rooms (
      room TEXT PRIMARY KEY,
      secret TEXT NOT NULL,
      code_hash TEXT NOT NULL,
      license_key TEXT,
      main_device TEXT,
      created_at INTEGER NOT NULL
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS cloud_devices (
      room TEXT NOT NULL,
      device_id TEXT NOT NULL,
      role TEXT,
      name TEXT,
      cursor INTEGER NOT NULL DEFAULT 0,
      joined_at INTEGER,
      PRIMARY KEY (room, device_id)
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS cloud_msgs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      room TEXT NOT NULL,
      sender TEXT,
      msg TEXT NOT NULL,
      created_at INTEGER
    )`),
    db.prepare(`CREATE INDEX IF NOT EXISTS idx_cloud_msgs_room ON cloud_msgs(room, id)`),
  ]);
  // v1.1.62+ relay sleep/wake: per-device "hot" mode + liveness stamp.
  // Additive columns — older apps simply never send hot, which reads as idle.
  try { await db.prepare(`ALTER TABLE cloud_devices ADD COLUMN hot INTEGER NOT NULL DEFAULT 0`).run(); } catch {}
  try { await db.prepare(`ALTER TABLE cloud_devices ADD COLUMN last_seen INTEGER`).run(); } catch {}
  cloudSchemaChecked = true;
}

function parseJsonArray(raw) {
  if (raw == null || raw === "") return null;
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

// Mirrors accessOf() in the license API: null ⇒ legacy row, everything on.
async function licenseAllowsCloud(db, licenseKey, deviceId) {
  if (!licenseKey) return false;
  const row = await db
    .prepare("SELECT status, expires_at, allowed_features, bound_device_id FROM licenses WHERE license_key = ?1")
    .bind(licenseKey.toUpperCase().trim()).first();
  if (!row || row.status !== "active") return false;
  if (row.expires_at && new Date(row.expires_at).getTime() < Date.now()) return false;
  if (row.bound_device_id && deviceId && row.bound_device_id !== deviceId) return false;
  const features = parseJsonArray(row.allowed_features);
  return features === null || features.includes(PLAN_FEATURE_KEY);
}

async function readBody(req) {
  try {
    const v = await req.json();
    return v && typeof v === "object" ? v : {};
  } catch {
    return {};
  }
}

// Transit hygiene: expired rows, rows everyone read, and rows beyond the cap
// all disappear. Nothing here is ever a backup.
async function prune(db, room) {
  try {
    await db.batch([
      db.prepare("DELETE FROM cloud_msgs WHERE room = ?1 AND created_at < ?2").bind(room, Date.now() - MSG_TTL_MS),
      db
        .prepare(
          `DELETE FROM cloud_msgs WHERE room = ?1
             AND id <= (SELECT COALESCE(MIN(cursor), -1) FROM cloud_devices WHERE room = ?1)`
        )
        .bind(room),
      db
        .prepare(
          `DELETE FROM cloud_msgs WHERE room = ?1
             AND id <= (SELECT COALESCE(MAX(id), 0) - ?2 FROM cloud_msgs WHERE room = ?1)`
        )
        .bind(room, MSG_CAP),
    ]);
  } catch {}
}

const licCache = new Map();
async function cachedLicenseOk(db, licenseKey, deviceId) {
  const k = `${licenseKey}:${deviceId || ""}`;
  const hit = licCache.get(k);
  if (hit && Date.now() - hit.at < 10 * 60 * 1000) return hit.ok;
  const ok = await licenseAllowsCloud(db, licenseKey, deviceId);
  licCache.set(k, { at: Date.now(), ok });
  if (licCache.size > 2000) {
    const now = Date.now();
    for (const [kk, v] of licCache) if (now - v.at > 20 * 60 * 1000) licCache.delete(kk);
  }
  return ok;
}

async function pruneIdleRooms(db) {
  const cutoff = Date.now() - 24 * 60 * 60 * 1000;
  try {
    const stale = await db.prepare(
      `SELECT room FROM cloud_rooms WHERE created_at < ?1
         AND room NOT IN (SELECT room FROM cloud_devices WHERE last_seen IS NOT NULL AND last_seen >= ?1)
         AND room NOT IN (SELECT room FROM cloud_msgs WHERE created_at >= ?1)`,
    ).bind(cutoff).all();
    for (const r of stale.results || []) {
      await db.batch([
        db.prepare("DELETE FROM cloud_msgs WHERE room = ?1").bind(r.room),
        db.prepare("DELETE FROM cloud_devices WHERE room = ?1").bind(r.room),
        db.prepare("DELETE FROM cloud_rooms WHERE room = ?1").bind(r.room),
      ]);
    }
  } catch {}
}

function diagTokenOk(env, request) {
  const want = String(env.DIAG_TOKEN || "").trim();
  if (!want) return false;
  const got = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim()
    || new URL(request.url).searchParams.get("token") || "";
  const n = Math.max(want.length, got.length);
  let d = want.length ^ got.length;
  for (let i = 0; i < n; i++) d |= (want.charCodeAt(i) || 0) ^ (got.charCodeAt(i) || 0);
  return d === 0;
}

export async function onRequest(context) {
  const { request, env } = context;
  const cors = corsFor(env, request);
  const reply = (status, body, extra = {}) => j(status, body, extra, cors);
  const db = env.DB;
  if (!db) return reply(500, { ok: false, error: "no_db" });
  try {
    await ensureCloudSchema(db);
    await pruneIdleRooms(db);
  } catch (e) {
    return reply(500, { ok: false, error: "db" });
  }

  const path = new URL(request.url).pathname.replace(/^\/api\/cloud\/?/, "").replace(/\/$/, "");

  if (request.method === "GET" || request.method === "HEAD") {
    // Support probe (v1.1.67+): GET /api/cloud/?diag=1 runs the same kinds
    // of writes /open performs (insert room+device+msg into a scratch row,
    // read it back, delete) and reports the raw D1 outcome. The app maps any
    // server failure to the friendly "cloud_err_server" toast; this endpoint
    // tells us WHICH D1 failure it actually is (daily write quota, a missing
    // column, a DB lock) without device logs.
    if (new URL(request.url).searchParams.get("diag") === "1") {
      if (!diagTokenOk(env, request)) return reply(401, { ok: false, error: "unauthorized" });
      const steps = [];
      const t0 = Date.now();
      const scratch = "diag-" + randomHex(8);
      const run = async (label, stmt) => {
        try {
          await stmt.run();
          steps.push(label + ":ok");
          return true;
        } catch (e) {
          steps.push(label + ":FAIL " + safeErr(e));
          return false;
        }
      };
      // Same statements /open runs, mirrored exactly (all-positional binds).
      let ok = await run("insert_room", db
        .prepare("INSERT INTO cloud_rooms (room, secret, code_hash, license_key, main_device, created_at) VALUES (?1,?2,?3,?4,?5,?6)")
        .bind(scratch, "diag", "diag", "diag", "diag", t0));
      if (ok)
        ok = await run("insert_device", db
          .prepare("INSERT INTO cloud_devices (room, device_id, role, name, cursor, joined_at) VALUES (?1,?2,'main','Main',0,?3)")
          .bind(scratch, "diag", t0));
      if (ok)
        ok = await run("insert_msg", db
          .prepare("INSERT INTO cloud_msgs (room, sender, msg, created_at) VALUES (?1,?2,?3,?4)")
          .bind(scratch, "diag", "x", t0));
      try {
        const rows = await db.prepare("SELECT COUNT(*) AS n FROM cloud_msgs WHERE room = ?1").bind(scratch).first();
        steps.push("read:ok n=" + Number(rows?.n ?? 0));
      } catch (e) {
        steps.push("read:FAIL " + safeErr(e));
        ok = false;
      }
      try {
        const lc = await db.prepare("SELECT COUNT(*) AS n FROM licenses").first();
        steps.push("licenses:ok n=" + Number(lc?.n ?? 0));
      } catch (e) {
        steps.push("licenses:FAIL " + safeErr(e));
        ok = false;
      }
      // Mirror of licenseAllowsCloud's exact SELECT — column names included,
      // so diag passing here proves /open can read the licenses table.
      try {
        await db
          .prepare("SELECT status, expires_at, allowed_features, bound_device_id FROM licenses WHERE license_key = ?1")
          .bind("DIAG-PROBE").first();
        steps.push("lic_select:ok");
      } catch (e) {
        steps.push("lic_select:FAIL " + safeErr(e));
        ok = false;
      }
      await run("delete_scratch", db.prepare("DELETE FROM cloud_msgs WHERE room = ?1").bind(scratch));
      await run("delete_dev", db.prepare("DELETE FROM cloud_devices WHERE room = ?1").bind(scratch));
      await run("delete_room", db.prepare("DELETE FROM cloud_rooms WHERE room = ?1").bind(scratch));
      return j(ok ? 200 : 500, {
        ok,
        diag: ok ? "all writes+reads ok" : "see steps",
        ms: Date.now() - t0,
        steps,
      });
    }
    return j(200, { ok: true, v: 1, service: "order-flow-cloud-relay" });
  }
  if (request.method !== "POST") return j(405, { ok: false, error: "method" });
  const body = await readBody(request);

  try {
    if (path === "open") {
      if (throttle(`cloud-open|${ipOf(request)}`, 20, 300000)) return j(429, { ok: false, error: "slow_down" }, { "Retry-After": "300" });
      const allowed = await licenseAllowsCloud(db, String(body.licenseKey || ""), String(body.deviceId || ""));
      if (!allowed) return j(403, { ok: false, error: "plan" });
      const licenseKey = String(body.licenseKey || "").slice(0, 80);
      const mainDevice = String(body.deviceId || "").slice(0, 160);
      const room = randomHex(32);
      const secret = randomHex(32);
      const code = randomCode();
      const now = Date.now();
      // One room per license+device: re-opening replaces it and forces fresh
      // pairing (old devices stop decrypting — nothing leaks across sessions).
      const prev = await db
        .prepare("SELECT room FROM cloud_rooms WHERE license_key = ?1 AND main_device = ?2")
        .bind(licenseKey, mainDevice).all();
      const stmts = [];
      for (const r of prev.results || []) {
        stmts.push(db.prepare("DELETE FROM cloud_msgs WHERE room = ?1").bind(r.room));
        stmts.push(db.prepare("DELETE FROM cloud_devices WHERE room = ?1").bind(r.room));
        stmts.push(db.prepare("DELETE FROM cloud_rooms WHERE room = ?1").bind(r.room));
      }
      stmts.push(
        db
          .prepare(
            "INSERT INTO cloud_rooms (room, secret, code_hash, license_key, main_device, created_at) VALUES (?1,?2,?3,?4,?5,?6)"
          )
          .bind(room, secret, await sha256Hex("of-cloud|" + code), licenseKey, mainDevice, now)
      );
      stmts.push(
        db
          .prepare("INSERT INTO cloud_devices (room, device_id, role, name, joined_at) VALUES (?1,?2,'main','Main',?3)")
          .bind(room, mainDevice, now)
      );
      await db.batch(stmts);
      // Keep `secret` so already-installed Mains can pair. New apps ignore it
      // when noSecret is true and generate the AES key locally.
      return j(200, { ok: true, room, secret, code, noSecret: true });
    }

    if (path === "join") {
      if (throttle(`cloud-join|${ipOf(request)}`, 30, 300000)) return j(429, { ok: false, error: "slow_down" }, { "Retry-After": "120" });
      const room = String(body.room || "");
      const code = String(body.code || "").toUpperCase().trim();
      if (!room || !code) return j(400, { ok: false, error: "args" });
      const row = await db.prepare("SELECT code_hash FROM cloud_rooms WHERE room = ?1").bind(room).first();
      if (!row) return j(404, { ok: false, error: "no_room" });
      if ((await sha256Hex("of-cloud|" + code)) !== row.code_hash) return j(403, { ok: false, error: "code" });
      const count = await db.prepare("SELECT COUNT(*) AS n FROM cloud_devices WHERE room = ?1").bind(room).first();
      if (count && Number(count.n) >= MAX_DEVICES) return j(403, { ok: false, error: "full" });
      await db
        .prepare(
          "INSERT OR REPLACE INTO cloud_devices (room, device_id, role, name, cursor, joined_at) VALUES (?1,?2,?3,?4,0,?5)"
        )
        .bind(room, String(body.deviceId || "?"), String(body.role || "station"), String(body.role || "station"), Date.now()).run();
      return j(200, { ok: true, room });
    }

    if (path === "leave") {
      if (throttle(`cloud-leave|${ipOf(request)}`, 20, 60000) || await d1Limit(db, `cloud-leave|${ipOf(request)}`, 20, 60000)) {
        return j(429, { ok: false, error: "slow_down" }, { "Retry-After": "60" });
      }
      const room = String(body.room || "");
      const dev = String(body.deviceId || "");
      const row = await db.prepare("SELECT main_device FROM cloud_rooms WHERE room = ?1").bind(room).first();
      if (row && row.main_device === dev) {
        await db.batch([
          db.prepare("DELETE FROM cloud_msgs WHERE room = ?1").bind(room),
          db.prepare("DELETE FROM cloud_devices WHERE room = ?1").bind(room),
          db.prepare("DELETE FROM cloud_rooms WHERE room = ?1").bind(room),
        ]);
      } else {
        await db.prepare("DELETE FROM cloud_devices WHERE room = ?1 AND device_id = ?2").bind(room, dev).run();
      }
      return j(200, { ok: true });
    }

    if (path === "send") {
      if (throttle(`cloud-send|${ipOf(request)}`, 300, 60000)) return j(429, { ok: false, error: "slow_down" }, { "Retry-After": "5" });
      const room = String(body.room || "");
      const msg = typeof body.msg === "string" ? body.msg : "";
      if (!room || msg.length === 0 || msg.length > MAX_MSG_LEN) return j(400, { ok: false, error: "args" });
      if (body.licenseKey) {
        const okLic = await cachedLicenseOk(db, String(body.licenseKey), String(body.device || ""));
        if (!okLic) return j(403, { ok: false, error: "plan" });
      }
      const open = await db.prepare("SELECT 1 AS x FROM cloud_rooms WHERE room = ?1").bind(room).first();
      if (!open) return j(404, { ok: false, error: "no_room" });
      await db
        .prepare("INSERT INTO cloud_msgs (room, sender, msg, created_at) VALUES (?1,?2,?3,?4)")
        .bind(room, String(body.device || ""), msg, Date.now()).run();
      await prune(db, room);
      return j(200, { ok: true });
    }

    if (path === "pull") {
      const room = String(body.room || "");
      const dev = String(body.device || "");
      const after = Number(body.after || 0);
      const open = await db.prepare("SELECT 1 AS x FROM cloud_rooms WHERE room = ?1").bind(room).first();
      if (!open) return j(404, { ok: false, error: "no_room" });
      const rs = await db
        .prepare(
          "SELECT id, sender, msg FROM cloud_msgs WHERE room = ?1 AND id > ?2 AND (sender IS NULL OR sender <> ?3) ORDER BY id ASC LIMIT 25"
        )
        .bind(room, after, dev).all();
      const msgs = rs.results || [];
      let cursor = after;
      if (msgs.length) cursor = msgs[msgs.length - 1].id;
      // Relay sleep/wake handshake: a device reports its mode with each pull
      // (hot = "my Wi-Fi link is down, keep this channel fast"). Idle pulls
      // with no news write nothing at all — that's the quota saving.
      const hot = body.hot ? 1 : 0;
      const now = Date.now();
      try {
        if (msgs.length) {
          await db.prepare("UPDATE cloud_devices SET cursor = ?1, hot = ?2, last_seen = ?3 WHERE room = ?4 AND device_id = ?5")
            .bind(cursor, hot, now, room, dev).run();
        } else if (hot === 1) {
          await db.prepare("UPDATE cloud_devices SET hot = 1, last_seen = ?1 WHERE room = ?2 AND device_id = ?3 AND (hot <> 1 OR last_seen IS NULL OR last_seen < ?4)")
            .bind(now, room, dev, now - 60000).run();
        } else {
          await db.prepare("UPDATE cloud_devices SET hot = 0 WHERE room = ?1 AND device_id = ?2 AND hot = 1")
            .bind(room, dev).run();
        }
      } catch {}
      // Main reads this to wake out of idle the moment any peer reports
      // trouble on its LAN side (fresh hot flags expire after ~90s).
      let peersHot = 0;
      try {
        const ph = await db.prepare("SELECT COUNT(*) AS n FROM cloud_devices WHERE room = ?1 AND device_id <> ?2 AND hot = 1 AND last_seen > ?3")
          .bind(room, dev, now - 90000).first();
        if (ph) peersHot = Number(ph.n);
      } catch {}
      return j(200, { ok: true, msgs, cursor, peersHot });
    }

    return j(404, { ok: false, error: "route" });
  } catch (e) {
    console.error("cloud relay error:", e && e.message);
    return j(500, { ok: false, error: "relay_err" });
  }
}
