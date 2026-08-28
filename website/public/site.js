const WA =
  "https://wa.me/Jathol_Jutt?text=" +
  encodeURIComponent(
    [
      "Name: ",
      "Business Name: ",
      "Email: ",
      "Phone number: ",
      "",
      "Hello Jathol,",
      "",
      "I would like to purchase an Order Flow license key for my business. Please share the available plans and payment details.",
      "",
      "Thank you.",
    ].join("\n"),
  );

document.querySelectorAll("#wa-hero, #wa-main, #wa-foot").forEach((a) => {
  if (a) a.href = WA;
});

const year = document.getElementById("y");
if (year) year.textContent = String(new Date().getFullYear());

const bar = document.getElementById("progress");
window.addEventListener(
  "scroll",
  () => {
    const h = document.documentElement;
    const max = h.scrollHeight - h.clientHeight;
    if (bar && max > 0) bar.style.width = `${(h.scrollTop / max) * 100}%`;
  },
  { passive: true },
);

async function apkMeta() {
  try {
    const res = await fetch("/download?meta=1");
    const data = await res.json();
    if (!data.ok) return;
    const tag = document.getElementById("apk-tag");
    const size = document.getElementById("apk-size");
    if (tag) tag.textContent = data.tag || "latest";
    if (size && data.size) size.textContent = `${(data.size / (1024 * 1024)).toFixed(1)} MB`;
  } catch (_) {}
}
apkMeta();

const statusEl = document.getElementById("dl-status");
async function startDownload(ev) {
  if (ev) ev.preventDefault();
  if (statusEl) statusEl.textContent = "Preparing your download…";
  try {
    const res = await fetch("/download");
    if (!res.ok) throw new Error("busy");
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "Order-Flow.apk";
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    if (statusEl) statusEl.textContent = "Download started on this device.";
  } catch (_) {
    if (statusEl) statusEl.textContent = "Could not start the download. Try again, or message WhatsApp.";
  }
}

document.getElementById("dl-btn")?.addEventListener("click", startDownload);
document.querySelectorAll("[data-apk]").forEach((el) => {
  el.addEventListener("click", (e) => {
    if (el.getAttribute("href") === "#download") return;
    startDownload(e);
  });
});
