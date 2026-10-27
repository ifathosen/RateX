/**
 * Service worker — makes the installed app open instantly and survive a dropped
 * connection.
 *
 * What it caches: only the application shell (HTML, JS, CSS, icons) from this origin.
 * What it never caches: anything from the Supabase origin. Financial data always goes
 * to the network; a stale cached response could show a balance that is no longer true.
 * If the network fails, the app falls back to the cached shell and shows its own
 * offline notice — it never pretends a save succeeded.
 *
 * Bump SHELL_VERSION to invalidate every old cache on the next visit.
 */
const SHELL_VERSION = 'ledger-shell-v3'
const SHELL_PREFIX = 'ledger-shell-'

self.addEventListener('install', (event) => {
  const base = new URL(self.registration.scope)
  event.waitUntil(
    caches.open(SHELL_VERSION).then((cache) =>
      // The manifest is deliberately NOT precached: a cached copy keeps pointing at old
      // icon paths, and Chrome then reports "This app cannot be installed".
      cache.addAll([new URL('index.html', base).toString()]).catch(() => {
        /* a missing optional file must not block installation */
      }),
    ),
  )
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith(SHELL_PREFIX) && k !== SHELL_VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

const isSupabase = (url) => /\.supabase\.(co|in)$/.test(url.hostname) || url.pathname.startsWith('/rest/v1') || url.pathname.startsWith('/auth/v1')

self.addEventListener('fetch', (event) => {
  const request = event.request
  if (request.method !== 'GET') return

  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return
  if (isSupabase(url)) return // never cache or intercept financial data

  // Navigations: network first so a new deploy is picked up, cached shell as fallback.
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone()
          caches.open(SHELL_VERSION).then((cache) => cache.put(request, copy)).catch(() => {})
          return response
        })
        .catch(async () => {
          const cached = (await caches.match(request)) || (await caches.match(new URL('index.html', self.registration.scope).toString()))
          return cached || new Response('<h1>Offline</h1><p>Open the app once while online.</p>', { status: 503, headers: { 'Content-Type': 'text/html' } })
        }),
    )
    return
  }

  // The manifest must always come from the network: a stale manifest hides new icons and
  // silently disables installation. Falls back to the cached copy only when offline.
  if (url.pathname.endsWith('.webmanifest')) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone()
          caches.open(SHELL_VERSION).then((cache) => cache.put(request, copy)).catch(() => {})
          return response
        })
        .catch(async () => (await caches.match(request)) || Response.error()),
    )
    return
  }

  // Built assets are content-hashed, so cache-first is safe and instant.
  if (url.pathname.includes('/assets/') || /\.(png|svg|ico|woff2?|css|js)$/.test(url.pathname)) {
    event.respondWith(
      caches.match(request).then(
        (cached) =>
          cached ||
          fetch(request).then((response) => {
            if (response.ok) {
              const copy = response.clone()
              caches.open(SHELL_VERSION).then((cache) => cache.put(request, copy)).catch(() => {})
            }
            return response
          }),
      ),
    )
  }
})
