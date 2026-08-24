/* 每日经济早报 · Service Worker：离线可用 */
const VERSION = 'eco-brief-v2';
const SHELL = [
  './',
  './index.html',
  './css/style.css',
  './js/app.js',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(VERSION)
      .then(function (cache) { return cache.addAll(SHELL); })
      .then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys()
      .then(function (keys) {
        return Promise.all(keys.filter(function (k) { return k !== VERSION; })
          .map(function (k) { return caches.delete(k); }));
      })
      .then(function () { return self.clients.claim(); })
  );
});

self.addEventListener('fetch', function (event) {
  var request = event.request;
  if (request.method !== 'GET') return;
  var url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // 数据文件：网络优先，失败时用缓存兜底（保证离线可读最新一期）
  if (url.pathname.indexOf('/data/') !== -1) {
    event.respondWith(
      fetch(request).then(function (res) {
        var copy = res.clone();
        caches.open(VERSION).then(function (cache) { cache.put(request, copy); });
        return res;
      }).catch(function () {
        return caches.match(request).then(function (hit) {
          return hit || Response.error();
        });
      })
    );
    return;
  }

  // 静态资源：缓存优先
  event.respondWith(
    caches.match(request).then(function (hit) {
      if (hit) return hit;
      return fetch(request).then(function (res) {
        var copy = res.clone();
        caches.open(VERSION).then(function (cache) { cache.put(request, copy); });
        return res;
      });
    })
  );
});