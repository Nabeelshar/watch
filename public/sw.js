// Cache only the app shell, never media, signed URLs, chat or socket traffic.
const CACHE = 'afterglow-shell-v2';
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(['/', '/favicon.svg', '/manifest.webmanifest', '/icons/icon-192.png'])));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('afterglow-shell-') && key !== CACHE).map(key => caches.delete(key)))));
});
self.addEventListener('fetch', event => {
  const request = event.request, url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin || request.headers.has('range')) return;
  const navigation = request.mode === 'navigate';
  const asset = url.pathname.startsWith('/assets/') && /\.(?:js|css)$/.test(url.pathname);
  if (!navigation && !asset) return;
  event.respondWith(fetch(request).then(response => {
    if (response.ok) {
      const copy = response.clone();
      event.waitUntil(caches.open(CACHE).then(cache => cache.put(navigation ? '/' : request, copy)));
    }
    return response;
  }).catch(async () => (await caches.match(navigation ? '/' : request)) || new Response('Connect to the internet to open Afterglow.', {status: 503, headers: {'Content-Type': 'text/plain'}})));
});
