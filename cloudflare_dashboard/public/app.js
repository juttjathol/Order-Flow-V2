const TOKEN_KEY = "of_admin_token";
function readToken() {
  try {
    const s = sessionStorage.getItem(TOKEN_KEY);
    if (s) return s;
    const old = localStorage.getItem(TOKEN_KEY);
    if (old) {
      sessionStorage.setItem(TOKEN_KEY, old);
      localStorage.removeItem(TOKEN_KEY);
      return old;
    }
  } catch {}
  return "";
}
function writeToken(v) {
  try {
    if (v) sessionStorage.setItem(TOKEN_KEY, v);
    else sessionStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(TOKEN_KEY);
  } catch {}
}

const state = {
  token: readToken(),
  customers: [],
  licF: { q: "", status: "all", plan: "all", sort: "expiry_asc" },
  custQ: "",
  licenses: [],
  broadcasts: [],
  theme: localStorage.getItem("of_theme") || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"),
};

const BROADCAST_TEMPLATES = {
  feature_kds: {
    title: "✨ New Feature: Kitchen Display Timers & Live Search",
    tag: "feature",
    url: "guide",
    message: "Track tickets with busy clocks on the Table Map, route orders to station printers, and use the instant search bar across kitchen & cashier screens to speed up service during peak hours.",
  },
  plan_growth: {
    title: "💎 Cloud add-on & Customize",
    tag: "plan",
    url: "https://jathol.org#plans",
    message: "Professional (PKR 2,000/mo) already includes 15 pro features — QR ordering too. Cloud networking is a PKR 500/month add-on; want a custom POS built for your business? Ask about Customize!",
  },
  tip_qr: {
    title: "💡 Restaurant Flow Tip: Cut Wait Times with Guest QR",
    tag: "tip",
    url: "floor",
    message: "Did you know? You can generate QR codes for each table from Floor > Table > QR. Guests scan with their camera to place orders directly into the kitchen, reducing server trips by 40%.",
  },
  tip_shift: {
    title: "📊 Audit & Control: End-of-Day Shift Close",
    tag: "tip",
    url: "more",
    message: "Close and reconcile daily register shifts with manager PIN security. Audit cash drawer discrepancies, staff sales, and payment breakdowns easily from the More menu.",
  },
  feature_display: {
    title: "⚡ Speed & Trust: Customer-Facing Display",
    tag: "feature",
    url: "guide",
    message: "Mount a second phone or tablet facing your customers to show live line items, taxes, and order totals in real-time. Turn it on in Station Shell > Role > Customer Display.",
  },
};

document.documentElement.dataset.theme = state.theme;

const $ = (id) => document.getElementById(id);

async function api(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...(options.headers || {}) };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;
  const res = await fetch(`/api/${path}`, { ...options, headers });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(data.message || data.error || res.statusText);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function toast(msg) {
  const el = $("toast");
  el.textContent = msg;
  el.classList.remove("hidden");
  setTimeout(() => el.classList.add("hidden"), 2800);
}

function showApp(on) {
  $("login").classList.toggle("hidden", on);
  $("app").classList.toggle("hidden", !on);
  const bar = $("bottom-tab-bar");
  if (bar) bar.classList.toggle("hidden", !on);
}

function setView(name) {
  ["home", "customers", "licenses", "broadcasts"].forEach((v) => {
    const el = $(`view-${v}`);
    if (el) el.classList.toggle("hidden", v !== name);
  });
  // Sidebar links (desktop/tablet)
  document.querySelectorAll(".side a").forEach((a) => {
    a.classList.toggle("active", a.dataset.view === name);
  });
  // Bottom tab buttons (mobile)
  document.querySelectorAll(".tab-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.view === name);
  });
  $("view-title").textContent =
    name === "home"
      ? "Overview"
      : name === "customers"
        ? "Customers"
        : name === "licenses"
          ? "License keys"
          : "Push Notifications";
  if (name === "broadcasts") {
    loadBroadcasts();
  }
}

function badge(kind, label) {
  return `<span class="badge ${kind}">${label}</span>`;
}

function planChips(l) {
  const KNOWN = ["starter", "growth", "custom", "full"];
  const raw = (l.plan || "full").toLowerCase();
  const plan = esc(KNOWN.includes(raw) ? raw : "custom"); // legacy rows can hold anything
  const nF = Array.isArray(l.allowedFeatures) ? l.allowedFeatures.length : "all";
  const nM = Array.isArray(l.allowedModels) ? l.allowedModels.length : 4;
  const legacy = l.allowedModels == null && l.allowedFeatures == null;
  return `
    <span class="badge plan plan-${plan}">${plan.toUpperCase()}</span>
    ${legacy
      ? '<span class="badge unbound" title="No plan data on this key — every feature stays on">all on</span>'
      : `<span class="badge bound" title="Features enabled by this key">${nF}/${FEATURES.length} feat · ${nM}/${MODELS.length} models</span>`}`;
}

function esc(v) {
  return String(v ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

const daysLeftOf = (iso) => {
  if (!iso) return null;
  return Math.ceil((new Date(iso).getTime() - Date.now()) / 86400000);
};

function statusBadgeOf(l) {
  if (l.status === "revoked") return badge("revoked", "Revoked");
  if (l.status === "paused") return badge("paused", "Paused");
  return badge("bound", "Active");
}

function expiryBadge(l) {
  const d = daysLeftOf(l.expiresAt);
  if (l.status !== "active" || d === null) return "";
  if (d < 0) return badge("revoked", `expired ${-d}d ago`);
  if (d <= 30) return badge("expiring", `${d}d left`);
  return "";
}

function licenseActionBtns(l) {
  const paused = l.status === "paused";
  const revoked = l.status === "revoked";
  return `
    <button class="secondary" data-copy="${esc(l.licenseKey)}">Copy</button>
    <button class="secondary" data-access="${l.id}">Access…</button>
    <button class="secondary" data-notice="${esc(l.licenseKey)}">Notify</button>
    <button class="secondary" data-reset="${l.id}">Reset device</button>
    <button class="secondary" data-extend="${l.id}">Extend…</button>
    ${!revoked ? `<button class="secondary" data-${paused ? "resume" : "pause"}="${l.id}">${paused ? "Resume" : "Pause"}</button>` : ""}
    ${!revoked && !paused ? `<button class="secondary" data-revoke="${l.id}">Revoke</button>` : ""}
    <button class="danger" data-dell="${l.id}">Delete</button>`;
}

function filteredLicenses() {
  let rows = [...state.licenses];
  const q = (state.licF.q || "").trim().toLowerCase();
  if (q) {
    rows = rows.filter((l) =>
      (l.licenseKey || "").toLowerCase().includes(q) ||
      (l.customer?.name || "").toLowerCase().includes(q) ||
      (l.customer?.businessName || "").toLowerCase().includes(q));
  }
  if (state.licF.status === "unbound") rows = rows.filter((l) => !l.boundDeviceId && l.status === "active");
  else if (state.licF.status !== "all") rows = rows.filter((l) => l.status === state.licF.status);
  if (state.licF.plan !== "all") rows = rows.filter((l) => (l.plan || "full").toLowerCase() === state.licF.plan);
  const s = state.licF.sort;
  if (s === "expiry_asc") rows.sort((a, b) => (a.expiresAt || "9").localeCompare(b.expiresAt || "9"));
  else if (s === "expiry_desc") rows.sort((a, b) => (b.expiresAt || "").localeCompare(a.expiresAt || ""));
  else if (s === "created_desc") rows.sort((a, b) => (b.createdAt || "").localeCompare(a.createdAt || ""));
  else if (s === "name_asc") rows.sort((a, b) => (a.customer?.name || "").localeCompare(b.customer?.name || ""));
  return rows;
}

function filteredCustomers() {
  const q = (state.custQ || "").trim().toLowerCase();
  if (!q) return state.customers;
  return state.customers.filter((c) =>
    (c.name || "").toLowerCase().includes(q) ||
    (c.business_name || "").toLowerCase().includes(q) ||
    (c.email || "").toLowerCase().includes(q) ||
    (c.phone || "").toLowerCase().includes(q));
}

function keysOf(customerId) {
  return state.licenses.filter((l) => l.customerId === customerId);
}

function renderCustomers() {
  const rows = filteredCustomers();
  // Desktop table
  $("c-body").innerHTML = rows.length === 0
    ? `<tr><td colspan="6" class="muted" style="text-align:center;padding:24px">No customers match.</td></tr>`
    : rows
    .map(
      (c) => `<tr>
        <td><strong>${esc(c.name)}</strong></td>
        <td>${esc(c.business_name || "")}</td>
        <td>${esc(c.email || "")}<br/>${esc(c.phone || "")}</td>
        <td>${keysOf(c.id).length}</td>
        <td class="muted">${esc((c.created_at || "").slice(0, 10))}</td>
        <td class="actions">
          <button class="secondary" data-issue="${c.id}">Issue key</button>
          <button class="secondary" data-viewkeys="${c.id}">Keys</button>
          <button class="danger" data-delc="${c.id}">Delete</button>
        </td>
      </tr>`,
    )
    .join("");

  // Mobile card list
  const cards = $("c-cards");
  if (cards) {
    if (rows.length === 0) {
      cards.innerHTML = `<p class="muted" style="text-align:center;padding:24px 0">No customers match.</p>`;
    } else {
      cards.innerHTML = rows
        .map(
          (c) => `<div class="m-card">
            <div class="m-card-row">
              <span class="m-card-label">Name</span>
              <span class="m-card-val"><strong>${esc(c.name)}</strong></span>
            </div>
            ${c.business_name ? `<div class="m-card-row"><span class="m-card-label">Business</span><span class="m-card-val">${esc(c.business_name)}</span></div>` : ""}
            ${c.email ? `<div class="m-card-row"><span class="m-card-label">Email</span><span class="m-card-val">${esc(c.email)}</span></div>` : ""}
            ${c.phone ? `<div class="m-card-row"><span class="m-card-label">Phone</span><span class="m-card-val">${esc(c.phone)}</span></div>` : ""}
            <div class="m-card-row"><span class="m-card-label">Keys</span><span class="m-card-val">${keysOf(c.id).length}</span></div>
            <div class="m-card-row"><span class="m-card-label">Created</span><span class="m-card-val muted">${esc((c.created_at || "").slice(0, 10))}</span></div>
            <div class="m-card-actions">
              <button class="secondary" data-issue="${c.id}">Issue key</button>
              <button class="secondary" data-viewkeys="${c.id}">Keys</button>
              <button class="danger" data-delc="${c.id}">Delete</button>
            </div>
          </div>`,
        )
        .join("");
    }
  }

  // Customer dropdown in license form
  $("l-customer").innerHTML = state.customers
    .map((c) => `<option value="${c.id}">${esc(c.name)} — ${esc(c.business_name || "shop")}</option>`)
    .join("");
}

function renderLicenses() {
  const rows = filteredLicenses();
  // Desktop table
  $("l-body").innerHTML = rows.length === 0
    ? `<tr><td colspan="6" class="muted" style="text-align:center;padding:24px">No license keys match.</td></tr>`
    : rows
    .map((l) => {
      const bind = l.boundDeviceId
        ? `${badge("bound", "Bound")}<div class="mono">${esc(l.boundDeviceId)}</div>`
        : badge("unbound", "Unbound");
      return `<tr>
        <td class="mono">${esc(l.licenseKey)}</td>
        <td>${esc(l.customer?.name || "")}</td>
        <td>${statusBadgeOf(l)}<div class="chips" style="margin-top:4px">${planChips(l)}</div></td>
        <td>${bind}</td>
        <td>${esc((l.expiresAt || "").slice(0, 10))}${expiryBadge(l)}</td>
        <td class="actions">${licenseActionBtns(l)}</td>
      </tr>`;
    })
    .join("");

  // Mobile card list
  const cards = $("l-cards");
  if (cards) {
    if (rows.length === 0) {
      cards.innerHTML = `<p class="muted" style="text-align:center;padding:24px 0">No license keys match.</p>`;
    } else {
      cards.innerHTML = rows
        .map((l) => {
          const deviceBadge = l.boundDeviceId
            ? `${badge("bound", "Bound")}<div class="mono" style="margin-top:4px;font-size:11px">${esc(l.boundDeviceId)}</div>`
            : badge("unbound", "Unbound");
          return `<div class="m-card">
            <div class="m-card-row">
              <span class="m-card-label">Key</span>
              <span class="m-card-key">${esc(l.licenseKey)}</span>
            </div>
            <div class="m-card-row">
              <span class="m-card-label">Customer</span>
              <span class="m-card-val">${esc(l.customer?.name || "—")}</span>
            </div>
            <div class="m-card-row">
              <span class="m-card-label">Status</span>
              <span>${statusBadgeOf(l)}</span>
            </div>
            <div class="m-card-row">
              <span class="m-card-label">Plan</span>
              <span class="chips">${planChips(l)}</span>
            </div>
            <div class="m-card-row" style="flex-direction:column;align-items:flex-start;gap:4px">
              <span class="m-card-label">Device</span>
              <span>${deviceBadge}</span>
            </div>
            <div class="m-card-row">
              <span class="m-card-label">Expires</span>
              <span class="m-card-val muted">${esc((l.expiresAt || "").slice(0, 10))} ${expiryBadge(l)}</span>
            </div>
            <div class="m-card-actions">${licenseActionBtns(l)}</div>
          </div>`;
        })
        .join("");
    }
  }
}

async function refresh() {
  const [stats, customers, licenses] = await Promise.all([
    api("admin/stats"),
    api("admin/customers"),
    api("admin/licenses"),
  ]);
  $("stat-customers").textContent = stats.customers;
  $("stat-licenses").textContent = stats.licenses;
  $("stat-bound").textContent = stats.bound;
  $("stat-revoked").textContent = stats.revoked;
  if ($("stat-expiring")) $("stat-expiring").textContent = stats.expiring30 ?? 0;
  if ($("stat-paused")) $("stat-paused").textContent = stats.paused ?? 0;
  state.customers = customers.customers || [];
  state.licenses = licenses.licenses || [];
  renderCustomers();
  renderLicenses();
  await populateBroadcastTarget();
  await loadBroadcasts(); // feeds both the history view and the home panel
}

// Target picker for broadcasts: Everyone + one row per issued key.
async function populateBroadcastTarget() {
  const bT = $("b-target");
  if (!bT) return;
  const prev = bT.value;
  const opts = [`<option value="">📣 Everyone (all Main devices)</option>`].concat(
    state.licenses.map((l) =>
      `<option value="${esc(l.licenseKey)}">🎯 ${esc(l.licenseKey)} — ${esc(l.customer?.name || "?")}${l.status === "active" ? "" : ` (${esc(l.status)})`}</option>`,
    ),
  );
  bT.innerHTML = opts.join("");
  if (prev && [...bT.options].some((o) => o.value === prev)) bT.value = prev;
}

function renderHomeNotices() {
  const box = $("home-notices");
  if (!box) return;
  if (!state.broadcasts || state.broadcasts.length === 0) {
    box.innerHTML = `<span class="muted">No notifications sent yet.</span>`;
    return;
  }
  box.innerHTML = `<div class="home-notes">` + state.broadcasts.slice(0, 5).map((b) => `
    <div class="home-note">
      <b>${esc(b.title)}</b>
      <span class="muted">${esc((b.created_at || "").slice(0, 16).replace("T", " "))} · ${esc(b.tag || "feature")}${b.target_key ? " · 🎯 " + esc(b.target_key) : " · 📣 everyone"}</span>
    </div>`).join("") + `</div>`;
}

async function loadBroadcasts() {
  try {
    const res = await api("admin/broadcasts");
    state.broadcasts = res.broadcasts || [];
    renderBroadcasts();
    renderHomeNotices();
  } catch (err) {
    toast(err.message || "Failed to load broadcasts");
  }
}

function renderBroadcasts() {
  const tbody = $("b-body");
  if (tbody) {
    if (state.broadcasts.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6" class="muted" style="text-align:center;padding:24px">No broadcast notifications sent yet.</td></tr>`;
    } else {
      tbody.innerHTML = state.broadcasts
        .map((b) => {
          const tagBadge = badge(
            b.tag === "plan" ? "bound" : b.tag === "feature" ? "bound" : "unbound",
            esc(b.tag || "feature"),
          );
          const targetBadge = b.target_key ? badge("target", `🎯 ${esc(b.target_key)}`) : `<span class="muted">📣 all</span>`;
          const date = esc((b.created_at || "").slice(0, 16).replace("T", " "));
          return `<tr>
          <td><span class="mono" style="font-size:12px">${date}</span></td>
          <td>${tagBadge}</td>
          <td>${targetBadge}</td>
          <td><strong>${esc(b.title)}</strong></td>
          <td style="max-width:320px;white-space:normal;font-size:13px">${esc(b.message)}</td>
          <td class="actions">
            <button class="danger" data-delb="${esc(b.id)}">Delete</button>
          </td>
        </tr>`;
        })
        .join("");
    }
  }

  const cards = $("b-cards");
  if (cards) {
    if (state.broadcasts.length === 0) {
      cards.innerHTML = `<p class="muted" style="text-align:center;padding:24px 0">No broadcast notifications sent yet.</p>`;
    } else {
      cards.innerHTML = state.broadcasts
        .map((b) => {
          const tagBadge = badge(
            b.tag === "plan" ? "bound" : b.tag === "feature" ? "bound" : "unbound",
            esc(b.tag || "feature"),
          );
          const date = esc((b.created_at || "").slice(0, 16).replace("T", " "));
          return `<div class="m-card">
          <div class="m-card-row">
            <span class="m-card-label">Type</span>
            <span class="m-card-val">${tagBadge}</span>
          </div>
          <div class="m-card-row">
            <span class="m-card-label">Target</span>
            <span class="m-card-val">${b.target_key ? badge("target", `🎯 ${esc(b.target_key)}`) : `<span class="muted">📣 all</span>`}</span>
          </div>
          <div class="m-card-row">
            <span class="m-card-label">Title</span>
            <span class="m-card-val"><strong>${esc(b.title)}</strong></span>
          </div>
          <div class="m-card-row">
            <span class="m-card-label">Message</span>
            <span class="m-card-val" style="font-size:13px">${esc(b.message)}</span>
          </div>
          <div class="m-card-row">
            <span class="m-card-label">Date</span>
            <span class="mono" style="font-size:11px">${date}</span>
          </div>
          <div class="m-card-actions">
            <button class="danger" data-delb="${esc(b.id)}">Delete</button>
          </div>
        </div>`;
        })
        .join("");
    }
  }
}

const APK_STABLE = `${location.origin}/download`;

async function loadGithubRelease() {
  const tagEl = document.getElementById("apk-tag");
  const statusEl = document.getElementById("apk-status");
  const dateEl = document.getElementById("apk-date");
  const linkEl = document.getElementById("apk-link");
  const dl = document.getElementById("apk-download");
  const chipEl = document.getElementById("planver-tag"); // "Plan & access (…)" in the issue-key dialog
  window.__apkUrl = APK_STABLE;
  if (linkEl) linkEl.textContent = APK_STABLE;
  if (dl) dl.href = APK_STABLE;
  if (!tagEl && !chipEl) return;
  let tag = "latest";
  try {
    const res = await fetch(`${APK_STABLE}?meta=1`, { cache: "no-store" });
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.error || "no apk");
    tag = data.tag || tag;
    if (tagEl) tagEl.textContent = tag;
    if (dateEl) dateEl.textContent = data.publishedAt ? "Published " + String(data.publishedAt).slice(0, 10) : "";
    if (statusEl) {
      statusEl.className = "badge bound";
      statusEl.textContent = "Always latest";
    }
  } catch (e) {
    if (tagEl) tagEl.textContent = "latest";
    if (statusEl) {
      statusEl.className = "badge unbound";
      statusEl.textContent = "Set GITHUB_TOKEN on Pages if the repo is private";
    }
  }
  if (chipEl) chipEl.textContent = tag;
}

async function boot() {
  loadGithubRelease();
  document.getElementById("apk-copy")?.addEventListener("click", () => {
    navigator.clipboard.writeText(window.__apkUrl || `${location.origin}/download`);
  });
  if (!state.token) {
    showApp(false);
    return;
  }
  try {
    const me = await api("admin/me");
    showPlainWarn(me && me.warn === "plaintext_admin_password");
    showApp(true);
    await refresh();
  } catch {
    state.token = "";
    writeToken("");
    showApp(false);
  }
}

$("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  $("login-error").textContent = "";
  try {
    const res = await api("admin/login", {
      method: "POST",
      body: JSON.stringify({ password: $("password").value }),
    });
    state.token = res.token;
    writeToken(res.token);
    showPlainWarn(res.warn === "plaintext_admin_password");
    showApp(true);
    await refresh();
  } catch (err) {
    $("login-error").textContent = err.message || "Login failed";
  }
});

function showPlainWarn(on) {
  const el = $("plain-warn");
  if (el) el.classList.toggle("hidden", !on);
}

$("logout-btn").addEventListener("click", () => {
  state.token = "";
  writeToken("");
  showApp(false);
});

$("theme-btn").addEventListener("click", () => {
  state.theme = state.theme === "dark" ? "light" : "dark";
  localStorage.setItem("of_theme", state.theme);
  document.documentElement.dataset.theme = state.theme;
});

// Desktop/tablet sidebar navigation
document.querySelectorAll(".side a").forEach((a) => {
  a.addEventListener("click", (e) => {
    e.preventDefault();
    setView(a.dataset.view);
  });
});

// Mobile bottom tab bar navigation
document.querySelectorAll(".tab-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    setView(btn.dataset.view);
  });
});

$("c-save").addEventListener("click", async () => {
  const name = $("c-name").value.trim();
  if (!name) return toast("Name is required");
  await api("admin/customers", {
    method: "POST",
    body: JSON.stringify({
      name,
      businessName: $("c-biz").value,
      email: $("c-email").value,
      phone: $("c-phone").value,
    }),
  });
  $("c-name").value = $("c-biz").value = $("c-email").value = $("c-phone").value = "";
  toast("Customer created");
  await refresh();
});

// ── v1.1.59: plan & access editor ────────────────────────────────────────
const MODELS = [
  ["restaurant", "Restaurant"],
  ["retail", "Retail"],
  ["fastfood", "Fast food"],
  ["services", "Services"],
];
const FEATURES = [
  ["multi_terminal", "Extra stations (taker / kitchen / cashier / driver)"],
  ["station_printers", "Per-station printers & auto kitchen print"],
  ["qr_ordering", "QR table ordering & self-order"],
  ["loyalty", "Loyalty points & store credit"],
  ["split_payment", "Split payment (two methods)"],
  ["refunds", "Refund paid orders"],
  ["customer_display", "Customer display screen"],
  ["reservations", "Reservations / appointments"],
  ["recipe_costing", "Recipe costing & food margins"],
  ["wastage", "Wastage log"],
  ["purchases", "Suppliers & purchase orders"],
  ["advanced_reports", "Insights: best sellers, profit, staff"],
  ["eighty_six", "86 board (sellable control)"],
  ["cloud_sync", "Cloud networking — stations keep running when Wi-Fi is down"],
  ["qr_branding", "Branded guest QR page (shop identity editor)"],
  ["third_party", "Third-party channels — Foodpanda, Grab & more (manual)"],
];
const PLAN_PRESETS = {
  // Oct 2026: 2 plans — Starter (12) + Customize (16). Growth is kept as alias for legacy keys.
  starter: FEATURES.filter((f) => !["qr_ordering", "cloud_sync", "qr_branding", "third_party"].includes(f[0])).map((f) => f[0]),
  growth: FEATURES.filter((f) => !["qr_ordering", "cloud_sync", "qr_branding", "third_party"].includes(f[0])).map((f) => f[0]),
  custom: FEATURES.map((f) => f[0]),
  customize: FEATURES.map((f) => f[0]),
  full: FEATURES.map((f) => f[0]),
};
const PLAN_SUMMARY = {
  starter: "Starter — 12 pro features (QR, cloud, branded QR & third-party are Customize add-ons).",
  growth: "Growth (legacy) — same as Starter (12). Use Starter for new keys.",
  custom: "Customize — all 16 features (QR, cloud, branded QR & third-party included).",
  customize: "Customize — all 16 features (QR, cloud, branded QR & third-party included).",
  full: "Full — everything on (same as before plans existed).",
};

let accessEditingId = null; // null = generating a new key

function buildAccessBoxes() {
  $("a-models").innerHTML = MODELS.map(
    ([k, label]) => `<label class="chk"><input type="checkbox" data-model="${k}" checked/><span>${label}</span></label>`,
  ).join("");
  $("a-features").innerHTML = FEATURES.map(
    ([k, label]) => `<label class="chk"><input type="checkbox" data-feature="${k}" checked/><span>${label}</span></label>`,
  ).join("");
  $("l-plan").addEventListener("change", applyPlanPreset);
  $("a-models").addEventListener("change", updateAccessSummary);
  $("a-features").addEventListener("change", updateAccessSummary);
  $("a-reset").addEventListener("click", () => applyPlanPreset());
  updateAccessSummary();
}

function applyPlanPreset() {
  const plan = $("l-plan").value;
  const on = new Set(PLAN_PRESETS[plan] ?? []);
  document.querySelectorAll("#a-features [data-feature]").forEach((cb) => {
    cb.checked = on.has(cb.dataset.feature);
  });
  if (plan !== "custom") {
    document.querySelectorAll("#a-models [data-model]").forEach((cb) => (cb.checked = true));
  }
  updateAccessSummary();
}

function checkedValues(sel, attr) {
  // v1.1.82 fix: the checkboxes carry data-feature / data-model attributes,
  // so the selector must name them explicitly — the old form matched
  // nothing and every save exported an empty feature list.
  return [...document.querySelectorAll(`${sel} [data-${attr}]:checked`)]
      .map((el) => el.dataset[attr]);
}

function updateAccessSummary() {
  const plan = $("l-plan").value;
  const feats = checkedValues("#a-features", "feature").length;
  const models = checkedValues("#a-models", "model").length || MODELS.length;
  const el = $("access-summary");
  el.textContent =
    `${PLAN_SUMMARY[plan] || ""} Models: ${models}/${MODELS.length} · Features: ${feats}/${FEATURES.length}`;
  if (plan !== "starter" && feats === 0) {
    // The editor bug exported exactly this shape — never ship it silently:
    // a save with zero features on a paid plan now falls back to the
    // plan preset (see accessBody) instead of locking a shop out of extras.
    el.textContent += " — ⚠ zero features ticked: save will use the plan preset (tick boxes for a Custom set)";
    el.style.color = "#c62828";
  } else {
    el.style.color = "";
  }
}

function accessBody() {
  const plan = $("l-plan").value;
  const models = checkedValues("#a-models", "model");
  let feats = checkedValues("#a-features", "feature");
  if (feats.length === 0 && plan !== "starter") {
    // Zero ticked on a paid plan is the bug's signature, never a shop's
    // intent — heal to the plan preset (Starter legitimately saves []).
    feats = [...(PLAN_PRESETS[plan] ?? PLAN_PRESETS.custom)];
    // Reflect the heal in the UI so the owner sees what will be saved.
    document.querySelectorAll("#a-features [data-feature]").forEach((cb) => {
      cb.checked = feats.includes(cb.dataset.feature);
    });
  }
  if (plan === "full") feats = FEATURES.map((f) => f[0]); // Full ships all 15
  return {
    plan,
    allowedModels: models.length ? models : MODELS.map((m) => m[0]),
    allowedFeatures: feats,
  };
}

function setAccessEditing(licenseId, license) {
  accessEditingId = licenseId;
  $("l-plan").value = license?.plan && PLAN_SUMMARY[license.plan] ? license.plan : "custom";
  const models = new Set(license?.allowedModels ?? MODELS.map((m) => m[0]));
  const feats = new Set(license?.allowedFeatures ?? FEATURES.map((f) => f[0]));
  document.querySelectorAll("#a-models [data-model]").forEach((cb) => (cb.checked = models.has(cb.dataset.model)));
  document.querySelectorAll("#a-features [data-feature]").forEach((cb) => (cb.checked = feats.has(cb.dataset.feature)));
  $("access-mode").textContent = `Editing ${license?.licenseKey ?? licenseId}`;
  $("access-mode").className = "badge bound";
  $("l-save").classList.add("hidden");
  $("l-hint").classList.add("hidden");
  $("a-save").classList.remove("hidden");
  $("a-cancel").classList.remove("hidden");
  updateAccessSummary();
  setView("licenses");
  $("access-box").scrollIntoView({ behavior: "smooth", block: "start" });
}

function setAccessCreating() {
  accessEditingId = null;
  $("access-mode").textContent = "New key";
  $("access-mode").className = "badge unbound";
  $("l-save").classList.remove("hidden");
  $("l-hint").classList.remove("hidden");
  $("a-save").classList.add("hidden");
  $("a-cancel").classList.add("hidden");
}

$("l-save").addEventListener("click", async () => {
  const customerId = $("l-customer").value;
  if (!customerId) return toast("Create a customer first");
  const res = await api("admin/licenses", {
    method: "POST",
    body: JSON.stringify({ customerId, days: Number($("l-days").value || 365), ...accessBody() }),
  });
  toast(`Key ${res.license.licenseKey}`);
  await refresh();
  setView("licenses");
});

$("a-save").addEventListener("click", async () => {
  if (!accessEditingId) return;
  await api(`admin/licenses/${accessEditingId}/access`, {
    method: "POST",
    body: JSON.stringify(accessBody()),
  });
  toast("Access saved — devices pick it up on the next license check");
  setAccessCreating();
  await refresh();
});

$("a-cancel").addEventListener("click", () => setAccessCreating());

const bPreset = $("b-preset");
if (bPreset) {
  bPreset.addEventListener("change", () => {
    const key = bPreset.value;
    if (!key || !BROADCAST_TEMPLATES[key]) return;
    const tpl = BROADCAST_TEMPLATES[key];
    $("b-title").value = tpl.title;
    $("b-message").value = tpl.message;
    $("b-tag").value = tpl.tag;
    $("b-url").value = tpl.url || "";
  });
}

const bSend = $("b-send");
if (bSend) {
  bSend.addEventListener("click", async () => {
    const title = ($("b-title").value || "").trim();
    const message = ($("b-message").value || "").trim();
    const tag = ($("b-tag").value || "feature").trim();
    const url = ($("b-url").value || "").trim();
    const targetKey = (($("b-target") && $("b-target").value) || "").trim();
    if (!title || !message) return toast("Enter both title and message");
    const activeN = state.licenses.filter((l) => l.status === "active").length;
    if (!targetKey && !confirm(`Push to ALL Main devices (${activeN} active keys)? Pick a key in Audience for a targeted notice.`)) {
      return;
    }
    try {
      bSend.disabled = true;
      bSend.textContent = "Pushing…";
      await api("admin/broadcasts", {
        method: "POST",
        body: JSON.stringify({ title, message, tag, url, ...(targetKey ? { targetKey } : {}) }),
      });
      toast(targetKey ? `🎯 Notice sent to ${targetKey}` : "🚀 Broadcast pushed to all Main devices!");
      $("b-title").value = "";
      $("b-message").value = "";
      $("b-preset").value = "";
      $("b-url").value = "";
      if ($("b-target")) $("b-target").value = "";
      const bc = $("b-count");
      if (bc) bc.textContent = "0/2000";
      await loadBroadcasts();
    } catch (err) {
      toast(err.message || "Failed to push broadcast");
    } finally {
      bSend.disabled = false;
      bSend.textContent = "🚀 Push Notification";
    }
  });
}

buildAccessBoxes();
setAccessCreating();

document.body.addEventListener("click", async (e) => {
  const t = e.target;
  if (!(t instanceof HTMLElement)) return;
  try {
    if (t.dataset.delb) {
      if (!confirm("Delete this broadcast notification?")) return;
      await api(`admin/broadcasts/${t.dataset.delb}`, { method: "DELETE" });
      toast("Broadcast deleted");
      await loadBroadcasts();
      return;
    } else if (t.dataset.delc) {
      if (!confirm("Delete this customer and all related keys?")) return;
      await api(`admin/customers/${t.dataset.delc}`, { method: "DELETE" });
      toast("Customer deleted");
    } else if (t.dataset.dell) {
      if (!confirm("Delete this license key? Main devices using it will lock.")) return;
      await api(`admin/licenses/${t.dataset.dell}`, { method: "DELETE" });
      toast("Key deleted");
    } else if (t.dataset.reset) {
      await api(`admin/licenses/${t.dataset.reset}/reset-device`, { method: "POST" });
      toast("Device binding cleared");
    } else if (t.dataset.extend) {
      const d = prompt("Extend key by how many days? (1–730)", "30");
      if (d === null) return;
      const days = Math.min(730, Math.max(1, Math.round(Number(d) || 30)));
      await api(`admin/licenses/${t.dataset.extend}/extend`, { method: "POST", body: JSON.stringify({ days }) });
      toast(`Extended +${days} days`);
    } else if (t.dataset.pause) {
      if (!confirm("Pause this key? Its Main device locks on the next license check.")) return;
      await api(`admin/licenses/${t.dataset.pause}/pause`, { method: "POST" });
      toast("Key paused");
    } else if (t.dataset.resume) {
      await api(`admin/licenses/${t.dataset.resume}/resume`, { method: "POST" });
      toast("Key resumed");
    } else if (t.dataset.notice) {
      setView("broadcasts");
      const sel = $("b-target");
      if (sel) sel.value = t.dataset.notice;
      const ti = $("b-title");
      if (ti) ti.focus();
      return;
    } else if (t.dataset.viewkeys) {
      const c = state.customers.find((x) => x.id === t.dataset.viewkeys);
      const ls = $("l-search");
      if (ls) { ls.value = c ? c.name : ""; state.licF.q = c ? c.name : ""; }
      setView("licenses");
      return;
    } else if (t.dataset.goto) {
      setView(t.dataset.goto);
      return;
    } else if (t.dataset.revoke) {
      await api(`admin/licenses/${t.dataset.revoke}/revoke`, { method: "POST" });
      toast("Key revoked");
    } else if (t.dataset.copy) {
      await navigator.clipboard.writeText(t.dataset.copy);
      toast("Copied");
      return;
    } else if (t.dataset.access) {
      const lic = state.licenses.find((x) => x.id === t.dataset.access) || null;
      setAccessEditing(t.dataset.access, lic);
      return;
    } else if (t.dataset.issue) {
      $("l-customer").value = t.dataset.issue;
      setAccessCreating();
      setView("licenses");
      return;
    } else {
      return;
    }
    await refresh();
  } catch (err) {
    toast(err.message || "Request failed");
  }
});

// ── v1.1.95 list controls: search / filter / sort ──────────────────────────
const lSearch = $("l-search");
if (lSearch) lSearch.addEventListener("input", () => { state.licF.q = lSearch.value; renderLicenses(); });
const fStatus = $("l-fstatus");
if (fStatus) fStatus.addEventListener("change", () => { state.licF.status = fStatus.value; renderLicenses(); });
const fPlan = $("l-fplan");
if (fPlan) fPlan.addEventListener("change", () => { state.licF.plan = fPlan.value; renderLicenses(); });
const fSort = $("l-sort");
if (fSort) fSort.addEventListener("change", () => { state.licF.sort = fSort.value; renderLicenses(); });
const cSearch = $("c-search");
if (cSearch) cSearch.addEventListener("input", () => { state.custQ = cSearch.value; renderCustomers(); });
const bMsg = $("b-message");
if (bMsg) bMsg.addEventListener("input", () => {
  const bc = $("b-count");
  if (bc) bc.textContent = `${bMsg.value.length}/2000`;
});

/* keep the "Latest Android APK" + "Plan & access (…)" tags fresh in long admin sessions */
setInterval(() => { if (!document.hidden) loadGithubRelease(); }, 300000);
document.addEventListener("visibilitychange", () => { if (!document.hidden) loadGithubRelease(); });

boot();
