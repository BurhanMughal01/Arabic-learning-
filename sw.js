// Nūr — Service Worker
// Caches app shell + data for offline use.

const VERSION = 'nur-v4';
const CACHE_STATIC = 'nur-static-' + VERSION;
const CACHE_DATA   = 'nur-data-' + VERSION;
const CACHE_AUDIO  = 'nur-audio-' + VERSION;
const CACHE_FONTS  = 'nur-fonts-' + VERSION;

// Files needed for app shell (offline-first)
const STATIC = [
  './',
  './index.html',
  './manifest.json',
  './data/top100.json'
];

// ─── Install ───
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_STATIC).then(cache => {
      console.log('[SW] Caching app shell');
      return cache.addAll(STATIC).catch(err => {
        console.warn('[SW] Some files failed:', err);
      });
    }).then(() => self.skipWaiting())
  );
});

// ─── Activate — clean old caches ───
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(
      keys.filter(k => !k.includes(VERSION))
          .map(k => caches.delete(k))
    )).then(() => self.clients.claim())
  );
});

// ─── Fetch — smart routing ───
self.addEventListener('fetch', event => {
  const req = event.request;
  const url = new URL(req.url);

  // Only GET
  if(req.method !== 'GET') return;

  // 1. Audio (EveryAyah) — cache-first
  if(url.hostname === 'everyayah.com'){
    event.respondWith(
      caches.open(CACHE_AUDIO).then(cache =>
        cache.match(req).then(cached => {
          if(cached) return cached;
          return fetch(req).then(res => {
            if(res.ok) cache.put(req, res.clone());
            return res;
          }).catch(() => new Response('', {status: 503}));
        })
      )
    );
    return;
  }

  // 2. Google Fonts — cache-first (long-term)
  if(url.hostname.includes('fonts.googleapis.com') || 
     url.hostname.includes('fonts.gstatic.com')){
    event.respondWith(
      caches.open(CACHE_FONTS).then(cache =>
        cache.match(req).then(cached => {
          if(cached) return cached;
          return fetch(req).then(res => {
            if(res.ok) cache.put(req, res.clone());
            return res;
          });
        })
      )
    );
    return;
  }

  // 3. Data (top100.json) — network-first (fresh data priority)
  if(url.pathname.includes('top100.json')){
    event.respondWith(
      fetch(req).then(res => {
        if(res.ok){
          const copy = res.clone();
          caches.open(CACHE_DATA).then(c => c.put(req, copy));
        }
        return res;
      }).catch(() => caches.match(req))
    );
    return;
  }

  // 4. Same-origin HTML/JS/CSS — cache-first
  if(url.origin === self.location.origin){
    event.respondWith(
      caches.match(req).then(cached => cached || fetch(req).then(res => {
        if(res.ok && res.type === 'basic'){
          const copy = res.clone();
          caches.open(CACHE_STATIC).then(c => c.put(req, copy));
        }
        return res;
      }).catch(() => caches.match('./index.html')))
    );
    return;
  }
});

// ─── Allow client to trigger skipWaiting ───
self.addEventListener('message', event => {
  if(event.data && event.data.type === 'SKIP_WAITING'){
    self.skipWaiting();
  }
});
