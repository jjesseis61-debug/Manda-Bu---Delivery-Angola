/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import MontarPrato from '@/app/montar/[id]';

const mockAdicionar = jest.fn();
const mockBaseEsgotada = { valor: false };
const mockComponentes: { valor: unknown[] } = { valor: [] };
const mockDoses: { valor: unknown[] } = { valor: [] };
jest.mock('@/lib/sessao', () => ({ useSessao: () => ({ carregado: true, ligada: () => true }) }));
const mockAvancarFila = jest.fn(() => null);
const mockRepeticao: { valor: unknown } = { valor: null };
jest.mock('@/lib/carrinho', () => ({
  useCarrinho: () => ({ adicionar: mockAdicionar, repeticao: mockRepeticao.valor, avancarFila: mockAvancarFila, definirRepeticao: jest.fn() }),
}));
jest.mock('@/lib/api', () => ({
  lerItemCardapio: async () => ({
    id: 'm', nome: 'Muamba', descricao: null, categoria: null, preco: 2500, foto_url: null, do_dia: false, cozinha_id: 'k', prato_base_id: null,
  }),
  lerComponentes: async () => mockComponentes.valor,
  lerDoses: async () => mockDoses.valor,
  lerOpcoes: async () => [
    { id: 'g1', cardapio_id: 'm', nome: 'Base', minimo: 1, maximo: 1, ordem: 1,
      opcoes: mockBaseEsgotada.valor ? [] : [{ id: 'funge', nome: 'Funge', preco_extra: 0, ordem: 1 }, { id: 'arroz', nome: 'Arroz', preco_extra: 0, ordem: 2 }] },
    { id: 'g2', cardapio_id: 'm', nome: 'Extras', minimo: 0, maximo: 2, ordem: 2,
      opcoes: [{ id: 'ovo', nome: 'Ovo', preco_extra: 200, ordem: 1 }] },
  ],
}));

test('só adiciona com a base escolhida, com o preço dos extras', async () => {
  const ecra = renderRouter({ 'montar/[id]': MontarPrato, inicio: () => <Text>Início</Text> }, { initialUrl: '/montar/m' });
  await act(async () => undefined);
  expect(ecra.getByText('Falta escolher: Base.')).toBeTruthy();
  fireEvent.press(ecra.getByText('Adicionar · 2.500 Kz'));
  expect(mockAdicionar).not.toHaveBeenCalled();

  fireEvent.press(ecra.getByText('Funge'));
  fireEvent.press(ecra.getByText('Ovo'));
  fireEvent.press(ecra.getByText('Adicionar · 2.700 Kz'));
  expect(mockAdicionar).toHaveBeenCalledWith(
    expect.objectContaining({ id: 'm' }),
    [{ id: 'funge', nome: 'Funge', preco_extra: 0 }, { id: 'ovo', nome: 'Ovo', preco_extra: 200 }],
    [],
  );
});

test('base toda esgotada: o prato aparece esgotado e não se adiciona', async () => {
  mockBaseEsgotada.valor = true;
  mockAdicionar.mockClear();
  const ecra = renderRouter({ 'montar/[id]': MontarPrato, inicio: () => <Text>Início</Text> }, { initialUrl: '/montar/m' });
  await act(async () => undefined);
  expect(ecra.getByText('Esgotado de momento: não há nenhuma opção disponível em Base.')).toBeTruthy();
  fireEvent.press(ecra.getByText('Esgotado'));
  expect(mockAdicionar).not.toHaveBeenCalled();
  mockBaseEsgotada.valor = false;
});

test('tirar ingredientes: o preço desce pelo valor de cada um e fica sempre pelo menos um', async () => {
  mockAdicionar.mockClear();
  mockComponentes.valor = [
    { cardapio_id: 'm', produto_id: 'frango', nome: 'Frango', quantidade: 250, unidade: 'g', valor: 1026 },
    { cardapio_id: 'm', produto_id: 'cebola', nome: 'Cebola', quantidade: 50, unidade: 'g', valor: 25 },
  ];
  const ecra = renderRouter({ 'montar/[id]': MontarPrato, inicio: () => <Text>Início</Text> }, { initialUrl: '/montar/m' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Funge'));
  fireEvent.press(ecra.getByLabelText('Tirar Cebola'));
  expect(ecra.getByText('Adicionar · 2.475 Kz')).toBeTruthy();
  // Com a cebola tirada, o frango (o último) já não se pode tirar
  expect(ecra.getByLabelText('Tirar Frango').props.accessibilityState).toEqual(expect.objectContaining({ disabled: true }));
  fireEvent.press(ecra.getByText('Adicionar · 2.475 Kz'));
  expect(mockAdicionar).toHaveBeenCalledWith(
    expect.objectContaining({ id: 'm' }),
    [{ id: 'funge', nome: 'Funge', preco_extra: 0 }],
    [expect.objectContaining({ produto_id: 'cebola', valor: 25 })],
  );
  mockComponentes.valor = [];
});

test('acabaram as doses de hoje: o prato aparece esgotado', async () => {
  mockAdicionar.mockClear();
  mockDoses.valor = [{ cardapio_id: 'm', restantes: 0 }];
  const ecra = renderRouter({ 'montar/[id]': MontarPrato, inicio: () => <Text>Início</Text> }, { initialUrl: '/montar/m' });
  await act(async () => undefined);
  expect(ecra.getByText('Esgotado: acabaram as doses de hoje.')).toBeTruthy();
  fireEvent.press(ecra.getByText('Funge'));
  fireEvent.press(ecra.getByText('Esgotado'));
  expect(mockAdicionar).not.toHaveBeenCalled();
  mockDoses.valor = [];
});

describe('"Pedir de novo" de um prato que mudou', () => {
  const rotas = { 'montar/[id]': MontarPrato, inicio: () => <Text>Início</Text>, carrinho: () => <Text>Carrinho</Text> };
  beforeEach(() => {
    mockAdicionar.mockClear();
    mockAvancarFila.mockClear();
    // Pediu Funge + Bacon (2 pratos); o Bacon já não existe
    mockRepeticao.valor = {
      fila: [{ itemId: 'm', nome: 'Muamba', qtd: 2, escolhidas: ['funge'], tirados: [], faltaram: ['Bacon'] }],
      faltam: [],
    };
  });
  afterEach(() => {
    mockRepeticao.valor = null;
  });

  test('volta com o que ainda há, avisa o que faltou e só avança quando o cliente decide', async () => {
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m?rever=1' });
    await act(async () => undefined);
    expect(ecra.getByText('Do teu pedido anterior já não temos: Bacon. Escolhe outra opção ou continua sem ela.')).toBeTruthy();
    expect(mockAdicionar).not.toHaveBeenCalled();
    fireEvent.press(ecra.getByText('Adicionar 2× · 5.000 Kz'));
    expect(mockAdicionar).toHaveBeenCalledWith(expect.objectContaining({ id: 'm' }), [{ id: 'funge', nome: 'Funge', preco_extra: 0 }], [], 2);
    expect(mockAvancarFila).toHaveBeenCalled();
    await act(async () => undefined);
    expect(ecra.getByText('Carrinho')).toBeTruthy();
  });

  test('pode tirar o prato do pedido em vez de o servir', async () => {
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m?rever=1' });
    await act(async () => undefined);
    fireEvent.press(ecra.getByText('Tirar este prato do pedido'));
    expect(mockAdicionar).not.toHaveBeenCalled();
    expect(mockAvancarFila).toHaveBeenCalled();
  });

  test('aberto normalmente (sem rever), ignora a fila e começa vazio', async () => {
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    expect(ecra.queryByText(/Do teu pedido anterior/)).toBeNull();
    expect(ecra.getByText('Falta escolher: Base.')).toBeTruthy();
  });
});
