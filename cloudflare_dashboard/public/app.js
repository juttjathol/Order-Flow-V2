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
}

function setView(name) {
  ["home", "customers", "licenses"].forEach((v) => {
    $(`view-${v}`).classList.toggle("hidden", v !== name);
  });
  document.querySelectorAll(".side a").forEach((a) => {
    a.classList.toggle("active", a.dataset.view === name);
  });
  $("view-title").textContent =
    name === "home" ? "Overview" : name === "customers" ? "Customers" : "License keys";
}

function badge(kind, label) {
  return `<span class="badge ${kind}">${label}</span>`;
}

function renderCustomers() {
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
  $("l-customer").innerHTML = state.customers
    .map((c) => `<option value="${c.id}">${esc(c.name)} — ${esc(c.business_name || "shop")}</option>`)
    .join("");
}

function renderLicenses() {
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
}

function esc(v) {
  return String(v ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
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

async function boot() {
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

document.querySelectorAll(".side a").forEach((a) => {
  a.addEventListener("click", (e) => {
    e.preventDefault();
    setView(a.dataset.view);
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
