const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,PATCH,DELETE,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

function json(data, status = 200, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS, ...extra },
  });
}

function pathOf(context) {
  const p = context.params?.path;
  if (Array.isArray(p)) return p.filter(Boolean).join("/");
  if (typeof p === "string") return p.replace(/^\/+|\/+$/g, "");
  const url = new URL(context.request.url);
  return url.pathname.replace(/^\/api\/?/, "").replace(/^\/+|\/+$/g, "");
}

async function readJson(request) {
  try {
    const text = await request.text();
    if (!text) return {};
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

async function hmacHex(secret, data) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(data));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function issueToken(env, hours = 12) {
  const secret = env.ADMIN_SECRET || env.ADMIN_PASSWORD;
  const payload = btoa(JSON.stringify({ iat: Date.now(), exp: Date.now() + hours * 3600_000 }));
  const sig = await hmacHex(secret, payload);
  return `${payload}.${sig}`;
}

async function verifyToken(env, header) {
  if (!header || !header.startsWith("Bearer ")) return false;
  const token = header.slice(7).trim();
  const secret = env.ADMIN_SECRET || env.ADMIN_PASSWORD;
  if (!secret || !token.includes(".")) return false;
  const [payload, sig] = token.split(".");
  const expect = await hmacHex(secret, payload);
  if (expect !== sig) return false;
  try {
    const body = JSON.parse(atob(payload));
    return Number(body.exp) > Date.now();
  } catch {
    return false;
  }
}

function requireAdminPassword(env) {
  return env.ADMIN_PASSWORD || "";
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
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }
  if (!env.DB) {
    return json({ ok: false, error: "d1_not_configured", message: "Bind a D1 database as DB." }, 500);
  }

  const path = pathOf(context);
  const method = request.method.toUpperCase();

  try {
    if (path === "v1/health" && method === "GET") {
      return json({ ok: true, app: "order-flow-saas", version: "1.0.0" });
    }

    if (path === "v1/license/validate" && method === "POST") {
      return handleValidate(env, await readJson(request));
    }

    if (path === "admin/login" && method === "POST") {
      const body = await readJson(request);
      const expected = requireAdminPassword(env);
      if (!expected) {
        return json({ ok: false, error: "not_configured", message: "Set ADMIN_PASSWORD secret." }, 500);
      }
      if ((body.password || "") !== expected) {
        return json({ ok: false, error: "unauthorized", message: "Invalid password." }, 401);
      }
      const token = await issueToken(env);
      return json({ ok: true, token, expiresHours: 12 });
    }

    const authed = await verifyToken(env, request.headers.get("Authorization") || "");
    if (path.startsWith("admin/")) {
      if (!authed) return json({ ok: false, error: "unauthorized" }, 401);
    }

    if (path === "admin/me" && method === "GET") {
      return json({ ok: true, role: "admin" });
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
      try {
        await env.DB.prepare(
          `INSERT INTO licenses (id, customer_id, license_key, status, expires_at, created_at)
           VALUES (?, ?, ?, 'active', ?, ?)`,
        )
          .bind(id, customerId, key, expires, nowIso())
          .run();
      } catch (e) {
        return json({ ok: false, error: "key_conflict", message: String(e) }, 409);
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
        return json({ ok: true });
      }
      if (method === "POST" && action === "reset-device") {
        await env.DB.prepare(
          "UPDATE licenses SET bound_device_id = NULL, bound_at = NULL WHERE id = ?",
        )
          .bind(id)
          .run();
        const next = await licenseById(env.DB, id);
        return json({ ok: true, license: publicLicense(next) });
      }
      if (method === "POST" && action === "extend") {
        const nextExp = addDays(row.expires_at, 30);
        await env.DB.prepare("UPDATE licenses SET expires_at = ? WHERE id = ?")
          .bind(nextExp, id)
          .run();
        const next = await licenseById(env.DB, id);
        return json({ ok: true, license: publicLicense(next) });
      }
      if (method === "POST" && action === "revoke") {
        await env.DB.prepare("UPDATE licenses SET status = 'revoked' WHERE id = ?").bind(id).run();
        const next = await licenseById(env.DB, id);
        return json({ ok: true, license: publicLicense(next) });
      }
    }

    return json({ ok: false, error: "not_found", path }, 404);
  } catch (error) {
    return json({ ok: false, error: "server_error", message: String(error) }, 500);
  }
}

async function handleValidate(env, body) {
  const licenseKey = String(body.licenseKey || body.license_key || "").trim().toUpperCase();
  const deviceId = String(body.deviceId || body.device_id || "").trim();
  if (!licenseKey || !deviceId) {
    return json({ ok: false, valid: false, error: "missing_fields" }, 400);
  }
  const row = await env.DB.prepare("SELECT * FROM licenses WHERE license_key = ?")
    .bind(licenseKey)
    .first();
  if (!row) {
    return json({
      ok: false,
      valid: false,
      error: "not_found",
      message: "License key not found.",
    }, 404);
  }
  if (row.status === "revoked") {
    return json({
      ok: false,
      valid: false,
      error: "revoked",
      message: "License has been revoked.",
    }, 403);
  }
  if (row.expires_at && new Date(row.expires_at) < new Date()) {
    return json({
      ok: false,
      valid: false,
      error: "expired",
      message: "License has expired.",
      expiresAt: row.expires_at,
    }, 403);
  }
  if (row.bound_device_id && row.bound_device_id !== deviceId) {
    return json({
      ok: false,
      valid: false,
      error: "bound_to_other_device",
      message: "This key is already bound to another device. Reset binding in the admin dashboard.",
      boundDeviceId: row.bound_device_id,
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

  const customer = await customerById(env.DB, row.customer_id);
  const next = await licenseById(env.DB, row.id);
  return json({
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
  });
}
