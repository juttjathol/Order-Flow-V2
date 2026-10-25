// Same-origin relay-forwarder for the POS webapp.
//
// jathol.org (jathol-order-flow Pages) has NO D1 binding — the real Order Flow
// API + license database live on the order-flow-v2 Pages project. Browsers
// calling that origin directly fail silently whenever CORS allow-listing is
// off/misconfigured, which manifested as "Activate does nothing / http_405".
// This function forwards /api/cloud/* SERVER-SIDE, so the webapp talks strict
// same-origin: no CORS preflight, no allow-origin env dependency.
//
// Mirror copies exist in ./functions (repo root) and ./website/functions —
// keep them in sync, same as download.js / geo.js.

const UPSTREAM_HOST = "order-flow-v2.pages.dev";

export async function onRequest(context) {
  const { request } = context;
  const url = new URL(request.url);
  const upstream = "https://" + UPSTREAM_HOST + url.pathname + url.search;

  const headers = new Headers();
  const ct = request.headers.get("content-type");
  if (ct) headers.set("content-type", ct);
  const auth = request.headers.get("authorization");
  if (auth) headers.set("authorization", auth);
  headers.set("x-of-proxy", "jathol.org");

  const init = { method: request.method, headers, redirect: "manual" };
  if (request.method !== "GET" && request.method !== "HEAD") {
    init.body = await request.arrayBuffer();
  }

  let resp;
  try {
    resp = await fetch(upstream, init);
  } catch (e) {
    return Response.json(
      { ok: false, error: "upstream_unreachable" },
      { status: 502, headers: { "content-type": "application/json" } }
    );
  }

  const out = new Response(resp.body, {
    status: resp.status,
    statusText: resp.statusText,
  });
  out.headers.set("content-type", resp.headers.get("content-type") || "application/json");
  const ra = resp.headers.get("retry-after");
  if (ra) out.headers.set("retry-after", ra);
  // Same-origin in normal use; permissive CORS so nothing in the chain can block it.
  out.headers.set("Access-Control-Allow-Origin", request.headers.get("origin") || "*");
  out.headers.set("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  out.headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  return out;
}
