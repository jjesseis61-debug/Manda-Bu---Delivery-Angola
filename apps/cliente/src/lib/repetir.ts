// "Pedir de novo": repõe no carrinho os pratos de um pedido anterior, pelos que ainda estão
// disponíveis no cardápio. As opções/montagens não se guardam no pedido, por isso repõem-se os
// pratos base (os montáveis voltam a personalizar-se).
import { lerCozinhaPublica, lerItemCardapio } from './api';
import type { CozinhaCarrinho, LinhaCarrinho } from './carrinho';
import { chaveLinha } from './opcoes';
import type { ItemOrcamento } from './tipos';

export async function montarRepeticao(
  itens: ItemOrcamento[],
): Promise<{ linhas: LinhaCarrinho[]; cozinha: CozinhaCarrinho | null; faltam: string[] }> {
  const res = await Promise.all(itens.map(async (i) => ({ i, item: await lerItemCardapio(i.cardapio_id).catch(() => null) })));
  const ok = res.filter((r) => r.item);
  const faltam = res.filter((r) => !r.item).map((r) => r.i.nome);
  const linhas: LinhaCarrinho[] = ok.map((r) => ({
    chave: chaveLinha(r.item!.id, [], []),
    item: r.item!,
    qtd: r.i.qtd,
    opcoes: [],
    tirados: [],
  }));
  let cozinha: CozinhaCarrinho | null = null;
  const cozId = ok[0]?.item?.cozinha_id;
  if (cozId) {
    const c = await lerCozinhaPublica(cozId).catch(() => null);
    cozinha = { id: cozId, nome: c?.nome ?? 'A tua cozinha' };
  }
  return { linhas, cozinha, faltam };
}
