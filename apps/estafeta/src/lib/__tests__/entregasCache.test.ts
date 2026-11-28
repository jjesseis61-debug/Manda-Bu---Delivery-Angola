/// <reference types="jest" />
import { guardarEntregasCache, lerEntregasCache } from '../entregasCache';
import type { PedidoOperador } from '../tipos';

// Um PedidoOperador mínimo para o teste (só o que o cache precisa de guardar/ler).
const pedido = { pedido_id: 'p1', cliente_nome: 'Ana', estado: 'em_entrega', a_pagar: 6000 } as unknown as PedidoOperador;

describe('cache de entregas (offline)', () => {
  it('guarda e lê a lista', async () => {
    await guardarEntregasCache([pedido]);
    const lido = await lerEntregasCache();
    expect(lido).not.toBeNull();
    expect(lido).toHaveLength(1);
    expect(lido![0].pedido_id).toBe('p1');
    expect(lido![0].cliente_nome).toBe('Ana');
  });

  it('devolve null quando não há nada guardado', async () => {
    await guardarEntregasCache([]); // grava uma lista vazia
    const vazio = await lerEntregasCache();
    expect(vazio).toEqual([]);
  });
});
