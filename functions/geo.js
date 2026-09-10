// Visitor country for plan-price currency (Cloudflare edge metadata only).
// Returns e.g. {"country":"MY"} — no IP is stored or forwarded anywhere.
export async function onRequestGet(context) {
  const cf = (context.request && context.request.cf) || {};
  const country = String(cf.country || "");
  return new Response(JSON.stringify({ country }), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
