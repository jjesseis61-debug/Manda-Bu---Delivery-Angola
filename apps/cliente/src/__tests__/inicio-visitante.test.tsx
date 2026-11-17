/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import Inicio from '@/app/(tabs)/inicio';
import Carrinho from '@/app/carrinho';
import Pedidos from '@/app/(tabs)/pedidos';

jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('@expo/vector-icons/Ionicons', () => () => null);
// Estável entre renders (como na app): o carregamento do Início depende de `ligada`
const mockSessaoVisitante = { carregado: true, actualizar: async () => undefined, sessao: null, perfil: null, parametros: null, ligada: (c: string) => c === 'multi_cozinha' || c === 'pacotes' };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessaoVisitante }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
jest.mock('@/lib/api', () => ({}));
jest.mock('@/lib/condominio', () => ({}));
jest.mock('@/lib/pedirDeNovo', () => ({ usePedirDeNovo: () => jest.fn() }));
jest.mock('@/lib/partilha', () => ({ partilharPrato: jest.fn(), convitePartilhaDe: () => null }));
jest.mock('@/components/ComoChegar', () => ({ ComoChegar: () => null }));
jest.mock('@/components/CartaoConvida', () => ({ CartaoConvida: () => null }));

const prato = (id: string, nome: string, preco: number, extra: object = {}) => ({
  id, nome, preco, descricao: null, categoria: null, foto_url: null, do_dia: false, cozinha_id: 'k1', prato_base_id: null, pedidos_mes: 0,
  esgotado: false, montar: false, ...extra,
});
const mockCozinhas = jest.fn();
const mockGuardarZona = jest.fn(async (..._a: unknown[]) => undefined);
const mockZona: { valor: unknown } = { valor: null };
const mockGuardarDestino = jest.fn(async (..._a: unknown[]) => undefined);
jest.mock('@/lib/visitante', () => ({
  ...jest.requireActual('@/lib/visitante'),
  guardarDestino: (...a: unknown[]) => mockGuardarDestino(...a),
  lerZonasVisitante: async () => [{ id: 'z1', nome: 'Maianga', taxa: 1000, entrega_gratis_acima: null }],
  lerZonaVisitante: async () => mockZona.valor,
  guardarZonaVisitante: (...a: unknown[]) => mockGuardarZona(...a),
  lerCozinhasVisitante: (...a: unknown[]) => mockCozinhas(...a),
  lerCardapioVisitante: async () => ({
    cozinha: { id: 'k1', nome: 'Viana' },
    pratos: [prato('m', 'Muamba', 2500), prato('s', 'Strogonoff', 3000), prato('c', 'Calulu', 3000, { categoria: 'Peixe', montar: false, desde: 3500 })],
  }),
}));
const mockAdicionar = jest.fn();
const mockCarrinho: { linhas: unknown[]; cozinha: unknown } = { linhas: [], cozinha: null };
jest.mock('@/lib/carrinho', () => ({
  useCarrinho: () => ({
    linhas: mockCarrinho.linhas, quantidade: mockCarrinho.linhas.length, totalEstimado: 2500, cozinhaActual: mockCarrinho.cozinha, grupo: null,
    adicionar: mockAdicionar, definirCozinha: jest.fn(), alterar: jest.fn(), quantidadeDe: () => 0,
  }),
}));

beforeEach(() => {
  mockCozinhas.mockResolvedValue([
    { id: 'k1', nome: 'Viana', pratos: 7, distancia_km: null, foto_url: null },
    { id: 'k2', nome: 'Rangel', pratos: 4, distancia_km: null, foto_url: null },
  ]);
  mockZona.valor = null;
  mockCarrinho.linhas = [];
  mockAdicionar.mockClear();
});

test('sem conta, o Início abre com o cardápio e as cozinhas, sem pedir o número', async () => {
  const ecra = renderRouter({ inicio: Inicio }, { initialUrl: '/inicio' });
  await act(async () => undefined);
  expect(ecra.getByText('Muamba')).toBeTruthy();
  expect(ecra.getByText('📍 De onde queres pedir?')).toBeTruthy();
  expect(ecra.queryByText(/adiciona o endereço/)).toBeNull();
  expect(ecra.getByText('desde 3.500 Kz')).toBeTruthy(); // como no Início com conta
  fireEvent.press(ecra.getAllByText('Adicionar')[0]);
  expect(mockAdicionar).toHaveBeenCalledWith(expect.objectContaining({ id: 'm' }));
});

test('igual ao Início com conta: sem a pergunta do bairro; pacote pede para entrar', async () => {
  const ecra = renderRouter({ inicio: Inicio, entrar: () => <Text>Entrar</Text> }, { initialUrl: '/inicio' });
  await act(async () => undefined);
  expect(ecra.queryByText('🛵 Onde entregamos?')).toBeNull();
  fireEvent.press(ecra.getByText('Pacote do mês: paga uma vez, almoça o mês todo'));
  expect(ecra.getByText('Entra na tua conta')).toBeTruthy();
  expect(ecra.getByText('Entra para comprares o pacote do mês.')).toBeTruthy();
  expect(ecra.getByText('Receber código')).toBeTruthy();
});

test('carrinho do visitante: escolhe o bairro e vê a entrega', async () => {
  mockCarrinho.linhas = [{ chave: 'm', item: prato('m', 'Muamba', 2500), qtd: 2, opcoes: [], tirados: [] }];
  const ecra = renderRouter({ carrinho: Carrinho }, { initialUrl: '/carrinho' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Maianga · entrega 1.000 Kz'));
  expect(mockGuardarZona).toHaveBeenCalledWith(expect.objectContaining({ id: 'z1' }));
  expect(ecra.getByText('Total estimado: 6.000 Kz')).toBeTruthy();
});

test('carrinho do visitante: «Pedir» pede o número só aí', async () => {
  mockCarrinho.linhas = [{ chave: 'm', item: prato('m', 'Muamba', 2500), qtd: 1, opcoes: [], tirados: [] }];
  const ecra = renderRouter({ carrinho: Carrinho, entrar: () => <Text>Entrar</Text> }, { initialUrl: '/carrinho' });
  await act(async () => undefined);
  expect(ecra.getByText('Total dos pratos: 2.500 Kz')).toBeTruthy();
  fireEvent.press(ecra.getByText('Pedir · 2.500 Kz'));
  expect(ecra.getByText('Só falta o teu número')).toBeTruthy();
  expect(ecra.getByText('Recebes um código por SMS ou WhatsApp para confirmar. O teu carrinho fica guardado.')).toBeTruthy();
  expect(ecra.getByText('Só usamos o teu número para os teus pedidos. Pagas na entrega.')).toBeTruthy();
  expect(ecra.getByText('Receber código')).toBeTruthy();
});

test('Pedidos sem conta: convite a entrar', async () => {
  const ecra = renderRouter({ pedidos: Pedidos }, { initialUrl: '/pedidos' });
  await act(async () => undefined);
  expect(ecra.getByText('Os teus pedidos')).toBeTruthy();
  expect(ecra.getByText('Entrar ou criar conta')).toBeTruthy();
});
