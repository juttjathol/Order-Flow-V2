/* ============================================================
   ORDER FLOW POS — more.js
   More tab, section-for-section with more_screen.dart.
   Every row opens a working sub-screen; plan-locked rows get
   the lock treatment (models_plans.dart catalog + heal rules).
   ============================================================ */
(function () {
'use strict';
const C = OFCore, L = OFLang, A = window.OFAct;
const $ = id => document.getElementById(id);
const ce = (t, c, h) => { const e = document.createElement(t); if (c) e.className = c; if (h != null) e.innerHTML = h; return e; };
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const shop = () => window.SHOP_REF();
const money = c => OFMoney(c);
const canF = k => C.allowsFeature(shop().entitlements, k);
const toast = (m, s) => window.__toastFn && window.__toastFn(m, s);

/* ================ SUB-SCREEN HOST ================ */
window.OFShowSub = function (title, sub, draw) {
  $('sub-title').textContent = title;
  $('sub-sub').textContent = sub || '';
  const body = $('sub-body'); body.innerHTML = '';
  const views = ['view-license', 'view-locked', 'view-connect', 'view-role', 'view-setup', 'view-main', 'view-rolehome', 'view-ticket', 'view-display'];
  views.forEach(v => $(v).hidden = true);
  $('view-sub').hidden = false;
  window.scrollTo(0, 0);
  Promise.resolve(draw(body)).catch(e => { console.error(e); body.appendChild(ce('p', 'muted small', String(e && e.message || e))); });
};

/* ================ MORE TAB RENDER ================ */
window.OFMoreRender = async function () {
  const host = $('tab-more'); if (!host) return;
  host.innerHTML = '';
  const p = shop().profile;
  const headCard = ce('div', 'card card--forest', '');
  headCard.style.cssText = 'padding:16px';
  headCard.innerHTML = '<div class="row"><div class="grow"><div style="font-weight:900;font-size:17px;letter-spacing:-.3px">' + esc(p.name) + '</div><div class="small" style="opacity:.8;font-weight:600;margin-top:2px">' + esc(p.address || 'Add your address in Bill profile') + '</div></div><span class="chip">' + C.FEATURE_CATALOG.length + ' features</span></div>';
  host.appendChild(headCard);

  const section = (t) => { const el = ce('div', 'sect'); el.appendChild(ce('div', 'sect__t', t)); host.appendChild(el); return host; };
  const mrow = (ic, title, subTxt, act, locked) => {
    const el = ce('button', 'mrow'); el.type = 'button';
    el.innerHTML = '<span class="lrow__ic">' + ic + '</span><span class="ttl">' + esc(title) + '<span class="sub">' + esc(subTxt || '') + '</span></span>' + (locked ? '<span class="lock">🔒</span>' : '') + '<span class="go">›</span>';
    el.onclick = () => { if (locked) return toast(L.t('locked_row'), 'Not in your plan — tap “Refresh my plan” after upgrading'); A[act] && A[act](); };
    const wrap = ce('div', 'tilewrap'); wrap.appendChild(el); host.appendChild(wrap);
  };

  section(L.t('config_head'));
  mrow('🧾', L.t('bill_profile'), 'Name, phone, address, receipt header/footer, currency, payment QR', 'more.bill');
  mrow('🖨️', L.t('printers'), 'Paper, copies, auto print, kitchen slips, Apple print, gateway', 'more.printers');
  mrow('👥', L.t('staff'), 'PINs, roles, shifts, 5-strike lock', 'more.staff');
  mrow('🏆', L.t('customers') + ' & ' + L.t('loyalty'), 'Points, visits, top customers', 'more.customers', !canF('loyalty'));
  mrow('🛵', L.t('drivers'), 'Delivery team, free/busy/offline', 'more.drivers');

  section(L.t('reports'));
  mrow('📊', L.t('x_report'), "Whole day's picture, totals & mix", 'more.xreport');
  mrow('🔐', L.t('z_report'), 'Close till — snapshot and reset day', 'more.zreport');
  mrow('📈', L.t('insights'), 'Top sellers, stock to watch, staff & shifts', 'more.insights');
  mrow('🧾 ' + '⏳', L.t('unpaid_bills'), 'Every open ticket with its money', 'more.unpaid');
  mrow('🚫', L.t('sold_out_word'), 'Off the menu right now', 'more.soldout');
  mrow('↩️', L.t('refunds'), 'Stock returns, ledger notes, reprints', 'more.refunds', !canF('refunds'));
  mrow('📣', L.t('third_party'), 'GrabFood / Foodpanda day totals + report split', 'more.thirdparty', !canF('third_party'));

  section(L.t('extras_head'));
  mrow('🧑‍🤝‍🧑', L.t('multi_terminal'), 'Stations join by QR — no key needed', 'more.cloud', !canF('multi_terminal'));
  mrow('📡', L.t('cloud_sync'), 'E2E-encrypted room relay for every device', 'more.cloud', !canF('cloud_sync'));
  mrow('🧍', L.t('qr_ordering'), 'Guests order from their table', 'more.qr', !canF('qr_ordering'));
  mrow('🎨', L.t('guest_branding'), 'Guest page name, cover, hours, accent', 'more.branding', !canF('qr_branding'));
  mrow('💸', L.t('split_payment'), 'Two methods on one bill — on the pay sheet', 'more.splitinfo');
  mrow('📺', L.t('customer_display'), 'Giant total for the guest, from any ticket', 'more.custdisp');
  mrow('📅', L.t('reservations'), 'Tables or appointment slots', 'more.reservations', !canF('reservations'));
  mrow('🧂', L.t('recipe_costing'), 'Ingredients → cost, price, margin', 'more.recipes', !canF('recipes'));
  mrow('🗑️', L.t('wastage'), 'Spilled, expired, broken — keeps stock honest', 'more.wastage', !canF('wastage'));
  mrow('🚚', L.t('suppliers') + ' & ' + L.t('purchases'), 'Buy, receive, stock rises', 'more.suppliers', !canF('suppliers'));
  mrow('🖨️', L.t('station_printers'), 'Print-gateway device for the whole room', 'more.printers', !canF('station_printers'));

  section(L.t('tools_head'));
  mrow('💾', L.t('backup_title'), 'Export / import — works with the APK backup too', 'more.backup');
  mrow('🌐', L.t('language'), 'English / اردو — RTL for Urdu', 'more.language');
  mrow('🌗', L.t('theme'), 'Auto, Light (cream), Dark — phone rules by default', 'more.theme');
  mrow('🔄', L.t('refresh_plan'), 'Sync license & plan from the server', 'more.refresh');
  mrow('📲', L.t('install'), 'Full-screen app icon on your iPhone home', 'more.install');
  mrow('💬', L.t('wa_support'), 'wa.me/Jathol_Jutt — real human help', 'more.whatsapp');
  mrow('🔒', L.t('privacy'), 'Everything lives on your devices; cloud relay sees only encrypted ciphertext', 'more.privacy');
  mrow('ℹ️', 'About', 'Order Flow Web', 'more.about');

  const leave = ce('button', 'btn btn--danger', L.t('leave_shop'));
  leave.style.cssText = 'width:100%;margin:18px 0 40px;border-radius:14px';
  leave.onclick = () => leaveShop();
  host.appendChild(leave);
};
window.OFMoreRefresh = function () { OFMoreRender().catch(() => {}); };

/* ================ ROW SCREENS ================ */
async function leaveShop() {
  OFDialog({ title: L.t('leave_shop') });
  $('dlg-body').innerHTML = '<p class="muted small" style="font-weight:600">' + L.t('leave_body') + ' Your shop data stays safe on this device (orders, menu, stock); next sign-in asks for the key again.</p>';
  $('dlg-btns').innerHTML = '';
  const no = ce('button', 'btn btn--ghost', L.t('cancel')); no.onclick = () => OFCloseDlg();
  const yes = ce('button', 'btn btn--danger', L.t('leave_shop'));
  yes.onclick = async () => { await kvSet('license', null); await kvSet('roomInfo', null); await kvSet('role', null); await kvSet('setupDone', false); await kvSet('stationRole', null); location.reload(); };
  $('dlg-btns').appendChild(no); $('dlg-btns').appendChild(yes);
}

async function scrBill() {
  OFShowSub(L.t('bill_profile'), 'Shown on receipts and the guest page', async (body) => {
    const p = shop().profile;
    body.innerHTML = '';
    const card = ce('div', 'card card--pad grid');
    card.innerHTML =
      fld('shop_name', 'setup-name-m', p.name) + fld('phone', 'shop-phone-m', p.phone, 'tel') + fld('address', 'shop-addr-m', p.address)
      + fld('currency', 'shop-cur-m', p.currency) + fld('receipt_header', 'rcp-head-m', p.receiptHead) + fld('receipt_footer', 'rcp-foot-m', p.receiptFoot)
      + fld('tagline', 'tagl-m', p.tagline) + fld('pay_qr_url', 'payqr-m', p.payQr, 'url', 'QR image URL shown on receipts')
      + '<label class="switch"><span>' + L.t('sales_tax') + ' %</span><input id="tax-m" type="number" inputmode="decimal" value="' + (p.tax || 0) + '" style="width:100px;text-align:right"/></label>'
      + '<label class="switch"><span>' + L.t('service_charge') + ' %</span><input id="svc-m" type="number" inputmode="decimal" value="' + (p.svc || 0) + '" style="width:100px;text-align:right"/></label>';
    const save = ce('button', 'btn btn--mint btn--full', L.t('save'));
    save.style.marginTop = '16px';
    save.onclick = async () => {
      Object.assign(shop().profile, {
        name: $('setup-name-m').value.trim() || p.name, phone: $('shop-phone-m').value, address: $('shop-addr-m').value,
        currency: $('shop-cur-m').value.trim().slice(0, 6) || p.currency, receiptHead: $('rcp-head-m').value, receiptFoot: $('rcp-foot-m').value,
        tagline: $('tagl-m').value, payQr: $('payqr-m').value.trim(),
        tax: Number($('tax-m').value) || 0, svc: Number($('svc-m').value) || 0,
      });
      await kvSet('shop', shop()); await kvSet('rev', Date.now()); OFSyncNow(); toast(L.t('saved') + ' ✓'); OFAct['sub.back']();
    };
    body.appendChild(card); body.appendChild(save);
  });
}
const fld = (label, id, val, mode, ph) => '<div><label class="small muted" style="font-weight:700">' + esc(label) + '</label><input id="' + id + '" value="' + esc(val || '') + '"' + (mode ? ' inputmode="' + mode + '"' : '') + (ph ? ' placeholder="' + esc(ph) + '"' : '') + '/></div>';

async function scrPrinters() {
  OFShowSub(L.t('printers'), 'AirPrint is the iPhone way; Bluetooth shows only on Android Chrome', async (body) => {
    const p = shop().profile;
    const gateway = await kvGet('printGateway', false);
    body.innerHTML = '';
    const card = ce('div', 'card card--pad grid');
    card.innerHTML =
      '<label class="switch"><span>' + L.t('auto_print') + '</span><input type="checkbox" id="pr-auto" ' + (p.autoPrint !== false ? 'checked' : '') + '/></label>'
      + '<label class="switch"><span>' + L.t('fire_mode') + ' — ' + L.t('fire_auto') + '</span><input type="checkbox" id="pr-fire" ' + ((p.fireMode || 'auto') === 'auto' ? 'checked' : '') + '/></label>'
      + '<label class="switch"><span>' + L.t('kitchen_sound') + '</span><input type="checkbox" id="pr-snd" ' + (p.kitchenSound !== false ? 'checked' : '') + '/></label>'
      + '<div class="priceedit"><span class="small muted" style="font-weight:700">' + L.t('copies') + '</span><input id="pr-copies" type="number" min="1" max="3" value="' + (p.copies || 1) + '" style="width:80px;text-align:center"/></div>'
      + '<div class="priceedit"><span class="small muted" style="font-weight:700">Paper</span><select id="pr-paper"><option value="80">80 mm</option><option value="58">58 mm</option></select></div>'
      + '<label class="switch"><span>' + L.t('print_gateway_row') + '</span><input type="checkbox" id="pr-gateway" ' + (gateway ? 'checked' : '') + '/></label>';
    card.querySelector('#pr-paper').value = p.paper || '80';
    body.appendChild(card);
    const row = ce('div', 'grid'); row.style.marginTop = '12px';
    const test = ce('button', 'btn btn--primary btn--full', '🖨️ ' + L.t('print_test'));
    test.onclick = () => { const demo = C.newOrder(p, {}); demo.lines.push({ id: 't1', name: 'Test print', qty: 1, priceCents: 100, mods: [], notes: '' }); OFPrintReceipt({ ...demo, payment: { method: 'cash', paidTenderCents: 100, changeCents: 0, at: Date.now() } }, {}); };
    row.appendChild(test);
    if ('bluetooth' in navigator) {
      const bt = ce('button', 'btn btn--ghost btn--full', '🔵 ' + L.t('print_bt'));
      bt.onclick = () => { const demo = C.newOrder(p, {}); demo.lines.push({ id: 't1', name: 'Test print', qty: 1, priceCents: 100, mods: [], notes: '' }); OFPrintViaBluetooth(demo, {}).catch(e => toast('Bluetooth print failed', String(e && e.message || e))); };
      row.appendChild(bt);
    } else {
      row.appendChild(ce('p', 'muted small', 'No Bluetooth here (that is normal on iPhone) — AirPrint above is your way.'));
    }
    body.appendChild(row);
    const save = ce('button', 'btn btn--mint btn--full', L.t('save')); save.style.marginTop = '14px';
    save.onclick = async () => {
      shop().profile.autoPrint = $('pr-auto').checked;
      shop().profile.fireMode = $('pr-fire').checked ? 'auto' : 'manual';
      shop().profile.kitchenSound = $('pr-snd').checked;
      shop().profile.copies = Math.max(1, Math.min(3, Number($('pr-copies').value) || 1));
      shop().profile.paper = $('pr-paper').value;
      await kvSet('shop', shop()); await kvSet('printGateway', $('pr-gateway').checked);
      await kvSet('rev', Date.now()); OFSyncNow(); toast(L.t('saved') + ' ✓');
    };
    body.appendChild(save);
  });
}

async function scrStaff() {
  OFShowSub(L.t('staff'), 'Add people, set PINs — 5 wrong tries locks 5 minutes', async (body) => {
    body.innerHTML = '';
    const staff = await idbGetAll('staff', []);
    for (const s of staff) {
      const el = ce('div', 'lrow');
      el.innerHTML = '<span class="lrow__ic">👤</span><div class="hd grow"><b>' + esc(s.name) + (s.pinHash ? '' : ' <span class="tag tag--gold">' + L.t('staff_no_pin') + '</span>') + '</b><small>' + esc((s.roles || []).join(' · ') || 'all roles') + '</small></div>'
        + '<button class="btn btn--sm" data-x="pin">' + (s.pinHash ? 'Change PIN' : 'Set PIN') + '</button><button class="btn btn--sm btn--danger" data-x="del">' + L.t('delete') + '</button>';
      el.querySelector('[data-x=pin]').onclick = () => setPinFlow(s);
      el.querySelector('[data-x=del]').onclick = async () => { await idbDel('staff', s.id); await kvSet('rev', Date.now()); OFSyncNow(); scrStaff(); };
      body.appendChild(el);
    }
    if (!staff.length) body.appendChild(ce('p', 'muted small', L.t('empty')));
    const add = ce('button', 'btn btn--primary btn--full', '+ ' + L.t('add_staff'));
    add.style.marginTop = '12px';
    add.onclick = () => {
      OFDialog({ title: L.t('add_staff') });
      $('dlg-body').innerHTML = '<div class="grid"><input id="st-name" placeholder="' + L.t('name_label') + '"/><div class="typechips" id="st-roles"></div><input id="st-pin" type="password" inputmode="numeric" maxlength="6" placeholder="PIN (optional)"/></div>';
      const roles = ['orderTaker', 'kitchen', 'cashier', 'driver', 'stockClerk', 'frontDesk', 'specialist'];
      const picked = new Set();
      const host = $('st-roles');
      for (const r of roles) { const b = ce('button', 'tchip', r); b.onclick = () => { if (picked.has(r)) { picked.delete(r); b.classList.remove('is-on'); } else { picked.add(r); b.classList.add('is-on'); } }; host.appendChild(b); }
      $('dlg-btns').innerHTML = '';
      const ok = ce('button', 'btn btn--mint', L.t('save'));
      ok.onclick = async () => {
        const name = $('st-name').value.trim(); if (!name) return toast('Name?');
        const pin = $('st-pin').value.trim();
        const s = { id: C.uuid(), name, roles: [...picked], pin: pin || '', pinHash: null, salt: null, active: true };
        if (pin) { s.salt = C.uuid().slice(0, 8); s.pinHash = await OFSha256(s.salt + ':' + pin); s.pin = ''; }
        await idbPut('staff', s); await kvSet('rev', Date.now()); OFSyncNow(); OFCloseDlg(); scrStaff();
      };
      $('dlg-btns').appendChild(ok);
    };
    body.appendChild(add);
  });
}
function setPinFlow(s) {
  OFDialog({ title: s.name + ' — PIN' });
  $('dlg-body').innerHTML = '<div class="grid"><input id="sp-pin" type="password" inputmode="numeric" maxlength="6" placeholder="New PIN"/><input id="sp-pin2" type="password" inputmode="numeric" maxlength="6" placeholder="Repeat PIN"/></div>';
  $('dlg-btns').innerHTML = '';
  const clear = ce('button', 'btn btn--ghost', 'Remove PIN'); clear.onclick = async () => { s.pinHash = null; s.salt = null; await idbPut('staff', s); OFSyncNow(); OFCloseDlg(); scrStaff(); };
  const ok = ce('button', 'btn btn--mint', L.t('save'));
  ok.onclick = async () => {
    const a = $('sp-pin').value.trim(), b = $('sp-pin2').value.trim();
    if (a.length < 4) return toast('At least 4 digits');
    if (a !== b) return toast(L.t('pin_mismatch'));
    s.salt = C.uuid().slice(0, 8); s.pinHash = await OFSha256(s.salt + ':' + a);
    await idbPut('staff', s); await kvSet('rev', Date.now()); OFSyncNow(); OFCloseDlg(); toast('PIN set ✓'); scrStaff();
  };
  $('dlg-btns').appendChild(clear); $('dlg-btns').appendChild(ok);
}

async function scrCustomers() {
  OFShowSub(L.t('customers') + ' & ' + L.t('loyalty'), 'Points earn at payment', async (body) => {
    body.innerHTML = '';
    const cs = await idbGetAll('customers', []);
    for (const c of cs) body.appendChild(ce('div', 'lrow', '<span class="lrow__ic">🏆</span><div class="hd grow"><b>' + esc(c.name || c.id) + '</b><small>' + esc(c.phone || '') + ' · ' + (c.points || 0) + ' ' + L.t('points') + '</small></div>'));
    if (!cs.length) body.appendChild(ce('p', 'muted small', L.t('empty')));
    const add = ce('button', 'btn btn--primary btn--full', '+ ' + L.t('add_customer')); add.style.marginTop = '12px';
    add.onclick = () => {
      OFDialog({ title: L.t('add_customer') });
      $('dlg-body').innerHTML = '<div class="grid"><input id="cu-name" placeholder="' + L.t('name_label') + '"/><input id="cu-phone" placeholder="' + L.t('phone') + '" inputmode="tel"/></div>';
      $('dlg-btns').innerHTML = '';
      const ok = ce('button', 'btn btn--mint', L.t('save'));
      ok.onclick = async () => { const n = $('cu-name').value.trim(); if (!n) return; await idbPut('customers', { id: C.uuid(), name: n, phone: $('cu-phone').value.trim(), points: 0 }); await kvSet('rev', Date.now()); OFSyncNow(); OFCloseDlg(); scrCustomers(); };
      $('dlg-btns').appendChild(ok);
    };
    body.appendChild(add);
  });
}

async function scrDrivers() {
  OFShowSub(L.t('drivers'), 'Their phone joins the room as a Driver station', async (body) => {
    body.innerHTML = '';
    const ds = await idbGetAll('drivers', []);
    for (const d of ds) {
      const el = ce('div', 'lrow');
      el.innerHTML = '<span class="lrow__ic">🛵</span><div class="hd grow"><b>' + esc(d.name) + '</b><small>' + esc(d.phone || '') + '</small></div><span class="tag">' + (d.status || 'free') + '</span>'
        + '<button class="btn btn--sm btn--ghost" data-x="x">' + L.t('delete') + '</button>';
      el.querySelector('[data-x=x]').onclick = async () => { await idbDel('drivers', d.id); OFSyncNow(); scrDrivers(); };
      body.appendChild(el);
    }
    if (!ds.length) body.appendChild(ce('p', 'muted small', L.t('empty')));
    const add = ce('button', 'btn btn--primary btn--full', '+ ' + L.t('add_driver')); add.style.marginTop = '12px';
    add.onclick = () => {
      OFDialog({ title: L.t('add_driver') });
      $('dlg-body').innerHTML = '<div class="grid"><input id="dr-name" placeholder="' + L.t('name_label') + '"/><input id="dr-phone" placeholder="' + L.t('phone') + '" inputmode="tel"/></div>';
      $('dlg-btns').innerHTML = '';
      const ok = ce('button', 'btn btn--mint', L.t('save'));
      ok.onclick = async () => { const n = $('dr-name').value.trim(); if (!n) return; await idbPut('drivers', { id: C.uuid(), name: n, phone: $('dr-phone').value.trim(), status: 'free' }); OFSyncNow(); OFCloseDlg(); scrDrivers(); };
      $('dlg-btns').appendChild(ok);
    };
    body.appendChild(add);
  });
}

async function reportLines(rep) {
  const p = shop().profile;
  const rows = [];
  rows.push([L.t('taken'), money(rep.taken)]);
  rows.push([L.t('waiting'), money(rep.waiting) + ' (' + rep.unpaidCount + ')']);
  rows.push([L.t('sales_count'), String(rep.paidCount)]);
  rows.push([L.t('avg_sale'), money(rep.avg)]);
  for (const m of Object.entries(rep.byMethod)) rows.push([L.t('method_' + m[0]), money(m[1])]);
  for (const ch of Object.entries(rep.byChannel)) rows.push(['Channel ' + ch[0], money(ch[1])]);
  if (rep.top.length) rows.push([L.t('top_items'), rep.top.slice(0, 3).map(t => t[0] + ' ×' + t[1]).join(', ')]);
  return rows;
}
async function scrX() { await scrReport(false); }
async function scrZ() { await scrReport(true); }
async function scrReport(isZ) {
  OFShowSub(isZ ? L.t('z_report') : L.t('x_report'), isZ ? 'Closes the day — after this, today starts fresh' : "Today's live picture", async (body) => {
    const os = await OFOrdersAll();
    const start = C.dayStart();
    const rep = C.reportXZ(os, shop().profile, start);
    body.innerHTML = '';
    const card = ce('div', 'card card--pad');
    card.innerHTML = '<div class="row" style="justify-content:space-between"><b>' + new Date(start).toLocaleDateString() + '</b><span class="tag tag--mint">' + rep.paidCount + ' sales</span></div><div style="font-size:30px;font-weight:900;letter-spacing:-.5px;margin:8px 0">' + money(rep.taken) + '</div>';
    for (const [k, v] of await reportLines(rep)) { const r = ce('div', 'tot', '<span>' + esc(k) + '</span><span>' + esc(v) + '</span>'); card.appendChild(r); }
    body.appendChild(card);
    const row = ce('div', 'grid'); row.style.marginTop = '12px';
    const print = ce('button', 'btn btn--primary btn--full', '🖨️ ' + L.t('print_now'));
    print.onclick = () => {
      const demo = { id: 'XZ', ticketNo: isZ ? 'Z' : 'X', createdAt: Date.now(), type: 'retail', lines: rep.top.map(t => ({ name: t[0], qty: t[1], priceCents: 0, mods: [], notes: '' })), note: 'X/Z' };
      OFPrintReceipt({ ...demo, lines: [], xz: true }, { type: 'bill' });
      toast('Report sent to printer', 'Totals: ' + money(rep.taken));
    };
    row.appendChild(print);
    if (isZ) {
      const close = ce('button', 'btn btn--danger btn--full', L.t('z_report') + ' — close today');
      close.onclick = () => {
        OFDialog({ title: L.t('z_report'), bodyHtml: '<p class="muted small" style="font-weight:600">' + L.t('z_report_body') + '</p>' });
        $('dlg-btns').innerHTML = '';
        const no = ce('button', 'btn btn--ghost', L.t('cancel')); no.onclick = () => OFCloseDlg();
        const yes = ce('button', 'btn btn--danger', 'Close the day');
        yes.onclick = async () => {
          await kvSet('lastZ', { at: Date.now(), rep });
          await kvSet('dayStart', Date.now() + 1); // next instant = new day marker
          OFCloseDlg(); toast('Day closed ✓', 'Tomorrow’s X starts at zero'); OFAct['sub.back']();
        };
        $('dlg-btns').appendChild(no); $('dlg-btns').appendChild(yes);
      };
      row.appendChild(close);
    }
    body.appendChild(row);
  });
}

async function scrInsights() {
  OFShowSub(L.t('insights'), 'What sells, what runs out, who covers the floor', async (body) => {
    body.innerHTML = '';
    const os = await OFOrdersAll(); const ss = await OFStockAll(); const staff = await idbGetAll('staff', []);
    const rep = C.reportXZ(os, shop().profile, C.dayStart() - 6 * 86400000);
    body.appendChild(ce('div', 'sect__t', L.t('top_items') + ' (7 days)'));
    const card = ce('div', 'card card--pad');
    if (!rep.top.length) card.appendChild(ce('p', 'muted small', L.t('empty')));
    for (const t of rep.top.slice(0, 8)) card.appendChild(ce('div', 'tot', '<span>' + esc(t[0]) + '</span><span>× ' + t[1] + '</span>'));
    body.appendChild(card);
    body.appendChild(ce('div', 'sect__t', L.t('stock_to_watch')));
    const low = ss.filter(s => s.qty <= (s.lowStockAt ?? 5));
    if (!low.length) body.appendChild(ce('p', 'muted small', 'All healthy ✓'));
    for (const s of low) body.appendChild(ce('div', 'lrow', '<span class="lrow__ic">📦</span><div class="hd grow"><b>' + esc(s.name) + '</b><small>' + s.qty + ' left</small></div>'));
    body.appendChild(ce('div', 'sect__t', L.t('staff_shifts')));
    if (!staff.length) body.appendChild(ce('p', 'muted small', 'Add staff in More → Staff'));
    for (const s of staff) body.appendChild(ce('div', 'lrow', '<span class="lrow__ic">👤</span><div class="hd grow"><b>' + esc(s.name) + '</b><small>' + esc((s.roles || []).join(' · ') || 'any station') + '</small></div>'));
  });
}

async function scrUnpaid() {
  OFShowSub(L.t('unpaid_bills'), 'One tap opens the ticket', async (body) => {
    body.innerHTML = '';
    const os = (await OFOrdersAll()).filter(o => !['paid', 'cancelled', 'refunded'].includes(o.status));
    let total = 0;
    for (const o of os) total += OFBillOf(o).due;
    body.appendChild(ce('div', 'card card--forest', '<div style="padding:14px"><span class="small" style="opacity:.8;font-weight:700">' + os.length + ' ' + L.t('unpaid_bills').toLowerCase() + '</span><div style="font-size:28px;font-weight:900;margin-top:4px">' + money(total) + '</div></div>'));
    for (const o of os.sort((a, b) => a.createdAt - b.createdAt)) {
      const el = ce('div', 'lrow');
      el.innerHTML = '<div class="hd grow"><b>' + esc(OFWhereOf(o)) + '</b><small>' + (o.lines || []).length + ' item(s) · ' + o.status + '</small></div><span class="lrow__amt">' + money(OFBillOf(o).due) + '</span><span class="go">›</span>';
      el.onclick = () => OFOpenTicket(o.id);
      body.appendChild(el);
    }
    if (!os.length) body.appendChild(ce('p', 'muted small', L.t('no_orders')));
  });
}

async function scrSoldOut() {
  OFShowSub(L.t('sold_out_word'), 'Back on menu when the kitchen is ready', async (body) => {
    body.innerHTML = '';
    const ps = (await OFProductsAll()).filter(p => p.available === false || p.avail === false);
    for (const p of ps) {
      const el = ce('div', 'lrow');
      el.innerHTML = '<div class="hd grow"><b>' + esc(p.name) + '</b><small>' + money(p.priceCents) + '</small></div><button class="btn btn--sm btn--mint">' + L.t('back_on_menu') + '</button>';
      el.querySelector('button').onclick = async () => { p.available = true; p.avail = true; await idbPut('products', p); await kvSet('rev', Date.now()); OFSyncNow(); scrSoldOut(); };
      body.appendChild(el);
    }
    if (!ps.length) body.appendChild(ce('p', 'muted small', 'Everything is on the menu ✓'));
  });
}

async function scrRefunds() {
  OFShowSub(L.t('refunds'), 'Every refund: stock back + ledger note + reprint', async (body) => {
    body.innerHTML = '';
    const rs = (await idbGetAll('refunds', [])).sort((a, b) => b.at - a.at);
    for (const r of rs) {
      const el = ce('div', 'lrow');
      el.innerHTML = '<span class="lrow__ic">↩️</span><div class="hd grow"><b>#' + esc(String(r.orderId || '').slice(0, 8)) + '</b><small>' + (r.lines || []).map(l => l.qty + '× ' + esc(l.name)).join(', ') + (r.restock ? ' · stock back' : ' · ledger only') + '</small></div><span class="lrow__amt">−' + money(r.amountCents) + '</span><button class="btn btn--sm btn--ghost">🖨️</button>';
      el.querySelector('button').onclick = async () => { const o = await idbGet('orders', r.orderId, null); if (o) OFPrintReceipt({ ...o, refundOf: r.lines }, { type: 'refund' }); };
      body.appendChild(el);
    }
    if (!rs.length) body.appendChild(ce('p', 'muted small', L.t('empty')));
  });
}

async function scrThirdParty() {
  OFShowSub(L.t('third_party'), 'Log GrabFood/Foodpanda runs — totals split in reports', async (body) => {
    body.innerHTML = '';
    const start = C.dayStart();
    const rows = (await idbGetAll('channelsThird', [])).filter(r => r.at >= start);
    const by = {};
    for (const r of rows) by[r.channel] = (by[r.channel] || 0) + (r.amountCents || 0);
    for (const ch of ['grabfood', 'foodpanda']) {
      const host = ce('div', 'lrow');
      host.innerHTML = '<span class="lrow__ic">' + (ch === 'grabfood' ? '🟢' : '🩷') + '</span><div class="hd grow"><b>' + ch + '</b><small>' + rows.filter(r => r.channel === ch).length + ' today</small></div><span class="lrow__amt">' + money(by[ch] || 0) + '</span><button class="btn btn--sm btn--primary">+ ' + L.t('add') + '</button>';
      host.querySelector('button').onclick = () => {
        OFDialog({ title: ch + ' — log a sale' });
        $('dlg-body').innerHTML = '<input id="tp-amt" type="number" inputmode="decimal" placeholder="Amount (e.g. 24.50)"/>';
        $('dlg-btns').innerHTML = '';
        const ok = ce('button', 'btn btn--mint', L.t('save'));
        ok.onclick = async () => { const a = C.cents(Number($('tp-amt').value) || 0); if (!a) return; await idbPut('channelsThird', { id: C.uuid(), channel: ch, amountCents: a, at: Date.now() }); OFSyncNow(); OFCloseDlg(); scrThirdParty(); };
        $('dlg-btns').appendChild(ok);
      };
      body.appendChild(host);
    }
  });
}

async function scrCloud() {
  OFShowSub(L.t('cloud_sync'), 'Room relay: end-to-end encrypted, nothing readable in the cloud', async (body) => {
    body.innerHTML = '';
    const relay = OFRelayState();
    const err = await kvGet('relayErr', null);
    if (relay) {
      const card = ce('div', 'card card--pad');
      const pair = C.pairingEncode(relay.info);
      card.innerHTML = '<div class="row"><span class="chip chip--live">● ' + L.t('room_live') + '</span><span class="muted small grow" style="font-weight:600">' + L.t('join_code') + ': <b class="mono">' + esc(relay.info.code) + '</b></span></div>'
        + '<p class="small muted" style="font-weight:600;margin-top:8px">' + L.t('guest_hint') + '</p>'
        + '<div class="qrbox"><img width="180" height="180" src="https://api.qrserver.com/v1/create-qr-code/?size=240x240&margin=8&data=' + encodeURIComponent(pair) + '" alt="Pair QR"/></div>';
      const copy = ce('button', 'btn btn--ghost btn--full', 'Copy pairing text (OF1:…)'); copy.style.marginTop = '10px';
      copy.onclick = async () => { await navigator.clipboard.writeText(pair).catch(() => {}); toast('Copied ✓'); };
      card.appendChild(copy);
      const url = location.origin + '/order.html#' + C.b64uEncode(new TextEncoder().encode(JSON.stringify({ r: relay.info.room, c: relay.info.code, k: relay.info.secret, shop: shop().profile.name })));
      const guest = ce('button', 'btn btn--ghost btn--full', L.t('copy_link') + ' (guest menu URL)');
      guest.style.marginTop = '8px';
      guest.onclick = async () => { await navigator.clipboard.writeText(url).catch(() => {}); toast('Guest link copied ✓'); };
      card.appendChild(guest);
      body.appendChild(card);
      body.appendChild(ce('div', 'sect__t', L.t('stations')));
      const seen = await kvGet('stationsSeen', {});
      const rows = Object.entries(seen);
      if (!rows.length) body.appendChild(ce('p', 'muted small', 'Stations say hi every 45 seconds — they appear here.'));
      for (const [dev, info] of rows) {
        const age = Math.round((Date.now() - (info.at || 0)) / 1000);
        body.appendChild(ce('div', 'lrow', '<span class="dot" style="background:' + (age < 75 ? 'var(--mint)' : 'var(--muted)') + '"></span><div class="hd grow"><b>' + esc(dev) + '</b><small>' + esc(info.role || 'station') + '</small></div><span class="tag">' + (age < 75 ? 'live' : Math.floor(age / 60) + 'm ago') + '</span>'));
      }
      const close = ce('button', 'btn btn--danger btn--full', 'Close the room'); close.style.marginTop = '14px';
      close.onclick = async () => { await kvSet('roomInfo', null); location.reload(); };
      body.appendChild(close);
    } else {
      if (err) body.appendChild(ce('p', 'muted small', err));
      body.appendChild(ce('p', 'muted small', 'Open an encrypted room so Android and iPhone stations meet here. Orders never upload as cloud backups — state stays on your devices; the relay just passes ciphertext.'));
      const open = ce('button', 'btn btn--mint btn--full', L.t('open_room'));
      open.onclick = async () => {
        open.disabled = true;
        try {
          const licInfo = await OFLicenseInfo();
          const deviceId = await kvGet('deviceId', null) || 'web-main';
          const api = await window.OFApiCloud('/api/cloud/open', { licenseKey: licInfo.lic && licInfo.lic.key, deviceId });
          const res = api && api.json ? api.json : null;
          if (!res) { toast('Could not open the room', 'No internet — try again.'); return; }
          if (res.error === 'plan') { toast('Cloud is not on your plan', 'Tap Refresh my plan — or WhatsApp Jathol to add it.'); return; }
          if (!res.ok || !res.room || !res.secret) { toast('Could not open the room', 'Cloud answered: ' + (res.error || 'unknown') + '. Try again.'); return; }
          const info = { room: res.room, code: res.code, secret: res.secret, base: api.base || '', device: deviceId };
          await kvSet('roomInfo', info);
          await kvSet('relayErr', null);
          location.reload();
        } finally { open.disabled = false; }
      };
      body.appendChild(open);
    }
  });
}

async function scrQR() {
  OFShowSub(L.t('qr_ordering'), 'A QR per table — guests order, you confirm', async (body) => {
    body.innerHTML = '';
    const relay = OFRelayState();
    if (!relay) { body.appendChild(ce('p', 'muted small', 'Open the room first (More → Cloud room), then come back.')); return; }
    const ts = await idbGetAll('tables', []);
    const grid = ce('div', 'grid'); grid.style.gridTemplateColumns = 'repeat(auto-fill, minmax(140px,1fr))';
    for (const t of ts) {
      const d = { r: relay.info.room, c: relay.info.code, k: relay.info.secret, t: t.id, tn: t.label || t.name, shop: shop().profile.name };
      const url = location.origin + '/order.html#' + C.b64uEncode(new TextEncoder().encode(JSON.stringify(d)));
      const card = ce('div', 'card card--pad');
      card.style.textAlign = 'center';
      card.innerHTML = '<b>' + esc(t.label || t.name) + '</b><div class="qrbox" style="padding:10px"><img width="110" height="110" src="https://api.qrserver.com/v1/create-qr-code/?size=200x200&margin=4&data=' + encodeURIComponent(url) + '"/></div>'
        + '<button class="btn btn--sm btn--ghost" style="margin-top:6px">PNG</button>';
      card.querySelector('img').onclick = () => window.open(url, '_blank');
      card.querySelector('button').onclick = () => window.open('https://api.qrserver.com/v1/create-qr-code/?size=720x720&margin=16&data=' + encodeURIComponent(url), '_blank');
      grid.appendChild(card);
    }
    body.appendChild(grid);
    if (!ts.length) body.appendChild(ce('p', 'muted small', 'Add tables on the Tables tab first.'));
  });
}

async function scrBranding() {
  OFShowSub(L.t('guest_branding'), 'The page guests see when they scan', async (body) => {
    const p = shop().profile;
    body.innerHTML = '';
    const card = ce('div', 'card card--pad grid');
    card.innerHTML = fld('tagline', 'gb-tag', p.tagline) + fld('whatsapp', 'gb-wa', p.whatsapp, 'tel') + fld('opening_hours', 'gb-hours', p.hours) + fld('welcome_note', 'gb-wel', p.welcome)
      + '<div class="priceedit"><span class="small muted" style="font-weight:700">Accent</span><input id="gb-accent" type="color" value="' + (p.accent || '#2EA771') + '"/></div>'
      + '<label class="switch"><span>' + (L.t('guest_branding') || 'Show my branding') + '</span><input type="checkbox" id="gb-on" ' + (p.brandOn ? 'checked' : '') + '/></label>';
    body.appendChild(card);
    const save = ce('button', 'btn btn--mint btn--full', L.t('save')); save.style.marginTop = '12px';
    save.onclick = async () => {
      Object.assign(shop().profile, { tagline: $('gb-tag').value, whatsapp: $('gb-wa').value, hours: $('gb-hours').value, welcome: $('gb-wel').value, accent: $('gb-accent').value, brandOn: $('gb-on').checked });
      await kvSet('shop', shop()); await kvSet('rev', Date.now()); OFSyncNow(); toast(L.t('saved') + ' ✓');
    };
    body.appendChild(save);
  });
}

async function scrSplitInfo() {
  OFShowSub(L.t('split_payment'), '', async (body) => {
    body.appendChild(ce('div', 'card card--pad', '<p class="small muted" style="font-weight:600;line-height:1.7">On any ticket → Pay → turn on “Split with two methods”. Pick method 2, enter the amount on it, the rest is cash (or whatever method 1 is). Tendered, change and short are computed in cents — nothing drifts.</p>'));
  });
}
async function scrCustDisp() {
  OFShowSub(L.t('customer_display'), '', async (body) => {
    body.appendChild(ce('div', 'card card--pad', '<p class="small muted" style="font-weight:600;line-height:1.7">Open any ticket → ⋯ → Customer display. The screen goes dark with a giant total the guest can read across the counter. Tap Close to return.</p>'));
  });
}

async function scrReservations() {
  OFShowSub(L.t('reservations'), 'Tables or time slots', async (body) => {
    body.innerHTML = '';
    const start = C.dayStart();
    const rs = (await idbGetAll('reservations', [])).filter(r => (r.at || 0) >= start);
    for (const r of rs) {
      const el = ce('div', 'lrow');
      el.innerHTML = '<span class="lrow__ic">📅</span><div class="hd grow"><b>' + esc(r.customer) + '</b><small>' + esc(r.table || '') + ' · ' + new Date(r.at).toLocaleString() + (r.phone ? ' · ' + esc(r.phone) : '') + '</small></div><span class="tag">' + (r.status || 'booked') + '</span>'
        + (r.status !== 'seated' ? '<button class="btn btn--sm btn--mint">Seat</button>' : '');
      const b = el.querySelector('button'); if (b) b.onclick = async () => { r.status = 'seated'; await idbPut('reservations', r); OFSyncNow(); scrReservations(); };
      body.appendChild(el);
    }
    if (!rs.length) body.appendChild(ce('p', 'muted small', L.t('empty')));
    const add = ce('button', 'btn btn--primary btn--full', '+ ' + L.t('book_appt').replace('appointment', 'reservation')); add.style.marginTop = '12px';
    add.onclick = () => {
      OFDialog({ title: L.t('reservations') });
      $('dlg-body').innerHTML = '<div class="grid"><input id="rv-name" placeholder="' + L.t('customer') + '"/><input id="rv-phone" placeholder="' + L.t('phone') + '" inputmode="tel"/><input id="rv-table" placeholder="' + L.t('table_word') + '"/><input id="rv-time" type="datetime-local"/></div>';
      $('dlg-btns').innerHTML = '';
      const ok = ce('button', 'btn btn--mint', L.t('save'));
      ok.onclick = async () => { const n = $('rv-name').value.trim(); if (!n) return; await idbPut('reservations', { id: C.uuid(), customer: n, phone: $('rv-phone').value.trim(), table: $('rv-table').value.trim(), at: new Date($('rv-time').value || Date.now()).getTime(), status: 'booked' }); OFSyncNow(); OFCloseDlg(); scrReservations(); };
      $('dlg-btns').appendChild(ok);
    };
    body.appendChild(add);
  });
}

async function scrRecipes() {
  OFShowSub(L.t('recipe_costing'), 'Cost → price → margin, honest numbers', async (body) => {
    body.innerHTML = '';
    const ps = await OFProductsAll();
    for (const p of ps.filter(x => (x.recipe || []).length)) {
      const cost = (p.recipe || []).reduce((a, r) => a + (r.costCents || 0) * (r.qty || 1), 0);
      const price = p.priceCents || 0;
      const margin = price ? Math.round((price - cost) / price * 100) : 0;
      body.appendChild(ce('div', 'lrow', '<div class="hd grow"><b>' + esc(p.name) + '</b><small>cost ' + money(cost) + ' → price ' + money(price) + '</small></div><span class="tag ' + (margin < 50 ? 'tag--danger' : 'tag--mint') + '">' + margin + '% margin</span>'));
    }
    const edit = ce('button', 'btn btn--primary btn--full', 'Set ingredients for an item'); edit.style.marginTop = '12px';
    edit.onclick = async () => {
      const ss = await OFStockAll();
      OFPick('Pick the dish', '', ps.map(p => ({ label: p.name, act: async () => recipeEditor(p, ss) })).concat([{ label: L.t('cancel'), kind: 'ghost' }]));
    };
    body.appendChild(edit);
  });
}
function recipeEditor(p, ss) {
  OFDialog({ title: p.name + ' — ingredients' });
  const host = ce('div', 'grid');
  p.recipe = p.recipe || [];
  const draw = () => {
    host.innerHTML = '';
    for (const r of p.recipe) {
      const row = ce('div', 'lrow');
      row.innerHTML = '<div class="hd grow"><b>' + esc(r.name) + '</b><small>' + r.qty + ' ' + esc(r.unit || '') + ' @ ' + money(r.costCents || 0) + '</small></div><button class="btn btn--sm btn--danger">×</button>';
      row.querySelector('button').onclick = () => { p.recipe = p.recipe.filter(x => x !== r); draw(); };
      host.appendChild(row);
    }
    const row = ce('div', 'row');
    const sel = ce('select'); sel.style.flex = '1';
    for (const s of ss) sel.append(Object.assign(ce('option'), { value: s.id, textContent: s.name + ' (' + money(s.costCents) + ')' }));
    const qty = ce('input'); qty.type = 'number'; qty.value = '1'; qty.style.width = '70px';
    const addB = ce('button', 'btn btn--sm btn--primary', '+');
    addB.onclick = () => { const s = ss.find(x => x.id === sel.value); if (!s) return; p.recipe.push({ stockId: s.id, name: s.name, qty: Number(qty.value) || 1, costCents: s.costCents || 0, unit: s.unit }); draw(); };
    row.appendChild(sel); row.appendChild(qty); row.appendChild(addB);
    host.appendChild(row);
  };
  draw();
  $('dlg-body').innerHTML = ''; $('dlg-body').appendChild(host); $('dlg-btns').innerHTML = '';
  const ok = ce('button', 'btn btn--mint', L.t('save'));
  ok.onclick = async () => { await idbPut('products', p); await kvSet('rev', Date.now()); OFSyncNow(); OFCloseDlg(); scrRecipes(); };
  $('dlg-btns').appendChild(ok);
}

async function scrWastage() {
  OFShowSub(L.t('wastage'), 'Every entry drops stock and logs a reason', async (body) => {
    body.innerHTML = '';
    const ws = (await idbGetAll('wastage', [])).sort((a, b) => b.at - a.at);
    for (const w of ws) body.appendChild(ce('div', 'lrow', '<span class="lrow__ic">🗑️</span><div class="hd grow"><b>' + esc(w.name) + ' ×' + w.qty + '</b><small>' + ({ spoiled: L.t('waste_spoiled'), dropped: L.t('waste_dropped'), error: L.t('waste_error') }[w.reason] || w.reason) + ' · ' + new Date(w.at).toLocaleDateString() + '</small></div>'));
    if (!ws.length) body.appendChild(ce('p', 'muted small', L.t('empty')));
    const add = ce('button', 'btn btn--primary btn--full', '+ ' + L.t('wastage_add')); add.style.marginTop = '12px';
    add.onclick = async () => {
      const ss = await OFStockAll();
      OFDialog({ title: L.t('wastage_add') });
      const host = ce('div', 'grid');
      const sel = ce('select'); for (const s of ss) sel.append(Object.assign(ce('option'), { value: s.id, textContent: s.name + ' (qty ' + s.qty + ')' }));
      const qty = ce('input'); qty.type = 'number'; qty.placeholder = 'qty'; qty.value = '1';
      const selR = ce('select'); for (const r of ['spoiled', 'dropped', 'error']) selR.append(Object.assign(ce('option'), { value: r, textContent: r }));
      host.appendChild(sel); host.appendChild(qty); host.appendChild(selR);
      $('dlg-body').innerHTML = ''; $('dlg-body').appendChild(host); $('dlg-btns').innerHTML = '';
      const ok = ce('button', 'btn btn--mint', L.t('save'));
      ok.onclick = async () => {
        const s = ss.find(x => x.id === sel.value); if (!s) return;
        const q = Math.max(1, Number(qty.value) || 1);
        s.qty -= q; await idbPut('stock', s);
        await idbPut('wastage', { id: C.uuid(), name: s.name, qty: q, reason: selR.value, at: Date.now() });
        await kvSet('rev', Date.now()); OFSyncNow(); OFCloseDlg(); scrWastage();
      };
      $('dlg-btns').appendChild(ok);
    };
    body.appendChild(add);
  });
}

async function scrSuppliers() {
  OFShowSub(L.t('suppliers') + ' & ' + L.t('purchases'), 'Buy → receive → stock rises', async (body) => {
    body.innerHTML = '';
    body.appendChild(ce('div', 'sect__t', L.t('suppliers')));
    const ss = await idbGetAll('suppliers', []);
    for (const s of ss) body.appendChild(ce('div', 'lrow', '<span class="lrow__ic">🚚</span><div class="hd grow"><b>' + esc(s.name) + '</b><small>' + esc(s.phone || '') + '</small></div>'));
    const addS = ce('button', 'btn btn--ghost btn--full', '+ ' + L.t('add_supplier'));
    addS.onclick = () => {
      OFDialog({ title: L.t('add_supplier') });
      $('dlg-body').innerHTML = '<div class="grid"><input id="sup-n" placeholder="' + L.t('name_label') + '"/><input id="sup-p" placeholder="' + L.t('phone') + '" inputmode="tel"/></div>';
      $('dlg-btns').innerHTML = '';
      const ok = ce('button', 'btn btn--mint', L.t('save'));
      ok.onclick = async () => { const n = $('sup-n').value.trim(); if (!n) return; await idbPut('suppliers', { id: C.uuid(), name: n, phone: $('sup-p').value.trim() }); OFSyncNow(); OFCloseDlg(); scrSuppliers(); };
      $('dlg-btns').appendChild(ok);
    };
    body.appendChild(addS);
    body.appendChild(ce('div', 'sect__t', L.t('purchases')));
    const ps = (await idbGetAll('purchases', [])).sort((a, b) => b.at - a.at);
    for (const pu of ps) {
      const el = ce('div', 'lrow');
      el.innerHTML = '<span class="lrow__ic">📦</span><div class="hd grow"><b>' + esc(pu.itemName) + ' ×' + pu.qty + '</b><small>' + esc(pu.supplier || '') + ' · ' + new Date(pu.at).toLocaleDateString() + '</small></div><span class="tag ' + (pu.received ? 'tag--mint' : 'tag--gold') + '">' + (pu.received ? 'received' : 'open') + '</span>'
        + (pu.received ? '' : '<button class="btn btn--sm btn--mint">' + L.t('receive') + '</button>');
      const b = el.querySelector('button');
      if (b) b.onclick = async () => {
        pu.received = true; await idbPut('purchases', pu);
        const st = await idbGet('stock', pu.stockId, null); if (st) { st.qty += pu.qty; if (pu.costCents) st.costCents = pu.costCents; await idbPut('stock', st); }
        await kvSet('rev', Date.now()); OFSyncNow(); scrSuppliers();
      };
      body.appendChild(el);
    }
    const addP = ce('button', 'btn btn--primary btn--full', '+ ' + L.t('purchase')); addP.style.marginTop = '10px';
    addP.onclick = async () => {
      const sups = await idbGetAll('suppliers', []); const stocks = await OFStockAll();
      OFDialog({ title: L.t('purchase') });
      const host = ce('div', 'grid');
      const selS = ce('select'); for (const s of stocks) selS.append(Object.assign(ce('option'), { value: s.id, textContent: s.name }));
      const selSup = ce('select'); selSup.append(Object.assign(ce('option'), { value: '', textContent: '—' })); for (const s of sups) selSup.append(Object.assign(ce('option'), { value: s.name, textContent: s.name }));
      const qty = ce('input'); qty.type = 'number'; qty.placeholder = 'qty'; qty.value = '1';
      const cost = ce('input'); cost.type = 'number'; cost.placeholder = 'unit cost (e.g. 2.50)';
      host.appendChild(selS); host.appendChild(selSup); host.appendChild(qty); host.appendChild(cost);
      $('dlg-body').innerHTML = ''; $('dlg-body').appendChild(host); $('dlg-btns').innerHTML = '';
      const ok = ce('button', 'btn btn--mint', L.t('save'));
      ok.onclick = async () => { const st = stocks.find(x => x.id === selS.value); if (!st) return; await idbPut('purchases', { id: C.uuid(), stockId: st.id, itemName: st.name, supplier: selSup.value, qty: Math.max(1, Number(qty.value) || 1), costCents: C.cents(Number(cost.value) || 0), at: Date.now(), received: false }); OFSyncNow(); OFCloseDlg(); scrSuppliers(); };
      $('dlg-btns').appendChild(ok);
    };
    body.appendChild(addP);
  });
}

/* ================ TOOLS ================ */
async function scrBackup() {
  OFShowSub(L.t('backup_title'), 'JSON export — the APK reads the same shape', async (body) => {
    body.innerHTML = '';
    const exp = ce('button', 'btn btn--mint btn--full', '⬇️ ' + L.t('export_backup'));
    exp.onclick = async () => {
      const out = {};
      for (const s of ['products', 'tables', 'orders', 'stock', 'customers', 'staff', 'drivers', 'suppliers', 'purchases', 'wastage', 'reservations', 'channelsThird', 'refunds', 'appointments']) out[s] = await idbGetAll(s, []);
      out.kv = { shop: shop(), receiptsNote: 'orderflow-web v3' };
      const blob = new Blob([JSON.stringify(out, null, 1)], { type: 'application/json' });
      const a = ce('a'); a.href = URL.createObjectURL(blob); a.download = 'order-flow-backup-' + new Date().toISOString().slice(0, 10) + '.json';
      document.body.appendChild(a); a.click(); a.remove();
      toast('Backup exported ✓', 'Keep it in Files or Drive');
    };
    body.appendChild(exp);
    const imp = ce('button', 'btn btn--ghost btn--full', '⬆️ ' + L.t('import_backup')); imp.style.marginTop = '10px';
    imp.onclick = () => {
      const inp = ce('input'); inp.type = 'file'; inp.accept = 'application/json';
      inp.onchange = async () => {
        const txt = await inp.files[0].text();
        let obj; try { obj = JSON.parse(txt); } catch { return toast('Not a backup file'); }
        OFDialog({ title: L.t('import_backup'), bodyHtml: '<p class="muted small" style="font-weight:600">Importing replaces the data on THIS device. The room re-syncs it to every station right after.</p>' });
        $('dlg-btns').innerHTML = '';
        const no = ce('button', 'btn btn--ghost', L.t('cancel')); no.onclick = () => OFCloseDlg();
        const yes = ce('button', 'btn btn--mint', 'Import now');
        yes.onclick = async () => {
          for (const s of Object.keys(obj)) {
            if (!Array.isArray(obj[s])) continue;
            const db = await OFDB.open();
            if (!db.objectStoreNames.contains(s)) continue;
            await idbClear(s);
            for (const row of obj[s]) if (row && row.id) await idbPut(s, row);
          }
          if (obj.kv && obj.kv.shop) { const keep = shop(); Object.assign(keep, obj.kv.shop); await kvSet('shop', keep); }
          await kvSet('rev', Date.now()); OFCloseDlg(); toast('Imported ✓'); OFAct['sub.back'](); location.reload();
        };
        $('dlg-btns').appendChild(no); $('dlg-btns').appendChild(yes);
      };
      inp.click();
    };
    body.appendChild(imp);
  });
}

async function scrLanguage() {
  OFShowSub(L.t('language'), '', async (body) => {
    body.innerHTML = '';
    for (const [code, name, sub] of [['en', 'English', 'Everything in English'], ['ur', 'اردو', 'Right-to-left, Urdu strings from the app']]) {
      const b = ce('button', 'modelcard' + (OFLang.getLang() === code ? ' is-on' : ''));
      b.style.cssText = 'display:flex;flex-direction:row;align-items:center;gap:12px;min-height:60px;padding:16px;margin-bottom:10px';
      b.innerHTML = '<span style="font-size:22px">' + (code === 'ur' ? '🇵🇰' : '🇬🇧') + '</span><span class="grow"><b>' + name + '</b><br><small style="color:var(--muted)">' + sub + '</small></span>' + (OFLang.getLang() === code ? '<span>✓</span>' : '');
      b.onclick = async () => { OFLang.setLang(code); await kvSet('lang', code); OFApplyText(); scrLanguage(); };
      body.appendChild(b);
    }
  });
}

async function scrTheme() {
  OFShowSub(L.t('theme'), '', async (body) => {
    body.innerHTML = '';
    const cur = await kvGet('theme', 'light');
    for (const [code, name, sub] of [['light', L.t('theme_light'), 'Cream canvas, dark green card — the signature look'], ['dark', L.t('theme_dark'), 'Deep forest night — eyes rest at the counter'], ['auto', L.t('theme_auto'), 'Follows the iPhone setting']]) {
      const b = ce('button', 'modelcard' + (cur === code ? ' is-on' : ''));
      b.style.cssText = 'display:flex;flex-direction:column;align-items:flex-start;min-height:64px;padding:16px;margin-bottom:10px;text-align:left';
      b.innerHTML = '<b>' + esc(name) + '</b><small style="color:var(--muted)">' + esc(sub) + '</small>';
      b.onclick = async () => { await kvSet('theme', code); OFApplyTheme && window.OFApplyTheme(code === 'auto' ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : code, true); scrTheme(); };
      body.appendChild(b);
    }
    body.appendChild(ce('p', 'muted small', L.t('theme_body')));
  });
}

async function scrRefresh() {
  OFShowSub(L.t('refresh_plan'), '', async (body) => {
    body.innerHTML = '';
    const info = await OFLicenseInfo();
    const ent = info.ent;
    const n = ent.allOn ? C.FEATURE_KEYS.length : (ent.features || []).length;
    const card = ce('div', 'card card--pad');
    card.innerHTML = '<div class="row" style="justify-content:space-between"><b>Plan ' + esc(ent.plan || 'full') + '</b><span class="tag tag--mint">' + n + '/16</span></div>'
      + '<p class="small muted" style="font-weight:600;margin-top:8px">' + C.FEATURE_CATALOG.filter(f => ent.allOn || (ent.features || []).includes(f.key)).map(f => '✓ ' + f.label).join('<br>') + '</p>'
      + '<p class="small" style="margin-top:8px;color:var(--warn);font-weight:600">' + C.FEATURE_CATALOG.filter(f => !(ent.allOn || (ent.features || []).includes(f.key))).map(f => '🔒 ' + f.label).join('<br>') + '</p>';
    body.appendChild(card);
    const btn = ce('button', 'btn btn--mint btn--full', L.t('refresh_plan')); btn.style.marginTop = '12px';
    btn.onclick = async () => { btn.disabled = true; await window.OFRefreshPlan(); btn.disabled = false; scrRefresh(); };
    body.appendChild(btn);
    if (info.lic) body.appendChild(ce('p', 'muted small', 'Key: ' + info.lic.key.slice(0, 10) + '… · activated ' + new Date(info.lic.okAt || Date.now()).toLocaleDateString()));
  });
}

async function scrPrivacy() {
  OFShowSub(L.t('privacy'), 'Plain words, no legalese', async (body) => {
    body.innerHTML = '';
    body.appendChild(ce('div', 'card card--pad', '<p class="small muted" style="font-weight:600;line-height:1.8">• Your shop data (orders, menu, stock, staff PINs, customers) lives in this iPhone and your stations.<br>• The cloud is a relay room: devices swap encrypted snapshots (AES-GCM) and delete each relay message the moment it is read. We cannot read any of it.<br>• Orders are never uploaded as backups. Export a backup yourself from More → Backup.<br>• Support is a human on WhatsApp: @Jathol_Jutt.</p>'));
  });
}
async function scrAbout() {
  OFShowSub('About', '', async (body) => {
    body.innerHTML = '';
    body.appendChild(ce('div', 'card card--pad', '<div style="text-align:center;padding:14px"><img src="/media/logo.png" width="56" style="border-radius:14px"/><div style="font-weight:900;font-size:17px;margin-top:10px">Order Flow Web</div><div class="small muted" style="font-weight:600;margin-top:4px">' + (L.t('app_name') || 'Order Flow') + ' · by Jathol · same POS as the Android app — in your browser</div><div class="small muted" style="font-weight:600;margin-top:8px">v25 · cache of-shell-v30</div></div>'));
  });
}

Object.assign(A, {
  'more.bill': () => scrBill(), 'more.printers': () => scrPrinters(), 'more.staff': () => scrStaff(),
  'more.customers': () => scrCustomers(), 'more.drivers': () => scrDrivers(),
  'more.xreport': () => scrX(), 'more.zreport': () => scrZ(), 'more.insights': () => scrInsights(),
  'more.unpaid': () => scrUnpaid(), 'more.soldout': () => scrSoldOut(), 'more.refunds': () => scrRefunds(),
  'more.thirdparty': () => scrThirdParty(),
  'more.cloud': () => scrCloud(), 'more.qr': () => scrQR(), 'more.branding': () => scrBranding(),
  'more.splitinfo': () => scrSplitInfo(), 'more.custdisp': () => scrCustDisp(),
  'more.reservations': () => scrReservations(), 'more.recipes': () => scrRecipes(),
  'more.wastage': () => scrWastage(), 'more.suppliers': () => scrSuppliers(),
  'more.backup': () => scrBackup(), 'more.language': () => scrLanguage(), 'more.theme': () => scrTheme(),
  'more.refresh': () => scrRefresh(), 'more.install': () => { $('sheet-install').classList.add('is-open'); },
  'more.whatsapp': () => scrWhatsApp(), 'more.privacy': () => scrPrivacy(), 'more.about': () => scrAbout(),
  'more.openAt': (what) => { if (what === 'cloud') scrCloud(); },
  'install.close': () => $('sheet-install').classList.remove('is-open'),
});
function scrWhatsApp() {
  OFShowSub(L.t('wa_support'), '', async (body) => {
    body.innerHTML = '';
    body.appendChild(ce('div', 'card card--pad', '<div style="text-align:center;padding:16px"><div style="font-size:38px">💬</div><div style="font-weight:900;font-size:16px;margin:8px 0">' + L.t('support') + '</div><a class="btn btn--mint" style="display:inline-flex;margin-top:8px" href="https://wa.me/Jathol_Jutt" target="_blank" rel="noopener">wa.me/Jathol_Jutt</a><p class="small muted" style="margin-top:12px;font-weight:600">Tell us what broke. Demo the POS in a video. Real reply, real fix.</p></div>'));
  });
}
})();
