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

// ---------------------------------------------------------------- Notificações (Web Push)
// O servidor manda { title, body, data, tag }. O tag evita mostrar o mesmo aviso duas vezes.
self.addEventListener('push', (e) => {
  let aviso = {};
  try {
    aviso = e.data ? e.data.json() : {};
  } catch (_) {
    aviso = { body: e.data ? e.data.text() : '' };
  }
  e.waitUntil(
    self.registration.showNotification(aviso.title || 'Manda Bué', {
      body: aviso.body || '',
      icon: '/icons/icon-192.png',
      badge: '/icons/icon-192.png',
      tag: aviso.tag,
      data: aviso.data || {},
    }),
  );
});

// Ecrã a abrir ao tocar (igual a rotaDaNotificacao em src/lib/push.ts)
function rotaDoAviso(d) {
  const c = d && d.codigo;
  if (c === 'N31' && typeof d.link === 'string' && d.link.startsWith('/')) return d.link;
  if (['N2', 'N3', 'N4', 'N5', 'N6', 'N43', 'N44'].includes(c)) return '/convida';
  if (c === 'N7') return '/destaques';
  if (c === 'N8') return '/levantar';
  if (c === 'N13' || c === 'N14') return '/pacotes';
  if (c === 'N9' && d.pedido_id) return `/avaliar/${d.pedido_id}`;
  if (['N16', 'N20', 'N22'].includes(c) && d.pedido_id) return `/pedido/${d.pedido_id}`;
  if (c === 'N30') return '/ajuda';
  if ((c === 'N10' || c === 'N11') && d.codigo_grupo) return `/grupo/${d.codigo_grupo}`;
  return '/avisos';
}

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = new URL(rotaDoAviso(e.notification.data || {}), self.location.origin).href;
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((janelas) => {
      for (const j of janelas) {
        if (j.url.startsWith(self.location.origin) && 'focus' in j) {
          j.navigate(url);
          return j.focus();
        }
      }
      return self.clients.openWindow(url);
    }),
  );
});
