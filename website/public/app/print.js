// Order Flow Web — Printing: 3 layers
// 1) Android: Web Bluetooth / WebUSB raw ESC/POS (Chrome)
// 2) iOS/macOS + any: Apple built-in printing (AirPrint) via window.print() — the iPhone Bluetooth-easy path
// 3) Relay-print: queue job → cloud relay → a station with a real printer executes it
//
// Apple gate: Web Bluetooth is *not* available on iOS Safari at all. The only
// zero-driver path Apple allows is the system print dialog (AirPrint).
// We therefore expose a dedicated "Print with Apple" button that renders
// the receipt into a hidden print frame and calls window.print().
// User picks their AirPrint / Bluetooth-via-AirPrint printer once, then it
// prints instantly next time. For non-AirPrint Bluetooth star/Bixolon,
// the Relay-print layer covers it (iPhone sends job to an Android print station).

const PRINT_CSS = `
  @media print {
    @page { size: 80mm auto; margin: 0; }
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .no-print { display:none !important; }
  }
  .receipt { width: 72mm; margin: 0 auto; font-family: ui-monospace, Menlo, monospace; color:#111; }
  .r-head { text-align:center; border-bottom: 1.5px dashed #111; padding: 10px 0 8px; }
  .r-head b { font-size: 16px; display:block; }
  .r-meta { font-size: 11px; color:#444; margin-top:4px; }
  .r-line { display:flex; justify-content:space-between; font-size: 12px; padding: 3px 0; border-bottom: 1px dotted #ccc; }
  .r-total { display:flex; justify-content:space-between; font-weight:800; font-size:14px; border-top:2px solid #111; margin-top:8px; padding-top:6px; }
  .r-foot { text-align:center; font-size:10px; color:#666; margin-top:10px; border-top: 1.5px dashed #111; padding-top:8px; }
`;

// Build printable HTML for an order
function receiptHTML(order, shop){
  const s = shop||{name:'Order Flow', phone:'', addr:''};
  const lines = (order.items||[]).map(it=> `<div class="r-line"><span>${esc(it.name)} × ${it.qty}</span><span>${money(it.total)}</span></div>`).join('');
  return `<!doctype html><html><head><meta charset="utf-8"><style>${PRINT_CSS}</style></head><body>
    <div class="receipt">
      <div class="r-head"><b>${esc(s.name)}</b><div class="r-meta">${esc(s.addr||'')} ${esc(s.phone||'')}</div><div class="r-meta">${new Date().toLocaleString()} · #${esc(order.id||'')}</div></div>
      ${lines || '<div class="r-line"><span>No items</span><span>—</span></div>'}
      <div class="r-total"><span>TOTAL</span><span>${money(order.total||0)}</span></div>
      <div class="r-foot">${esc(s.footer||'Thank you — come again')}</div>
    </div>
    <script>window.onload=()=>{ setTimeout(()=>{ window.print(); }, 120); window.onafterprint=()=>{ try{ window.close(); }catch{} }; }<\/script>
  </body></html>`;
}
function money(n){ try{ return 'RM ' + Number(n).toFixed(2); }catch{ return String(n); } }
function esc(s){ return String(s||'').replace(/[&<>]/g,c=> ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }

// Apple built-in: open hidden iframe and print — works in Safari PWA standalone
// since iOS 7. On iPhone this shows the system printer picker (AirPrint
// including Bluetooth printers that expose AirPrint). No Web Bluetooth needed.
function printViaApple(order, shop){
  const html = receiptHTML(order, shop);
  // Use an iframe so PWA stays alive after print
  let frame = document.getElementById('apple-print-frame');
  if(!frame){
    frame = document.createElement('iframe');
    frame.id = 'apple-print-frame';
    frame.style.cssText = 'position:fixed;left:-9999px;top:0;width:72mm;height:0;border:0;';
    frame.setAttribute('aria-hidden','true');
    document.body.appendChild(frame);
  }
  const doc = frame.contentDocument || frame.contentWindow.document;
  doc.open(); doc.write(html); doc.close();
  // Focus then print from the frame context (required for iOS standalone)
  try{
    frame.contentWindow.focus();
    // iOS needs a user gesture; this function IS the gesture handler, so call directly
    const doPrint = () => frame.contentWindow.print();
    if (frame.contentDocument.readyState === 'complete') doPrint();
    else frame.onload = doPrint;
  }catch(e){
    // Fallback: open new tab
    const w = window.open('', '_blank');
    if(w){ w.document.open(); w.document.write(html); w.document.close(); }
    else { alert('Allow pop-ups to print. You can also Save as PDF then print from Files.'); }
  }
}

// Android: raw ESC/POS via Web Bluetooth (Chromium only)
async function printViaBluetooth(order, shop){
  if(!('bluetooth' in navigator)){
    throw new Error('Web Bluetooth not available on this iPhone — use Print with Apple or Relay-print instead.');
  }
  // Filter for common thermal services — generic single-service fallback
  const device = await navigator.bluetooth.requestDevice({
    acceptAllDevices: true,
    optionalServices: ['000018f0-0000-1000-8000-00805f9b34fb','49535343-fe7d-4ae5-8fa9-9fafd205e455','0000ae00-0000-1000-8000-00805f9b34fb']
  });
  const server = await device.gatt.connect();
  // Try to find a writable characteristic — brute-force common UUIDs
  const services = await server.getPrimaryServices();
  let writable = null;
  for(const svc of services){
    const chars = await svc.getCharacteristics();
    for(const ch of chars){ if(ch.properties.write || ch.properties.writeWithoutResponse){ writable = ch; break; } }
    if(writable) break;
  }
  if(!writable) throw new Error('Printer connected but no writable characteristic found.');
  const bytes = buildEscPos(order, shop);
  // chunk 512 bytes (MTU limit)
  const CHUNK=180;
  for(let i=0;i<bytes.length;i+=CHUNK){
    const chunk = bytes.slice(i, i+CHUNK);
    try{ await writable.writeValueWithoutResponse(chunk); } catch { await writable.writeValue(chunk); }
    await new Promise(r=> setTimeout(r, 12));
  }
  try{ device.gatt.disconnect(); }catch{}
}

function buildEscPos(order, shop){
  const enc = new TextEncoder();
  const ESC='\x1B', GS='\x1D';
  let out='';
  out+= ESC+'@'; // init
  out+= ESC+'a'+'\x01' + (shop?.name||'Order Flow') + '\n';
  out+= ESC+'a'+'\x00' + (shop?.addr||'') + '\n';
  out+= '-'.repeat(32) + '\n';
  for(const it of (order.items||[])){
    const line = `${it.name} x${it.qty}`.slice(0,22).padEnd(22,' ') + money(it.total).padStart(10,' ');
    out+= line + '\n';
  }
  out+= '-'.repeat(32) + '\n';
  out+= GS+'!'+'\x11' + 'TOTAL '+ money(order.total||0) + '\n';
  out+= GS+'!'+'\x00';
  out+= '\n\n' + (shop?.footer||'Thank you') + '\n\n\n';
  out+= GS+'V'+'\x42'+'\x00'; // partial cut
  out+= ESC+'p'+'\x00'+'\x19'+'\xFA'; // drawer kick (if present)
  return enc.encode(out);
}

// Relay-print queue: when iPhone has no printer, queue job for a print station
// Print station = any Main/Station that toggled "Act as print gateway" (stored in kv)
async function queueRelayPrint(order, shop){
  const job = {id:'pj-'+Date.now(), order, shop, createdAt: Date.now(), status:'pending'};
  await idbPut('printQueue', job);
  // also push via cloud relay immediately if available
  try{ if(window.OFRelay && window.OFRelay.sendPrintJob) await window.OFRelay.sendPrintJob(job); }catch{}
  return job;
}

// Public: one button handler that picks best available path and explains fallback
async function handlePrint(order, shop, opts={}){
  const ua = navigator.userAgent;
  const isIOS = /iPad|iPhone|iPod/.test(ua);
  const canBLE = 'bluetooth' in navigator;
  // If user explicitly chose Apple, honor it
  if(opts.via==='apple') return printViaApple(order, shop);
  if(opts.via==='bluetooth') return printViaBluetooth(order, shop);
  if(opts.via==='relay') return queueRelayPrint(order, shop);
  // Auto: iOS → Apple, Android with BLE → offer BLE first then Apple
  if(isIOS) return printViaApple(order, shop);
  if(canBLE){
    // try BLE, fall back to Apple dialog on cancel/fail
    try{ await printViaBluetooth(order, shop); return; } catch(e){ if(String(e).includes('User cancelled')||String(e).includes('cancel')) throw e; return printViaApple(order, shop); }
  }
  return printViaApple(order, shop);
}
