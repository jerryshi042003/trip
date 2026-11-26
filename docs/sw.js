const C = 'trip-v17';
const SHELL = ['./', 'index.html', 'tom/', 'trip.css', 'trip.js', 'where.js', 'vendor/leaflet/leaflet.js', 'vendor/leaflet/leaflet.css', 'manifest.webmanifest?v=2', 'manifest-tom.webmanifest', 'icon-180.png?v=2', 'icon-192.png?v=2', 'icon-512.png?v=2', 'trip.json', 'tom-notes.txt'];
self.addEventListener('install', e => { e.waitUntil(caches.open(C).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(k => Promise.all(k.filter(x => x.startsWith('trip-v') && x !== C).map(x => caches.delete(x)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (u.origin !== location.origin || e.request.method !== 'GET' || u.pathname.startsWith('/api/')) return;
  // Network first (so edits arrive when online), cache fallback (works with no service).
  e.respondWith(fetch(e.request).then(async r => {
    if (r.ok) {
      if (u.pathname.endsWith('/trip.json')) {
        const trip = await r.clone().json();
        if (![trip.travelers?.tom?.plan, trip.travelers?.jerry?.plan, trip.places, trip.people, trip.emergency].every(Array.isArray)) throw new Error('Invalid trip data');
      }
      try { await (await caches.open(C)).put(e.request, r.clone()); } catch { /* Serve online even if storage is full. */ }
    }
    return r;
  }).catch(async () => {
    const cache = await caches.open(C);
    const cached = await cache.match(e.request, { ignoreSearch: true });
    const page = u.pathname.endsWith('/tom/') ? 'tom/' : 'index.html';
    return cached || (e.request.mode === 'navigate' ? await cache.match(page) : null) || Response.error();
  }));
});
