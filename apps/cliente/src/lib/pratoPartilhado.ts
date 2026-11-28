// Prato aberto por link (ou pelo ecrã de montar): a que cozinha pertence e se pode entrar no carrinho.
// O servidor recusa um pedido com pratos de outra cozinha ("item indisponível"), por isso a app
// muda o carrinho para a cozinha do prato (perguntando antes, se já tiver pratos).
import { cozinhaPadrao, cozinhasParaPedir } from './api';
import { condominioAqui, posicaoParaCondominio } from './condominio';

export type DecisaoCozinha =
  /** O carrinho já é desta cozinha: adiciona */
  | 'adicionar'
  /** Carrinho vazio (ou sem cozinha): passa para a cozinha do prato e adiciona */
  | 'trocar'
  /** Carrinho com pratos de outra cozinha: pergunta antes de o esvaziar */
  | 'confirmar'
  /** Pedido de grupo de outra cozinha: não se mistura */
  | 'grupo'
  /** Cozinha fechada, inactiva ou só para moradores de um condomínio */
  | 'indisponivel';

export function decidirCozinha(p: {
  cozinhaPrato: string;
  actual: string | null;
  quantidade: number;
  emGrupo: boolean;
  /** Cozinhas a que este cliente pode pedir agora; null = não se sabe (o servidor volta a validar) */
  disponiveis: string[] | null;
}): DecisaoCozinha {
  if (p.disponiveis && !p.disponiveis.includes(p.cozinhaPrato)) return 'indisponivel';
  if (p.actual === p.cozinhaPrato) return 'adicionar';
  if (p.emGrupo) return 'grupo';
  if (!p.actual || p.quantidade === 0) return 'trocar';
  return 'confirmar';
}

export const TEXTO_INDISPONIVEL =
  'Este prato não está disponível para ti agora: a cozinha está fechada ou é só para os moradores de um condomínio.';

/** Prato sem opções nem ingredientes para tirar: página simples com "Adicionar ao carrinho" */
export function pratoSimples(grupos: unknown[], componentes: unknown[]): boolean {
  return grupos.length === 0 && componentes.length === 0;
}

/**
 * Cozinhas a que o cliente pode pedir agora, com o nome (para o carrinho).
 * Com multi_cozinha: as da lista geral e, se estiver num condomínio de que é membro e a cozinha
 * estiver aberta, a do condomínio. Sem multi_cozinha: só a cozinha principal.
 * Falha → null (não bloqueia; o servidor valida ao confirmar).
 */
export async function cozinhasDisponiveis(
  multiCozinha: boolean,
  condominios: boolean,
): Promise<{ id: string; nome: string }[] | null> {
  try {
    if (!multiCozinha) {
      const id = await cozinhaPadrao();
      return id ? [{ id, nome: '' }] : [];
    }
    const lista = (await cozinhasParaPedir()).map((c) => ({ id: c.cozinha_id, nome: c.nome }));
    if (condominios) {
      const pos = await posicaoParaCondominio();
      const cond = pos ? await condominioAqui(pos.lat, pos.lng).catch(() => null) : null;
      if (cond?.aberta) lista.push({ id: cond.cozinha_id, nome: cond.cozinha });
    }
    return lista;
  } catch {
    return null;
  }
}
