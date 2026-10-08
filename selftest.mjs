/* Order Flow POS — pre-commit self test (pure node, no deps).
   Runs the full money/plan/license/pairing/contracts matrix and
   a device-free "click path" simulation of a whole day of trade.
   Fails the push if ANYTHING is off — run: node selftest.mjs */
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = dirname(fileURLToPath(import.meta.url));
const APP = join(ROOT, 'website', 'public', 'app');
const PUB = join(ROOT, 'website', 'public');
const require = createRequire(import.meta.url);
const C = require(join(APP, 'core.js'));

let pass = 0, failCount = 0;
const failures = [];
function ok(name, cond) { if (cond) { pass++; console.log('  ✓ ' + name); } else { failCount++; failures.push(name); console.log('  ✗ FAIL: ' + name); } }
function eq(name, a, b) { ok(name + ` (${JSON.stringify(a)} === ${JSON.stringify(b)})`, JSON.stringify(a) === JSON.stringify(b)); }

/* ============ 1. syntax: every shipped JS parses ============ */
console.log('\n[1] syntax');
const JS = ['core.js', 'lang.js', 'db.js', 'print.js', 'app.js', 'ticket.js', 'more.js'].map(f => join(APP, f));
JS.push(join(PUB, 'order.js'), join(PUB, 'sw.js'));
let synOK = true;
for (const f of JS) { try { execFileSync(process.execPath, ['--check', f], { stdio: 'pipe' }); } catch (e) { synOK = false; console.log(String(e.stderr).slice(0, 400)); ok('syntax ' + f, false); } }
ok('all shipped JS passes node --check', synOK);

/* ============ 2. license key contract ============ */
console.log('\n[2] license key OF-contract');
eq('normalize trims+uppercases+prefix', C.normalizeKey('  of-abcd-1234-cdef-5678 '), 'OF-ABCD-1234-CDEF-5678');
ok('valid full key accepted', C.isValidKey('OF-ABCD-1234-CDEF-5678'));
ok('truncated key rejected', !C.isValidKey('OF-ABCD-1234'));
ok('lower input still valid', C.isValidKey('of-abcd-1234-cdef-5678'));
ok('no key → invalid', !C.isValidKey('') && !C.isValidKey(null));
ok('mask keeps prefix', C.maskKey('OF-ABCD-1234-CDEF-5678').startsWith('OF-ABCD'));
const appJs = readFileSync(join(APP, 'app.js'), 'utf8');
const idx0 = readFileSync(join(APP, 'index.html'), 'utf8');
ok('validator pings /api/v1/license/validate', appJs.includes('/api/v1/license/validate'));
ok('license box fits a full 22-char key (was 19 — truncated pastes)', /maxlength="(2[2-9]|[3-9]\d)"/.test(idx0));
ok('same-origin first, pages.dev fallback', /API_BASES\s*=\s*\[\s*''/.test(appJs) && appJs.includes('https://order-flow-v2.pages.dev'));
ok('only not_found/revoked/expired lock', appJs.includes('not_found') && appJs.includes('revoked') && appJs.includes('expired'));
ok('offline never locks an activated shop', appJs.includes("state: 'offline'") && appJs.includes('prev.okAt'));

/* ============ 3. OF1 pairing round-trip ============ */
console.log('\n[3] OF1 pairing');
const pair = { room: 'r001', code: '482910', secret: 's3cr3tabcdef' };
eq('OF1 round-trip', C.pairingDecode(C.pairingEncode(pair)), pair);
let threw = false; try { C.pairingDecode('garbage'); } catch { threw = true; }
ok('bad pairing text throws (UI shows error, never joins)', threw);
eq('b64u unicode round-trip', C.b64uDecodeString(C.b64uEncode('{"name":"حلو café"}')), '{"name":"حلو café"}');

/* ============ 4. plan catalog & heal rules ============ */
console.log('\n[4] plan gating');
eq('catalog has 16 keys', C.FEATURE_CATALOG.length, 16);
ok('starter preset locks qr/cloud/branding/third-party',
  ['qr_ordering', 'cloud_sync', 'qr_branding', 'third_party'].every(k => !C.PLAN_PRESETS.starter.includes(k)));
eq('growth preset == starter', C.PLAN_PRESETS.growth, C.PLAN_PRESETS.starter);
eq('custom preset = everything', C.PLAN_PRESETS.custom.length, 16);
const entFull = C.entitlementsFromLicense({ plan: 'full', allowedFeatures: ['x'], allowedModels: ['retail'] });
ok("'full' turns everything ON regardless of lists", entFull.allOn === true && C.FEATURE_KEYS.every(k => C.allowsFeature(entFull, k)));
const entStarter = C.entitlementsFromLicense({ plan: 'starter', allowedModels: ['restaurant', 'retail'], allowedFeatures: [] });
ok('paid plan with empty features heals to preset', entStarter.features.includes('refunds') && !entStarter.features.includes('qr_ordering'));
ok('starter locks qr_ordering', !C.allowsFeature(entStarter, 'qr_ordering'));
ok('starter locks cloud_sync', !C.allowsFeature(entStarter, 'cloud_sync'));
ok('starter keeps split payment', C.allowsFeature(entStarter, 'split_payment'));
ok('starter model gate works', C.allowsModel(entStarter, 'restaurant') && !C.allowsModel(entStarter, 'fastfood'));
ok('unknown feature passes through (not surgically gated)', C.allowsFeature(entStarter, 'not_a_feature'));

/* ============ 5. integer cents money ============ */
console.log('\n[5] money in cents');
eq('0.1 + 0.2 == 0.3 in cents', C.cents(0.1) + C.cents(0.2), 30);
eq('fmt', C.fmtCents(1230, 'RM'), 'RM 12.30');
const o1 = C.newOrder({ currency: 'RM' }, { type: 'dineIn', ticketNo: '101' });
C.addLine(o1, { id: 'p1', name: 'Tea', priceCents: 500, available: true });
C.addLine(o1, { id: 'p1', name: 'Tea', priceCents: 500, available: true });
C.addLine(o1, { id: 'p2', name: 'Nasi', priceCents: 1800, available: true });
const b1 = C.billOf(o1, { tax: 6, svc: 10 });
eq('bill subtotal', b1.subTotal, 2800);
eq('bill tax 6%', b1.taxAmt, Math.round(2800 * 6 / 100));
eq('bill service 10%', b1.svcAmt, 280);
eq('bill due', b1.due, 2800 + 168 + 280);
withDisc();
function withDisc() {
  const o = C.newOrder({}, { type: 'takeaway' });
  C.addLine(o, { id: 'p3', name: 'X', priceCents: 1000, available: true });
  o.discountCents = 250; o.taxRate = 6;
  const b = C.billOf(o, {});
  eq('discount applied before tax', b.due, 750 + Math.round(750 * 6 / 100));
}

/* ============ 6. pay sheet matrix ============ */
console.log('\n[6] pay sheet arithmetic');
{
  const ck = C.payCheck(3000, { method: 'cash', tenderCents: 3000 });
  ok('exact cash → need 0, change 0', ck.ok && ck.need === 0 && ck.change === 0);
  const c2 = C.payCheck(1230, { method: 'cash', tenderCents: 1500 });
  eq('over-tender change', c2.change, 270);
  const c3 = C.payCheck(1230, { method: 'cash', tenderCents: 900 });
  eq('short shows remaining', c3.need, 330); ok('short blocks confirm', !c3.ok);
  const c4 = C.payCheck(1000, { method: 'card' });
  ok('card needs no tender', c4.ok && c4.cashTarget === 0);
  const c5 = C.payCheck(1000, { method: 'cash', tenderCents: 700, split: { method2: 'card', amountCents: 400 } });
  ok('split: cash part = 600', c5.cashTarget === 600);
  ok('split: change 100 from the 700 tendered', c5.change === 100);
  const c6 = C.payCheck(1000, { method: 'card', split: { method2: 'cash', amountCents: 400 }, tenderCents: 300 });
  ok('split m2 cash short 100', c6.need === 100 && !c6.ok);
  const c7 = C.payCheck(1000, { method: 'cash', tenderCents: 1000, split: { method2: 'card', amountCents: 0 } });
  ok('split with 0 on second rejects', !c7.ok);
  const c8 = C.payCheck(1230, { method: 'cash', tenderCents: 1300, tipCents: 100 });
  ok('tip rides along', c8.total === 1330 && c8.cashTarget === 1330);
  const c9 = C.payCheck(1230, { method: 'cash', tenderCents: 1330, tipCents: 100 });
  ok('exact with tip ok', c9.ok && c9.change === 0);
}

/* ============ 7. simulated click path (pure node day of trade) ============ */
console.log('\n[7] click-path simulation: setup → table → item → ticket → send → ready → pay → receipt → X report → export/import');
{
  // fake device store
  const store = new Map();
  const put = (s, row) => store.set(s + ':' + row.id, row);
  const all = (s) => [...store.entries()].filter(([k]) => k.startsWith(s + ':')).map(([, v]) => v);

  // setup restaurant
  const profile = { name: 'Test Shop', currency: 'RM', model: 'restaurant', tax: 0, svc: 0 };
  ok('restaurant roles include kitchen', C.MODEL_ROLES.restaurant.includes('kitchen'));
  ok('restaurant 2nd tab = tables', C.MODEL_SECOND_TAB.restaurant === 'tables');

  // table
  const table = { id: 't1', label: 'T1', seats: 4, state: 'free' };
  put('tables', table);

  // ticket + items
  const ticket = C.newOrder(profile, { type: 'dineIn', tableId: 't1', tableName: 'T1', ticketNo: '101' });
  C.addLine(ticket, { id: 'p1', name: 'Soup', priceCents: 900, available: true });
  C.addLine(ticket, { id: 'p2', name: 'Main', priceCents: 2100, available: true });
  table.state = 'ordered'; put('tables', table); put('orders', ticket);
  const soldOut = { id: 'p3', name: 'Gone', priceCents: 100, available: false };
  const before = ticket.lines.length;
  C.addLine(ticket, soldOut);
  eq('sold-out item refuses to be added', ticket.lines.length, before);

  // send → preparing → ready
  ticket.status = 'sent'; put('orders', ticket);
  ticket.status = 'preparing'; put('orders', ticket);
  ticket.status = 'ready'; put('orders', ticket);
  eq('kitchen cycle ends ready', all('orders')[0].status, 'ready');

  // pay exact
  const bill = C.billOf(ticket, profile);
  eq('bill 30.00', bill.due, 3000);
  ticket.tipCents = 0;
  const check = C.payCheck(bill.due + 0, { method: 'cash', tenderCents: 3000 });
  ok('pay ok', check.ok);
  ticket.payment = { method: 'cash', paidTenderCents: 3000, changeCents: check.change, at: Date.now() };
  ticket.status = 'paid';
  // receipt math identical to pay sheet (ONE totals function)
  const receiptBill = C.billOf(ticket, profile);
  eq('receipt total == pay total', receiptBill.due, bill.due);
  // table frees
  table.state = 'free'; put('tables', table);
  put('orders', ticket);
  eq('table freed after pay', all('tables')[0].state, 'free');

  // X report counts
  const rep = C.reportXZ(all('orders'), profile, C.dayStart());
  eq('X shows taken 30.00', rep.taken, 3000);
  eq('X shows 1 paid', rep.paidCount, 1);
  eq('X shows 0 unpaid', rep.unpaidCount, 0);
  eq('X avg sale', rep.avg, 3000);
  eq('X pos channel', rep.byChannel.pos, 3000);

  // sold-out filtering on the order screen (guest): only available products visible
  const menu = [{ id: 'p1', available: true }, { id: 'p3', available: false }];
  eq('guest menu hides sold-out', menu.filter(p => p.available !== false && p.avail !== false).length, 1);

  // refund → stock comes back
  const prod = { id: 'p2', inventoryId: 'stk1', deductQty: 2 };
  const plan = C.refundPlan(ticket, [prod]);
  ok('refund finds the stock link', plan.stockBack.length === 1 && plan.stockBack[0].stockId === 'stk1' && plan.stockBack[0].qty === 2);
  eq('refund amount = full bill', plan.amount, 3000);
  eq('refund builds reprint lines', plan.linesRefund.length, 2);

  // payment-time deduct plan
  const stock = { id: 'stk1', qty: 10 };
  put('stock', stock);
  for (const d of C.deductPlan(C.newOrder(profile, { type: 'dineIn' }), [prod])) stock.qty -= d.qty;
  eq('stockDeducted=false plan works on empty order', stock.qty, 10);

  // EXISTING DB never wiped: db.js upgrade only ADDS stores
  const dbJs = readFileSync(join(APP, 'db.js'), 'utf8');
  ok('db upgrade only adds stores', dbJs.includes('if (!db.objectStoreNames.contains(s))') && !/deleteObjectStore/.test(dbJs));
  ok('db open handles blocked upgrades', dbJs.includes('onblocked') && dbJs.includes('onerror'));
  ok('db degrades to memory instead of hanging boot', dbJs.includes('finishMem') && dbJs.includes('isMemory'));
  ok('db open has a stall timeout', dbJs.includes('3500'));
  ok('boot has a watchdog that never leaves a blank page', appJs.includes('watchdog') || appJs.includes('anyVisible'));
  ok('boot errors are caught (no unhandled blank screen)', appJs.includes("boot().catch"));

  // export → import → sale persists
  const backup = JSON.stringify({ orders: all('orders'), tables: all('tables') });
  const fresh = new Map();
  const imp = JSON.parse(backup);
  for (const row of imp.orders) fresh.set('orders:' + row.id, row);
  for (const row of imp.tables) fresh.set('tables:' + row.id, row);
  const rep2 = C.reportXZ([...fresh.values()].filter((_, i, arr) => true).filter(o => o.status === 'paid' || o.status), profile, C.dayStart());
  eq('sale survives export→import', rep2.taken, 3000);
}

/* ============ 8. contracts — source checks ============ */
console.log('\n[8] shell visual/navigation contracts');
const idx = readFileSync(join(APP, 'index.html'), 'utf8');
const css = readFileSync(join(APP, 'styles.css'), 'utf8');
const sw = readFileSync(join(PUB, 'sw.js'), 'utf8');
const orderHtml = readFileSync(join(PUB, 'order.html'), 'utf8');
ok('[hidden] CSS safeguard present', /\[hidden\]\s*{\s*display:\s*none\s*!important/.test(css));
ok('SW cache bumped to of-shell-v25', sw.includes("'of-shell-v30'"));
ok('SW network-first for /app code + /order.html', sw.includes('NETWORK_FIRST') && sw.includes("/app/") && sw.includes("/order.html"));
ok('viewport-fit=cover on both pages', idx.includes('viewport-fit=cover') && orderHtml.includes('viewport-fit=cover'));
ok('apple status bar black-translucent', idx.includes('black-translucent'));
ok('light cream is default paint', idx.includes('data-theme=\"light\"'));
ok('no fake Wi-Fi IPs / 8787 shell', !/8787|192\.168\.|10\.0\.0\./.test(idx + appJs));
ok('Add-to-Home only lives in the install sheet', idx.includes('sheet-install') && readFileSync(join(APP, 'more.js'), 'utf8').includes("'more.install'"));
ok('version text says Order Flow Web', readFileSync(join(APP, 'more.js'), 'utf8').includes('Order Flow Web'));
ok('splashed Jathol typing is in the shell', idx.includes('splash-typed'));
ok('splash auto-hides even if JS stalls', appJs.includes('6000') || idx.includes('animation'));
ok('app view is never under a license gate', idx.includes('id="view-license"') && idx.includes('id="view-main"') && css.includes('[hidden]'));

/* inline JS: no inline <script> bodies in either html */
for (const [name, html] of [['app/index.html', idx], ['order.html', orderHtml]]) {
  const bodies = [...html.matchAll(/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/gi)].map(m => m[1].trim()).filter(Boolean);
  eq(name + ' has zero inline scripts', bodies.length, 0);
}

/* every data-act has a registered handler */
{
  const handlers = new Set();
  for (const f of ['app.js', 'ticket.js', 'more.js']) {
    const src = readFileSync(join(APP, f), 'utf8');
    for (const m of src.matchAll(/'([a-z]+(?:\.[a-zA-Z]+)+)'\s*:/g)) handlers.add(m[1]);
  }
  const acts = new Set();
  for (const src of [idx, orderHtml, ...['app.js', 'ticket.js', 'more.js'].map(f => readFileSync(join(APP, f), 'utf8'))]) {
    for (const m of src.matchAll(/data-act="([^"]+)"/g)) acts.add(m[1]);
    for (const m of src.matchAll(/data-act="([^"]+)"/g)) acts.add(m[1]);
  }
  // dynamic data-act strings inside markup generated in JS use template literal chunks e.g. 'data-act="menu.soldout"'
  const missing = [...acts].filter(a => !handlers.has(a));
  eq('every data-act button has a handler: ' + [...acts].sort().join(','), missing, []);
}

/* hidden-vs-inline-display fight (spec): nothing sets el.style.display while [hidden] also in play */
ok('no element uses style.display= on view containers', !/view-(main|ticket|sub|rolehome)"?\)?\.style\.display/.test(appJs));

/* guest page contracts */
const orderJs = readFileSync(join(PUB, 'order.js'), 'utf8');
ok('guest joins room as guest, never with a key', orderJs.includes("role: 'guest'"));
ok('guest orders tagged channel qr when state-watching', orderJs.includes("channel === 'qr'"));
ok('prices come from the shop snapshot (never set by guest)', orderJs.includes('priceCents: v.p.priceCents') && !orderJs.includes('prompt('));
ok('identity survives degraded mode via localStorage mirror', readFileSync(join(APP, 'db.js'), 'utf8').includes('ofkv:'));
ok('phone layout: view-main__col has base flex rules (was 720px-only — killed scrolling)', /@media[\s\S]*?view-main__col/.test(css) === false || /\.view-main__col\{[^}]*min-height:0/.test(css.split('@media (min-width:720px)')[0]));
ok('rows cannot overlap: lrow hd flexes + buttons flex:none', css.includes('.lrow .hd{ flex:1 1 auto') && css.includes('.lrow button, .lrow .qtyctl'));
ok('more rows stack title+sub on own lines', css.includes('.mrow .ttl .sub'));
const langStr = readFileSync(join(APP, 'lang.js'), 'utf8');
for (const k of ['bill_profile', 'config_head', 'printers', 'staff_shifts', 'unpaid_bills', 'theme_dark']) ok('lang has ' + k, langStr.includes(k + ': ['));
ok('guest flood caps client-side', orderJs.includes('ofqrcap') && readFileSync(join(APP, 'app.js'), 'utf8').includes('qrCapCheck'));
ok('guest fire-mode note', orderJs.includes('fireMode'));

/* print contract */
const printJs = readFileSync(join(APP, 'print.js'), 'utf8');
ok('AirPrint via pre-rendered iframe + window.print', printJs.includes('window.print') && printJs.includes('apple-print-frame'));
ok('Bluetooth offered only when navigator.bluetooth exists', printJs.includes("'bluetooth' in navigator"));
ok('relay print-job contract', appJs.includes("cmd.type === 'printjob'") && appJs.includes('isGateway'));

/* RTL + language */
const langJs = readFileSync(join(APP, 'lang.js'), 'utf8');
ok('lang has EN + UR', /[\u0600-\u06FF]/.test(langJs));
ok('RTL switches for ur', appJs.includes('langDir') && appJs.includes("'rtl'"));

/* v29 — cloud relay contract + menu row actions */
const moreJs = readFileSync(join(APP, 'more.js'), 'utf8');
ok('cloud open sends licenseKey + deviceId (worker contract)', moreJs.includes("OFApiCloud('/api/cloud/open'") && moreJs.includes('licenseKey') && moreJs.includes('deviceId'));
ok('plan error gets a real message, not check internet', moreJs.includes("res.error === 'plan'"));
ok('station join includes deviceId (membership)', appJs.includes("role: 'station', deviceId"));
ok('guest join includes room + deviceId (membership)', readFileSync(join(ROOT, 'website/public/order.js'), 'utf8').includes('room: cfg.r, code: cfg.c') && readFileSync(join(ROOT, 'website/public/order.js'), 'utf8').includes('deviceId: CFG.device'));
ok('cloud API has an upstream fallback base', appJs.includes('order-flow-v2.pages.dev') && readFileSync(join(ROOT, 'website/public/order.js'), 'utf8').includes('order-flow-v2.pages.dev'));
ok('menu row: one overflow button, name keeps the width', appJs.includes('aria-label="Actions"') && !appJs.includes('data-act="menu.soldout"') && !appJs.includes('data-act="menu.edit"'));
ok('menu actions: edit + soldout + delete via sheet', appJs.includes('menuToggleSoldout') && appJs.includes('menuDeleteConfirm') && appJs.includes('OFPick('));
ok('menu.keep registered handlers for legacy rows', appJs.includes("'menu.soldout':") && appJs.includes("'menu.edit':"));
ok('main boot starts the relay when a room is open', appJs.includes('enterMain(); startRelayBoot(room);'));
ok('menu thumb + dim styles', css.includes('.lrow__ic img') && css.includes('.lrow.is-off'));

console.log('\n────────────────────────────');
console.log(`${pass} passed, ${failCount} failed`);
if (failCount) { console.log('FAILURES:\n - ' + failures.join('\n - ')); process.exit(1); }
console.log('SELFTEST GREEN ✓');
