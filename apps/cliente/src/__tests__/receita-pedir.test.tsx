/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import ReceitaDetalhe from '@/app/receita/[id]';

const mockSessao = { carregado: true, perfil: { cliente_id: 'c1' }, ligada: (c: string) => c === 'receitas' };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
jest.mock('@/lib/carrinho', () => ({ useCarrinho: () => ({ cozinhaActual: { id: 'kil', nome: 'Kilamba' }, quantidade: 0, grupo: null }) }));
const mockOnde = jest.fn();
const mockQuero = jest.fn(async (..._a: unknown[]) => 3);
const mockToque = jest.fn(async (..._a: unknown[]) => undefined);
jest.mock('@/lib/api', () => ({
  lerReceita: async () => ({ id: 'r1', titulo: 'Mufete de peixe', resumo: null, corpo: 'Ingredientes…', foto_url: null, cozinha_id: 'via', cozinha_nome: 'Viana' }),
  lerEnderecos: async () => [{ ponto_entrega_id: 'p1' }],
  receitaAbriu: async () => undefined,
  receitaOndePedir: (...a: unknown[]) => mockOnde(...a),
  receitaQuero: (...a: unknown[]) => mockQuero(...a),
  receitaTocouPedir: (...a: unknown[]) => mockToque(...a),
}));

const abrir = () =>
  renderRouter({ 'receita/[id]': ReceitaDetalhe, 'montar/[id]': () => <Text>Ecrã do prato</Text> }, { initialUrl: '/receita/r1' });

beforeEach(() => {
  mockOnde.mockReset();
  mockQuero.mockClear();
  mockToque.mockClear();
});

test('o balcão escolhido faz o prato: pede-se aí e abre o prato', async () => {
  mockOnde.mockResolvedValue({ estado: 'aqui', cozinha_id: 'kil', cozinha_nome: 'Kilamba', cardapio_id: 'm1', prato_nome: 'Mufete', preco: 4500, distancia_km: 0.8, quero: false });
  const ecra = abrir();
  await act(async () => undefined);
  expect(mockOnde).toHaveBeenCalledWith('r1', 'kil', 'p1');
  expect(ecra.queryByText(/Viana faz por ti/)).toBeNull();
  fireEvent.press(ecra.getByText('Não queres cozinhar? Pede Mufete em Kilamba · 4.500 Kz'));
  await act(async () => undefined);
  expect(mockToque).toHaveBeenCalledWith('r1');
  expect(ecra.getByText('Ecrã do prato')).toBeTruthy();
});

test('outro balcão faz o prato: diz qual e a que distância', async () => {
  mockOnde.mockResolvedValue({ estado: 'perto', cozinha_id: 'via', cozinha_nome: 'Viana', cardapio_id: 'm2', prato_nome: 'Mufete', preco: 4500, distancia_km: 12.3, quero: false });
  const ecra = abrir();
  await act(async () => undefined);
  expect(ecra.getByText('Kilamba não faz Mufete de peixe. Viana faz Mufete (a 12,3 km).')).toBeTruthy();
  expect(ecra.getByText('Pedir em Viana · 4.500 Kz')).toBeTruthy();
});

test('ninguém faz: não promete e regista «quero que façam»', async () => {
  mockOnde.mockResolvedValue({ estado: 'ninguem', quero: false, interessados: 2 });
  const ecra = abrir();
  await act(async () => undefined);
  expect(ecra.getByText('Ainda ninguém faz Mufete de peixe perto de ti.')).toBeTruthy();
  expect(ecra.queryByText(/Pedir/)).toBeNull();
  await act(async () => {
    fireEvent.press(ecra.getByText('Quero que façam'));
  });
  expect(mockQuero).toHaveBeenCalledWith('r1');
  expect(ecra.getByText('✓ Registado: já são 3 a pedir. Mostramos às cozinhas o que os clientes querem.')).toBeTruthy();
});
