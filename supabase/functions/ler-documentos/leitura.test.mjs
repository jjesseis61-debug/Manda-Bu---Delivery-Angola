// Testes da Edge Function ler-documentos sem Deno nem rede: o Claude e o Supabase são simulados.
// Correr com: node --experimental-strip-types supabase/functions/ler-documentos/leitura.test.mjs
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

let handler;
let env = {};
let reserva = { comprovativos: [], extratos: [] };
let registos = [];
let pedidosClaude = [];
let respostaClaude = () => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: '{}' }] });

class APIError extends Error {}
class AuthenticationError extends APIError {}
class PermissionDeniedError extends APIError {}
class BadRequestError extends APIError {}
class RateLimitError extends APIError {}
class AnthropicSimulado {
  static AuthenticationError = AuthenticationError;
  static PermissionDeniedError = PermissionDeniedError;
  static BadRequestError = BadRequestError;
  constructor(opcoes) { this.opcoes = opcoes; }
  beta = { messages: { create: async (p) => { pedidosClaude.push(p); return respostaClaude(p); } } };
}
globalThis.__Anthropic = AnthropicSimulado;
globalThis.Deno = { env: { get: (k) => env[k] }, serve: (h) => { handler = h; } };
globalThis.__criarCliente = () => ({
  rpc: async (nome, args) => {
    if (nome === 'segredo_envio_valido') return { data: args.p_segredo === 'segredo-da-bd', error: null };
    if (nome === 'reservar_documentos') return { data: reserva, error: null };
    registos.push({ nome, ...args });
    if (nome === 'registar_leitura_comprovativo') return { data: args.p_resultado === 'lido' ? 'confere' : args.p_resultado, error: null };
    return { data: 0, error: null };
  },
  storage: { from: () => ({ download: async () => ({ data: new Blob([new Uint8Array([1, 2, 3])]), error: null }) }) },
});

const fonte = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  .replace("import Anthropic from 'npm:@anthropic-ai/sdk';", 'const Anthropic = (globalThis as any).__Anthropic;')
  .replace("import { createClient } from 'npm:@supabase/supabase-js@2';", 'const createClient = (globalThis as any).__criarCliente;');
const ficheiro = join(mkdtempSync(join(tmpdir(), 'ler-documentos-')), 'index.mts');
writeFileSync(ficheiro, fonte);
await import(pathToFileURL(ficheiro).href);

const pedido = (segredo = 's') => handler(new Request('http://x', { method: 'POST', headers: { 'x-envio-segredo': segredo } }));
const assert = (c, m) => { console.log(c ? 'ok  ' : 'FALHA', m); if (!c) process.exitCode = 1; };
const comp = (id) => ({ id, caminho: `${id}/1.jpg`, metodo: 'Multicaixa Express', valor: 3000, referencia: 'MCX-1', dia: '2026-10-03' });
const ext = { id: 'e1', caminho: 'e1/extrato.pdf', tipo_ficheiro: 'pdf', conta: 'BAI', inicio: '2026-10-01', fim: '2026-10-31' };
const json = (o) => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(o) }] });

// 1. segredo errado
env = { ENVIO_SEGREDO: 's', SUPABASE_URL: 'x', SUPABASE_SERVICE_ROLE_KEY: 'y' };
let r = await pedido('errado');
assert(r.status === 401, 'sem o segredo certo -> 401');

// 2. sem chave: tudo fica para a conferência humana, sem chamar o Claude
reserva = { comprovativos: [comp('c1')], extratos: [ext] };
registos = []; pedidosClaude = [];
r = await pedido();
assert(pedidosClaude.length === 0, 'sem ANTHROPIC_API_KEY não chama o Claude');
assert(registos.some((x) => x.p_id === 'c1' && x.p_resultado === 'indisponivel')
       && registos.some((x) => x.p_id === 'e1' && x.p_resultado === 'indisponivel'), 'sem chave -> comprovativo e extrato indisponíveis');

// 3. com chave: comprovativo lido, extrato lido
env.ANTHROPIC_API_KEY = 'chave';
registos = []; pedidosClaude = [];
respostaClaude = (p) => p.messages[0].content[0].type === 'image'
  ? json({ legivel: true, valor: 3000, referencia: 'MCX-1', data: '2026-10-03', nota: 'ok' })
  : json({ legivel: true, nota: '2 entradas', movimentos: [
      { data: '2026-10-03', valor: 3000, referencia: 'MCX-1', descricao: 'MCX' },
      { data: 'ontem', valor: 500, referencia: null, descricao: 'data inválida' }] });
r = await pedido();
const corpo = await r.json();
const pc = pedidosClaude[0];
assert(pc.model === 'claude-opus-5-5' && pc.fallbacks === 'default' && pc.betas.includes('server-side-fallback-2026-07-01'),
       'usa o claude-opus-5-5 com fallback por defeito');
assert(pc.output_config.format.type === 'json_schema' && pc.output_config.format.schema.required.includes('referencia'),
       'pede saída estruturada (valor, referência, data)');
assert(pc.messages[0].content[0].source.media_type === 'image/jpeg' && pc.messages[0].content[0].source.data === 'AQID',
       'envia a foto em base64');
const pe = pedidosClaude.find((p) => p.messages[0].content[0].type === 'document');
assert(pe && pe.messages[0].content[0].source.media_type === 'application/pdf', 'o extrato em PDF vai como documento');
assert(registos.some((x) => x.nome === 'registar_leitura_comprovativo' && x.p_resultado === 'lido' && x.p_valor === 3000 && x.p_referencia === 'MCX-1'),
       'regista o que leu no comprovativo');
const le = registos.find((x) => x.nome === 'registar_leitura_extrato');
assert(le && le.p_resultado === 'lido' && le.p_movimentos.length === 1, 'regista as entradas do extrato (descarta datas inválidas)');
assert(corpo.resultados.c1 === 'confere' && corpo.resultados.e1 === 'lido:1', 'devolve o resumo da execução');

// 4. ilegível, recusa e falhas
reserva = { comprovativos: [comp('c2'), comp('c3'), comp('c4'), comp('c5')], extratos: [] };
registos = [];
respostaClaude = (p) => {
  const id = p.messages[0].content[1].text && pedidosClaude.length;
  if (id % 4 === 1) return json({ legivel: false, valor: null, referencia: null, data: null, nota: 'foto desfocada' });
  if (id % 4 === 2) return { stop_reason: 'refusal', content: [] };
  if (id % 4 === 3) throw new RateLimitError('429');
  throw new AuthenticationError('401');
};
pedidosClaude = [];
r = await pedido();
const res = registos.filter((x) => x.nome === 'registar_leitura_comprovativo').map((x) => x.p_resultado).sort();
assert(JSON.stringify(res) === JSON.stringify(['erro', 'ilegivel', 'ilegivel', 'indisponivel']),
       'foto desfocada e recusa -> ilegível; limite de pedidos -> tenta outra vez; chave inválida -> indisponível');

// 5. nada para ler
reserva = { comprovativos: [], extratos: [] };
pedidosClaude = [];
r = await pedido();
assert((await r.json()).comprovativos === 0 && pedidosClaude.length === 0, 'sem documentos não chama o Claude');
