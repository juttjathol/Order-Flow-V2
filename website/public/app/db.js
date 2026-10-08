// Order Flow Web — IndexedDB (no account needed)
// Tiny promisified wrapper; schema mirrors flutter_app/lib/services/database_service.dart
// Everything encrypted-at-rest is not required — shop file is local-only.
// Export JSON is compatible with native: {meta, tables, products, stock, orders, customers}
const DB_NAME = 'orderflow-web';
const DB_VER = 4;
const STORES = ['kv','products','tables','orders','stock','customers','settings','printQueue'];

function openDB(){
  return new Promise((res, rej)=>{
    const req = indexedDB.open(DB_NAME, DB_VER);
    req.onupgradeneeded = () => {
      const db = req.result;
      for(const s of STORES){
        if(!db.objectStoreNames.contains(s)) db.createObjectStore(s, {keyPath: s==='kv'?'k':'id'});
      }
      // migrate: ensure indexes
      if(!db.objectStoreNames.contains('orders')) db.createObjectStore('orders',{keyPath:'id'});
    };
    req.onsuccess = ()=> res(req.result);
    req.onerror = ()=> rej(req.error);
  });
}
async function idbPut(store, value){
  const db = await openDB();
  return new Promise((res, rej)=>{
    const tx = db.transaction(store,'readwrite'); tx.objectStore(store).put(value);
    tx.oncomplete=()=>res(); tx.onerror=()=>rej(tx.error);
  });
}
async function idbGet(store, key){
  const db = await openDB();
  return new Promise((res, rej)=>{
    const tx = db.transaction(store,'readonly');
    const q = tx.objectStore(store).get(key);
    q.onsuccess=()=>res(q.result||null); q.onerror=()=>rej(q.error);
  });
}
async function idbGetAll(store){
  const db = await openDB();
  return new Promise((res, rej)=>{
    const tx = db.transaction(store,'readonly');
    const q = tx.objectStore(store).getAll();
    q.onsuccess=()=>res(q.result||[]); q.onerror=()=>rej(q.error);
  });
}
async function idbDel(store, key){
  const db = await openDB();
  return new Promise((res, rej)=>{
    const tx = db.transaction(store,'readwrite'); tx.objectStore(store).delete(key);
    tx.oncomplete=()=>res(); tx.onerror=()=>rej(tx.error);
  });
}
async function idbClear(store){
  const db = await openDB();
  return new Promise((res, rej)=>{
    const tx = db.transaction(store,'readwrite'); tx.objectStore(store).clear();
    tx.oncomplete=()=>res(); tx.onerror=()=>rej(tx.error);
  });
}
// kv helpers
const kvGet = (k, fallback=null) => idbGet('kv', k).then(v=> v ? v.v : fallback);
const kvSet = (k, v) => idbPut('kv', {k, v});

// Export: produce native-compatible JSON (also web-only full snapshot)
async function exportBackup(){
  const [products, tables, orders, stock, customers, settings] = await Promise.all([
    idbGetAll('products'), idbGetAll('tables'), idbGetAll('orders'), idbGetAll('stock'), idbGetAll('customers'), idbGetAll('settings')
  ]);
  const kvPairs = await idbGetAll('kv');
  const kv = Object.fromEntries(kvPairs.map(r=>[r.k,r.v]));
  const blob = {
    meta:{app:'Order Flow Web', v:1, exportedAt: new Date().toISOString(), device: kv.deviceId||''},
    kv, products, tables, orders, stock, customers, settings
  };
  return blob;
}
async function importBackup(obj){
  if(!obj || typeof obj!=='object') throw new Error('Bad file');
  const src = obj.products ? obj : (obj.data||obj);
  const putAll = async (store, arr)=>{ if(!Array.isArray(arr)) return; await idbClear(store); for(const r of arr) await idbPut(store, r); };
  await putAll('products', src.products);
  await putAll('tables', src.tables);
  await putAll('orders', src.orders);
  await putAll('stock', src.stock);
  await putAll('customers', src.customers);
  await putAll('settings', src.settings);
  if(src.kv && typeof src.kv==='object'){ for(const [k,v] of Object.entries(src.kv)) await kvSet(k,v); }
  return true;
}
// storage persist + estimate (iOS eviction guard)
async function ensurePersist(){
  try{ if(navigator.storage && navigator.storage.persist) await navigator.storage.persist(); }catch{}
}
async function storageEstimate(){
  try{ if(!navigator.storage || !navigator.storage.estimate) return null; const {usage,quota}=await navigator.storage.estimate(); return {usage, quota, pct: quota ? (usage/quota*100).toFixed(1):'0'}; }catch{ return null; }
}
