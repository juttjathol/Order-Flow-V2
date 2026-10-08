/* ============================================================
   ORDER FLOW POS — print.js
   AirPrint first (iPhone path): receipt pre-rendered into a
   hidden iframe and window.print() fired synchronously inside
   the tap handler. Web Bluetooth ESC/POS offered ONLY when
   navigator.bluetooth exists (never on iPhone). Relay print:
   cmd {type:'printjob'} to a station flagged as print gateway.
   ============================================================ */
(function () {
'use strict';
const C = OFCore;
const esc = s => String(s ?? '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const fmt = (c, cur) => C.fmtCents(c == null ? 0 : c, cur || 'RM');

const RECEIPT_CSS = `
  @page { size: 80mm auto; margin: 0; }
  body { -webkit-print-color-adjust: exact; print-color-adjust: exact; font-family: ui-monospace, Menlo, monospace; color:#111; margin: 0; }
  .receipt { width: 72mm; margin: 0 auto; padding: 4mm 0 10mm; }
  .r-copy { page-break-after: always; }
  .r-copy:last-child { page-break-after: auto; }
  .r-head { text-align:center; border-bottom: 1.5px dashed #111; padding: 8px 0; }
  .r-head b { font-size: 16px; display:block; }
  .r-meta { font-size: 11px; color:#444; margin-top:3px; }
  .r-sub { font-size: 10.5px; color:#555; text-align:center; padding: 3px 0; }
  .r-line { display:flex; justify-content:space-between; gap:8px; font-size: 12px; padding: 3px 0; border-bottom: 1px dotted #ccc; }
  .r-note { font-size:10.5px; color:#555; padding-left:10px; }
  .r-big { font-size: 14px; font-weight: 800; padding: 4px 0; }
  .r-row { display:flex; justify-content:space-between; font-size: 12px; padding: 2px 0; }
  .r-total { display:flex; justify-content:space-between; font-weight:800; font-size:15px; border-top:2px solid #111; margin-top:8px; padding-top:6px; }
  .r-paid { text-align:center; font-weight:900; font-size:16px; letter-spacing:2px; margin-top:6px; }
  .r-foot { text-align:center; font-size:10px; color:#666; margin-top:10px; border-top: 1.5px dashed #111; padding-top:8px; }
  .k-item { font-size: 15px; font-weight: 800; padding: 5px 0; border-bottom: 1px dashed #999; }
  .k-note { font-size: 12px; padding-left: 12px; color:#333; }
`;

function shop() { const s = window.SHOP_REF ? window.SHOP_REF() : null; return (s && s.profile) || { name: 'Order Flow', currency: 'RM', receiptFoot: 'Thank you — please come again' }; }
function linesOf(order) { return order.lines || (order.items || []).map(i => ({ name: i.name, qty: i.qty || 1, priceCents: C.cents(i.price != null ? i.price : ((i.total || 0) / (i.qty || 1))), mods: i.mods || [], notes: i.notes || '' })); }
function whereTxt(order) { return order.tableName ? 'Table ' + order.tableName : (order.type === 'delivery' ? 'DELIVERY' : order.type === 'takeaway' ? 'TAKEAWAY' : order.type === 'retail' ? 'RETAIL' : order.channel === 'qr' ? '>>> QR ' + (order.tableName || '') + ' <<<' : 'Ticket #' + (order.ticketNo || '')); }

function receiptOne(order, opts) {
  const s = shop(), cur = s.currency || 'RM';
  const b = C.billOf(order, s);
  const lines = linesOf(order);
  const head = `<div class="r-head"><b>${esc(s.receiptHead || s.name)}</b><div class="r-meta">${esc(s.address || '')} ${esc(s.phone || '')}</div><div class="r-meta">${new Date(order.createdAt || Date.now()).toLocaleString()} · #${esc(String(order.ticketNo || order.id || ''))} · ${esc(order.staffName || order.createdBy || 'Main')}</div></div>`;
  const sub = `<div class="r-sub">${esc(whereTxt(order))}${order.persons ? ' · ' + order.persons + ' guest(s)' : ''}${order.customerId ? ' · ' + esc(order.customerName || order.customerId) : ''}</div>`;
  let body = '';
  if (opts.type === 'kitchen') {
    for (const l of lines) {
      body += `<div class="k-item">${esc(l.name)} × ${l.qty}</div>`;
      for (const m of (l.mods || [])) body += `<div class="k-note">+ ${esc(m)}</div>`;
      if (l.notes) body += `<div class="k-note">✎ ${esc(l.notes)}</div>`;
    }
    return head + sub + body + `<div class="r-foot">KITCHEN COPY · ${new Date(order.sentAt || Date.now()).toLocaleTimeString()}</div>`;
  }
  if (opts.type === 'refund') {
    for (const l of (order.refundOf || lines)) body += `<div class="r-line"><span>↩ ${esc(l.name)} × ${l.qty}</span><span>${fmt((l.priceCents || 0) * (l.qty || 0), cur)}</span></div>`;
    return head + sub + body + `<div class="r-paid">REFUND</div><div class="r-foot">${esc(s.receiptFoot || '')}</div>`;
  }
  for (const l of lines) {
    const each = C.linePriceCents(l);
    body += `<div class="r-line"><span>${esc(l.name)}</span><span>${l.qty} × ${fmt(each, cur)}</span></div>`;
    for (const m of (l.mods || [])) body += `<div class="r-note">+ ${esc(m)}</div>`;
    if (l.notes) body += `<div class="r-note">✎ ${esc(l.notes)}</div>`;
  }
  let rows = `<div class="r-row"><span>Subtotal</span><span>${fmt(b.subTotal, cur)}</span></div>`;
  if (b.discount) rows += `<div class="r-row"><span>Discount</span><span>−${fmt(b.discount, cur)}</span></div>`;
  if (b.service) rows += `<div class="r-row"><span>Service ${order.serviceRate != null ? order.serviceRate : s.svc}%</span><span>+${fmt(b.service, cur)}</span></div>`;
  for (const t of b.taxes) rows += `<div class="r-row"><span>${esc(t[0])}</span><span>+${fmt(t[1], cur)}</span></div>`;
  if (order.tipCents) rows += `<div class="r-row"><span>Tip</span><span>+${fmt(order.tipCents, cur)}</span></div>`;
  const total = b.due + (order.tipCents || 0);
  let foot = `<div class="r-total"><span>TOTAL</span><span>${fmt(total, cur)}</span></div>`;
  if (opts.type !== 'bill') {
    const p = order.payment;
    if (p) {
      const mname = { cash: 'CASH', card: 'CARD', wallet: 'WALLET', other: 'OTHER', complimentary: 'COMPLIMENTARY' }[p.method] || 'PAID';
      foot += `<div class="r-row"><span>Paid by ${mname}</span><span>${fmt(total, cur)}</span></div>`;
      if (p.method === 'cash') {
        foot += `<div class="r-row"><span>Tendered</span><span>${fmt(p.paidTenderCents != null ? p.paidTenderCents : (order.tenderCents || total), cur)}</span></div>`;
        foot += `<div class="r-row"><span>Change</span><span>${fmt(p.changeCents != null ? p.changeCents : (order.changeCents || 0), cur)}</span></div>`;
      }
      if (order.splitPayment) foot += `<div class="r-row"><span>Split: ${esc(order.splitPayment.method1)}/${esc(order.splitPayment.method2)}</span><span>${fmt(order.splitPayment.amount1Cents, cur)} / ${fmt(order.splitPayment.amount2Cents, cur)}</span></div>`;
      foot += `<div class="r-paid">PAID ✓</div>`;
    }
  }
  if (s.payQr && opts.type !== 'kitchen') foot += `<div style="text-align:center;margin-top:6px"><img src="${esc(s.payQr)}" width="120"/></div>`;
  return head + sub + body + rows + foot + `<div class="r-foot">${esc(s.receiptFoot || '')}${s.tagline ? ' · ' + esc(s.tagline) : ''}</div>`;
}

function htmlDoc(order, opts) {
  const copies = Math.max(1, Math.min(3, Number(opts.copies || shop().copies) || 1));
  let pages = '';
  for (let i = 0; i < copies; i++) pages += `<div class="r-copy receipt">${receiptOne(order, opts)}</div>`;
  return `<!doctype html><html><head><meta charset="utf-8"><style>${RECEIPT_CSS}</style></head><body>${pages}<script>window.onload=function(){ setTimeout(function(){ window.print(); }, 100); window.onafterprint=function(){ try{ window.close(); }catch(e){} }; }<\/script></body></html>`;
}

/* plain-text for share / WhatsApp */
function receiptText(order) {
  const s = shop(), cur = s.currency || 'RM';
  const b = C.billOf(order, s);
  const out = [s.receiptHead || s.name, whereTxt(order) + ' · #' + (order.ticketNo || ''), '--------------------------------'];
  for (const l of linesOf(order)) out.push(l.qty + ' x ' + l.name);
  out.push('--------------------------------', 'TOTAL  ' + fmt(b.due + (order.tipCents || 0), cur));
  if (order.payment) out.push((order.payment.method || 'paid').toUpperCase() + ' — PAID');
  out.push(s.receiptFoot || 'Thank you');
  return out.join('\n');
}

function printViaApple(order, opts) {
  const html = htmlDoc(order, opts);
  let frame = document.getElementById('apple-print-frame');
  if (!frame) {
    frame = document.createElement('iframe');
    frame.id = 'apple-print-frame';
    frame.style.cssText = 'position:fixed;left:-9999px;top:0;width:76mm;height:10mm;border:0;';
    frame.setAttribute('aria-hidden', 'true');
    document.body.appendChild(frame);
  }
  const doc = frame.contentDocument || frame.contentWindow.document;
  doc.open(); doc.write(html); doc.close();
  try {
    frame.contentWindow.focus();
    const go = () => frame.contentWindow.print();
    if (doc.readyState === 'complete') go(); else frame.onload = go;
  } catch (e) {
    const w = window.open('', '_blank');
    if (w) { w.document.open(); w.document.write(html); w.document.close(); }
  }
}

async function printViaBluetooth(order, opts) {
  if (!('bluetooth' in navigator)) throw new Error('Web Bluetooth is not available on this device — use AirPrint.');
  const device = await navigator.bluetooth.requestDevice({
    acceptAllDevices: true,
    optionalServices: ['000018f0-0000-1000-8000-00805f9b34fb', '49535343-fe7d-4ae5-8fa9-9fafd205e455', '0000ae00-0000-1000-8000-00805f9b34fb']
  });
  const server = await device.gatt.connect();
  const services = await server.getPrimaryServices();
  let writable = null;
  for (const svc of services) {
    const chars = await svc.getCharacteristics();
    for (const ch of chars) if (ch.properties.write || ch.properties.writeWithoutResponse) { writable = ch; break; }
    if (writable) break;
  }
  if (!writable) throw new Error('Printer connected but no writable characteristic found.');
  const bytes = buildEscPos(order);
  for (let i = 0; i < bytes.length; i += 180) {
    const chunk = bytes.slice(i, i + 180);
    try { await writable.writeValueWithoutResponse(chunk); } catch { await writable.writeValue(chunk); }
    await new Promise(r => setTimeout(r, 12));
  }
  try { device.gatt.disconnect(); } catch {}
}
function buildEscPos(order) {
  const s = shop(), cur = s.currency || 'RM';
  const b = C.billOf(order, s);
  const enc = new TextEncoder();
  let out = '\x1B@' + '\x1Ba\x01' + (s.name || 'Order Flow') + '\n' + '\x1Ba\x00' + '-'.repeat(32) + '\n';
  for (const l of linesOf(order)) out += (l.name + ' x' + l.qty).slice(0, 22).padEnd(22) + fmt(C.linePriceCents(l) * l.qty, cur).padStart(10) + '\n';
  out += '-'.repeat(32) + '\n' + '\x1D!\x11' + 'TOTAL ' + fmt(b.due + (order.tipCents || 0), cur) + '\n' + '\x1D!\x00' + '\n\n' + (s.receiptFoot || '') + '\n\n\n' + '\x1DV\x42\x00';
  return enc.encode(out);
}

/* public — call synchronously inside the user's tap */
window.OFPrintReceipt = function (order, opts) {
  opts = opts || {};
  if (opts.via === 'bluetooth') { printViaBluetooth(order, opts).catch(() => printViaApple(order, opts)); return; }
  printViaApple(order, opts);
};
window.OFReceiptText = receiptText;
window.OFPrintViaBluetooth = printViaBluetooth;
})();
