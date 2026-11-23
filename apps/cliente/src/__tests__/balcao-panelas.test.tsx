/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import MontarPrato from '@/app/montar/[id]';
import {
  dicaDoPasso,
  gruposComStock,
  passosDoBalcao,
  perguntaDoPasso,
  recipienteDaOpcao,
  textoRestam,
  textoRestamOpcao,
  textoSeguinte,
  tipoDoGrupo,
  zonasDoPrato,
} from '@/lib/balcaoPanelas';
import type { GrupoOpcoes } from '@/lib/tipos';

const mockAdicionar = jest.fn();
const mockVisita = jest.fn();
const mockGrupo: { valor: 'A' | 'B' | null } = { valor: 'B' };
const mockDoses: { valor: unknown[] } = { valor: [] };
const mockUnidades: { valor: Record<string, number> } = { valor: {} };
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
  lerUnidadesOpcoes: async () => mockUnidades.valor,
  lerDoses: async () => mockDoses.valor,
  lerOpcoes: async () => [
    { id: 'g1', cardapio_id: 'm', nome: 'Base', minimo: 1, maximo: 1, ordem: 1,
      opcoes: [{ id: 'arroz', nome: 'Arroz', preco_extra: 700, ordem: 1 }, { id: 'funje', nome: 'Funje', preco_extra: 600, ordem: 2 }], acabaram: [] },
    { id: 'g2', cardapio_id: 'm', nome: 'Proteína', minimo: 1, maximo: 1, ordem: 2,
      opcoes: [{ id: 'frango', nome: 'Frango', preco_extra: 1200, ordem: 1 }],
      acabaram: [{ id: 'vaca', nome: 'Carne de vaca', preco_extra: 2500, ordem: 2 }] },
    { id: 'g3', cardapio_id: 'm', nome: 'Acompanhamentos', minimo: 0, maximo: 3, ordem: 3,
      opcoes: [{ id: 'feijao', nome: 'Feijão', preco_extra: 400, ordem: 1 }, { id: 'salada', nome: 'Salada', preco_extra: 300, ordem: 2 }], acabaram: [] },
    { id: 'g4', cardapio_id: 'm', nome: 'Bebida', minimo: 0, maximo: 1, ordem: 4,
      opcoes: [{ id: 'ananas', nome: 'Sumo de Ananás', preco_extra: 1000, ordem: 1 }, { id: 'gasosa', nome: 'Gasosa', preco_extra: 500, ordem: 2 },
        { id: 'cola', nome: 'Cola', preco_extra: 500, ordem: 3 }], acabaram: [] },
  ],
}));

const grupo = (o: Partial<GrupoOpcoes>): GrupoOpcoes => ({ id: 'g', cardapio_id: 'm', nome: 'Base', minimo: 1, maximo: 1, ordem: 1, opcoes: [], ...o });
const op = (id: string, nome: string) => ({ id, nome, preco_extra: 0, ordem: 1 });

describe('regras do balcão', () => {
  test('tipo do grupo pelo nome; recipiente pelo tipo (panela, tigela, barro, copo, lata)', () => {
    expect(tipoDoGrupo({ nome: 'Sumo Natural', maximo: 3 })).toBe('bebida');
    expect(tipoDoGrupo({ nome: 'Base', maximo: 3 })).toBe('base');
    expect(tipoDoGrupo({ nome: 'Proteína', maximo: 3 })).toBe('proteina');
    expect(tipoDoGrupo({ nome: 'Acompanhamentos', maximo: 3 })).toBe('acompanhamento');
    expect(tipoDoGrupo({ nome: 'Escolhe', maximo: 1 })).toBe('base');
    expect(recipienteDaOpcao({ nome: 'Base', maximo: 3 }, { nome: 'Arroz' })).toBe('panela');
    expect(recipienteDaOpcao({ nome: 'Acompanhamentos', maximo: 3 }, { nome: 'Feijão de óleo de palma' })).toBe('barro');
    expect(recipienteDaOpcao({ nome: 'Acompanhamentos', maximo: 3 }, { nome: 'Salada' })).toBe('tigela');
    expect(recipienteDaOpcao({ nome: 'Sumo Natural', maximo: 3 }, { nome: 'Sumo de Ananás' })).toBe('copo');
    expect(recipienteDaOpcao({ nome: 'Bebida', maximo: 1 }, { nome: 'Gasosa de laranja' })).toBe('lata');
  });

  test('pergunta e dica pelo tipo; bebidas vão para o fim e para o tabuleiro', () => {
    const passos = passosDoBalcao(
      [
        grupo({ id: 'b', nome: 'Sumo Natural', minimo: 0, maximo: 3, opcoes: [op('s', 'Sumo de Ananás')] }),
        grupo({ id: 'a', opcoes: [op('a', 'Arroz'), op('f', 'Funje')] }),
        grupo({ id: 'c', nome: 'Acompanhamentos', minimo: 0, maximo: 3, opcoes: [op('x', 'Salada')] }),
      ],
      [],
    );
    expect(passos.map((p) => p.titulo)).toEqual(['Base', 'Acompanhamentos', 'Sumo Natural']);
    expect(perguntaDoPasso(passos[0])).toBe('Arroz ou funje?');
    expect(perguntaDoPasso(passos[1])).toBe('E para acompanhar?');
    expect(perguntaDoPasso(passos[2])).toBe('E para beber?');
    expect(dicaDoPasso(passos[2])).toBe('Toca para pôr no tabuleiro, ao lado do prato. Até 3, se quiseres.');
    expect(dicaDoPasso(passos[1])).toBe('Toca na tigela para servir. Até 3, se quiseres.');
  });

  test('ingredientes antes das bebidas; o botão diz o que falta ou o passo seguinte', () => {
    const g = grupo({ opcoes: [op('a', 'Arroz')] });
    const passos = passosDoBalcao([g], [{ cardapio_id: 'm', produto_id: 'p', nome: 'Cebola', quantidade: 1, unidade: null, valor: 25 }]);
    expect(passos.map((p) => p.titulo)).toEqual(['Base', 'Ingredientes']);
    expect(textoSeguinte(passos, 0, [])).toBe('Falta: base');
    expect(textoSeguinte(passos, 0, ['a'])).toBe('Seguinte: ingredientes');
  });

  test('restam: só poucos e verdadeiros (Cialdini: escassez real); 0 no stock passa a «acabaram»', () => {
    expect(textoRestam(null)).toBeNull();
    expect(textoRestam(12)).toBeNull();
    expect(textoRestam(4)).toBe('Restam 4 pratos hoje');
    expect(textoRestamOpcao(0)).toBeNull();
    expect(textoRestamOpcao(1)).toBe('Resta 1');
    const [g] = gruposComStock([grupo({ opcoes: [op('a', 'Gasosa'), op('b', 'Água')] })], { a: 0, b: 3 });
    expect(g.opcoes.map((o) => o.id)).toEqual(['b']);
    expect(g.acabaram?.map((o) => o.id)).toEqual(['a']);
  });

  test('zonas do prato: base, proteína, acompanhamento e a bebida no tabuleiro', () => {
    const z = zonasDoPrato(
      [grupo({ opcoes: [op('a', 'Arroz')] }), grupo({ id: 'b', nome: 'Bebida', opcoes: [op('g', 'Gasosa')] })],
      ['a', 'g'],
    );
    expect(z.base.map((o) => o.id)).toEqual(['a']);
    expect(z.bebida.map((o) => o.id)).toEqual(['g']);
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
    mockUnidades.valor = { gasosa: 2, cola: 0 };
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
    expect(ecra.getByText('1 item · ver')).toBeTruthy();
    fireEvent.press(ecra.getByText('Seguinte: proteína'));

    // A carne acabou hoje: panela vazia, não se escolhe
    expect(ecra.getByLabelText('Carne de vaca: hoje não há')).toBeTruthy();
    fireEvent.press(ecra.getByText('Carne de vaca'));
    fireEvent.press(ecra.getByText('Frango'));
    fireEvent.press(ecra.getByText('Seguinte: acompanhamentos'));

    expect(ecra.getByText('E para acompanhar?')).toBeTruthy();
    fireEvent.press(ecra.getByText('Feijão'));
    fireEvent.press(ecra.getByText('Seguinte: bebida'));

    // Geleira: a gasosa conta o stock (restam 2), a cola acabou; o sumo vai para o tabuleiro
    expect(ecra.getByText('E para beber?')).toBeTruthy();
    expect(ecra.getByText('Restam 2')).toBeTruthy();
    expect(ecra.getByLabelText('Cola: hoje não há')).toBeTruthy();
    expect(ecra.getByLabelText('Sem bebida')).toBeTruthy();
    fireEvent.press(ecra.getByText('Sumo de Ananás'));
    expect(ecra.getByText('✓ no tabuleiro')).toBeTruthy();
    expect(ecra.getByLabelText('No tabuleiro: Sumo de Ananás')).toBeTruthy();
    expect(ecra.getByText('4 itens · ver')).toBeTruthy();
    fireEvent.press(ecra.getByLabelText(/^O teu prato: Arroz, Frango, Feijão/));
    expect(ecra.getByText('4 itens · esconder')).toBeTruthy();

    fireEvent.press(ecra.getByText('Adicionar · 3.300 Kz'));
    expect(mockAdicionar).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'm' }),
      [
        { id: 'arroz', nome: 'Arroz', preco_extra: 700 },
        { id: 'frango', nome: 'Frango', preco_extra: 1200 },
        { id: 'feijao', nome: 'Feijão', preco_extra: 400 },
        { id: 'ananas', nome: 'Sumo de Ananás', preco_extra: 1000 },
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
