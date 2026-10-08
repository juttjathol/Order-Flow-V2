/* ============================================================
   Order Flow POS — CORE (pure logic, no DOM)
   Shared by app.js / ticket.js / more.js / order.js AND the
   node self-test harness. Mirrors models_*.dart + reducer.dart.
   ============================================================ */
(function (root, factory) {
  const OFC = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = OFC;
  else root.OFCore = OFC;
})(typeof self !== 'undefined' ? self : globalThis, function () {
  'use strict';

  // ——— ids & text ———
  function uuid() {
    if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
      const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
    });
  }
  function b64uEncode(bytes) {
    let bin = ''; const u8 = typeof bytes === 'string' ? new TextEncoder().encode(bytes) : bytes;
    for (let i = 0; i < u8.length; i++) bin += String.fromCharCode(u8[i]);
    return (typeof btoa !== 'undefined' ? btoa(bin) : Buffer.from(u8).toString('base64'))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }
  function b64uDecode(s) {
    s = String(s || '').replace(/-/g, '+').replace(/_/g, '/');
    while (s.length % 4) s += '=';
    if (typeof atob !== 'undefined') return Uint8Array.from(atob(s), c => c.charCodeAt(0));
    return Uint8Array.from(Buffer.from(s, 'base64'));
  }
  function b64uDecodeString(s) { return new TextDecoder().decode(b64uDecode(s)); }

  // ——— license key contract (OF-XXXX-XXXX-XXXX-XXXX) ———
  const KEY_RE = /^OF-(?:[A-Z0-9]{4}-){3}[A-Z0-9]{4}$/;
  // paste from WhatsApp/email in ANY shape (spaced, no hyphens, lowercase) → OF-XXXX-XXXX-XXXX-XXXX
  function normalizeKey(raw) {
    let v = String(raw || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (v.startsWith('OF')) v = v.slice(2);
    const groups = v.match(/.{1,4}/g) || [];
    return 'OF-' + groups.slice(0, 4).join('-');
  }
  function isValidKey(raw) { return KEY_RE.test(normalizeKey(raw)); }
  function maskKey(key) {
    key = normalizeKey(key);
    if (!KEY_RE.test(key)) return '—';
    const parts = key.split('-');
    return [parts[0], parts[1], '••••', '••••', parts[4]].join('-');
  }

  // ——— pairing OF1:room:code:secret ———
  function pairingEncode(p) { return 'OF1:' + p.room + ':' + p.code + ':' + p.secret; }
  function pairingDecode(text) {
    const t = String(text || '').trim();
    if (!t.toUpperCase().startsWith('OF1:')) throw new Error('NOT_OF1');
    const parts = t.slice(4).split(':').map(s => s.trim()).filter(Boolean);
    if (parts.length < 3) throw new Error('SHORT');
    return { room: parts[0], code: parts[1], secret: parts[2] };
  }

  // ——— plan catalog (models_plans.dart — keys are stable, never rename) ———
  const FEATURE_CATALOG = [
    { key: 'multi_terminal', label: 'Connect extra station devices' },
    { key: 'station_printers', label: 'Per-station printers & auto kitchen print' },
    { key: 'qr_ordering', label: 'QR table ordering & self-order' },
    { key: 'loyalty', label: 'Loyalty points & store credit' },
    { key: 'split_payment', label: 'Split payment (two methods)' },
    { key: 'refunds', label: 'Refund paid orders' },
    { key: 'customer_display', label: 'Customer display screen' },
    { key: 'reservations', label: 'Reservations / appointments' },
    { key: 'recipe_costing', label: 'Recipe costing & food margins' },
    { key: 'wastage', label: 'Wastage log' },
    { key: 'purchases', label: 'Suppliers & purchase orders' },
    { key: 'advanced_reports', label: 'Insights: best sellers, profit, staff' },
    { key: 'eighty_six', label: 'Sold-out board' },
    { key: 'cloud_sync', label: 'Cloud station networking' },
    { key: 'qr_branding', label: 'Your own branded guest QR ordering page' },
    { key: 'third_party', label: 'Third-party channels — Foodpanda, Grab & more (manual)' },
  ];
  const FEATURE_KEYS = FEATURE_CATALOG.map(f => f.key);
  const NOT_STARTER = ['qr_ordering', 'cloud_sync', 'qr_branding', 'third_party'];
  const PLAN_PRESETS = {
    starter: FEATURE_KEYS.filter(k => !NOT_STARTER.includes(k)),
    growth: FEATURE_KEYS.filter(k => !NOT_STARTER.includes(k)),
    custom: FEATURE_KEYS.slice(),
    full: FEATURE_KEYS.slice(),
  };
  function entitlementsFromLicense(payload) {
    const plan = String(payload && payload.plan || '');
    if (plan === 'full') return { allOn: true, plan: 'full', models: [], features: FEATURE_KEYS.slice() };
    const am = payload && payload.allowedModels, af = payload && payload.allowedFeatures;
    const hasPlan = Array.isArray(am) || Array.isArray(af);
    if (!hasPlan) return { allOn: true, plan: plan || 'full', models: [], features: FEATURE_KEYS.slice() };
    // heal: paid plan with an empty feature list → plan preset (APK rule)
    let features = Array.isArray(af) ? af.filter(k => FEATURE_KEYS.includes(k)) : [];
    if (features.length === 0 && PLAN_PRESETS[plan]) features = PLAN_PRESETS[plan].slice();
    return { allOn: false, plan, models: Array.isArray(am) ? am : [], features };
  }
  function allowsFeature(e, key) {
    if (!e || e.allOn) return true;
    if (!FEATURE_KEYS.includes(key)) return true;
    return (e.features || []).includes(key);
  }
  function allowsModel(e, model) {
    if (!e || e.allOn || !(e.models || []).length) return true;
    return e.models.includes(model);
  }

  // ——— money: integer cents, one function for everything ———
  const cents = n => Math.round(Number(n) * 100) || 0;
  const fromCents = c => (c / 100);
  function fmtCents(c, currency) {
    c = c == null ? 0 : c;
    const sign = c < 0 ? '-' : '';
    return sign + (currency || '') + ' ' + (Math.abs(c) / 100).toFixed(2);
  }
  /** Bill math in cents. order: {lines:[{qty, unitPrice? price, mods:[{priceCents?}]}], discount, taxRate, serviceRate, tip} s: {tax,svc} fallback */
  function billOf(order, s) {
    const sub = (order.lines || order.items || []).reduce((a, it) => {
      const unit = (it.priceCents != null) ? it.priceCents : cents(it.price != null ? it.price : it.unitPrice);
      const mods = (it.mods || []).reduce((m, d) => m + (d.priceCents != null ? d.priceCents : cents(d.price)), 0);
      return a + (unit + mods) * (it.qty || 1);
    }, 0);
    const discount = order.discountCents != null ? order.discountCents : cents(order.discount);
    const taxRate = order.taxRate != null ? order.taxRate : (s && s.tax) || 0;
    const svcRate = order.serviceRate != null ? order.serviceRate : (s && s.svc) || 0;
    const taxed = Math.max(0, sub - discount);
    const taxAmt = Math.round(taxed * taxRate / 100);
    const svcAmt = Math.round(taxed * svcRate / 100);
    const tip = order.tipCents != null ? order.tipCents : cents(order.tip);
    const due = taxed + taxAmt + svcAmt + tip;
    // one shape, two vocabularies: reducer names + UI names
    return {
      sub, discount, taxAmt, svcAmt, tip, due,
      subTotal: sub, total: taxed + taxAmt + svcAmt, service: svcAmt,
      taxes: taxAmt ? [[(taxRate % 1 ? taxRate : taxRate) + '% tax', taxAmt]] : [],
    };
  }
  /** Pay sheet arithmetic (APK _pay) — object opts; result carries need/change/cashTarget/tenderDue. */
  function payCheck(dueCents, opts) {
    opts = opts || {};
    const m1 = opts.method || 'cash';
    const tender = opts.tenderCents || 0;
    const split = opts.split || null;
    const splitAmt = split ? Math.max(0, split.amountCents || 0) : 0;
    const total = dueCents + (opts.tipCents || 0);
    const primary = split ? total - splitAmt : total;
    const cashPart = m1 === 'cash' ? primary : (split && (split.method2 || 'cash') === 'cash' ? splitAmt : 0);
    const tenderDue = m1 === 'cash' ? 0 : primary;      // exact-pay amount on method 1 (non-cash)
    const need = cashPart ? Math.max(0, cashPart - tender) : 0;
    const change = cashPart ? Math.max(0, tender - cashPart) : 0;
    const ok = total >= 0 && need === 0 && (!split || (splitAmt > 0 && splitAmt < total));
    return { ok, need, change, cashTarget: cashPart, tenderDue, primary, splitAmt, total, short: need };
  }

  // ——— order helpers (used by ticket + harness) ———
  function newOrder(profile, opts) {
    const o = {
      id: uuid(),
      ticketNo: String(opts.ticketNo || ('100' + Math.floor(Math.random() * 900))),
      type: opts.type || 'dineIn',
      status: 'open',
      tableId: opts.tableId || null,
      tableName: opts.tableName || '',
      customerName: '', customerPhone: '', address: '', driverId: null, staffId: null,
      lines: [], discount: 0, taxRate: null, serviceRate: null, tip: 0,
      payment: null, splitPayment: null, splitAmount: 0, payments: [],
      notes: '', createdAt: Date.now(), updatedAt: Date.now(), createdBy: opts.createdBy || '',
      stockDeducted: false, held: false, voidReason: '', sentAt: null, channel: opts.channel || '',
      shiftNo: opts.shiftNo || 0,
    };
    return o;
  }
  function addLine(order, product, qty) {
    qty = qty || 1;
    if (!product || product.available === false) return order;
    const ex = order.lines.find(l => l.productId === product.id && (l.name === product.name));
    order.updatedAt = Date.now();
    if (ex) { ex.qty += qty; return order; }
    order.lines.push({
      id: uuid(), productId: product.id, name: product.name, qty,
      priceCents: product.priceCents != null ? product.priceCents : cents(product.price),
      mods: [], notes: '', course: product.course || 'main',
    });
    return order;
  }
  function linePriceCents(line) {
    return ((line.priceCents != null ? line.priceCents : cents(line.price)) +
      (line.mods || []).reduce((a, m) => a + (m.priceCents != null ? m.priceCents : cents(m.price)), 0)) * (line.qty || 1);
  }
  /** What comes back on refund of a paid order (mirrors reducer refund). */
  function refundPlan(order, products) {
    const linesRefund = []; const stockBack = [];
    let amount = 0;
    for (const l of (order.lines || order.items || [])) {
      const price = l.priceCents != null ? l.priceCents : cents(l.price);
      linesRefund.push({ productId: l.productId || l.id || null, name: l.name, qty: l.qty || 1, priceCents: price });
      amount += linePriceCents(l);
      const p = (products || []).find(x => x.id === (l.productId || l.id));
      const inv = p && (p.inventoryId || p.stockId);
      if (inv) stockBack.push({ stockId: inv, qty: (l.qty || 1) * (p.deductQty || 1) });
    }
    return { linesRefund, stockBack, amount };
  }
  /** Stock deduction plan at payment time (mirror of stockBack). */
  function deductPlan(order, products) {
    if (order.stockDeducted) return [];
    return refundPlan(order, products).stockBack.map(d => ({ ...d })); // apply as decrement
  }

  // ——— reports (pure) ———
  function dayStart(ts) { const d = new Date(ts == null ? Date.now() : ts); d.setHours(0, 0, 0, 0); return d.getTime(); }
  function reportXZ(orders, s, when) {
    const start = dayStart(when);
    const list = (orders || []).filter(o => (o.createdAt || 0) >= start && o.status !== 'cancelled');
    const isPaid = o => o.status === 'paid';
    const paid = list.filter(isPaid);
    const unpaid = list.filter(o => !isPaid(o));
    let taken = 0, waiting = 0; const byMethod = {}, byChannel = {}, items = {};
    for (const o of paid) {
      const b = billOf(o, s); taken += b.due;
      const met = o.payment && o.payment.method || (o.payments && o.payments[0] && o.payments[0].method) || 'cash';
      byMethod[met] = (byMethod[met] || 0) + b.due;
      const ch = o.channel || 'pos';
      byChannel[ch === 'qr' ? 'qr' : 'pos'] = (byChannel[ch === 'qr' ? 'qr' : 'pos'] || 0) + b.due;
    }
    for (const o of unpaid) waiting += billOf(o, s).due;
    for (const o of list) for (const l of (o.lines || [])) items[l.name] = (items[l.name] || 0) + (l.qty || 1);
    const top = Object.entries(items).sort((a, b) => b[1] - a[1]).slice(0, 8);
    return { paidCount: paid.length, unpaidCount: unpaid.length, taken, waiting, byMethod, byChannel, top, avg: paid.length ? Math.round(taken / paid.length) : 0 };
  }

  // ——— business models & roles ———
  const MODELS = ['restaurant', 'retail', 'fastfood', 'services'];
  const MODEL_SECOND_TAB = { restaurant: 'tables', retail: 'register', fastfood: 'queue', services: 'appointments' };
  const MODEL_ROLES = {
    restaurant: ['orderTaker', 'kitchen', 'cashier', 'driver', 'stockClerk'],
    retail: ['cashier', 'stockClerk'],
    fastfood: ['orderTaker', 'kitchen', 'cashier', 'stockClerk'],
    services: ['frontDesk', 'specialist', 'cashier'],
  };
  return {
    uuid, b64uEncode, b64uDecode, b64uDecodeString,
    KEY_RE, normalizeKey, isValidKey, maskKey,
    pairingEncode, pairingDecode,
    FEATURE_CATALOG, FEATURE_KEYS, PLAN_PRESETS, entitlementsFromLicense, allowsFeature, allowsModel,
    cents, fromCents, fmtCents, billOf, payCheck,
    newOrder, addLine, linePriceCents, refundPlan, deductPlan,
    dayStart, reportXZ,
    MODELS, MODEL_SECOND_TAB, MODEL_ROLES,
  };
});
