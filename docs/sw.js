const C = 'trip-v5';
const SHELL = ['./', 'index.html', 'manifest.webmanifest?v=2', 'icon-180.png?v=2', 'icon-192.png?v=2', 'icon-512.png?v=2', 'trip.json'];
self.addEventListener('install', e => { e.waitUntil(caches.open(C).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(k => Promise.all(k.filter(x => x !== C).map(x => caches.delete(x)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (u.origin !== location.origin || e.request.method !== 'GET') return;
  // Network first (so edits arrive when online), cache fallback (works with no service).
  e.respondWith(fetch(e.request).then(r => {
    if (r.ok) {
      const copy = r.clone();
      caches.open(C).then(c => c.put(e.request, copy));
    }
    return r;
  }).catch(async () => {
    const cached = await caches.match(e.request, { ignoreSearch: true });
    return cached || (e.request.mode === 'navigate' ? await caches.match('index.html') : Response.error());
  }));
});
