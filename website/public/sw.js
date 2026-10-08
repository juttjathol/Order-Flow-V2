/* Order Flow PWA — offline app shell + runtime cache
   v1 • additive only; never caches /api/* or /download
*/
const CACHE_SHELL = 'of-shell-v18';
const SHELL = [
  '/app/',
  '/app/index.html',
  '/app/app.js',
  '/app/db.js',
  '/app/print.js',
  '/app/styles.css',
  '/media/logo.png',
  '/media/bolt.png',
  '/styles.css',
  '/manifest.json'
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE_SHELL).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_SHELL).map(k => caches.delete(k)))).then(()=> self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  // never cache API, geo, download, cloud relay
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/download') || url.pathname.startsWith('/geo') || url.pathname.startsWith('/functions/')) return;
  // navigation: network-first, fallback to cache + offline page
  if (e.request.mode === 'navigate') {
    e.respondWith((async () => {
      try { const r = await fetch(e.request); const c = await caches.open(CACHE_SHELL); c.put(e.request, r.clone()); return r; } catch { const c = await caches.open(CACHE_SHELL); return (await c.match('/app/index.html')) || (await c.match('/app/')) || Response.error(); }
    })());
    return;
  }
  // shell assets: cache-first
  if (SHELL.some(p => url.pathname === p || url.pathname.endsWith(p))) {
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(r => { caches.open(CACHE_SHELL).then(c=>c.put(e.request,r.clone())); return r; })));
    return;
  }
  // images + css/js: stale-while-revalidate
  if (/\.(png|jpg|jpeg|webp|svg|css|js|woff2?)$/.test(url.pathname)) {
    e.respondWith((async ()=>{ const c=await caches.open(CACHE_SHELL); const hit=await c.match(e.request); const fetchP=fetch(e.request).then(r=>{c.put(e.request,r.clone()); return r;}).catch(()=>hit); return hit || fetchP;})());
  }
});
