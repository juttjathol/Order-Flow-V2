// Order Flow Web POS — Main *or* Station (iPhone can be either)
// Replica: tables/menu/kitchen/stock + IndexedDB + cloud relay + relay-print + AirPrint
const $ = (s, r=document)=> r.querySelector(s);
const $$ = (s, r=document)=> [...r.querySelectorAll(s)];

let ROLE = null; // 'main' | 'station'
let RELAY = null;
let CUR_ORDER = null;
let HOT = true;

// license key canonical form — accepts OF-XXXX-XXXX-XXXX-XXXX or XXXX-XXXX-XXXX-XXXX.
// Keys are generated server-side as OF-XXXX-… and must match the DB exactly.
function ofNormalizeKey(v){
  v = String(v==null?'':v).toUpperCase().replace(/[^A-Z0-9]/g,'');
  let prefix='';
  if(v.startsWith('OF')){ prefix='OF-'; v=v.slice(2); }
  v = v.slice(0,16);
  const body = v.replace(/(.{4})/g,'$1-').replace(/-$/,'');
  return prefix ? prefix+body : body;
}
const OF_KEY_RE = /^(OF-)?[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/;

// ——— device settings (APK parity — shop/receipt/kitchen/qr ordering) ———
const SET_DEFAULTS = { shopName:'My Shop', shopPhone:'', currency:'RM', tax:0, svc:0, receiptHead:'Thank you!', receiptFoot:'See you again', copies:1, paper:'80', showQr:false, autoPrint:true, kitchenSound:true, qrOrder:false };
let _setCache = null;
async function getSettings(){
  if(_setCache) return _setCache;
  let saved = {};
  try{ saved = (await kvGet('settings', {})) || {}; }catch{}
  _setCache = {...SET_DEFAULTS, ...saved};
  return _setCache;
}
async function saveSettings(patch){
  const cur = await getSettings();
  Object.assign(cur, patch); _setCache = cur;
  await kvSet('settings', cur);
  try{ await kvSet('rev', Date.now()); }catch{}
  const st = document.getElementById('settings-status');
  if(st){ st.textContent='Saved ✓'; clearTimeout(st._t); st._t=setTimeout(()=> st.textContent='', 1400); }
}
function fmtMoney(n){
  const cur = _setCache || SET_DEFAULTS;
  return (cur.currency||'RM') + ' ' + (Number(n)||0).toFixed(2);
}

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
    // same-origin proxy first (jathol.org/api/cloud/* → forwarder, no CORS),
    // then the configured base as fallback. text/plain = CORS-simple request.
    const payload=JSON.stringify({room:this.room, device:this.deviceId, ...body});
    const bases=['', this.base].filter((b,i,a)=> b!==undefined && a.indexOf(b)===i);
    let lastErr=null;
    for(const base of bases){
      try{
        const r = await fetch(base+path, {method:'POST', headers:{'Content-Type':'text/plain'}, body: payload});
        const j = await r.json().catch(()=>null);
        if(j) return j;
        lastErr=new Error('http_'+r.status);
      }catch(e){ lastErr=e; }
    }
    throw lastErr||new Error('api failed');
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

// UI: tables — BistroTableTile (like common.dart)
async function renderTables(filter='all'){
  const grid = $('#table-grid'); if(!grid) return;
  const tables = await idbGetAll('tables');
  const orders = await idbGetAll('orders').catch(()=>[]);
  grid.innerHTML = '';
  for(const t of tables){
    if(filter!=='all' && t.state!==filter) continue;
    const st=(t.state||'free'); const busy=st==='busy'||st==='ready';
    const amount=orders.filter(o=> o.table===t.id && o.status!=='closed').reduce((a,o)=> a+(o.total||0),0);
    const el = document.createElement('button');
    el.className='tile '+(busy?'is-busy':'')+' '+(st==='free'?'is-empty':'')+' '+st;
    el.setAttribute('aria-label', t.label+' '+st);
    el.innerHTML = '<div class="tile__top"><span class="tile__name">'+t.label+'</span><span class="tile__cap">'+t.cap+'×</span></div><div class="tile__center"><div class="tile__plate">'+(busy?'🍽️':'○')+'</div></div><div class="tile__meta"><span style="display:flex;align-items:center;gap:6px">'+(busy?'<span class="tile__pulse" aria-hidden="true"></span>':'')+'<span>'+(st==='free'?'Empty': st==='ready'?'Ready':'Busy')+'</span></span><span class="tile__amount">'+(busy&&amount? 'RM '+amount.toFixed(0): '')+'</span></div>';
    el.onclick=()=> openOrder(t.id);
    grid.appendChild(el);
  }
  if(!grid.children.length) grid.innerHTML='<p class="muted" style="grid-column:1/-1;padding:12px">No tables in this filter.</p>';
  renderHome().catch(()=>{});
}
// UI: order sheet — real bottom sheet above everything (like APK order sheet)
async function openOrder(tableId){
  const orders = await idbGetAll('orders');
  let o = orders.find(x=> x.table===tableId && (x.status==='open'||x.status==='sent'));
  if(!o){ o = {id:'ord-'+Date.now(), table:tableId, status:'open', items:[], total:0, createdAt: Date.now()}; await idbPut('orders', o); }
  CUR_ORDER = o;
  $('#order-title').textContent = 'Table '+tableId.replace(/^T/,'')+' — Order';
  const pick = $('#order-items'); pick.innerHTML='';
  const products = await idbGetAll('products');
  const list = products.filter(p=> p && p.name);
  if(!list.length) pick.innerHTML='<p class="muted" style="font-weight:600">Menu is empty — add items in the Menu tab first.</p>';
  for(const p of list){
    const off = p.avail===false;
    const row = document.createElement('div');
    row.className='menu-pick-row'+(off?' is-off':'');
    row.innerHTML='<div style="min-width:0"><div class="name">'+p.name+(off?' · sold out':'')+'</div><div class="price">'+fmtMoney(p.price)+'</div></div><button class="add" type="button">Add</button>';
    row.querySelector('.add').onclick=async()=>{
      if(off) return;
      const ex = CUR_ORDER.items.find(it=> it.name===p.name);
      if(ex){ ex.qty++; ex.total = ex.qty * p.price; }
      else CUR_ORDER.items.push({name:p.name, qty:1, price:p.price, total:p.price});
      CUR_ORDER.total = CUR_ORDER.items.reduce((a,b)=> a+b.total, 0);
      await idbPut('orders', CUR_ORDER); await kvSet('rev', Date.now());
      buildOrderSheet();
    };
    pick.appendChild(row);
  }
  await buildOrderSheet();
  const sh = $('#sheet-order'); sh.classList.add('is-open'); sh.setAttribute('aria-hidden','false');
}
function closeOrderSheet(){ const sh=$('#sheet-order'); if(!sh) return; sh.classList.remove('is-open'); sh.setAttribute('aria-hidden','true'); }
async function buildOrderSheet(){
  if(!CUR_ORDER) return;
  const s = await getSettings();
  const cur = $('#order-current'); if(cur) cur.innerHTML='';
  if(!CUR_ORDER.items.length){
    cur.innerHTML='<p class="muted" style="font-weight:600;margin:0">Nothing added yet — pick from the menu below.</p>';
  }
  for(const [i,it] of CUR_ORDER.items.entries()){
    const row=document.createElement('div');
    row.className='ord-line';
    row.innerHTML='<span style="min-width:0">'+it.name+'</span><span class="qty"><button type="button" data-d="-1">−</button><b>'+it.qty+'</b><button type="button" data-d="1">+</button><span style="min-width:64px;text-align:right">'+fmtMoney(it.total)+'</span></span>';
    row.querySelectorAll('.qty button').forEach(b=> b.onclick=async()=>{
      it.qty += Number(b.dataset.d);
      if(it.qty<=0) CUR_ORDER.items.splice(i,1); else it.total = it.qty * (it.price ?? (it.total/ (it.qty-Number(b.dataset.d)) || 0));
      CUR_ORDER.total = CUR_ORDER.items.reduce((a,x)=> a+x.total, 0);
      await idbPut('orders', CUR_ORDER); await kvSet('rev', Date.now());
      buildOrderSheet();
    });
    cur.appendChild(row);
  }
  const sub = CUR_ORDER.total||0;
  const tax = sub * (Number(s.tax)||0)/100;
  const svc = sub * (Number(s.svc)||0)/100;
  const grand = sub + tax + svc;
  $('#order-total-row').innerHTML =
    '<div style="display:flex;justify-content:space-between"><span>Subtotal</span><span>'+fmtMoney(sub)+'</span></div>'
    + ((Number(s.tax)||0) ? '<div style="display:flex;justify-content:space-between"><span>Tax ('+s.tax+'%)</span><span>'+fmtMoney(tax)+'</span></div>' : '')
    + ((Number(s.svc)||0) ? '<div style="display:flex;justify-content:space-between"><span>Service ('+s.svc+'%)</span><span>'+fmtMoney(svc)+'</span></div>' : '')
    + '<div class="grand"><span>Total</span><span>'+fmtMoney(grand)+'</span></div>';
}

async function renderMenu(){
  const host = $('#menu-list'); if(!host) return;
  const list = await idbGetAll('products');
  host.innerHTML='';
  host.className='prod-grid';
  for(const p of list){
    const row=document.createElement('div');
    row.className='prod';
    row.innerHTML='<div class="prod__img">'+(p.image?'<img src="'+p.image+'" alt="" loading="lazy"/>':'<span style="font-size:28px">🍽️</span>')+'</div><div class="prod__body"><div class="prod__name">'+p.name+(p.avail?'':' · <span style="color:var(--danger);font-weight:800">Sold out</span>')+'</div><div class="prod__price">'+fmtMoney(p.price)+'</div><button class="prod__add" data-a="86">'+(p.avail?'Mark sold out':'Back on menu')+'</button><button class="btn btn--muted" data-a="del" style="min-height:36px;margin-top:6px;padding:0 10px;border-radius:12px;font-size:13px">Delete</button></div>';
    row.querySelector('[data-a="86"]').onclick=async()=>{ p.avail=!p.avail; await idbPut('products', p); await kvSet('rev', Date.now()); renderMenu(); renderHome().catch(()=>{}); };
    row.querySelector('[data-a="del"]').onclick=async()=>{ await idbDel('products', p.id); await kvSet('rev', Date.now()); renderMenu(); renderHome().catch(()=>{}); };
    host.appendChild(row);
  }
  if(!host.children.length) host.innerHTML='<p class="muted" style="grid-column:1/-1;padding:12px">No products — add one above.</p>';
}
async function renderKitchen(){
  const host = $('#kitchen-list'); if(!host) return;
  const orders = await idbGetAll('orders');
  const open = orders.filter(o=> o.status==='open' || o.status==='sent');
  host.innerHTML = open.length ? '' : '<p class="muted" style="color:var(--muted)">No open tickets.</p>';
  for(const o of open){
    const age = Math.max(0,Math.round((Date.now()-(o.createdAt||Date.now()))/60000));
    const card=document.createElement('div');
    card.className='of-card pad';
    card.innerHTML='<div style="display:flex;justify-content:space-between;align-items:center"><b>'+o.table+' · #'+o.id.slice(-6)+'</b><span class="of-badge '+(age>12?'of-badge--gold':'')+'">'+age+' min</span></div><div style="margin-top:8px;display:grid;gap:4px">'+(o.items||[]).map(it=> '<div style="display:flex;justify-content:space-between"><span>'+it.name+' × '+it.qty+'</span><span style="font-weight:800">'+fmtMoney(it.total||0)+'</span></div>').join('')+'</div><div style="display:flex;gap:8px;margin-top:10px;flex-wrap:wrap"><button class="btn btn--forest" data-a="ready" style="min-height:40px;padding:0 14px;border-radius:999px;font-size:13px">Mark ready</button><button class="btn btn--ghost" data-a="print" style="min-height:40px;padding:0 14px;border-radius:999px;font-size:13px">Print slip</button></div>';
    card.querySelector('[data-a="ready"]').onclick=async()=>{ o.status='ready'; await idbPut('orders', o); await kvSet('rev', Date.now()); renderKitchen(); renderTables(); renderHome().catch(()=>{}); window.OFAfterReady?.(o); };
    card.querySelector('[data-a="print"]').onclick=()=> window.OFPrintReceipt?.(o, {type:'kitchen'});
    host.appendChild(card);
  }
  // also paint home live
  renderHome().catch(()=>{});
}
async function renderStock(){
  const host = $('#stock-list'); if(!host) return;
  const rows = await idbGetAll('stock');
  host.innerHTML = rows.length ? '' : '<p class="muted" style="color:var(--muted)">No stock items.</p>';
  for(const s of rows){
    const n=s; const low = n.qty <= n.lowAt;
    const row=document.createElement('div');
    row.className='of-card pad'; row.style.cssText='display:flex;justify-content:space-between;align-items:center;'+(low?'background:#FFF4E6;border-color:#FFD7A0':'' );
    row.innerHTML='<span><b>'+n.name+'</b> <span class="mono">qty '+n.qty+'</span> '+(low?'<span class="of-badge" style="background:#D94838;color:#fff;border-color:#D94838">LOW</span>':'')+'</span><span style="display:flex;gap:6px"><button class="btn btn--muted" data-a="minus" style="min-height:36px;padding:0 12px;border-radius:999px">−1</button><button class="btn btn--muted" data-a="plus" style="min-height:36px;padding:0 12px;border-radius:999px">+1</button></span>';
    row.querySelector('[data-a="minus"]').onclick=async()=>{ n.qty=Math.max(0,n.qty-1); await idbPut('stock', n); await kvSet('rev', Date.now()); renderStock(); renderHome().catch(()=>{}); };
    row.querySelector('[data-a="plus"]').onclick=async()=>{ n.qty+=1; await idbPut('stock', n); await kvSet('rev', Date.now()); renderStock(); renderHome().catch(()=>{}); };
    host.appendChild(row);
  }
}

// --- HOME — APK home_screen.dart replica: sales sparkline + stats + live ---
async function renderHome(){
  try{
    const tables=(await idbGetAll('tables').catch(()=>[]));
    const orders=(await idbGetAll('orders').catch(()=>[]));
    const prods=(await idbGetAll('products').catch(()=>[]));
    const stock=(await idbGetAll('stock').catch(()=>[]));
    const openOrders=orders.filter(o=> o.status==='open'||o.status==='sent');
    const busyTables=tables.filter(t=> t.state==='busy'||t.state==='ready').length;
    const totalSales=orders.filter(o=> o.status!=='closed').reduce((a,o)=> a+(o.total||0),0);
    const low=stock.filter(s=> s.qty<=s.lowAt).length;
    const els={
      kicker: document.getElementById('home-kicker'),
      sales: document.getElementById('home-sales'),
      delta: document.getElementById('home-delta'),
      ordersMeta: document.getElementById('home-orders'),
      tablesMeta: document.getElementById('home-tables'),
      statOrders: document.getElementById('stat-orders'),
      statBusy: document.getElementById('stat-busy'),
      statMenu: document.getElementById('stat-menu'),
      statLow: document.getElementById('stat-low'),
      spark: document.getElementById('home-spark'),
      live: document.getElementById('kitchen-live'),
      liveEmpty: document.getElementById('live-empty'),
    };
    if(els.sales) els.sales.textContent=fmtMoney(totalSales);
    if(els.kicker){
      const isMain=ROLE==='main'; const now=new Date();
      els.kicker.textContent=(isMain?'Main':'Station')+' · '+now.toLocaleDateString(undefined,{weekday:'short', month:'short', day:'numeric'})+' · '+(HOT?'live':'idle');
    }
    if(els.delta){
      const ySales=Math.max(0, totalSales * (0.88 + Math.random()*0.18));
      const d= totalSales - ySales;
      els.delta.textContent=(d>=0? '↗ +RM '+d.toFixed(0): '↘ RM '+d.toFixed(0))+' vs yesterday';
      els.delta.style.background=d>=0? 'rgba(46,167,113,.16)': 'rgba(217,72,56,.14)';
      els.delta.style.color=d>=0? '#163E2E': '#7C1D1D';
    }
    if(els.ordersMeta) els.ordersMeta.textContent=openOrders.length+' open';
    if(els.tablesMeta) els.tablesMeta.textContent=busyTables+' tables busy';
    if(els.statOrders) els.statOrders.textContent=String(openOrders.length);
    if(els.statBusy) els.statBusy.textContent=String(busyTables);
    if(els.statMenu) els.statMenu.textContent=String(prods.length);
    if(els.statLow) els.statLow.textContent=String(low);
    // spark — simple jitter
    if(els.spark){
      const vals=Array.from({length:9},(_,i)=> 26 - Math.round((totalSales%40)/4) - Math.round(Math.sin(i*0.9)*6) - (i%2?2:0));
      const pts=vals.map((v,i)=> `${Math.round(i*108/8)},${Math.max(6,Math.min(42,v))}`).join(' ');
      els.spark.setAttribute('points', pts);
    }
    // live tickets mini
    if(els.live){
      els.live.innerHTML='';
      const toShow=openOrders.slice(0,3);
      for(const o of toShow){
        const age=Math.max(0,Math.round((Date.now()-(o.createdAt||Date.now()))/60000));
        const el=document.createElement('div');
        el.className='of-card pad';
        el.style.cssText='padding:12px';
        el.innerHTML='<div style="display:flex;justify-content:space-between;align-items:center"><b>'+o.table+' · #'+o.id.slice(-6)+'</b><span class="of-badge '+(age>12?'of-badge--gold':'')+'">'+age+'m</span></div><div class="muted" style="margin-top:4px;font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+(o.items||[]).map(it=> it.name+'×'+it.qty).join(' · ')+'</div>';
        els.live.appendChild(el);
      }
      if(els.liveEmpty) els.liveEmpty.hidden= toShow.length>0;
      if(!toShow.length && els.live) els.live.innerHTML='';
    }
    // bottom nav dot for pending tickets
    const navMore=document.querySelector('.of-nav__item[data-tab="more"]');
    if(navMore) navMore.classList.toggle('has-dot', openOrders.length>0);
  }catch(e){ /* no-op */ }
}

async function refreshAll(){
  const f = document.querySelector('#tab-tables [data-filter].is-active')?.dataset.filter || document.querySelector('#tab-tables [data-filter].active')?.dataset.filter || 'all';
  await Promise.all([renderTables(f), renderMenu(), renderKitchen(), renderStock(), renderHome()]);
  try{ await window.OFCheckOrders?.(); }catch{}
  const est = await storageEstimate();
  if(est && $('#storage-est')) $('#storage-est').textContent = `Storage ${((est.usage/1024/1024).toFixed(1))} MB / ${(est.quota/1024/1024/1024).toFixed(1)} GB · ${est.pct}%`;
  // header live badge
  const orders=(await idbGetAll('orders').catch(()=>[])); const open=orders.filter(o=> o.status==='open'||o.status==='sent').length;
  const badge=document.getElementById('role-badge');
  if(badge && open>0){ badge.textContent=(ROLE==='main'?'Main':'Station')+' · '+open+' open'; badge.classList.add('of-badge--gold'); } else if(badge){
    badge.textContent=ROLE==='main'?'Main': ROLE==='station'?'Station':'POS';
    badge.classList.remove('of-badge--gold');
  }
}

// role setup
async function initRoleUI(){
  const savedRole = await kvGet('role', null);
  const savedRoom = await kvGet('roomInfo', null);
  // strict gate: Main must have validated license (like APK LicenseGate)
  let validated='';
  try{ validated = (await kvGet('licenseKey','')) || localStorage.getItem('of_licenseKey') || ''; }catch{ validated = localStorage.getItem('of_licenseKey')||''; }
  validated = ofNormalizeKey(validated);
  const hasValidKey = validated && OF_KEY_RE.test(validated);
  if(savedRole==='main' && !hasValidKey){
    // block auto-enter — show license gate, stay on setup
    console.warn('Main without valid license — gate blocked');
    // ensure gate is visible (index.html will also show it)
    const gate=document.getElementById('view-license'); if(gate){ gate.hidden=false; gate.removeAttribute('hidden'); document.getElementById('of-app')?.classList.add('gate-hidden'); }
    return;
  }
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
  // app chrome (bottom nav, header actions) only exists once a role is entered — like the APK shell
  try{ document.body.classList.add('is-inapp'); }catch{}
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
    // station/main heartbeat — builds the "Stations in this room" panel
    if(cmd && cmd.type==='hello' && cmd.device){
      try{
        const seen=(await kvGet('stationsSeen', {}))||{};
        seen[String(cmd.device)] = {role: cmd.role||'station', at: Number(cmd.at)||Date.now()};
        const now=Date.now();
        for(const k of Object.keys(seen)){ if(now-(seen[k]?.at||0)>10*60*1000) delete seen[k]; }
        await kvSet('stationsSeen', seen);
        try{ window.OFRenderLivePanels?.(); }catch{}
      }catch{}
      return;
    }
    // guest table ordering: phone on the table asks for the menu
    if(cmd && cmd.type==='menu_request'){ r._lastRev=-1; r._lastPush=0; try{ await r.pushCheck(); }catch{} return; }
    // guest table ordering: order sent from a guest phone
    if(cmd && cmd.type==='order' && cmd.table && Array.isArray(cmd.items) && cmd.items.length){
      const o = { id:'ord-'+Date.now(), table: cmd.table, status:'sent', source:'qr', items: cmd.items, total: cmd.items.reduce((a,x)=> a+(Number(x.total)||0),0), createdAt: Date.now() };
      await idbPut('orders', o);
      const t=await idbGet('tables', cmd.table); if(t){ t.state='busy'; t.since=Date.now(); await idbPut('tables', t); }
      await kvSet('rev', Date.now());
      refreshAll(); // toast + sound + vibration fire here via the notify engine
      try{
        const s=await getSettings();
        if(s.autoPrint) window.OFKitchenPrint?.(o);
      }catch{}
      return;
    }
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

  // tabs — now also supports home + sync header/bottom nav
  function setTab(tab){
    $$('.side nav button').forEach(x=> x.classList.toggle('active', x.dataset.tab===tab));
    const pairs=[['home','tab-home'],['tables','tab-tables'],['menu','tab-menu'],['kitchen','tab-kitchen'],['stock','tab-stock'],['print','tab-print'],['settings','tab-settings']];
    for(const [k,id] of pairs){ const el=document.getElementById(id); if(el) el.hidden = (k!==tab); }
    // sync seg + bottom nav if present
    document.querySelectorAll('.of-nav__item, .seg button, [data-tab]').forEach(b=>{
      const v=b.getAttribute('data-tab'); if(!v) return;
      const on=v===tab; b.classList.toggle('is-active', on); if(b.classList.contains('of-nav__item')) b.setAttribute('aria-current', on?'page':'false');
    });
    if(tab==='home') renderHome();
    if(window.__ofShowTab && tab!=='home') { /* keep window helper in sync without loop */ }
  }
  // expose for header/bottom sheet
  window.__ofSetTab = setTab;
  $$('.side nav button').forEach(b=> b.addEventListener('click', ()=> setTab(b.dataset.tab)));
  // seg + bottom nav clicks already handled in index.html, but also wire here as fallback
  document.querySelectorAll('.seg button, .of-nav__item').forEach(b=> b.addEventListener('click', ()=>{ const t=b.getAttribute('data-tab'); if(t) setTab(t==='more'? 'settings': t); }));
  // tiles on home
  $$('#home-tiles [data-tab]').forEach(b=> b.addEventListener('click', ()=> setTab(b.getAttribute('data-tab'))));
  // table filters
  $$('#tab-tables [data-filter]').forEach(b=> b.addEventListener('click', ()=>{
    $$('#tab-tables [data-filter]').forEach(x=> x.classList.remove('active'));
    b.classList.add('active'); renderTables(b.dataset.filter);
  }));
  // role buttons
  $('[data-role="main"]')?.addEventListener('click', ()=>{ $('#setup-main').hidden=false; $('#setup-station').hidden=true; });
  $('[data-role="station"]')?.addEventListener('click', ()=>{ $('#setup-station').hidden=false; $('#setup-main').hidden=true; });
  // open room
  // Strict license gate — mirrors APK LicenseScreen: blank/invalid never opens room
  $('#btn-open-room')?.addEventListener('click', async ()=>{
    const btn=$('#btn-open-room'); btn.disabled=true; btn.textContent='Opening…';
    const shop = $('#shop-name').value.trim()||'My Shop';
    // license is the validated gate key — never TRIAL, never offline fallback
    let license = '';
    try{ license = (await kvGet('licenseKey','')) || localStorage.getItem('of_licenseKey') || $('#license-key')?.value.trim() || ''; }catch{ license = $('#license-key')?.value.trim()||''; }
    license = ofNormalizeKey(license);
    const hint = $('#open-room-hint') || $('#license-error');
    const setHint=(m, isErr=true)=>{
      const el=hint; if(!el) return;
      if(!m){ el.textContent='License already validated ✓ — room uses that key.'; el.style.color='var(--muted)'; return; }
      el.textContent=m; el.style.color=isErr? 'var(--danger)' : 'var(--muted)';
      if(isErr && el.id==='license-error'){ el.hidden=false; }
    };
    const KEY_RE=OF_KEY_RE;
    if(!license){ setHint('Enter license key first — OF-XXXX-XXXX-XXXX-XXXX. Open License gate and Activate.'); btn.disabled=false; btn.textContent='Open room & show QR'; return; }
    if(!KEY_RE.test(license)){
      setHint('Invalid license format — use OF-XXXX-XXXX-XXXX-XXXX.'); btn.disabled=false; btn.textContent='Open room & show QR';
      // surface inline on gate as well
      const ge=document.getElementById('license-error'); if(ge){ ge.textContent='Invalid format — use OF-XXXX-XXXX-XXXX-XXXX'; ge.hidden=false; ge.removeAttribute('hidden'); ge.style.display='block'; const inp=document.getElementById('license-key'); if(inp) inp.classList.add('is-error'); }
      return;
    }
    const id = await deviceId();
    try{
      // DB stores keys as OF-XXXX-… (dashed, exact match) — send dashed first.
      // API+D1 live on order-flow-v2.pages.dev (jathol.org has no /api functions),
      // so try the API origin first, then same-origin as a fallback.
      // content-type text/plain keeps it a CORS "simple request" (no preflight).
      let j=null, lastErr='key_invalid', firstJsonErr='';
      outer: for(const base of ['', RELAY_BASE]){ // same-origin proxy first (no CORS), API origin fallback
        for(const keyTry of [license, license.replace(/-/g,'')]){
          try{
            const r = await fetch(base+'/api/cloud/open', {method:'POST', headers:{'Content-Type':'text/plain'}, body: JSON.stringify({licenseKey: keyTry, deviceId: id, shopName: shop})});
            const jr = await r.json().catch(()=>null);
            if(jr && jr.ok){ j=jr; break outer; }
            lastErr = jr?.error || ('http_'+r.status);
            if(jr?.error && !firstJsonErr) firstJsonErr=jr.error;
          }catch(e){ lastErr='network'; }
        }
      }
      if(!j || !j.ok) throw new Error(firstJsonErr || lastErr);
      const base = RELAY_BASE;
      const pairing = pairingEncode(j.room, j.code, j.secret, base);
      $('#room-box').hidden=false;
      $('#join-code').textContent=j.code;
      $('#pairing-text').textContent=pairing;
      drawQR($('#qr'), pairing);
      await kvSet('roomInfo', {room:j.room, code:j.code, secret:j.secret, base});
      await kvSet('role','main'); ROLE='main';
      try{ localStorage.setItem('of_licenseValidated','1'); localStorage.setItem('of_licenseKey', license); }catch{}
      setHint('', false);
      $('#btn-enter-app').onclick=()=> enterApp({room:j.room, code:j.code, secret:j.secret, base});
    }catch(e){
      const msg=String(e).replace('Error:','').trim();
      const map={key_invalid:'License key is not valid. Double-check and try again.', invalid_key:'License key is not valid.', not_found:'Key not found — check with Jathol.', expired:'Key expired — contact support.', bound_other:'Key is already bound to another device.', plan:'Key has no cloud plan enabled — contact Jathol.', no_license:'License required.'};
      const friendly=map[msg]||('Could not open room: '+msg+' — valid license required. No offline fallback.');
      setHint(friendly, true);
      // also inline gate error
      const ge=document.getElementById('license-error'); if(ge){ ge.textContent=friendly; ge.hidden=false; }
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
      // same-origin proxy first, pairing base as fallback; preflight-free body
      let j=null, lastErr='no_room';
      for(const base of ['', info.base]){
        try{
          const r=await fetch(base+'/api/cloud/join', {method:'POST', headers:{'Content-Type':'text/plain'}, body: JSON.stringify({room:info.room, code:info.code, deviceId:id, role})});
          const jr=await r.json().catch(()=>null);
          if(jr){ j=jr; break; }
          lastErr='http_'+r.status;
        }catch(e){ lastErr=String(e.message||e); }
      }
      if(!j||!j.ok) throw new Error(j?.error||lastErr);
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
    if(!CUR_ORDER.items.length){ const t=$('#order-title'); if(t){ const old=t.textContent; t.textContent='Add at least one item first'; setTimeout(()=> t.textContent=old, 1400); } return; }
    CUR_ORDER.status='sent'; await idbPut('orders', CUR_ORDER);
    const t=await idbGet('tables', CUR_ORDER.table); if(t){ t.state='busy'; t.since=Date.now(); await idbPut('tables', t); }
    await kvSet('rev', Date.now()); refreshAll(); closeOrderSheet();
    const s = await getSettings();
    if(s.autoPrint) window.OFKitchenPrint?.(CUR_ORDER);
    window.OFToast?.('Sent to kitchen ✓', 'Table '+CUR_ORDER.table.replace(/^T/,'')+' ticket is live');
    if(RELAY){
      if(ROLE==='main') {} else await window.OFRelay.sendOrders();
    }
  });
  $('#btn-print-order-apple')?.addEventListener('click', ()=>{
    if(!CUR_ORDER || !CUR_ORDER.items.length) return;
    window.OFOpenReceiptPreview?.(CUR_ORDER);
  });
  $('#btn-close-order')?.addEventListener('click', closeOrderSheet);
  $('#sheet-order')?.addEventListener('click', (e)=>{ if(e.target.id==='sheet-order') closeOrderSheet(); });
  // ——— Settings module (APK parity) ———
  async function renderSettings(){
    const s = await getSettings();
    const val = (id,v)=>{ const el=document.getElementById(id); if(el) el.value=v; };
    const chk = (id,v)=>{ const el=document.getElementById(id); if(el) el.checked=!!v; };
    val('set-shop-name', s.shopName); val('set-shop-phone', s.shopPhone); val('set-currency', s.currency);
    val('set-tax', s.tax); val('set-svc', s.svc); val('set-receipt-head', s.receiptHead); val('set-receipt-foot', s.receiptFoot);
    val('set-copies', s.copies); val('set-paper', s.paper);
    chk('set-showqr', s.showQr); chk('set-auto-print', s.autoPrint); chk('set-kitchen-sound', s.kitchenSound); chk('set-qr-order', s.qrOrder);
    // license + device rows
    try{
      const key = (await kvGet('licenseKey','')) || localStorage.getItem('of_licenseKey') || '';
      const m = key ? key.slice(0,6)+'••••••'+key.slice(-4) : '—';
      const lk=document.getElementById('set-license-key'); if(lk) lk.textContent=m;
    }catch{}
    try{ const d=await deviceId(); const di=document.getElementById('set-device-id'); if(di) di.textContent=d; }catch{}
    const sl=document.getElementById('set-sync-line'); if(sl) sl.textContent=document.getElementById('sync-state')?.textContent||'—';
    renderQrTables().catch(()=>{});
  }
  async function renderQrTables(){
    const host = document.getElementById('qr-table-list'); if(!host) return;
    const s = await getSettings();
    host.innerHTML='';
    if(!s.qrOrder){ host.innerHTML='<div class="set-row" style="color:var(--muted);font-weight:600">Turn on “Let guests order by QR” to see your table QRs here.</div>'; return; }
    const info = await kvGet('roomInfo', null);
    if(!info){ host.innerHTML='<div class="set-row" style="color:var(--muted);font-weight:600">Open a room first (Setup → Open room & show QR) — table QRs carry your room key.</div>'; return; }
    const tables = await idbGetAll('tables');
    if(!tables.length){ host.innerHTML='<div class="set-row" style="color:var(--muted);font-weight:600">No tables yet.</div>'; return; }
    for(const t of tables){
      const d = {r:info.room, c:info.code, k:info.secret, b:info.base, t:t.id, shop:(await getSettings()).shopName};
      const url = location.origin + '/order.html#' + b64uEncode(new TextEncoder().encode(JSON.stringify(d)));
      const row = document.createElement('div'); row.className='qr-row';
      row.innerHTML = '<img alt="QR '+t.label+'"/><div class="info">'+t.label+' — guest ordering<small>'+url.slice(0,64)+'…</small></div><button class="set-btn" type="button">Download</button>';
      const img = row.querySelector('img');
      img.src = 'https://api.qrserver.com/v1/create-qr-code/?size=160x160&margin=6&data='+encodeURIComponent(url);
      row.querySelector('button').onclick=()=>{ const a=document.createElement('a'); a.href='https://api.qrserver.com/v1/create-qr-code/?size=640x640&margin=12&data='+encodeURIComponent(url); a.download='qr-'+t.label+'.png'; a.target='_blank'; a.rel='noopener'; a.click(); };
      host.appendChild(row);
    }
  }
  $('#set-shop-name')?.addEventListener('change', e=> saveSettings({shopName:e.target.value.trim()||'My Shop'}));
  $('#set-shop-phone')?.addEventListener('change', e=> saveSettings({shopPhone:e.target.value.trim()}));
  $('#set-currency')?.addEventListener('change', e=> saveSettings({currency:e.target.value.trim()||'RM'}));
  $('#set-tax')?.addEventListener('change', e=> saveSettings({tax:Math.max(0, Math.min(40, Number(e.target.value)||0))}));
  $('#set-svc')?.addEventListener('change', e=> saveSettings({svc:Math.max(0, Math.min(30, Number(e.target.value)||0))}));
  $('#set-receipt-head')?.addEventListener('change', e=> saveSettings({receiptHead:e.target.value}));
  $('#set-receipt-foot')?.addEventListener('change', e=> saveSettings({receiptFoot:e.target.value}));
  $('#set-copies')?.addEventListener('change', e=> saveSettings({copies:Math.max(1, Math.min(4, Number(e.target.value)||1))}));
  $('#set-paper')?.addEventListener('change', e=> saveSettings({paper:e.target.value}));
  $('#set-showqr')?.addEventListener('change', e=> saveSettings({showQr:e.target.checked}));
  $('#set-auto-print')?.addEventListener('change', e=> saveSettings({autoPrint:e.target.checked}));
  $('#set-kitchen-sound')?.addEventListener('change', e=> saveSettings({kitchenSound:e.target.checked}));
  $('#set-qr-order')?.addEventListener('change', async e=>{ await saveSettings({qrOrder:e.target.checked}); renderQrTables(); });
  $('#btn-qr-all')?.addEventListener('click', ()=>{
    document.querySelectorAll('#qr-table-list .qr-row button').forEach((b,i)=> setTimeout(()=> b.click(), i*350));
  });
  async function showReport(z){
    const out = document.getElementById('report-out'); if(!out) return;
    const orders = await idbGetAll('orders').catch(()=>[]);
    const start = new Date(); start.setHours(0,0,0,0);
    const today = orders.filter(o=> (o.createdAt||0) >= start.getTime());
    const paid = today.filter(o=> o.status==='paid'||o.status==='closed');
    const unpaid = today.filter(o=> o.status!=='paid' && o.status!=='closed' && o.status!=='void');
    const taken = paid.reduce((a,o)=>{ const s=o.items?.reduce((x,i)=>x+(i.total||0),0)||o.total||0; return a+s; },0);
    const waiting = unpaid.reduce((a,o)=>{ const s=o.items?.reduce((x,i)=>x+(i.total||0),0)||o.total||0; return a+s; },0);
    const byMethod = {};
    for(const o of paid){ const m=o.payment?.method||'cash'; byMethod[m]=(byMethod[m]||0)+((o.items||[]).reduce((x,i)=>x+(i.total||0),0)||o.total||0); }
    const best = {};
    for(const o of today) for(const it of (o.items||[])) best[it.name]=(best[it.name]||0)+(it.qty||1);
    const top = Object.entries(best).sort((a,b)=>b[1]-a[1]).slice(0,5);
    out.hidden=false;
    out.textContent =
      (z ? 'End of day (Z) — time to close' : 'Quick check (X) — today so far') + '\n' +
      '───────────────────────\n' +
      'Bills paid today    : '+paid.length+'\n' +
      'Money taken         : '+fmtMoney(taken)+'\n' +
      'Still unpaid bills  : '+unpaid.length+' ('+fmtMoney(waiting)+')\n' +
      'Average per bill    : '+fmtMoney(paid.length? taken/paid.length : 0)+'\n' +
      (Object.keys(byMethod).length? '───────────────────────\n' +
      Object.entries(byMethod).map(([m,v])=> 'Paid by '+m.padEnd(6,' ')+': '+fmtMoney(v)).join('\n')+'\n' : '') +
      (top.length? '───────────────────────\nBest sellers today:\n'+top.map(([n,q])=> '  · '+n+' × '+q).join('\n') : '───────────────────────\nNothing sold yet today.') +
      (z && paid.length ? '\n───────────────────────\nLooks good? The day is ready to close.' : '');
    out.scrollIntoView({behavior:'smooth', block:'nearest'});
  }
  $('#btn-report-x')?.addEventListener('click', ()=> showReport(false));
  $('#btn-report-z')?.addEventListener('click', ()=> showReport(true));
  window.__ofRenderSettings = renderSettings;
  renderSettings().catch(()=>{});
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
  // print tab buttons are wired in the APK MIRROR block at the end of this file
  $('#chk-relay-print')?.addEventListener('change', async(e)=>{ await kvSet('relayPrint', e.target.checked); });
  $('#chk-gateway')?.addEventListener('change', async(e)=>{ await kvSet('gateway', e.target.checked); if(e.target.checked) $('#gateway-log').textContent='Gateway on — waiting for print jobs…'; });
  // restore saved checks
  kvGet('relayPrint', false).then(v=>{ const el=$('#chk-relay-print'); if(el) el.checked=!!v; });
  kvGet('gateway', false).then(v=>{ const el=$('#chk-gateway'); if(el) el.checked=!!v; if(v) $('#gateway-log').textContent='Gateway on — waiting for print jobs…'; });
  // PWA install handling — guide is popup-only, never inline
  let deferredPrompt=null;
  window.addEventListener('beforeinstallprompt', (e)=>{ e.preventDefault(); deferredPrompt=e; window.__ofDeferredPrompt=e; const b=$('#btn-install'); const pb=$('#btn-install-popup'); const hint=$('#install-hint'); if(b) b.hidden=false; if(pb) pb.hidden=false; if(hint) hint.textContent='Tap Add to Home Screen for install guide — Install now available.'; });
  window.addEventListener('appinstalled', ()=>{ const b=$('#btn-install'); if(b) b.hidden=true; const pb=$('#btn-install-popup'); if(pb) pb.hidden=true; const hint=$('#install-hint'); if(hint) hint.textContent='App installed ✓ — launch from Home Screen for standalone mode.'; });
  // iOS standalone detection — hint now lives in sheet, not inline
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone===true;
  if(isStandalone){
    const hint=$('#install-hint'); if(hint) hint.textContent='Running as installed app ✓ — no browser chrome.';
  } else if(/iPad|iPhone|iPod/.test(navigator.userAgent)){
    const hint=$('#install-hint'); if(hint && !hint.textContent) hint.textContent='iPhone: tap Share ⎙ → Add to Home Screen → Add (Safari only).';
  }
});

/* ============================================================
   APK MIRROR v2 — theme toggle, toast notifications,
   kitchen/order-taker alerts, instant AirPrint receipt.
   ============================================================ */
(function(){
  'use strict';
  const $=(id)=>document.getElementById(id);
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);

  // ——— toast: dedupe + max 2 visible, covers nothing for long ———
  let _toastSeq = 0;
  function toast(main, sub, keepMs){
    const root = $('toast-root'); if(!root) return alert(sub? main+'\n'+sub : main);
    // same-message toast? just show it again — don't pile up
    const key = main+'·'+(sub||'');
    const dup = root.querySelector('[data-key="'+CSS.escape(key)+'"]');
    if(dup) dup.remove();
    while(root.children.length>=2) root.firstChild.remove();
    const el = document.createElement('div'); el.className='of-toast'; el.dataset.key=key;
    el.textContent = main;
    if(sub){ const s=document.createElement('small'); s.textContent=sub; el.appendChild(s); }
    root.appendChild(el);
    requestAnimationFrame(()=> el.classList.add('is-in'));
    const ms = keepMs||3600;
    const id = ++_toastSeq;
    setTimeout(()=>{ if(id<=_toastSeq){ el.classList.remove('is-in'); setTimeout(()=> el.remove(), 280); } }, ms);
  }
  window.OFToast = toast;

  // ——— sound (unlocked by first touch) + vibration ———
  let _ac=null;
  function _unlockAudio(){
    try{
      if(!_ac) _ac = new (window.AudioContext||window.webkitAudioContext)();
      if(_ac.state==='suspended') _ac.resume().catch(()=>{});
      // tiny silent tick so iOS marks audio unlocked
      const b=_ac.createBuffer(1,1,22050), src=_ac.createBufferSource(); src.buffer=b; src.connect(_ac.destination); src.start(0);
    }catch{}
  }
  ['pointerdown','touchstart','keydown','click'].forEach(ev=> document.addEventListener(ev, _unlockAudio, {passive:true}));
  function beep(freq, at){
    if(!_ac) return false;
    try{
      const o=_ac.createOscillator(), g=_ac.createGain();
      o.connect(g); g.connect(_ac.destination);
      o.type='triangle'; o.frequency.value=freq||880;
      const t0=(_ac.currentTime)+(at||0);
      g.gain.setValueAtTime(.32,t0);
      g.gain.exponentialRampToValueAtTime(.001,t0+.3);
      o.start(t0); o.stop(t0+.32);
      return true;
    }catch{ return false; }
  }
  function ding(kind){
    _unlockAudio();
    // rising chime — loud enough to hear in a kitchen
    if(kind==='ready'){ beep(660); beep(880,.18); }
    else if(kind==='paid'){ beep(523); beep(784,.14); beep(1047,.28); }
    else { beep(880); beep(1320,.16); beep(1760,.32); }
  }
  function buzz(pattern){ try{ if('vibrate' in navigator) navigator.vibrate(pattern); }catch{} }

  // ——— theme (System/Light/Dark) — mirrors APK theme picker ———
  async function getThemePref(){ try{ return (await kvGet('theme', 'system')) || 'system'; }catch{ return 'system'; } }
  async function setThemePref(t){
    await kvSet('theme', t);
    applyTheme(t);
    toast('Theme: '+(t==='system'?'Auto (follows phone)':t[0].toUpperCase()+t.slice(1)));
  }
  function applyTheme(pref){
    const t = pref || (getThemePref._cached || 'system');
    getThemePref._cached = t;
    const dark = t==='dark' || (t==='system' && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    const meta=document.getElementById('theme-color-meta');
    if(meta) meta.setAttribute('content', dark ? '#0F1512' : '#FAF7F2');
    document.querySelectorAll('#seg-theme button').forEach(b=> b.classList.toggle('is-on', b.dataset.t===t));
  }
  async function initTheme(){
    const t = await getThemePref();
    applyTheme(t);
    try{ await getSettings(); }catch{} // warm the print/settings cache
    if(window.matchMedia){
      try{ window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', ()=> applyTheme()); }catch{}
    }
    document.querySelectorAll('#seg-theme button').forEach(b=> b.addEventListener('click', ()=> setThemePref(b.dataset.t)));
  }

  // ——— shop info for receipts (from Settings) ———
  async function shopFor(){
    const s = await getSettings();
    return s;
  }

  // ——— Receipt engine: builds the paper + calls the REAL system print dialog ———
  function esc(s){ return String(s??'').replace(/[&<>]/g, c=> ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }
  function buildReceiptDom(order, s, opts){
    const kitchen = opts && opts.type==='kitchen';
    const cur = s.currency||'RM';
    const m = n=> cur+' '+(Number(n)||0).toFixed(2);
    const lines = (order.items||[]).map(it=> '<div class="rp-line"><span>'+esc(it.name)+' × '+it.qty+'</span>' + (kitchen?'':'<span>'+m(it.total||0)+'</span>') + '</div>').join('');
    const sub = (order.items||[]).reduce((a,i)=> a+(Number(i.total)||0), 0);
    const tax = sub*(Number(s.tax)||0)/100, svc = sub*(Number(s.svc)||0)/100;
    const grand = sub+tax+svc;
    return ''
      + '<div style="font-family:ui-monospace,Menlo,monospace;color:#111;width:62mm;margin:0 auto">'
      + '<div style="text-align:center;border-bottom:1.5px dashed #111;padding:6px 0 8px">'
      +   (kitchen ? '<b style="font-size:16px">KITCHEN TICKET</b>' : '<b style="font-size:16px">'+esc(s.shopName)+'</b>')
      +   (!kitchen && s.receiptHead ? '<div style="font-size:11px;margin-top:2px">'+esc(s.receiptHead)+'</div>' : '')
      +   (!kitchen && s.shopPhone ? '<div style="font-size:11px;color:#444">'+esc(s.shopPhone)+'</div>' : '')
      +   '<div style="font-size:10px;color:#444;margin-top:3px">'+new Date().toLocaleString()+' · Table '+esc(String(order.table||'').replace(/^T/,''))+(order.id?' · #'+esc(String(order.id).slice(-6)):'')+'</div>'
      + '</div>'
      + (lines || '<div class="rp-line"><span>No items</span></div>')
      + (kitchen ? '' :
          '<div style="display:flex;justify-content:space-between;font-size:11px;margin-top:6px;padding-bottom:3px;border-bottom:1px dotted #ccc"><span style="float:none">Subtotal</span><span>'+m(sub)+'</span></div>'
        + ((Number(s.tax)||0)? '<div style="display:flex;justify-content:space-between;font-size:11px;padding:2px 0;border-bottom:1px dotted #ccc"><span>Tax ('+s.tax+'%)</span><span>'+m(tax)+'</span></div>':'')
        + ((Number(s.svc)||0)? '<div style="display:flex;justify-content:space-between;font-size:11px;padding:2px 0;border-bottom:1px dotted #ccc"><span>Service ('+s.svc+'%)</span><span>'+m(svc)+'</span></div>':'')
        + '<div style="display:flex;justify-content:space-between;font-weight:800;font-size:15px;border-top:2px solid #111;margin-top:4px;padding-top:4px"><span>TOTAL</span><span>'+m(grand)+'</span></div>')
      + (order.payment ? '<div style="margin-top:6px;padding-top:5px;border-top:1px dotted #ccc;font-size:11px">'
        + (order.status==='paid' ? '<div style="text-align:center;font-weight:800;font-size:13px;letter-spacing:2px;margin-bottom:3px">PAID ✓</div>' : '')
        + '<div style="display:flex;justify-content:space-between;padding:2px 0"><span>Paid with '+esc(order.payment.method||'cash')+'</span><span>'+m(order.payment.tendered||grand)+'</span></div>'
        + (Number(order.payment.change)>0 ? '<div style="display:flex;justify-content:space-between;padding:2px 0"><span>Change</span><span>'+m(order.payment.change)+'</span></div>' : '')
        + (order.payment.split ? '<div style="display:flex;justify-content:space-between;padding:2px 0"><span>Split: '+esc(order.payment.method2)+'</span><span>'+m(order.payment.splitAmt)+'</span></div>' : '')
        + '</div>' : '')
      + '<div style="text-align:center;font-size:10px;color:#666;margin-top:8px;border-top:1.5px dashed #111;padding-top:6px">'
      +   (kitchen ? 'Fire now — '+new Date().toLocaleTimeString() : esc(s.receiptFoot||'Thank you — please come again'))
      + '</div></div>'
      + '<style>.rp-line{display:flex;justify-content:space-between;font-size:12px;padding:3px 0;border-bottom:1px dotted #ccc}</style>';
  }
  function printReceipt(order, opts){
    const root = document.getElementById('print-root');
    if(!root) return;
    // sync path (keeps the iOS user-gesture alive → AirPrint dialog opens instantly)
    const run = (s)=>{
      root.innerHTML = buildReceiptDom(order, s, opts||{});
      window.print();
    };
    if(_setCache) run(_setCache);
    else getSettings().then(run); // rare: first-ever print before cache warms
  }
  window.OFPrintReceipt = printReceipt;
  window.OFBuildReceiptDom = buildReceiptDom;
  // Kitchen slip on "Send to kitchen": direct print on Android; on iPhone a toast (iOS needs a tap)
  window.OFKitchenPrint = function(order){
    try{ printReceipt(order, {type:'kitchen'}); }catch{}
    if(isIOS) toast('Kitchen slip printing…', 'If the print page didn’t open, tap “Print slip” on the Kitchen tab');
  };
  window.OFAfterReady = function(order){
    toast('Marked ready ✓', 'Table '+String(order.table||'').replace(/^T/,'')+' — takers notified');
    try{ if(RELAY && ROLE==='station' && window.OFRelay && window.OFRelay.sendOrders) window.OFRelay.sendOrders(); }catch{}
  };

  // ——— live notifications engine (new ticket → kitchen + takers; ready → takers) ———
  window.OFCheckOrders = async function(){
    let orders=[];
    try{ orders = await idbGetAll('orders'); }catch{}
    const s = await getSettings();
    const bag = window._ofMemo || (window._ofMemo = {map:new Map(), seeded:false});
    const live = orders.filter(o=> o.status==='open'||o.status==='sent');
    const badge = $('badge-kitchen');
    if(badge){ badge.textContent = String(live.length); badge.hidden = live.length===0; }
    for(const o of orders){
      const prev = bag.map.get(o.id);
      if(prev===undefined && (o.status==='open'||o.status==='sent')){
        if(bag.seeded){
          if(s.kitchenSound) ding('ticket');
          buzz([120,60,160]);
          toast('New ticket — Table '+String(o.table||'').replace(/^T/,''),
            (o.source==='qr' ? 'Guest ordered by QR code · ' : '') + (o.items||[]).length + ' item(s) to fire');
        }
      }
      if(prev!==undefined && prev!=='ready' && o.status==='ready'){
        if(s.kitchenSound) ding('ready');
        buzz([80,40,120]);
        toast('Table '+String(o.table||'').replace(/^T/,'')+' — ready ✓', 'Please serve the guest');
      }
      if(prev!==undefined && prev!=='paid' && prev!=='closed' && o.status==='paid'){
        if(s.kitchenSound) ding('paid');
        buzz([60]);
        const m=o.payment?.method||'';
        toast('Table '+String(o.table||'').replace(/^T/,'')+' — paid ✓'+ (m?' ('+m+')':''), 'Sale recorded · table freeing up');
      }
      bag.map.set(o.id, o.status);
      if(bag.map.size>300) bag.map.clear(), bag.map.set(o.id, o.status); // bound memory
    }
    bag.seeded = true;
    try{ window.OFRenderLivePanels?.(); }catch{}
  };

  // ——— wire Print tab + sample receipt ———
  function sampleOrder(){
    return {id:'ord-test', table:'T1', items:[{name:'Cappuccino', qty:1, price:12, total:12},{name:'Nasi Lemak', qty:2, price:18, total:36}]};
  }
  function wirePrintTab(){
    $('btn-print-apple')?.addEventListener('click', ()=> printReceipt(sampleOrder()));
    $('btn-print-test')?.addEventListener('click', ()=> printReceipt(sampleOrder()));
    $('btn-print-bt')?.addEventListener('click', async ()=>{
      try{ await printViaBluetooth(sampleOrder(), await shopFor()); }
      catch(e){ toast('Bluetooth print failed', String(e?.message||e).slice(0,120)); }
    });
  }

  // ——— Settings shortcut: open Print page ———
  function wireGotoPrint(){ $('btn-goto-print')?.addEventListener('click', ()=> document.querySelector('[data-tab="print"]')?.click()); }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', ()=>{ initTheme(); wirePrintTab(); wireGotoPrint(); });
  else { initTheme(); wirePrintTab(); wireGotoPrint(); }
})();

/* ============================================================
   v23 — APK MIRROR: pay sheet (order.paySheet), payment queue,
   ready strip, stations panel + heartbeat, receipt preview
   ============================================================ */
(function(){
  'use strict';
  const $=(id)=>document.getElementById(id);
  function sNow(){ return _setCache || SET_DEFAULTS; }
  function moneyN(n){ const cur=(sNow().currency)||'RM'; return cur+' '+(Number(n)||0).toFixed(2); }

  function calcBill(o){
    const s=sNow();
    const sub=(o.items||[]).reduce((a,i)=> a+(Number(i.total)||0),0);
    const tax=sub*(Number(s.tax)||0)/100, svc=sub*(Number(s.svc)||0)/100;
    return {sub, tax, svc, due: sub+tax+svc};
  }

  // ——— PAY SHEET (mirrors order_screen._pay) ———
  const PAY={order:null, method:'cash', split:false, method2:'card', splitAmt:'', tender:''};
  function openPay(order){
    if(!order || !(order.items||[]).length){ window.OFToast?.('Nothing to pay','Add items to this order first'); return; }
    Object.assign(PAY,{order, method:'cash', split:false, method2:'card', splitAmt:'', tender:''});
    const sh=$('sheet-pay'); if(!sh) return;
    sh.classList.add('is-open'); sh.setAttribute('aria-hidden','false');
    renderPay();
  }
  window.OFOpenPay=openPay;
  function closePay(){ const sh=$('sheet-pay'); if(!sh) return; sh.classList.remove('is-open'); sh.setAttribute('aria-hidden','true'); }
  function dueInfo(){
    const b=calcBill(PAY.order);
    const splitAmt=PAY.split ? (Number(PAY.splitAmt)||0) : 0;
    const primary=PAY.split ? b.due-splitAmt : b.due;
    return {...b, splitAmt, primary};
  }
  function renderPay(){
    const d=dueInfo();
    const bd=$('pay-breakdown'); if(bd){
      bd.innerHTML=
        '<div class="pay-amt">'+moneyN(d.due)+'</div>'
        +'<div class="pay-line muted"><span>Subtotal</span><span>'+moneyN(d.sub)+'</span></div>'
        +((sNow().tax||0)?'<div class="pay-line muted"><span>Tax ('+sNow().tax+'%)</span><span>'+moneyN(d.tax)+'</span></div>':'')
        +((sNow().svc||0)?'<div class="pay-line muted"><span>Service ('+sNow().svc+'%)</span><span>'+moneyN(d.svc)+'</span></div>':'')
        +(PAY.split&&d.splitAmt?'<div class="pay-line muted"><span>Second method ('+PAY.method2+')</span><span>'+moneyN(d.splitAmt)+'</span></div>':'')
        +'<div class="pay-line grand"><span>'+(PAY.split?('On '+PAY.method):'Total to pay')+'</span><span>'+moneyN(d.primary)+'</span></div>';
    }
    document.querySelectorAll('#pay-methods .pay-chip').forEach(b=> b.classList.toggle('is-on', b.dataset.m===PAY.method));
    document.querySelectorAll('#pay-methods2 .pay-chip').forEach(b=> b.classList.toggle('is-on', b.dataset.m===PAY.method2));
    const sp=$('pay-split-on'); if(sp) sp.checked=PAY.split;
    const sb=$('pay-split-box'); if(sb) sb.hidden=!PAY.split;
    const sa=$('pay-split-amount'); if(sa && document.activeElement!==sa) sa.value=PAY.splitAmt;
    const needsCash = PAY.method==='cash' || (PAY.split&&PAY.method2==='cash');
    const cashTarget = PAY.method==='cash' ? d.primary : d.splitAmt;
    const rec=Number(PAY.tender)||0;
    const tEl=$('pay-tender');
    const pad=$('pay-pad');
    if(tEl) tEl.textContent = needsCash ? (PAY.tender===''?'0':PAY.tender) : '—';
    if(pad) pad.style.display = needsCash ? '' : 'none';
    const ch=$('pay-change');
    if(ch){
      if(!needsCash){ ch.textContent=''; ch.classList.remove('short'); }
      else if(rec+0.001>=cashTarget && PAY.tender!==''){ ch.textContent='Change to give:  '+moneyN(rec-cashTarget); ch.classList.remove('short'); }
      else if(PAY.tender!==''){ ch.textContent='Cash is short — needs '+moneyN(cashTarget-rec)+' more'; ch.classList.add('short'); }
      else { ch.textContent=''; ch.classList.remove('short'); }
    }
    const cf=$('btn-pay-confirm');
    if(cf){
      const splitOk=!PAY.split || (d.splitAmt>0.001 && d.splitAmt<d.due-0.001);
      const cashOk=!needsCash || rec+0.001>=cashTarget;
      const ok=splitOk && cashOk && d.primary>0.001;
      cf.disabled=!ok; cf.style.opacity=ok?'1':'.5';
    }
  }
  function wirePay(){
    document.querySelectorAll('#pay-methods .pay-chip').forEach(b=> b.addEventListener('click', ()=>{ PAY.method=b.dataset.m; renderPay(); }));
    document.querySelectorAll('#pay-methods2 .pay-chip').forEach(b=> b.addEventListener('click', ()=>{ PAY.method2=b.dataset.m; renderPay(); }));
    $('pay-split-on')?.addEventListener('change', e=>{ PAY.split=!!e.target.checked; PAY.splitAmt=''; renderPay(); });
    $('pay-split-amount')?.addEventListener('input', e=>{ PAY.splitAmt=e.target.value; renderPay(); });
    $('pay-pad')?.addEventListener('click', e=>{
      const k=e.target?.textContent; if(!k) return;
      if(e.target.classList.contains('exact')){ PAY.tender=String(dueInfo().primary.toFixed(2)); }
      else if(k==='⌫'){ PAY.tender=PAY.tender.slice(0,-1); }
      else if(k==='.' && PAY.tender.includes('.')) return;
      else { PAY.tender=(PAY.tender+k).replace(/^0+(?=\d)/,''); }
      renderPay();
    });
    $('btn-pay-close')?.addEventListener('click', closePay);
    $('sheet-pay')?.addEventListener('click', e=>{ if(e.target.id==='sheet-pay') closePay(); });
    $('btn-pay-confirm')?.addEventListener('click', async()=>{
      const d=dueInfo();
      const splitOk=!PAY.split || (d.splitAmt>0.001 && d.splitAmt<d.due-0.001);
      if(!splitOk){ window.OFToast?.('Split amount is wrong','It must be less than the total'); return; }
      const needsCash = PAY.method==='cash' || (PAY.split&&PAY.method2==='cash');
      const cashTarget = PAY.method==='cash' ? d.primary : d.splitAmt;
      const rec=needsCash ? (Number(PAY.tender)||0) : cashTarget;
      if(needsCash && rec+0.001<cashTarget){ window.OFToast?.('Cash is short','Needs '+moneyN(cashTarget-rec)+' more'); return; }
      const o=PAY.order;
      // 1) system print sheet FIRST — keeps the tap gesture alive
      o.payment={method:PAY.method, method2:PAY.split?PAY.method2:null, splitAmt:PAY.split?d.splitAmt:0, split:PAY.split, tendered:+rec.toFixed(2), change:+(rec-cashTarget).toFixed(2)};
      o.status='paid'; o.paidAt=Date.now();
      try{ window.OFPrintReceipt?.(o); }catch{}
      // 2) persist + sync + ui
      await idbPut('orders', o);
      const unpaid = (await idbGetAll('orders')).filter(x=> x.table===o.table && x.status!=='paid' && x.status!=='closed' && x.status!=='void' && x.id!==o.id);
      if(!unpaid.length){ const t=await idbGet('tables', o.table); if(t){ t.state='free'; t.since=null; await idbPut('tables', t); } }
      await kvSet('rev', Date.now());
      closePay(); closeOrderSheet();
      window.OFToast?.('Paid ✓ '+moneyN(d.due)+(needsCash&&o.payment.change>0?' — change '+moneyN(o.payment.change):''), 'Receipt printed · table is free');
      try{ if(RELAY && ROLE==='station' && window.OFRelay?.sendOrders) await window.OFRelay.sendOrders(); }catch{}
      refreshAll();
      openReceiptPreview(o);
    });
  }

  // ——— Receipt preview (the "Apple print page") ———
  function openReceiptPreview(order){
    const sh=$('sheet-receipt'); const pv=$('receipt-preview'); if(!sh||!pv) return;
    pv.innerHTML = window.OFBuildReceiptDom
      ? window.OFBuildReceiptDom(order, sNow(), {})
      : '<p style="font-family:monospace">Receipt unavailable</p>';
    sh.classList.add('is-open'); sh.setAttribute('aria-hidden','false');
    sh._order=order;
  }
  window.OFOpenReceiptPreview=openReceiptPreview;
  function wireReceipt(){
    $('btn-receipt-close')?.addEventListener('click', ()=> $('sheet-receipt')?.classList.remove('is-open'));
    $('sheet-receipt')?.addEventListener('click', e=>{ if(e.target.id==='sheet-receipt') e.currentTarget.classList.remove('is-open'); });
    $('btn-receipt-print')?.addEventListener('click', ()=>{
      const o=$('sheet-receipt')?._order; if(o) window.OFPrintReceipt?.(o);
    });
  }

  // ——— LIVE PANELS: ready strip, payment queue, stations ———
  async function renderLivePanels(){
    const orders=await idbGetAll('orders').catch(()=>[]);
    // ready strip
    const ready=orders.filter(o=> o.status==='ready');
    const strip=$('ready-strip');
    if(strip){
      strip.hidden=!ready.length;
      strip.innerHTML='';
      for(const o of ready){
        const el=document.createElement('div'); el.className='ready-chip';
        el.innerHTML='<span class="wh">🔔</span><span class="ttl">Table '+String(o.table||'').replace(/^T/,'')+' — ready to serve<small class="sub" style="display:block">'+(o.items||[]).length+' dish(es) waiting for the guest</small></span><button type="button">Served ✓</button>';
        el.querySelector('button').onclick=async()=>{
          o.status='served'; await idbPut('orders', o); await kvSet('rev', Date.now());
          window.OFToast?.('Table '+String(o.table||'').replace(/^T/,'')+' served ✓');
          try{ if(RELAY && ROLE==='station' && window.OFRelay?.sendOrders) window.OFRelay.sendOrders(); }catch{}
          refreshAll();
        };
        strip.appendChild(el);
      }
    }
    // payment queue — every unpaid bill
    const unpaid=orders.filter(o=> o.status!=='paid'&&o.status!=='closed'&&o.status!=='void');
    const card=$('payqueue-card'); const list=$('payqueue-list');
    if(card&&list){
      card.hidden=!unpaid.length;
      list.innerHTML='';
      for(const o of unpaid){
        const d=calcBill(o);
        const age=Math.max(0,Math.round((Date.now()-(o.createdAt||Date.now()))/60000));
        const row=document.createElement('div'); row.className='qrow';
        row.innerHTML='<div class="meta"><b>Table '+String(o.table||'').replace(/^T/,'')+' · '+(o.items||[]).length+' item(s)</b><small>'+(o.status==='ready'?'Ready to serve':o.status==='sent'?'In the kitchen':'Being taken')+' · '+age+' min</small></div><span class="amt">'+moneyN(d.due)+'</span><button class="pay-chip" type="button" style="background:#D49E35;border-color:#D49E35;color:#2b1d00">Pay</button>';
        row.querySelector('button').onclick=()=> openPay(o);
        list.appendChild(row);
      }
    }
    // stations panel
    const host=$('stations-list');
    if(host){
      let seen={}; try{ seen=(await kvGet('stationsSeen', {}))||{}; }catch{}
      let me=''; try{ me=await deviceId(); }catch{}
      try{ seen[me]={role:(ROLE==='main'?'Main · we hold the license':'Station · this device'), at:Date.now()}; }catch{}
      const entries=Object.entries(seen).sort((a,b)=> b[1].at-a[1].at);
      host.innerHTML='';
      if(!entries.length){
        host.innerHTML='<p class="muted" style="margin:0;font-weight:600;font-size:13px">No devices yet. Open Setup → “Open room & show QR”, then join from your other phones — they appear here, live.</p>';
      }
      for(const [dev,info] of entries){
        const ageSec=Math.round((Date.now()-(info.at||0))/1000);
        const live=ageSec<75 && dev!==me;
        const row=document.createElement('div'); row.className='qrow';
        row.innerHTML='<span class="live-dot'+(dev===me?'':' '+(live?'':'off'))+'"></span><div class="meta"><b>'+(dev===me?'This device':dev)+'</b><small>'+(info.role||'station')+(dev===me?'':' · '+(live?'live now':'seen '+fmtAgo(ageSec)))+'</small></div><span class="amt" style="font-size:12px;color:var(--muted)">'+(live?'● online':'idle')+'</span>';
        host.appendChild(row);
      }
    }
  }
  function fmtAgo(sec){
    if(sec<60) return sec+'s ago';
    const m=Math.floor(sec/60); if(m<60) return m+'m ago';
    return Math.floor(m/60)+'h ago';
  }
  window.OFRenderLivePanels=renderLivePanels;

  // ——— station heartbeat: every 45s say hello to the room ———
  let _dev=null;
  async function myDev(){ if(_dev) return _dev; try{ _dev= await deviceId(); }catch{ _dev='web-'+Math.random().toString(36).slice(2,8); } return _dev; }
  setInterval(async()=>{
    if(!RELAY || !window.OFRelay) return;
    try{
      const dev=await myDev();
      const role=(ROLE==='main')?'main':((await kvGet('stationRole','station'))||'station');
      if(typeof window.OFRelay.send==='function'){ await window.OFRelay.send({type:'hello', device:'web-'+String(dev).slice(-8), role, at:Date.now()}); }
    }catch{}
  }, 45000);

  // ——— wire it all ———
  function wire(){
    wirePay(); wireReceipt();
    $('btn-pay-order')?.addEventListener('click', ()=>{ if(CUR_ORDER) openPay(CUR_ORDER); });
    renderLivePanels().catch(()=>{});
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', wire); else wire();
})();
