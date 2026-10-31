// Testes do analista sem Deno nem rede: o Claude e o Supabase são simulados.
// Correr com: node --experimental-strip-types supabase/functions/analista/analista.test.mjs
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

let handler;
let env = {};
let reserva = null;
let rpcs = [];
let pedidosClaude = [];
let guiao = [];

class APIError extends Error {}
class AuthenticationError extends APIError {}
class PermissionDeniedError extends APIError {}
class BadRequestError extends APIError {}
class AnthropicSimulado {
  static AuthenticationError = AuthenticationError;
  static PermissionDeniedError = PermissionDeniedError;
  static BadRequestError = BadRequestError;
  constructor(opcoes) { this.opcoes = opcoes; }
  beta = { messages: { create: async (p) => {
    pedidosClaude.push(JSON.parse(JSON.stringify(p)));
    const passo = guiao.shift();
    if (passo instanceof Error) throw passo;
    return passo;
  } } };
}
globalThis.__Anthropic = AnthropicSimulado;
globalThis.Deno = { env: { get: (k) => env[k] }, serve: (h) => { handler = h; } };
globalThis.__criarCliente = () => ({
  rpc: async (nome, args) => {
    if (nome === 'segredo_envio_valido') return { data: false, error: null };
    rpcs.push({ nome, ...args });
    if (nome === 'reservar_pergunta') return { data: reserva, error: null };
    if (nome === 'registar_resposta_analista') return { data: args.p_resultado, error: null };
    if (nome === 'analista_vendas') return { data: { pedidos_entregues: [{ grupo: 'Alexandra', pedidos: 120 }] }, error: null };
    return { data: {}, error: null };
  },
});

const fonte = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  .replace("import Anthropic from 'npm:@anthropic-ai/sdk';", 'const Anthropic = (globalThis as any).__Anthropic;')
  .replace("import { createClient } from 'npm:@supabase/supabase-js@2';", 'const createClient = (globalThis as any).__criarCliente;');
const ficheiro = join(mkdtempSync(join(tmpdir(), 'analista-')), 'index.mts');
writeFileSync(ficheiro, fonte);
await import(pathToFileURL(ficheiro).href);

const Q = '22222222-2222-4222-8222-222222222222';
const pedido = ({ segredo = '', corpo = {} } = {}) =>
  handler(new Request('http://x', { method: 'POST', headers: segredo ? { 'x-envio-segredo': segredo } : {}, body: JSON.stringify(corpo) }));
const assert = (c, m) => { console.log(c ? 'ok  ' : 'FALHA', m); if (!c) process.exitCode = 1; };
const usar = (id, name, input) => ({ type: 'tool_use', id, name, input });
const resp = (stop, ...content) => ({ stop_reason: stop, content });
const pergunta = { id: Q, tipo: 'pergunta', pergunta: 'Que cozinha vendeu mais em Setembro?', inicio: null, fim: null, hoje: '2026-10-03' };
const final = { resposta: 'A Alexandra, com 120 pedidos.', numeros_chave: [{ rotulo: 'Alexandra', valor: '120' }], sugestoes: [], limitacoes: '' };

env = { ENVIO_SEGREDO: 's', SUPABASE_URL: 'x', SUPABASE_SERVICE_ROLE_KEY: 'y' };

// 1. sem segredo e sem pergunta indicada
let r = await pedido();
assert(r.status === 401, 'sem segredo nem pergunta_id -> 401');

// 2. a app indica a pergunta: reserva só essa
reserva = null; rpcs = [];
r = await pedido({ corpo: { pergunta_id: Q } });
assert(rpcs[0].nome === 'reservar_pergunta' && rpcs[0].p_id === Q && (await r.json()).pergunta === null,
       'pela app reserva só a pergunta indicada');
rpcs = [];
await pedido({ segredo: 's' });
assert(rpcs[0].p_id === null, 'pelo pg_cron reserva a mais antiga');

// 3. sem chave
reserva = pergunta; rpcs = [];
await pedido({ segredo: 's' });
assert(rpcs.some((x) => x.nome === 'registar_resposta_analista' && x.p_resultado === 'indisponivel'), 'sem chave -> indisponível');

// 4. resposta em vários passos
env.ANTHROPIC_API_KEY = 'chave';
rpcs = []; pedidosClaude = [];
guiao = [
  resp('tool_use', usar('a', 'vendas', { inicio: '2026-09-01', fim: '2026-09-30', agrupar: 'cozinha' }),
       usar('b', 'equipa', { inicio: '2026-09-30', fim: '2026-09-01' })),
  resp('tool_use', usar('c', 'responder', final)),
];
r = await pedido({ corpo: { pergunta_id: Q } });
const p0 = pedidosClaude[0];
assert(p0.model === 'claude-opus-5-5' && p0.thinking.type === 'adaptive' && p0.tools.length === 8, 'claude-opus-5-5, 7 ferramentas e responder');
assert(p0.messages[0].content.includes('Hoje é 2026-10-03') && p0.messages[0].content.includes('<pergunta>'), 'dá a data de hoje e a pergunta');
assert(rpcs.some((x) => x.nome === 'analista_vendas' && x.p_agrupar === 'cozinha' && x.p_inicio === '2026-09-01'), 'chama a ferramenta no servidor');
assert(!rpcs.some((x) => x.nome === 'analista_equipa'), 'período ao contrário não chega ao servidor');
const res = pedidosClaude[1].messages[2].content;
assert(res[0].content.includes('Alexandra') && res[1].content.includes('período inválido'), 'devolve os resultados e os erros ao Claude');
const reg = rpcs.find((x) => x.nome === 'registar_resposta_analista');
assert(reg.p_resultado === 'respondida' && reg.p_resposta.resposta.startsWith('A Alexandra') && reg.p_passos.length === 2, 'regista a resposta e os passos');

// 5. relatório mensal: pede as secções
reserva = { ...pergunta, tipo: 'relatorio_mensal', inicio: '2026-09-01', fim: '2026-09-30' };
rpcs = []; pedidosClaude = [];
guiao = [resp('tool_use', usar('z', 'responder', final))];
await pedido({ segredo: 's' });
assert(pedidosClaude[0].messages[0].content.includes('relatório mensal'), 'relatório mensal com as secções pedidas');

// 6. erros
reserva = pergunta;
rpcs = []; guiao = [new AuthenticationError('401')];
await pedido({ segredo: 's' });
assert(rpcs.some((x) => x.p_resultado === 'indisponivel'), 'chave inválida -> indisponível');
rpcs = []; guiao = Array.from({ length: 10 }, (_, i) => resp('tool_use', usar(`v${i}`, 'pratos', { inicio: '2026-09-01', fim: '2026-09-30' })));
pedidosClaude = [];
await pedido({ segredo: 's' });
assert(JSON.stringify(pedidosClaude[9].messages.at(-1)).includes('Não há mais tempo')
       && rpcs.some((x) => x.nome === 'registar_resposta_analista' && x.p_resultado === 'erro'),
       'sem resposta nas 10 voltas: pede-a na última e tenta outra vez mais tarde');
