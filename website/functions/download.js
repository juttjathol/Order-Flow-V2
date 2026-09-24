// Jathol Order Flow — "always the latest APK" worker.
// Identical copy lives at ./functions/download.js (repo root, serves the
// jathol Pages project), ./website/functions/download.js and
// ./cloudflare_dashboard/functions/download.js — keep them in sync.
const REPO = "juttjathol/Order-Flow-V2";
const FALLBACK_TAG = "v1.1.75";
const FALLBACK_APK = `https://github.com/${REPO}/releases/download/${FALLBACK_TAG}/app-release.apk`;

// ── security: burst throttle + short meta cache (per isolate) ────────────
// GitHub allows ~5000 authenticated API calls/hour. Without this, a scanner
// hitting ?meta=1 could burn the quota and starve real visitors mid-release.
const hits = new Map();
function overLimit(key, max, windowMs) {
  const now = Date.now();
  let a = hits.get(key);
  if (!a) { a = []; hits.set(key, a); }
  a.push(now);
  while (a.length && now - a[0] > windowMs) a.shift();
  if (hits.size > 4000) {
    for (const [k, v] of hits) if (!v.length || now - v[v.length - 1] > 10 * windowMs) hits.delete(k);
  }
  return a.length > max;
}
function ipOf(request) {
  return (request.headers.get("cf-connecting-ip") || "na").split(",")[0].trim();
}
let metaCache = { t: 0, body: null, status: 200 };
const SEC = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
};

function ghHeaders(env, extra = {}) {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "jathol-order-flow-apk",
    ...extra,
  };
  // Token comes from Pages env secrets only — never committed, never echoed.
  if (env.GITHUB_TOKEN) headers.Authorization = `Bearer ${env.GITHUB_TOKEN}`;
  return headers;
}

function apkAsset(release) {
  return (release.assets || []).find((a) => String(a.name || "") === "app-release.apk");
}

function skipRelease(release) {
  if (!release || release.draft || release.prerelease) return true;
  return /-rc\d*/i.test(String(release.tag_name || ""));
}

async function latestApk(env) {
  const listRes = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=30`, {
    headers: ghHeaders(env),
  });
  if (listRes.ok) {
    const list = await listRes.json();
    if (Array.isArray(list)) {
      for (const release of list) {
        if (skipRelease(release)) continue;
        const asset = apkAsset(release);
        if (asset) return { release, asset };
      }
    }
  }

  const latestRes = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
    headers: ghHeaders(env),
  });
  if (latestRes.ok) {
    const release = await latestRes.json();
    if (!skipRelease(release)) {
      const asset = apkAsset(release);
      if (asset) return { release, asset };
    }
  }

  // Rate-limited or API blip: fall back to the pinned release tag so shoppers
  // can still download the current build.
  return {
    release: { tag_name: FALLBACK_TAG, published_at: null },
    asset: {
      name: "app-release.apk",
      size: 0,
      url: "",
      browser_download_url: FALLBACK_APK,
    },
  };
}

async function fetchApk(env, asset) {
  const urls = [asset.browser_download_url, FALLBACK_APK].filter(Boolean);
  for (const url of urls) {
    const res = await fetch(url, { redirect: "follow" });
    if (res.ok) return res;
  }
  if (asset.url) {
    const viaApi = await fetch(asset.url, {
      headers: ghHeaders(env, { Accept: "application/octet-stream" }),
      redirect: "follow",
    });
    if (viaApi.ok) return viaApi;
  }
  throw new Error("apk_fetch");
}

export async function onRequest(context) {
  if (context.request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,HEAD" },
    });
  }
  return onRequestGet(context);
}

export async function onRequestGet(context) {
  const { env, request } = context;
  const url = new URL(request.url);

  if (url.searchParams.get("meta") === "1") {
    if (overLimit(ipOf(request) + "|meta", 40, 60000)) {
      return new Response(JSON.stringify({ ok: false, error: "slow_down" }), {
        status: 429,
        headers: { "Content-Type": "application/json", "Retry-After": "60", ...SEC },
      });
    }
    if (metaCache.body && Date.now() - metaCache.t < 45000) {
      return new Response(metaCache.body, {
        status: metaCache.status,
        headers: { "Content-Type": "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=45", ...SEC },
      });
    }
    try {
      const { release, asset } = await latestApk(env);
      const body = JSON.stringify({
        ok: true,
        tag: release.tag_name,
        publishedAt: release.published_at,
        size: asset.size,
        name: "Order-Flow.apk",
      });
      metaCache = { t: Date.now(), body, status: 200 };
      return new Response(body, {
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Access-Control-Allow-Origin": "*",
          "Cache-Control": "public, max-age=60",
          ...SEC,
        },
      });
    } catch (e) {
      console.error("meta failed:", e && e.message); // cause stays server-side
      const body = JSON.stringify({ ok: false, error: "release_lookup_failed" });
      metaCache = { t: Date.now(), body, status: 502 };
      return new Response(body, {
        status: 502,
        headers: { "Content-Type": "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*", ...SEC },
      });
    }
  }

  if (overLimit(ipOf(request) + "|apk", 10, 60000)) {
    return new Response("Too many downloads from your network right now — try again in a minute.", {
      status: 429,
      headers: { "Retry-After": "60", ...SEC },
    });
  }
  try {
    const { asset } = await latestApk(env);
    const file = await fetchApk(env, asset);
    return new Response(file.body, {
      headers: {
        "Content-Type": "application/vnd.android.package-archive",
        "Content-Disposition": 'attachment; filename="Order-Flow.apk"',
        "Cache-Control": "private, max-age=60",
        "Access-Control-Allow-Origin": "*",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch (e) {
    console.error("apk stream failed:", e && e.message);
    return new Response("The Android app is being prepared. Please try again shortly.", { status: 502, headers: { ...SEC } });
  }
}
