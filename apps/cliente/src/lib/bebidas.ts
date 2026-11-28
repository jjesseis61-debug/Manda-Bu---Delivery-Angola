// Bebidas sozinhas no cardápio (gasosa, água, sumo) e a sugestão discreta no carrinho.
import type { LinhaCarrinho } from './carrinho';
import type { ItemCardapio } from './tipos';

const semAcentos = (t: string) =>
  t
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

const BEBIDA = /bebid|sumo|refri|gasosa|agua|coca|fanta|sprite|pepsi|batido|nocal|blue/;

/** A categoria do cardápio é de bebidas («Bebidas», «Refrigerantes», «Sumos»…) */
export function eCategoriaBebida(categoria: string | null | undefined): boolean {
  return !!categoria && BEBIDA.test(semAcentos(categoria));
}

/** O carrinho já leva bebida: um prato da categoria de bebidas ou uma opção que é bebida (sumo, gasosa no tabuleiro) */
export function carrinhoTemBebida(linhas: Pick<LinhaCarrinho, 'item' | 'opcoes'>[]): boolean {
  return linhas.some((l) => eCategoriaBebida(l.item.categoria) || l.opcoes.some((o) => BEBIDA.test(semAcentos(o.nome))));
}

/**
 * A bebida a sugerir quando o carrinho não tem nenhuma (Cialdini: prova social verdadeira, a mais pedida;
 * Prahalad: em empate, a mais barata). Só bebidas simples (sem montar) da cozinha do carrinho.
 */
export function bebidaSugerida(cardapio: ItemCardapio[], linhas: Pick<LinhaCarrinho, 'item' | 'opcoes'>[]): ItemCardapio | null {
  if (linhas.length === 0 || carrinhoTemBebida(linhas)) return null;
  const bebidas = cardapio.filter((i) => eCategoriaBebida(i.categoria) && !(i.minimo_montavel && i.minimo_montavel > 0));
  if (bebidas.length === 0) return null;
  return [...bebidas].sort((a, b) => (b.pedidos_mes ?? 0) - (a.pedidos_mes ?? 0) || a.preco - b.preco || a.nome.localeCompare(b.nome))[0];
}

/** «Falta a bebida? Gasosa 500 Kz» (com «a mais pedida» só quando é verdade) */
export function textoBebidaSugerida(b: Pick<ItemCardapio, 'nome' | 'pedidos_mes'>, preco: string): string {
  return `Falta a bebida? ${b.nome.trim()} · ${preco}${b.pedidos_mes > 0 ? ' · a mais pedida' : ''}`;
}
