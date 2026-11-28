import { supabase } from './supabase';
import { horaLuanda } from './formatar';
import type { MetodoAntes } from './tipos';

const DIA_SEMANA = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

/** «Sáb 28/11» a partir de 'AAAA-MM-DD' */
export function rotuloDia(dia: string): string {
  const d = new Date(`${dia}T12:00:00Z`);
  return `${DIA_SEMANA[d.getUTCDay()]} ${dia.slice(8, 10)}/${dia.slice(5, 7)}`;
}

/** «Sáb 28/11 às 13h00» (Luanda) */
export function quandoEncomenda(iso: string): string {
  const dia = new Date(new Date(iso).getTime() + 3600_000).toISOString().slice(0, 10);
  return `${rotuloDia(dia)} às ${horaLuanda(iso)}`;
}

export type EstadoEncomenda = 'pedida' | 'na_cozinha' | 'proposta' | 'a_confirmar' | 'confirmada' | 'recusada' | 'cancelada';

/** Encomenda de uma receita (prato que ninguém tem no cardápio), tratada pelo operador */
export type Encomenda = {
  id: string;
  estado: EstadoEncomenda;
  criado_em: string;
  para_quando: string;
  pessoas: number;
  nota: string | null;
  motivo: string | null;
  receita_id: string;
  receita: string;
  cozinha_nome: string | null;
  preco: number | null;
  taxa_entrega: number;
  total: number | null;
  sinal: number;
  pedido_id: string | null;
  pago_antes: number | null;
  pagamento: { estado: 'pendente' | 'confirmado' | 'rejeitado' | 'devolvido'; valor: number; motivo: string | null } | null;
  local: string | null;
};

function verificar<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw r.error;
  return r.data as T;
}

export async function encomendar(dados: { receitaId: string; pessoas: number; paraQuando: string; pontoId: string; nota: string }): Promise<string> {
  return verificar(
    await supabase.rpc('encomendar', {
      p_receita: dados.receitaId,
      p_pessoas: dados.pessoas,
      p_para_quando: dados.paraQuando,
      p_ponto: dados.pontoId,
      p_nota: dados.nota.trim() || null,
    }),
  ) as string;
}

export async function minhasEncomendas(): Promise<Encomenda[]> {
  return (verificar(await supabase.rpc('minhas_encomendas')) as Encomenda[]) ?? [];
}

export async function responderEncomenda(id: string, aceitar: boolean): Promise<string | null> {
  return verificar(await supabase.rpc('encomenda_responder', { p_id: id, p_aceitar: aceitar })) as string | null;
}

export async function pagarSinalEncomenda(id: string, metodo: MetodoAntes, referencia: string): Promise<void> {
  verificar(await supabase.rpc('encomenda_pagar_sinal', { p_id: id, p_metodo: metodo, p_referencia: referencia }));
}

export async function cancelarEncomenda(id: string): Promise<void> {
  verificar(await supabase.rpc('encomenda_cancelar_cliente', { p_id: id }));
}

/** O que a encomenda está a fazer, em palavras do cliente */
export function textoEstadoEncomenda(e: Pick<Encomenda, 'estado' | 'cozinha_nome' | 'motivo'>): string {
  switch (e.estado) {
    case 'pedida':
      return 'Recebida: estamos a escolher a cozinha que a faz.';
    case 'na_cozinha':
    case 'proposta':
      return `${e.cozinha_nome ?? 'A cozinha'} está a preparar o preço.`;
    case 'a_confirmar':
      return 'O preço está pronto: confirma para avançarmos.';
    case 'confirmada':
      return 'Confirmada.';
    case 'recusada':
      return 'Recusaste a proposta.';
    case 'cancelada':
      return `Cancelada${e.motivo ? `: ${e.motivo}` : ''}.`;
  }
}

/** Dias possíveis (AAAA-MM-DD, Luanda) a partir de `horas` de antecedência, durante 7 dias */
export function diasParaEncomenda(agora: Date = new Date(), horas = 24): string[] {
  const r: string[] = [];
  for (let i = 0; i <= 8 && r.length < 7; i++) {
    const d = new Date(agora.getTime() + 3600_000 + i * 86_400_000).toISOString().slice(0, 10);
    if (HORAS_ENCOMENDA.some((h) => instanteLuanda(d, h).getTime() >= agora.getTime() + horas * 3600_000)) r.push(d);
  }
  return r;
}

/** Horas a que se pode entregar uma encomenda (Luanda) */
export const HORAS_ENCOMENDA = ['11:00', '12:00', '13:00', '14:00', '17:00', '18:00', '19:00', '20:00'];

/** 'AAAA-MM-DD' + 'HH:MM' em Luanda (UTC+1) -> Date */
export function instanteLuanda(dia: string, hora: string): Date {
  return new Date(`${dia}T${hora}:00+01:00`);
}
