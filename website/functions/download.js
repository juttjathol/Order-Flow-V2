const REPO = "juttjathol/Order-Flow-V2";
const FALLBACK_TAG = "v1.1.60";
const FALLBACK_APK = `https://github.com/${REPO}/releases/download/${FALLBACK_TAG}/app-release.apk`;

function ghHeaders(env, extra = {}) {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "jathol-order-flow-apk",
    ...extra,
  };
  if (env.GITHUB_TOKEN) headers.Authorization = `Bearer ${env.GITHUB_TOKEN}`;
  return headers;
}

function apkAsset(release) {
  return (release.assets || []).find((a) => String(a.name || "").toLowerCase().endsWith(".apk"));
}

async function latestApk(env) {
  const listRes = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=30`, {
    headers: ghHeaders(env),
  });
  if (listRes.ok) {
    const list = await listRes.json();
    if (Array.isArray(list)) {
      for (const release of list) {
        if (release.draft) continue;
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
    const asset = apkAsset(release);
    if (asset) return { release, asset };
  }

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
    try {
      const { release, asset } = await latestApk(env);
      return new Response(
        JSON.stringify({
          ok: true,
          tag: release.tag_name,
          publishedAt: release.published_at,
          size: asset.size,
          name: "Order-Flow.apk",
        }),
        {
          headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "public, max-age=60",
          },
        },
      );
    } catch (e) {
      return new Response(JSON.stringify({ ok: false, error: String(e.message || e) }), {
        status: 502,
        headers: { "Content-Type": "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*" },
      });
    }
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
      },
    });
  } catch (e) {
    return new Response("The Android app is being prepared. Please try again shortly.", { status: 502 });
  }
}
