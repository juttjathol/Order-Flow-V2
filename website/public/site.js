const EMAIL = "contact@jathol.org";
function mailto(subject, lines) {
  return "mailto:" + EMAIL +
    "?subject=" + encodeURIComponent(subject) +
    "&body=" + encodeURIComponent(lines.join("\n"));
}

// Ready-made contact buttons used to be raw mailto: links. On Windows Chrome
// with no default mail app — and inside an iframe preview — those clicks do
// nothing at all. Open an on-page draft instead; Gmail / copy always work.
function mailUrls(subject, body) {
  const q = (k, v) => k + "=" + encodeURIComponent(v);
  return {
    mailto: "mailto:" + EMAIL + "?" + q("subject", subject) + "&" + q("body", body),
    gmail: "https://mail.google.com/mail/?view=cm&fs=1&tf=1&" +
      q("to", EMAIL) + "&" + q("su", subject) + "&" + q("body", body),
  };
}

function fallbackCopy(text) {
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.setAttribute("readonly", "");
  ta.style.cssText = "position:fixed;left:-9999px;top:0";
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand("copy"); } catch (_) {}
  ta.remove();
}

function copyText(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    return navigator.clipboard.writeText(text).catch(() => fallbackCopy(text));
  }
  fallbackCopy(text);
  return Promise.resolve();
}

let mailDraftLastFocus = null;

function ensureDraftUi() {
  let root = document.getElementById("mail-draft");
  if (root) return root;

  root = document.createElement("div");
  root.id = "mail-draft";
  root.className = "mail-draft";
  root.hidden = true;
  root.setAttribute("role", "dialog");
  root.setAttribute("aria-modal", "true");
  root.setAttribute("aria-labelledby", "md-title");
  root.innerHTML =
    '<div class="mail-draft-card">' +
      '<button type="button" class="mail-draft-x" data-md-close aria-label="Close draft">&times;</button>' +
      '<p class="kicker">Email draft</p>' +
      '<h2 id="md-title">Ready to send</h2>' +
      '<p class="mail-draft-hint">Edit the message, then open it in Gmail, copy it, or hand it to your mail app. Nothing is sent from this website.</p>' +
      '<p class="mail-draft-label">To</p>' +
      '<p class="mail-draft-to">' + EMAIL + '</p>' +
      '<label class="mail-draft-label" for="md-subject">Subject</label>' +
      '<input id="md-subject" data-md-subject autocomplete="off"/>' +
      '<label class="mail-draft-label" for="md-body">Message</label>' +
      '<textarea id="md-body" data-md-body rows="12"></textarea>' +
      '<p class="mail-draft-status" data-md-status hidden></p>' +
      '<div class="mail-draft-actions">' +
        '<a class="btn btn-mint" data-md-gmail target="_blank" rel="noopener">Open in Gmail</a>' +
        '<button type="button" class="btn btn-ghost" data-md-copy>Copy draft</button>' +
        '<a class="btn btn-ghost" data-md-app>Open mail app</a>' +
      '</div>' +
    '</div>';
  document.body.appendChild(root);

  const card = root.querySelector(".mail-draft-card");
  const status = root.querySelector("[data-md-status]");
  const subjectEl = root.querySelector("[data-md-subject]");
  const bodyEl = root.querySelector("[data-md-body]");
  const gmailA = root.querySelector("[data-md-gmail]");
  const appA = root.querySelector("[data-md-app]");

  function current() {
    return { subject: subjectEl.value, body: bodyEl.value };
  }
  function syncHrefs() {
    const { subject, body } = current();
    const urls = mailUrls(subject, body);
    gmailA.href = urls.gmail;
    appA.href = urls.mailto;
  }
  function setStatus(msg) {
    if (!msg) { status.hidden = true; status.textContent = ""; return; }
    status.hidden = false;
    status.textContent = msg;
  }

  subjectEl.addEventListener("input", syncHrefs);
  bodyEl.addEventListener("input", syncHrefs);
  root._syncHrefs = syncHrefs;
  root._setStatus = setStatus;

  root.addEventListener("click", (e) => {
    if (e.target === root) closeMailDraft();
  });
  card.addEventListener("click", (e) => e.stopPropagation());
  root.querySelector("[data-md-close]").addEventListener("click", closeMailDraft);
  root.querySelector("[data-md-copy]").addEventListener("click", () => {
    const { subject, body } = current();
    const text = "To: " + EMAIL + "\nSubject: " + subject + "\n\n" + body;
    copyText(text).then(() => setStatus("Copied. Paste into Gmail, Outlook, or any mail app."));
  });
  appA.addEventListener("click", () => {
    setStatus("If nothing opened, your computer has no mail app set. Use Gmail or Copy draft.");
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !root.hidden) closeMailDraft();
  });
  return root;
}

function openMailDraft(subject, body) {
  const root = ensureDraftUi();
  mailDraftLastFocus = document.activeElement;
  root.querySelector("[data-md-subject]").value = subject || "Order Flow enquiry";
  root.querySelector("[data-md-body]").value = body || "";
  root._syncHrefs();
  root._setStatus("");
  root.hidden = false;
  document.body.style.overflow = "hidden";
  const ta = root.querySelector("[data-md-body]");
  ta.focus();
  try { ta.setSelectionRange(0, 0); } catch (_) {}
}

function closeMailDraft() {
  const root = document.getElementById("mail-draft");
  if (!root || root.hidden) return;
  root.hidden = true;
  document.body.style.overflow = "";
  if (mailDraftLastFocus && typeof mailDraftLastFocus.focus === "function") {
    try { mailDraftLastFocus.focus(); } catch (_) {}
  }
}

document.querySelectorAll(".js-mail-draft").forEach((a) => {
  a.addEventListener("click", (e) => {
    e.preventDefault();
    openMailDraft(
      a.getAttribute("data-mail-subject") || "Order Flow enquiry",
      (a.getAttribute("data-mail-body") || "").replace(/\r\n/g, "\n"),
    );
  });
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
  if (!name || !model || !phone) return;
  const body = [
    "Hello Jathol,",
    "",
    "I would like to request a 3-day trial of Order Flow for my business. Please issue a trial license key and share the steps to activate Main on our shop Wi‑Fi.",
    "",
    "Name: " + name,
    "Business model: " + model,
    "Email: " + (email || "(not given)"),
    "Phone number: " + phone,
    "",
    "Thank you.",
  ];
  openMailDraft("Order Flow — 3-day trial request", body.join("\n"));
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

// Count-up for plan prices (arm() can be re-run after currency re-renders)
const armPriceCounts = (() => {
  if (reduceMotion || !("IntersectionObserver" in window)) return () => {};
  const seen = new WeakSet();
  const cio = new IntersectionObserver((rows) => {
    for (const r of rows) {
      if (!r.isIntersecting) continue;
      cio.unobserve(r.target);
      if (seen.has(r.target)) continue;
      seen.add(r.target);
      const end = Number(r.target.dataset.count || 0);
      const t0 = performance.now();
      const dur = 900;
      const tick = (t) => {
        const k = Math.min(1, (t - t0) / dur);
        r.target.textContent = Math.round(end * (1 - Math.pow(1 - k, 3))).toLocaleString();
        if (k < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    }
  }, { threshold: 0.6 });
  return function arm() {
    document.querySelectorAll("[data-count]").forEach((el) => { if (!seen.has(el)) cio.observe(el); });
  };
})();
armPriceCounts();

// Plan CTA: pre-filled email draft per plan
document.querySelectorAll(".plan-cta").forEach((a) => {
  a.addEventListener("click", (e) => {
    e.preventDefault();
    const plan = a.dataset.plan || "a plan";
    const body = [
      "Hello Jathol,",
      "",
      `I would like the ${plan} for Order Flow. Please share the payment details and the steps to activate Main on our shop Wi-Fi.`,
      "",
      "Name: ",
      "Business Name: ",
      "Email: ",
      "Phone number: ",
      "Business model: ",
      "",
      "Thank you.",
    ];
    openMailDraft("Order Flow — " + plan, body.join("\n"));
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

// ── v1.1.59+: plan prices in the visitor's currency ────────────────────
// Geo lookup: our own Cloudflare Pages Function /geo only (request.cf.country
// edge header — no third-party IP-geolocation service). Runs only behind the
// storage-consent gate; if it fails, the currency select stays manual.
// Billing is always in RM — other currencies are marked as indicative.
const PLAN_CCY = {
  MYR: { sym: "RM ", pre: true },  IDR: { sym: "Rp ", pre: true },  THB: { sym: "฿", pre: true },
  PHP: { sym: "₱", pre: true },    VND: { sym: "₫", pre: false, sp: true }, INR: { sym: "₹", pre: true },
  PKR: { sym: "Rs ", pre: true },  BDT: { sym: "৳ ", pre: true },   LKR: { sym: "Rs ", pre: true },
  NPR: { sym: "Rs ", pre: true },  SGD: { sym: "S$ ", pre: true },  BND: { sym: "B$ ", pre: true },
  USD: { sym: "$", pre: true },    CAD: { sym: "C$ ", pre: true },  AUD: { sym: "A$ ", pre: true },
  NZD: { sym: "NZ$ ", pre: true }, EUR: { sym: "€", pre: true },    GBP: { sym: "£", pre: true },
  AED: { sym: "AED ", pre: true }, SAR: { sym: "SAR ", pre: true }, QAR: { sym: "QR ", pre: true },
  KWD: { sym: "KD ", pre: true },  CNY: { sym: "¥", pre: true },    HKD: { sym: "HK$ ", pre: true },
  TWD: { sym: "NT$ ", pre: true }, JPY: { sym: "¥", pre: true },    KRW: { sym: "₩", pre: true },
  TRY: { sym: "₺", pre: true },    ZAR: { sym: "R ", pre: true },   NGN: { sym: "₦", pre: true },
  KES: { sym: "KSh ", pre: true }, EGP: { sym: "E£ ", pre: true },  BRL: { sym: "R$ ", pre: true },
  MXN: { sym: "MX$", pre: true },  PLN: { sym: "zł", pre: false, sp: true }, MVR: { sym: "Rf ", pre: true },
  MMK: { sym: "K ", pre: true },   KHR: { sym: "៛", pre: true },    LAK: { sym: "₭", pre: true },
};
const PLAN_COUNTRY = {
  MY: "MYR", ID: "IDR", TH: "THB", PH: "PHP", VN: "VND", MM: "MMK", KH: "KHR", LA: "LAK",
  SG: "SGD", BN: "BND", IN: "INR", PK: "PKR", BD: "BDT", LK: "LKR", NP: "NPR", MV: "MVR",
  AE: "AED", SA: "SAR", QA: "QAR", KW: "KWD", US: "USD", CA: "CAD", GB: "GBP", IE: "EUR",
  DE: "EUR", FR: "EUR", IT: "EUR", ES: "EUR", NL: "EUR", BE: "EUR", AT: "EUR", PT: "EUR",
  FI: "EUR", GR: "EUR", SK: "EUR", SI: "EUR", EE: "EUR", LV: "EUR", LT: "EUR", MT: "EUR",
  CY: "EUR", HR: "EUR", LU: "EUR", HK: "HKD", TW: "TWD", CN: "CNY", JP: "JPY", KR: "KRW",
  AU: "AUD", NZ: "NZD", ZA: "ZAR", KE: "KES", NG: "NGN", TR: "TRY", EG: "EGP", BR: "BRL",
  MX: "MXN", PL: "PLN",
};
const PLAN_CCY_CHOICES = ["MYR", "IDR", "THB", "PHP", "VND", "INR", "PKR", "BDT", "SGD", "BND",
  "AED", "SAR", "QAR", "USD", "CAD", "EUR", "GBP", "AUD", "NZD", "CNY", "HKD", "TWD", "JPY",
  "KRW", "TRY", "ZAR", "NGN", "KES", "EGP", "BRL", "MXN", "PLN", "LKR", "NPR", "MMK", "KHR", "LAK", "MVR", "KWD"];

async function initPlanCurrency() {
  const bar = document.getElementById("currency-bar");
  const sel = document.getElementById("cur-select");
  const note = document.getElementById("cur-note");
  if (!bar || !sel || !note) return;
  if (!hasConsent() || initPlanCurrency.running) return; // no consent → plain RM, zero third-party calls
  initPlanCurrency.running = true;

  let rates = null;
  try {
    const cached = JSON.parse(sessionStorage.getItem("of-myr-rates") || "null");
    if (cached && Date.now() - cached.t < 12 * 3600 * 1000) {
      rates = cached.r;
    } else {
      const res = await fetch("https://open.er-api.com/v6/latest/MYR");
      const j = await res.json();
      if (j && j.result === "success" && j.rates) {
        rates = j.rates;
        sessionStorage.setItem("of-myr-rates", JSON.stringify({ t: Date.now(), r: rates }));
      }
    }
  } catch (_) {}
  if (!rates) return; // rates unreachable → plain RM display (current look)

  const valid = (c) => c && Object.prototype.hasOwnProperty.call(rates, c) && PLAN_CCY[c];

  function snap(v) {
    if (v >= 10000) return Math.round(v / 1000) * 1000;
    if (v >= 1000) return Math.round(v / 50) * 50;
    if (v >= 100) return Math.round(v / 5) * 5;
    return v;
  }

  function renderPrices(ccy) {
    const rate = ccy === "MYR" ? 1 : (rates[ccy] || 1);
    document.querySelectorAll(".plan-price[data-myr]").forEach((el) => {
      const myr = Number(el.dataset.myr || 0);
      const meta = PLAN_CCY[ccy] || { sym: ccy + " ", pre: true };
      // RM is the billing currency — show it exactly, never snapped.
      const v = ccy === "MYR" ? myr : snap(myr * rate);
      const txt = Number.isInteger(v) ? v.toLocaleString() : v.toFixed(2);
      const numAttr = (ccy === "MYR" || v >= 100) ? ` data-count="${Math.round(v)}"` : "";
      const b = `<b${numAttr}>${txt}</b>`;
      const sym = meta.pre ? `<span>${meta.sym}</span>` : `<span>${meta.sym.trim()}${meta.sp ? " " : ""}</span>`;
      const anchor = ccy === "MYR" ? "/month" : `≈ RM ${myr}/mo`;
      el.innerHTML = meta.pre ? sym + b + `<small>${anchor}</small>` : b + sym + `<small>${anchor}</small>`;
    });
    armPriceCounts();
    bar.hidden = false;
    sel.value = ccy;
    note.textContent = ccy === "MYR"
      ? "Malaysian Ringgit — the billed currency."
      : `Indicative at today's market rate · billing is in RM.`;
  }

  async function detectCountry() {
    try {
      const g = await fetch("./geo", { cache: "no-store" });
      if (g.ok) {
        const cc = String((await g.json()).country || "").toUpperCase();
        if (/^[A-Z]{2}$/.test(cc)) return cc;
      }
    } catch (_) {}
    return "";
  }

  sel.innerHTML = `<option value="auto">🌐 Auto (my country)</option>` +
    PLAN_CCY_CHOICES.map((c) => `<option value="${c}">${c} · ${(PLAN_CCY[c].sym || "").trim()}</option>`).join("");

  let autoTried = false;
  async function applyAuto() {
    autoTried = true;
    const cc = await detectCountry();
    const ccy = cc && PLAN_COUNTRY[cc] && valid(PLAN_COUNTRY[cc]) ? PLAN_COUNTRY[cc] : "MYR";
    renderPrices(ccy);
    if (cc) note.textContent += ccy === "MYR" ? "" : ` Detected from country ${cc}.`;
  }

  sel.addEventListener("change", () => {
    if (sel.value === "auto") {
      localStorage.removeItem("of-ccy");
      applyAuto();
    } else {
      localStorage.setItem("of-ccy", sel.value);
      renderPrices(sel.value);
      note.textContent += " Saved for your next visit — pick Auto to reset.";
    }
  });

  initPlanCurrency.running = false;
  const saved = (() => { try { return localStorage.getItem("of-ccy"); } catch (_) { return null; } })();
  if (valid(saved)) renderPrices(saved);
  else await applyAuto();
}
window.ofInitCurrency = initPlanCurrency;
initPlanCurrency();

// ── cookie/storage consent banner (asks once; choice remembered locally) ──
(function consentBar() {
  const cbar = document.getElementById("cookiebar");
  if (!cbar) return;
  let have = null;
  try { have = localStorage.getItem(CONSENT_KEY) || sessionStorage.getItem(CONSENT_KEY); } catch (_) {}
  if (have === "yes" || have === "no") return; // already decided
  cbar.hidden = false;
  const decide = (v) => {
    try { localStorage.setItem(CONSENT_KEY, v); }
    catch (_) { try { sessionStorage.setItem(CONSENT_KEY, v); } catch (__) {} }
    if (v === "no") { try { localStorage.removeItem("of-ccy"); sessionStorage.removeItem("of-myr-rates"); } catch (_) {} }
    cbar.hidden = true;
    if (v === "yes") initPlanCurrency();
  };
  document.getElementById("cb-accept")?.addEventListener("click", () => decide("yes"));
  document.getElementById("cb-decline")?.addEventListener("click", () => decide("no"));
})();

// ── screenshots gallery: keyboard friendly ──
document.querySelectorAll(".fx-gallery").forEach((g) => {
  const scroller = [g, g.querySelector(".fx-track")].find(
    (el) => el && el.scrollWidth - el.clientWidth > 24 || (el && getComputedStyle(el).overflowX === "auto") || (el && getComputedStyle(el).overflowX === "scroll")
  );
  if (!scroller) return;
  g.addEventListener("keydown", (e) => {
    const dir = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
    if (!dir) return;
    e.preventDefault();
    scroller.scrollBy({ left: dir * Math.max(280, scroller.clientWidth * 0.8), behavior: "smooth" });
  });
});