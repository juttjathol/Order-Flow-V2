// Order Flow Web POS — Main *or* Station (iPhone can be either)
// Replica: tables/menu/kitchen/stock + IndexedDB + cloud relay + relay-print + AirPrint
const $ = (s, r=document)=> r.querySelector(s);
const $$ = (s, r=document)=> [...r.querySelectorAll(s)];

let ROLE = null; // 'main' | 'station'
let RELAY = null;
let CUR_ORDER = null;
let HOT = true;

// device id
async function deviceId(){
  let id = await kvGet('deviceId', null);
  if(!id){ id = 'web-'+Math.random().toString(36).slice(2,10)+'-'+Date.now().toString(36); await kvSet('deviceId', id); }
  return id;
}

// qrcode tiny (no lib) — use canvas text fallback + draw simple QR via api if online
function drawQR(canvas, text){
  const ctx = canvas.getContext('2d');
  ctx.fillStyle='#fff'; ctx.fillRect(0,0,canvas.width,canvas.height);
  // light QR placeholder: if online, fetch QR image and draw; else write text
  const img = new Image();
  img.crossOrigin='anonymous';
  img.onload=()=>{
    ctx.drawImage(img,0,0,canvas.width,canvas.height);
    // overlay small logo dot
    ctx.fillStyle='#163E2E'; ctx.beginPath(); ctx.arc(canvas.width/2, canvas.height/2, 14, 0, Math.PI*2); ctx.fill();
    ctx.fillStyle='#FAF7F2'; ctx.font='12px system-ui'; ctx.textAlign='center'; ctx.fillText('OF', canvas.width/2, canvas.height/2+4);
  };
  img.onerror=()=>{
    ctx.fillStyle='#111'; ctx.font='12px monospace'; ctx.textAlign='center';
    wrapText(ctx, text, canvas.width/2, 18, canvas.width-20, 12);
    ctx.fillStyle='#5C6E64'; ctx.fillText('(no image — use Copy text)', canvas.width/2, canvas.height-10);
  };
  const enc = encodeURIComponent(text);
  img.src = 'https://api.qrserver.com/v1/create-qr-code/?size=220x220&data='+enc;
}
function wrapText(ctx, text, x, y, maxW, lh){
  const words = text.split(''); let line=''; // char wrap for base64
  for(let i=0;i<text.length;i++){
    const test = line + text[i];
    if(ctx.measureText(test).width > maxW && line){ ctx.fillText(line, x, y); line=text[i]; y+=lh; } else line=test;
  }
  if(line) ctx.fillText(line,x,y);
}

// Relay client (web port of cloud_relay.dart) — AES-GCM with SubtleCrypto
const RELAY_BASE = 'https://order-flow-v2.pages.dev';
async function sha256Hex(s){ const d=await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)); return [...new Uint8Array(d)].map(b=>b.toString(16).padStart(2,'0')).join(''); }
function b64uEncode(buf){ return btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,''); }
function b64uDecode(s){ s=s.replace(/-/g,'+').replace(/_/g,'/'); while(s.length%4) s+='='; return Uint8Array.from(atob(s), c=>c.charCodeAt(0)); }
async function deriveKey(secret){
  const raw = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('orderflow-cloud|v1|'+secret));
  return crypto.subtle.importKey('raw', raw, {name:'AES-GCM'}, false, ['encrypt','decrypt']);
}
async function encryptString(key, plain){
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const enc = await crypto.subtle.encrypt({name:'AES-GCM', iv}, key, new TextEncoder().encode(plain));
  return b64uEncode(iv) + '.' + b64uEncode(enc);
}
async function decryptString(key, blob){
  const dot = blob.indexOf('.'); if(dot<=0) return null;
  try{
    const iv = b64uDecode(blob.slice(0,dot));
    const data = b64uDecode(blob.slice(dot+1));
    const dec = await crypto.subtle.decrypt({name:'AES-GCM', iv}, key, data);
    return new TextDecoder().decode(dec);
  }catch{ return null; }
}
function pairingEncode(room, code, secret, base){
  return 'OF1:'+room+':'+code+':'+secret+':'+b64uEncode(new TextEncoder().encode(base));
}
function pairingDecode(raw){
  const p = raw.trim().split(':'); if(p.length!==5 || p[0]!=='OF1') return null;
  try{ const url = new TextDecoder().decode(b64uDecode(p[4])); if(!url.startsWith('https://')) return null; return {room:p[1], code:p[2], secret:p[3], base:url}; }catch{ return null; }
}

class Relay {
  constructor({room, secret, base, deviceId, isMain}){
    this.room=room; this.secret=secret; this.base=base||RELAY_BASE; this.deviceId=deviceId; this.isMain=isMain;
    this.key=null; this.cursor=0; this.timer=null; this.hot=HOT; this.running=false; this.fails=0;
    this.onState=null; this.onCmd=null; this.onPrintJob=null;
    this._chunkBuf=null;
  }
  async init(){ this.key = await deriveKey(this.secret); }
  start(){
    this.running=true;
    this.timer = setInterval(()=> this.tick(), this.hot ? 1200 : 30000);
    this.tick();
  }
  stop(){ this.running=false; if(this.timer) clearInterval(this.timer); }
  setHot(v){ if(v===this.hot) return; this.hot=v; HOT=v; this.stop(); this.start(); }
  async tick(){
    try{ await this.pull(); await this.pushCheck(); this.fails=0; $('#sync-state') && ($('#sync-state').textContent = this.hot ? 'Hot — live (1.2s)' : 'Idle — relay sleeps (30s)'); } catch{ this.fails++; if(this.fails>=40) $('#sync-state') && ($('#sync-state').textContent='Relay unreachable — retrying automatically'); }
  }
  async api(path, body){
    const r = await fetch(this.base+path, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({room:this.room, device:this.deviceId, ...body})});
    const j = await r.json(); return j;
  }
  async pull(){
    const j = await this.api('/api/cloud/pull', {after:this.cursor, hot: this.hot?1:0});
    if(!j || j.ok!==true) throw new Error('pull failed');
    if(typeof j.cursor==='number') this.cursor=j.cursor;
    if(j.peersHot>0 && this.isMain) this.hot=true;
    if(Array.isArray(j.msgs)) for(const m of j.msgs) await this.handle(m);
  }
  async handle(raw){
    if(!raw || raw.sender===this.deviceId) return;
    const plain = await decryptString(this.key, String(raw.msg||''));
    if(!plain) return;
    let env; try{ env=JSON.parse(plain); }catch{ return; }
    if(env.t==='state_part'){
      const k = Number(env.parts)||1, i=Number(env.part)||0;
      if(k<=1){ this.applyState(String(env.s||'')); return; }
      this._chunkBuf = this._chunkBuf || Array(k).fill('');
      if(i>=0 && i<this._chunkBuf.length) this._chunkBuf[i]=String(env.s||'');
      if(this._chunkBuf.every(p=> p!=='')){ const s=this._chunkBuf.join(''); this._chunkBuf=null; this.applyState(s); }
    } else if(env.t==='state'){ this.applyState(String(env.s||'')); }
    else if(env.t==='cmd' && this.isMain){ if(env.c) this.onCmd && this.onCmd(env.c); }
    else if(env.t==='print_job'){ if(env.job) { this.onPrintJob && this.onPrintJob(env.job); } }
  }
  async send(cmd){
    const blob = await encryptString(this.key, JSON.stringify({t:'cmd', c:cmd}));
    const j = await this.api('/api/cloud/send', {msg: blob});
    return j && j.ok===true;
  }
  async sendPrintJob(job){
    const blob = await encryptString(this.key, JSON.stringify({t:'print_job', job}));
    const j = await this.api('/api/cloud/send', {msg: blob}); return j && j.ok===true;
  }
  _lastRev=-1; _lastPush=0;
  async pushCheck(){
    if(!this.isMain) return;
    const rev = await kvGet('rev', 0);
    const now = Date.now();
    const stale = now - this._lastPush > (this.hot ? 120000 : 600000);
    if(rev===this._lastRev && !stale) return;
    if(!this.hot && !stale) return;
    const json = JSON.stringify(await exportBackup());
    const CHUNK=480000;
    if(json.length <= CHUNK){
      const blob = await encryptString(this.key, JSON.stringify({t:'state', s: json}));
      const j = await this.api('/api/cloud/send', {msg: blob}); if(j && j.ok) { this._lastRev=rev; this._lastPush=now; }
    } else {
      for(let i=0;i<json.length;i+=CHUNK){
        const part = json.slice(i, i+CHUNK);
        const blob = await encryptString(this.key, JSON.stringify({t:'state_part', part: Math.floor(i/CHUNK), parts: Math.ceil(json.length/CHUNK), s: part}));
        const j = await this.api('/api/cloud/send', {msg: blob}); if(!j || !j.ok) return;
      }
      this._lastRev=rev; this._lastPush=now;
    }
  }
  applyState(json){
    try{ const obj = JSON.parse(json); if(obj && typeof obj==='object'){ importBackup(obj).then(()=> { refreshAll(); }).catch(()=>{}); } }catch{}
  }
}

// Tables / menu / stock demo seed
async function ensureSeed(){
  const has = await kvGet('seeded', 0);
  if(has) return;
  const tables = Array.from({length:8}, (_,i)=> ({id:'T'+(i+1), label:'T'+(i+1), cap: 2+(i%4), state:'free', since:null}));
  const products = [
    {id:'p1', name:'Cappuccino', price:12, cat:'Drinks', avail:true},
    {id:'p2', name:'Nasi Lemak', price:18, cat:'Mains', avail:true},
    {id:'p3', name:'Roti Canai', price:8, cat:'Mains', avail:true},
    {id:'p4', name:'Teh Tarik', price:6, cat:'Drinks', avail:true},
  ];
  const stock = [
    {id:'s1', name:'Milk', qty: 40, lowAt: 10},
    {id:'s2', name:'Rice', qty: 25, lowAt: 5},
  ];
  for(const t of tables) await idbPut('tables', t);
  for(const p of products) await idbPut('products', p);
  for(const s of stock) await idbPut('stock', s);
  await kvSet('seeded', 1);
  await kvSet('rev', 1);
}

// UI: tables
async function renderTables(filter='all'){
  const grid = $('#table-grid'); if(!grid) return;
  const tables = await idbGetAll('tables');
  grid.innerHTML = '';
  for(const t of tables){
    if(filter!=='all' && t.state!==filter) continue;
    const el = document.createElement('button');
    el.className='tile '+(t.state||'free');
    el.innerHTML = `<b>${t.label}</b><div class="mono" style="color:var(--muted);font-size:11px">${t.cap} seats</div><span class="badge badge-${t.state}">${(t.state||'free').toUpperCase()}</span>`;
    el.onclick=()=> openOrder(t.id);
    grid.appendChild(el);
  }
}
async function openOrder(tableId){
  const orders = await idbGetAll('orders');
  let o = orders.find(x=> x.table===tableId && x.status==='open');
  if(!o){ o = {id:'ord-'+Date.now(), table:tableId, status:'open', items:[], total:0, createdAt: Date.now()}; await idbPut('orders', o); }
  CUR_ORDER = o;
  $('#order-title').textContent = 'Order · '+tableId + ' · ' + o.id.slice(-6);
  const itemsEl = $('#order-items'); itemsEl.innerHTML='';
  const products = await idbGetAll('products');
  for(const p of products){
    const row = document.createElement('div');
    row.style.cssText='display:flex;justify-content:space-between;align-items:center;border:1px solid var(--line);border-radius:12px;padding:8px 10px;background:#FFFDF9';
    row.innerHTML=`<span>${p.name} · RM ${p.price}</span><button class="btn btn-ghost" style="padding:6px 10px">Add</button>`;
    row.querySelector('button').onclick=async()=>{
      CUR_ORDER.items.push({name:p.name, qty:1, total:p.price});
      CUR_ORDER.total = CUR_ORDER.items.reduce((a,b)=> a+b.total, 0);
      await idbPut('orders', CUR_ORDER); await kvSet('rev', Date.now());
      buildOrderSheet();
    };
    itemsEl.appendChild(row);
  }
  // current items
  const cur = document.createElement('div'); cur.style.marginTop='10px';
  cur.innerHTML = CUR_ORDER.items.map(it=> `<div style="display:flex;justify-content:space-between"><span>${it.name} × ${it.qty}</span><span>RM ${it.total.toFixed(2)}</span></div>`).join('') || '<p class="mono" style="color:var(--muted)">No items yet — add from above.</p>';
  itemsEl.appendChild(cur);
  $('#order-sheet').hidden=false;
  $('#order-sheet').scrollIntoView({behavior:'smooth'});
}
function buildOrderSheet(){
  if(!CUR_ORDER) return;
  const box = $('#order-items').lastElementChild;
  if(box) box.innerHTML = CUR_ORDER.items.map(it=> `<div style=\"display:flex;justify-content:space-between\"><span>${it.name} × ${it.qty}</span><span>RM ${it.total.toFixed(2)}</span></div>`).join('') || '<p class="mono" style="color:var(--muted)">No items yet</p>';
}

async function renderMenu(){
  const host = $('#menu-list'); if(!host) return;
  const list = await idbGetAll('products');
  host.innerHTML='';
  for(const p of list){
    const row=document.createElement('div');
    row.style.cssText='display:flex;justify-content:space-between;align-items:center;border:1px solid var(--line);border-radius:14px;padding:10px 14px;background:#FFFDF9';
    row.innerHTML=`<span><b>${p.name}</b> <span class="mono" style="color:var(--muted)">RM ${p.price}</span> ${p.avail?'':'· 86'}</span><span style="display:flex;gap:6px"><button class="btn btn-ghost" data-a="86" style="padding:6px 10px">86</button><button class="btn btn-ghost" data-a="del" style="padding:6px 10px">Delete</button></span>`;
    row.querySelector('[data-a="86"]').onclick=async()=>{ p.avail=!p.avail; await idbPut('products', p); await kvSet('rev', Date.now()); renderMenu(); };
    row.querySelector('[data-a="del"]').onclick=async()=>{ await idbDel('products', p.id); await kvSet('rev', Date.now()); renderMenu(); };
    host.appendChild(row);
  }
}
async function renderKitchen(){
  const host = $('#kitchen-list'); if(!host) return;
  const orders = await idbGetAll('orders');
  const open = orders.filter(o=> o.status==='open');
  host.innerHTML = open.length ? '' : '<p class="mono" style="color:var(--muted)">No open tickets.</p>';
  for(const o of open){
    const age = Math.round((Date.now()-o.createdAt)/60000);
    const card=document.createElement('div');
    card.style.cssText='border:1.5px solid var(--line);border-radius:16px;padding:14px;background:#FFFDF9';
    card.innerHTML=`<div style="display:flex;justify-content:space-between;align-items:center"><b>${o.table} · #${o.id.slice(-6)}</b><span class="pill">${age} min</span></div><div style="margin-top:6px">${o.items.map(it=> `<div style="display:flex;justify-content:space-between"><span>${it.name} × ${it.qty}</span><span>RM ${it.total.toFixed(2)}</span></div>`).join('')}</div><div style="display:flex;gap:8px;margin-top:8px"><button class="btn btn-mint" data-a="ready" style="padding:8px 12px">Mark ready</button><button class="btn btn-ghost" data-a="print" style="padding:8px 12px">Print with Apple</button></div>`;
    card.querySelector('[data-a="ready"]').onclick=async()=>{ o.status='ready'; await idbPut('orders', o); await kvSet('rev', Date.now()); renderKitchen(); renderTables(); };
    card.querySelector('[data-a="print"]').onclick=()=> handlePrint(o, {name: (document.getElementById('shop-name')?.value||'Order Flow')});
    host.appendChild(card);
  }
}
async function renderStock(){
  const host = $('#stock-list'); if(!host) return;
  const rows = await idbGetAll('stock');
  host.innerHTML = rows.length ? '' : '<p class="mono" style="color:var(--muted)">No stock items.</p>';
  for(const s of rows){
    const low = s.qty <= s.lowAt;
    const row=document.createElement('div');
    row.style.cssText='display:flex;justify-content:space-between;align-items:center;border:1px solid var(--line);border-radius:14px;padding:10px 14px;background:'+(low?'#FFF0F0':'#FFFDF9');
    row.innerHTML=`<span><b>${s.name}</b> <span class="mono">qty ${s.qty}</span> ${low?'<span class="badge" style="background:#FEE2E2;color:#7C1D1D">LOW</span>':''}</span><span style="display:flex;gap:6px"><button class="btn btn-ghost" data-a="minus" style="padding:6px 10px">−1</button><button class="btn btn-ghost" data-a="plus" style="padding:6px 10px">+1</button></span>`;
    row.querySelector('[data-a="minus"]').onclick=async()=>{ s.qty=Math.max(0,s.qty-1); await idbPut('stock', s); await kvSet('rev', Date.now()); renderStock(); };
    row.querySelector('[data-a="plus"]').onclick=async()=>{ s.qty+=1; await idbPut('stock', s); await kvSet('rev', Date.now()); renderStock(); };
    host.appendChild(row);
  }
}
async function refreshAll(){
  const f = document.querySelector('#tab-tables [data-filter].active')?.dataset.filter || 'all';
  await Promise.all([renderTables(f), renderMenu(), renderKitchen(), renderStock()]);
  const est = await storageEstimate();
  if(est && $('#storage-est')) $('#storage-est').textContent = `Storage ${((est.usage/1024/1024).toFixed(1))} MB / ${(est.quota/1024/1024/1024).toFixed(1)} GB · ${est.pct}%`;
}

// role setup
async function initRoleUI(){
  const savedRole = await kvGet('role', null);
  const savedRoom = await kvGet('roomInfo', null);
  if(savedRole && savedRoom){
    ROLE = savedRole;
    enterApp(savedRoom);
    return;
  }
  // show setup
}

function enterApp(roomInfo){
  $('#view-setup').hidden=true;
  $('#view-app').hidden=false;
  $('#side-role').textContent = ROLE==='main' ? 'Main — this iPhone is the shop server' : 'Station — '+ ($('#station-role')?.value || 'taker');
  $('#side-room').textContent = roomInfo ? (roomInfo.room.slice(0,8)+'… · '+roomInfo.code) : 'Offline only (no room)';
  $('#role-badge').textContent = ROLE==='main' ? 'Main' : 'Station';
  refreshAll();
  if(roomInfo) startRelay(roomInfo);
  ensurePersist();
}

async function startRelay(info){
  const id = await deviceId();
  const r = new Relay({room: info.room, secret: info.secret, base: info.base, deviceId: id, isMain: ROLE==='main'});
  await r.init();
  r.onCmd = async (cmd)=>{
    // station pushed an order update — merge: for demo, just replace orders with cmd.orders
    if(cmd.orders) for(const o of cmd.orders) await idbPut('orders', o);
    await kvSet('rev', Date.now());
    refreshAll();
  };
  r.onPrintJob = async (job)=>{
    // this device is print gateway listening
    const isGateway = await kvGet('gateway', false);
    if(!isGateway) return;
    const log = $('#gateway-log');
    if(log) log.textContent += `\n[${new Date().toLocaleTimeString()}] print job ${job.id} → Printing with Apple…`;
    try{ printViaApple(job.order, job.shop); if(log) log.textContent += ' ✓'; } catch(e){ if(log) log.textContent += ' — '+e; }
  };
  r.start();
  RELAY = r; window.OFRelay = r;
  // delta: when station creates order, push orders array
  window.OFRelay.sendOrders = async ()=>{
    const orders = await idbGetAll('orders');
    await r.send({orders});
  };
  window.OFRelay.sendPrintJob = (job)=> r.sendPrintJob(job);
}

// events
document.addEventListener('DOMContentLoaded', async ()=>{
  await ensureSeed();
  await initRoleUI();
  refreshAll();

  // tabs
  $$('.side nav button').forEach(b=> b.addEventListener('click', ()=>{
    $$('.side nav button').forEach(x=> x.classList.remove('active'));
    b.classList.add('active');
    const tab=b.dataset.tab;
    $('#tab-tables').hidden = tab!=='tables';
    $('#tab-menu').hidden = tab!=='menu';
    $('#tab-kitchen').hidden = tab!=='kitchen';
    $('#tab-stock').hidden = tab!=='stock';
    $('#tab-print').hidden = tab!=='print';
    $('#tab-settings').hidden = tab!=='settings';
  }));
  // table filters
  $$('#tab-tables [data-filter]').forEach(b=> b.addEventListener('click', ()=>{
    $$('#tab-tables [data-filter]').forEach(x=> x.classList.remove('active'));
    b.classList.add('active'); renderTables(b.dataset.filter);
  }));
  // role buttons
  $('[data-role="main"]')?.addEventListener('click', ()=>{ $('#setup-main').hidden=false; $('#setup-station').hidden=true; });
  $('[data-role="station"]')?.addEventListener('click', ()=>{ $('#setup-station').hidden=false; $('#setup-main').hidden=true; });
  // open room
  $('#btn-open-room')?.addEventListener('click', async ()=>{
    const btn=$('#btn-open-room'); btn.disabled=true; btn.textContent='Opening…';
    const shop = $('#shop-name').value.trim()||'My Shop';
    const license = $('#license-key').value.trim();
    const id = await deviceId();
    try{
      const r = await fetch(RELAY_BASE+'/api/cloud/open', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({licenseKey: license || 'TRIAL-WEB-PLACEHOLDER', deviceId: id, shopName: shop})});
      const j = await r.json();
      if(!j || !j.ok) throw new Error(j?.error||'plan');
      const base = RELAY_BASE;
      const pairing = pairingEncode(j.room, j.code, j.secret, base);
      $('#room-box').hidden=false;
      $('#join-code').textContent=j.code;
      $('#pairing-text').textContent=pairing;
      drawQR($('#qr'), pairing);
      await kvSet('roomInfo', {room:j.room, code:j.code, secret:j.secret, base});
      await kvSet('role','main'); ROLE='main';
      $('#btn-enter-app').onclick=()=> enterApp({room:j.room, code:j.code, secret:j.secret, base});
    }catch(e){
      alert('Could not open room: '+ (String(e).includes('plan') ? 'License not on cloud plan — using offline-only room. Stations can still join on same Wi-Fi via copy? For web, internet relay is required — use a trial key or ask Jathol to enable cloud on your key.' : String(e)));
      // offline fallback room
      const room = 'offline-'+Math.random().toString(36).slice(2,10);
      const secret = Math.random().toString(36).slice(2,18);
      const code = Math.random().toString(36).slice(2,8).toUpperCase();
      const pairing = pairingEncode(room, code, secret, RELAY_BASE);
      $('#room-box').hidden=false;
      $('#join-code').textContent=code + ' · offline';
      $('#pairing-text').textContent=pairing;
      drawQR($('#qr'), pairing);
      await kvSet('roomInfo', {room, code, secret, base:RELAY_BASE});
      await kvSet('role','main'); ROLE='main';
      $('#btn-enter-app').onclick=()=> enterApp({room, code, secret, base:RELAY_BASE});
    } finally { btn.disabled=false; btn.textContent='Open room & show QR'; }
  });
  $('#btn-copy-pair')?.addEventListener('click', async ()=>{ const t=$('#pairing-text').textContent; await navigator.clipboard.writeText(t).catch(()=>{}); const b=$('#btn-copy-pair'); const old=b.textContent; b.textContent='Copied!'; setTimeout(()=> b.textContent=old, 1500); });
  $('#btn-save-qr')?.addEventListener('click', ()=>{
    const c=$('#qr'); const a=document.createElement('a'); a.download='order-flow-qr.png'; a.href=c.toDataURL('image/png'); a.click();
  });
  // join
  $('#btn-join')?.addEventListener('click', async ()=>{
    const raw=$('#pairing-input').value.trim(); if(!raw) return;
    const info=pairingDecode(raw); if(!info){ $('#join-status').textContent='Bad pairing text — copy the full OF1:… line from Main.'; return; }
    const id=await deviceId(); const role=$('#station-role').value||'taker';
    try{
      const r=await fetch(info.base+'/api/cloud/join', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({room:info.room, code:info.code, deviceId:id, role})});
      const j=await r.json(); if(!j||!j.ok) throw new Error(j?.error||'no_room');
      await kvSet('roomInfo', info); await kvSet('role','station'); ROLE='station'; $('#join-status').textContent='Joined ✓ — tap Enter as Station';
    }catch(e){ $('#join-status').textContent='Join failed: '+String(e); }
  });
  $('#qr-file')?.addEventListener('change', async (e)=>{
    const f=e.target.files?.[0]; if(!f) return;
    // Use BarcodeDetector if available
    try{
      if('BarcodeDetector' in window){
        const det=new BarcodeDetector({formats:['qr_code']});
        const bmp=await createImageBitmap(f);
        const codes=await det.detect(bmp);
        if(codes[0]?.rawValue){ $('#pairing-input').value=codes[0].rawValue; $('#join-status').textContent='QR read ✓ — tap Join'; return; }
      }
    }catch{}
    $('#join-status').textContent='Could not auto-read QR — paste the OF1:… text from Main.';
  });
  $('#btn-enter-station')?.addEventListener('click', async()=>{
    const info=await kvGet('roomInfo', null);
    if(!info) { alert('Paste the OF1:… pairing text and tap Join first.'); return; }
    enterApp(info);
  });
  // menu add
  $('#btn-add-item')?.addEventListener('click', async()=>{
    const n=$('#new-item-name').value.trim(); const p=Number($('#new-item-price').value);
    if(!n) return;
    await idbPut('products', {id:'p-'+Date.now(), name:n, price:isFinite(p)?p:0, cat:'Custom', avail:true});
    $('#new-item-name').value=''; $('#new-item-price').value=''; await kvSet('rev', Date.now()); renderMenu();
    if(RELAY && ROLE==='station') await window.OFRelay.sendOrders();
  });
  // order sheet actions
  $('#btn-send-kitchen')?.addEventListener('click', async()=>{
    if(!CUR_ORDER) return;
    CUR_ORDER.status='sent'; await idbPut('orders', CUR_ORDER);
    // update table state
    const t=await idbGet('tables', CUR_ORDER.table); if(t){ t.state='busy'; t.since=Date.now(); await idbPut('tables', t); }
    await kvSet('rev', Date.now()); refreshAll(); $('#order-sheet').hidden=true;
    if(RELAY){
      if(ROLE==='main') {} else await window.OFRelay.sendOrders();
    }
  });
  $('#btn-print-order-apple')?.addEventListener('click', ()=>{
    if(!CUR_ORDER) return;
    const shop={name: $('#shop-name')?.value||'Order Flow'}; printViaApple(CUR_ORDER, shop);
  });
  $('#btn-close-order')?.addEventListener('click', ()=> $('#order-sheet').hidden=true);
  // export / import
  async function doExport(){
    const blob = await exportBackup();
    const text = JSON.stringify(blob, null, 2);
    const file = new File([text], 'order-flow-backup-'+new Date().toISOString().slice(0,10)+'.json', {type:'application/json'});
    if(navigator.canShare && navigator.canShare({files:[file]})){
      try{ await navigator.share({files:[file], title:'Order Flow backup'}); return; }catch{}
    }
    const url = URL.createObjectURL(new Blob([text], {type:'application/json'}));
    const a=document.createElement('a'); a.href=url; a.download=file.name; a.click(); setTimeout(()=> URL.revokeObjectURL(url), 2000);
  }
  $('#btn-export')?.addEventListener('click', doExport);
  $('#btn-export2')?.addEventListener('click', doExport);
  $('#btn-restore')?.addEventListener('click', ()=> $('#import-file')?.click());
  async function handleImport(file){
    const text = await file.text(); const obj = JSON.parse(text);
    await importBackup(obj); await kvSet('rev', Date.now()); refreshAll(); alert('Import done — '+ (obj.products?.length||0)+' products, '+(obj.orders?.length||0)+' orders');
  }
  $('#import-file')?.addEventListener('change', async(e)=>{ const f=e.target.files?.[0]; if(f) await handleImport(f); });
  $('#import-file2')?.addEventListener('change', async(e)=>{ const f=e.target.files?.[0]; if(f) await handleImport(f); });
  $('#btn-wipe')?.addEventListener('click', async()=>{ if(confirm('Wipe all local data on this device?')){ for(const s of ['products','tables','orders','stock','customers','settings','printQueue','kv']) await idbClear(s); location.reload(); } });
  $('#btn-leave')?.addEventListener('click', async()=>{
    if(confirm('Leave room and go back to setup? Your local data stays.')){ await kvSet('roomInfo', null); await kvSet('role', null); if(RELAY) RELAY.stop(); location.reload(); }
  });
  // print tab
  $('#btn-print-apple')?.addEventListener('click', async()=>{
    const demo = CUR_ORDER || {id:'TEST-'+Date.now(), items:[{name:'Demo item', qty:1, total:12}], total:12};
    const shop={name: $('#shop-name')?.value||'Order Flow'}; $('#print-status').textContent='Opening Apple print dialog… pick your AirPrint/Bluetooth printer.';
    try{ printViaApple(demo, shop); setTimeout(()=> $('#print-status').textContent='Dialog opened — pick printer and Print. For Bluetooth, pair the printer in iOS Settings → Bluetooth first, if it supports AirPrint it appears here.', 800); } catch(e){ $('#print-status').textContent='Print failed: '+e; }
  });
  $('#btn-print-bt')?.addEventListener('click', async()=>{
    const demo = CUR_ORDER || {id:'TEST-'+Date.now(), items:[{name:'Demo item', qty:1, total:12}], total:12};
    const shop={name: $('#shop-name')?.value||'Order Flow'};
    $('#print-status').textContent='Requesting Bluetooth device… pick your thermal printer.';
    try{ await printViaBluetooth(demo, shop); $('#print-status').textContent='Sent to Bluetooth printer ✓'; } catch(e){ $('#print-status').textContent='Bluetooth: '+ String(e.message||e) + ' — on iPhone use Print with Apple instead.'; }
  });
  $('#chk-relay-print')?.addEventListener('change', async(e)=>{ await kvSet('relayPrint', e.target.checked); });
  $('#chk-gateway')?.addEventListener('change', async(e)=>{ await kvSet('gateway', e.target.checked); if(e.target.checked) $('#gateway-log').textContent='Gateway on — waiting for print jobs…'; });
  // restore saved checks
  kvGet('relayPrint', false).then(v=>{ const el=$('#chk-relay-print'); if(el) el.checked=!!v; });
  kvGet('gateway', false).then(v=>{ const el=$('#chk-gateway'); if(el) el.checked=!!v; if(v) $('#gateway-log').textContent='Gateway on — waiting for print jobs…'; });
  $('#btn-print-test')?.addEventListener('click', ()=> $('#btn-print-apple').click());

  // PWA install handling
  let deferredPrompt=null;
  window.addEventListener('beforeinstallprompt', (e)=>{ e.preventDefault(); deferredPrompt=e; const b=$('#btn-install'); if(b){ b.hidden=false; b.onclick=async()=>{ if(deferredPrompt){ deferredPrompt.prompt(); const c=await deferredPrompt.userChoice; deferredPrompt=null; b.hidden=true; $('#install-hint').textContent = c.outcome==='accepted' ? 'Installed ✓ — open from Home Screen' : 'You can still add via Share → Add to Home Screen'; } }; } });
  window.addEventListener('appinstalled', ()=>{ const b=$('#btn-install'); if(b) b.hidden=true; $('#install-hint').textContent='App installed ✓ — launch from Home Screen for standalone mode.'; });
  // iOS standalone detection
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone===true;
  if(isStandalone) $('#install-hint').textContent='Running in standalone — you’re on the Home Screen app ✓';
  else if(/iPad|iPhone|iPod/.test(navigator.userAgent)) $('#install-hint').textContent='iPhone: tap Share → Add to Home Screen → Add (Safari only). The App Store button does the same.';
});
