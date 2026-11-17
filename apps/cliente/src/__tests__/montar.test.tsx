/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import MontarPrato from '@/app/montar/[id]';

const mockAdicionar = jest.fn();
const mockBaseEsgotada = { valor: false };
const mockComponentes: { valor: unknown[] } = { valor: [] };
const mockDoses: { valor: unknown[] } = { valor: [] };
const mockSessao = { visitante: false };
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({
    carregado: true,
    ligada: (c: string) => !mockSessao.visitante || c === 'nenhum',
    sessao: mockSessao.visitante ? null : {},
    perfil: mockSessao.visitante ? null : { cliente_id: 'c' },
  }),
}));
jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('@/lib/convite', () => ({ lerCodigoPendente: async () => 'MB-1234' }));
const mockLerPratoVisitante = jest.fn();
jest.mock('@/lib/visitante', () => ({
  ...jest.requireActual('@/lib/visitante'),
  lerPratoVisitante: (...a: unknown[]) => mockLerPratoVisitante(...a),
}));
const mockAvancarFila = jest.fn(() => null);
const mockRepeticao: { valor: unknown } = { valor: null };
const mockDefinirCozinha = jest.fn();
const mockCarrinho = { cozinha: { id: 'k', nome: 'Maianga' } as { id: string; nome: string } | null, quantidade: 0 };
jest.mock('@/lib/carrinho', () => ({
  useCarrinho: () => ({
    adicionar: mockAdicionar, repeticao: mockRepeticao.valor, avancarFila: mockAvancarFila, definirRepeticao: jest.fn(),
    cozinhaActual: mockCarrinho.cozinha, quantidade: mockCarrinho.quantidade, grupo: null, definirCozinha: mockDefinirCozinha,
  }),
}));
jest.mock('@/lib/condominio', () => ({ posicaoParaCondominio: async () => null, condominioAqui: async () => null }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
const mockItem = { cozinha: 'k', semOpcoes: false };
const mockCozinhas: { valor: { cozinha_id: string; nome: string }[] } = { valor: [{ cozinha_id: 'k', nome: 'Maianga' }, { cozinha_id: 'v', nome: 'Viana' }] };
jest.mock('@/lib/api', () => ({
  cozinhasParaPedir: async () => mockCozinhas.valor,
  cozinhaPadrao: async () => 'k',
  lerItemCardapio: async () => ({
    id: 'm', nome: 'Muamba ', descricao: null, categoria: null, preco: 2500, foto_url: null, do_dia: false, cozinha_id: mockItem.cozinha, prato_base_id: null,
  }),
  lerComponentes: async () => mockComponentes.valor,
  lerDoses: async () => mockDoses.valor,
  lerOpcoes: async () => mockItem.semOpcoes ? [] : [
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

describe('prato aberto por link', () => {
  const rotas = { 'montar/[id]': MontarPrato, inicio: () => <Text>Início</Text> };
  beforeEach(() => {
    mockAdicionar.mockClear();
    mockDefinirCozinha.mockClear();
    mockItem.semOpcoes = true;
  });
  afterEach(() => {
    mockItem.semOpcoes = false;
    mockItem.cozinha = 'k';
    mockCarrinho.cozinha = { id: 'k', nome: 'Maianga' };
    mockCarrinho.quantidade = 0;
  });

  test('prato sem opções: página simples com "Adicionar ao carrinho" (nome sem espaços)', async () => {
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    expect(ecra.getByText('Muamba')).toBeTruthy();
    expect(ecra.queryByText(/Escolhe à esquerda/)).toBeNull();
    fireEvent.press(ecra.getByText('Adicionar ao carrinho · 2.500 Kz'));
    expect(mockAdicionar).toHaveBeenCalledWith(expect.objectContaining({ id: 'm' }), [], []);
    expect(mockDefinirCozinha).not.toHaveBeenCalled();
  });

  test('de outra cozinha com o carrinho vazio: muda de cozinha e adiciona', async () => {
    mockItem.cozinha = 'v';
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    fireEvent.press(ecra.getByText('Adicionar ao carrinho · 2.500 Kz'));
    expect(mockDefinirCozinha).toHaveBeenCalledWith({ id: 'v', nome: 'Viana' });
    expect(mockAdicionar).toHaveBeenCalled();
  });

  test('de outra cozinha com pratos no carrinho: pergunta antes de trocar', async () => {
    mockItem.cozinha = 'v';
    mockCarrinho.quantidade = 2;
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    fireEvent.press(ecra.getByText('Adicionar ao carrinho · 2.500 Kz'));
    expect(mockAdicionar).not.toHaveBeenCalled();
    expect(ecra.getByText('Trocar de cozinha?')).toBeTruthy();
    fireEvent.press(ecra.getByText('Trocar e adicionar'));
    expect(mockDefinirCozinha).toHaveBeenCalledWith({ id: 'v', nome: 'Viana' });
    expect(mockAdicionar).toHaveBeenCalled();
  });

  test('cozinha indisponível (fechada ou de condomínio): não adiciona e explica', async () => {
    mockItem.cozinha = 'cond';
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    fireEvent.press(ecra.getByText('Adicionar ao carrinho · 2.500 Kz'));
    expect(mockAdicionar).not.toHaveBeenCalled();
    expect(ecra.getByText(/só para os moradores de um condomínio/)).toBeTruthy();
  });
});

describe('visitante (sem conta) pelo link', () => {
  const rotas = { 'montar/[id]': MontarPrato, 'visita/[cozinha]': () => <Text>Cardápio da cozinha</Text> };
  beforeEach(() => {
    mockSessao.visitante = true;
    mockAdicionar.mockClear();
    mockDefinirCozinha.mockClear();
    mockCarrinho.cozinha = null;
    mockLerPratoVisitante.mockResolvedValue({
      prato: { id: 'm', nome: 'Strogonoff', descricao: null, categoria: null, preco: 3000, foto_url: null, do_dia: false, cozinha_id: 'v', prato_base_id: null, pedidos_mes: 0 },
      cozinha: { id: 'v', nome: 'Viana' },
      esgotado: false,
      grupos: [],
      componentes: [],
      convite: { desconto: 500, minimo: 2000 },
    });
  });
  afterEach(() => {
    mockSessao.visitante = false;
    mockCarrinho.cozinha = { id: 'k', nome: 'Maianga' };
  });

  test('vê o prato e o desconto do convite, sem lhe pedirem a conta', async () => {
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    expect(mockLerPratoVisitante).toHaveBeenCalledWith('m', 'MB-1234');
    expect(ecra.getByText('Strogonoff')).toBeTruthy();
    expect(ecra.getByText('🎁 Convite aplicado: −500 Kz no teu 1.º pedido (pedido a partir de 2.000 Kz).')).toBeTruthy();
  });

  test('adiciona na cozinha do prato e segue para o cardápio dessa cozinha', async () => {
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    fireEvent.press(ecra.getByText('Adicionar ao carrinho · 3.000 Kz'));
    expect(mockDefinirCozinha).toHaveBeenCalledWith({ id: 'v', nome: 'Viana' });
    expect(mockAdicionar).toHaveBeenCalledWith(expect.objectContaining({ id: 'm' }), [], []);
    await act(async () => undefined);
    expect(ecra.getByText('Cardápio da cozinha')).toBeTruthy();
  });

  test('prato que já não está disponível: explica', async () => {
    mockLerPratoVisitante.mockResolvedValue(null);
    const ecra = renderRouter(rotas, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    expect(ecra.getByText('Este prato já não está disponível.')).toBeTruthy();
  });
});
