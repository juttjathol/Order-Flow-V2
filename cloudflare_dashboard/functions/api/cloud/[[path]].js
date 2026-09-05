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

const PLAN_FEATURE_KEY = "cloud_sync";
const MSG_TTL_MS = 30 * 60 * 1000; // rows never live longer than ~30 min
const MSG_CAP = 400; // newest-rows cap per room
const MAX_DEVICES = 16;
const MAX_MSG_LEN = 1_300_000; // encrypted payload size cap

function j(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
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
  cloudSchemaChecked = true;
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
async function licenseAllowsCloud(db, licenseKey) {
  if (!licenseKey) return false;
  const row = await db
    .prepare("SELECT status, expires_at, allowed_features FROM licenses WHERE key = ?1")
    .first(licenseKey);
  if (!row || row.status !== "active") return false;
  if (row.expires_at && new Date(row.expires_at).getTime() < Date.now()) return false;
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

export async function onRequest(context) {
  const { request, env } = context;
  const db = env.DB;
  if (!db) return j(500, { ok: false, error: "no_db" });
  try {
    await ensureCloudSchema(db);
  } catch (e) {
    return j(500, { ok: false, error: "db" });
  }

  const path = new URL(request.url).pathname.replace(/^\/api\/cloud\/?/, "").replace(/\/$/, "");

  if (request.method === "GET" || request.method === "HEAD") {
    return j(200, { ok: true, v: 1, service: "order-flow-cloud-relay" });
  }
  if (request.method !== "POST") return j(405, { ok: false, error: "method" });
  const body = await readBody(request);

  try {
    if (path === "open") {
      const allowed = await licenseAllowsCloud(db, String(body.licenseKey || ""));
      if (!allowed) return j(403, { ok: false, error: "plan" });
      const licenseKey = String(body.licenseKey || "");
      const mainDevice = String(body.deviceId || "");
      const room = randomHex(32);
      const secret = randomHex(32);
      const code = randomCode();
      const now = Date.now();
      // One room per license+device: re-opening replaces it and forces fresh
      // pairing (old devices stop decrypting — nothing leaks across sessions).
      const prev = await db
        .prepare("SELECT room FROM cloud_rooms WHERE license_key = ?1 AND main_device = ?2")
        .all(licenseKey, mainDevice);
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
      return j(200, { ok: true, room, secret, code });
    }

    if (path === "join") {
      const room = String(body.room || "");
      const code = String(body.code || "").toUpperCase().trim();
      if (!room || !code) return j(400, { ok: false, error: "args" });
      const row = await db.prepare("SELECT code_hash FROM cloud_rooms WHERE room = ?1").first(room);
      if (!row) return j(404, { ok: false, error: "no_room" });
      if ((await sha256Hex("of-cloud|" + code)) !== row.code_hash) return j(403, { ok: false, error: "code" });
      const count = await db.prepare("SELECT COUNT(*) AS n FROM cloud_devices WHERE room = ?1").first(room);
      if (count && Number(count.n) >= MAX_DEVICES) return j(403, { ok: false, error: "full" });
      await db
        .prepare(
          "INSERT OR REPLACE INTO cloud_devices (room, device_id, role, name, cursor, joined_at) VALUES (?1,?2,?3,?4,0,?5)"
        )
        .run(room, String(body.deviceId || "?"), String(body.role || "station"), String(body.role || "station"), Date.now());
      return j(200, { ok: true, room });
    }

    if (path === "leave") {
      const room = String(body.room || "");
      const dev = String(body.deviceId || "");
      const row = await db.prepare("SELECT main_device FROM cloud_rooms WHERE room = ?1").first(room);
      if (row && row.main_device === dev) {
        await db.batch([
          db.prepare("DELETE FROM cloud_msgs WHERE room = ?1").bind(room),
          db.prepare("DELETE FROM cloud_devices WHERE room = ?1").bind(room),
          db.prepare("DELETE FROM cloud_rooms WHERE room = ?1").bind(room),
        ]);
      } else {
        await db.prepare("DELETE FROM cloud_devices WHERE room = ?1 AND device_id = ?2").run(room, dev);
      }
      return j(200, { ok: true });
    }

    if (path === "send") {
      const room = String(body.room || "");
      const msg = typeof body.msg === "string" ? body.msg : "";
      if (!room || msg.length === 0 || msg.length > MAX_MSG_LEN) return j(400, { ok: false, error: "args" });
      const open = await db.prepare("SELECT 1 AS x FROM cloud_rooms WHERE room = ?1").first(room);
      if (!open) return j(404, { ok: false, error: "no_room" });
      await db
        .prepare("INSERT INTO cloud_msgs (room, sender, msg, created_at) VALUES (?1,?2,?3,?4)")
        .run(room, String(body.device || ""), msg, Date.now());
      await prune(db, room);
      return j(200, { ok: true });
    }

    if (path === "pull") {
      const room = String(body.room || "");
      const dev = String(body.device || "");
      const after = Number(body.after || 0);
      const open = await db.prepare("SELECT 1 AS x FROM cloud_rooms WHERE room = ?1").first(room);
      if (!open) return j(404, { ok: false, error: "no_room" });
      const rs = await db
        .prepare(
          "SELECT id, sender, msg FROM cloud_msgs WHERE room = ?1 AND id > ?2 AND (sender IS NULL OR sender <> ?3) ORDER BY id ASC LIMIT 25"
        )
        .all(room, after, dev);
      const msgs = rs.results || [];
      let cursor = after;
      if (msgs.length) cursor = msgs[msgs.length - 1].id;
      try {
        await db.prepare("UPDATE cloud_devices SET cursor = ?1 WHERE room = ?2 AND device_id = ?3").run(cursor, room, dev);
      } catch {}
      return j(200, { ok: true, msgs, cursor });
    }

    return j(404, { ok: false, error: "route" });
  } catch (e) {
    return j(500, { ok: false, error: String((e && e.message) || e) });
  }
}
