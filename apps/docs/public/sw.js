// Dummy service worker to prevent 404 errors on the docs website.
// This is required if a previous version of the site registered a service worker
// or if some library/browser extension is looking for it.

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});
