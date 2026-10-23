// Offline cache for SAM (our own service worker, used with --pwa-strategy=none).
//
// VERSION and PRECACHE are filled in automatically on every deploy by
// stamp.ps1 (called from deploy.bat). Do not edit the two lines below
// by hand, deploy.bat looks for them exactly as written.
const VERSION = 'sam-dev';
const PRECACHE = [];

const ORIGIN = self.location.origin;

// Firebase's web SDK and the fallback fonts are downloaded from Google's CDN
// every time the app starts. Keep a copy, or the app can not start offline
// when the phone has dropped its own browser cache (iPhone does this).
// (This name must not start with "sam-" so deploys do not delete it.)
const CDN_CACHE = 'cdn-firebase';
const CDN_PREFIXES = [
  'https://www.gstatic.com/firebasejs/',
  'https://fonts.gstatic.com/',
];
function isCdn(href) {
  return CDN_PREFIXES.some((p) => href.startsWith(p));
}

// Small files that must always be there.
const SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'sqflite_sw.js',
  'sqlite3.wasm',
];

function isHtml(res) {
  return (res.headers.get('content-type') || '').includes('text/html');
}

// Firebase can answer a missing file with index.html (SPA rewrite).
// Never store that under a js / wasm / png name.
function isPageUrl(href) {
  const p = new URL(href).pathname;
  return p.endsWith('/') || p.endsWith('.html');
}

// A redirected response can not be used for a page load, so make a clean copy.
async function clean(res) {
  if (!res.redirected) return res;
  return new Response(await res.blob(), {
    status: res.status,
    statusText: res.statusText,
    headers: res.headers,
  });
}

// Download one file fresh and keep it.
// - Network error: throws (so a half-finished update never replaces a good one).
// - File not found: skipped.
// - Other bad status: throws for shell files, skipped for the rest.
async function store(cache, href, strict) {
  const res = await fetch(new Request(href, { cache: 'no-cache' }));
  if (!res.ok) {
    if (strict && res.status !== 404) throw new Error('bad status ' + res.status + ' ' + href);
    return;
  }
  if (isHtml(res) && !isPageUrl(href) && !isPageUrl(res.url || href)) return;
  await cache.put(href, await clean(res));
}

// fetch() that gives up after a few seconds. On a slow (but not dead) connection
// a plain fetch() can hang for minutes, and the app would sit on the loading
// screen. With a limit it fails like "offline" does, and the app falls back.
function fetchLimited(req, ms) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), ms);
  return fetch(req, { signal: ctrl.signal }).finally(() => clearTimeout(timer));
}

// Run jobs a few at a time (iPhone can fail when 100+ downloads start at once,
// and a slow connection needs the app's own requests to go first).
async function runPool(jobs, size) {
  const queue = jobs.slice();
  await Promise.all(
    Array.from({ length: size }, async () => {
      while (queue.length) await queue.shift()();
    })
  );
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(VERSION);
      const shell = new Set(SHELL.map((u) => new URL(u, self.location.href).href));
      const others = new Set();

      // Every file of this build (list written by stamp.ps1 at deploy time).
      PRECACHE.forEach((p) => {
        others.add(new URL(encodeURI(p), self.location.href).href);
      });

      // Plus every file the old version had cached.
      for (const key of await caches.keys()) {
        if (key === VERSION || !key.startsWith('sam-')) continue;
        const old = await caches.open(key);
        for (const req of await old.keys()) {
          const u = new URL(req.url);
          if (u.origin === ORIGIN) others.add(u.href);
        }
      }

      const jobs = [];
      shell.forEach((href) => jobs.push(() => store(cache, href, true)));
      others.forEach((href) => {
        if (!shell.has(href)) jobs.push(() => store(cache, href, false));
      });
      await runPool(jobs, 3);

      // Only reached when everything above worked.
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // Remove all old caches (ours and any left by the old Flutter worker).
      for (const key of await caches.keys()) {
        if (key !== VERSION && key !== CDN_CACHE) await caches.delete(key);
      }
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  if (req.headers.has('range')) return;

  if (isCdn(req.url)) {
    event.respondWith(serveCdn(req));
    return;
  }

  const url = new URL(req.url);
  // Only our own files. Firebase / Google calls go straight to the network.
  if (url.origin !== ORIGIN) return;
  if (url.pathname.startsWith('/__/')) return;

  event.respondWith(serve(event, req));
});

// Cache first. A cached file is returned at once and the network is NOT touched.
// New versions arrive through the worker update (stamp.ps1 gives every deploy a
// new VERSION, so the whole file set is replaced together). Re-downloading single
// files in the background could mix old and new files and slows a weak connection.
async function serve(event, req) {
  const cache = await caches.open(VERSION);
  const cached = await cache.match(req, { ignoreSearch: true });
  if (cached) return cached;

  // Not cached: try the network, but only for a few seconds.
  try {
    const res = await fetchLimited(req, 8000);
    if (res && res.status === 200) {
      const wrongHtml = req.mode !== 'navigate' && isHtml(res);
      if (!wrongHtml) event.waitUntil(cache.put(req, res.clone()));
    }
    return res;
  } catch (e) {
    // Offline or too slow: open the app shell for page loads.
    if (req.mode === 'navigate') {
      const shell = (await cache.match('index.html')) || (await cache.match('./'));
      if (shell) return shell;
    }
    return Response.error();
  }
}

// Versioned CDN files never change: cache first, network only when missing.
async function serveCdn(req) {
  const cache = await caches.open(CDN_CACHE);
  const cached = await cache.match(req, { ignoreVary: true });
  if (cached) return cached;
  const res = await fetchLimited(req, 10000);
  if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone());
  return res;
}

async function storeCdn(href) {
  const cache = await caches.open(CDN_CACHE);
  if (await cache.match(href, { ignoreVary: true })) return;
  const res = await fetch(new Request(href, { mode: 'cors' }));
  if (res.ok) await cache.put(href, res);
}

// Every image / font that is declared in the app (assets/AssetManifest.bin.json
// and assets/FontManifest.json), so screens that were never opened online
// still have their pictures offline.
async function cacheDeclaredAssets() {
  const found = new Set();
  const readJson = async (path) => {
    try {
      const res = await fetch(path, { cache: 'no-cache' });
      if (!res.ok || isHtml(res)) return null;
      return await res.json();
    } catch (e) {
      return null;
    }
  };

  const assets = await readJson('assets/AssetManifest.bin.json');
  if (assets && typeof assets === 'object') {
    Object.keys(assets).forEach((key) => {
      found.add(key);
      const variants = Array.isArray(assets[key]) ? assets[key] : [];
      variants.forEach((v) => {
        if (typeof v === 'string') found.add(v);
        else if (v && typeof v.asset === 'string') found.add(v.asset);
      });
    });
  }
  const fonts = await readJson('assets/FontManifest.json');
  if (Array.isArray(fonts)) {
    fonts.forEach((f) =>
      (f.fonts || []).forEach((x) => {
        if (x && typeof x.asset === 'string') found.add(x.asset);
      })
    );
  }

  const cache = await caches.open(VERSION);
  const wanted = ['assets/AssetManifest.bin', 'assets/AssetManifest.bin.json', 'assets/FontManifest.json'];
  found.forEach((key) => wanted.push('assets/' + key));
  for (const path of wanted) {
    try {
      const href = new URL(encodeURI(path), self.location.href).href;
      if (await cache.match(href)) continue;
      await store(cache, href, false);
    } catch (e) {
      // ignore, we will try again next time
    }
  }
}

// The page tells the worker what it really loaded, so files that were fetched
// before this worker took control are also stored for offline use.
self.addEventListener('message', (event) => {
  const data = event.data || {};

  if (data.type === 'CACHE_ASSETS') {
    event.waitUntil(cacheDeclaredAssets());
    return;
  }

  if (data.type !== 'CACHE_URLS' || !Array.isArray(data.urls)) return;

  event.waitUntil(
    (async () => {
      const cache = await caches.open(VERSION);
      for (const raw of data.urls) {
        try {
          const u = new URL(raw, self.location.href);
          if (isCdn(u.href)) {
            await storeCdn(u.href);
            continue;
          }
          if (u.origin !== ORIGIN || u.pathname.startsWith('/__/')) continue;
          if (await cache.match(u.href, { ignoreSearch: true })) continue;
          await store(cache, u.href, false);
        } catch (e) {
          // ignore, we will try again next time
        }
      }
    })()
  );
});
