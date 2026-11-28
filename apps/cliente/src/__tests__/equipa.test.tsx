/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';

import Equipa from '@/app/equipa';
import { horaValida, textoColegasPorPagar, textoDias, textoEscalao } from '@/lib/equipas';

jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('@expo/vector-icons/Ionicons', () => () => null);
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, sessao: {}, perfil: { cliente_id: 'maria' }, ligada: (c: string) => c === 'equipas_trabalho' }),
}));
jest.mock('@/lib/carrinho', () => ({ useCarrinho: () => ({ cozinhaActual: { id: 'k', nome: 'Viana' } }) }));
jest.mock('@/lib/api', () => ({ lerEnderecos: async () => [], lerCardapio: async () => [] }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const mockMinhas = jest.fn();
const mockResponder = jest.fn(async () => undefined);
const mockHabitual = jest.fn();
const mockPedirPor = jest.fn(async () => 'p');
jest.mock('@/lib/equipas', () => {
  const real = jest.requireActual('@/lib/equipas');
  return {
    ...real,
    minhasEquipas: () => mockMinhas(),
    responderConvite: (...a: unknown[]) => (mockResponder as (...x: unknown[]) => Promise<void>)(...a),
    lerContaMes: async () => ({
      equipa_id: 'eq', cliente_id: 'maria', nome: 'Maria Responsável', mes: '2026-11-01', limite: 40000, total: 7000, pago: 0,
      a_confirmar: 0, em_falta: 7000, em_atraso: false, pagamentos: [],
      linhas: [{ pedido_id: 'x', dia: '2026-11-25', valor: 7000, entregue: true, pedido_por: null, itens: '1× Funge' }],
    }),
    pratoHabitualColega: (...a: unknown[]) => mockHabitual(...a),
    pedirPorColega: (...a: unknown[]) => (mockPedirPor as (...x: unknown[]) => Promise<string>)(...a),
  };
});

const base = {
  id: 'eq', nome: 'Contabilidade', cozinha_id: 'k', responsavel: 'Maria', cozinha: 'Viana', local: 'Escritório', hora_entrega: '12:30',
  prazo_minutos: 90, dias: [1, 2, 3, 4, 5], limite_mensal: 40000, activa: true, pode_pedir: false, pode_ver_conta: false, em_atraso: false,
  extras_hoje: [], acordo: null, beneficio: null,
};

describe('textos da equipa', () => {
  test('dias, hora e metas próximas (Bandura)', () => {
    expect(textoDias([1, 2, 3, 4, 5])).toBe('de segunda a sexta');
    expect(textoDias([1, 3, 5])).toBe('seg, qua, sex');
    expect(horaValida('12:30')).toBe(true);
    expect(horaValida('25:00')).toBe(false);
    expect(textoEscalao({ media: 7.5, pct: 3, proximo_limite: 10, proximo_pct: 5, faltam: 2.5 })).toBe(
      'Este mês ganhas 3% de cada almoço. Com mais 3 almoços por dia (média de 10), passas a 5% no mês seguinte.',
    );
    expect(textoEscalao({ media: 16, pct: 10, proximo_limite: null })).toBe('Estás no escalão mais alto: 10% de cada almoço.');
    expect(textoColegasPorPagar(0)).toBeNull();
    expect(textoColegasPorPagar(1)).toBe('Falta 1 colega pagar a conta do mês para desbloqueares o resto.');
  });
});

describe('ecrã A minha equipa', () => {
  test('convite: o colega escolhe as autorizações antes de aceitar (Cialdini)', async () => {
    mockMinhas.mockResolvedValue([{ ...base, estado: 'convidado', sou_responsavel: false, hoje: null, colegas: [] }]);
    const ecra = renderRouter({ equipa: Equipa }, { initialUrl: '/equipa' });
    await act(async () => undefined);
    expect(ecra.getByText('Convite: equipa «Contabilidade»')).toBeTruthy();
    fireEvent(ecra.getByLabelText('Maria pode pedir o meu almoço'), 'valueChange', true);
    await act(async () => {
      fireEvent.press(ecra.getByText('Aceitar'));
    });
    expect(mockResponder).toHaveBeenCalledWith('eq', true, true, false);
  });

  test('responsável: vê quem pediu, pede pelo colega autorizado (habitual) e vê a sua conta', async () => {
    const prazo = new Date(Date.now() + 3600_000).toISOString();
    mockMinhas.mockResolvedValue([
      {
        ...base,
        estado: 'activo',
        sou_responsavel: true,
        hoje: { grupo_id: 'g', codigo: 'GRP1', estado: 'aberto', prazo, hora: prazo, meu_pedido: null, pedidos: 1 },
        beneficio: { escalao: { media: 7, pct: 3, proximo_limite: 10, proximo_pct: 5, faltam: 3 }, mes_pendente: 420, desbloqueado: 90, pago: 0, colegas_por_pagar: 2 },
        colegas: [
          { cliente_id: 'maria', nome: 'Maria Responsável', estado: 'activo', pode_pedir: false, pode_ver_conta: false, em_atraso: false, pediu_hoje: false },
          { cliente_id: 'joao', nome: 'João Colega', estado: 'activo', pode_pedir: true, pode_ver_conta: true, em_atraso: false, pediu_hoje: false },
          { cliente_id: 'rui', nome: 'Rui Colega', estado: 'activo', pode_pedir: false, pode_ver_conta: false, em_atraso: false, pediu_hoje: true },
        ],
      },
    ]);
    mockHabitual.mockResolvedValue({ itens: [{ cardapio_id: 'f', qtd: 1 }], texto: '1× Funge' });
    const ecra = renderRouter({ equipa: Equipa }, { initialUrl: '/equipa' });
    await act(async () => undefined);
    expect(ecra.getByText('Faltam 2 colegas pagarem a conta do mês para desbloqueares o resto.')).toBeTruthy();
    expect(ecra.getByText('Rui Colega · ✓ pediu hoje')).toBeTruthy();
    expect(ecra.getAllByText('Pedir por ele')).toHaveLength(1);
    expect(ecra.getByText('Em falta')).toBeTruthy();
    fireEvent.press(ecra.getByText('Pedir por ele'));
    await act(async () => undefined);
    await act(async () => {
      fireEvent.press(ecra.getByText('Repetir o habitual: 1× Funge'));
    });
    expect(mockPedirPor).toHaveBeenCalledWith('eq', 'joao', [{ cardapio_id: 'f', qtd: 1 }]);
    expect(ecra.getByText('Pedido feito. João recebeu um aviso e pode trocar ou recusar.')).toBeTruthy();
  });
});
