// Cozinha de condomínio: o GPS decide o que o morador vê; o servidor confirma o endereço no pedido.
import * as Location from 'expo-location';

import { supabase } from './supabase';
import type { CozinhaParaPedir } from './tipos';

export type CondominioAqui = {
  condominio_id: string;
  nome: string;
  cozinha_id: string;
  cozinha: string;
  foto_url: string | null;
  historia: string | null;
  aberta: boolean;
  reabre_em: string | null;
  /** Aberta, ou fechada há menos de 12 horas */
  visivel: boolean;
  pratos: number;
};

export type CondominioLink = {
  nome: string;
  cozinha: string;
  lista_aberta: boolean;
  vagas_livres: number;
  inscricoes_ate: string | null;
  aprovacao_manual: boolean;
  meu_estado: 'activo' | 'pendente' | 'espera' | null;
  /** A lista está cheia mas aceita lista de espera */
  lista_espera?: boolean;
  em_espera?: number;
  minha_posicao?: number | null;
};

export type Promocao = {
  nome: string;
  descricao: string | null;
  tipo: 'percentagem' | 'preco';
  valor: number;
  cozinha_id: string | null;
  cozinha: string | null;
  minimo_pedido: number;
  fim: string | null;
};

export async function promocoesParaMim(ponto: string): Promise<Promocao[]> {
  return (verificar(await supabase.rpc('campanhas_para_mim', { p_ponto: ponto })) as Promocao[]) ?? [];
}

export type MeuCondominio = { nome: string; estado: 'activo' | 'pendente' | 'espera'; bloco: string | null; casa: string | null };

function verificar<T>(r: { data: T; error: { message: string } | null }): T {
  if (r.error) throw r.error;
  return r.data;
}

export async function condominioAqui(lat: number, lng: number): Promise<CondominioAqui | null> {
  return (verificar(await supabase.rpc('condominio_aqui', { p_lat: lat, p_lng: lng })) as CondominioAqui | null) ?? null;
}

export async function condominioPeloCodigo(codigo: string): Promise<CondominioLink | null> {
  return (verificar(await supabase.rpc('condominio_pelo_codigo', { p_codigo: codigo })) as CondominioLink | null) ?? null;
}

export async function pedirEntradaCondominio(codigo: string, bloco: string, casa: string): Promise<'activo' | 'pendente' | 'espera'> {
  return verificar(await supabase.rpc('condominio_pedir_entrada', { p_codigo: codigo, p_bloco: bloco, p_casa: casa })) as
    | 'activo'
    | 'pendente'
    | 'espera';
}

export async function meusCondominios(): Promise<MeuCondominio[]> {
  return (verificar(await supabase.rpc('meus_condominios')) as MeuCondominio[]) ?? [];
}

/**
 * Posição do telemóvel para o condomínio. Só pede autorização a quem é membro activo de algum
 * condomínio (os outros clientes nunca vêem o pedido de localização por causa disto).
 * Falha em silêncio (null): sem GPS, a app mostra as cozinhas normais.
 */
export async function posicaoParaCondominio(): Promise<{ lat: number; lng: number } | null> {
  try {
    let { status } = await Location.getForegroundPermissionsAsync();
    if (status !== 'granted') {
      const meus = await meusCondominios().catch(() => []);
      if (!meus.some((m) => m.estado === 'activo')) return null;
      ({ status } = await Location.requestForegroundPermissionsAsync());
      if (status !== 'granted') return null;
    }
    const conhecida = await Location.getLastKnownPositionAsync({ maxAge: 5 * 60_000 });
    const pos = conhecida ?? (await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced }));
    return { lat: pos.coords.latitude, lng: pos.coords.longitude };
  } catch {
    return null;
  }
}

/**
 * Cozinhas a mostrar com o condomínio: aberta → só a do condomínio; fechada (até 12 h) → as outras
 * (o cartão "fechada" aparece à parte); invisível ou fora → as outras, como sempre.
 */
export function cozinhasComCondominio(cond: CondominioAqui | null, outras: CozinhaParaPedir[]): CozinhaParaPedir[] {
  if (!cond || !cond.visivel || !cond.aberta) return outras;
  return [
    {
      cozinha_id: cond.cozinha_id,
      nome: cond.cozinha,
      publica: !!cond.foto_url,
      foto_url: cond.foto_url,
      historia: cond.historia,
      pratos: cond.pratos,
    },
  ];
}

/** Texto do cartão da cozinha do condomínio fechada */
export function textoCondominioFechado(cond: CondominioAqui, horaLuanda: (iso: string) => string): string {
  return `🔒 ${cond.cozinha} (${cond.nome}) está fechada${cond.reabre_em ? ` e volta às ${horaLuanda(cond.reabre_em)}` : ''}. Entretanto podes pedir noutra cozinha.`;
}

/** Preço com campanha de um prato (o mesmo que o servidor cobra por 1 unidade) */
export type PrecoCampanha = { cardapio_id: string; preco: number; preco_campanha: number; campanha: string };
export type PrecosParaMim = { entrega_gratis_acima: number | null; pratos: PrecoCampanha[] };

/** Preços com campanha da cozinha para a morada do cliente e o limiar da entrega grátis da zona */
export async function precosParaMim(ponto: string, cozinha: string): Promise<PrecosParaMim> {
  const r = await supabase.rpc('precos_para_mim', { p_ponto: ponto, p_cozinha: cozinha });
  if (r.error) throw r.error;
  return (r.data as PrecosParaMim) ?? { entrega_gratis_acima: null, pratos: [] };
}
