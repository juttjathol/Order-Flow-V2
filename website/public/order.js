/* ============================================================
   ORDER FLOW POS — order.js (guest QR menu)
   Reads OF payload from #hash, joins the room as a guest,
   renders the shop's menu (sold-out hidden), sends encrypted
   order commands. Prices come from the shop only — guests can
   never set them. Flood caps live client + server side.
   ============================================================ */
(function () {
'use strict';
const C = OFCore;
const $ = id => document.getElementById(id);
const ce = (t, c, h) => { const e = document.createElement(t); if (c) e.className = c; if (h != null) e.innerHTML = h; return e; };
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

let CFG = null, KEY = null, CURSOR = 0, STATE = null, CART = new Map(), SESSION_START = Date.now(), CACHE_SEEDED = false;
let CAT = 'all', SENT_GIDS = [];
const BASES = ['', 'https://order-flow-v2.pages.dev'];
let BASE = location.protocol.startsWith('http') ? '' : BASES[1];

function fail(t, b) { $('g-err').hidden = false; $('g-err-t').textContent = t; if (b) $('g-err-b').textContent = b; $('g-bar').hidden = true; }

async function key(secret) {
  const raw = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('orderflow-cloud|v1|' + secret));
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
}
async function enc(plain) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const out = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, KEY, new TextEncoder().encode(plain));
  return C.b64uEncode(iv) + '.' + C.b64uEncode(out);
}
async function dec(blob) {
  const dot = String(blob || '').indexOf('.'); if (dot <= 0) return null;
  try {
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: C.b64uDecode(blob.slice(0, dot)) }, KEY, C.b64uDecode(blob.slice(dot + 1)));
    return new TextDecoder().decode(plain);
  } catch { return null; }
}
async function api(path, body) {
  const payload = JSON.stringify(body);
  for (const b of [BASE, ...BASES]) {
    try {
      const r = await fetch(b + path, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: payload });
      const j = await r.json();
      if (j) { BASE = b; return j; }
    } catch { /* next base */ }
  }
  return null;
}

async function boot() {
  const hash = location.hash.slice(1);
  if (!hash) return fail('This QR looks out of date', 'No order data in the link. Ask staff for a fresh code.');
  let cfg;
  try { cfg = JSON.parse(new TextDecoder().decode(C.b64uDecode(hash))); } catch { return fail('This QR looks out of date', 'Ask the staff for a fresh code — we renew them when the room reopens.'); }
  if (!cfg.r || !cfg.c || !cfg.k) return fail('This QR looks out of date');
  CFG = cfg; KEY = await key(cfg.k);
  CFG.device = 'guest-' + Math.random().toString(36).slice(2, 10);
  // Instant menu on repeat visits: render the last snapshot we received for
  // this room from localStorage, then refresh it live below.
  try {
    const hit = JSON.parse(localStorage.getItem('ofqrmenu:' + cfg.r) || 'null');
    if (hit && hit.s) { CACHE_SEEDED = true; applyState(hit.s); $('g-sub').textContent = 'Refreshing…'; }
  } catch { /* no cache */ }
  // Worker contract (v1.1.83+): join needs room + code + deviceId — the
  // deviceId is what makes us a member allowed to send.
  const j = await api('/api/cloud/join', { room: cfg.r, code: cfg.c, role: 'guest', deviceId: CFG.device });
  if (!j || j.ok !== true) return fail('Room is closed right now', 'The shop is not taking QR orders at the moment. Order at the counter.');
  $('g-shop').textContent = cfg.shop || 'Order here';
  if (cfg.tn) {
    const chip = ce('div', 'g-chip', '📍 Table ' + esc(cfg.tn));
    $('g-hero').querySelector('div').appendChild(chip);
  }
  await api('/api/cloud/send', { room: cfg.r, device: CFG.device, msg: await enc(JSON.stringify({ t: 'cmd', c: { type: 'hello', device: CFG.device, role: 'guest', at: Date.now() } })) });
  requestMenu(true); // ask main for a fresh push instead of waiting silently
  poll();
}
let parts = null, LAST_MENU_REQ = 0;
async function requestMenu(force) {
  const now = Date.now();
  if (!force && LAST_MENU_REQ && now - LAST_MENU_REQ < 6000) return;
  LAST_MENU_REQ = now;
  try { await api('/api/cloud/send', { room: CFG.r, device: CFG.device, msg: await enc(JSON.stringify({ t: 'cmd', c: { type: 'menu_request', device: CFG.device, role: 'guest', at: now } })) }); } catch {}
}
async function poll() {
  try {
    const j = await api('/api/cloud/pull', { room: CFG.r, device: CFG.device, after: CURSOR });
    if (j && j.ok !== false && Array.isArray(j.msgs)) {
      if (typeof j.cursor === 'number') CURSOR = j.cursor;
      for (const m of j.msgs) {
        if (!m || m.sender === CFG.device) continue;
        const plain = await dec(String(m.msg || '')); if (!plain) continue;
        let env; try { env = JSON.parse(plain); } catch { continue; }
        if (env.t === 'state') applyState(env.s);
        else if (env.t === 'state_part') {
          const k = Number(env.parts) || 1, i = Number(env.part) || 0;
          parts = parts || Array(k).fill('');
          if (i >= 0 && i < k) parts[i] = String(env.s || '');
          if (parts.every(p => p !== '')) { const s = parts.join(''); parts = null; applyState(s); }
        } else if (env.t === 'cmd' && env.c && env.c.type === 'order_rejected') {
          toast('The kitchen is slammed — your order did not go through, please ask staff.');
        } else if (env.t === 'cmd' && env.c && env.c.type === 'menu_request') { /* main will push state */ }
      }
    }
  } catch { /* keep polling — a dropped request is not a reason to die */ }
  if (!STATE) {
    // No live menu yet: keep asking, and tell the customer what's happening
    // instead of an eternal "Loading the menu…".
    requestMenu(false);
    if (Date.now() - SESSION_START > 20000 && !CACHE_SEEDED) {
      const g = $('g-sub');
      if (g && !g.dataset.wait) { g.dataset.wait = '1'; g.textContent = 'Still waiting for the menu — is Order Flow open on the main device?'; }
    }
  }
  setTimeout(poll, document.hidden ? 9000 : (STATE ? 2500 : 1100));
}
function applyState(json) {
  let obj; try { obj = JSON.parse(json); } catch { return; }
  STATE = obj;
  // remember the last good snapshot so the next scan renders instantly
  try { if (json && json.length < 600000) localStorage.setItem('ofqrmenu:' + CFG.r, JSON.stringify({ at: Date.now(), s: json })); } catch {}
  const p = (obj.kv && obj.kv.shop && obj.kv.shop.profile) || {};
  if (p.name && !CFG.shop) $('g-shop').textContent = p.name;
  if (p.brandOn) {
    $('g-hero').style.background = 'linear-gradient(135deg,' + (p.accent || '#2EA771') + ',#16302A)';
    if (p.tagline) $('g-sub').textContent = p.tagline;
    if (p.welcome) { const w = ce('div', 'g-live'); w.textContent = '👋 ' + p.welcome; $('g-live').hidden = false; $('g-live').replaceChildren(w); }
    if (p.hours) $('g-note').textContent = '🕒 ' + p.hours + ' · pay at the counter';
  } else {
    $('g-sub').textContent = 'Order from your table — kitchen gets it straight away';
  }
  renderMenu();
  renderLive();
}
function products() {
  if (!STATE) return [];
  return (STATE.products || []).map(pr => ({ ...pr, priceCents: pr.priceCents != null ? pr.priceCents : C.cents(pr.price) })).filter(pr => pr.available !== false && pr.avail !== false);
}
function money(c) { const cur = ((STATE && STATE.kv && STATE.kv.shop && STATE.kv.shop.profile) || {}).currency || 'RM'; return C.fmtCents(c, cur); }
function renderMenu() {
  const ps = products();
  if (!ps.length) return;
  const cats = [...new Set(ps.map(p => p.categoryId || p.cat || 'Menu'))];
  const catsHost = $('g-cats'); catsHost.innerHTML = '';
  const mk = (id, label) => { const b = ce('button', CAT === id ? 'is-on' : '', label); b.onclick = () => { CAT = id; renderMenu(); }; catsHost.appendChild(b); };
  mk('all', 'All'); for (const c of cats) mk(c, c);
  const host = $('g-menu'); host.innerHTML = '';
  for (const p of ps.filter(x => CAT === 'all' || (x.categoryId || x.cat || 'Menu') === CAT)) {
    const inCart = CART.get(p.id);
    const row = ce('div', 'g-item');
    row.innerHTML = '<div class="g-item__img">' + (p.imageBase64 ? '<img src="' + p.imageBase64 + '" alt=""/>' : '🍽️') + '</div>'
      + '<div style="flex:1;min-width:0"><b>' + esc(p.name) + '</b><small>' + esc(p.description || '') + '</small></div>'
      + '<span class="prc">' + money(p.priceCents) + '</span>'
      + (inCart ? '<span class="g-qty"><button data-d="-1">−</button><b>' + inCart.qty + '</b><button data-d="1">＋</button></span>' : '<button class="g-add">＋</button>');
    if (inCart) {
      row.querySelector('[data-d="-1"]').onclick = () => bump(p, -1);
      row.querySelector('[data-d="1"]').onclick = () => bump(p, 1);
    } else row.querySelector('.g-add').onclick = () => bump(p, 1);
    host.appendChild(row);
  }
  renderBar();
}
function bump(p, d) {
  const cur = CART.get(p.id);
  const qty = (cur ? cur.qty : 0) + d;
  if (qty <= 0) CART.delete(p.id); else CART.set(p.id, { p, qty });
  renderMenu();
}
function cartTotal() { let t = 0; for (const v of CART.values()) t += v.p.priceCents * v.qty; return t; }
function renderBar() {
  const host = $('g-cartlines');
  const bar = $('g-bar');
  if (!CART.size && !SENT_GIDS.length) { bar.hidden = true; $('g-send').disabled = true; host.innerHTML = ''; return; }
  bar.hidden = false; host.innerHTML = '';
  for (const v of CART.values()) host.appendChild(ce('div', 'tot', '<span>' + v.qty + ' × ' + esc(v.p.name) + '</span><span>' + money(v.p.priceCents * v.qty) + '</span>'));
  const btn = $('g-send');
  btn.disabled = !CART.size;
  btn.textContent = CART.size ? 'Send order · ' + money(cartTotal()) : 'Sent ✓';
}
async function sendOrder() {
  if (!CART.size) return;
  // client-side flood caps (server enforces too): 6 per table-hour, 10 items each
  try {
    const keyLS = 'ofqrcap:' + (CFG.t || 'none');
    const now = Date.now();
    const log = JSON.parse(localStorage.getItem(keyLS) || '[]').filter(x => now - x < 3600000);
    if (log.length >= 6) return toast('Slow down a little — too many orders from this table in an hour.', true);
    if (cartCount() > 10) return toast('Max 10 items per order — split it into two.', true);
    log.push(now); localStorage.setItem(keyLS, JSON.stringify(log));
  } catch {}
  const gid = 'g' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  const lines = [];
  for (const v of CART.values()) lines.push({ productId: v.p.id, name: v.p.name, qty: v.qty, priceCents: v.p.priceCents, notes: '' });
  const cmd = { type: 'order', gid, tableId: CFG.t || null, tableName: CFG.tn || '', lines, at: Date.now() };
  const msg = await enc(JSON.stringify({ t: 'cmd', c: cmd }));
  const j = await api('/api/cloud/send', { room: CFG.r, device: CFG.device, msg });
  if (j && j.ok !== false) {
    SENT_GIDS.push({ gid, at: Date.now() });
    CART.clear();
    renderMenu();
    const fireAuto = (((STATE && STATE.kv && STATE.kv.shop && STATE.kv.shop.profile) || {}).fireMode || 'auto') === 'auto';
    toast(fireAuto ? 'Sent to the kitchen ✓ — we will bring it out' : 'Order placed ✓ — the staff will confirm it at the counter');
    renderLive();
  } else toast('Could not reach the room — try again', true);
}
function cartCount() { let n = 0; for (const v of CART.values()) n += v.qty; return n; }
function renderLive() {
  if (!STATE || !SENT_GIDS.length) return;
  const orders = (STATE.orders || []).filter(o => o.channel === 'qr' && (o.createdAt || 0) >= SESSION_START - 60000 && (!CFG.t || o.tableId === CFG.t));
  if (!orders.length) return;
  const host = $('g-live'); host.hidden = false; host.innerHTML = '';
  for (const o of orders.sort((a, b) => b.createdAt - a.createdAt).slice(0, 3)) {
    const st = o.status;
    const cls = st === 'paid' ? ' is-paid' : (['preparing', 'sent', 'open'].includes(st) ? ' is-prep' : '');
    const txt = { open: '⏳ Waiting for the counter…', sent: '👨‍🍳 In the kitchen…', preparing: '👨‍🍳 Cooking…', ready: '✅ Ready — on the way to your table', served: '🍽️ Served — enjoy', paid: '🧾 Paid — thank you', cancelled: '✖ Cancelled — ask staff', refunded: '↩ Refunded' }[st] || st;
    host.appendChild(ce('div', 'g-live' + cls, txt + ' · ' + (o.lines || []).length + ' item(s)'));
  }
}
function toast(msg, err) {
  const t = ce('div', 'g-live' + (err ? ' is-prep' : ''), msg);
  t.style.position = 'fixed'; t.style.left = '14px'; t.style.right = '14px'; t.style.bottom = 'calc(90px + env(safe-area-inset-bottom))'; t.style.zIndex = 99; t.style.margin = 0;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3200);
}
$('g-send').addEventListener('click', sendOrder);
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
