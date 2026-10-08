/* ============================================================
   ORDER FLOW POS — app.js
   Boot, license, connect, setup, shell, home, floor (all four
   business models), menu, stock, role screens, relay sync,
   notifications. Mirrors router.dart / main_shell.dart /
   home_screen.dart / floor_screen.dart / menu_screen.dart /
   stock_screen.dart + the station role screens.
   ============================================================ */
(function () {
'use strict';
const C = OFCore, L = OFLang;
const $ = id => document.getElementById(id);
const ce = (tag, cls, html) => { const el = document.createElement(tag); if (cls) el.className = cls; if (html != null) el.innerHTML = html; return el; };
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/* ================= SHOP + SETTINGS ================= */
let SHOP = null;
const PROFILE_DEFAULTS = {
  name: 'My Shop', phone: '', address: '', currency: 'RM', model: 'restaurant',
  receiptHead: '', receiptFoot: 'Thank you — please come again', tax: 0, svc: 0,
  copies: 1, paper: '80', showPrices: true, payQr: '', autoPrint: true, kitchenSound: true,
  fireMode: 'auto', drawerNoteShown: false,
  tagline: '', whatsapp: '', hours: '', welcome: '', accent: '#2EA771', brandOn: false,
};
async function loadShop() {
  const saved = (await kvGet('shop', null)) || {};
  const prof = { ...PROFILE_DEFAULTS, ...(saved.profile || {}) };
  SHOP = {
    profile: prof,
    entitlements: saved.entitlements || { allOn: true, plan: 'full', models: [], features: C.FEATURE_KEYS.slice() },
    brand: saved.brand || {},
  };
  return SHOP;
}
async function saveShop() { await kvSet('shop', SHOP); await kvSet('rev', Date.now()); }
const money = (c) => C.fmtCents(c == null ? 0 : c, SHOP.profile.currency || 'RM');
const canF = k => C.allowsFeature(SHOP.entitlements, k);

async function products() { const ps = await idbGetAll('products', []); return ps.map(p => ({ ...p, priceCents: p.priceCents != null ? p.priceCents : C.cents(p.price) })); }
async function orders() { const os = await idbGetAll('orders', []); return os.map(o => normOrder(o)); }
function normOrder(o) { // back-compat: legacy items → lines with cents
  if (o.lines && o.lines.length) return o;
  if (o.items && o.items.length) o.lines = o.items.map(i => ({ id: i.id || C.uuid(), productId: i.productId || i.id || '', name: i.name, qty: i.qty || 1, priceCents: C.cents(i.price != null ? i.price : (i.total || 0)), mods: i.mods || [], notes: i.notes || '' }));
  else if (!o.lines) o.lines = [];
  if (o.table && !o.tableId) { o.tableId = o.table; o.tableName = String(o.table).replace(/^T/, ''); }
  if (!o.type) o.type = o.tableId ? 'dineIn' : 'takeaway';
  return o;
}
async function tablesAll() { return idbGetAll('tables', []); }
async function stockAll() { const ss = await idbGetAll('stock', []); return ss.map(s => ({ ...s, costCents: s.costCents != null ? s.costCents : C.cents(s.cost || 0) })); }

const billOf = (o) => C.billOf(o, SHOP.profile);
function billOfLegacy(o) { return C.billOf(normOrder({ ...o }), SHOP.profile); }
function linePrice(l) { return C.linePriceCents(l); }

/* ================= TOASTS + SOUND + HAPTICS ================= */
function toast(main, sub) {
  const root = $('toast-root'); if (!root) return;
  const key = main + '·' + (sub || '');
  root.querySelectorAll('[data-key]').forEach(el => { if (el.dataset.key === key) el.remove(); });
  while (root.children.length >= 2) root.firstChild.remove();
  const el = ce('div', 'of-toast'); el.dataset.key = key; el.textContent = main;
  if (sub) { const s = ce('small'); s.textContent = sub; el.appendChild(s); }
  root.appendChild(el);
  try { requestAnimationFrame(() => el.classList.add('is-in')); } catch { el.classList.add('is-in'); }
  setTimeout(() => { el.classList.remove('is-in'); setTimeout(() => el.remove(), 260); }, 3800);
}
let _ac = null;
function unlockAudio() {
  try {
    if (!_ac) _ac = new (window.AudioContext || window.webkitAudioContext)();
    if (_ac.state === 'suspended') _ac.resume().catch(() => {});
    const b = _ac.createBuffer(1, 1, 22050), s = _ac.createBufferSource(); s.buffer = b; s.connect(_ac.destination); s.start(0);
  } catch {}
}
['pointerdown', 'touchstart', 'keydown'].forEach(ev => document.addEventListener(ev, unlockAudio, { passive: true }));
function beep(freq, at, gain) {
  if (!_ac) return;
  try {
    const o = _ac.createOscillator(), g = _ac.createGain();
    o.connect(g); g.connect(_ac.destination); o.type = 'triangle'; o.frequency.value = freq;
    const t0 = _ac.currentTime + (at || 0);
    g.gain.setValueAtTime(gain || .3, t0); g.gain.exponentialRampToValueAtTime(.001, t0 + .28);
    o.start(t0); o.stop(t0 + .3);
  } catch {}
}
function chime(kind) {
  unlockAudio();
  if (kind === 'ready') { beep(660); beep(880, .18); }
  else if (kind === 'paid') { beep(523); beep(784, .14); beep(1047, .28); }
  else { beep(880); beep(1320, .16); beep(1760, .32); }
}
const buzz = p => { try { if ('vibrate' in navigator) navigator.vibrate(p); } catch {} };

/* ================= VIEW ROUTER ================= */
const VIEWS = ['view-license', 'view-locked', 'view-connect', 'view-role', 'view-setup', 'view-main', 'view-rolehome', 'view-ticket', 'view-sub', 'view-display'];
let VSTACK = [];
function show(id, remember) {
  const cur = VIEWS.find(v => { const el = $(v); return el && !el.hidden; });
  if (remember && cur && cur !== id) VSTACK.push(cur);
  VIEWS.forEach(v => { const el = $(v); if (el) el.hidden = v !== id; });
  window.scrollTo(0, 0);
}
function goBack() { const prev = VSTACK.pop(); if (prev) show(prev); else show(ROLE === 'main' ? 'view-main' : 'view-rolehome'); }

/* ================= LICENSE (contract 1) ================= */
const API_BASES = ['', 'https://order-flow-v2.pages.dev'];
async function apiJson(path, body) {
  const payload = JSON.stringify(body);
  for (const base of API_BASES) {
    try {
      const r = await fetch(base + path, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: payload });
      const t = await r.text();
      try { return { base, json: JSON.parse(t), status: r.status }; } catch { continue; }
    } catch { continue; }
  }
  return null;
}
async function deviceId() {
  let d = await kvGet('deviceId', null);
  if (!d) { d = 'web-' + C.uuid().slice(0, 8) + '-' + Math.random().toString(36).slice(2, 8); await kvSet('deviceId', d); }
  return d;
}
let ROLE = 'main', STATION_ROLE = '';
async function validateKey(key) {
  const r = await apiJson('/api/v1/license/validate', { licenseKey: key, deviceId: await deviceId() });
  if (!r) return { state: 'offline' };
  const j = r.json || {};
  if (j.valid === true || j.ok === true || j.state === 'valid') {
    return { state: 'valid', payload: j };
  }
  const reason = String(j.reason || j.error || '').toLowerCase();
  if (['not_found', 'revoked', 'expired', 'deleted'].includes(reason)) return { state: 'locked', reason };
  // server busy / html / 5xx / anything else never locks a shop
  return { state: 'server_' + (reason || 'unknown') };
}
async function activateLicense() {
  const input = $('lic-key'); const err = $('lic-err');
  const key = C.normalizeKey(input.value);
  input.value = key; err.textContent = '';
  if (!C.isValidKey(key)) { err.textContent = L.t('key_invalid') + ' — OF-XXXX-XXXX-XXXX-XXXX'; return; }
  const btn = $('lic-btn'); btn.disabled = true;
  const res = await validateKey(key);
  if (res.state === 'valid') {
    await kvSet('license', { key, okAt: Date.now() });
    let ent = C.entitlementsFromLicense(res.payload || {});
    await kvSet('entitlements', ent);
    SHOP.entitlements = ent;
    await saveShop();
    await kvSet('role', 'main');
    await afterRole('main');
  } else if (res.state === 'locked') {
    show('view-locked');
  } else if (res.state === 'offline') {
    const prev = await kvGet('license', null);
    if (prev && prev.okAt) { await afterRole('main'); }
    else err.textContent = 'No internet — needs one online check the first time. Try again.';
  } else {
    const prev = await kvGet('license', null);
    if (prev && prev.okAt) { toast('Server hiccup — carrying on', 'Your shop is already activated on this device.'); await afterRole('main'); }
    else err.textContent = 'License server hiccup — try again in a moment.';
  }
  btn.disabled = false;
}
async function refreshPlan() {
  const lic = await kvGet('license', null);
  if (!lic) return;
  const r = await apiJson('/api/v1/license/validate', { licenseKey: lic.key, deviceId: await deviceId() });
  if (r && r.json && (r.json.valid === true || r.json.ok === true || r.json.state === 'valid')) {
    const ent = C.entitlementsFromLicense(r.json);
    await kvSet('entitlements', ent);
    SHOP.entitlements = ent; await saveShop();
    await kvSet('license', { key: lic.key, okAt: Date.now() });
    syncNow();
    const n = ent.allOn ? C.FEATURE_KEYS.length : (ent.features || []).length;
    toast(L.t('license') + ': ' + (ent.plan || 'full'), 'Plan synced · ' + n + '/16');
    if (typeof OFMoreRefresh === 'function') OFMoreRefresh();
  } else if (r && ['not_found', 'revoked', 'expired', 'deleted'].includes(String(r.json.reason || r.json.error || '').toLowerCase())) {
    show('view-locked');
  } else {
    toast('Could not reach the license server', 'Plan stays as-is — nothing was removed.');
  }
}

/* ================= BOOT ================= */
async function boot() {
  await loadShop();
  // theme
  const theme = await kvGet('theme', 'light');
  applyTheme(theme, false);
  // language
  const lang = await kvGet('lang', 'en');
  OFLang.setLang(lang); applyDir();
  await idbGetAll('products', []); // warm db open (upgrade runs)
  if (window.OFDB && OFDB.isMemory && OFDB.isMemory()) {
    toast('Running without local save', 'Close any other Order Flow tab, then reload — data will persist again.');
  }
  licenseBoot();
}
function applyTheme(pref, announce) {
  const dark = pref === 'dark';
  document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
  $('theme-meta')?.setAttribute('content', dark ? '#0F1512' : '#FAF7F2');
  if (announce) toast(pref === 'dark' ? 'Dark' : 'Light' , 'Theme will stay on this device.');
}
async function licenseBoot() {
  const lic = await kvGet('license', null);
  const role = await kvGet('role', null);
  const room = await kvGet('roomInfo', null);
  if (role === 'station' && room) {
    await afterRole('station', room);
    return;
  }
  if (lic && lic.key && C.isValidKey(lic.key)) {
    ROLE = 'main';
    const setup = await kvGet('setupDone', false);
    if (setup) { enterMain(); startRelayBoot(room); return; }
    show('view-setup'); renderSetup(); return;
  }
  show('view-license');
}
async function afterRole(role, roomInfo) {
  ROLE = role === 'station' ? 'station' : 'main';
  await loadShop();
  if (ROLE === 'main') {
    const setup = await kvGet('setupDone', false);
    if (!setup) { show('view-setup'); renderSetup(); return; }
    enterMain();
  } else {
    roomAfterJoin(roomInfo);
  }
  startRelayBoot(roomInfo);
}
async function roomAfterJoin(roomInfo) {
  startRelayBoot(roomInfo);
  const saved = await kvGet('stationRole', null);
  if (saved) { STATION_ROLE = saved; roleHome(saved); }
  else renderRoleScreen();
}

/* ================= SETUP ================= */
const MODEL_META = {
  restaurant: { ic: '🍽️', label: ['Restaurant', 'Tables, kitchen, reservations'] },
  retail: { ic: '🏪', label: ['Retail', 'Register, SKUs, held sales'] },
  fastfood: { ic: '🍔', label: ['Fast food', 'Counter queue, kitchen board'] },
  services: { ic: '💈', label: ['Services', 'Appointments, staff, tickets'] },
};
let SETUP_MODEL = 'restaurant';
function renderSetup() {
  const host = $('setup-models'); if (!host) return;
  host.innerHTML = '';
  for (const m of C.MODELS) {
    if (!C.allowsModel(SHOP.entitlements, m)) continue;
    const b = ce('button', 'modelcard' + (m === SETUP_MODEL ? ' is-on' : ''));
    b.innerHTML = '<span class="ic">' + MODEL_META[m].ic + '</span><span>' + MODEL_META[m].label[0] + '</span><small style="color:var(--muted);font-weight:600">' + MODEL_META[m].label[1] + '</small>';
    b.onclick = () => { SETUP_MODEL = m; renderSetup(); };
    host.appendChild(b);
  }
}
async function setupDone() {
  const name = $('setup-name').value.trim();
  if (!name) { toast('Give your shop a name', 'It shows on receipts and the guest page.'); return; }
  Object.assign(SHOP.profile, {
    name, model: SETUP_MODEL,
    phone: $('setup-phone').value.trim(), address: $('setup-addr').value.trim(),
    currency: ($('setup-currency').value.trim() || 'RM').slice(0, 6),
  });
  await saveShop();
  await kvSet('setupDone', true);
  await seedIfEmpty();
  await kvSet('role', 'main'); ROLE = 'main';
  enterMain();
  startRelayBoot();
  toast('Welcome to ' + name + ' 🎉', 'Add your tables and menu, then invite stations from More → Cloud room');
}
async function seedIfEmpty() {
  const ps = await idbGetAll('products', []);
  if (!ps.length) {
    const mk = (n, p, cat) => ({ id: C.uuid(), categoryId: cat, cat, name: n, nameUr: '', price: p, priceCents: C.cents(p), available: true, avail: true, inventoryId: null, deductQty: 1, recipe: [] });
    if (SHOP.profile.model === 'restaurant' || SHOP.profile.model === 'fastfood')
      for (const p of await Promise.resolve([mk('Cappuccino', 12, 'Drinks'), mk('Nasi Lemak', 18, 'Mains'), mk('Roti Canai', 8, 'Mains'), mk('Teh Tarik', 6, 'Drinks')])) await idbPut('products', p);
    const ts = await idbGetAll('tables', []);
    if (!ts.length) for (let i = 1; i <= 8; i++) await idbPut('tables', { id: 't-' + i, label: 'T' + i, name: 'T' + i, seats: 2 + (i % 4), state: 'free', since: null });
  }
}

/* ================= RELAY (cloud room — contract 2) ================= */
const CLOUD_BASES = ['', 'https://order-flow-v2.pages.dev'];
let RELAY = null, RELAY_HOT = false;
let PUSH_TIMER = null;
async function OFApiCloudRaw(path, body, bases) {
  const payload = JSON.stringify(body);
  for (const base of (bases || CLOUD_BASES)) {
    try {
      const r = await fetch(base + path, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: payload });
      const j = await r.json().catch(() => null);
      if (j) return { json: j, base };
    } catch {}
  }
  return null;
}
window.OFApiCloud = async (path, body) => (await OFApiCloudRaw(path, body)) || null;
async function cloudApi(path, body, info) {
  const payload = { room: info.room, device: info.device, ...body };
  const bases = ['', info.base, ...CLOUD_BASES].filter((b, i, a) => b != null && a.indexOf(b) === i);
  const res = await OFApiCloudRaw(path, payload, bases);
  if (res && res.base !== (info.base || '')) { info.base = res.base; kvSet('roomInfo', info).catch(() => {}); }
  return res ? res.json : null;
}
async function relayKey(secret) {
  const raw = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('orderflow-cloud|v1|' + secret));
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
}
async function encStr(key, plain) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const enc = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(plain));
  return C.b64uEncode(iv) + '.' + C.b64uEncode(enc);
}
async function decStr(key, blob) {
  const dot = String(blob || '').indexOf('.'); if (dot <= 0) return null;
  try {
    const dec = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: C.b64uDecode(blob.slice(0, dot)) }, key, C.b64uDecode(blob.slice(dot + 1)));
    return new TextDecoder().decode(dec);
  } catch { return null; }
}
async function backupObject() {
  const out = {};
  for (const s of ['products', 'tables', 'orders', 'stock', 'customers', 'staff', 'drivers', 'suppliers', 'purchases', 'wastage', 'reservations', 'channelsThird', 'refunds', 'appointments']) out[s] = await idbGetAll(s, []);
  out.kv = { shop: SHOP, entitlements: SHOP.entitlements };
  return out;
}
async function restoreBackup(obj) {
  for (const s of Object.keys(obj)) {
    if (!Array.isArray(obj[s])) continue;
    const db = await window.OFDB.open();
    if (!db.objectStoreNames.contains(s)) continue;
    await idbClear(s);
    for (const row of obj[s]) if (row && row.id) await idbPut(s, row);
  }
  if (obj.kv && obj.kv.shop) { SHOP = { ...SHOP, ...obj.kv.shop, profile: { ...SHOP.profile, ...(obj.kv.shop.profile || {}) } }; await kvSet('shop', SHOP); }
  if (obj.kv && obj.kv.entitlements) { SHOP.entitlements = obj.kv.entitlements; await kvSet('entitlements', SHOP.entitlements); await saveShop(); }
}
async function startRelayBoot(roomInfo) {
  if (RELAY) return;
  let info = roomInfo || await kvGet('roomInfo', null);
  if (!info) return;
  RELAY = { info, key: await relayKey(info.secret), cursor: 0, dead: false, lastPush: 0, lastRev: 0, parts: null };
  if (!await kvGet('roomInfo', null)) await kvSet('roomInfo', info);
  await setStatusLive();
  loop();
  pushStateNow();
  heartbeat();
  setInterval(heartbeat, 45000);
  setInterval(updateChips, 5000);
}
async function setStatusLive() {
  const h = $('hdr-status'); if (h) h.textContent = L.t('room_live');
  const r = $('role-status'); if (r) r.textContent = L.t('room_live');
}
async function sendCmd(c) {
  if (!RELAY) return;
  const blob = await encStr(RELAY.key, JSON.stringify({ t: 'cmd', c }));
  await cloudApi('/api/cloud/send', { msg: blob }, RELAY.info);
}
async function heartbeat() {
  try {
    const role = ROLE === 'main' ? 'main' : (STATION_ROLE || 'station');
    await sendCmd({ type: 'hello', device: await deviceId(), role, at: Date.now() });
  } catch {}
}
function syncNow() { if (RELAY) pushStateNow(); }
async function pushStateNow() {
  if (!RELAY) return;
  try {
    const obj = await backupObject();
    const json = JSON.stringify(obj);
    const parts = Math.max(1, Math.ceil(json.length / 110000));
    for (let i = 0; i < parts; i++) {
      const chunk = json.slice(i * 110000, (i + 1) * 110000);
      const blob = await encStr(RELAY.key, JSON.stringify(parts > 1 ? { t: 'state_part', part: i, parts, s: chunk } : { t: 'state', s: chunk }));
      const j = await cloudApi('/api/cloud/send', { msg: blob }, RELAY.info);
      if (j && j.ok === false) {
        if (j.error === 'no_room' || j.error === 'no_key') { RELAY = null; await kvSet('relayErr', 'Room is gone — open it again from More → Cloud room'); updateChips(); return; }
      }
    }
    RELAY.lastPush = Date.now();
    updateChips();
  } catch {}
}
function loop() {
  if (!RELAY || RELAY.dead) return;
  const slow = document.hidden ? 8000 : 1800;
  setTimeout(async () => {
    try {
      const j = await cloudApi('/api/cloud/pull', { after: RELAY.cursor }, RELAY.info);
      if (j && j.ok !== false && Array.isArray(j.msgs)) {
        if (typeof j.cursor === 'number') RELAY.cursor = j.cursor;
        for (const m of j.msgs) {
          if (!m || m.sender === RELAY.info.device) continue;
          const plain = await decStr(RELAY.key, String(m.msg || ''));
          if (!plain) continue;
          let env; try { env = JSON.parse(plain); } catch { continue; }
          await handleMsg(env);
        }
        RELAY.deadCount = 0;
        updateChips();
      } else if (j && j.ok === false && (j.error === 'no_room' || j.error === 'no_key')) {
        // Two strikes before declaring death: one transient (proxy/replica
        // race right after /open) must not wipe a room the server just made.
        RELAY.deadCount = (RELAY.deadCount || 0) + 1;
        if (RELAY.deadCount >= 2) {
          RELAY.dead = true; await kvSet('relayErr', 'Room is gone — open it again from More → Cloud room'); updateChips();
        }
      }
    } catch {}
    loop();
  }, slow);
}
async function handleMsg(env) {
  if (env.t === 'state' || env.t === 'state_part') {
    if (env.t === 'state') await applyState(env.s);
    else {
      const k = Number(env.parts) || 1, i = Number(env.part) || 0;
      RELAY.parts = RELAY.parts || Array(k).fill('');
      if (i >= 0 && i < k) RELAY.parts[i] = String(env.s || '');
      if (RELAY.parts.every(p => p !== '')) { const j = RELAY.parts.join(''); RELAY.parts = null; await applyState(j); }
    }
    return;
  }
  if (env.t === 'cmd') return onCmd(env.c || {});
}
async function applyState(json) {
  let obj; try { obj = JSON.parse(json); } catch { return; }
  await restoreBackup(obj);
  await renderActiveTab(true);
  if (ROLE !== 'main' && STATION_ROLE) renderRoleHome(STATION_ROLE).catch(() => {});
  renderStationsMini().catch(() => {});
  refreshBoard().catch(() => {});
}
async function onCmd(cmd) {
  if (!cmd) return;
  if (cmd.type === 'hello' && cmd.device) {
    const seen = (await kvGet('stationsSeen', {})) || {};
    seen[String(cmd.device)] = { role: cmd.role || 'station', at: Number(cmd.at) || Date.now() };
    const now = Date.now();
    for (const k of Object.keys(seen)) if (now - (seen[k]?.at || 0) > 12 * 60 * 1000) delete seen[k];
    await kvSet('stationsSeen', seen);
    await renderStationsPanel();
    return;
  }
  if (cmd.type === 'menu_request') { await pushStateNow(); return; }
  if (cmd.type === 'order' && Array.isArray(cmd.lines)) { // guest QR order (transit only — not a cloud backup)
    const info = normTypeForModel();
    const o = C.newOrder({}, { type: info, tableId: cmd.tableId || null, tableName: cmd.tableName || '', channel: 'qr' });
    for (const l of cmd.lines) o.lines.push({ id: C.uuid(), productId: l.productId || '', name: l.name, qty: l.qty || 1, priceCents: l.priceCents | 0, mods: [], notes: l.notes || '' });
    o.status = 'sent'; o.sentAt = Date.now(); o.createdBy = 'guest@qr';
    // flood caps: per-table 24/h, shop 900/h
    const cap = await qrCapCheck(o.tableId || 'none');
    if (!cap.ok) { await sendCmd({ type: 'order_rejected', tableId: o.tableId, reason: 'busy' }); return; }
    await idbPut('orders', o); await kvSet('rev', Date.now());
    if ((SHOP.profile.fireMode || 'auto') === 'auto' && SHOP.profile.autoPrint && canF('station_printers')) {
      try { ofPrintKitchen(o); } catch {}
    }
    await refreshBoard(); await renderActiveTab(true);
    return;
  }
  if (cmd.type === 'printjob') {
    const isGateway = await kvGet('printGateway', false);
    if (isGateway && cmd.order) { try { printReceipt(cmd.order, {}); } catch {} }
    return;
  }
  if (cmd.orders) { for (const o of cmd.orders) await idbPut('orders', normOrder(o)); await kvSet('rev', Date.now()); await refreshBoard(); await renderActiveTab(true); }
}
async function qrCapCheck(tableId) {
  const win = Date.now() - 3600 * 1000;
  const all = await orders();
  const guest = all.filter(o => o.channel === 'qr' && (o.createdAt || 0) > win);
  if (guest.length >= 900) return { ok: false };
  if (guest.filter(o => o.tableId === tableId).length >= 24) return { ok: false };
  return { ok: true };
}
function normTypeForModel() { return SHOP.profile.model === 'retail' ? 'retail' : SHOP.profile.model === 'services' ? 'service' : SHOP.profile.model === 'fastfood' ? 'takeaway' : 'dineIn'; }

/* ================= STATUS CHIPS ================= */
function updateChips() {
  const dead = RELAY && RELAY.dead;
  if (dead) { // a ghost room from an old build: clear it, show idle, no scary banner
    RELAY = null;
    kvSet('roomInfo', null).catch(() => {});
    kvSet('relayErr', null).catch(() => {});
    const t = window.__toastFn; t && t('Room closed', 'Reopen it any time: More → Cloud room');
  }
  const txt = RELAY ? L.t('room_live') : 'Room idle';
  for (const el of document.querySelectorAll('#hdr-status, #role-status')) {
    el.textContent = txt;
    el.className = 'chip ' + (RELAY ? 'chip--live' : '');
    el.style.cursor = 'pointer';
    el.onclick = () => { window.OFAct['more.goto.cloud'] && window.OFAct['more.goto.cloud'](); };
  }
}
window.OFStartRelay = startRelayBoot;
window.OFUpdateChips = updateChips;

/* ================= NOTIFICATION ENGINE ================= */
const memo = { map: new Map(), seeded: false };
async function refreshBoard() {
  const os = await orders();
  for (const o of os) {
    const prev = memo.map.get(o.id);
    const where = o.tableName ? 'Table ' + o.tableName : (o.type === 'delivery' ? 'Delivery' : o.type === 'takeaway' ? 'Takeaway' : 'Ticket');
    if (prev === undefined && (o.status === 'open' || o.status === 'sent')) {
      if (memo.seeded) { if (SHOP.profile.kitchenSound) chime('ticket'); buzz([120, 60, 160]); toast('New ticket — ' + where, (o.channel === 'qr' ? 'Guest ordered by QR · ' : '') + (o.lines || []).length + ' item(s)'); }
    }
    if (prev !== undefined && prev !== 'ready' && o.status === 'ready') { if (SHOP.profile.kitchenSound) chime('ready'); buzz([80, 40, 120]); toast(where + ' — ready ✓', 'Please serve the guest'); }
    if (prev !== undefined && !['paid', 'refunded', 'cancelled'].includes(prev) && o.status === 'paid') { if (SHOP.profile.kitchenSound) chime('paid'); toast(where + ' — paid ✓', 'Sale recorded'); }
    memo.map.set(o.id, o.status);
  }
  if (memo.map.size > 400) memo.map.clear();
  memo.seeded = true;
  updateTakerBadge(os);
}
function takerReadyOrders(os) { return (os || []).filter(o => o.status === 'ready'); }
function updateTakerBadge(os) { /* ready strip handles visibility; kitchen uses column counts */ }

/* ================= MAIN SHELL ================= */
const ICON = {
  home: '<svg viewBox="0 0 24 24"><path d="M3 10.5L12 3l9 7.5"/><path d="M5 10v10h5v-6h4v6h5V10"/></svg>',
  tables: '<svg viewBox="0 0 24 24"><path d="M4 17h16M6 17V7h12v10M9 7V5h6v2"/></svg>',
  register: '<svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="6" rx="2"/><path d="M4 12v6a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6M7 16h6"/></svg>',
  queue: '<svg viewBox="0 0 24 24"><path d="M6 6l4 6-4 6M14 6l4 6-4 6"/></svg>',
  appointments: '<svg viewBox="0 0 24 24"><rect x="4" y="5" width="16" height="16" rx="3"/><path d="M8 3v4M16 3v4M4 10h16"/></svg>',
  menu: '<svg viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h16"/></svg>',
  services: '<svg viewBox="0 0 24 24"><path d="M12 3l2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5z"/></svg>',
  stock: '<svg viewBox="0 0 24 24"><path d="M21 8l-9-5-9 5v8l9 5 9-5z"/><path d="M3 8l9 5 9-5M12 13v8"/></svg>',
  more: '<svg viewBox="0 0 24 24"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg>',
};
function dests() {
  const m = SHOP.profile.model;
  const second = { restaurant: ['tables', L.t('tables')], retail: ['register', L.t('register')], fastfood: ['queue', L.t('queue')], services: ['appointments', L.t('appointments')] }[m];
  const third = m === 'services' ? ['services', L.t('services')] : ['menu', L.t('menu')];
  return [
    { id: 'home', label: L.t('home'), ic: ICON.home },
    { id: 'floor', label: second[1], ic: ICON[second[0]] },
    { id: 'menu', label: third[1], ic: ICON[third[0]] },
    { id: 'stock', label: L.t('stock'), ic: ICON.stock },
    { id: 'more', label: L.t('more'), ic: ICON.more },
  ];
}
let ACTIVE_TAB = 'home';
function buildNav() {
  const ds = dests();
  const rail = $('rail'), bn = $('bnav'); if (!rail || !bn) return;
  rail.innerHTML = ''; bn.innerHTML = '';
  for (const d of ds) {
    const br = ce('button', 'rail__dest' + (d.id === ACTIVE_TAB ? ' is-on' : ''), d.ic + '<span>' + esc(d.label) + '</span>');
    br.onclick = () => setTab(d.id); rail.appendChild(br);
    const bb = ce('button', 'bnav__dest' + (d.id === ACTIVE_TAB ? ' is-on' : ''), d.ic + '<span>' + esc(d.label) + '</span>');
    bb.dataset.tabId = d.id; bb.onclick = () => setTab(d.id); bn.appendChild(bb);
  }
}
function setTab(tab) {
  ACTIVE_TAB = tab;
  for (const t of ['home', 'floor', 'menu', 'stock', 'more']) $('tab-' + t).hidden = t !== tab;
  document.querySelectorAll('#rail .rail__dest, #bnav .bnav__dest').forEach((el, i) => {
    const on = (el.dataset.tabId || '') === tab || el.classList.contains('is-on') && !el.dataset.tabId;
  });
  buildNavIfChanged(tab);
  renderActiveTab();
}
function buildNavIfChanged(tab) {
  document.querySelectorAll('#bnav .bnav__dest').forEach(el => el.classList.toggle('is-on', el.dataset.tabId === tab));
  document.querySelectorAll('#rail .rail__dest').forEach((el, i) => {
    const ds = dests(); el.classList.toggle('is-on', ds[i] && ds[i].id === tab);
  });
}
async function renderActiveTab(silent) {
  // never steal focus mid-typing (30s auto-refresh tick)
  const ae = document.activeElement;
  if (silent && ae && (ae.tagName === 'INPUT' || ae.tagName === 'TEXTAREA' || ae.tagName === 'SELECT') && ae.closest('#main-body,#role-body,#sub-body')) return;
  try {
    const fn = { home: renderHome, floor: renderFloor, menu: renderMenu, stock: renderStock, more: OFMoreRender }[ACTIVE_TAB];
    if (fn) await fn();
  } catch (e) { console.error('render', e); }
}
function enterMain() {
  ROLE = 'main';
  $('hdr-shop').textContent = SHOP.profile.name;
  $('hdr-role').textContent = L.t('role_main');
  show('view-main');
  buildNav(); setTab('home');
  document.documentElement.dir = langDir();
  applyText();
  refreshBoard().catch(() => {});
  setInterval(async () => { await renderActiveTab(true); await refreshBoard(); renderStationsMini().catch(() => {}); }, 30000);
  setInterval(tickClocks, 30000);
}
function applyText() {
  document.querySelectorAll('[data-t]').forEach(el => el.textContent = L.t(el.dataset.t));
  document.querySelectorAll('[data-ph]').forEach(el => el.placeholder = L.t(el.dataset.ph));
}
function langDir() { return OFLang.getLang() === 'ur' ? 'rtl' : 'ltr'; }
function applyDir() { document.documentElement.lang = OFLang.getLang(); document.documentElement.dir = langDir(); }

/* ================= HOME ================= */
function greeting() { const h = new Date().getHours(); return h < 12 ? L.t('greeting_morning') : h < 17 ? L.t('greeting_afternoon') : L.t('greeting_evening'); }
async function renderHome() {
  const host = $('tab-home'); if (!host || host.hidden) { if (host && ACTIVE_TAB === 'home') return; }
  const os = await orders(), ps = await products(), ss = await stockAll();
  const rep = C.reportXZ(os, SHOP.profile);
  const start = C.dayStart();
  const y = C.reportXZ(os, SHOP.profile, start - 3600000);
  const delta = rep.taken - y.taken;
  const openN = os.filter(o => !['paid', 'cancelled', 'refunded'].includes(o.status)).length;
  const lowN = ss.filter(s => s.qty <= (s.lowStockAt ?? s.lowAt ?? 5)).length;
  const apptN = SHOP.profile.model === 'services' ? (await idbGetAll('appointments', [])).filter(a => a.status !== 'done' && (a.at || 0) >= start && (a.at || 0) < start + 86400000).length : 0;
  const ready = takerReadyOrders(os);
  const busyClocks = os.filter(o => o.tableId && !['paid', 'cancelled', 'refunded'].includes(o.status)).length;
  const spark = [...Array(7)].map((_, i) => { const d = start - (6 - i) * 86400000; return C.reportXZ(os, SHOP.profile, d).taken; });
  const mx = Math.max(1, ...spark);
  const now = new Date();
  host.innerHTML = '';
  const top = ce('h2', null, '<span class="muted" style="font-weight:600">' + greeting() + ', </span>' + esc(SHOP.profile.name));
  top.style.cssText = 'font-weight:900;letter-spacing:-.5px;font-size:22px';
  host.appendChild(top);
  host.appendChild(ce('p', 'muted small', now.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'short' })));
  // sales hero (dark in both themes)
  const hero = ce('div', 'card card--forest hero');
  hero.innerHTML = '<div class="row" style="justify-content:space-between"><span class="small" style="font-weight:700;opacity:.75">' + L.t('reports_today') + '</span><span class="chip">' + openN + ' open · ' + busyClocks + ' on tables</span></div>'
    + '<div class="hero__amt" style="margin-top:8px">' + money(rep.taken) + '</div>'
    + '<span class="chip ' + (delta >= 0 ? '' : 'chip--gold') + '" style="margin-top:10px">' + (delta >= 0 ? '↗ +' : '↘ ') + money(Math.abs(delta)).trim() + ' vs yesterday</span>'
    + '<div class="hero__grid"><div><div class="small" style="opacity:.75">' + rep.unpaidCount + ' unpaid · ' + money(rep.waiting) + '</div><div class="prog" style="margin-top:8px;width:180px;max-width:46vw"><b style="width:' + Math.min(100, Math.round(rep.taken / mx * 100)) + '%"></b></div></div><svg class="hero__spark" viewBox="0 0 110 44">' + spark.map((v, i) => (i ? ' L' : 'M') + (i * (100 / 6) + 5).toFixed(0) + ' ' + (40 - (v / mx * 34)).toFixed(0)).join('') + '" fill="none" stroke="#fff" stroke-width="2.5" stroke-linejoin="round"/></svg></div>';
  host.appendChild(hero);
  // quick tiles (model-aware)
  const tiles = ce('div', 'tiles'); tiles.style.marginTop = '14px';
  const mkT = (label, ic, act) => { const b = ce('button', 'tile', '<span class="tile__ic">' + ic + '</span>' + esc(label)); b.dataset.act = act; tiles.appendChild(b); };
  const m = SHOP.profile.model;
  if (m === 'restaurant') { mkT(L.t('tables'), ICON.tables, 'shell.tab.floor'); mkT(L.t('new_ticket'), ICON.queue, 'ticket.new'); mkT(L.t('kitchen') || 'Kitchen', ICON.queue, 'rolecover.kitchen'); mkT(L.t('menu'), ICON.menu, 'shell.tab.menu'); }
  else if (m === 'retail') { mkT(L.t('register'), ICON.register, 'shell.tab.floor'); mkT(L.t('new_ticket'), ICON.queue, 'ticket.new'); mkT(L.t('menu'), ICON.menu, 'shell.tab.menu'); mkT(L.t('stock'), ICON.stock, 'shell.tab.stock'); }
  else if (m === 'fastfood') { mkT(L.t('queue'), ICON.queue, 'shell.tab.floor'); mkT(L.t('new_ticket'), ICON.queue, 'ticket.new'); mkT(L.t('menu'), ICON.menu, 'shell.tab.menu'); mkT(L.t('stock'), ICON.stock, 'shell.tab.stock'); }
  else { mkT(L.t('appointments'), ICON.appointments, 'shell.tab.floor'); mkT(L.t('services'), ICON.services, 'shell.tab.menu'); mkT(L.t('stock'), ICON.stock, 'shell.tab.stock'); mkT(L.t('more'), ICON.more, 'shell.tab.more'); }
  host.appendChild(tiles);
  // room card — room live + join code + QR (never a fake Wi-Fi IP)
  const roomInfo = RELAY ? RELAY.info : null;
  const room = ce('div', 'card card--pad'); room.style.marginTop = '14px';
  if (roomInfo) {
    room.innerHTML = '<div class="row"><span class="chip chip--live">● ' + L.t('room_live') + '</span><span class="muted small grow" style="font-weight:600">' + L.t('join_code') + ': <b class="mono">' + esc(roomInfo.code) + '</b></span><button class="btn btn--sm" data-act="home.roomqr">QR</button></div><p class="small muted" style="margin-top:8px;font-weight:600">Android and iPhone stations meet in this room — scan the code on any station.</p><div id="stations-mini" style="display:grid;gap:6px;margin-top:10px"></div>';
  } else {
    room.innerHTML = '<div class="row"><span class="chip chip--warn">Room closed</span><span class="muted small grow" style="font-weight:600">Open it so stations can join</span><button class="btn btn--sm btn--primary" data-act="more.goto.cloud">Open room</button></div>';
  }
  host.appendChild(room);
  renderStationsMini();
  // ready strip
  if (ready.length) {
    host.appendChild(ce('div', 'sect__t', L.t('ready_to_serve')));
    for (const o of ready) host.appendChild(readyLine(o));
  }
  // stats
  const stats = ce('div', 'stats'); stats.style.marginTop = '12px';
  const stat = (k, v, d) => { const el = ce('div', 'stat', '<div class="stat__k">' + k + '</div><div class="stat__v">' + v + '</div><div class="stat__d">' + d + '</div>'); stats.appendChild(el); };
  stat('Open orders', String(openN), 'live');
  stat(m === 'services' ? 'Appointments' : 'Items sold', m === 'services' ? String(apptN) : String(rep.top.reduce((a, x) => a + x[1], 0)), L.t('reports_today'));
  stat('Menu items', String(ps.length), 'catalog');
  stat('Low stock', String(lowN), lowN ? 'watch' : 'ok');
  host.appendChild(stats);
  // live board
  const open = os.filter(o => !['paid', 'cancelled', 'refunded'].includes(o.status))
    .sort((a, b) => b.createdAt - a.createdAt).slice(0, 8);
  host.appendChild(ce('div', 'sect__t', 'Live board'));
  if (!open.length) host.appendChild(ce('p', 'muted small', L.t('no_orders')));
  else {
    for (const o of open) host.appendChild(boardRow(o));
  }
}
function readyLine(o) {
  const el = ce('div', 'readyline',
    '<span class="lrow__ic" style="background:rgba(212,158,53,.18)">🔔</span>'
    + '<span class="ttl">' + esc(whereOf(o)) + ' — ' + L.t('ready_to_serve') + '<small class="sub" style="display:block">' + (o.lines || []).length + ' dish(es) waiting</small></span>'
    + '<button type="button" data-act="tk.served" data-id="' + o.id + '">' + L.t('mark_served') + '</button>');
  el.querySelector('button').onclick = (e) => { e.stopPropagation(); OFAct['ticket.served'](el.querySelector('button'), e); };
  return el;
}
function whereOf(o) { return o.tableName ? 'Table ' + o.tableName : (o.type === 'delivery' ? 'Delivery' : o.type === 'takeaway' ? 'Takeaway' : 'Ticket #' + o.ticketNo); }
function boardRow(o) {
  const age = Math.max(0, Math.round((Date.now() - (o.createdAt || Date.now())) / 60000));
  const b = billOf(o);
  const st = { open: ['New', 'tag--blue'], sent: ['In kitchen', 'tag--blue'], preparing: ['Preparing', 'tag--gold'], ready: ['READY ✓', 'tag--mint'], served: ['Served', 'tag--gold'], out: ['Out for delivery', 'tag--blue'] }[o.status] || [o.status, ''];
  const el = ce('div', 'lrow', '<div class="hd grow"><b>' + esc(whereOf(o)) + '</b><small>' + age + ' min · ' + (o.lines || []).length + ' item(s)</small></div><span class="tag ' + st[1] + '">' + st[0] + '</span><span class="lrow__amt">' + money(b.due) + '</span>');
  el.onclick = () => openTicket(o.id);
  return el;
}
async function renderStationsMini() {
  const host = $('stations-mini'); if (!host) return;
  const seen = (await kvGet('stationsSeen', {})) || {};
  const me = await deviceId();
  const rows = [['This device', { role: ROLE === 'main' ? L.t('role_main') : (STATION_ROLE || 'station'), at: Date.now() }], ...Object.entries(seen)];
  host.innerHTML = '';
  for (const [dev, info] of rows) {
    const age = Math.round((Date.now() - (info.at || 0)) / 1000);
    const live = age < 75;
    const el = ce('div', 'row', '<span class="dot" style="background:' + (live ? 'var(--mint)' : 'var(--muted)') + '"></span><span class="small grow" style="font-weight:700">' + esc(dev === me ? 'This device' : dev) + '</span><span class="small muted" style="font-weight:600">' + esc(info.role) + (dev === me ? '' : ' · ' + (live ? 'live' : fmtAgo(age))) + '</span>');
    host.appendChild(el);
  }
}
function fmtAgo(sec) { return sec < 60 ? sec + 's ago' : Math.floor(sec / 60) + 'm ago'; }
async function renderStationsPanel() { renderStationsMini().catch(() => {}); }

/* ================= TICKETS ================= */
async function newTicket(opts) {
  opts = opts || {};
  const o = C.newOrder(SHOP.profile, { type: opts.type || normTypeForModel(), tableId: opts.table?.id || null, tableName: opts.table ? opts.table.name || opts.table.label : '' });
  await idbPut('orders', o); await kvSet('rev', Date.now());
  syncNow(); refreshBoard().catch(() => {});
  openTicket(o.id);
}
function openTicket(id) { if (window.OFOpenTicket) OFOpenTicket(id); }

/* ================= FLOOR ================= */
let FLOOR_FILTER = 'all', FLOOR_Q = '';
async function renderFloor() {
  const host = $('tab-floor'); if (!host) return;
  const m = SHOP.profile.model;
  host.innerHTML = '';
  if (m === 'restaurant') return renderFloorRestaurant(host);
  if (m === 'retail') return renderFloorRetail(host);
  if (m === 'fastfood') return renderFloorQueue(host);
  return renderFloorAppts(host);
}
async function renderFloorRestaurant(host) {
  const ts = await tablesAll(); const os = await orders();
  const openByTable = {};
  for (const o of os) if (!['paid', 'cancelled', 'refunded'].includes(o.status) && o.tableId) (openByTable[o.tableId] = openByTable[o.tableId] || []).push(o);
  const head = ce('div', 'row');
  head.innerHTML = '<h2 class="grow" style="font-weight:900;letter-spacing:-.5px">' + L.t('tables') + '</h2><button class="btn btn--sm btn--primary" data-act="floor.addtable">+ ' + L.t('new_table') + '</button>';
  host.appendChild(head);
  const srch = ce('input'); srch.placeholder = L.t('search'); srch.style.marginTop = '10px'; srch.value = FLOOR_Q;
  srch.addEventListener('input', () => { FLOOR_Q = srch.value; renderFloorRestaurantTiles(); });
  host.appendChild(srch); host._searchField = srch;
  const chips = ce('div', 'filters'); chips.style.marginTop = '10px';
  const counts = { all: 0, free: 0, busy: 0, ready: 0 };
  const stateOf = t => (openByTable[t.id] && openByTable[t.id].length) ? (openByTable[t.id].some(o => o.status === 'ready') ? 'ready' : 'ordered') : 'free';
  for (const t of ts) { counts.all++; counts[stateOf(t) === 'free' ? 'free' : 'busy']++; if (stateOf(t) === 'ready') counts.ready++; }
  for (const f of [['all', 'All'], ['free', 'Free'], ['busy', 'Ordered'], ['ready', 'Ready']])
    chips.appendChild(Object.assign(ce('button', 'fchip' + (FLOOR_FILTER === f[0] ? ' is-on' : '')), { textContent: f[1] + ' · ' + counts[f[0]] }));
  chips.querySelectorAll('.fchip').forEach((b, i) => b.onclick = () => { FLOOR_FILTER = ['all', 'free', 'busy', 'ready'][i]; renderFloorRestaurant(host); });
  host.appendChild(chips);
  const map = ce('div', 'tmap'); map.style.marginTop = '12px'; host.appendChild(map);
  host._tiles = { map, ts, openByTable };
  renderFloorRestaurantTiles();
}
function renderFloorRestaurantTiles() {
  const host = $('tab-floor'); if (!host || !host._tiles) return;
  const { map, ts, openByTable } = host._tiles;
  map.innerHTML = '';
  const q = FLOOR_Q.toLowerCase();
  for (const t of ts) {
    if (q && !(t.label || t.name || '').toLowerCase().includes(q)) continue;
    const os = openByTable[t.id] || [];
    const st = os.length ? (os.some(o => o.status === 'ready') ? 'ready' : 'ordered') : 'free';
    if (FLOOR_FILTER === 'busy' && st === 'free') continue;
    if (FLOOR_FILTER !== 'all' && FLOOR_FILTER !== 'busy' && st !== FLOOR_FILTER) continue;
    const since = os.length ? Math.min(...os.map(o => o.createdAt || Date.now())) : null;
    const amt = os.reduce((a, o) => a + billOf(o).due, 0);
    const el = ce('button', 'tcard' + (st === 'ready' ? ' tcard--ready' : st === 'ordered' ? ' tcard--busy' : ' tcard--free'));
    el.innerHTML = '<div class="row" style="justify-content:space-between"><span class="tcard__name">' + esc(t.label || t.name || 'T') + '</span><span class="small muted" style="font-weight:700">' + (t.seats || 2) + '×🪑</span></div>'
      + (os.length ? '<div class="tcard__meta"><span class="dot ' + (st === 'ready' ? 'dot--ready' : 'dot--busy') + '"></span><span>' + (st === 'ready' ? 'Ready' : 'Ordered') + '</span><b class="js-clock">' + clockTxt(since) + '</b><b>' + money(amt) + '</b></div>' : '<div class="tcard__meta"><span class="dot dot--free"></span><span>Free</span></div>');
    el.onclick = () => tableTap(t, os);
    map.appendChild(el);
  }
  if (!map.children.length) map.appendChild(ce('p', 'muted small', L.t('empty')));
}
function clockTxt(since) { const s = Math.max(0, Math.floor((Date.now() - (since || Date.now())) / 1000)); const m = Math.floor(s / 60), r = s % 60; return m + ':' + String(r).padStart(2, '0'); }
function tickClocks() {
  document.querySelectorAll('.js-clock').forEach(() => {});
  if (ACTIVE_TAB === 'floor' && SHOP && SHOP.profile.model === 'restaurant') renderFloorRestaurantTiles();
  if (ACTIVE_TAB === 'home') noop0();
}
function noop0() {}
async function tableTap(t, os) {
  const allowed = [
    { label: os.length ? 'Open bill' : L.t('new_ticket'), act: async () => { const o = os.length ? os[os.length - 1] : null; if (o) openTicket(o.id); else newTicket({ table: t }); } },
    { label: L.t('new_ticket'), act: () => newTicket({ table: t }) },
  ];
  if (canF('qr_ordering')) allowed.push({ label: L.t('qr_ordering') + ' QR', act: () => showTableQR(t) });
  allowed.push({ label: L.t('cancel'), act: null, kind: 'ghost' });
  pickAction('Table ' + (t.label || t.name), 'Free · ' + (t.seats || 2) + ' seats', allowed);
}
function showTableQR(t) {
  if (!RELAY) { toast('Open the room first', 'More → Cloud room → Open & show QR'); return; }
  OFAct['home.tableqr'](null, t);
}
async function renderFloorRetail(host) {
  const head = ce('div', 'row');
  head.innerHTML = '<h2 class="grow" style="font-weight:900;letter-spacing:-.5px">' + L.t('register') + '</h2><button class="btn btn--sm btn--primary" data-act="ticket.new">+ ' + L.t('new_ticket') + '</button><button class="btn btn--sm" data-act="floor.held">' + L.t('held_sales') + '</button>';
  host.appendChild(head);
  host.appendChild(ce('p', 'muted small', 'Scan or type a SKU, or tap an item to start a sale. Held sales recall here.'));
  const q = ce('input'); q.placeholder = 'Scan or type SKU / name…'; q.style.marginTop = '10px';
  q.addEventListener('keydown', async (e) => {
    if (e.key !== 'Enter') return;
    const v = q.value.trim(); if (!v) return;
    const ps = await products();
    const p = ps.find(x => (x.sku || '').toLowerCase() === v.toLowerCase()) || ps.find(x => (x.name || '').toLowerCase().startsWith(v.toLowerCase()));
    if (p) { const open = (await orders()).find(o => o.type === 'retail' && o.status === 'open' && !o.held); if (open) { C.addLine(open, p); await idbPut('orders', open); openTicket(open.id); } else await newTicketQuickRetail(p); }
    else toast('Not found: ' + v); q.value = '';
  });
  host.appendChild(q);
  const ps = await products();
  const grid = ce('div', 'mgrid'); grid.style.marginTop = '12px';
  for (const p of ps.filter(x => x.available !== false)) grid.appendChild(menuPickCard(p, async () => {
    const open = (await orders()).find(o => o.type === 'retail' && o.status === 'open' && !o.held);
    if (open) { C.addLine(open, p); await idbPut('orders', open); syncNow(); openTicket(open.id); }
    else await newTicketQuickRetail(p);
  }));
  host.appendChild(grid);
}
async function newTicketQuickRetail(p) { const o = C.newOrder(SHOP.profile, { type: 'retail' }); C.addLine(o, p); await idbPut('orders', o); await kvSet('rev', Date.now()); syncNow(); openTicket(o.id); }
async function renderFloorQueue(host) {
  const head = ce('div', 'row');
  head.innerHTML = '<h2 class="grow" style="font-weight:900;letter-spacing:-.5px">' + L.t('queue') + '</h2><button class="btn btn--sm btn--primary" data-act="ticket.new">+ ' + L.t('new_ticket') + '</button>';
  host.appendChild(head);
  const os = await orders();
  const cols = [
    ['New', os.filter(o => ['open', 'sent'].includes(o.status))],
    ['Preparing', os.filter(o => o.status === 'preparing')],
    ['Ready', os.filter(o => o.status === 'ready')],
    ['Done (unpaid)', os.filter(o => o.status === 'served')],
  ];
  const wrap = ce('div', 'grid'); wrap.style.cssText = 'margin-top:12px;grid-template-columns:repeat(auto-fit, minmax(240px,1fr))';
  for (const [name, list] of cols) {
    const col = ce('div', 'card card--pad');
    col.innerHTML = '<div class="row" style="justify-content:space-between"><b>' + name + '</b><span class="tag">' + list.length + '</span></div>';
    col.appendChild(ce('div', 'divider'));
    for (const o of list.sort((a, b) => b.createdAt - a.createdAt)) col.appendChild(boardRow(o));
    if (!list.length) col.appendChild(ce('p', 'muted small', L.t('empty')));
    wrap.appendChild(col);
  }
  host.appendChild(wrap);
}
async function renderFloorAppts(host) {
  const head = ce('div', 'row');
  head.innerHTML = '<h2 class="grow" style="font-weight:900;letter-spacing:-.5px">' + L.t('appointments') + '</h2><button class="btn btn--sm btn--primary" data-act="appt.book">+ ' + L.t('book_appt') + '</button>';
  host.appendChild(head);
  const start = C.dayStart();
  const appts = (await idbGetAll('appointments', [])).filter(a => (a.at || 0) >= start - 43200000).sort((a, b) => a.at - b.at);
  const today = appts.filter(a => (a.at || 0) < start + 86400000);
  const tomorrow = appts.filter(a => (a.at || 0) >= start + 86400000 && (a.at || 0) < start + 2 * 86400000);
  host.appendChild(ce('div', 'sect__t', L.t('todays_appts')));
  if (!today.length) host.appendChild(ce('p', 'muted small', L.t('empty')));
  for (const a of today) host.appendChild(apptRow(a));
  host.appendChild(ce('div', 'sect__t', 'Tomorrow'));
  if (!tomorrow.length) host.appendChild(ce('p', 'muted small', L.t('empty')));
  for (const a of tomorrow) host.appendChild(apptRow(a));
}
function apptRow(a) {
  const late = a.status === 'booked' && (Date.now() - a.at) > 15 * 60000;
  const el = ce('div', 'lrow', '<span class="lrow__ic">🗓️</span><div class="hd grow"><b>' + esc(a.customer) + '</b><small>' + esc(a.service || '') + ' · ' + new Date(a.at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) + (a.staff ? ' · ' + esc(a.staff) : '') + (a.phone ? ' · ' + esc(a.phone) : '') + '</small></div>'
    + (late ? '<span class="tag tag--danger">' + L.t('running_late') + '</span>' : '<span class="tag">' + (a.status || 'booked') + '</span>')
    + (a.status === 'booked' ? '<button class="btn btn--sm btn--mint" data-act="appt.start" data-id="' + a.id + '">' + L.t('start') + '</button>' : (a.status === 'in_service' ? '<button class="btn btn--sm" data-act="appt.finish" data-id="' + a.id + '">' + L.t('finish') + '</button>' : '')));
  el.querySelectorAll('button').forEach(b => b.onclick = (e) => { e.stopPropagation(); OFAct[b.dataset.act](b, e); });
  return el;
}

/* ================= MENU PICK CARD (shared) ================= */
function menuPickCard(p, onAdd) {
  const el = ce('div', 'mcard');
  el.innerHTML = '<div class="mcard__img">' + (p.imageBase64 ? '<img src="' + p.imageBase64 + '" alt=""/>' : '🍽️') + '</div>'
    + '<div class="mcard__body"><span class="mcard__name">' + esc(p.name) + '</span><span class="mcard__price">' + money(p.priceCents) + '</span><button class="mcard__add" type="button">' + L.t('add') + '</button></div>';
  el.querySelector('button').onclick = (e) => { e.stopPropagation(); onAdd && onAdd(); };
  el.onclick = () => onAdd && onAdd();
  return el;
}

/* ================= MENU TAB ================= */
let MENU_CAT = 'all', MENU_Q = '';
async function renderMenu() {
  const host = $('tab-menu'); if (!host) return;
  host.innerHTML = '';
  const m = SHOP.profile.model;
  const head = ce('div', 'row');
  head.innerHTML = '<h2 class="grow" style="font-weight:900;letter-spacing:-.5px">' + (m === 'services' ? L.t('services') : L.t('menu')) + '</h2>'
    + '<button class="btn btn--sm" data-act="menu.scan">' + L.t('menu_scan') + '</button><button class="btn btn--sm btn--primary" data-act="menu.add">+ ' + L.t('add_item') + '</button>';
  host.appendChild(head);
  const srch = ce('input'); srch.placeholder = L.t('search'); srch.style.margin = '10px 0'; srch.value = MENU_Q;
  srch.addEventListener('input', () => { MENU_Q = srch.value; renderMenu(); });
  host.appendChild(srch);
  const ps = await products();
  const cats = [...new Set(ps.map(p => p.categoryId || p.cat || 'Items'))];
  const chips = ce('div', 'filters');
  chips.append(chipOf('all', 'All', cats.length)); for (const c of cats) chips.append(chipOf(c, c, ps.filter(p => (p.categoryId || p.cat) === c).length));
  function chipOf(id, label) { const b = ce('button', 'fchip' + (MENU_CAT === id ? ' is-on' : ''), esc(label)); b.onclick = () => { MENU_CAT = id; renderMenu(); }; return b; }
  host.appendChild(chips);
  const list = ps.filter(p => (MENU_CAT === 'all' || (p.categoryId || p.cat || 'Items') === MENU_CAT) && (!MENU_Q || (p.name || '').toLowerCase().includes(MENU_Q.toLowerCase())));
  for (const p of list) {
    const off = p.available === false || p.avail === false;
    // APK-style row: [icon][name+cat, flexible][price][⋯]. Tapping the row
    // opens the editor; ⋯ opens an action sheet (sold-out / delete live here)
    // so the name always gets the full width — never one letter per line.
    const el = ce('div', 'lrow' + (off ? ' is-off' : ''));
    el.innerHTML = '<span class="lrow__ic">' + (p.imageBase64 ? '<img src="' + p.imageBase64 + '" alt=""/>' : '🍽️') + '</span>'
      + '<div class="hd grow"><b>' + esc(p.name) + (off ? ' <span class="tag tag--danger">' + L.t('sold_out_word') + '</span>' : '') + '</b><small>' + esc(p.categoryId || p.cat || 'Items') + (p.sku ? ' · ' + esc(p.sku) : '') + '</small></div>'
      + '<span class="lrow__amt">' + money(p.priceCents) + '</span>'
      + '<button class="iconbtn" type="button" aria-label="Actions">⋯</button>';
    el.onclick = () => OFMenuEditor(p.id);
    el.querySelector('button').onclick = (e) => {
      e.stopPropagation();
      OFPick(p.name, esc(p.categoryId || p.cat || 'Items') + ' · ' + money(p.priceCents), [
        { label: '✏️ ' + L.t('edit'), act: () => OFMenuEditor(p.id) },
        { label: (off ? '✅ ' : '🚫 ') + L.t(off ? 'back_on_menu' : 'mark_sold'), act: () => menuToggleSoldout(p.id) },
        { label: '🗑 ' + L.t('delete'), kind: 'danger', act: () => menuDeleteConfirm(p) },
        { label: L.t('cancel'), kind: 'ghost' }
      ]);
    };
    host.appendChild(el);
  }
  if (!list.length) host.appendChild(ce('p', 'muted small', L.t('empty')));
}
async function menuToggleSoldout(id) {
  const p = await idbGet('products', id, null); if (!p) return;
  p.available = (p.available === false || p.avail === false);
  p.avail = p.available;
  await idbPut('products', p); await kvSet('rev', Date.now()); syncNow();
  toast(p.available ? p.name + ' — ' + L.t('back_on_menu') : p.name + ' — ' + L.t('sold_out_word'));
  if (ACTIVE_TAB === 'menu') renderMenu();
}
function menuDeleteConfirm(p) {
  OFDialog({ title: L.t('delete') + ' — ' + esc(p.name), bodyHtml: '<p class="muted small">This removes the item from your menu. Sales history is kept in reports.</p>' });
  const wrap = ce('div', 'row');
  const no = ce('button', 'btn btn--ghost grow', L.t('cancel'));
  no.onclick = () => closeDlg();
  const yes = ce('button', 'btn btn--primary grow', L.t('delete'));
  yes.style.background = 'var(--danger)';
  yes.onclick = async () => { closeDlg(); await idbDel('products', p.id); await kvSet('rev', Date.now()); syncNow(); if (ACTIVE_TAB === 'menu') renderMenu(); };
  wrap.append(no, yes);
  $('dlg-body').appendChild(wrap);
}

/* ================= STOCK TAB ================= */
async function renderStock() {
  const host = $('tab-stock'); if (!host) return;
  host.innerHTML = '';
  const head = ce('div', 'row');
  head.innerHTML = '<h2 class="grow" style="font-weight:900;letter-spacing:-.5px">' + L.t('stock') + '</h2><button class="btn btn--sm btn--primary" data-act="stock.add">+ ' + L.t('add_stock') + '</button>';
  host.appendChild(head);
  host.appendChild(ce('p', 'muted small', 'Stock drops by itself when a paid order has a linked item. Watch for low and out.'));
  const ss = await stockAll();
  for (const s of ss) {
    const lvl = s.qty <= 0 ? ['Out', 'tag--danger'] : (s.qty <= (s.lowStockAt ?? s.lowAt ?? 5) ? ['Low', 'tag--gold'] : ['OK', 'tag--mint']);
    const el = ce('div', 'lrow');
    el.innerHTML = '<span class="lrow__ic">📦</span><div class="hd grow"><b>' + esc(s.name) + ' <span class="tag ' + lvl[1] + '">' + lvl[0] + '</span></b><small>qty ' + s.qty + ' ' + (s.unit || 'pcs') + (s.costCents ? ' · cost ' + money(s.costCents) : '') + '</small></div>'
      + '<button class="btn btn--sm" data-act="stock.adjust" data-id="' + s.id + '">' + L.t('adjust') + '</button>';
    el.querySelector('button').onclick = (e) => { e.stopPropagation(); OFAct['stock.adjust'](e.target.closest('button'), e); };
    host.appendChild(el);
  }
  if (!ss.length) host.appendChild(ce('p', 'muted small', L.t('empty')));
}

/* ================= ROLE SCREENS ================= */
const ROLE_META = {
  orderTaker: { ic: '📝', label: 'role_taker' }, kitchen: { ic: '🍳', label: 'role_kitchen' },
  cashier: { ic: '💳', label: 'role_cashier' }, driver: { ic: '🛵', label: 'role_driver' },
  stockClerk: { ic: '📦', label: 'role_stock' }, frontDesk: { ic: '💺', label: 'role_desk' },
  specialist: { ic: '🧑‍⚕️', label: 'role_specialist' },
};
function roleHome(role) {
  STATION_ROLE = role;
  $('rolehdr-title').textContent = L.t(ROLE_META[role].label);
  $('rolehdr-sub').textContent = SHOP.profile.name + ' · ' + SHOP.profile.model;
  show('view-rolehome');
  renderRoleHome(role);
  document.documentElement.dir = langDir(); applyText();
}
async function renderRoleHome(role) {
  const host = $('role-body'); if (!host) return;
  host.innerHTML = '';
  const os = await orders();
  const renderers = {
    orderTaker: async () => {
      roleZone_Take(host, os);
    },
    kitchen: async () => { roleZone_Kitchen(host, os); },
    cashier: async () => { roleZone_Cashier(host, os); },
    driver: async () => { await roleZone_Driver(host, os); },
    stockClerk: async () => { await renderStockHome(host); },
    frontDesk: async () => { await roleZone_Desk(host); },
    specialist: async () => { roleZone_Specialist(host, os); },
  };
  await (renderers[role] || renderers.orderTaker)();
  updateChips();
}
async function renderStockHome(host) {
  const tmp = $('tab-stock'); const keep = tmp.innerHTML;
  tmp.innerHTML = ''; await renderStock();
  host.innerHTML = tmp.innerHTML; tmp.innerHTML = keep;
  host.querySelectorAll('[data-act]').forEach(b => {}); // buttons work via dispatcher
}
function roleZone_Take(host, os) {
  const takerNew = ce('button', 'btn btn--primary btn--full', '+ ' + L.t('new_ticket'));
  takerNew.dataset.act = 'ticket.new'; host.appendChild(takerNew);
  const ready = takerReadyOrders(os);
  if (ready.length) {
    host.appendChild(ce('div', 'sect__t', L.t('ready_to_serve')));
    for (const o of ready) host.appendChild(readyLine(o));
  }
  const mine = os.filter(o => !['paid', 'cancelled', 'refunded'].includes(o.status)).sort((a, b) => b.createdAt - a.createdAt);
  host.appendChild(ce('div', 'sect__t', 'Your floors'));
  const floorsTitle = { restaurant: L.t('tables'), retail: L.t('register'), fastfood: L.t('queue'), services: L.t('appointments') }[SHOP.profile.model] || L.t('tables');
  host.appendChild(ce('div', 'sect__t', floorsTitle));
  renderFloorInto(host);
  host.appendChild(ce('div', 'sect__t', 'Open tickets'));
  if (!mine.length) host.appendChild(ce('p', 'muted small', L.t('no_orders')));
  for (const o of mine.slice(0, 10)) host.appendChild(boardRow(o));
}
async function renderFloorInto(host) {
  const tmp = ce('div'); document.body.appendChild(tmp); tmp.id = 'tab-floor-tmp-x'; tmp.hidden = false;
  const real = $('tab-floor'); const buf = real.innerHTML;
  real.innerHTML = ''; tmp.innerHTML = '';
  await (async () => {
    const ps = SHOP.profile.model;
    if (ps === 'restaurant') { const shadow = ce('div'); shadow.id = 'tab-floor-holder-x'; }
    // lightweight approach: render the floor tab into the real node, then move markup
    const save = real.innerHTML; real.innerHTML = '';
    await renderFloor();
    const nodes = [...real.children]; for (const n of nodes) host.appendChild(n);
    real.innerHTML = save;
  })();
  tmp.remove();
}
function roleZone_Kitchen(host, os) {
  const cols = [[L.t('kds_new'), os.filter(o => ['open', 'sent'].includes(o.status))], [L.t('kds_preparing'), os.filter(o => o.status === 'preparing')], [L.t('kds_ready'), os.filter(o => o.status === 'ready')]];
  const wrap = ce('div', 'grid'); wrap.style.cssText = 'grid-template-columns:repeat(auto-fit, minmax(250px,1fr))';
  for (const [name, list] of cols) {
    const col = ce('div', 'card card--pad');
    col.innerHTML = '<div class="row" style="justify-content:space-between"><b>' + name + '</b><span class="tag">' + list.length + '</span></div><div class="divider"></div>';
    for (const o of list.sort((a, b) => (a.sentAt || a.createdAt) - (b.sentAt || b.createdAt))) {
      const el = ce('div', 'card card--pad'); el.style.cssText = 'margin-bottom:8px;border-radius:16px;background:var(--surface2)';
      const age = Math.max(0, Math.round((Date.now() - (o.sentAt || o.createdAt || Date.now())) / 60000));
      el.innerHTML = '<div class="row" style="justify-content:space-between"><b>' + esc(whereOf(o)) + '</b><span class="tag ' + (age > 12 ? 'tag--danger' : '') + '">' + age + ' min</span></div>'
        + '<div style="margin-top:6px;font-size:13.5px">' + (o.lines || []).map(l => '<div style="display:flex;justify-content:space-between;padding:2px 0;font-weight:600"><span>' + esc(l.name) + (l.notes ? ' · ' + esc(l.notes) : '') + '</span><span>× ' + l.qty + '</span></div>').join('') + '</div>'
        + (o.channel === 'qr' ? '<div class="small muted" style="margin-top:4px;font-weight:700">QR order — ready counts on the guest page too</div>' : '')
        + '<div class="row" style="margin-top:10px">'
        + (['open', 'sent'].includes(o.status) ? '<button class="btn btn--sm btn--primary" data-act="kd.prep" data-id="' + o.id + '">' + L.t('mark_prepared') + '</button>' : '')
        + (o.status !== 'ready' ? '<button class="btn btn--sm btn--mint" data-act="kd.ready" data-id="' + o.id + '">' + L.t('mark_ready') + '</button>' : '<button class="btn btn--sm" data-act="kd.back" data-id="' + o.id + '">↩</button>')
        + '<button class="btn btn--sm btn--ghost" data-act="kd.print" data-id="' + o.id + '">🖨️</button></div>';
      el.querySelectorAll('button').forEach(b => b.onclick = (e) => { e.stopPropagation(); OFAct[b.dataset.act](b, e); });
      col.appendChild(el);
    }
    if (!list.length) col.appendChild(ce('p', 'muted small', L.t('no_orders')));
    wrap.appendChild(col);
  }
  host.appendChild(wrap);
}
function roleZone_Cashier(host, os) {
  const unpaid = os.filter(o => !['paid', 'cancelled', 'refunded'].includes(o.status));
  host.appendChild(ce('h2', null, L.t('payment_queue')));
  host.appendChild(ce('p', 'muted small', 'Every unpaid bill — one tap opens the pay sheet.'));
  let total = 0; for (const o of unpaid) total += billOf(o).due;
  const card = ce('div', 'card card--forest'); card.style.cssText = 'padding:14px;margin:12px 0';
  card.innerHTML = '<span class="small" style="opacity:.8;font-weight:700">' + unpaid.length + ' unpaid</span><div style="font-size:30px;font-weight:900;letter-spacing:-.5px;margin-top:4px">' + money(total) + '</div>';
  host.appendChild(card);
  for (const o of unpaid.sort((a, b) => a.createdAt - b.createdAt)) {
    const b = billOf(o); const age = Math.max(0, Math.round((Date.now() - (o.createdAt || 0)) / 60000));
    const el = ce('div', 'lrow');
    el.innerHTML = '<div class="hd grow"><b>' + esc(whereOf(o)) + '</b><small>' + age + ' min · ' + (o.lines || []).length + ' item(s)</small></div><span class="lrow__amt">' + money(b.due) + '</span><button class="btn btn--sm btn--gold" data-act="kd.open" data-id="' + o.id + '">' + L.t('pay') + '</button>';
    el.querySelector('button').onclick = (e) => { e.stopPropagation(); OFAct['kd.open'](e.target.closest('button'), e); };
    host.appendChild(el);
  }
  if (!unpaid.length) host.appendChild(ce('p', 'muted small', L.t('no_orders')));
}
async function roleZone_Driver(host, os) {
  const st = await kvGet('driverStatus', 'free');
  host.appendChild(ce('h2', null, L.t('deliveries')));
  const chips = ce('div', 'typechips'); chips.style.marginTop = '10px';
  for (const s of [['free', L.t('free')], ['busy', L.t('busy')], ['offline', L.t('offline')]]) {
    const b = ce('button', 'fchip' + (st === s[0] ? ' is-on' : ''), s[1]);
    b.onclick = async () => { await kvSet('driverStatus', s[0]); syncNow(); renderRoleHome('driver'); };
    chips.appendChild(b);
  }
  host.appendChild(chips);
  host.appendChild(ce('p', 'muted small', 'Works off shop Wi-Fi too — the room keeps you in the loop.'));
  const dev = (await orders()).filter(o => o.type === 'delivery' && !['paid', 'cancelled', 'refunded'].includes(o.status));
  const me = await deviceId();
  for (const o of dev) {
    const el = boardRow(o);
    const acts = ce('div', 'row'); acts.style.cssText = 'margin-top:8px;gap:6px';
    if (o.status !== 'out') acts.append(Object.assign(ce('button', 'btn btn--sm btn--primary', L.t('out_for_delivery')), { onclick: je(async () => { o.status = 'out'; o.driverId = me; await idbPut('orders', o); await kvSet('rev', Date.now()); syncNow(); renderRoleHome('driver'); }) }));
    acts.append(Object.assign(ce('button', 'btn btn--sm', L.t('picked_up')), { onclick: je(async () => { o.status = 'served'; await idbPut('orders', o); await kvSet('rev', Date.now()); syncNow(); renderRoleHome('driver'); }) }));
    el.appendChild(acts); host.appendChild(el);
  }
  if (!dev.length) host.appendChild(ce('p', 'muted small', L.t('empty')));
}
async function roleZone_Desk(host) { await renderFloorAppts(host); }
function roleZone_Specialist(host, os) {
  host.appendChild(ce('h2', null, L.t('assigned_to_me')));
  deviceId().then(me => {
    const mine = os.filter(o => o.staffId === me && !['paid', 'cancelled', 'refunded', 'served'].includes(o.status));
    for (const o of mine) host.appendChild(boardRow(o));
    if (!mine.length) host.appendChild(ce('p', 'muted small', L.t('empty')));
  });
}
const je = fn => async (e) => { e && e.stopPropagation && e.stopPropagation(); try { await fn(); } catch (err) { console.error(err); } };

/* ——— print helpers shared (kitchen slip path, no prices) ——— */
function ofPrintKitchen(o) { try { if (window.OFPrintReceipt) OFPrintReceipt(o, { type: 'kitchen' }); } catch {} }
function printReceipt(o, opts) { if (window.OFPrintReceipt) window.OFPrintReceipt(o, opts || {}); }

/* ================= ACTIONS REGISTRY ================= */
window.OFAct = window.OFAct || {};
Object.assign(window.OFAct, {
  'license.activate': () => activateLicense(),
  'license.station': () => show('view-connect'),
  'license.reset': async () => { show('view-license'); },
  'license.back': () => show('view-license'),
  'connect.join': async () => OFConnectJoin(),
  'setup.done': () => setupDone(),
  'shell.cover': () => OFCoverMenu(),
  'shell.tab.home': () => setTab('home'), 'shell.tab.floor': () => setTab('floor'),
  'shell.tab.menu': () => setTab('menu'), 'shell.tab.stock': () => setTab('stock'), 'shell.tab.more': () => setTab('more'),
  'more.open': () => setTab('more'),
  'more.goto.cloud': () => { setTab('more'); OFAct['more.openAt']?.('cloud'); },
  'ticket.new': () => newTicket({}),
  'role.leave': async () => { await kvSet('role', null); location.reload(); },
  'rolecover.kitchen': () => roleHome('kitchen'),
  'home.roomqr': () => OFAct['home.tableqr']?.(null, null),
  'home.tableqr': (el, t) => OFShowTableQR(t),
  'kd.prep': async (b) => { const o = await idbGet('orders', b.dataset.id); if (o) { o.status = 'preparing'; await idbPut('orders', o); await kvSet('rev', Date.now()); await sendCmd({ orders: [o] }); refreshBoard(); renderActiveTab(true); renderRoleHome(STATION_ROLE); } },
  'kd.back': async (b) => { const o = await idbGet('orders', b.dataset.id); if (o && o.status === 'ready') { o.status = 'preparing'; await idbPut('orders', o); await kvSet('rev', Date.now()); await sendCmd({ orders: [o] }); refreshBoard(); renderActiveTab(true); renderRoleHome(STATION_ROLE); } },
  'kd.ready': async (b) => { const o = await idbGet('orders', b.dataset.id, null); if (o) { o.status = 'ready'; await idbPut('orders', o); await kvSet('rev', Date.now()); await sendCmd({ orders: [o] }); toast(whereOf(o) + ' — ready', 'Every taker + Main just heard ✓'); chime('ready'); refreshBoard(); renderActiveTab(true); renderRoleHome(STATION_ROLE); } },
  'kd.open': (b) => openTicket(b.dataset.id),
  'ticket.back': () => {
    const prev = window.__tktPrev || VSTACK.pop();
    window.__tktPrev = null;
    show(prev || (ROLE === 'main' ? 'view-main' : 'view-rolehome'));
  },
  'tk.served': async (b) => OFAct['ticket.served'](b),
  'ticket.served': async (b) => {
    const o = await idbGet('orders', b.dataset.id, null);
    if (o) { o.status = 'served'; await idbPut('orders', o); await kvSet('rev', Date.now()); await sendCmd({ orders: [o] }); toast(whereOf(o) + ' served ✓'); refreshBoard(); renderActiveTab(true); if (ROLE !== 'main') renderRoleHome(STATION_ROLE); }
  },
  'floor.addtable': () => OFAddTable(),
  'appt.book': () => OFBookAppt(),
  'appt.start': async (b) => { const a = await idbGet('appointments', b.dataset.id, null); if (a) { a.status = 'in_service'; await idbPut('appointments', a); await kvSet('rev', Date.now()); syncNow(); renderActiveTab(true); renderRoleHome(STATION_ROLE); } },
  'appt.finish': async (b) => { const a = await idbGet('appointments', b.dataset.id, null); if (a) { a.status = 'done'; await idbPut('appointments', a); await kvSet('rev', Date.now()); syncNow(); renderActiveTab(true); renderRoleHome(STATION_ROLE); } },
  'menu.add': () => OFMenuEditor(null),
  'menu.edit': (b) => OFMenuEditor(b.dataset.id),
  'menu.soldout': async (b) => {
    const p = await idbGet('products', b.dataset.id, null); if (!p) return;
    p.available = !(p.available === false || p.avail === false); p.avail = p.available;
    await idbPut('products', p); await kvSet('rev', Date.now()); syncNow();
    toast(p.available ? p.name + ' — ' + L.t('back_on_menu') : p.name + ' — ' + L.t('sold_out_word'));
    renderActiveTab(true);
  },
  'menu.scan': () => OFMenuScan(),
  'sub.back': () => goBack(),
  'floor.held': () => OFHeldSales(),
  'display.close': () => { $('view-display').hidden = true; show('view-ticket'); },
  'kd.print': (b) => idbGet('orders', b.dataset.id, null).then(o => { if (o) ofPrintKitchen(o); }),
  'stock.add': () => {
    OFDialog({ title: L.t('add_stock') });
    $('dlg-body').innerHTML = '<div class="grid"><input id="sk-name" placeholder="' + L.t('name_label') + '"/><input id="sk-qty" type="number" inputmode="decimal" placeholder="' + 'Starting qty' + '"/><input id="sk-low" type="number" placeholder="' + L.t('low_at') + '"/><input id="sk-unit" placeholder="' + 'Unit (pcs, kg, L)' + '"/><input id="sk-cost" type="number" inputmode="decimal" placeholder="' + L.t('cost') + '"/></div>';
    $('dlg-btns').innerHTML = '';
    const no = ce('button', 'btn btn--ghost', L.t('cancel'));
    no.onclick = () => closeDlg();
    const ok = ce('button', 'btn btn--mint', L.t('save'));
    ok.onclick = async () => {
      const name = $('sk-name').value.trim(); if (!name) return toast('Name?');
      await idbPut('stock', { id: C.uuid(), name, qty: Number($('sk-qty').value) || 0, lowStockAt: Number($('sk-low').value) || 5, unit: $('sk-unit').value.trim() || 'pcs', costCents: C.cents(Number($('sk-cost').value) || 0) });
      await kvSet('rev', Date.now()); syncNow(); closeDlg(); toast(name + ' added'); renderActiveTab(true); if (ROLE !== 'main') renderRoleHome(STATION_ROLE);
    };
    $('dlg-btns').appendChild(no);
    $('dlg-btns').appendChild(ok);
  },
  'stock.adjust': async (b) => {
    const s = await idbGet('stock', b.dataset.id, null); if (!s) return;
    OFDialog({ title: s.name + ' — adjust' });
    $('dlg-body').innerHTML = '<p class="muted small" style="font-weight:600">On hand now: ' + s.qty + ' ' + (s.unit || 'pcs') + '</p><div class="qtyctl" style="max-width:260px;margin:12px auto 0"><button type="button" id="sa-minus" style="font-size:22px">−</button><b id="sa-val" style="font-size:22px">0</b><button type="button" id="sa-plus" style="font-size:22px">+</button></div>';
    $('dlg-btns').innerHTML = '';
    let delta = 0;
    const draw = () => $('sa-val').textContent = (delta > 0 ? '+' : '') + delta;
    $('sa-minus').onclick = () => { delta--; draw(); };
    $('sa-plus').onclick = () => { delta++; draw(); };
    const ok = ce('button', 'btn btn--mint', L.t('done'));
    ok.onclick = async () => {
      s.qty = Math.max(0, (s.qty || 0) + delta);
      await idbPut('stock', s); await kvSet('rev', Date.now()); syncNow(); closeDlg();
      toast(s.name + ' → ' + s.qty + ' ' + (s.unit || 'pcs')); renderActiveTab(true); if (ROLE !== 'main') renderRoleHome(STATION_ROLE);
    };
    const low = ce('button', 'btn btn--ghost', 'Set low alert');
    low.onclick = () => {
      const v = prompt('Alert me when ≤ (number):', String(s.lowStockAt ?? 5));
      if (v != null) { s.lowStockAt = Math.max(0, Number(v) || 0); toast('Low alert: ' + s.lowStockAt); }
    };
    $('dlg-btns').appendChild(low); $('dlg-btns').appendChild(ok);
  },
});
/* cross-file glue for ticket.js / more.js / print.js */
window.SHOP_REF = () => SHOP;
window.OFSyncNow = () => syncNow();
window.__toastFn = toast;
window.__chimeFn = chime;
window.OFMoney = money;
window.OFOrdersAll = orders;
window.OFProductsAll = products;
window.OFStockAll = stockAll;
window.OFBillOf = billOf;
window.OFWhereOf = whereOf;
window.OFRefreshPlan = refreshPlan;
window.OFApplyTheme = applyTheme;
window.OFApplyText = () => { applyDir(); applyText(); buildNav(); renderActiveTab(true); };
window.OFEnterRole = roleHome;
window.OFRelayState = () => RELAY;
window.OFLicenseInfo = async () => ({ lic: await kvGet('license', null), ent: SHOP.entitlements });

function window_init() {
  if (window.__ofInit) return; window.__ofInit = 1;
  // never leave the iPhone staring at cream: capture errors + watchdog
  window.addEventListener('error', (e) => { window.__lastErr = String(e.message || e.error || e); });
  window.addEventListener('unhandledrejection', (e) => { window.__lastErr = String((e.reason && e.reason.message) || e.reason || e); });
  // delegated dispatcher
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-act]');
    if (el && el.dataset.act) { const fn = window.OFAct[el.dataset.act]; if (fn) { e.preventDefault(); fn(el, e); } }
  });
  // splash typewriter
  const typed = $('splash-typed'); const word = 'Jathol'; let i = 0;
  const tick = () => {
    if (i <= word.length) { typed.textContent = word.slice(0, i); i++; setTimeout(tick, 110); }
    else setTimeout(() => { $('splash-tag').classList.add('is-in'); const sp = $('splash'); setTimeout(() => { sp.style.transition = 'opacity .5s'; sp.style.opacity = '0'; setTimeout(() => sp.remove(), 520); }, 850); }, 250);
  };
  tick();
  setTimeout(() => { const sp = $('splash'); if (sp) sp.remove(); }, 6000); // failsafe even if JS stalls
  boot().catch(err => { window.__lastErr = String((err && err.message) || err); console.error('boot', err); });
  // watchdog: if nothing became visible, recover + show what broke
  setTimeout(() => {
    const anyVisible = VIEWS.some(v => { const el = $(v); return el && !el.hidden; });
    if (!anyVisible) {
      show('view-license');
      const sub = document.querySelector('#view-license .gate__sub');
      if (sub && window.__lastErr) sub.textContent = 'Recovered from a hiccup — ' + window.__lastErr.slice(0, 90) + '. Enter your key again.';
      else if (sub) sub.textContent = 'Enter your license key to continue.';
    }
  }, 4200);
}

/* ================= MINI DIALOGS (pick an action etc.) ================= */
window.OFDialog = function ({ title, bodyHtml, buttons }) {
  const root = $('dlg'); root.classList.add('is-open'); root.setAttribute('aria-hidden', 'false');
  $('dlg-title').textContent = title || '';
  $('dlg-body').innerHTML = bodyHtml || '';
  const bs = $('dlg-btns'); bs.innerHTML = '';
  for (const b of (buttons || [])) {
    const el = ce('button', 'btn ' + (b.kind ? 'btn--' + b.kind : ''), esc(b.label));
    el.onclick = async () => { if (b.act) { const r = await b.act(); if (r !== false) closeDlg(); } else closeDlg(); };
    bs.appendChild(el);
  }
  return root;
};
function closeDlg() { const root = $('dlg'); root.classList.remove('is-open'); root.setAttribute('aria-hidden', 'true'); }
window.OFCloseDlg = closeDlg;
// Tapping the dimmed area OUTSIDE any dialog card closes it — the user
// must never be trapped inside a card (Add stock item, pickers, etc.).
{
  const dlgEl = $('dlg');
  dlgEl.addEventListener('click', (e) => { if (e.target === dlgEl) closeDlg(); });
}
function pickAction(title, sub, entries) {
  const body = ce('div', 'grid');
  for (const en of entries) {
    const b = ce('button', 'btn ' + (en.kind ? 'btn--' + en.kind : 'btn--ghost'), esc(en.label));
    b.style.minHeight = '50px';
    b.onclick = async () => { closeDlg(); if (en.act) await en.act(); };
    body.appendChild(b);
  }
  OFDialog({ title, bodyHtml: (sub ? '<p class="muted small" style="margin-bottom:10px">' + esc(sub) + '</p>' : '') });
  $('dlg-body').appendChild(body);
}
window.OFPick = pickAction;

/* ================= CONNECT (join station) ================= */
async function OFConnectJoin() {
  const err = $('connect-err'); err.textContent = '';
  let pair;
  try { pair = C.pairingDecode($('connect-paste').value); }
  catch { err.textContent = 'That does not look like an OF1:… pairing text. Copy it fully.'; return; }
  // preflight: join room over the cloud (deviceId is what makes us a member)
  const dev = await deviceId();
  let info = { ...pair, base: '', device: dev };
  const j = await cloudApi('/api/cloud/join', { code: pair.code, role: 'station', deviceId: dev }, info);
  if (!j) { err.textContent = 'No internet — could not reach the relay. Try again.'; return; }
  if (j.ok !== true) {
    err.textContent = j.error === 'code' || j.error === 'bad_code' ? 'Wrong join code — get a fresh QR/text from Main.' : (j.error === 'no_room' ? 'That room is closed — Main should reopen it (More → Cloud room).' : (j.error === 'full' ? 'The room is full (16 devices).' : (j.error || 'Could not join.')));
    return;
  }
  await kvSet('roomInfo', info);
  await kvSet('role', 'station');
  ROLE = 'station';
  await evolutionaryAppend(info);
  renderRoleScreen();
}
async function evolutionaryAppend(info) { startRelayBoot(info); pullUntilFirstState(); }
async function pullUntilFirstState() { /* loop() already pulls; after first state apply we re-render role views */ }
function renderRoleScreen() {
  const grid = $('role-grid'); if (!grid) return;
  grid.innerHTML = '';
  $('role-shop').textContent = SHOP.profile.name + ' · ' + SHOP.profile.model;
  const roles = C.MODEL_ROLES[SHOP.profile.model] || C.MODEL_ROLES.restaurant;
  for (const r of roles) {
    const b = ce('button', 'modelcard');
    b.innerHTML = '<span class="ic">' + ROLE_META[r].ic + '</span><span>' + L.t(ROLE_META[r].label) + '</span>';
    b.onclick = async () => { await rolePickWithPin(r); };
    grid.appendChild(b);
  }
  show('view-role');
}
async function rolePickWithPin(role) {
  const staff = await idbGetAll('staff', []);
  const pinOn = staff.some(s => s.pinHash);
  if (!pinOn) { await kvSet('stationRole', role); STATION_ROLE = role; roleHome(role); heartbeat(); return; }
  const pick = staff.filter(s => staffCanRole(s, role));
  const list = pick.length ? pick : staff;
  pickAction(L.t('selecting_station'), 'Who are you?', list.map(s => ({ label: s.name, act: async () => { const ok = await pinAsk(s); if (ok === true) { await kvSet('stationRole', role); STATION_ROLE = role; roleHome(role); heartbeat(); } } })).concat([{ label: L.t('cancel'), kind: 'ghost', act: async () => { } }]));
  async function pinAsk(st) {
    await new Promise(resolve => {
      const body = ce('div', 'grid');
      body.innerHTML = '<input id="pin-in" type="password" inputmode="numeric" maxlength="6" placeholder="PIN"/>';
      const ok = ce('button', 'btn btn--mint', L.t('done'));
      body.appendChild(ok);
      $('dlg-title').textContent = st.name + ' — ' + L.t('staff_pin_ask');
      $('dlg-body').innerHTML = ''; $('dlg-body').appendChild(body); $('dlg-btns').innerHTML = '';
      const failsKey = 'pinFails:' + st.id;
      ok.onclick = async () => {
        const lock = await kvGet(failsKey + ':lock', 0);
        if (Date.now() < lock) { toast(L.t('staff_pin_lock')); resolve(false); closeDlg(); return; }
        const entered = $('pin-in').value.trim();
        const hash = await sha256(st.salt + ':' + entered);
        if (hash === st.pinHash) { await kvSet(failsKey, 0); closeDlg(); resolve(true); }
        else {
          const fails = (await kvGet(failsKey, 0)) + 1;
          await kvSet(failsKey, fails);
          if (fails >= 5) { await kvSet(failsKey + ':lock', Date.now() + 5 * 60000); toast(L.t('staff_pin_lock')); closeDlg(); resolve(false); return; }
          toast('Wrong PIN (' + (5 - fails) + ' left)');
        }
      };
    });
  }
}
function staffCanRole(s, role) { return (s.roles || []).includes(role) || !(s.roles || []).length; }
async function sha256(s) {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('');
}
window.OFSha256 = sha256;

/* ================= COVER STATION (main jumps into a role) ================= */
async function OFCoverMenu() {
  const roles = ['orderTaker', 'kitchen', 'cashier', 'stockClerk'];
  if (SHOP.profile.model === 'services') roles.push('frontDesk', 'specialist');
  roles.push('driver');
  pickAction(L.t('cover_role'), 'Main covers a station — full-screen like the APK', roles.map(r => ({ label: ROLE_META[r].ic + '  ' + L.t(ROLE_META[r].label), act: async () => { ROLE === 'main' && (window.__covering = true); roleHome(r); } })).concat([{ label: '🔙 ' + L.t('cover_home'), kind: 'ghost', act: async () => { enterMain(); } }]));
}

/* ================= TABLE TILE OPS ================= */
function OFAddTable() {
  const body = ce('div', 'grid');
  body.innerHTML = '<input id="nt-name" placeholder="Table name (e.g. T9)"/><input id="nt-seats" type="number" min="1" max="16" placeholder="' + L.t('seats') + '"/>';
  const save = ce('button', 'btn btn--mint', L.t('save'));
  body.appendChild(save);
  OFDialog({ title: L.t('new_table') });
  $('dlg-body').appendChild(body);
  save.onclick = async () => {
    const name = $('nt-name').value.trim() || 'T' + ((await tablesAll()).length + 1);
    const seats = Math.max(1, Number($('nt-seats').value) || 2);
    await idbPut('tables', { id: C.uuid(), label: name, name, seats, state: 'free', since: null });
    await kvSet('rev', Date.now()); syncNow(); closeDlg(); renderActiveTab(true);
  };
}
function OFShowTableQR(t) {
  if (!RELAY) { toast('Open the room first', 'More → Cloud room'); return; }
  const body = ce('div', 'grid');
  const d = { r: RELAY.info.room, c: RELAY.info.code, k: RELAY.info.secret, t: t ? (t.id || '') : '', tn: t ? (t.label || t.name || '') : '', shop: SHOP.profile.name };
  const hash = C.b64uEncode(new TextEncoder().encode(JSON.stringify(d)));
  const url = location.origin + '/order.html#' + hash;
  body.innerHTML = '<div class="qrbox"><img width="200" height="200" src="https://api.qrserver.com/v1/create-qr-code/?size=240x240&margin=8&data=' + encodeURIComponent(url) + '" alt="QR"/></div>'
    + '<p class="small muted" style="overflow-wrap:anywhere">' + esc(url) + '</p>';
  const dl = ce('a', 'btn btn--mint', 'Download QR (prints big)');
  dl.href = 'https://api.qrserver.com/v1/create-qr-code/?size=720x720&margin=16&data=' + encodeURIComponent(url);
  dl.target = '_blank'; dl.rel = 'noopener'; dl.download = 'qr-' + (t ? (t.label || 'table') : 'room') + '.png';
  body.appendChild(dl);
  const copy = ce('button', 'btn btn--ghost', 'Copy guest link');
  copy.onclick = async () => { await navigator.clipboard.writeText(url).catch(() => {}); toast('Copied'); };
  body.appendChild(copy);
  OFDialog({ title: t ? ('Table ' + (t.label || t.name) + ' — guest QR') : L.t('qr_ordering') });
  $('dlg-body').appendChild(body);
}

/* ================= HELD SALES ================= */
async function OFHeldSales() {
  const os = (await orders()).filter(o => o.held);
  const body = ce('div', 'grid');
  if (!os.length) body.appendChild(ce('p', 'muted small', L.t('empty')));
  for (const o of os) {
    const b = ce('button', 'btn btn--ghost', esc(whereOf(o)) + ' · ' + money(billOf(o).due));
    b.onclick = async () => { o.held = false; await idbPut('orders', o); await kvSet('rev', Date.now()); closeDlg(); openTicket(o.id); };
    body.appendChild(b);
  }
  OFDialog({ title: L.t('held_sales') }); $('dlg-body').appendChild(body);
}

/* ================= APPOINTMENT BOOKING ================= */
function OFBookAppt() {
  const body = ce('div', 'grid');
  body.innerHTML = '<input id="ap-name" data-ph="customer" placeholder="' + L.t('customer') + '"/><input id="ap-phone" placeholder="' + L.t('phone') + '" inputmode="tel"/><input id="ap-svc" placeholder="' + L.t('service_word') + '"/><input id="ap-staff" placeholder="' + L.t('staff') + '"/><input id="ap-time" type="datetime-local"/><input id="ap-notes" placeholder="' + L.t('notes') + '"/>';
  const save = ce('button', 'btn btn--mint', L.t('save')); body.appendChild(save);
  OFDialog({ title: L.t('book_appt') }); $('dlg-body').appendChild(body);
  save.onclick = async () => {
    const at = new Date($('ap-time').value || Date.now()).getTime();
    await idbPut('appointments', { id: C.uuid(), customer: $('ap-name').value.trim() || 'Walk-in', phone: $('ap-phone').value.trim(), service: $('ap-svc').value.trim(), staff: $('ap-staff').value.trim(), notes: $('ap-notes').value.trim(), at, status: 'booked' });
    await kvSet('rev', Date.now()); syncNow(); closeDlg(); toast('Booked ✓'); renderActiveTab(true);
  };
}

/* ================= MENU EDITOR / SCAN ================= */
function OFMenuEditor(id) {
  Promise.resolve().then(async () => {
    const p = id ? await idbGet('products', id, null) : null;
    const body = ce('div', 'grid');
    body.innerHTML = '<input id="me-name" placeholder="' + L.t('name_label') + '" value="' + esc(p ? p.name || '' : '') + '"/>'
      + '<input id="me-price" type="number" inputmode="decimal" placeholder="' + 'Price' + '" value="' + (p ? (p.priceCents / 100).toFixed(2) : '') + '"/>'
      + '<input id="me-cat" placeholder="Category" value="' + esc(p ? (p.categoryId || p.cat || 'Items') : 'Items') + '"/>'
      + '<input id="me-sku" placeholder="SKU (barcode) — optional" value="' + esc(p ? p.sku || '' : '') + '"/>'
      + '<input id="me-img" type="file" accept="image/*"/>'
      + '<select id="me-stock"><option value="">No stock link</option></select>';
    const ss = await stockAll();
    for (const s of ss) body.querySelector('#me-stock').append(Object.assign(ce('option'), { value: s.id, textContent: s.name + ' (qty ' + s.qty + ')' }));
    if (p && (p.inventoryId || p.stockId)) body.querySelector('#me-stock').value = p.inventoryId || p.stockId;
    OFDialog({ title: p ? L.t('edit') : L.t('add_item') });
    $('dlg-body').appendChild(body);
    const dlg = $('dlg-btns'); dlg.innerHTML = '';
    const save = ce('button', 'btn btn--mint', L.t('save'));
    save.onclick = async () => {
      const name = $('me-name').value.trim(); if (!name) { toast('Give it a name'); return; }
      const priceC = C.cents(Number($('me-price').value) || 0);
      const obj = p || { id: C.uuid(), available: true, avail: true, recipe: [], mods: [], deductQty: 1 };
      obj.name = name; obj.priceCents = priceC; obj.price = priceC / 100;
      obj.categoryId = $('me-cat').value.trim() || 'Items'; obj.cat = obj.categoryId; obj.sku = $('me-sku').value.trim();
      const file = $('me-img').files && $('me-img').files[0];
      if (file) obj.imageBase64 = await fileToB64(file, 240);
      obj.inventoryId = $('me-stock').value || null; obj.stockId = obj.inventoryId;
      await idbPut('products', obj); await kvSet('rev', Date.now()); syncNow(); closeDlg(); toast(name + ' saved'); renderActiveTab(true);
    };
    const del = p ? ce('button', 'btn btn--danger', L.t('delete')) : null;
    if (del) del.onclick = async () => { await idbDel('products', p.id); await kvSet('rev', Date.now()); syncNow(); closeDlg(); toast(p.name + ' deleted'); renderActiveTab(true); };
    const cancel = ce('button', 'btn btn--ghost', L.t('cancel')); cancel.onclick = () => closeDlg();
    dlg.appendChild(cancel); if (del) dlg.appendChild(del); dlg.appendChild(save);
  });
}
function fileToB64(file, max) {
  return new Promise(res => {
    const rd = new FileReader();
    rd.onload = () => {
      const img = new Image();
      img.onload = () => { const cv = document.createElement('canvas'); const sc = Math.min(1, max / Math.max(img.width, img.height)); cv.width = img.width * sc; cv.height = img.height * sc; cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height); res(cv.toDataURL('image/jpeg', .7)); };
      img.onerror = () => res(null); img.src = rd.result;
    };
    rd.onerror = () => res(null);
    rd.readAsDataURL(file);
  });
}
function OFMenuScan() {
  const body = ce('div', 'grid');
  body.innerHTML = '<p class="small muted" style="font-weight:600">Pick a photo or PDF of your menu, or paste lines like <b>Tea 5</b>. Image text can’t be read by this browser, so confirm/adjust the lines yourself before saving.</p>'
    + '<input id="ms-file" type="file" accept="image/*,application/pdf"/>'
    + '<textarea id="ms-lines" rows="7" placeholder="Cappuccino 12&#10;Nasi Lemak 18&#10;Teh Tarik 6"></textarea>';
  const hint = ce('p', 'small muted', 'Nothing read yet.');
  body.appendChild(hint);
  const parseBtn = ce('button', 'btn btn--ghost', 'Read lines as draft items');body.appendChild(parseBtn);
  const save = ce('button', 'btn btn--mint', L.t('save')); body.appendChild(save);
  OFDialog({ title: L.t('menu_scan') }); $('dlg-body').appendChild(body);
  parseBtn.onclick = async () => {
    const lines = $('ms-lines').value.split('\n').map(x => x.trim()).filter(Boolean);
    hint.textContent = 'Read ' + lines.length + ' line(s) — confirm with Save.';
  };
  save.onclick = async () => {
    const lines = $('ms-lines').value.split('\n').map(x => x.trim()).filter(Boolean);
    let added = 0;
    for (const ln of lines) {
      const m = ln.match(/^(.+?)\s+([\d.]+)\s*$/); if (!m) continue;
      const priceC = C.cents(Number(m[2]));
      await idbPut('products', { id: C.uuid(), name: m[1], priceCents: priceC, price: priceC / 100, categoryId: 'Items', cat: 'Items', available: true, avail: true, recipe: [], mods: [], deductQty: 1 });
      added++;
    }
    await kvSet('rev', Date.now()); syncNow(); closeDlg(); toast(added + ' item(s) saved'); renderActiveTab(true);
  };
}

window.addEventListener('DOMContentLoaded', window_init);
})();
