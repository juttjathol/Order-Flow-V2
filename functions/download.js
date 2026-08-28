const REPO = "juttjathol/Order-Flow-V2";

function ghHeaders(env, extra = {}) {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "jathol-order-flow-apk",
    ...extra,
  };
  if (env.GITHUB_TOKEN) headers.Authorization = `Bearer ${env.GITHUB_TOKEN}`;
  return headers;
}

async function latestApk(env) {
  const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
    headers: ghHeaders(env),
  });
  if (!res.ok) throw new Error(`github_latest_${res.status}`);
  const data = await res.json();
  const asset = (data.assets || []).find((a) =>
    String(a.name || "").toLowerCase().endsWith(".apk"),
  );
  if (!asset) throw new Error("no_apk");
  return { release: data, asset };
}

async function fetchApk(env, asset) {
  const viaApi = await fetch(asset.url, {
    headers: ghHeaders(env, { Accept: "application/octet-stream" }),
    redirect: "follow",
  });
  if (viaApi.ok) return viaApi;
  const viaBrowser = await fetch(asset.browser_download_url, { redirect: "follow" });
  if (viaBrowser.ok) return viaBrowser;
  throw new Error(`apk_fetch_${viaApi.status}_${viaBrowser.status}`);
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
