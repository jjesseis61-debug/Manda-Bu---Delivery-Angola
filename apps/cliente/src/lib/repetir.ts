// "Pedir de novo": repõe no carrinho os pratos de um pedido anterior que ainda estão disponíveis.
// Os pratos montados voltam com as opções que o servidor gravou no pedido. Se um deles mudou
// (uma opção acabou, ou já não cumpre as regras do prato), NÃO entra no carrinho alterado em
// silêncio: vai para a fila de pratos a rever no ecrã de montar, onde o cliente decide.
import { lerComponentes, lerCozinhaPublica, lerItemCardapio, lerOpcoes } from './api';
import type { CozinhaCarrinho, LinhaCarrinho, PendenteMontar } from './carrinho';
import { chaveLinha, gruposEmFalta, opcoesEscolhidas, precoMontado } from './opcoes';
import type { ComponentePrato, GrupoOpcoes, ItemCardapio, ItemOrcamento, OpcaoEscolhida } from './tipos';

export type Repetido = {
  linhas: LinhaCarrinho[];
  cozinha: CozinhaCarrinho | null;
  /** Nomes dos pratos que já não existem no cardápio */
  faltam: string[];
  /** Pratos montados que mudaram: o cliente revê-os, um de cada vez */
  aMontar: PendenteMontar[];
};

/**
 * Um prato montado do pedido anterior, comparado com o cardápio de agora.
 * Intacto (todas as opções ainda há e cumpre mínimo/máximo e o valor mínimo) → volta tal e qual.
 * Qualquer mudança → pendente de revisão, MESMO que ainda chegue ao valor mínimo:
 * o cliente escolhe outra opção ou decide seguir sem ela.
 */
export function reverMontado(
  item: ItemCardapio,
  grupos: GrupoOpcoes[],
  pedido: ItemOrcamento,
  tirados: ComponentePrato[] = [],
): { opcoes: OpcaoEscolhida[] } | { pendente: PendenteMontar } {
  const antes = pedido.opcoes ?? [];
  const disponiveis = new Set(grupos.flatMap((g) => g.opcoes.map((o) => o.id)));
  const escolhidas = antes.filter((o) => disponiveis.has(o.id)).map((o) => o.id);
  const faltaram = antes.filter((o) => !disponiveis.has(o.id)).map((o) => o.nome);
  const opcoes = opcoesEscolhidas(grupos, escolhidas);
  const total = precoMontado(item.preco, opcoes, tirados);
  const minimo = item.minimo_montavel ?? 0;
  const aMais = grupos.some((g) => g.opcoes.filter((o) => escolhidas.includes(o.id)).length > g.maximo);
  const intacto =
    faltaram.length === 0 &&
    gruposEmFalta(grupos, escolhidas).length === 0 &&
    !aMais &&
    total > 0 &&
    !(minimo > 0 && total < minimo);
  if (intacto) return { opcoes };
  return {
    pendente: { itemId: item.id, nome: item.nome, qtd: pedido.qtd, escolhidas, tirados: tirados.map((c) => c.produto_id), faltaram },
  };
}

function linha(item: ItemCardapio, qtd: number, opcoes: OpcaoEscolhida[], tirados: ComponentePrato[]): LinhaCarrinho {
  return { chave: chaveLinha(item.id, opcoes, tirados), item, qtd, opcoes, tirados };
}

export async function montarRepeticao(itens: ItemOrcamento[], montaveisLigados = true): Promise<Repetido> {
  const res = await Promise.all(itens.map(async (i) => ({ i, item: await lerItemCardapio(i.cardapio_id).catch(() => null) })));
  const ok = res.filter((r): r is { i: ItemOrcamento; item: ItemCardapio } => r.item !== null);
  const faltam = res.filter((r) => !r.item).map((r) => r.i.nome);
  const ids = [...new Set(ok.map((r) => r.item.id))];
  const comTirados = ok.some((r) => (r.i.componentes_excluidos?.length ?? 0) > 0);
  const [grupos, componentes] = await Promise.all([
    montaveisLigados ? lerOpcoes(ids) : Promise.resolve([] as GrupoOpcoes[]),
    comTirados ? lerComponentes(ids) : Promise.resolve([] as ComponentePrato[]),
  ]);

  const linhas: LinhaCarrinho[] = [];
  const aMontar: PendenteMontar[] = [];
  for (const { i, item } of ok) {
    const excluidos = i.componentes_excluidos ?? [];
    const tirados = componentes.filter((c) => c.cardapio_id === item.id && excluidos.includes(c.produto_id));
    const gs = grupos.filter((g) => g.cardapio_id === item.id);
    if (gs.length === 0) {
      linhas.push(linha(item, i.qtd, [], tirados));
      continue;
    }
    const r = reverMontado(item, gs, i, tirados);
    if ('pendente' in r) aMontar.push(r.pendente);
    else linhas.push(linha(item, i.qtd, r.opcoes, tirados));
  }

  let cozinha: CozinhaCarrinho | null = null;
  const cozId = ok[0]?.item.cozinha_id;
  if (cozId) {
    const c = await lerCozinhaPublica(cozId).catch(() => null);
    cozinha = { id: cozId, nome: c?.nome ?? 'A tua cozinha' };
  }
  return { linhas, cozinha, faltam, aMontar };
}
