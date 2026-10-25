// v1.1.72 security layer: shared helpers (throttle, hardening headers,
// origin-allowlisted CORS, constant-time compares, PBKDF2).
import { sec, throttle, ipOf, corsFor, safeEqual, pbkdf2Hex, d1Limit, licenseCanonical } from "../_security.js";

// v1.1.59 — plan & entitlements catalog. Keys here must match
// kFeatureCatalog in flutter_app/lib/models/models_plans.dart exactly.
const CORE_FEATURE_KEYS = new Set([
  "multi_terminal", "station_printers", "qr_ordering", "loyalty", "split_payment",
  "refunds", "customer_display", "reservations", "recipe_costing", "wastage",
  "purchases", "advanced_reports", "eighty_six",
]);
// v1.1.60: extras that belong to the custom plan only. Must match
// kFeatureCatalog in the app (kFeatureCatalog lists ALL sixteen).
const FEATURE_KEYS = new Set([...CORE_FEATURE_KEYS, "cloud_sync", "qr_branding", "third_party"]);
const MODEL_KEYS = new Set(["restaurant", "retail", "fastfood", "services"]);
const PLAN_PRESETS = {
  starter: [...CORE_FEATURE_KEYS].filter((k) => k !== "qr_ordering"),
  growth: [...CORE_FEATURE_KEYS].filter((k) => k !== "qr_ordering"),
  custom: [...FEATURE_KEYS],
  customize: [...FEATURE_KEYS],
  full: [...FEATURE_KEYS],
};

// Phase-1 10k-shop: in-memory row cache for license validate (isolate-level).
// kRevalidateMinutes=5 → 10k shops = 33 rps. 2 min TTL cuts D1 selects ~40%
// without risking stale revoke (writes clear the entry immediately).
const validateRowCache = new Map();
const VALIDATE_ROW_TTL_MS = 120_000;
function cacheGetValidateRow(licenseKey) {
  const hit = validateRowCache.get(licenseKey);
  if (!hit) return null;
  if (Date.now() - hit.at > VALIDATE_ROW_TTL_MS) {
    validateRowCache.delete(licenseKey);
    return null;
  }
  return hit.row;
}
function cacheSetValidateRow(licenseKey, row) {
  validateRowCache.set(licenseKey, { at: Date.now(), row });
  if (validateRowCache.size > 4000) {
    const now = Date.now();
    for (const [k, v] of validateRowCache) {
      if (now - v.at > VALIDATE_ROW_TTL_MS * 2) validateRowCache.delete(k);
    }
  }
}
function cacheDelValidateRow(licenseKey) {
  if (!licenseKey) return;
  validateRowCache.delete(licenseKey.toUpperCase().trim());
  validateRowCache.delete(licenseKey);
}

// Add plan columns to databases created before v1.1.59 (idempotent, once per isolate).
let planSchemaChecked = false;
async function ensurePlanColumns(db) {
  if (planSchemaChecked) return;
  try {
    await db.prepare("SELECT plan FROM licenses LIMIT 1").first();
    planSchemaChecked = true;
  } catch {
    try { await db.prepare("ALTER TABLE licenses ADD COLUMN plan TEXT NOT NULL DEFAULT 'full'").run(); } catch {}
    try { await db.prepare("ALTER TABLE licenses ADD COLUMN allowed_models TEXT").run(); } catch {}
    try { await db.prepare("ALTER TABLE licenses ADD COLUMN allowed_features TEXT").run(); } catch {}
    try {
      await db.prepare("SELECT plan FROM licenses LIMIT 1").first();
      planSchemaChecked = true;
    } catch {}
  }
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

// null result → legacy row created before plans existed: the app keeps ALL
// features on. Once a plan is saved the arrays are explicit (possibly empty).
function healFeatures(plan, features) {
  // v1.1.82: an empty feature list on a non-Starter plan is the dashboard
  // editor bug's signature, never a shop's intent. Heal it to the plan.
  if (plan === "full") return [...FEATURE_KEYS]; // Full means everything
  if (Array.isArray(features) && features.length === 0 && plan !== "starter") {
    return [...(PLAN_PRESETS[plan] ?? FEATURE_KEYS)];
  }
  return features;
}

function accessOf(row) {
  if (row == null) return null;
  const models = parseJsonArray(row.allowed_models);
  const rawFeatures = parseJsonArray(row.allowed_features);
  if (models === null && rawFeatures === null && (!row.plan || row.plan === "full")) {
    return null;
  }
  const plan = row.plan || "full";
  return {
    plan,
    allowedModels: models ?? [...MODEL_KEYS],
    allowedFeatures: healFeatures(plan, rawFeatures ?? [...FEATURE_KEYS]),
  };
}

function normalizeAccess(body) {
  const rawPlan = String(body.plan || "").trim().toLowerCase();
  const planAlias = rawPlan === "customize" ? "custom" : rawPlan;
  const plan = ["starter", "growth", "custom", "full"].includes(planAlias) ? planAlias : "full";
  const models = Array.isArray(body.allowedModels)
    ? body.allowedModels.filter((m) => MODEL_KEYS.has(m))
    : [...MODEL_KEYS];
  const rawFeatures = Array.isArray(body.allowedFeatures)
    ? body.allowedFeatures.filter((f) => FEATURE_KEYS.has(f))
    : [...PLAN_PRESETS[plan]];
  const features = plan === "full"
    ? [...FEATURE_KEYS] // Full can never be an empty set
    : healFeatures(plan, rawFeatures);
  return {
    plan,
    models: models.length ? models : [...MODEL_KEYS],
    features,
  };
}

function jsonOut(data, status = 200, extra = {}, cors = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...sec(), ...cors, ...extra },
  });
}

function pathOf(context) {
  const p = context.params?.path;
  if (Array.isArray(p)) return p.filter(Boolean).join("/");
  if (typeof p === "string") return p.replace(/^\/+|\/+$/g, "");
  const url = new URL(context.request.url);
  return url.pathname.replace(/^\/api\/?/, "").replace(/^\/+|\/+$/g, "");
}

async function readJson(request, maxBytes = 65536) {
  try {
    const len = Number(request.headers.get("content-length") || 0);
    if (len > maxBytes) return {};
    const text = await request.text();
    if (!text || text.length > maxBytes) return {};
    const data = JSON.parse(text);
    return data && typeof data === "object" ? data : {};
  } catch {
    return {};
  }
}

function nowIso() {
  return new Date().toISOString();
}

function addDays(iso, days) {
  const d = iso ? new Date(iso) : new Date();
  if (Number.isNaN(d.getTime()) || d < new Date()) {
    const n = new Date();
    n.setUTCDate(n.getUTCDate() + days);
    return n.toISOString();
  }
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString();
}

function generateKey() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const block = () =>
    Array.from(crypto.getRandomValues(new Uint8Array(4)))
      .map((n) => alphabet[n % alphabet.length])
      .join("");
  return `OF-${block()}-${block()}-${block()}-${block()}`;
}

// SEC-04: HMAC session tokens are keyed ONLY by ADMIN_SECRET (never the
// login password). Import as a CryptoKey — SubtleCrypto will not sign with a raw Uint8Array.
async function hmacKey(env) {
  const secret = String(env.ADMIN_SECRET || "").trim();
  if (!secret) return null;
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function issueToken(env, hours = 12) {
  const key = await hmacKey(env);
  if (!key) throw new Error("no_admin_secret");
  const payload = btoa(JSON.stringify({ iat: Date.now(), exp: Date.now() + hours * 3600_000 }));
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return `${payload}.${[...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

async function verifyToken(env, header) {
  if (!header || !header.startsWith("Bearer ")) return false;
  const token = header.slice(7).trim();
  if (!token.includes(".")) return false;
  const key = await hmacKey(env);
  if (!key) return false;
  const [payload, sig] = token.split(".");
  if (!/^[0-9a-f]{64}$/.test(sig || "")) return false;
  const sigBytes = new Uint8Array((sig.match(/../g) || []).map((h) => parseInt(h, 16)));
  let ok = false;
  try {
    ok = await crypto.subtle.verify("HMAC", key, sigBytes, new TextEncoder().encode(payload));
  } catch {
    return false;
  }
  if (!ok) return false;
  try {
    const body = JSON.parse(atob(payload));
    return Number(body.exp) > Date.now();
  } catch {
    return false;
  }
}

let eventsSchemaChecked = false;
let lastEventPrune = 0;
const EVENT_PRUNE_EVERY_MS = 6 * 60 * 60 * 1000;
async function ensureLicenseEvents(db) {
  if (eventsSchemaChecked) return;
  try {
    await db.prepare("SELECT 1 FROM license_events LIMIT 1").first();
    eventsSchemaChecked = true;
  } catch {
    try {
      await db.prepare(
        `CREATE TABLE IF NOT EXISTS license_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          license_id TEXT,
          license_key TEXT,
          event TEXT NOT NULL,
          device_id TEXT,
          detail TEXT,
          created_at TEXT NOT NULL
        )`,
      ).run();
      eventsSchemaChecked = true;
    } catch {}
  }
}

async function logLicenseEvent(db, { licenseId, licenseKey, event, deviceId, detail }) {
  try {
    await db.prepare(
      `INSERT INTO license_events (license_id, license_key, event, device_id, detail, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
      .bind(licenseId || "", licenseKey || "", event, deviceId || "", detail || "", nowIso())
      .run();
  } catch {}
}

let appEventsSchemaChecked = false;
async function ensureAppEventsTable(db) {
  if (appEventsSchemaChecked) return;
  try {
    await db.prepare("SELECT 1 FROM app_events LIMIT 1").first();
    appEventsSchemaChecked = true;
  } catch {
    try {
      await db.prepare(
        `CREATE TABLE IF NOT EXISTS app_events (
          id TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          device_id TEXT,
          license_key TEXT,
          route TEXT,
          detail TEXT,
          created_at TEXT NOT NULL
        )`,
      ).run();
      try { await db.prepare("CREATE INDEX IF NOT EXISTS idx_app_events_kind ON app_events(kind, created_at DESC)").run(); } catch {}
      try { await db.prepare("CREATE INDEX IF NOT EXISTS idx_app_events_license ON app_events(license_key, created_at DESC)").run(); } catch {}
      appEventsSchemaChecked = true;
    } catch {}
  }
}

let broadcastSchemaChecked = false;
async function ensureBroadcastTable(db) {
  if (broadcastSchemaChecked) return;
  try {
    await db.prepare("SELECT 1 FROM broadcast_notifications LIMIT 1").first();
    broadcastSchemaChecked = true;
  } catch {
    try {
      await db.prepare(
        `CREATE TABLE IF NOT EXISTS broadcast_notifications (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          message TEXT NOT NULL,
          tag TEXT NOT NULL DEFAULT 'feature',
          url TEXT,
          created_at TEXT NOT NULL
        )`,
      ).run();
      try {
        await db.prepare("CREATE INDEX IF NOT EXISTS idx_broadcast_created ON broadcast_notifications(created_at DESC)").run();
      } catch {}
      broadcastSchemaChecked = true;
    } catch {}
  }
}

// PBKDF2 password hash: pbkdf2-sha256$<iterations>$<saltHex>$<hashHex>
// (generate with: node scripts/hash-pass.mjs 'your password')
async function verifyAdminPassword(env, given) {
  const stored = String(env.ADMIN_PASSWORD_HASH || "").trim();
  if (stored) {
    const m = /^pbkdf2-sha256\$(\d+)\$([0-9a-f]+)\$([0-9a-f]+)$/i.exec(stored);
    if (!m || typeof given !== "string" || !given) return false;
    const iters = Math.min(Math.max(Number(m[1]) || 0, 1), 100000);
    const calc = await pbkdf2Hex(given, m[2], iters);
    return await safeEqual(calc, m[3].toLowerCase());
  }
  const legacy = String(env.ADMIN_PASSWORD || "");
  if (!legacy || typeof given !== "string" || !given) return false;
  return await safeEqual(given, legacy); // constant-time fallback for plaintext secret
}

// Broadcasts are rendered inside every shop's Main app and can carry a link
// the app opens. Only http(s) is ever acceptable — a javascript:/file:/content:/
// intent: URL here would be an injection primitive into installed clients.
function safeBroadcastUrl(raw) {
  const u = String(raw || "").trim().slice(0, 500);
  if (!u) return "";
  if (!/^https:\/\/[^\s]+$/i.test(u)) return "";
  return u;
}

function clip(raw, max) {
  // Strip C0/C1 control characters, then cap the length.
  return String(raw || "").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/g, "").trim().slice(0, max);
}

async function customerById(db, id) {
  return db.prepare("SELECT * FROM customers WHERE id = ?").bind(id).first();
}

async function licenseById(db, id) {
  return db.prepare("SELECT * FROM licenses WHERE id = ?").bind(id).first();
}

function publicLicense(row, customer) {
  const access = accessOf(row);
  return {
    id: row.id,
    customerId: row.customer_id,
    licenseKey: row.license_key,
    status: row.status,
    expiresAt: row.expires_at,
    boundDeviceId: row.bound_device_id,
    boundAt: row.bound_at,
    lastValidatedAt: row.last_validated_at,
    createdAt: row.created_at,
    binding: row.bound_device_id ? "bound" : "unbound",
    plan: row.plan || "full",
    allowedModels: access?.allowedModels ?? null,
    allowedFeatures: access?.allowedFeatures ?? null,
    customer: customer
      ? {
          id: customer.id,
          name: customer.name,
          businessName: customer.business_name,
          email: customer.email,
          phone: customer.phone,
        }
      : null,
  };
}

export async function onRequest(context) {
  const { request, env } = context;
  const cors = corsFor(env, request);
  const json = (data, status = 200, extra = {}) => jsonOut(data, status, extra, cors);
  if (request.method === "OPTIONS") {
    const allowed = Boolean(cors["Access-Control-Allow-Origin"]);
    const h = { ...sec(), Allow: "GET,POST,PATCH,DELETE,OPTIONS", ...(allowed ? { "Access-Control-Allow-Methods": "GET,POST,PATCH,DELETE,OPTIONS", "Access-Control-Allow-Headers": "Content-Type, Authorization", "Access-Control-Max-Age": "600", ...cors } : {}) };
    return new Response(null, { status: allowed ? 204 : 403, headers: h });
  }
  if (!env.ADMIN_PASSWORD && !env.ADMIN_PASSWORD_HASH) {
    return json({ ok: false, error: "not_configured", message: "Set ADMIN_PASSWORD_HASH (preferred) or ADMIN_PASSWORD." }, 500);
  }
  if (!String(env.ADMIN_SECRET || "").trim()) {
    return json({ ok: false, error: "not_configured", message: "Set ADMIN_SECRET (openssl rand -hex 32)." }, 500);
  }
  if (!env.DB) {
    return json({ ok: false, error: "d1_not_configured", message: "Bind a D1 database as DB." }, 500);
  }
  await ensurePlanColumns(env.DB);
  await ensureLicenseEvents(env.DB);
  await ensureBroadcastTable(env.DB);
  await ensureAppEventsTable(env.DB);

  const path = pathOf(context);
  const method = request.method.toUpperCase();

  try {
    if (path === "v1/health" && method === "GET") {
      const t0 = Date.now();
      let d1ok = true, d1ms = 0;
      try {
        const q0 = Date.now();
        await env.DB.prepare("SELECT 1 AS x").first();
        d1ms = Date.now() - q0;
      } catch { d1ok = false; }
      return json({
        ok: true,
        app: "order-flow-saas",
        version: "1.0.0",
        d1: d1ok ? "ok" : "down",
        d1Ms: d1ms,
        uptimeMs: Date.now() - t0,
        cache: { validateRows: validateRowCache.size },
        time: nowIso(),
      });
    }

    if (path === "v1/broadcasts" && method === "GET") {
      // Unauthenticated by design (Mains poll it before they hold a session),
      // so it is throttled and defensively filtered: a link stored before the
      // https-only rule is never handed to a client.
      if (throttle(`broadcasts|${ipOf(request)}`, 60, 60000)) {
        return json({ ok: false, error: "slow_down" }, 429, { "Retry-After": "60" });
      }
      try {
        const { results } = await env.DB.prepare(
          "SELECT id, title, message, tag, url, created_at FROM broadcast_notifications ORDER BY created_at DESC LIMIT 25",
        ).all();
        const broadcasts = (results || []).map((b) => ({ ...b, url: safeBroadcastUrl(b.url) }));
        return json({ ok: true, broadcasts });
      } catch (e) {
        return json({ ok: true, broadcasts: [] });
      }
    }

    if (path === "v1/events" && method === "POST") {
      if (throttle(`events|${ipOf(request)}`, 120, 60000) || await d1Limit(env.DB, `events|${ipOf(request)}`, 120, 60000)) {
        return json({ ok: false, error: "slow_down" }, 429, { "Retry-After": "60" });
      }
      const body = await readJson(request);
      const kind = ["crash","perf","funnel","error"].includes(String(body.kind || "").trim()) ? String(body.kind).trim() : "error";
      const route = clip(String(body.route || ""), 200);
      const detail = clip(String(body.detail || body.message || ""), 2000);
      const deviceId = clip(String(body.deviceId || ""), 80);
      const licenseKey = clip(String(body.licenseKey || ""), 40).toUpperCase();
      try {
        await env.DB.prepare(
          `INSERT INTO app_events (id, kind, device_id, license_key, route, detail, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
        ).bind(crypto.randomUUID(), kind, deviceId, licenseKey, route, detail, nowIso()).run();
      } catch {}
      return json({ ok: true });
    }

    if (path === "admin/events" && method === "GET") {
      const authed2 = await verifyToken(env, request.headers.get("Authorization") || "");
      if (!authed2) return json({ ok: false, error: "unauthorized" }, 401);
      try {
        const { results } = await env.DB.prepare(
          "SELECT kind, route, detail, device_id, license_key, created_at FROM app_events ORDER BY created_at DESC LIMIT 100",
        ).all();
        const crashes = await env.DB.prepare("SELECT COUNT(*) as n FROM app_events WHERE kind='crash' AND created_at > datetime('now','-7 days')").first();
        return json({ ok: true, events: results || [], crashes7d: crashes?.n || 0 });
      } catch { return json({ ok: true, events: [] }); }
    }

    if (path === "v1/license/validate" && method === "POST") {
      const ip = ipOf(request);
      if (throttle(`validate|${ip}`, 60, 600000) || await d1Limit(env.DB, `validate|${ip}`, 60, 600000)) {
        return json({ ok: false, valid: false, error: "slow_down" }, 429, { "Retry-After": "600" });
      }
      return handleValidate(env, await readJson(request), json);
    }

    if (path === "admin/login" && method === "POST") {
      const ip = ipOf(request);
      if (throttle(`login|${ip}`, 8, 300000) || await d1Limit(env.DB, `login|${ip}`, 8, 300000)) {
        return json({ ok: false, error: "slow_down", message: "Too many attempts — wait a few minutes." }, 429, { "Retry-After": "300" });
      }
      const body = await readJson(request);
      if (!(await verifyAdminPassword(env, body.password))) {
        return json({ ok: false, error: "unauthorized", message: "Invalid password." }, 401);
      }
      const token = await issueToken(env);
      const hashed = String(env.ADMIN_PASSWORD_HASH || "").trim();
      const warn = (!hashed && String(env.ADMIN_PASSWORD || "")) ? "plaintext_admin_password" : undefined;
      return json({ ok: true, token, expiresHours: 12, ...(warn ? { warn } : {}) });
    }

    const authed = await verifyToken(env, request.headers.get("Authorization") || "");
    if (path.startsWith("admin/")) {
      if (!authed) return json({ ok: false, error: "unauthorized" }, 401);
    }

    if (path === "admin/me" && method === "GET") {
      const hashed = String(env.ADMIN_PASSWORD_HASH || "").trim();
      const warn = (!hashed && String(env.ADMIN_PASSWORD || "")) ? "plaintext_admin_password" : undefined;
      return json({ ok: true, role: "admin", ...(warn ? { warn } : {}) });
    }

    if (path === "admin/stats" && method === "GET") {
      const customers = await env.DB.prepare("SELECT COUNT(*) AS n FROM customers").first();
      const licenses = await env.DB.prepare("SELECT COUNT(*) AS n FROM licenses").first();
      const bound = await env.DB.prepare("SELECT COUNT(*) AS n FROM licenses WHERE bound_device_id IS NOT NULL").first();
      const revoked = await env.DB.prepare("SELECT COUNT(*) AS n FROM licenses WHERE status = 'revoked'").first();
      return json({
        ok: true,
        customers: customers?.n || 0,
        licenses: licenses?.n || 0,
        bound: bound?.n || 0,
        revoked: revoked?.n || 0,
      });
    }

    if (path === "admin/customers" && method === "GET") {
      const { results } = await env.DB.prepare(
        "SELECT * FROM customers ORDER BY created_at DESC",
      ).all();
      return json({ ok: true, customers: results || [] });
    }

    if (path === "admin/customers" && method === "POST") {
      const body = await readJson(request);
      const name = (body.name || "").trim();
      if (!name) return json({ ok: false, error: "name_required" }, 400);
      const id = crypto.randomUUID();
      await env.DB.prepare(
        `INSERT INTO customers (id, name, email, phone, business_name, notes, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
        .bind(
          id,
          name,
          (body.email || "").trim(),
          (body.phone || "").trim(),
          (body.businessName || body.business_name || "").trim(),
          (body.notes || "").trim(),
          nowIso(),
        )
        .run();
      const row = await customerById(env.DB, id);
      return json({ ok: true, customer: row }, 201);
    }

    const customerMatch = path.match(/^admin\/customers\/([^/]+)$/);
    if (customerMatch && method === "DELETE") {
      const id = customerMatch[1];
      await env.DB.prepare("DELETE FROM licenses WHERE customer_id = ?").bind(id).run();
      await env.DB.prepare("DELETE FROM customers WHERE id = ?").bind(id).run();
      return json({ ok: true });
    }

    if (path === "admin/licenses" && method === "GET") {
      const { results } = await env.DB.prepare(
        `SELECT l.*, c.name AS customer_name, c.business_name AS customer_business
         FROM licenses l
         LEFT JOIN customers c ON c.id = l.customer_id
         ORDER BY l.created_at DESC`,
      ).all();
      return json({
        ok: true,
        licenses: (results || []).map((row) => ({
          ...publicLicense(row, {
            id: row.customer_id,
            name: row.customer_name,
            business_name: row.customer_business,
          }),
        })),
      });
    }

    if (path === "admin/licenses" && method === "POST") {
      const body = await readJson(request);
      const customerId = body.customerId || body.customer_id;
      if (!customerId) return json({ ok: false, error: "customer_required" }, 400);
      const customer = await customerById(env.DB, customerId);
      if (!customer) return json({ ok: false, error: "customer_not_found" }, 404);
      const days = Number(body.days || env.LICENSE_DEFAULT_DAYS || 365);
      const id = crypto.randomUUID();
      const key = (body.licenseKey || generateKey()).toUpperCase();
      const expires = addDays(null, Number.isFinite(days) ? days : 365);
      const access = normalizeAccess(body);
      try {
        await env.DB.prepare(
          `INSERT INTO licenses (id, customer_id, license_key, status, expires_at, created_at, plan, allowed_models, allowed_features)
           VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?)`,
        )
          .bind(
            id,
            customerId,
            key,
            expires,
            nowIso(),
            access.plan,
            JSON.stringify(access.models),
            JSON.stringify(access.features),
          )
          .run();
      } catch (e) {
        console.error("key insert failed:", e && e.message);
        return json({ ok: false, error: "key_conflict", message: "That key already exists — generate another." }, 409);
      }
      const row = await licenseById(env.DB, id);
      return json({ ok: true, license: publicLicense(row, customer) }, 201);
    }

    const licenseMatch = path.match(/^admin\/licenses\/([^/]+)(?:\/([^/]+))?$/);
    if (licenseMatch) {
      const id = licenseMatch[1];
      const action = licenseMatch[2] || "";
      const row = await licenseById(env.DB, id);
      if (!row) return json({ ok: false, error: "not_found" }, 404);

      if (method === "DELETE" && !action) {
        await env.DB.prepare("DELETE FROM licenses WHERE id = ?").bind(id).run();
        await logLicenseEvent(env.DB, { licenseId: id, licenseKey: row.license_key, event: "delete" });
        return json({ ok: true });
      }
      if (method === "POST" && action === "reset-device") {
        await env.DB.prepare(
          "UPDATE licenses SET bound_device_id = NULL, bound_at = NULL WHERE id = ?",
        )
          .bind(id)
          .run();
        cacheDelValidateRow(row.license_key);
        await logLicenseEvent(env.DB, {
          licenseId: id,
          licenseKey: row.license_key,
          event: "reset-device",
          deviceId: row.bound_device_id || "",
        });
        const next = await licenseById(env.DB, id);
        return json({ ok: true, license: publicLicense(next) });
      }
      if (method === "POST" && action === "extend") {
        const nextExp = addDays(row.expires_at, 30);
        await env.DB.prepare("UPDATE licenses SET expires_at = ? WHERE id = ?")
          .bind(nextExp, id)
          .run();
        cacheDelValidateRow(row.license_key);
        await logLicenseEvent(env.DB, {
          licenseId: id,
          licenseKey: row.license_key,
          event: "extend",
          detail: nextExp,
        });
        const next = await licenseById(env.DB, id);
        return json({ ok: true, license: publicLicense(next) });
      }
      if (method === "POST" && action === "revoke") {
        await env.DB.prepare("UPDATE licenses SET status = 'revoked' WHERE id = ?").bind(id).run();
        cacheDelValidateRow(row.license_key);
        await logLicenseEvent(env.DB, { licenseId: id, licenseKey: row.license_key, event: "revoke" });
        const next = await licenseById(env.DB, id);
        return json({ ok: true, license: publicLicense(next) });
      }
      if (method === "POST" && action === "access") {
        const body = await readJson(request);
        const access = normalizeAccess(body);
        await env.DB.prepare(
          "UPDATE licenses SET plan = ?, allowed_models = ?, allowed_features = ? WHERE id = ?",
        )
          .bind(access.plan, JSON.stringify(access.models), JSON.stringify(access.features), id)
          .run();
        cacheDelValidateRow(row.license_key);
        const next = await licenseById(env.DB, id);
        const cust = await customerById(env.DB, next.customer_id);
        return json({ ok: true, license: publicLicense(next, cust) });
      }
    }

    if (path === "admin/broadcasts" && method === "GET") {
      const { results } = await env.DB.prepare(
        "SELECT * FROM broadcast_notifications ORDER BY created_at DESC LIMIT 100",
      ).all();
      return json({ ok: true, broadcasts: results || [] });
    }

    if (path === "admin/broadcasts" && method === "POST") {
      const body = await readJson(request);
      const title = clip(body.title, 160);
      const message = clip(body.message, 2000);
      const tag = ["feature", "plan", "alert", "maintenance"].includes(String(body.tag || "").trim())
        ? String(body.tag).trim()
        : "feature";
      const rawUrl = String(body.url || "").trim();
      const url = safeBroadcastUrl(rawUrl);
      if (!title || !message) {
        return json({ ok: false, error: "missing_fields", message: "Title and message are required." }, 400);
      }
      if (rawUrl && !url) {
        return json({ ok: false, error: "bad_url", message: "Links must start with https:// (or be left empty)." }, 400);
      }
      const id = crypto.randomUUID();
      const now = nowIso();
      await env.DB.prepare(
        `INSERT INTO broadcast_notifications (id, title, message, tag, url, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
        .bind(id, title, message, tag, url, now)
        .run();
      return json(
        {
          ok: true,
          broadcast: { id, title, message, tag, url, created_at: now },
        },
        201,
      );
    }

    const broadcastMatch = path.match(/^admin\/broadcasts\/([^/]+)$/);
    if (broadcastMatch && method === "DELETE") {
      const id = broadcastMatch[1];
      await env.DB.prepare("DELETE FROM broadcast_notifications WHERE id = ?").bind(id).run();
      return json({ ok: true });
    }

    return json({ ok: false, error: "not_found", path }, 404);
  } catch (error) {
    console.error("api error:", path, error && error.message); // details stay server-side
    return json({ ok: false, error: "server_error", message: "Something went wrong on our side." }, 500);
  }
}

async function signLicensePayload(env, canonical) {
  const raw = String(env.LICENSE_SIGNING_KEY || "").trim();
  if (!raw) return null;
  let der;
  try { der = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)); } catch { return null; }
  try {
    const key = await crypto.subtle.importKey("pkcs8", der, { name: "Ed25519" }, false, ["sign"]);
    const sig = await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(canonical));
    return btoa(String.fromCharCode(...new Uint8Array(sig)));
  } catch {
    return null;
  }
}

// Retention prune. It used to run inside every validate call — a full-table
// DELETE scan per device check (every ~5 min per shop). Once per isolate per
// 6h gives identical retention for a tiny fraction of the D1 quota.
async function pruneLicenseEvents(db) {
  if (Date.now() - lastEventPrune < EVENT_PRUNE_EVERY_MS) return;
  lastEventPrune = Date.now();
  try {
    await db.prepare("DELETE FROM license_events WHERE created_at < datetime('now', '-90 days')").run();
  } catch {}
}

async function handleValidate(env, body, json) {
  const licenseKey = String(body.licenseKey || body.license_key || "").trim().toUpperCase();
  const deviceId = String(body.deviceId || body.device_id || "").trim();
  const appVersion = String(body.appVersion || body.app_version || "").trim();
  if (!licenseKey || !deviceId) {
    return json({ ok: false, valid: false, error: "missing_fields" }, 400);
  }
  if (licenseKey.length > 40 || deviceId.length > 80 || appVersion.length > 32) {
    return json({ ok: false, valid: false, error: "invalid_input" }, 400);
  }
  // Phase-1 cache: hot path for 10k shops polling every 5 min.
  let row = cacheGetValidateRow(licenseKey);
  if (!row) {
    row = await env.DB.prepare("SELECT * FROM licenses WHERE license_key = ?")
      .bind(licenseKey)
      .first();
    if (row && row.status === "active") {
      cacheSetValidateRow(licenseKey, row);
    }
  } else {
    if (row.expires_at && new Date(row.expires_at) < new Date()) {
      cacheDelValidateRow(licenseKey);
      row = await env.DB.prepare("SELECT * FROM licenses WHERE license_key = ?")
        .bind(licenseKey)
        .first();
    }
  }
  if (!row) {
    if (!throttle(`nf|${licenseKey.slice(0, 8)}`, 20, 60 * 60 * 1000)) {
      await logLicenseEvent(env.DB, { licenseKey, event: "not_found", deviceId });
    }
    return json({
      ok: false,
      valid: false,
      error: "not_found",
      message: "License key not found.",
    }, 404);
  }
  if (row.status === "revoked") {
    await logLicenseEvent(env.DB, { licenseId: row.id, licenseKey, event: "revoked", deviceId });
    return json({
      ok: false,
      valid: false,
      error: "revoked",
      message: "License has been revoked.",
    }, 403);
  }
  if (row.expires_at && new Date(row.expires_at) < new Date()) {
    await logLicenseEvent(env.DB, { licenseId: row.id, licenseKey, event: "expired", deviceId });
    return json({
      ok: false,
      valid: false,
      error: "expired",
      message: "License has expired.",
      expiresAt: row.expires_at,
    }, 403);
  }
  if (row.bound_device_id && row.bound_device_id !== deviceId) {
    // Never echo the bound device id back — the fact of a conflict is enough.
    await logLicenseEvent(env.DB, { licenseId: row.id, licenseKey, event: "bound_other", deviceId });
    return json({
      ok: false,
      valid: false,
      error: "bound_to_other_device",
      message: "This key is already bound to another device. Reset binding in the admin dashboard.",
    }, 409);
  }

  const bindNow = !row.bound_device_id;
  await env.DB.prepare(
    `UPDATE licenses
     SET bound_device_id = ?, bound_at = COALESCE(bound_at, ?), last_validated_at = ?
     WHERE id = ?`,
  )
    .bind(deviceId, bindNow ? nowIso() : row.bound_at, nowIso(), row.id)
    .run();
  // Keep cache warm for next poll — 10k shops poll every 5 min
  try {
    const fresh = await env.DB.prepare("SELECT * FROM licenses WHERE id = ?").bind(row.id).first();
    if (fresh) cacheSetValidateRow(licenseKey, fresh);
  } catch {}
  await logLicenseEvent(env.DB, {
    licenseId: row.id,
    licenseKey,
    event: bindNow ? "bind" : "validate",
    deviceId,
  });

  const customer = await customerById(env.DB, row.customer_id);
  const next = await licenseById(env.DB, row.id);
  const access = accessOf(next);
  await pruneLicenseEvents(env.DB);
  const payload = {
    ok: true,
    valid: true,
    status: next.status,
    licenseKey: next.license_key,
    expiresAt: next.expires_at,
    boundDeviceId: next.bound_device_id,
    boundAt: next.bound_at,
    lastValidatedAt: next.last_validated_at,
    customer: {
      id: customer?.id,
      name: customer?.name || "",
      businessName: customer?.business_name || "",
      email: customer?.email || "",
    },
    graceHours: 48,
    // v1.1.59 plan entitlements — null lists keep the app at full access.
    plan: access ? access.plan : "full",
    allowedModels: access ? access.allowedModels : null,
    allowedFeatures: access ? access.allowedFeatures : null,
  };
  const signedAt = nowIso();
  const nonce = [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");
  const canonical = licenseCanonical({
    licenseKey: next.license_key,
    deviceId,
    status: next.status,
    expiresAt: next.expires_at,
    plan: payload.plan,
    features: payload.allowedFeatures || [],
    models: payload.allowedModels || [],
    signedAt,
    nonce,
  });
  const signature = await signLicensePayload(env, canonical);
  if (signature) {
    payload.signedAt = signedAt;
    payload.nonce = nonce;
    payload.signature = signature;
  }
  return json(payload);
}
