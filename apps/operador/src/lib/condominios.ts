// Cozinha de condomínio (Fase 1): chamadas ao servidor, tipos e textos.
// O servidor verifica as permissões (cozinhas.gerir, ou pedidos.gerir na cozinha do condomínio).
import { supabase } from './supabase';

export type Condominio = {
  id: string;
  nome: string;
  cozinha_id: string;
  cozinha: string;
  zona_id: string | null;
  zona: string | null;
  centro_lat: number;
  centro_lng: number;
  raio_m: number;
  vagas: number;
  inscricoes_ate: string | null;
  inscricoes_abertas: boolean;
  aprovacao_manual: boolean;
  modo_entrega: 'cozinha' | 'parceiro';
  parceiro_nome: string | null;
  codigo: string;
  lista_aberta: boolean;
  cozinha_aberta: boolean;
  fechada_desde: string | null;
  reabre_em: string | null;
  activos: number;
  pendentes: number;
  activos_30d: number;
};

export type MembroCondominio = {
  id: string;
  cliente_nome: string;
  telefone: string | null;
  bloco: string | null;
  casa: string | null;
  estado: 'pendente' | 'activo';
  origem: 'link' | 'cozinha';
  criado_em: string;
  ultimo_pedido: string | null;
};

export type CondominioGuardar = {
  id?: string;
  nome: string;
  cozinha_id: string;
  zona_id: string | null;
  centro_lat: number;
  centro_lng: number;
  raio_m: number;
  vagas: number;
  inscricoes_ate: string | null;
  inscricoes_abertas: boolean;
  aprovacao_manual: boolean;
  modo_entrega: 'cozinha' | 'parceiro';
  parceiro_nome: string | null;
};

function verificar<T>(r: { data: T; error: { message: string } | null }): T {
  if (r.error) throw r.error;
  return r.data;
}

export async function lerCondominios(): Promise<Condominio[]> {
  return (verificar(await supabase.rpc('condominios_lista')) as Condominio[]) ?? [];
}

export async function guardarCondominio(c: CondominioGuardar): Promise<string> {
  return verificar(await supabase.rpc('guardar_condominio', { p: c })) as string;
}

export async function apagarCondominio(id: string) {
  verificar(await supabase.rpc('apagar_condominio', { p_id: id }));
}

export async function lerMembrosCondominio(id: string): Promise<MembroCondominio[]> {
  return (verificar(await supabase.rpc('condominio_membros_lista', { p_cond: id })) as MembroCondominio[]) ?? [];
}

export async function adicionarMembroCondominio(id: string, telefone: string, bloco: string, casa: string) {
  verificar(await supabase.rpc('condominio_adicionar_membro', { p_cond: id, p_telefone: telefone, p_bloco: bloco, p_casa: casa }));
}

export async function decidirMembroCondominio(membro: string, accao: 'aprovar' | 'recusar' | 'remover') {
  verificar(await supabase.rpc('condominio_decidir_membro', { p_membro: membro, p_accao: accao }));
}

export async function abrirFecharCozinha(cozinha: string, aberta: boolean, reabreEm: string | null = null) {
  verificar(await supabase.rpc('abrir_fechar_cozinha', { p_cozinha: cozinha, p_aberta: aberta, p_reabre_em: reabreEm }));
}

/** Link para os moradores pedirem para entrar (abre a app do cliente) */
export function linkCondominio(codigo: string): string {
  const site = (process.env.EXPO_PUBLIC_SITE_URL || 'https://manda-bue.netlify.app').replace(/\/+$/, '');
  return `${site}/condominio/${encodeURIComponent(codigo)}`;
}

export function mensagemConviteCondominio(nome: string, link: string): string {
  return `🏘️ ${nome} já tem a sua cozinha no Manda Bué! Pede para entrar na lista de moradores: ${link}`;
}

/** "32/50 membros · lista aberta" */
export function textoVagas(c: Pick<Condominio, 'activos' | 'pendentes' | 'vagas' | 'lista_aberta'>): string {
  const ocupadas = c.activos + c.pendentes;
  const estado = c.lista_aberta ? 'lista aberta' : ocupadas >= c.vagas ? 'lista completa' : 'lista fechada';
  return `${c.activos}/${c.vagas} membros${c.pendentes ? ` · ${c.pendentes} à espera de aprovação` : ''} · ${estado}`;
}

/** Hora prevista de reabertura: daqui a N horas (1–24), em ISO */
export function reabreDaquiA(horas: number, agora: Date = new Date()): string | null {
  if (!Number.isInteger(horas) || horas < 1 || horas > 24) return null;
  return new Date(agora.getTime() + horas * 3600_000).toISOString();
}

/** "30/11/2026" -> fim desse dia em Luanda (ISO); "" -> null; inválida -> undefined */
export function dataLimiteISO(texto: string): string | null | undefined {
  const t = texto.trim();
  if (t === '') return null;
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(t);
  if (!m) return undefined;
  const [d, mes, a] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const data = new Date(Date.UTC(a, mes - 1, d));
  if (data.getUTCDate() !== d || data.getUTCMonth() !== mes - 1) return undefined;
  return `${a}-${String(mes).padStart(2, '0')}-${String(d).padStart(2, '0')}T23:59:59+01:00`;
}

/** ISO -> "30/11/2026" (data de Luanda) */
export function dataLimiteTexto(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(new Date(iso).getTime() + 3600_000);
  return `${String(d.getUTCDate()).padStart(2, '0')}/${String(d.getUTCMonth() + 1).padStart(2, '0')}/${d.getUTCFullYear()}`;
}

/** Estado da cozinha do condomínio, como o morador o vê */
export function textoEstadoCozinha(c: Pick<Condominio, 'cozinha_aberta' | 'fechada_desde'>, agora: Date = new Date()): string {
  if (c.cozinha_aberta) return '🟢 Aberta';
  if (!c.fechada_desde) return '🔴 Fechada';
  const horas = (agora.getTime() - new Date(c.fechada_desde).getTime()) / 3600_000;
  return horas >= 12 ? '🔴 Fechada há mais de 12 h (invisível para os moradores)' : '🔴 Fechada (os moradores vêem "fechada")';
}

const ERROS: Record<string, string> = {
  cozinha_principal_nao: 'A cozinha principal não pode ser de condomínio (recebe os pedidos de todos).',
  cozinha_ja_tem_condominio: 'Essa cozinha já serve outro condomínio.',
  cliente_nao_encontrado: 'Não há conta com esse número. O morador tem de criar conta na app primeiro.',
  lista_cheia: 'A lista está completa. Aumenta as vagas para acrescentar mais moradores.',
  hora_invalida: 'Hora de reabertura inválida.',
};

/** Mensagem amiga para os erros do servidor dos condomínios (null = usar a mensagem geral) */
export function erroCondominio(e: unknown): string | null {
  const m = e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : '';
  const chave = Object.keys(ERROS).find((k) => m.includes(k));
  return chave ? ERROS[chave] : null;
}
