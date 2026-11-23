/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import MontarPrato from '@/app/montar/[id]';
import { dicaDoPasso, passosDoBalcao, perguntaDoPasso, recipienteDaOpcao, textoRestam, textoSeguinte } from '@/lib/balcaoPanelas';
import type { GrupoOpcoes } from '@/lib/tipos';

const mockAdicionar = jest.fn();
const mockVisita = jest.fn();
const mockGrupo: { valor: 'A' | 'B' | null } = { valor: 'B' };
const mockDoses: { valor: unknown[] } = { valor: [] };
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({
    carregado: true,
    ligada: () => true,
    sessao: {},
    perfil: { cliente_id: 'c', codigo: 'MB-4812' },
    parametros: { desconto_indicado: 1000, desconto_subtotal_minimo: 5000 },
  }),
}));
jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('@/lib/convite', () => ({ lerCodigoPendente: async () => null }));
jest.mock('@expo/vector-icons/Ionicons', () => () => null);
jest.mock('@/lib/carrinho', () => ({
  useCarrinho: () => ({
    adicionar: mockAdicionar, repeticao: null, avancarFila: jest.fn(), definirRepeticao: jest.fn(),
    cozinhaActual: { id: 'k', nome: 'Maianga' }, quantidade: 0, grupo: null, definirCozinha: jest.fn(),
  }),
}));
jest.mock('@/lib/condominio', () => ({ posicaoParaCondominio: async () => null, condominioAqui: async () => null }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
jest.mock('@/lib/api', () => ({
  cozinhasParaPedir: async () => [{ cozinha_id: 'k', nome: 'Maianga' }],
  cozinhaPadrao: async () => 'k',
  visitaExperiencia: async (...a: unknown[]) => {
    mockVisita(...a);
    return mockGrupo.valor;
  },
  lerItemCardapio: async () => ({
    id: 'm', nome: 'Prato da casa', descricao: null, categoria: null, preco: 0, foto_url: null, do_dia: false, cozinha_id: 'k', prato_base_id: null,
  }),
  lerComponentes: async () => [],
  lerDoses: async () => mockDoses.valor,
  lerOpcoes: async () => [
    { id: 'g1', cardapio_id: 'm', nome: 'Base', minimo: 1, maximo: 1, ordem: 1,
      opcoes: [{ id: 'arroz', nome: 'Arroz', preco_extra: 700, ordem: 1 }, { id: 'funje', nome: 'Funje', preco_extra: 600, ordem: 2 }], acabaram: [] },
    { id: 'g2', cardapio_id: 'm', nome: 'Proteína', minimo: 1, maximo: 1, ordem: 2,
      opcoes: [{ id: 'frango', nome: 'Frango', preco_extra: 1200, ordem: 1 }],
      acabaram: [{ id: 'vaca', nome: 'Carne de vaca', preco_extra: 2500, ordem: 2 }] },
    { id: 'g3', cardapio_id: 'm', nome: 'Acompanhamentos', minimo: 0, maximo: 3, ordem: 3,
      opcoes: [{ id: 'feijao', nome: 'Feijão', preco_extra: 400, ordem: 1 }, { id: 'salada', nome: 'Salada', preco_extra: 300, ordem: 2 }], acabaram: [] },
  ],
}));

const grupo = (o: Partial<GrupoOpcoes>): GrupoOpcoes => ({ id: 'g', cardapio_id: 'm', nome: 'Base', minimo: 1, maximo: 1, ordem: 1, opcoes: [], ...o });
const op = (id: string, nome: string) => ({ id, nome, preco_extra: 0, ordem: 1 });

describe('regras do balcão', () => {
  test('recipiente: guisados em panela de barro, escolha múltipla em tigela, o resto em panela', () => {
    expect(recipienteDaOpcao({ maximo: 3 }, { nome: 'Feijão de óleo de palma' })).toBe('barro');
    expect(recipienteDaOpcao({ maximo: 1 }, { nome: 'Muamba de galinha' })).toBe('barro');
    expect(recipienteDaOpcao({ maximo: 3 }, { nome: 'Salada' })).toBe('tigela');
    expect(recipienteDaOpcao({ maximo: 1 }, { nome: 'Arroz' })).toBe('panela');
  });

  test('pergunta: «Arroz ou funje?» com 2 ou 3 opções de escolha única, senão o nome do grupo', () => {
    const passo = (g: GrupoOpcoes) => passosDoBalcao([g], [])[0];
    expect(perguntaDoPasso(passo(grupo({ opcoes: [op('a', 'Arroz'), op('f', 'Funje')] })))).toBe('Arroz ou funje?');
    expect(perguntaDoPasso(passo(grupo({ opcoes: [op('a', 'frango'), op('p', 'Peixe'), op('c', 'Carne')] })))).toBe('Frango, peixe ou carne?');
    expect(perguntaDoPasso(passo(grupo({ nome: 'acompanhamentos', maximo: 3, opcoes: [op('a', 'A'), op('b', 'B')] })))).toBe('Acompanhamentos');
    expect(dicaDoPasso(passo(grupo({ minimo: 0, maximo: 3 })))).toBe('Toca na panela para tirar uma concha. Até 3, se quiseres.');
  });

  test('ingredientes entram como último passo; o botão diz o que falta ou o passo seguinte', () => {
    const g = grupo({ opcoes: [op('a', 'Arroz')] });
    const passos = passosDoBalcao([g], [{ cardapio_id: 'm', produto_id: 'p', nome: 'Cebola', quantidade: 1, unidade: null, valor: 25 }]);
    expect(passos.map((p) => p.titulo)).toEqual(['Base', 'Ingredientes']);
    expect(textoSeguinte(passos, 0, [])).toBe('Falta: base');
    expect(textoSeguinte(passos, 0, ['a'])).toBe('Seguinte: ingredientes');
  });

  test('restam: só poucos e verdadeiros (Cialdini: escassez real)', () => {
    expect(textoRestam(null)).toBeNull();
    expect(textoRestam(0)).toBeNull();
    expect(textoRestam(12)).toBeNull();
    expect(textoRestam(1)).toBe('Resta 1 prato hoje');
    expect(textoRestam(4)).toBe('Restam 4 pratos hoje');
  });
});

describe('ecrã Servir o prato', () => {
  beforeEach(() => {
    mockAdicionar.mockClear();
    mockVisita.mockClear();
    mockDoses.valor = [];
  });

  test('grupo B: serve passo a passo, com a panela vazia e o tempo até Adicionar', async () => {
    mockGrupo.valor = 'B';
    mockDoses.valor = [{ cardapio_id: 'm', restantes: 4 }];
    const ecra = renderRouter({ 'montar/[id]': MontarPrato, inicio: () => <Text>Início</Text> }, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    expect(mockVisita).toHaveBeenCalledWith('balcao_panelas');
    expect(ecra.getByText('Arroz ou funje?')).toBeTruthy();
    expect(ecra.getByText('Restam 4 pratos hoje')).toBeTruthy();
    // Sem base não se segue
    fireEvent.press(ecra.getByText('Falta: base'));
    expect(ecra.queryByText('Frango')).toBeNull();

    fireEvent.press(ecra.getByText('Arroz'));
    expect(ecra.getByText('🥄 no prato')).toBeTruthy();
    expect(ecra.getByText('700 Kz')).toBeTruthy();
    fireEvent.press(ecra.getByText('Seguinte: proteína'));

    // A carne acabou hoje: panela vazia, não se escolhe
    expect(ecra.getByLabelText('Carne de vaca: hoje não há')).toBeTruthy();
    fireEvent.press(ecra.getByText('Carne de vaca'));
    fireEvent.press(ecra.getByText('Frango'));
    fireEvent.press(ecra.getByText('Seguinte: acompanhamentos'));

    fireEvent.press(ecra.getByText('Feijão'));
    fireEvent.press(ecra.getByText('Adicionar · 2.300 Kz'));
    expect(mockAdicionar).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'm' }),
      [
        { id: 'arroz', nome: 'Arroz', preco_extra: 700 },
        { id: 'frango', nome: 'Frango', preco_extra: 1200 },
        { id: 'feijao', nome: 'Feijão', preco_extra: 400 },
      ],
      [],
    );
    expect(mockVisita).toHaveBeenCalledWith('balcao_panelas', expect.any(Number));
  });

  test('grupo A: fica a lista de sempre e também conta o tempo até Adicionar', async () => {
    mockGrupo.valor = 'A';
    const ecra = renderRouter({ 'montar/[id]': MontarPrato, inicio: () => <Text>Início</Text> }, { initialUrl: '/montar/m' });
    await act(async () => undefined);
    expect(ecra.queryByText('Arroz ou funje?')).toBeNull();
    expect(ecra.getByText('🍽️ O teu prato')).toBeTruthy();
    fireEvent.press(ecra.getByText('Arroz'));
    fireEvent.press(ecra.getByText('Frango'));
    fireEvent.press(ecra.getByText('Adicionar · 1.900 Kz'));
    expect(mockAdicionar).toHaveBeenCalled();
    expect(mockVisita).toHaveBeenCalledWith('balcao_panelas', expect.any(Number));
  });
});
