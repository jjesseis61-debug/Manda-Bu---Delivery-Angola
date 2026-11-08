import { useRouter } from 'expo-router';

import { useCarrinho } from './carrinho';
import { montarRepeticao } from './repetir';
import { useSessao } from './sessao';
import type { ItemOrcamento } from './tipos';

/**
 * "Pedir de novo" (pedidos, detalhe do pedido e início): repõe o carrinho e, se houver pratos
 * montados que mudaram, abre o ecrã de montar para o primeiro (os outros seguem à vez).
 * Devolve false quando já não há nenhum prato do pedido no cardápio.
 */
export function usePedirDeNovo(): (itens: ItemOrcamento[]) => Promise<boolean> {
  const carrinho = useCarrinho();
  const router = useRouter();
  const { ligada } = useSessao();

  return async (itens) => {
    const { linhas, cozinha, faltam, aMontar } = await montarRepeticao(itens, ligada('pratos_montaveis'));
    if (linhas.length === 0 && aMontar.length === 0) return false;
    carrinho.repor(linhas, cozinha);
    if (aMontar.length > 0) {
      carrinho.definirRepeticao({ fila: aMontar, faltam });
      router.push({ pathname: '/montar/[id]', params: { id: aMontar[0].itemId, rever: '1' } });
    } else {
      carrinho.definirRepeticao(null);
      router.push({ pathname: '/carrinho', params: faltam.length > 0 ? { faltam: faltam.join(', ') } : {} });
    }
    return true;
  };
}
