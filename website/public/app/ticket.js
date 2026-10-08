/* ============================================================
   ORDER FLOW POS — ticket.js
   Full-screen /order route (bottom nav hides, back = ops):
   type chips, table/customer/driver meta, lines with qty,
   notes, modifiers, hold/send/flow buttons, discount, service,
   tax, tip-in-pay, split-even, move/merge, cancel, refund,
   customer display, share receipt, pay sheet (APK-identical).
   ============================================================ */
(function () {
'use strict';
const C = OFCore, L = OFLang, A = window.OFAct;
const $ = id => document.getElementById(id);
const ce = (t, c, h) => { const e = document.createElement(t); if (c) e.className = c; if (h != null) e.innerHTML = h; return e; };
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
let CUR = null;          // live PosOrder
let T_CAT = 'all';

const money = c => C.fmtCents(c == null ? 0 : c, SHOP_SAFE().profile.currency || 'RM');
function SHOP_SAFE() { return window.SHOP_REF ? window.SHOP_REF() : { profile: { currency: 'RM', model: 'restaurant' }, entitlements: { allOn: true } }; }
const bill = () => C.billOf(CUR, SHOP_SAFE().profile);

/* ================= OPEN + RENDER ================= */
window.OFOpenTicket = async function (id) {
  CUR = await idbGet('orders', id, null);
  if (!CUR) return;
  showTicketView();
  renderTicket();
};
function showTicketView() {
  const views = ['view-license', 'view-locked', 'view-connect', 'view-role', 'view-setup', 'view-main', 'view-rolehome', 'view-ticket', 'view-sub', 'view-display'];
  const cur = views.find(v => !$(v).hidden);
  if (cur !== 'view-ticket') window.__tktPrev = cur;               // remember where back lands
  views.forEach(v => $(v).hidden = v !== 'view-ticket');
  window.scrollTo(0, 0);
}
async function renderTicket() {
  if (!CUR) return;
  $('tkt-title').textContent = 'Ticket #' + (CUR.ticketNo || '—');
  const badges = $('tkt-badges'); badges.innerHTML = '';
  const st = { open: ['New', 'tag--blue'], sent: ['Kitchen', 'tag--blue'], preparing: ['Preparing', 'tag--gold'], ready: ['READY ✓', 'tag--mint'], served: ['Served', 'tag--gold'], paid: ['PAID', 'tag--mint'], cancelled: ['Cancelled', 'tag--danger'], refunded: ['Refunded', 'tag--danger'], out: ['Out for delivery', 'tag--blue'] }[CUR.status] || [CUR.status, ''];
  badges.appendChild(ce('span', 'tag ' + st[1], st[0]));
  if (CUR.held) badges.appendChild(ce('span', 'tag tag--blue', 'Held'));
  $('tkt-sub').textContent =
    (CUR.tableName ? 'Table ' + CUR.tableName + ' · ' : '') +
    (CUR.persons ? CUR.persons + ' guest(s) · ' : '') + new Date(CUR.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  renderTypes(); renderMeta(); renderLines(); await renderMenuPick(); renderTotals();
}
function renderTypes() {
  const host = $('tkt-types'); host.innerHTML = '';
  const m = SHOP_SAFE().profile.model;
  const ops = m === 'restaurant' ? ['dineIn', 'takeaway', 'delivery']
    : m === 'fastfood' ? ['takeaway', 'delivery', 'dineIn']
    : m === 'services' ? ['service'] : ['retail', 'delivery', 'takeaway'];
  for (const t of ops) host.appendChild(typeChip(t));
}
function typeChip(t) {
  const names = { dineIn: 'Dine in', takeaway: 'Takeaway', delivery: 'Delivery', retail: 'Retail', service: 'In-shop', qr: 'QR', grabfood: 'GrabFood', foodpanda: 'Foodpanda' };
  const b = ce('button', 'tchip' + (CUR.type === t ? ' is-on' : ''), names[t] || t);
  b.onclick = async () => { CUR.type = t; await persist(); renderTicket(); };
  return b;
}
async function renderMeta() {
  const host = $('tkt-meta'); host.innerHTML = '';
  const m = SHOP_SAFE().profile.model;
  if (m === 'restaurant' || m === 'fastfood') {
    const ts = await idbGetAll('tables', []);
    const sel = ce('select'); sel.innerHTML = '<option value="">No table</option>';
    for (const t of ts) sel.append(Object.assign(ce('option'), { value: t.id, textContent: (t.label || t.name) }));
    sel.value = CUR.tableId || '';
    sel.onchange = async () => { const t = ts.find(x => x.id === sel.value); CUR.tableId = t ? t.id : null; CUR.tableName = t ? (t.label || t.name) : ''; await persist(); renderTicket(); };
    host.appendChild(wrapField('Table', sel));
    const pers = ce('input'); pers.type = 'number'; pers.min = 1; pers.max = 24; pers.value = CUR.persons || '';
    pers.placeholder = 'Guests'; pers.onchange = async () => { CUR.persons = Math.max(1, Number(pers.value) || 1); await persist(); };
    host.appendChild(wrapField(L.t('seat_label'), pers));
  }
  if (CUR.type === 'delivery') {
    const addr = ce('input'); addr.placeholder = 'Delivery address'; addr.value = CUR.address || '';
    addr.onchange = async () => { CUR.address = addr.value; await persist(); };
    host.appendChild(wrapField('Address', addr));
    const drv = ce('button', 'btn btn--ghost btn--full', '🛵 ' + L.t('assign_driver') + (CUR.driverId ? ' ✓' : ''));
    drv.style.minHeight = '44px';
    drv.onclick = () => pickDriver();
    host.appendChild(drv);
  }
  const cust = ce('input'); cust.placeholder = L.t('link_customer'); cust.value = CUR.customerId || CUR.customerName || '';
  cust.onchange = async () => { CUR.customerName = cust.value.trim(); CUR.customerId = cust.value.trim() || null; await persist(); };
  host.appendChild(wrapField(L.t('customer'), cust));
  const ref = ce('input'); ref.placeholder = L.t('reference'); ref.value = CUR.refNo || '';
  ref.onchange = async () => { CUR.refNo = ref.value.trim(); await persist(); };
  host.appendChild(wrapField(L.t('reference'), ref));
}
function wrapField(label, el) {
  const w = ce('div'); w.appendChild(ce('label', 'small muted', label)); w.firstChild.style.cssText = 'font-weight:700;margin-bottom:4px;display:block';
  el.style.width = '100%'; w.appendChild(el); return w;
}
function renderLines() {
  const host = $('tkt-lines'); host.innerHTML = '';
  if (!(CUR.lines || []).length) { host.appendChild(ce('p', 'muted small', L.t('empty') + ' — pick items below')); return; }
  for (const l of CUR.lines) {
    const each = C.linePriceCents(l);
    const el = ce('div', 'lrow');
    el.innerHTML = '<div class="hd grow"><b>' + esc(l.name) + (l.mods && l.mods.length ? ' <small class="muted">+ ' + l.mods.length + ' mod(s)</small>' : '') + '</b><small>' + money(each) + ' each' + (l.notes ? ' · ' + esc(l.notes) : '') + '</small></div>'
      + '<span class="qtyctl"><button type="button" data-q="-1">−</button><b>' + l.qty + '</b><button type="button" data-q="1">+</button></span>'
      + '<span class="lrow__amt">' + money(each * l.qty) + '</span>'
      + '<button class="iconbtn" type="button" data-note="1" title="Notes / options">✎</button>';
    el.querySelectorAll('[data-q]').forEach(b => b.onclick = async () => {
      l.qty = Math.max(0, (l.qty || 1) + Number(b.dataset.q));
      if (!l.qty) CUR.lines = CUR.lines.filter(x => x !== l);
      await persist(); renderTicket();
    });
    el.querySelector('[data-note]').onclick = () => lineOpts(l);
    host.appendChild(el);
  }
}
async function renderMenuPick() {
  const ps = await idbGetAll('products', []);
  const cats = [...new Set(ps.map(p => p.categoryId || p.cat || 'Items'))];
  const catsHost = $('tkt-cats'); catsHost.innerHTML = '';
  const all = ce('button', 'fchip' + (T_CAT === 'all' ? ' is-on' : ''), 'All'); all.onclick = () => { T_CAT = 'all'; renderMenuPick(); }; catsHost.appendChild(all);
  for (const c of cats) { const b = ce('button', 'fchip' + (T_CAT === c ? ' is-on' : ''), c); b.onclick = () => { T_CAT = c; renderMenuPick(); }; catsHost.appendChild(b); }
  const grid = $('tkt-mgrid'); grid.innerHTML = '';
  for (const p of ps.filter(p => (T_CAT === 'all' || (p.categoryId || p.cat || 'Items') === T_CAT))) {
    const off = p.available === false || p.avail === false;
    const card = ce('div', 'mcard' + (off ? ' mcard--off' : ''));
    card.innerHTML = '<div class="mcard__img">' + (p.imageBase64 ? '<img src="' + p.imageBase64 + '" alt=""/>' : '🍽️') + '</div>'
      + '<div class="mcard__body"><span class="mcard__name">' + esc(p.name) + '</span>'
      + '<span class="chip chip--small ' + (off ? 'tag--danger' : '') + '">' + (off ? L.t('sold_out_word') : money(p.priceCents != null ? p.priceCents : C.cents(p.price))) + '</span>'
      + (off ? '' : '<button class="mcard__add" type="button">' + L.t('add') + '</button>') + '</div>';
    const btn = card.querySelector('button');
    if (btn) btn.onclick = (e) => { e.stopPropagation(); addProduct(p); };
    if (!off) card.onclick = () => addProduct(p);
    grid.appendChild(card);
  }
}
async function addProduct(p) {
  const priceC = p.priceCents != null ? p.priceCents : C.cents(p.price);
  const exist = CUR.lines.find(l => l.productId === p.id && !(l.mods || []).length && !l.notes);
  if (exist) exist.qty++;
  else CUR.lines.push({ id: C.uuid(), productId: p.id, name: p.name, qty: 1, priceCents: priceC, mods: [], notes: '' });
  await persist(); renderLines(); renderTotals();
}
function renderTotals() {
  const b = bill();
  const host = $('tkt-totals'); host.innerHTML = '';
  const line = (k, v, strong) => host.appendChild(ce('div', 'tot' + (strong ? ' tot--strong' : ''), '<span>' + k + '</span><span>' + v + '</span>'));
  line(L.t('subtotal'), money(b.subTotal));
  if (b.discount) line(L.t('bill_discount'), '−' + money(b.discount));
  if (b.service) line(L.t('bill_service'), '+' + money(b.service));
  for (const t of b.taxes) line(t[0], '+' + money(t[1]));
  const payBtn = document.querySelector('[data-act="ticket.pay"]');
  if (payBtn) payBtn.textContent = L.t('pay') + ' · ' + money(b.due);
}
async function persist() { await idbPut('orders', CUR); await kvSet('rev', Date.now()); if (window.OFSyncNow) OFSyncNow(); }

/* ================= LINE OPTIONS (notes + modifiers) ================= */
async function lineOpts(l) {
  const p = l.productId ? await idbGet('products', l.productId, null) : null;
  const body = ce('div', 'grid');
  body.innerHTML = '<input id="lo-notes" placeholder="' + 'Kitchen note: less sugar, no ice…' + '" value="' + esc(l.notes || '') + '"/>';
  if (p && (p.mods || []).length) {
    body.appendChild(ce('div', 'sect__t', L.t('options')));
    for (const mn of p.mods) {
      const on = (l.mods || []).includes(mn);
      const b = ce('button', 'btn btn--ghost' + (on ? ' btn--mint' : ''), (on ? '✓ ' : '＋ ') + mn);
      b.style.minHeight = '44px';
      b.onclick = () => { l.mods = l.mods || []; const i = l.mods.indexOf(mn); if (i >= 0) l.mods.splice(i, 1); else l.mods.push(mn); redraw(); };
      body.appendChild(b);
    }
  }
  OFDialog({ title: l.name });
  $('dlg-body').innerHTML = ''; $('dlg-body').appendChild(body);
  $('dlg-btns').innerHTML = '';
  const del = ce('button', 'btn btn--danger', L.t('delete')); del.onclick = async () => { CUR.lines = CUR.lines.filter(x => x !== l); await persist(); OFCloseDlg(); renderTicket(); };
  const save = ce('button', 'btn btn--mint', L.t('save')); save.onclick = async () => { l.notes = $('lo-notes').value.trim(); await persist(); OFCloseDlg(); renderTicket(); };
  $('dlg-btns').appendChild(del); $('dlg-btns').appendChild(save);
  function redraw() { OFCloseDlg(); lineOpts(l); }
}
async function pickDriver() {
  const ds = (await idbGetAll('drivers', [])).filter(d => d.status !== 'offline');
  if (!ds.length) { OFActToast('Add drivers first in More → Drivers'); return; }
  const rows = ds.map(d => ({ label: (d.name || 'Driver') + ' — ' + d.status, act: async () => { CUR.driverId = d.id; CUR.driverName = d.name; await persist(); renderTicket(); } }));
  OFPick(L.t('assign_driver'), '', rows.concat([{ label: L.t('cancel'), kind: 'ghost' }]));
}
function OFActToast(m, s) { const t = window.__toastFn; t && t(m, s); }

/* ================= OPERATIONS SHEET (⋯ button) ================= */
function ticketOps() {
  const can = k => C.allowsFeature(SHOP_SAFE().entitlements, k);
  const acts = [];
  if (['open', 'sent'].includes(CUR.status)) acts.push({ label: '📥 ' + L.t('hold'), act: async () => { CUR.held = true; await persist(); toast2('Held — recall from the register', ''); exitTicket(); } });
  acts.push({ label: '🖨️ ' + L.t('print_bill'), act: async () => { window.OFPrintReceipt && OFPrintReceipt(CUR, { bill: true }); } });
  acts.push({ label: '🔃 ' + L.t('move_table'), act: () => moveTable() });
  acts.push({ label: '🔗 ' + L.t('merge_table'), act: () => mergeTable() });
  acts.push({ label: '✂️ ' + L.t('split_bill') + ' (' + L.t('split_even') + ')', act: () => splitEven() });
  acts.push({ label: '％ ' + L.t('bill_discount'), act: () => editDiscount() });
  acts.push({ label: '🛎 ' + L.t('bill_service') + ' / ' + L.t('tax_word'), act: () => editRates() });
  if (CUR.status !== 'sent') acts.push({ label: '🍳 ' + L.t('send_kitchen'), act: () => sendKitchen() });
  acts.push({ label: '✅ ' + L.t('mark_served'), act: async () => { CUR.status = 'served'; await persist(); renderTicket(); } });
  if (can('loyalty')) acts.push({ label: '🏆 ' + L.t('loyalty'), act: () => earnPoints() });
  acts.push({ label: '📺 ' + L.t('customer_display'), act: () => openCustomerDisplay() });
  acts.push({ label: '📤 ' + L.t('share_receipt'), act: () => shareReceipt() });
  if (CUR.payment && can('refunds')) acts.push({ label: '↩️ ' + L.t('refund'), act: () => refundFlow() });
  acts.push({ label: '🗑 ' + L.t('cancelled'), kind: 'danger', act: () => cancelTicket() });
  OFPick(L.t('order') + ' #' + (CUR.ticketNo || ''), 'Every action syncs to all devices', acts);
}
function toast2(m, s) { const t = window.__toastFn; t && t(m, s); }
function exitTicket() { OFAct['ticket.back'](); }
async function sendKitchen() {
  CUR.status = 'sent'; CUR.sentAt = Date.now();
  await persist();
  if ((SHOP_SAFE().profile.fireMode || 'auto') === 'auto' && window.OFPrintReceipt && (C.allowsFeature(SHOP_SAFE().entitlements, 'station_printers') || true)) {
    if (SHOP_SAFE().profile.autoPrint !== false) OFPrintReceipt(CUR, { type: 'kitchen' });
  }
  toast2('Sent to kitchen', 'The slip prints and the board lights up');
  renderTicket();
}
async function moveTable() {
  const ts = await idbGetAll('tables', []);
  OFPick(L.t('move_table'), 'Everything moves to the new table', ts.map(t => ({ label: (t.label || t.name), act: async () => { CUR.tableId = t.id; CUR.tableName = t.label || t.name; await persist(); renderTicket(); } })).concat([{ label: L.t('cancel'), kind: 'ghost' }]));
}
async function mergeTable() {
  const ts = await idbGetAll('tables', []);
  const os = (await idbGetAll('orders', [])).filter(o => o.tableId && o.id !== CUR.id && !['paid', 'cancelled', 'refunded'].includes(o.status));
  const opts = os.map(o => ({ label: (o.tableName ? 'Table ' + o.tableName : 'Ticket #' + o.ticketNo) + ' · ' + (o.lines || []).length + ' item(s)', act: async () => {
    CUR.lines.push(...(o.lines || [])); CUR.tableId = o.tableId; CUR.tableName = o.tableName;
    o.status = 'cancelled'; await idbPut('orders', o); await persist(); renderTicket();
  } }));
  OFPick(L.t('merge_table'), 'Bill joins another table (old one cancels)', opts.length ? opts.concat([{ label: L.t('cancel'), kind: 'ghost' }]) : [{ label: 'No other open tables', kind: 'ghost' }]);
}
async function splitEven() {
  const b = bill(); const linesN = (CUR.lines || []).reduce((a, l) => a + l.qty, 0);
  const body = ce('div', 'grid');
  const maxParts = Math.max(2, Math.min(6, linesN));
  body.innerHTML = '<label for="sp-n" class="small muted" style="font-weight:700">' + L.t('split_even') + ' — ' + money(b.due) + '</label><div class="typechips" id="sp-chips"></div><div class="tot tot--strong" id="sp-result"></div><p class="small muted" id="sp-note" style="font-weight:600"></p>';
  OFDialog({ title: L.t('split_bill') }); $('dlg-body').innerHTML = ''; $('dlg-body').appendChild(body); $('dlg-btns').innerHTML = '';
  const chips = body.querySelector('#sp-chips'); let n = 2;
  const draw = () => {
    chips.innerHTML = '';
    for (let i = 2; i <= maxParts; i++) { const c = ce('button', 'tchip' + (i === n ? ' is-on' : ''), '÷' + i); c.onclick = () => { n = i; draw(); }; chips.appendChild(c); }
    $('sp-result').innerHTML = '<span>Each pays</span><span>' + money(Math.ceil(b.due / n)) + '</span>';
    $('sp-note').textContent = 'Last guest covers rounding; nothing is lost or overcharged (cents math).';
  };
  draw();
  const ok = ce('button', 'btn btn--mint', L.t('done')); $('dlg-btns').appendChild(ok);
  ok.onclick = async () => { CUR.splitAmount = Math.ceil(b.due / n); CUR.splitParts = n; await persist(); OFCloseDlg(); toast2('Split ×' + n + ' noted on the bill', 'Pay screen shows the per-person amount'); renderTicket(); };
}
function editDiscount() {
  OFDialog({ title: L.t('bill_discount') });
  $('dlg-body').innerHTML = '<div class="priceedit"><input id="ed-val" type="number" inputmode="decimal" value="' + (CUR.discountPct || '') + '" placeholder="' + L.t('percent') + '"/><button class="btn btn--sm" id="ed-pct">%</button><button class="btn btn--sm" id="ed-amt">Amount</button></div><div class="tot tot--strong" id="ed-res"></div>';
  let pct = true;
  const up = () => { const v = Number($('ed-val').value) || 0; const b = bill(); const amt = pct ? Math.round(b.total * v / 100) : C.cents(v); $('ed-res').innerHTML = '<span>Saving</span><span>' + money(amt) + '</span>'; };
  $('ed-pct').onclick = () => { pct = true; up(); }; $('ed-amt').onclick = () => { pct = false; up(); };
  $('ed-val').oninput = up; up();
  $('dlg-btns').innerHTML = '';
  const zero = ce('button', 'btn btn--ghost', 'Remove'); zero.onclick = async () => { CUR.discountPct = 0; CUR.discountCents = 0; await persist(); OFCloseDlg(); renderTicket(); };
  const save = ce('button', 'btn btn--mint', L.t('done')); save.onclick = async () => {
    const v = Number($('ed-val').value) || 0; const b = bill();
    if (pct) { CUR.discountPct = Math.min(100, Math.max(0, v)); CUR.discountCents = null; }
    else { CUR.discountPct = null; CUR.discountCents = Math.min(b.subTotal, Math.max(0, C.cents(v))); }
    await persist(); OFCloseDlg(); renderTicket();
  };
  $('dlg-btns').appendChild(zero); $('dlg-btns').appendChild(save);
}
function editRates() {
  OFDialog({ title: L.t('bill_service') + ' & ' + L.t('tax_word') });
  $('dlg-body').innerHTML = '<div class="priceedit"><input id="er-svc" type="number" inputmode="decimal" value="' + (CUR.serviceRate != null ? CUR.serviceRate : SHOP_SAFE().profile.svc) + '"/><span class="small muted" style="font-weight:700">' + L.t('bill_service') + ' %</span></div>'
    + '<div class="priceedit"><input id="er-tax" type="number" inputmode="decimal" value="' + (CUR.taxRate != null ? CUR.taxRate : SHOP_SAFE().profile.tax) + '"/><span class="small muted" style="font-weight:700">' + L.t('tax_word') + ' %</span></div>';
  $('dlg-btns').innerHTML = '';
  const save = ce('button', 'btn btn--mint', L.t('done')); save.onclick = async () => { CUR.serviceRate = Number($('er-svc').value) || 0; CUR.taxRate = Number($('er-tax').value) || 0; await persist(); OFCloseDlg(); renderTicket(); };
  $('dlg-btns').appendChild(save);
}
function cancelTicket() {
  OFDialog({ title: 'Cancel ticket #' + (CUR.ticketNo || '') + '?' });
  $('dlg-body').innerHTML = '<p class="muted small" style="font-weight:600">' + L.t('sure') + ' It cannot be reopened. Stock returns, points reverse.</p>';
  $('dlg-btns').innerHTML = '';
  const no = ce('button', 'btn btn--ghost', 'Keep it'); no.onclick = () => OFCloseDlg();
  const yes = ce('button', 'btn btn--danger', 'Cancel ticket'); yes.onclick = async () => {
    CUR.status = 'cancelled'; await freeTable(); await persist(); OFCloseDlg(); exitTicket(); toast2('Ticket cancelled', 'It shows in reports as cancelled');
  };
  $('dlg-btns').appendChild(no); $('dlg-btns').appendChild(yes);
}
async function freeTable() {
  if (!CUR.tableId) return;
  const all = await idbGetAll('orders', []);
  const otherOpen = all.some(o => o.id !== CUR.id && o.tableId === CUR.tableId && !['paid', 'cancelled', 'refunded'].includes(o.status));
  if (otherOpen) return;
  const t = await idbGet('tables', CUR.tableId, null);
  if (t) { t.state = 'free'; t.since = null; t.busySince = null; await idbPut('tables', t); }
}
function earnPoints() { toast2('Points apply at payment', 'Pick the customer first, then pay — points land automatically'); }
function openCustomerDisplay() {
  const b = bill();
  $('cdisp-shop').textContent = SHOP_SAFE().profile.name;
  $('cdisp-amt').textContent = money(b.due);
  $('cdisp-name').textContent = CUR.customerId ? 'Thanks, ' + (CUR.customerName || CUR.customerId) : 'Thanks for coming';
  ['view-main', 'view-rolehome', 'view-ticket', 'view-sub', 'view-license', 'view-locked', 'view-connect', 'view-role', 'view-setup'].forEach(v => $(v).hidden = true);
  $('view-display').hidden = false;
}
async function shareReceipt() {
  const txt = (window.OFReceiptText ? OFReceiptText(CUR) : '') || receiptTextFallback();
  const data = { title: SHOP_SAFE().profile.name + ' — receipt', text: txt };
  if (navigator.share) { try { await navigator.share(data); } catch {} }
  else if (navigator.clipboard) { await navigator.clipboard.writeText(txt); toast2('Receipt copied', ''); }
}
function receiptTextFallback() {
  const b = bill(); const cur = SHOP_SAFE().profile.currency || 'RM';
  const lines = [SHOP_SAFE().profile.name, 'Ticket #' + (CUR.ticketNo || ''), '----------------------------'];
  for (const l of CUR.lines) lines.push((l.qty + ' × ' + l.name).slice(0, 26).padEnd(26) + ' ' + ((C.linePriceCents(l) * l.qty) / 100).toFixed(2));
  lines.push('----------------------------', L.t('total') + '  ' + cur + ' ' + (b.total / 100).toFixed(2), L.t('receipt_footer'));
  return lines.join('\n');
}

/* ================= REFUNDS ================= */
async function refundFlow() {
  const plan = C.refundPlan(CUR, (await idbGetAll('products', [])));
  const body = ce('div', 'grid');
  body.innerHTML = '<p class="muted small" style="font-weight:600">' + L.t('undo_pay') + ' Stock may go back; everything reprints.</p>';
  for (const l of plan.linesRefund) {
    const row = ce('div', 'lrow');
    row.innerHTML = '<div class="hd grow"><b>' + esc(l.name) + '</b></div><span class="qtyctl"><button type="button" data-d="-1">−</button><b data-cur>' + l.qty + '</b><button type="button" data-d="1">+</button></span>';
    const cur = { qty: l.qty, max: l.qty };
    row.querySelectorAll('button').forEach(b => b.onclick = () => { cur.qty = Math.max(0, Math.min(cur.max, cur.qty + Number(b.dataset.d))); row.querySelector('[data-cur]').textContent = cur.qty; l.qty = cur.qty; });
    body.appendChild(row);
  }
  const restock = ce('label', 'switch', '<span>' + L.t('restock') + '</span><input type="checkbox" id="rf-restock" checked/>');
  body.appendChild(restock);
  OFDialog({ title: L.t('refund') + ' — ' + money(plan.amount) }); $('dlg-body').innerHTML = ''; $('dlg-body').appendChild(body); $('dlg-btns').innerHTML = '';
  const ok = ce('button', 'btn btn--danger', L.t('refund') + ' ' + money(plan.linesRefund.reduce((a, l) => a + (l.priceCents || 0) * (l.qty || 0), 0)));
  ok.onclick = async () => {
    const entry = { id: C.uuid(), orderId: CUR.id, at: Date.now(), lines: JSON.parse(JSON.stringify(plan.linesRefund)), amountCents: plan.linesRefund.reduce((a, l) => a + (l.priceCents || 0) * (l.qty || 0), 0), restock: !!$('rf-restock').checked, by: ROLE_LABEL() };
    await idbPut('refunds', entry);
    if (entry.restock) for (const l of plan.linesRefund) if (l.productId) {
      const p = await idbGet('products', l.productId, null);
      if (p && (p.inventoryId || p.stockId)) { const s = await idbGet('stock', p.inventoryId || p.stockId, null); if (s) { s.qty += (l.qty || 0) * (p.deductQty || 1); await idbPut('stock', s); } }
    }
    const remaining = (CUR.lines || []).map(l => { const r = plan.linesRefund.find(x => x.productId === l.productId); return r ? { ...l, qty: Math.max(0, l.qty - r.qty) } : l; }).filter(l => l.qty > 0);
    CUR.lines = remaining;
    if (!remaining.length) { CUR.status = 'refunded'; await freeTable(); }
    await persist(); OFCloseDlg(); toast2('Refunded ✓', entry.restock ? 'Stock went back' : 'Ledger-only refund');
    if (window.OFPrintReceipt) OFPrintReceipt({ ...CUR, refundOf: plan.linesRefund }, { type: 'refund' });
    if (remaining.length) renderTicket(); else exitTicket();
  };
  const cancel = ce('button', 'btn btn--ghost', L.t('cancel')); cancel.onclick = () => OFCloseDlg();
  $('dlg-btns').appendChild(cancel); $('dlg-btns').appendChild(ok);
}
function ROLE_LABEL() { return 'main'; }

/* ================= PAY SHEET ================= */
const PAY = { method: 'cash', method2: null, split: false, splitCents: 0, tender: '' };
const METHODS = ['cash', 'card', 'wallet', 'other', 'complimentary'];
function openPay() {
  if (!CUR || !(CUR.lines || []).length) { toast2('Add items first', ''); return; }
  PAY.method = 'cash'; PAY.method2 = null; PAY.split = false; PAY.splitCents = 0; PAY.tender = '';
  $('pay-split-on').checked = false; $('pay-split-box').hidden = true; $('pay-tip').value = '';
  drawPayBreakdown(); drawMethods(); drawNumpad(); drawTender();
  $('sheet-pay').classList.add('is-open'); $('sheet-pay').setAttribute('aria-hidden', 'false');
}
function closePay() { $('sheet-pay').classList.remove('is-open'); $('sheet-pay').setAttribute('aria-hidden', 'true'); }
function drawPayBreakdown() {
  const b = bill();
  const el = $('pay-breakdown'); el.innerHTML = '';
  const totLine = (k, v, minus) => { const d = ce('div', 'tot', '<span>' + k + '</span><span>' + (minus ? '−' : '') + v + '</span>'); el.appendChild(d); };
  totLine(L.t('subtotal'), money(b.subTotal));
  if (b.discount) totLine(L.t('bill_discount'), money(b.discount), true);
  if (b.service) totLine(L.t('bill_service'), money(b.service));
  for (const t of b.taxes) totLine(t[0], money(t[1]));
  const due = ce('div', 'tot tot--strong', '<span>' + L.t('total') + '</span><span>' + money(b.due) + '</span>'); el.appendChild(due);
}
function drawMethods() {
  const names = { cash: L.t('cash'), card: L.t('card'), wallet: L.t('wallet'), other: L.t('other'), complimentary: L.t('complimentary') };
  const host = $('pay-methods'); host.innerHTML = '';
  for (const m of METHODS) { const b = ce('button', 'pay-chip' + (PAY.method === m ? ' is-on' : ''), names[m]); b.onclick = () => { PAY.method = m; drawMethods(); drawNumpad(); drawTender(); }; host.appendChild(b); }
  const host2 = $('pay-methods2'); host2.innerHTML = '';
  for (const m of METHODS) { if (m === PAY.method) continue; const b = ce('button', 'pay-chip' + (PAY.method2 === m ? ' is-on' : ''), names[m]); b.onclick = () => { PAY.method2 = m; drawMethods(); }; host2.appendChild(b); }
}
function drawNumpad() {
  const host = $('pay-pad'); host.innerHTML = '';
  const b = bill();
  const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '⌫', '0', '00'];
  for (const k of keys) {
    const bt = ce('button', '', k); bt.type = 'button';
    bt.onclick = () => { tenderPress(k); };
    host.appendChild(bt);
  }
  if (PAY.method === 'cash' || PAY.split) {
    const ex = ce('button', '', L.t('exact'));
    ex.className = 'exact';
    ex.style.cssText = 'font-weight:800;font-size:13px;border-radius:12px;border:0;min-height:52px;background:rgba(228,191,86,.25);color:var(--warn);cursor:pointer;font-family:inherit';
    ex.onclick = () => { const t = cashTarget(); PAY.tender = String(t); drawTender(); };
    host.appendChild(ex);
  }
}
function tenderPress(k) {
  if (k === '⌫') PAY.tender = PAY.tender.slice(0, -1);
  else if (PAY.tender.replace('.', '').length < 9) PAY.tender += k;
  drawTender();
}
function cashTarget() {
  const b = bill(); const tipC = C.cents(Number($('pay-tip').value) || 0);
  const check = C.payCheck(b.due, { method: PAY.method, tipCents: tipC, split: PAY.split && PAY.method2 ? { method2: PAY.method2, amountCents: PAY.splitCents || Math.floor((b.due + tipC) / 2) } : null });
  return PAY.method === 'cash' ? check.cashTarget : check.tenderDue;
}
function drawTender() {
  const b = bill(); const tipC = C.cents(Number($('pay-tip').value) || 0);
  const splitAmt = PAY.split ? C.cents(Number($('pay-split-amount').value) || 0) || Math.floor((b.due + tipC) / 2) : 0;
  PAY.splitCents = splitAmt;
  const tenderC = PAY.tender ? C.cents(Number(PAY.tender)) : 0;
  const check = C.payCheck(b.due, { tenderCents: tenderC, method: PAY.method, tipCents: tipC, split: PAY.split ? { method2: PAY.method2 || 'cash', amountCents: splitAmt } : null });
  $('pay-tender').textContent = PAY.tender ? money(tenderC) : money(0);
  const el = $('pay-change'); el.className = 'pay-change'; el.innerHTML = '';
  const confirm = $('pay-confirm');
  if (PAY.method === 'complimentary') { el.textContent = L.t('complimentary') + ' — no money changes hands'; confirm.disabled = false; confirm.textContent = L.t('confirm') + ' · ' + L.t('complimentary'); return; }
  if (check.need > 0) {
    el.classList.add('is-short');
    el.textContent = L.t('short_by') + ' ' + money(check.need) + (check.cashTarget !== check.tenderDue ? ' (cash part ' + money(check.cashTarget) + ')' : '');
    confirm.disabled = true;
    confirm.textContent = L.t('confirm') + ' · ' + money(check.tenderDue + (PAY.method === 'cash' ? 0 : 0));
  } else {
    el.textContent = L.t('change') + ' ' + money(check.change) + (PAY.split ? ' · second ' + money(splitAmt) : '');
    confirm.disabled = false;
    confirm.textContent = L.t('confirm') + ' · ' + money(b.due + tipC);
  }
}
async function confirmPay() {
  const b = bill(); const tipC = C.cents(Number($('pay-tip').value) || 0);
  const splitAmt = PAY.split ? C.cents(Number($('pay-split-amount').value) || 0) || Math.floor((b.due + tipC) / 2) : 0;
  const tenderC = PAY.tender ? C.cents(Number(PAY.tender)) : 0;
  const check = C.payCheck(b.due, { tenderCents: tenderC, method: PAY.method, tipCents: tipC, split: PAY.split ? { method2: PAY.method2 || 'cash', amountCents: splitAmt } : null });
  if (PAY.method !== 'complimentary' && check.need > 0) return;
  CUR.tipCents = tipC; CUR.tip = tipC / 100;
  CUR.payment = { method: PAY.method, paidTenderCents: tenderC, changeCents: check.change, at: Date.now(), tipCents: tipC };
  CUR.tenderCents = tenderC; CUR.changeCents = check.change;
  if (PAY.split) CUR.splitPayment = { method1: PAY.method, method2: PAY.method2 || 'cash', amount1Cents: check.tenderDue - splitAmt, amount2Cents: splitAmt };
  CUR.status = 'paid'; CUR.paidAt = Date.now();
  if (PAY.method === 'cash' && !SHOP_SAFE().profile.drawerNoteShown) { SHOP_SAFE().profile.drawerNoteShown = true; setTimeout(() => toast2('No cash drawer on the web POS', 'Asking staff to put the tendered cash in the drawer'), 700); }
  // stock deduct (linked items)
  for (const l of CUR.lines) if (l.productId) {
    const p = await idbGet('products', l.productId, null);
    if (p && (p.inventoryId || p.stockId)) { const s = await idbGet('stock', p.inventoryId || p.stockId, null); if (s) { s.qty -= (l.qty || 0) * (p.deductQty || 1); await idbPut('stock', s); } }
    if (p && (p.recipe || []).length) for (const r of p.recipe) { const s = await idbGet('stock', r.stockId, null); if (s) { s.qty -= (r.qty || 0) * (l.qty || 1); await idbPut('stock', s); } }
  }
  await freeTable(); await persist();
  // loyalty points
  if (C.allowsFeature(SHOP_SAFE().entitlements, 'loyalty') && CUR.customerId) { const cst = await idbGet('customers', CUR.customerId, null); if (cst) { cst.points = (cst.points || 0) + Math.floor(b.due / 100); await idbPut('customers', cst); } }
  // print in the same tap — synchronously, so iOS honours it
  if (window.OFPrintReceipt) OFPrintReceipt(CUR, { type: 'receipt' });
  chimePaid();
  closePay();
  toast2(L.t('paid') + ' ✓', L.t('change') + ' ' + money(check.change) + ' — table freed');
  exitTicket();
}
function chimePaid() { const f = window.__chimeFn; f && f('paid'); }

Object.assign(A, {
  'ticket.pay': () => openPay(),
  'ticket.send': () => sendKitchen(),
  'ticket.ops': () => ticketOps(),
  'pay.close': () => closePay(),
  'pay.confirm': () => { confirmPay(); },
});
$('pay-split-on')?.addEventListener('change', (e) => { PAY.split = e.target.checked; $('pay-split-box').hidden = !PAY.split; drawMethods(); drawNumpad(); drawTender(); });
$('pay-split-amount')?.addEventListener('input', drawTender);
$('pay-tip')?.addEventListener('input', drawTender);
})();
