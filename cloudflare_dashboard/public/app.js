const state = {
  token: localStorage.getItem("of_admin_token") || "",
  customers: [],
  licenses: [],
  theme: localStorage.getItem("of_theme") || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"),
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
  ["home", "customers", "licenses"].forEach((v) => {
    $(`view-${v}`).classList.toggle("hidden", v !== name);
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
    name === "home" ? "Overview" : name === "customers" ? "Customers" : "License keys";
}

function badge(kind, label) {
  return `<span class="badge ${kind}">${label}</span>`;
}

function esc(v) {
  return String(v ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function renderCustomers() {
  // Desktop table
  $("c-body").innerHTML = state.customers
    .map(
      (c) => `<tr>
        <td><strong>${esc(c.name)}</strong></td>
        <td>${esc(c.business_name || "")}</td>
        <td>${esc(c.email || "")}<br/>${esc(c.phone || "")}</td>
        <td class="muted">${esc((c.created_at || "").slice(0, 10))}</td>
        <td class="actions">
          <button class="secondary" data-issue="${c.id}">Issue key</button>
          <button class="danger" data-delc="${c.id}">Delete</button>
        </td>
      </tr>`,
    )
    .join("");

  // Mobile card list
  const cards = $("c-cards");
  if (cards) {
    if (state.customers.length === 0) {
      cards.innerHTML = `<p class="muted" style="text-align:center;padding:24px 0">No customers yet.</p>`;
    } else {
      cards.innerHTML = state.customers
        .map(
          (c) => `<div class="m-card">
            <div class="m-card-row">
              <span class="m-card-label">Name</span>
              <span class="m-card-val"><strong>${esc(c.name)}</strong></span>
            </div>
            ${c.business_name ? `<div class="m-card-row"><span class="m-card-label">Business</span><span class="m-card-val">${esc(c.business_name)}</span></div>` : ""}
            ${c.email ? `<div class="m-card-row"><span class="m-card-label">Email</span><span class="m-card-val">${esc(c.email)}</span></div>` : ""}
            ${c.phone ? `<div class="m-card-row"><span class="m-card-label">Phone</span><span class="m-card-val">${esc(c.phone)}</span></div>` : ""}
            <div class="m-card-row"><span class="m-card-label">Created</span><span class="m-card-val muted">${esc((c.created_at || "").slice(0, 10))}</span></div>
            <div class="m-card-actions">
              <button class="secondary" data-issue="${c.id}">Issue key</button>
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
  // Desktop table
  $("l-body").innerHTML = state.licenses
    .map((l) => {
      const bind = l.boundDeviceId
        ? `${badge("bound", "Bound")}<div class="mono">${esc(l.boundDeviceId)}</div>`
        : badge("unbound", "Unbound");
      const status =
        l.status === "revoked" ? badge("revoked", "Revoked") : badge("bound", "Active");
      return `<tr>
        <td class="mono">${esc(l.licenseKey)}</td>
        <td>${esc(l.customer?.name || "")}</td>
        <td>${status}</td>
        <td>${bind}</td>
        <td>${esc((l.expiresAt || "").slice(0, 10))}</td>
        <td class="actions">
          <button class="secondary" data-copy="${esc(l.licenseKey)}">Copy</button>
          <button class="secondary" data-reset="${l.id}">Reset device</button>
          <button class="secondary" data-extend="${l.id}">+30 days</button>
          <button class="secondary" data-revoke="${l.id}">Revoke</button>
          <button class="danger" data-dell="${l.id}">Delete</button>
        </td>
      </tr>`;
    })
    .join("");

  // Mobile card list
  const cards = $("l-cards");
  if (cards) {
    if (state.licenses.length === 0) {
      cards.innerHTML = `<p class="muted" style="text-align:center;padding:24px 0">No license keys yet.</p>`;
    } else {
      cards.innerHTML = state.licenses
        .map((l) => {
          const statusBadge =
            l.status === "revoked" ? badge("revoked", "Revoked") : badge("bound", "Active");
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
              <span>${statusBadge}</span>
            </div>
            <div class="m-card-row" style="flex-direction:column;align-items:flex-start;gap:4px">
              <span class="m-card-label">Device</span>
              <span>${deviceBadge}</span>
            </div>
            <div class="m-card-row">
              <span class="m-card-label">Expires</span>
              <span class="m-card-val muted">${esc((l.expiresAt || "").slice(0, 10))}</span>
            </div>
            <div class="m-card-actions">
              <button class="secondary" data-copy="${esc(l.licenseKey)}">Copy</button>
              <button class="secondary" data-reset="${l.id}">Reset device</button>
              <button class="secondary" data-extend="${l.id}">+30 days</button>
              <button class="secondary" data-revoke="${l.id}">Revoke</button>
              <button class="danger" data-dell="${l.id}">Delete</button>
            </div>
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
  state.customers = customers.customers || [];
  state.licenses = licenses.licenses || [];
  renderCustomers();
  renderLicenses();
}

const APK_STABLE = `${location.origin}/download`;

async function loadGithubRelease() {
  const tagEl = document.getElementById("apk-tag");
  const statusEl = document.getElementById("apk-status");
  const dateEl = document.getElementById("apk-date");
  const linkEl = document.getElementById("apk-link");
  const dl = document.getElementById("apk-download");
  if (!tagEl) return;
  window.__apkUrl = APK_STABLE;
  if (linkEl) linkEl.textContent = APK_STABLE;
  if (dl) dl.href = APK_STABLE;
  try {
    const res = await fetch(`${APK_STABLE}?meta=1`);
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.error || "no apk");
    tagEl.textContent = data.tag || "latest";
    if (dateEl) dateEl.textContent = data.publishedAt ? "Published " + String(data.publishedAt).slice(0, 10) : "";
    statusEl.className = "badge bound";
    statusEl.textContent = "Always latest";
  } catch (e) {
    tagEl.textContent = "latest";
    statusEl.className = "badge unbound";
    statusEl.textContent = "Set GITHUB_TOKEN on Pages if the repo is private";
  }
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
    await api("admin/me");
    showApp(true);
    await refresh();
  } catch {
    state.token = "";
    localStorage.removeItem("of_admin_token");
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
    localStorage.setItem("of_admin_token", res.token);
    showApp(true);
    await refresh();
  } catch (err) {
    $("login-error").textContent = err.message || "Login failed";
  }
});

$("logout-btn").addEventListener("click", () => {
  state.token = "";
  localStorage.removeItem("of_admin_token");
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

$("l-save").addEventListener("click", async () => {
  const customerId = $("l-customer").value;
  if (!customerId) return toast("Create a customer first");
  const res = await api("admin/licenses", {
    method: "POST",
    body: JSON.stringify({ customerId, days: Number($("l-days").value || 365) }),
  });
  toast(`Key ${res.license.licenseKey}`);
  await refresh();
  setView("licenses");
});

document.body.addEventListener("click", async (e) => {
  const t = e.target;
  if (!(t instanceof HTMLElement)) return;
  try {
    if (t.dataset.delc) {
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
      await api(`admin/licenses/${t.dataset.extend}/extend`, { method: "POST" });
      toast("Extended +30 days");
    } else if (t.dataset.revoke) {
      await api(`admin/licenses/${t.dataset.revoke}/revoke`, { method: "POST" });
      toast("Key revoked");
    } else if (t.dataset.copy) {
      await navigator.clipboard.writeText(t.dataset.copy);
      toast("Copied");
      return;
    } else if (t.dataset.issue) {
      $("l-customer").value = t.dataset.issue;
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

boot();
