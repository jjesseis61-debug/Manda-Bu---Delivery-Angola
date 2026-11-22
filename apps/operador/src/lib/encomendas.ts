import { supabase } from './supabase';

export type EstadoEncomenda = 'pedida' | 'na_cozinha' | 'proposta' | 'a_confirmar' | 'confirmada' | 'recusada' | 'cancelada';

export type SugestaoCozinha = { cozinha_id: string; nome: string; sabe_fazer: boolean; distancia_km: number | null };

/** Encomenda de uma receita que nenhuma cozinha tem no cardápio (vista do operador ou da cozinha) */
export type EncomendaOperador = {
  id: string;
  estado: EstadoEncomenda;
  criado_em: string;
  para_quando: string;
  pessoas: number;
  nota: string | null;
  motivo: string | null;
  receita: string;
  cozinha_id: string | null;
  cozinha_nome: string | null;
  preco_cozinha: number | null;
  nota_cozinha: string | null;
  preco: number | null;
  taxa_entrega: number;
  total: number | null;
  sinal: number;
  pedido_id: string | null;
  local: string | null;
  cliente_nome: string;
  cliente_telefone: string | null;
  /** Operador (pedidos.gerir): envia à cozinha, aprova e cancela */
  pode_gerir: boolean;
  /** Cozinha a quem foi enviada (ou o operador): propõe o preço ou recusa */
  pode_propor: boolean;
  sugestoes: SugestaoCozinha[] | null;
};

export const nomeEstadoEncomenda: Record<EstadoEncomenda, string> = {
  pedida: 'Escolher cozinha',
  na_cozinha: 'Na cozinha: à espera do preço',
  proposta: 'Preço proposto: aprovar',
  a_confirmar: 'À espera do cliente',
  confirmada: 'Confirmada',
  recusada: 'Recusada pelo cliente',
  cancelada: 'Cancelada',
};

function verificar<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw r.error;
  return r.data as T;
}

export async function encomendasLista(): Promise<EncomendaOperador[]> {
  return (verificar(await supabase.rpc('encomendas_lista')) as EncomendaOperador[]) ?? [];
}

export async function enviarEncomendaCozinha(id: string, cozinhaId: string): Promise<void> {
  verificar(await supabase.rpc('encomenda_enviar_cozinha', { p_id: id, p_cozinha: cozinhaId }));
}

/** Preço null = a cozinha não pode fazer (a nota é o motivo) */
export async function responderEncomendaCozinha(id: string, preco: number | null, nota: string): Promise<void> {
  verificar(await supabase.rpc('encomenda_resposta_cozinha', { p_id: id, p_preco: preco, p_nota: nota.trim() || null }));
}

export async function aprovarEncomenda(id: string, preco: number): Promise<void> {
  verificar(await supabase.rpc('encomenda_aprovar', { p_id: id, p_preco: preco }));
}

export async function cancelarEncomenda(id: string, motivo: string): Promise<void> {
  verificar(await supabase.rpc('encomenda_cancelar', { p_id: id, p_motivo: motivo.trim() }));
}

/** Por fazer (o que precisa de alguém agora) e o resto */
export function separarEncomendas(l: EncomendaOperador[]) {
  const porFazer = l.filter((e) => (e.estado === 'pedida' || e.estado === 'proposta') ? e.pode_gerir : e.estado === 'na_cozinha' && e.pode_propor);
  return { porFazer, outras: l.filter((e) => !porFazer.includes(e)) };
}
