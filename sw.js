/* RateX — Service Worker v7 (offline app shell; Supabase API is never cached)
   Files are cached one-by-one so a single missing file can NEVER
   break installation/offline mode again. */
const CACHE = "ratex-v7";
const SHELL = [
  "./",
  "./index.html",
  "./manifest.json",
  "./supabase.js",
  "./icon-192.png",
  "./icon-512.png",
  "./maskable-512.png"
];

self.addEventListener("install", (e) => {
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.allSettled(SHELL.map(async (url) => {
      try {
        const res = await fetch(url, { cache: "reload" });
        if (res && res.ok) await cache.put(url, res);
      } catch (_) { /* keep going — one bad file must not fail install */ }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);

  // Never intercept Supabase (auth/data backup sync) or non-GET requests.
  if (e.request.method !== "GET" || url.hostname.endsWith("supabase.co")) return;

  // Page navigations: network-first, fall back to cached app shell (offline).
  if (e.request.mode === "navigate") {
    e.respondWith(
      fetch(e.request)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put("./index.html", copy));
          return res;
        })
        .catch(() => caches.match("./index.html"))
    );
    return;
  }

  // Static assets (app files + Supabase CDN fallback): cache-first,
  // refresh in the background. Works fully offline after first visit.
  const cacheable = url.origin === location.origin || url.hostname === "cdn.jsdelivr.net";
  if (!cacheable) return;
  e.respondWith(
    caches.match(e.request).then((hit) => {
      const network = fetch(e.request)
        .then((res) => {
          if (res && res.status === 200) {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(e.request, copy));
          }
          return res;
        })
        .catch(() => hit);
      return hit || network;
    })
  );
});
