/* Order Flow PWA — offline app shell + runtime cache
   v25 • additive only; never caches /api/* or /download
   /app/*.{html,js,css} + /order.html are network-first
   so the freshest shell always wins and old builds die. */
const CACHE_SHELL = 'of-shell-v33';
const SHELL = [
  '/app/',
  '/app/index.html',
  '/app/core.js',
  '/app/lang.js',
  '/app/db.js',
  '/app/print.js',
  '/app/app.js',
  '/app/ticket.js',
  '/app/more.js',
  '/app/styles.css',
  '/order.html',
  '/order.js',
  '/media/logo.png',
  '/media/bolt.png',
  '/styles.css',
  '/manifest.json'
];
const NETWORK_FIRST = (pathname) =>
  pathname === '/order.html' ||
  (pathname.startsWith('/app/') && /\.(html|js|css)$/.test(pathname));

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE_SHELL).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_SHELL).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  // never cache API, geo, download, cloud relay
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/download') || url.pathname.startsWith('/geo') || url.pathname.startsWith('/functions/')) return;
  // navigation + app shell code: NETWORK-FIRST, cache as fallback
  if (e.request.mode === 'navigate' || NETWORK_FIRST(url.pathname)) {
    e.respondWith((async () => {
      const c = await caches.open(CACHE_SHELL);
      try { const r = await fetch(e.request); if (r && r.ok) c.put(e.request, r.clone()); return r; }
      catch {
        if (e.request.mode === 'navigate') return (await c.match(e.request)) || (await c.match('/app/index.html')) || (await c.match('/app/')) || Response.error();
        return (await c.match(e.request)) || Response.error();
      }
    })());
    return;
  }
  // shell assets: cache-first
  if (SHELL.some(p => url.pathname === p || url.pathname.endsWith(p))) {
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(r => { caches.open(CACHE_SHELL).then(c => c.put(e.request, r.clone())); return r; })));
    return;
  }
  // images + css/js: stale-while-revalidate
  if (/\.(png|jpg|jpeg|webp|svg|css|js|woff2?)$/.test(url.pathname)) {
    e.respondWith((async () => {
      const c = await caches.open(CACHE_SHELL);
      const hit = await c.match(e.request);
      const fetchP = fetch(e.request).then(r => { c.put(e.request, r.clone()); return r; }).catch(() => hit);
      return hit || fetchP;
    })());
  }
});
