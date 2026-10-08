/* Order Flow POS — IndexedDB (orderflow-web, v4).
   Contract: NEVER delete/wipe existing stores on upgrade — ADD only.
   Hardened: a blocked/stalled open (another tab holding an old
   connection, private mode, old SW) degrades to an in-memory store
   so boot NEVER hangs on a white page, and retries in the back. */
(function () {
  'use strict';
  const DB_NAME = 'orderflow-web';
  const DB_VERSION = 4;
  const STORES_V1 = ['products', 'tables', 'orders', 'stock', 'customers', 'settings', 'kv', 'printQueue'];
  const STORES_V3 = ['staff', 'drivers', 'suppliers', 'purchases', 'wastage', 'reservations', 'channelsThird', 'refunds', 'appointments'];
  const ALL = STORES_V1.concat(STORES_V3);
  let _db = null, _mem = null, _attempts = 0;

  const memStore = () => { _mem = _mem || new Map(ALL.map(s => [s, new Map()])); return _mem; };
  let degraded = false;

  function open() {
    if (_db) return Promise.resolve(_db);
    if (degraded) return Promise.resolve(null);
    _attempts++;
    return new Promise((res, rej) => {
      let done = false;
      try {
        const rq = indexedDB.open(DB_NAME, DB_VERSION);
        rq.onupgradeneeded = () => {
          const db = rq.result;
          for (const s of ALL) if (!db.objectStoreNames.contains(s)) db.createObjectStore(s, { keyPath: 'id' });
        };
        rq.onsuccess = () => {
          if (done) { try { rq.result.close(); } catch {} return; }
          done = true;
          _db = rq.result;
          _db.onversionchange = () => { try { _db.close(); } catch {} _db = null; };
          res(_db);
        };
        rq.onblocked = () => { console.warn('orderflow-web: another tab is holding the DB open — running in memory for now'); finishMem(res); done = true; };
        rq.onerror = () => { if (done) return; done = true; console.warn('orderflow-web: IndexedDB unavailable', rq.error); finishMem(res); };
        setTimeout(() => { if (!done) { done = true; console.warn('orderflow-web: DB open stalled — memory mode'); finishMem(res); } }, 3500);
      } catch (e) { done = true; finishMem(res); }
    });
  }
  function finishMem(res) {
    degraded = true; memStore();
    res(null);
    // retry persistence later; when it comes back, reload into durable mode on next app start
    setTimeout(() => { degraded = false; memStoreMaybeMigrate().catch(() => {}); degraded = true; }, 15000 + Math.min(30000, _attempts * 5000));
  }
  async function memStoreMaybeMigrate() {
    const db = await new Promise(res => {
      try {
        const rq = indexedDB.open(DB_NAME, DB_VERSION);
        rq.onupgradeneeded = () => { const d = rq.result; for (const s of ALL) if (!d.objectStoreNames.contains(s)) d.createObjectStore(s, { keyPath: 'id' }); };
        rq.onsuccess = () => res(rq.result);
        rq.onerror = () => res(null);
        setTimeout(() => res(null), 4000);
      } catch { res(null); }
    });
    if (!db) return;
    const mem = memStore();
    await Promise.all(ALL.map(s => new Promise(r => {
      const t = db.transaction(s, 'readwrite'); const os = t.objectStore(s);
      for (const v of (mem.get(s) || new Map()).values()) os.put(v);
      t.oncomplete = r; t.onerror = r;
      setTimeout(r, 3000);
    })));
    _db = db; degraded = false;
    _db.onversionchange = () => { try { _db.close(); } catch {} _db = null; };
  }

  const prom = (rq) => new Promise((res, rej) => { rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
  async function tx(store, mode, fn) {
    const db = await open();
    if (!db) { throw new Error('DB_MEM'); }
    return new Promise((res, rej) => {
      const t = db.transaction(store, mode);
      const out = fn(t.objectStore(store));
      t.oncomplete = () => res(out && out.result !== undefined ? out.result : out);
      t.onerror = () => rej(t.error);
      setTimeout(() => res(out && out.result !== undefined ? out.result : out), 4000);
    });
  }

  window.OFDB = {
    open,
    isMemory() { return degraded && !_db; },
    async idbGet(store, id, fallback) {
      const db = await open();
      if (!db) { const row = memStore().get(store).get(id); return row == null ? fallback : row; }
      try { return (await prom(db.transaction(store, 'readonly').objectStore(store).get(id))) ?? fallback; }
      catch { return fallback; }
    },
    async idbGetAll(store, fallback) {
      const db = await open();
      if (!db) return [...memStore().get(store).values()];
      try { return (await prom(db.transaction(store, 'readonly').objectStore(store).getAll())) ?? (fallback ?? []); }
      catch { return fallback ?? []; }
    },
    async idbPut(store, obj) {
      const db = await open();
      if (!db) { memStore().get(store).set(obj.id, obj); return obj.id; }
      try { return await tx(store, 'readwrite', os => prom(os.put(obj))); }
      catch { memStore().get(store).set(obj.id, obj); return obj.id; }
    },
    async idbDel(store, id) {
      const db = await open();
      if (!db) { memStore().get(store).delete(id); return; }
      try { return await tx(store, 'readwrite', os => prom(os.delete(id))); } catch { }
    },
    async idbClear(store) {
      const db = await open();
      if (!db) { memStore().get(store).clear(); return; }
      try { return await tx(store, 'readwrite', os => prom(os.clear())); } catch { }
    },
    async kvGet(k, fallback) {
      const row = await this.idbGet('kv', k, null);
      return row == null ? fallback : ('value' in row ? row.value : row);
    },
    async kvSet(k, v) { return this.idbPut('kv', { id: k, value: v }); },
  };

  ['idbGet', 'idbGetAll', 'idbPut', 'idbDel', 'idbClear', 'kvGet', 'kvSet'].forEach(n => { window[n] = (...a) => window.OFDB[n](...a); });
})();
