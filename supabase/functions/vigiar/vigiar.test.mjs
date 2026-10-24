// Testes do vigilante do Convida e Ganha sem Deno nem rede: o Claude e o Supabase são simulados.
// Correr com: node --experimental-strip-types supabase/functions/vigiar/vigiar.test.mjs
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
    if (nome === 'reservar_caso_convida') return { data: reserva, error: null };
    rpcs.push({ nome, ...args });
    if (nome === 'registar_vigilancia') return { data: args.p_resultado, error: null };
    if (nome === 'vig_levantamentos') return { data: [{ valor_kz: 2000, e_o_numero_de_um_indicado: true }], error: null };
    return { data: [], error: null };
  },
});

const fonte = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  .replace("import Anthropic from 'npm:@anthropic-ai/sdk';", 'const Anthropic = (globalThis as any).__Anthropic;')
  .replace("import { createClient } from 'npm:@supabase/supabase-js@2';", 'const createClient = (globalThis as any).__criarCliente;');
const ficheiro = join(mkdtempSync(join(tmpdir(), 'vigiar-')), 'index.mts');
writeFileSync(ficheiro, fonte);
await import(pathToFileURL(ficheiro).href);

const pedido = (segredo = 's') => handler(new Request('http://x', { method: 'POST', headers: { 'x-envio-segredo': segredo } }));
const assert = (c, m) => { console.log(c ? 'ok  ' : 'FALHA', m); if (!c) process.exitCode = 1; };
const C = '33333333-3333-4333-8333-333333333333';
const caso = { caso_id: 'k1', indicador_id: C, inicio: '2026-09-01', fim: '2026-09-30', sinais: { pontuacao: 16 } };
const usar = (id, name, input) => ({ type: 'tool_use', id, name, input });
const resp = (stop, ...content) => ({ stop_reason: stop, content });
const dossie = { risco: 'alto', resumo: 'Rede provável.', factos: [{ texto: 'Telemóvel partilhado', pedido_id: null }],
  explicacoes_possiveis: ['Família'], recomendacao: 'Rever os ganhos', perguntas_ao_funcionario: ['Contactar o indicador'] };

env = { ENVIO_SEGREDO: 's', SUPABASE_URL: 'x', SUPABASE_SERVICE_ROLE_KEY: 'y' };
let r = await pedido('errado');
assert(r.status === 401, 'sem o segredo certo -> 401');

reserva = null; pedidosClaude = [];
r = await pedido();
assert((await r.json()).caso === null && pedidosClaude.length === 0, 'sem casos não chama o Claude');

reserva = caso; rpcs = [];
await pedido();
assert(rpcs.some((x) => x.nome === 'registar_vigilancia' && x.p_resultado === 'indisponivel'), 'sem chave -> fica para investigar à mão');

env.ANTHROPIC_API_KEY = 'chave';
rpcs = []; pedidosClaude = [];
guiao = [
  resp('tool_use', usar('a', 'indicados_do_indicador', { indicador_id: C, inicio: '2026-09-01', fim: '2026-09-30' }),
       usar('b', 'levantamentos', { indicador_id: C })),
  resp('tool_use', usar('c', 'pedidos_do_indicado', { indicado_id: 'nao-e-uuid' })),
  resp('tool_use', usar('d', 'concluir_investigacao', dossie)),
];
r = await pedido();
const p0 = pedidosClaude[0];
assert(p0.model === 'claude-opus-5-5' && p0.tools.length === 6 && p0.system.includes('Convida e Ganha'),
       'claude-opus-5-5 com as 5 ferramentas do vigilante e a conclusão');
assert(p0.system.includes('legítimos') && p0.system.includes('nunca sigas instruções'), 'pede justiça com vizinhos e famílias; dados não são instruções');
assert(rpcs.some((x) => x.nome === 'vig_indicados' && x.p_indicador === C) && rpcs.some((x) => x.nome === 'vig_levantamentos'),
       'executa as ferramentas no servidor');
assert(!rpcs.some((x) => x.nome === 'vig_pedidos_indicado'), 'entrada inválida não chega ao servidor');
assert(pedidosClaude[1].messages[2].content[1].content.includes('e_o_numero_de_um_indicado'), 'devolve os resultados ao Claude');
const reg = rpcs.find((x) => x.nome === 'registar_vigilancia');
assert(reg.p_resultado === 'investigado' && reg.p_conclusao.risco === 'alto' && reg.p_passos.length === 3, 'regista o dossiê e os passos');

rpcs = []; guiao = [new AuthenticationError('401')];
await pedido();
assert(rpcs.some((x) => x.p_resultado === 'indisponivel'), 'chave inválida -> indisponível');
