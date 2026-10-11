// Nūr — Service Worker v2
const VERSION = 'nur-v5';
const CACHE_STATIC = 'nur-static-' + VERSION;
const CACHE_DATA   = 'nur-data-' + VERSION;
const CACHE_AUDIO  = 'nur-audio-' + VERSION;
const CACHE_FONTS  = 'nur-fonts-' + VERSION;

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
      return cache.addAll(STATIC).catch(err => {
        console.warn('[SW] Install cache fail:', err);
      });
    }).then(() => self.skipWaiting())
  );
});

// ─── Activate ───
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(
      keys.filter(k => !k.includes(VERSION)).map(k => caches.delete(k))
    )).then(() => self.clients.claim())
  );
});

// ─── Fetch ───
self.addEventListener('fetch', event => {
  const req = event.request;
  const url = new URL(req.url);

  if(req.method !== 'GET') return;

  // 1. Audio — cache-first (with ignoreSearch)
  if(url.hostname === 'everyayah.com'){
    event.respondWith(
      caches.open(CACHE_AUDIO).then(cache =>
        cache.match(req, {ignoreSearch: true}).then(cached => {
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

  // 2. Fonts — cache-first
  if(url.hostname.includes('fonts.googleapis.com') ||
     url.hostname.includes('fonts.gstatic.com')){
    event.respondWith(
      caches.open(CACHE_FONTS).then(cache =>
        cache.match(req, {ignoreSearch: true}).then(cached => {
          if(cached) return cached;
          return fetch(req).then(res => {
            if(res.ok) cache.put(req, res.clone());
            return res;
          }).catch(() => new Response('', {status: 200, headers: {'Content-Type':'text/css'}}));
        })
      )
    );
    return;
  }

  // 3. Data — network-first with ignoreSearch fallback
  if(url.pathname.includes('top100.json')){
    event.respondWith(
      fetch(req).then(res => {
        if(res.ok){
          const copy = res.clone();
          caches.open(CACHE_DATA).then(c => c.put(req, copy));
        }
        return res;
      }).catch(() =>
        caches.open(CACHE_DATA).then(cache =>
          cache.match(req, {ignoreSearch: true}).then(cached =>
            cached || caches.open(CACHE_STATIC).then(c2 =>
              c2.match('./data/top100.json', {ignoreSearch: true})
            )
          )
        )
      )
    );
    return;
  }

  // 4. Same-origin — cache-first
  if(url.origin === self.location.origin){
    event.respondWith(
      caches.match(req, {ignoreSearch: true}).then(cached => {
        if(cached) return cached;
        return fetch(req).then(res => {
          if(res.ok && res.type === 'basic'){
            const copy = res.clone();
            caches.open(CACHE_STATIC).then(c => c.put(req, copy));
          }
          return res;
        }).catch(() => caches.match('./index.html'));
      })
    );
    return;
  }
});

self.addEventListener('message', event => {
  if(event.data && event.data.type === 'SKIP_WAITING'){
    self.skipWaiting();
  }
});
