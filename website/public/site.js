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
  const el = document.getElementById("apk-meta");
  if (!el) return;
  el.textContent = "Current official app for Android.";
  try {
    const res = await fetch("/download?meta=1");
    const data = await res.json();
    if (!data.ok || !data.tag) return;
    const ver = String(data.tag).replace(/^v/i, "");
    const mb = data.size ? ` · ${(data.size / (1024 * 1024)).toFixed(1)} MB` : "";
    el.textContent = `Version ${ver}${mb}`;
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
    if (blob.size < 10000) throw new Error("empty");
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
    if (statusEl) statusEl.textContent = "Starting download…";
    window.location.assign("/download");
  }
}

document.getElementById("trial-form")?.addEventListener("submit", (e) => {
  e.preventDefault();
  const name = document.getElementById("t-name").value.trim();
  const model = document.getElementById("t-model").value.trim();
  const email = document.getElementById("t-email").value.trim();
  const phone = document.getElementById("t-phone").value.trim();
  if (!name || !model || !email || !phone) return;
  const body = [
    "Name: " + name,
    "Business model: " + model,
    "Email: " + email,
    "Phone number: " + phone,
    "",
    "Hello Jathol,",
    "",
    "I would like to request a 3-day trial of Order Flow for my business. Please issue a trial license key and share the steps to activate Main on our shop Wi‑Fi.",
    "",
    "Thank you.",
  ].join("\n");
  window.location.href = "https://wa.me/Jathol_Jutt?text=" + encodeURIComponent(body);
});
document.getElementById("dl-btn")?.addEventListener("click", startDownload);
document.querySelectorAll("[data-apk]").forEach((el) => {
  el.addEventListener("click", (e) => {
    if (el.getAttribute("href") === "#download") return;
    startDownload(e);
  });
});

// ── v1.1.59: scroll reveals, price count-up, plan CTAs, hero parallax ──
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

// Scroll reveal (additive; hero .reveal animations above stay untouched)
try {
  const io = new IntersectionObserver((rows) => {
    for (const r of rows) {
      if (r.isIntersecting) { r.target.classList.add("revealed"); io.unobserve(r.target); }
    }
  }, { threshold: 0.15 });
  document.querySelectorAll("[data-reveal]").forEach((el) => io.observe(el));
} catch (_) {
  document.querySelectorAll("[data-reveal]").forEach((el) => el.classList.add("revealed"));
}

// Count-up for plan prices
try {
  const nums = document.querySelectorAll("[data-count]");
  if (!reduceMotion && "IntersectionObserver" in window) {
    const cio = new IntersectionObserver((rows) => {
      for (const r of rows) {
        if (!r.isIntersecting) continue;
        cio.unobserve(r.target);
        const end = Number(r.target.dataset.count || 0);
        const t0 = performance.now();
        const dur = 900;
        const tick = (t) => {
          const k = Math.min(1, (t - t0) / dur);
          r.target.textContent = Math.round(end * (1 - Math.pow(1 - k, 3)));
          if (k < 1) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      }
    }, { threshold: 0.6 });
    nums.forEach((el) => cio.observe(el));
  }
} catch (_) {}

// Plan CTA: pre-filled WhatsApp message per plan
document.querySelectorAll(".plan-cta").forEach((a) => {
  a.addEventListener("click", (e) => {
    e.preventDefault();
    const plan = a.dataset.plan || "a plan";
    const body = [
      "Name: ",
      "Business Name: ",
      "Email: ",
      "Phone number: ",
      "Business model: ",
      "",
      "Hello Jathol,",
      "",
      `I would like the ${plan} plan for Order Flow. Please share the payment details and the steps to activate Main on our shop Wi-Fi.`,
      "",
      "Thank you.",
    ].join("\n");
    window.location.href = "https://wa.me/Jathol_Jutt?text=" + encodeURIComponent(body);
  });
});

// Gentle hero parallax (only when motion is allowed)
if (!reduceMotion) {
  const heroBg = document.querySelector(".hero-bg");
  if (heroBg) {
    let raf = 0;
    window.addEventListener("scroll", () => {
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        const y = Math.min(160, window.scrollY * 0.18);
        heroBg.style.transform = `translateY(${y}px) scale(1.1)`;
      });
    }, { passive: true });
  }
}
