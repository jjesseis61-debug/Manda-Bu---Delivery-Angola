import { mudarEstado } from './api';
import { lerFila, removerDaFila } from './filaOffline';

/** Erro de rede (o fetch falhou antes de chegar ao servidor): a acção fica na fila para repetir. */
export function semRede(e: unknown): boolean {
  const o = e as { name?: string; message?: string; status?: number } | null | undefined;
  const msg = (o?.message ?? '').toLowerCase();
  return (
    o?.name === 'AuthRetryableFetchError' ||
    o?.name === 'TypeError' ||
    o?.status === 0 ||
    /network request failed|failed to fetch|fetch failed|network error|timeout|rede/.test(msg)
  );
}

export type ResultadoSync = { feitas: number; pendentes: number; falhadas: number };

/**
 * Reproduz a fila offline por ordem. Pára no 1.º erro de rede (tenta de novo mais tarde); um erro
 * do servidor (ex.: o estado já tinha mudado) descarta a acção para não bloquear a fila.
 */
export async function sincronizar(): Promise<ResultadoSync> {
  let feitas = 0;
  let falhadas = 0;
  const fila = await lerFila();
  for (const a of fila) {
    try {
      if (a.tipo === 'em_entrega') await mudarEstado(a.pedido_id, 'em_entrega');
      else await mudarEstado(a.pedido_id, 'entregue_pago', { caixa: a.caixa, parcelas: a.parcelas });
      await removerDaFila(a.id);
      feitas++;
    } catch (e) {
      if (semRede(e)) break; // sem rede: pára e tenta na próxima sincronização
      await removerDaFila(a.id); // erro do servidor: descarta para não bloquear a fila
      falhadas++;
    }
  }
  const pendentes = (await lerFila()).length;
  return { feitas, pendentes, falhadas };
}
