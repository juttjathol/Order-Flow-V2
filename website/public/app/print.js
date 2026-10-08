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

function printHtml(order, opts) {
  // honor the 58/80mm paper picker (the CSS ships 80mm by default)
  const paper = String(shop().paper) === '58' ? 58 : 80;
  const css = paper === 80 ? RECEIPT_CSS : RECEIPT_CSS.replace(/80mm/g, '58mm').replace(/72mm/g, '50mm');
  const copies = Math.max(1, Math.min(3, Number(opts.copies || shop().copies) || 1));
  let pages = '';
  for (let i = 0; i < copies; i++) pages += `<div class="r-copy receipt">${receiptOne(order, opts)}</div>`;
  return `<style>${css}</style>${pages}`;
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
  // Safari-tab path: inject the receipt into THIS document, flip
  // is-printing, and let @media print show only the receipt, then
  // window.print() inside the tap (hidden-iframe printing is silently
  // ignored by iOS, and standalone gets printViaShare instead).
  const inner = printHtml(order, opts);
  let host = document.getElementById('of-print-area');
  if (!host) {
    host = document.createElement('div');
    host.id = 'of-print-area';
    host.setAttribute('aria-hidden', 'true');
    document.body.appendChild(host);
  }
  host.innerHTML = inner;
  document.body.classList.add('is-printing');
  window.print();
  const done = () => { document.body.classList.remove('is-printing'); host.innerHTML = ''; };
  window.addEventListener('afterprint', done, { once: true });
  setTimeout(done, 8000);
}

/* ---- minimal one-page receipt PDF (Courier, ASCII) — no library ----
   Used for the SHARE path below: iOS can print any shared PDF from the
   native share sheet, which is the ONLY print mechanism that always works
   inside a home-screen (standalone) web app. */
function escPdf(s) { return String(s).replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)').replace(/[^\x20-\x7E]/g, '?'); }
function buildReceiptPdf(order, opts) {
  const s = shop();
  const paper = String(s.paper) === '58' ? 58 : 80;
  const wPt = Math.round(paper / 25.4 * 72);
  let text;
  if (opts && opts.type === 'kitchen') {
    text = (s.receiptHead || s.name) + '\n' + whereTxt(order) + ' — KITCHEN\n--------------------------------\n'
      + linesOf(order).map(l => l.qty + ' x ' + l.name + (l.notes ? '  (' + l.notes + ')' : '')).join('\n')
      + '\n--------------------------------\nKITCHEN COPY';
  } else {
    text = receiptText(order);
  }
  const lines = text.split('\n');
  const fontSize = 9, lead = 11, pad = 14;
  const hPt = pad * 2 + lines.length * lead + 6;
  let content = 'BT /F1 ' + fontSize + ' Tf ' + pad + ' ' + (hPt - pad - fontSize) + ' Td ' + lead + ' TL\n';
  for (const ln of lines) content += '(' + escPdf(ln) + ') Tj T*\n';
  content += 'ET';
  const objs = [];
  objs[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objs[2] = '<< /Type /Pages /Kids [3 0 R] /Count 1 >>';
  objs[3] = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' + wPt + ' ' + hPt + '] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>';
  objs[4] = '<< /Length ' + content.length + ' >>\nstream\n' + content + '\nendstream';
  objs[5] = '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>';
  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  for (let i = 1; i <= 5; i++) { offsets[i] = pdf.length; pdf += i + ' 0 obj\n' + objs[i] + '\nendobj\n'; }
  const xref = pdf.length;
  pdf += 'xref\n0 6\n0000000000 65535 f \n';
  for (let i = 1; i <= 5; i++) pdf += String(offsets[i]).padStart(10, '0') + ' 00000 n \n';
  pdf += 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n' + xref + '\n%%EOF';
  return new TextEncoder().encode(pdf);
}
/* Standalone-PWA printing: share the PDF — iOS share sheet has Print built in */
async function printViaShare(order, opts) {
  try {
    const bytes = buildReceiptPdf(order, opts);
    const file = new File([bytes], 'receipt-' + ((opts && opts.type) || 'r') + '-' + (order.ticketNo || order.id || 'order') + '.pdf', { type: 'application/pdf' });
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      await navigator.share({ files: [file], title: 'Order Flow — receipt' });
      return true;
    }
  } catch (e) { if (e && e.name === 'AbortError') return true; }
  if (!printViaTab(order, opts)) printViaApple(order, opts);
  return false;
}

/* The every-environment escape hatch: receipt as a real browser page whose
   own script auto-prints it (works in standalone PWAs, old iOS, webviews).
   Called inside a user tap so the popup is not blocked. */
function printViaTab(order, opts) {
  const w = window.open('', '_blank');
  if (!w) return false;
  w.document.open();
  w.document.write('<!doctype html><html><head><meta charset="utf-8"><title>Order Flow — receipt</title></head><body>' + printHtml(order, opts) +
    '<script>window.onload=function(){setTimeout(function(){window.print();},250);};<\/script></body></html>');
  w.document.close();
  return true;
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
  if (navigator.standalone === true) { printViaShare(order, opts); return; } // home-screen PWA: share sheet → Print
  printViaApple(order, opts);
};
window.OFShareReceiptPdf = printViaShare;
window.OFReceiptText = receiptText;
window.OFPrintViaBluetooth = printViaBluetooth;
window.OFPrintReceiptInTab = printViaTab;
})();
