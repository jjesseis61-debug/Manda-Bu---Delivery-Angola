// Testes do gerente de turno sem Deno nem rede: o Claude e o Supabase são simulados.
// Correr com: node --experimental-strip-types supabase/functions/turno/turno.test.mjs
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

class AnthropicSimulado {
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
    if (nome === 'reservar_turno') return { data: reserva, error: null };
    if (nome === 'registar_propostas_turno') return { data: args.p_propostas.length, error: null };
    if (nome === 'agente_historico_pedido') return { data: { eventos: [{ acao: 'pedido_estado' }] }, error: null };
    return { data: null, error: null };
  },
});

const fonte = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  .replace("import Anthropic from 'npm:@anthropic-ai/sdk';", 'const Anthropic = (globalThis as any).__Anthropic;')
  .replace("import { createClient } from 'npm:@supabase/supabase-js@2';", 'const createClient = (globalThis as any).__criarCliente;');
const ficheiro = join(mkdtempSync(join(tmpdir(), 'turno-')), 'index.mts');
writeFileSync(ficheiro, fonte);
await import(pathToFileURL(ficheiro).href);

const pedido = (segredo = 's') => handler(new Request('http://x', { method: 'POST', headers: { 'x-envio-segredo': segredo } }));
const assert = (c, m) => { console.log(c ? 'ok  ' : 'FALHA', m); if (!c) process.exitCode = 1; };
const P = '44444444-4444-4444-8444-444444444444';
const usar = (id, name, input) => ({ type: 'tool_use', id, name, input });
const resp = (stop, ...content) => ({ stop_reason: stop, content });
const proposta = { tipo: 'avisar_atraso', pedido_id: P, prioridade: 'alta', explicacao: 'Passou da hora.',
  motivo_cliente: 'Estamos com muitos pedidos', mais_minutos: 15 };

env = { ENVIO_SEGREDO: 's', SUPABASE_URL: 'x', SUPABASE_SERVICE_ROLE_KEY: 'y' };
let r = await pedido('errado');
assert(r.status === 401, 'sem o segredo certo -> 401');

rpcs = []; pedidosClaude = [];
r = await pedido();
assert((await r.json()).indisponivel && rpcs.length === 0, 'sem chave não reserva nem chama o Claude');

env.ANTHROPIC_API_KEY = 'chave';
reserva = null; pedidosClaude = [];
r = await pedido();
assert((await r.json()).cozinha === null && pedidosClaude.length === 0, 'nenhuma cozinha a pedir atenção -> não chama o Claude');

reserva = { cozinha_id: 'c1', situacao: { pedidos_em_curso: [{ pedido_id: P }] } };
rpcs = []; pedidosClaude = [];
guiao = [
  resp('tool_use', usar('a', 'historico_do_pedido', { pedido_id: P }), usar('b', 'historico_do_pedido', { pedido_id: 'x' })),
  resp('tool_use', usar('c', 'propor', { propostas: [proposta] })),
];
r = await pedido();
const corpo = await r.json();
assert(pedidosClaude[0].model === 'claude-sonnet-5-5' && pedidosClaude[0].messages[0].content.includes(P),
       'modelo mais leve, com a situação da cozinha');
assert(pedidosClaude[1].messages[2].content[0].content.includes('pedido_estado')
       && pedidosClaude[1].messages[2].content[1].content.includes('inválido'), 'abre o histórico pedido; id inválido não chega ao servidor');
const reg = rpcs.find((x) => x.nome === 'registar_propostas_turno');
assert(reg.p_cozinha === 'c1' && reg.p_propostas[0].motivo_cliente === 'Estamos com muitos pedidos' && corpo.propostas === 1,
       'guarda as propostas no servidor (que as valida)');

rpcs = []; pedidosClaude = [];
guiao = [resp('end_turn', { type: 'text', text: 'Tudo calmo.' }), resp('end_turn', { type: 'text', text: '...' }),
         resp('end_turn', { type: 'text', text: '...' }), resp('tool_use', usar('z', 'propor', { propostas: [] }))];
await pedido();
assert(pedidosClaude[3].tool_choice?.name === 'propor' && rpcs.some((x) => x.nome === 'registar_propostas_turno' && x.p_propostas.length === 0),
       'na última volta obriga a propor (lista vazia se estiver tudo bem)');
