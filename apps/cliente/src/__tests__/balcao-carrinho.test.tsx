/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';

import Inicio from '@/app/(tabs)/inicio';
import { balcaoLonge, pratoDoErro, textoQuandoVolta } from '@/lib/balcao';

jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('@expo/vector-icons/Ionicons', () => () => null);
jest.mock('expo-location', () => ({}));
const mockSessao = {
  carregado: true, sessao: {}, perfil: { cliente_id: 'c1', primeiro_nome: 'Jacob' }, parametros: null,
  ligada: (c: string) => c === 'multi_cozinha',
};
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));
const mockRpc = jest.fn();
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: (...a: unknown[]) => mockRpc(...a) } }));
jest.mock('@/lib/partilha', () => ({ partilharPrato: jest.fn(), convitePartilhaDe: () => null }));
jest.mock('@/lib/pedirDeNovo', () => ({ usePedirDeNovo: () => jest.fn() }));
jest.mock('@/components/ComoChegar', () => ({ ComoChegar: () => null }));
jest.mock('@/components/CartaoConvida', () => ({ CartaoConvida: () => null }));
jest.mock('@/components/FaixaConfianca', () => ({ FaixaConfianca: () => null }));
jest.mock('@/lib/condominio', () => ({
  cozinhasComCondominio: (_c: unknown, l: unknown) => l,
  precosParaMim: async () => null,
  promocoesParaMim: async () => [],
}));
const coz = (id: string, nome: string, km: number) => ({ cozinha_id: id, nome, publica: false, foto_url: null, historia: null, pratos: 3, distancia_km: km });
jest.mock('@/lib/api', () => ({
  lerEnderecos: async () => [{ ponto_entrega_id: 'p1', nome: 'Casa', pontos_entrega: { tipo: 'residencial', zona_id: 'z', zonas: { nome: 'Maianga' } } }],
  cozinhasPertoParaPedir: async () => [coz('mai', 'Maianga', 1.2), coz('via', 'Viana', 18.3)],
  lerCardapio: async () => [
    { id: 'st', nome: 'Strogonoff', preco: 3000, descricao: null, categoria: null, foto_url: null, do_dia: false, cozinha_id: 'via', prato_base_id: null, pedidos_mes: 0 },
  ],
  lerDoses: async () => [],
  lerPedidos: async () => [],
  maisPedidosNaZona: async () => [],
}));
const mockDefinirCozinha = jest.fn();
jest.mock('@/lib/carrinho', () => ({
  useCarrinho: () => ({
    linhas: [], quantidade: 0, totalEstimado: 0, cozinhaActual: { id: 'via', nome: 'Viana' }, grupo: null,
    adicionar: jest.fn(), definirCozinha: mockDefinirCozinha, quantidadeDe: () => 0,
  }),
}));

test('balcão longe: só avisa quando o escolhido fica bem mais longe do que o mais perto', () => {
  const lista = [coz('mai', 'Maianga', 1.2), coz('via', 'Viana', 18.3), coz('kil', 'Kilamba', 4)];
  expect(balcaoLonge(lista, 'via')?.perto.nome).toBe('Maianga');
  expect(balcaoLonge(lista, 'kil')).toBeNull(); // 2,8 km a mais: não vale o aviso
  expect(balcaoLonge(lista, 'mai')).toBeNull();
  expect(balcaoLonge([coz('a', 'A', 1), { ...coz('b', 'B', 0), distancia_km: null }], 'b')).toBeNull();
});

test('quando volta: hoje, amanhã ou o dia da semana (hora de Luanda)', () => {
  const agora = new Date('2026-11-23T08:00:00Z'); // segunda, 9h00 em Luanda
  expect(textoQuandoVolta('2026-11-23T11:00:00Z', agora)).toBe('hoje às 12h00');
  expect(textoQuandoVolta('2026-11-24T11:00:00Z', agora)).toBe('amanhã às 12h00');
  expect(textoQuandoVolta('2026-11-24T21:29:00Z', agora)).toBe('amanhã às 22h29');
  expect(textoQuandoVolta('2026-11-27T11:00:00Z', agora)).toBe('sex 27/11 às 12h00');
});

test('erro do servidor: identifica o prato recusado', () => {
  const id = '9fafb454-268d-4d4e-bda8-7141f753a881';
  expect(pratoDoErro({ message: 'item_indisponivel', details: id })).toBe(id);
  expect(pratoDoErro({ message: 'item_indisponivel', details: null })).toBeNull();
  expect(pratoDoErro({ message: 'outro', details: id })).toBeNull();
});

test('Início: avisa que Viana fica longe da morada, propõe o mais perto, e mostra o que volta mais tarde', async () => {
  mockRpc.mockImplementation(async (nome: string) =>
    nome === 'cardapio_mais_tarde'
      ? { data: [{ cardapio_id: 'cf', nome: 'Choco frito', preco: 9000, foto_url: null, categoria: null, proxima: '2099-11-24T21:29:00Z' }], error: null }
      : { data: null, error: null },
  );
  const ecra = renderRouter({ inicio: Inicio }, { initialUrl: '/inicio' });
  await act(async () => undefined);
  expect(ecra.getByText('📍 Viana fica a 18,3 km de Casa · Maianga.')).toBeTruthy();
  expect(ecra.getByText('Maianga fica a 1,2 km: a comida chega mais depressa.')).toBeTruthy();
  fireEvent.press(ecra.getByText('Pedir em Maianga'));
  expect(mockDefinirCozinha).toHaveBeenCalledWith({ id: 'mai', nome: 'Maianga' });
  expect(ecra.getByText('Mais tarde')).toBeTruthy();
  expect(ecra.getByText('Choco frito')).toBeTruthy();
  expect(ecra.getByText(/À venda .* às 22h29/)).toBeTruthy();
});

test('Início: «Ficar em Viana» esconde o aviso', async () => {
  mockRpc.mockResolvedValue({ data: null, error: null });
  const ecra = renderRouter({ inicio: Inicio }, { initialUrl: '/inicio' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Ficar em Viana'));
  expect(ecra.queryByText(/Viana fica a/)).toBeNull();
});
