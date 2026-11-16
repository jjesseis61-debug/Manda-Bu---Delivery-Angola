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
  /** Com as vagas cheias, quem pede fica em lista de espera */
  lista_espera: boolean;
  espera: number;
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
  estado: 'pendente' | 'activo' | 'espera';
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
  lista_espera: boolean;
  modo_entrega: 'cozinha' | 'parceiro';
  parceiro_nome: string | null;
};

export type RelatorioCondominio = {
  membros: { activos: number; pendentes: number; espera: number; novos: number; sairam: number; vagas: number };
  pedidos: number;
  entregues: number;
  cancelados: number;
  vendas: number;
  ticket_medio: number | null;
  clientes: number;
  membros_que_pediram: number;
  com_campanha: number;
  pratos: { nome: string; qtd: number }[];
  horas: { hora: string; pedidos: number }[];
};

export type Campanha = {
  id: string;
  nome: string;
  descricao: string | null;
  condominio_id: string | null;
  condominio: string | null;
  zona_id: string | null;
  zona: string | null;
  cozinha_id: string | null;
  cozinha: string | null;
  tipo: 'percentagem' | 'preco';
  valor: number;
  cardapio_ids: string[] | null;
  minimo_pedido: number;
  inicio: string;
  fim: string | null;
  dias_semana: number[] | null;
  hora_inicio: string | null;
  hora_fim: string | null;
  so_membros: boolean;
  limite_por_cliente: number | null;
  limite_total: number | null;
  activa: boolean;
  avisado_em: string | null;
  em_curso: boolean;
  resultado: { pedidos: number; entregues: number; clientes: number; vendas: number; desconto: number };
};

export type CampanhaGuardar = Omit<Campanha, 'id' | 'condominio' | 'zona' | 'cozinha' | 'avisado_em' | 'em_curso' | 'resultado'> & {
  id?: string;
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

export async function relatorioCondominio(id: string, inicio: string, fim: string): Promise<RelatorioCondominio> {
  return verificar(await supabase.rpc('relatorio_condominio', { p_cond: id, p_inicio: inicio, p_fim: fim })) as RelatorioCondominio;
}

export async function lerCampanhas(): Promise<Campanha[]> {
  return (verificar(await supabase.rpc('campanhas_lista')) as Campanha[]) ?? [];
}

export async function guardarCampanha(c: CampanhaGuardar): Promise<string> {
  return verificar(await supabase.rpc('guardar_campanha', { p: c })) as string;
}

export async function apagarCampanha(id: string) {
  verificar(await supabase.rpc('apagar_campanha', { p_id: id }));
}

/** Avisa os clientes da campanha (uma vez); devolve quantos */
export async function avisarCampanha(id: string): Promise<number> {
  return verificar(await supabase.rpc('campanha_avisar', { p_id: id })) as number;
}

/** "20% nos pratos" / "Preço especial: 1.500 Kz" */
export function textoOferta(c: Pick<Campanha, 'tipo' | 'valor'>): string {
  return c.tipo === 'percentagem' ? `${c.valor}% de desconto nos pratos` : `Preço especial: ${formatarKzSimples(c.valor)}`;
}

const DIAS = ['', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

/** "sex e sáb · 12:00–15:00" (vazio = todos os dias, todo o dia) */
export function textoQuando(c: Pick<Campanha, 'dias_semana' | 'hora_inicio' | 'hora_fim'>): string {
  const dias = c.dias_semana && c.dias_semana.length > 0 && c.dias_semana.length < 7
    ? [...c.dias_semana].sort().map((d) => DIAS[d]).join(', ')
    : 'todos os dias';
  return c.hora_inicio && c.hora_fim ? `${dias} · ${c.hora_inicio}–${c.hora_fim}` : dias;
}

function formatarKzSimples(v: number): string {
  return `${Math.round(v).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')} Kz`;
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
export function textoVagas(
  c: Pick<Condominio, 'activos' | 'pendentes' | 'vagas' | 'lista_aberta'> & { espera?: number },
): string {
  const ocupadas = c.activos + c.pendentes;
  const estado = c.lista_aberta ? 'lista aberta' : ocupadas >= c.vagas ? 'lista completa' : 'lista fechada';
  return `${c.activos}/${c.vagas} membros${c.pendentes ? ` · ${c.pendentes} à espera de aprovação` : ''}${
    c.espera ? ` · ${c.espera} em lista de espera` : ''
  } · ${estado}`;
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
  ja_avisado: 'Os clientes desta campanha já foram avisados.',
  sem_publico: 'Só se avisa uma campanha de um condomínio ou de uma zona.',
};

/** Mensagem amiga para os erros do servidor dos condomínios (null = usar a mensagem geral) */
export function erroCondominio(e: unknown): string | null {
  const m = e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : '';
  const chave = Object.keys(ERROS).find((k) => m.includes(k));
  return chave ? ERROS[chave] : null;
}
