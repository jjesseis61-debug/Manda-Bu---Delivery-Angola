// Fila de acções feitas sem rede, guardada no telemóvel (sobrevive a reinícios). Quando a rede volta,
// sincronizar.ts reproduz as acções por ordem. Cobre as mudanças de estado e a entrega paga em
// DINHEIRO (sem foto). O pagamento electrónico precisa de enviar a foto do comprovativo, por isso
// exige rede no momento: não entra na fila.
import AsyncStorage from '@react-native-async-storage/async-storage';

const CHAVE = 'manda-bue-estafeta:fila-offline';

export type AccaoFila =
  | { id: string; pedido_id: string; tipo: 'em_entrega'; criado_em: string }
  | {
      id: string;
      pedido_id: string;
      tipo: 'entregue_pago';
      caixa: string;
      parcelas: { metodo: string; valor: number }[];
      criado_em: string;
    };

// Omit distributivo: preserva cada variante da união (senão perde caixa/parcelas do entregue_pago).
type SemMeta<T> = T extends unknown ? Omit<T, 'id' | 'criado_em'> : never;

function novoId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

export async function lerFila(): Promise<AccaoFila[]> {
  try {
    const s = await AsyncStorage.getItem(CHAVE);
    return s ? (JSON.parse(s) as AccaoFila[]) : [];
  } catch {
    return [];
  }
}

async function guardarFila(lista: AccaoFila[]): Promise<void> {
  try {
    await AsyncStorage.setItem(CHAVE, JSON.stringify(lista));
  } catch {
    // sem storage: ignora
  }
}

/** Acrescenta uma acção à fila (gera id e data). Devolve a fila atualizada. */
export async function enfileirar(a: SemMeta<AccaoFila>): Promise<AccaoFila[]> {
  const fila = await lerFila();
  const nova = [...fila, { ...a, id: novoId(), criado_em: new Date().toISOString() } as AccaoFila];
  await guardarFila(nova);
  return nova;
}

export async function removerDaFila(id: string): Promise<AccaoFila[]> {
  const fila = (await lerFila()).filter((x) => x.id !== id);
  await guardarFila(fila);
  return fila;
}

/** Conjunto de pedidos com acção pendente, para a UI marcar "a enviar" e não repetir. */
export async function pedidosNaFila(): Promise<Set<string>> {
  return new Set((await lerFila()).map((x) => x.pedido_id));
}
