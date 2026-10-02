/// <reference types="jest" />
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);

// Servidor simulado: guarda os pedidos por id e recusa um id repetido como o Postgres (23505)
const mockGravados = new Map<string, unknown>();
jest.mock('../supabase', () => ({
  supabase: {
    from: () => ({
      insert: async (linha: { id: string }) =>
        mockGravados.has(linha.id)
          ? { data: null, error: { code: '23505', message: 'duplicate key value violates unique constraint "pedidos_pkey"' } }
          : (mockGravados.set(linha.id, linha), { data: null, error: null }),
      select: () => ({
        eq: (_c: string, id: string) => ({
          maybeSingle: async () => ({ data: mockGravados.has(id) ? { id } : null, error: null }),
        }),
      }),
    }),
  },
}));

import { criarPedido } from '../api';
import { novoId } from '../dispositivo';

const pedido = (id: string) => ({
  id,
  clienteId: 'c1',
  pontoEntregaId: 'p1',
  itens: [{ cardapio_id: 'm1', qtd: 1 }],
  observacoes: '',
});

beforeEach(() => mockGravados.clear());

test('retentar com o mesmo id não cria um segundo pedido', async () => {
  const id = novoId();
  await expect(criarPedido(pedido(id))).resolves.toBe(id);
  // a resposta perdeu-se e o cliente tocou outra vez em "Confirmar pedido"
  await expect(criarPedido(pedido(id))).resolves.toBe(id);
  expect(mockGravados.size).toBe(1);
});

test('ids gerados no telemóvel são UUID v4 diferentes', () => {
  const a = novoId();
  expect(a).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  expect(novoId()).not.toBe(a);
});
