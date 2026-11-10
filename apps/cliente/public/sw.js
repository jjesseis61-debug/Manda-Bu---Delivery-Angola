// Service worker da PWA do cliente (Manda Bué).
// Guarda SÓ o "esqueleto" da app (HTML, JS e imagens do próprio site) para abrir rápido e
// funcionar sem rede ao arrancar. NUNCA guarda pedidos à API (Supabase), preços, menus ou
// dados do cliente: tudo o que é de outro domínio passa direto à rede.
// __VERSAO__ é substituída em cada build (scripts/pwa.mjs) para o browser ver a versão nova.
const VERSAO = '__VERSAO__';
const CACHE = `mb-cliente-${VERSAO}`;

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(['/index.html'])).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((nomes) => Promise.all(nomes.filter((n) => n.startsWith('mb-cliente-') && n !== CACHE).map((n) => caches.delete(n))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // Supabase e afins: sempre à rede

  // Páginas: rede primeiro (apanha logo a versão nova); sem rede, a última guardada
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then((r) => { const copia = r.clone(); caches.open(CACHE).then((c) => c.put('/index.html', copia)); return r; })
        .catch(() => caches.match('/index.html')),
    );
    return;
  }

  // JS/imagens com nome por hash: nunca mudam → cache primeiro
  if (url.pathname.startsWith('/_expo/static/') || url.pathname.startsWith('/assets/') || url.pathname.startsWith('/icons/')) {
    e.respondWith(
      caches.match(req).then((em) => em || fetch(req).then((r) => {
        if (r.ok) { const copia = r.clone(); caches.open(CACHE).then((c) => c.put(req, copia)); }
        return r;
      })),
    );
  }
});
