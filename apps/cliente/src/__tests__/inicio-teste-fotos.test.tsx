/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { StyleSheet } from 'react-native';

import Inicio from '@/app/(tabs)/inicio';

jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('@expo/vector-icons/Ionicons', () => () => null);
const mockLigadas = { teste: true };
const mockSessao = {
  carregado: true, sessao: {}, perfil: { cliente_id: 'c1', primeiro_nome: 'Jacob' }, parametros: null,
  ligada: (c: string) => c === 'teste_fotos_inicio' && mockLigadas.teste,
};
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
jest.mock('@/lib/partilha', () => ({ partilharPrato: jest.fn(), convitePartilhaDe: () => null }));
jest.mock('@/lib/pedirDeNovo', () => ({ usePedirDeNovo: () => jest.fn() }));
jest.mock('@/components/ComoChegar', () => ({ ComoChegar: () => null }));
jest.mock('@/components/CartaoConvida', () => ({ CartaoConvida: () => null }));
jest.mock('@/components/FaixaConfianca', () => ({ FaixaConfianca: () => null }));
jest.mock('@/lib/condominio', () => ({}));

const prato = (id: string, nome: string, preco: number) => ({
  id, nome, preco, descricao: null, categoria: null, foto_url: `https://x/${id}.jpg`, do_dia: false, cozinha_id: 'k1',
  prato_base_id: null, pedidos_mes: 0,
});
const mockVisita = jest.fn();
const mockGrupo: { valor: 'A' | 'B' | null } = { valor: 'A' };
jest.mock('@/lib/api', () => ({
  cozinhaPadrao: async () => 'k1',
  lerEnderecos: async () => [],
  lerCardapio: async () => [prato('m', 'Muamba', 2500), prato('s', 'Strogonoff', 3000)],
  lerDoses: async () => [],
  lerPedidos: async () => [{ id: 'p1', estado: 'entregue_pago', itens: [{ qtd: 1, nome: 'Muamba' }] }],
  maisPedidosNaZona: async () => [],
  visitaExperiencia: (...a: unknown[]) => mockVisita(...a),
}));
const mockAdicionar = jest.fn();
jest.mock('@/lib/carrinho', () => ({
  useCarrinho: () => ({
    linhas: [], quantidade: 0, totalEstimado: 0, cozinhaActual: { id: 'k1', nome: 'Viana' }, grupo: null,
    adicionar: mockAdicionar, definirCozinha: jest.fn(), quantidadeDe: () => 0,
  }),
}));

beforeEach(() => {
  mockVisita.mockReset();
  mockVisita.mockImplementation(async () => mockGrupo.valor);
  mockAdicionar.mockClear();
});

const largura = (ecra: ReturnType<typeof renderRouter>, nome: string) => StyleSheet.flatten(ecra.getByLabelText(nome).props.style).width;

test('grupo A: fotografia grande; o primeiro «Adicionar» guarda o tempo uma só vez', async () => {
  mockLigadas.teste = true;
  mockGrupo.valor = 'A';
  const ecra = renderRouter({ inicio: Inicio }, { initialUrl: '/inicio' });
  await act(async () => undefined);
  expect(mockVisita).toHaveBeenCalledWith('fotos_inicio');
  expect(largura(ecra, 'Muamba')).toBe('100%');
  fireEvent.press(ecra.getAllByText('Adicionar')[0]);
  fireEvent.press(ecra.getAllByText('Adicionar')[1]);
  expect(mockAdicionar).toHaveBeenCalledTimes(2);
  const comTempo = mockVisita.mock.calls.filter((c) => c.length === 2);
  expect(comTempo).toHaveLength(1);
  expect(comTempo[0][0]).toBe('fotos_inicio');
  expect(typeof comTempo[0][1]).toBe('number');
});

test('grupo B: fotografia média ao lado do nome, e o habitual numa linha', async () => {
  mockLigadas.teste = true;
  mockGrupo.valor = 'B';
  const ecra = renderRouter({ inicio: Inicio }, { initialUrl: '/inicio' });
  await act(async () => undefined);
  expect(largura(ecra, 'Muamba')).toBe(112);
  expect(ecra.getByText('↺ O teu habitual')).toBeTruthy();
  expect(ecra.getByText('Pedir de novo')).toBeTruthy();
});

test('teste desligado: não regista nada e mostra a fotografia média', async () => {
  mockLigadas.teste = false;
  const ecra = renderRouter({ inicio: Inicio }, { initialUrl: '/inicio' });
  await act(async () => undefined);
  expect(mockVisita).not.toHaveBeenCalled();
  expect(largura(ecra, 'Muamba')).toBe(112);
  fireEvent.press(ecra.getAllByText('Adicionar')[0]);
  expect(mockVisita).not.toHaveBeenCalled();
});
