// Testes do agente de stock e compras sem Deno nem rede: o Claude e o Supabase são simulados.
// Correr com: node --experimental-strip-types supabase/functions/compras/compras.test.mjs
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
    if (nome === 'reservar_plano_compras') return { data: reserva, error: null };
    if (nome === 'registar_plano_compras') return { data: args.p_resultado, error: null };
    if (nome === 'stk_precos') return { data: { compras: [{ fornecedor: 'Mercado A', preco_por_unidade_compra: 1000 }] }, error: null };
    return { data: {}, error: null };
  },
});

const fonte = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  .replace("import Anthropic from 'npm:@anthropic-ai/sdk';", 'const Anthropic = (globalThis as any).__Anthropic;')
  .replace("import { createClient } from 'npm:@supabase/supabase-js@2';", 'const createClient = (globalThis as any).__criarCliente;');
const ficheiro = join(mkdtempSync(join(tmpdir(), 'compras-')), 'index.mts');
writeFileSync(ficheiro, fonte);
await import(pathToFileURL(ficheiro).href);

const PL = '33333333-3333-4333-8333-333333333333';
const ARROZ = '55555555-5555-4555-8555-555555555555';
const pedido = ({ segredo = '', corpo = {} } = {}) =>
  handler(new Request('http://x', { method: 'POST', headers: segredo ? { 'x-envio-segredo': segredo } : {}, body: JSON.stringify(corpo) }));
const assert = (c, m) => { console.log(c ? 'ok  ' : 'FALHA', m); if (!c) process.exitCode = 1; };
const usar = (id, name, input) => ({ type: 'tool_use', id, name, input });
const resp = (stop, ...content) => ({ stop_reason: stop, content });
const plano = { id: PL, cozinha_id: 'c1', cozinha: 'Viana', hoje: '2026-10-03', saldos: [{ produto_id: ARROZ, nome: 'Arroz', dias_de_cobertura: 1.5 }] };
const final = { resumo: 'O arroz acaba amanhã.', compras: [{ produto_id: ARROZ, quantidade: 10, urgencia: 'hoje', motivo: 'Cobertura de 1,5 dias.' }], alertas: [] };

env = { ENVIO_SEGREDO: 's', SUPABASE_URL: 'x', SUPABASE_SERVICE_ROLE_KEY: 'y' };
let r = await pedido({ segredo: 'errado' });
assert(r.status === 401, 'sem o segredo e sem plano_id -> 401');

reserva = plano; rpcs = []; pedidosClaude = [];
r = await pedido({ segredo: 's' });
assert((await r.json()).resultado === 'indisponivel' && rpcs.some((x) => x.nome === 'registar_plano_compras' && x.p_resultado === 'indisponivel')
       && pedidosClaude.length === 0, 'sem chave: plano indisponível sem chamar o Claude');

env.ANTHROPIC_API_KEY = 'chave';
reserva = null; rpcs = [];
r = await pedido({ corpo: { plano_id: PL } });
assert((await r.json()).plano === null && rpcs[0].nome === 'reservar_plano_compras' && rpcs[0].p_id === PL,
       'pela app reserva só o plano indicado');

reserva = plano; rpcs = []; pedidosClaude = [];
guiao = [
  resp('tool_use', usar('a', 'precos', { produto_id: ARROZ }), usar('b', 'consumo_diario', { produto_id: 'x' }),
       usar('c', 'reconciliacao', { dias: 7 }), usar('d', 'apagar_stock', {})),
  resp('tool_use', usar('e', 'entregar_plano', final)),
];
r = await pedido({ segredo: 's' });
const corpo = await r.json();
assert(pedidosClaude[0].model === 'claude-opus-5-5' && pedidosClaude[0].thinking.type === 'adaptive'
       && pedidosClaude[0].messages[0].content.includes(ARROZ), 'modelo, pensamento adaptativo e os saldos na primeira mensagem');
const res = pedidosClaude[1].messages[2].content;
assert(res[0].content.includes('Mercado A') && res[1].content.includes('produto_id inválido') && res[3].content.includes('desconhecida'),
       'ferramentas executadas; id inválido e ferramenta desconhecida não chegam ao servidor');
assert(rpcs.some((x) => x.nome === 'stk_reconciliacao' && x.p_cozinha === 'c1' && x.p_dias === 7)
       && !rpcs.some((x) => x.nome === 'stk_consumo_diario'), 'as ferramentas usam sempre a cozinha do plano');
const reg = rpcs.find((x) => x.nome === 'registar_plano_compras');
assert(reg.p_resultado === 'pronto' && reg.p_plano.compras[0].urgencia === 'hoje' && reg.p_passos.length === 4 && corpo.resultado === 'pronto',
       'entrega o plano (o servidor valida) com os passos');

rpcs = []; pedidosClaude = [];
guiao = Array.from({ length: 9 }, (_, i) => resp('tool_use', usar('t' + i, 'compras_diarias', {}))).concat([resp('tool_use', usar('z', 'entregar_plano', final))]);
await pedido({ segredo: 's' });
const ultima = pedidosClaude[9].messages.at(-1).content;
assert(Array.isArray(ultima) && ultima.at(-1).text.includes('Não há mais tempo'), 'na última volta pede para entregar já');

rpcs = []; guiao = [new AuthenticationError('x')];
r = await pedido({ segredo: 's' });
assert((await r.json()).resultado === 'indisponivel', 'chave inválida: indisponível');
rpcs = []; guiao = [new Error('rede')];
r = await pedido({ segredo: 's' });
assert((await r.json()).resultado === 'erro' && rpcs.find((x) => x.nome === 'registar_plano_compras').p_nota === 'rede', 'erro de rede: volta a tentar');
