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
// kFeatureCatalog in the app (kFeatureCatalog lists ALL fifteen).
const FEATURE_KEYS = new Set([...CORE_FEATURE_KEYS, "cloud_sync", "qr_branding"]);
const MODEL_KEYS = new Set(["restaurant", "retail", "fastfood", "services"]);
const PLAN_PRESETS = {
  starter: [],
  growth: [...CORE_FEATURE_KEYS],
  custom: [...FEATURE_KEYS],
  full: [...FEATURE_KEYS],
};

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
function accessOf(row) {
  if (row == null) return null;
  const models = parseJsonArray(row.allowed_models);
  const features = parseJsonArray(row.allowed_features);
  if (models === null && features === null && (!row.plan || row.plan === "full")) {
    return null;
  }
  return {
    plan: row.plan || "full",
    allowedModels: models ?? [...MODEL_KEYS],
    allowedFeatures: features ?? [...FEATURE_KEYS],
  };
}

function normalizeAccess(body) {
  const plan = ["starter", "growth", "custom", "full"].includes(body.plan) ? body.plan : "full";
  const models = Array.isArray(body.allowedModels)
    ? body.allowedModels.filter((m) => MODEL_KEYS.has(m))
    : [...MODEL_KEYS];
  const features = Array.isArray(body.allowedFeatures)
    ? body.allowedFeatures.filter((f) => FEATURE_KEYS.has(f))
    : [...PLAN_PRESETS[plan]];
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

async function customerById(db, id) {
  return db.prepare("SELECT * FROM customers WHERE id = ?").bind(id).first();
}

async function licenseById(db, id) {
  return db.prepare("SELECT * FROM licenses WHERE id = ?").bind(id).first();
}

function publicLicense(row, customer) {
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
    allowedModels: accessOf(row)?.allowedModels ?? null,
    allowedFeatures: accessOf(row)?.allowedFeatures ?? null,
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

  const path = pathOf(context);
  const method = request.method.toUpperCase();

  try {
    if (path === "v1/health" && method === "GET") {
      return json({ ok: true, app: "order-flow-saas", version: "1.0.0" });
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
        const next = await licenseById(env.DB, id);
        const cust = await customerById(env.DB, next.customer_id);
        return json({ ok: true, license: publicLicense(next, cust) });
      }
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

async function pruneLicenseEvents(db) {
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
  const row = await env.DB.prepare("SELECT * FROM licenses WHERE license_key = ?")
    .bind(licenseKey)
    .first();
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
