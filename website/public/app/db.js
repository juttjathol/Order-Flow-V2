/* Order Flow POS — IndexedDB (orderflow-web, v3).
   Contract: NEVER delete/wipe existing stores on upgrade — ADD only. */
(function () {
  'use strict';
  const DB_NAME = 'orderflow-web';
  const DB_VERSION = 3;
  const STORES_V1 = ['products', 'tables', 'orders', 'stock', 'customers', 'settings', 'kv', 'printQueue'];
  const STORES_V3 = ['staff', 'drivers', 'suppliers', 'purchases', 'wastage', 'reservations', 'channelsThird', 'refunds', 'appointments'];
  let _db = null;

  function open() {
    if (_db) return Promise.resolve(_db);
    return new Promise((res, rej) => {
      const rq = indexedDB.open(DB_NAME, DB_VERSION);
      rq.onupgradeneeded = (e) => {
        const db = rq.result;
        for (const s of STORES_V1.concat(STORES_V3)) {
          if (!db.objectStoreNames.contains(s)) db.createObjectStore(s, { keyPath: 'id' });
        }
      };
      rq.onsuccess = () => { _db = rq.result; res(_db); };
      rq.onerror = () => rej(rq.error);
    });
  }
  async function tx(store, mode, fn) {
    const db = await open();
    return new Promise((res, rej) => {
      const t = db.transaction(store, mode);
      const os = t.objectStore(store);
      const out = fn(os);
      t.oncomplete = () => res(out && out.result !== undefined ? out.result : out);
      t.onerror = () => rej(t.error);
    });
  }
  const prom = (rq) => new Promise((res, rej) => { rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });

  window.OFDB = {
    open,
    async idbGet(store, id, fallback) {
      const db = await open();
      try { return (await prom(db.transaction(store, 'readonly').objectStore(store).get(id))) ?? fallback; }
      catch { return fallback; }
    },
    async idbGetAll(store, fallback) {
      const db = await open();
      try { return (await prom(db.transaction(store, 'readonly').objectStore(store).getAll())) ?? (fallback ?? []); }
      catch { return fallback ?? []; }
    },
    async idbPut(store, obj) { return tx(store, 'readwrite', os => prom(os.put(obj))); },
    async idbDel(store, id) { return tx(store, 'readwrite', os => prom(os.delete(id))); },
    async idbClear(store) { return tx(store, 'readwrite', os => prom(os.clear())); },
    async kvGet(k, fallback) {
      const row = await this.idbGet('kv', k, null);
      return row == null ? fallback : ('value' in row ? row.value : row);
    },
    async kvSet(k, v) { return this.idbPut('kv', { id: k, value: v }); },
  };

  // back-compat globals used across the app
  ['idbGet', 'idbGetAll', 'idbPut', 'idbDel', 'idbClear', 'kvGet', 'kvSet'].forEach(n => { window[n] = (...a) => window.OFDB[n](...a); });
})();
