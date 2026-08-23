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
          name: asset.name,
          download: `${url.origin}/download`,
        }),
        { headers: { "Content-Type": "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*" } },
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
    const file = await fetch(asset.url, {
      headers: ghHeaders(env, { Accept: "application/octet-stream" }),
    });
    if (!file.ok) throw new Error(`apk_fetch_${file.status}`);
    return new Response(file.body, {
      headers: {
        "Content-Type": "application/vnd.android.package-archive",
        "Content-Disposition": 'attachment; filename="app-release.apk"',
        "Cache-Control": "public, max-age=120",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (e) {
    return new Response(`APK not available: ${e.message || e}`, { status: 502 });
  }
}
