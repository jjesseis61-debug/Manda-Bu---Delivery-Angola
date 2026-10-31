// Testes do atendimento ao cliente sem Deno nem rede: o Claude e o Supabase são simulados.
// Correr com: node --experimental-strip-types supabase/functions/atendimento/atendimento.test.mjs
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
    if (nome === 'reservar_atendimento') return { data: reserva, error: null };
    if (nome === 'registar_atendimento') return { data: args.p_resultado === 'respondida' ? (args.p_resposta.passar_a_pessoa ? 'humano' : 'respondida') : args.p_resultado === 'erro' ? 'pendente' : 'humano', error: null };
    if (nome === 'atd_pedidos') return { data: [{ pedido_id: 'p2', estado: 'em_preparacao', atraso: { motivo_dado_ao_cliente: 'Muitos pedidos' } }], error: null };
    return { data: {}, error: null };
  },
});

const fonte = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  .replace("import Anthropic from 'npm:@anthropic-ai/sdk';", 'const Anthropic = (globalThis as any).__Anthropic;')
  .replace("import { createClient } from 'npm:@supabase/supabase-js@2';", 'const createClient = (globalThis as any).__criarCliente;');
const ficheiro = join(mkdtempSync(join(tmpdir(), 'atendimento-')), 'index.mts');
writeFileSync(ficheiro, fonte);
await import(pathToFileURL(ficheiro).href);

const C = '66666666-6666-4666-8666-666666666666';
const pedido = ({ segredo = '', corpo = {} } = {}) =>
  handler(new Request('http://x', { method: 'POST', headers: segredo ? { 'x-envio-segredo': segredo } : {}, body: JSON.stringify(corpo) }));
const assert = (c, m) => { console.log(c ? 'ok  ' : 'FALHA', m); if (!c) process.exitCode = 1; };
const usar = (id, name, input) => ({ type: 'tool_use', id, name, input });
const resp = (stop, ...content) => ({ stop_reason: stop, content });
const conversa = { id: C, primeiro_nome: 'Ana', agora: '2026-10-04 12:10',
  mensagens: [{ autor: 'cliente', texto: 'Onde está o meu calulu?', quando: '12:09' }] };
const final = { texto: 'Ana, o teu calulu está a ser preparado; atrasou por haver muitos pedidos.', passar_a_pessoa: false, motivo: null };

env = { ENVIO_SEGREDO: 's', SUPABASE_URL: 'x', SUPABASE_SERVICE_ROLE_KEY: 'y' };
let r = await pedido({ corpo: { conversa_id: 'x' } });
assert(r.status === 401, 'sem o segredo e sem conversa_id válido -> 401');

reserva = conversa; rpcs = []; pedidosClaude = [];
r = await pedido({ corpo: { conversa_id: C } });
assert((await r.json()).resultado === 'humano' && rpcs.some((x) => x.nome === 'registar_atendimento' && x.p_resultado === 'indisponivel')
       && pedidosClaude.length === 0, 'sem chave: a conversa passa para uma pessoa sem chamar o Claude');

env.ANTHROPIC_API_KEY = 'chave';
reserva = null; rpcs = [];
r = await pedido({ corpo: { conversa_id: C } });
assert((await r.json()).conversa === null && rpcs[0].nome === 'reservar_atendimento' && rpcs[0].p_id === C,
       'pela app reserva só a conversa indicada');

reserva = conversa; rpcs = []; pedidosClaude = [];
guiao = [
  resp('tool_use', usar('a', 'meus_pedidos', {}), usar('b', 'apagar_pedido', { pedido_id: 'p2' })),
  resp('tool_use', usar('c', 'responder', final)),
];
r = await pedido({ segredo: 's' });
const corpo = await r.json();
assert(pedidosClaude[0].model === 'claude-sonnet-5-5' && pedidosClaude[0].messages[0].content.includes('Ana: Onde está o meu calulu?')
       && pedidosClaude[0].system.includes('não prometas reembolsos'), 'modelo leve, a conversa e as regras');
const res = pedidosClaude[1].messages[2].content;
assert(res[0].content.includes('Muitos pedidos') && res[1].content.includes('desconhecida')
       && rpcs.some((x) => x.nome === 'atd_pedidos' && x.p_conversa === C), 'ferramentas sempre da conversa reservada; desconhecidas não chegam ao servidor');
assert(corpo.resultado === 'respondida' && rpcs.find((x) => x.nome === 'registar_atendimento').p_resposta.texto === final.texto,
       'guarda a resposta');

rpcs = []; pedidosClaude = [];
guiao = [resp('tool_use', usar('z', 'responder', { texto: 'Vou passar-te a um colega.', passar_a_pessoa: true, motivo: 'pede reembolso' }))];
r = await pedido({ segredo: 's' });
assert((await r.json()).resultado === 'humano', 'passa a uma pessoa quando o Claude o decide');

rpcs = []; pedidosClaude = [];
guiao = Array.from({ length: 4 }, (_, i) => resp('tool_use', usar('t' + i, 'informacoes', {}))).concat([resp('tool_use', usar('z', 'responder', final))]);
await pedido({ segredo: 's' });
assert(pedidosClaude[4].tool_choice?.name === 'responder' && pedidosClaude[3].tool_choice === undefined, 'na última volta obriga a responder');

rpcs = []; guiao = [new Error('rede')];
r = await pedido({ segredo: 's' });
assert((await r.json()).resultado === 'pendente' && rpcs.find((x) => x.nome === 'registar_atendimento').p_nota === 'rede', 'erro de rede: volta a tentar');
rpcs = []; guiao = [new BadRequestError('x')];
r = await pedido({ segredo: 's' });
assert((await r.json()).resultado === 'humano', 'pedido recusado pela API: passa para uma pessoa');
