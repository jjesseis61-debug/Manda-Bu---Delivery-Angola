import { supabase } from './supabase';

/** Pagamento feito antes da entrega por um participante de um grupo (a confirmar pelas Finanças) */
export type PagamentoAntes = {
  id: string;
  pedido_id: string;
  cliente_nome: string;
  cliente_telefone: string | null;
  metodo: 'multicaixa_express' | 'unitel_money';
  valor: number;
  referencia: string;
  estado: 'pendente' | 'confirmado' | 'rejeitado' | 'devolvido';
  motivo: string | null;
  criado_em: string;
  decidido_em: string | null;
  pedido_estado: string;
  grupo_hora: string | null;
  cozinha_nome: string | null;
  /** Pedido cancelado depois de pago, ou pago também na entrega: devolver ao cliente */
  a_devolver: boolean;
};

export const nomeMetodoAntes = { multicaixa_express: 'Multicaixa Express', unitel_money: 'Unitel Money' } as const;

function verificar<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw r.error;
  return r.data as T;
}

export async function pagamentosAntes(): Promise<PagamentoAntes[]> {
  return (verificar(await supabase.rpc('pagamentos_antes_lista')) as PagamentoAntes[]) ?? [];
}

export async function decidirPagamentoAntes(id: string, confirmar: boolean, motivo?: string): Promise<void> {
  verificar(await supabase.rpc('decidir_pagamento_antes', { p_id: id, p_confirmar: confirmar, p_motivo: motivo ?? null }));
}

export async function devolverPagamentoAntes(id: string, referencia: string): Promise<void> {
  verificar(await supabase.rpc('devolver_pagamento_antes', { p_id: id, p_referencia: referencia }));
}

/** Separa a lista nas três partes do ecrã */
export function separarPagamentosAntes(lista: PagamentoAntes[]) {
  return {
    aConfirmar: lista.filter((p) => p.estado === 'pendente' && !p.a_devolver),
    aDevolver: lista.filter((p) => p.a_devolver),
    decididos: lista.filter((p) => p.estado !== 'pendente' && !p.a_devolver),
  };
}
