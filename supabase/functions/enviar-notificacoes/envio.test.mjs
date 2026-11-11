// Testes da Edge Function enviar-notificacoes sem Deno nem rede: a Expo e o Supabase são simulados.
// Correr com: node --experimental-strip-types supabase/functions/enviar-notificacoes/envio.test.mjs
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

let handler;
let pendentes = [], marcadas = [], falharLote = null, lotesRecebidos = 0;
// Fase 2 (receipts): recibosAntigos = tickets prontos a verificar; receiptsResposta = resposta do getReceipts
let recibosRegistados = [], recibosAntigos = [], recibosConcluidos = [], receiptsResposta = {}, getReceiptsChamado = 0;
globalThis.Deno = { env: { get: (k) => ({ ENVIO_SEGREDO: 's', SUPABASE_URL: 'x', SUPABASE_SERVICE_ROLE_KEY: 'y', VAPID_PUBLICA: 'pub', VAPID_PRIVADA: 'priv' })[k] }, serve: (h) => { handler = h; } };
// Web Push simulado: assinaturas com "morta" no endpoint respondem 410 (o navegador desistiu)
let webEnviados = [];
globalThis.__webPush = {
  setVapidDetails: () => {},
  sendNotification: async (sub, payload) => {
    if (sub.endpoint.includes('morta')) throw Object.assign(new Error('gone'), { statusCode: 410 });
    webEnviados.push({ endpoint: sub.endpoint, payload: JSON.parse(payload) });
  },
};
globalThis.__criarCliente = () => ({
  rpc: async (nome, args) => {
    if (nome === 'notificacoes_por_enviar') return { data: pendentes.filter((p) => !marcadas.includes(p.id)), error: null };
    if (nome === 'marcar_notificacoes_enviadas') { marcadas.push(...args.p_ids); return { data: args.p_ids.length, error: null }; }
    if (nome === 'desactivar_tokens_push') return { data: args.p_tokens.length, error: null };
    if (nome === 'segredo_envio_valido') return { data: args.p_segredo === 'segredo-da-bd', error: null };
    if (nome === 'registar_recibos_push') { recibosRegistados.push(...args.p_recibos); return { data: args.p_recibos.length, error: null }; }
    if (nome === 'recibos_por_verificar') return { data: recibosAntigos, error: null };
    if (nome === 'concluir_recibos') { recibosConcluidos.push(...args.p_ids); return { data: args.p_tokens_invalidos.length, error: null }; }
  },
});
globalThis.fetch = async (url, opt) => {
  if (String(url).includes('getReceipts')) {
    getReceiptsChamado++;
    const { ids } = JSON.parse(opt.body);
    const data = {};
    for (const id of ids) if (receiptsResposta[id]) data[id] = receiptsResposta[id];
    return { ok: true, json: async () => ({ data }) };
  }
  lotesRecebidos++;
  const lote = JSON.parse(opt.body);
  if (lotesRecebidos === falharLote) return { ok: false, status: 503 };
  // Tokens "morto" falham logo (ticket error); os restantes recebem um ticket ok com id
  return { ok: true, json: async () => ({ data: lote.map((m) => (m.to.includes('morto') ? { status: 'error', details: { error: 'DeviceNotRegistered' } } : { status: 'ok', id: `tk-${m.to}` })) }) };
};
// A função importa o cliente do Supabase por npm:; aqui troca-se pelo simulado
const fonte = readFileSync(new URL('./index.ts', import.meta.url), 'utf8').replace(
  "import { createClient } from 'npm:@supabase/supabase-js@2';",
  'const createClient = (globalThis as any).__criarCliente;',
).replace("import webpush from 'npm:web-push@3.6.7';", 'const webpush = (globalThis as any).__webPush;');
const ficheiro = join(mkdtempSync(join(tmpdir(), 'enviar-notificacoes-')), 'index.mts');
writeFileSync(ficheiro, fonte);
await import(pathToFileURL(ficheiro).href);
const pedido = () => handler(new Request('http://x', { method: 'POST', headers: { 'x-envio-segredo': 's' } }));
const n = (i, destino, tokens, apps) => ({ id: `n${i}`, destino, codigo: 'N3', titulo: 't', corpo: 'c', dados: {}, tokens, apps });
const assert = (c, m) => { console.log(c ? 'ok  ' : 'FALHA', m); if (!c) process.exitCode = 1; };

// 120 notificações de cliente com 1 telemóvel cada → 2 lotes; o 2.º falha
pendentes = Array.from({ length: 120 }, (_, i) => n(i, 'cliente', [`tok${i}`]));
falharLote = 2;
let r = await pedido();
assert(r.status === 502, 'Expo falha no 2.º lote: resposta 502');
assert(marcadas.length === 100, `só as 100 do 1.º lote ficam marcadas (${marcadas.length})`);
lotesRecebidos = 0; falharLote = null;
r = await pedido();
assert(r.status === 200 && marcadas.length === 120, 'no minuto seguinte seguem só as 20 que faltavam');
assert(new Set(marcadas).size === 120, 'nenhuma notificação enviada duas vezes');

// sem telemóvel, funcionário à parte, token inválido
pendentes = [n(200, 'cliente', []), n(201, 'funcionario', ['tok-f']), n(202, 'cliente', ['morto-1'])];
marcadas = []; lotesRecebidos = 0;
r = await pedido(); const corpo = await r.json();
assert(lotesRecebidos === 2, 'cliente e funcionário em pedidos à Expo separados');
assert(marcadas.length === 3, 'as 3 saem da fila, incluindo a sem telemóvel');
assert(corpo.tokens_desactivados === 1, 'token não registado é desactivado');

// notificação com muitos telemóveis não se parte entre lotes
pendentes = [n(300, 'cliente', Array.from({ length: 60 }, (_, i) => `a${i}`)), n(301, 'cliente', Array.from({ length: 60 }, (_, i) => `b${i}`))];
marcadas = []; lotesRecebidos = 0;
await pedido();
assert(lotesRecebidos === 2, 'duas notificações de 60 telemóveis vão em 2 lotes, sem se partirem');

// A equipa tem dois projectos Expo (operador e estafeta): nunca vão no mesmo pedido à Expo
pendentes = [n(500, 'funcionario', ['op-1'], ['operador']), n(501, 'funcionario', ['est-1'], ['estafeta'])];
marcadas = []; lotesRecebidos = 0;
r = await pedido();
assert(lotesRecebidos === 2, 'operador e estafeta (projectos Expo diferentes) seguem em pedidos separados');
assert(marcadas.length === 2, 'as duas notificações de equipa saem da fila');

// Uma notificação para os dois projectos (ex. N19) parte-se e só é marcada quando ambos enviam
pendentes = [n(600, 'funcionario', ['op-x', 'est-x'], ['operador', 'estafeta'])];
marcadas = []; lotesRecebidos = 0;
await pedido();
assert(lotesRecebidos === 2, 'uma notificação com tokens de dois projectos vai em 2 pedidos');
assert(marcadas.length === 1 && marcadas[0] === 'n600', 'a notificação mista só é marcada depois de ambos os projectos enviarem');

// Se um dos projectos falha, a notificação mista NÃO é marcada (tenta tudo no minuto seguinte)
pendentes = [n(700, 'funcionario', ['op-y', 'est-y'], ['operador', 'estafeta'])];
marcadas = []; lotesRecebidos = 0; falharLote = 2;
r = await pedido();
assert(r.status === 502, 'falha num dos projectos devolve 502');
assert(!marcadas.includes('n700'), 'notificação mista não é marcada se um dos projectos falhou');
lotesRecebidos = 0; falharLote = null;

// Fase 2 (receipts): os tickets ok ficam guardados para verificar o receipt mais tarde
pendentes = [n(400, 'cliente', ['viva-1', 'viva-2'])];
marcadas = []; lotesRecebidos = 0; recibosRegistados = []; recibosAntigos = [];
await pedido();
assert(recibosRegistados.length === 2, 'tickets ok são guardados como recibos para verificar depois');
assert(recibosRegistados.every((x) => x.ticket_id && x.token), 'cada recibo tem ticket_id e token');

// Fase 2 (receipts): um receipt DeviceNotRegistered desactiva o token e o recibo é concluído,
// mesmo sem envios novos nesse minuto
pendentes = []; marcadas = []; lotesRecebidos = 0; getReceiptsChamado = 0; recibosConcluidos = [];
recibosAntigos = [
  { id: 'rc1', ticket_id: 'T1', token: 'tok-vivo' },
  { id: 'rc2', ticket_id: 'T2', token: 'tok-fantasma' },
];
receiptsResposta = { T1: { status: 'ok' }, T2: { status: 'error', details: { error: 'DeviceNotRegistered' } } };
r = await pedido();
const cr = await r.json();
assert(r.status === 200, 'receipts: resposta 200 mesmo sem envios novos');
assert(getReceiptsChamado === 1, 'receipts: consultou o getReceipts');
assert(cr.tokens_desactivados === 1, 'receipts: o token fantasma (DeviceNotRegistered) é desactivado');
assert(recibosConcluidos.length === 2 && recibosConcluidos.includes('rc1') && recibosConcluidos.includes('rc2'),
  'receipts: os recibos verificados são concluídos/apagados');

// PWA: assinaturas web saem por Web Push (não pela Expo); 410 desactiva; só-web sai da fila
const web = (ep) => JSON.stringify({ endpoint: `https://push.exemplo/${ep}`, keys: { p256dh: 'p', auth: 'a' } });
pendentes = [
  n(800, 'cliente', [web('a')], ['web']),
  n(801, 'cliente', ['tok-app', web('b')], ['cliente', 'web']),
  n(802, 'cliente', [web('morta')], ['web']),
];
marcadas = []; lotesRecebidos = 0; webEnviados = []; recibosAntigos = [];
r = await pedido();
const cw = await r.json();
assert(webEnviados.length === 2, 'web: duas assinaturas vivas recebem o aviso por Web Push');
assert(lotesRecebidos === 1, 'web: só a parte da app vai à Expo');
assert(webEnviados[0].payload.tag && webEnviados[0].payload.title === 't', 'web: o aviso leva título e tag (sem duplicados)');
assert(marcadas.includes('n800') && marcadas.includes('n801') && marcadas.includes('n802'), 'web: as três saem da fila');
assert(cw.tokens_desactivados >= 1, 'web: assinatura que respondeu 410 é desactivada');

// Autorização: o segredo da função ou o guardado na base de dados (o que o cron manda)
const comSegredo = (v) => handler(new Request('http://x', { method: 'POST', headers: v === null ? {} : { 'x-envio-segredo': v } }));
pendentes = [];
assert((await comSegredo('errado')).status === 401, 'segredo errado: 401');
assert((await comSegredo(null)).status === 401, 'sem segredo: 401');
assert((await comSegredo('segredo-da-bd')).status === 200, 'segredo guardado na base de dados: aceite');
