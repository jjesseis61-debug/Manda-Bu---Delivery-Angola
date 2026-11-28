/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';

import EquipaOperador from '@/app/equipas/[id]';
import { parteDaCozinha, textoEscaloes } from '@/lib/equipas';

jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
jest.mock('@/components/Guarda', () => ({ Guarda: ({ children }: { children: React.ReactNode }) => children }));
const mockPode = jest.fn((p: string) => p === 'pedidos.gerir');
jest.mock('@/lib/sessao', () => ({ useSessao: () => ({ pode: (p: string) => mockPode(p) }) }));

const mockDecidir = jest.fn(async () => undefined);
const mockDinheiro = jest.fn(async () => 'id');
const mockAceitar = jest.fn(async () => undefined);
jest.mock('@/lib/equipas', () => {
  const real = jest.requireActual('@/lib/equipas');
  return {
    ...real,
    lerEquipa: async () => ({
      id: 'eq', nome: 'Contabilidade', origem: 'plataforma', limite_mensal: 40000, activa: true, responsavel: 'Maria', cozinha: 'Viana',
      mes: '2026-11-01', hora_entrega: '12:30', prazo_minutos: 90, dias: [1, 2, 3, 4, 5],
      grupo_hoje: { id: 'g', estado: 'aberto', prazo: '2026-11-28T10:00:00Z', pedidos: 4 },
      extras: [{ id: 'x1', cliente: 'João', quantidade: 3, motivo: 'Visita', estado: 'pendente', aprovadas: null, dia: '2026-11-28' }],
      contas: [{ cliente_id: 'joao', nome: 'João', mes: '2026-11-01', limite: 40000, total: 7000, pago: 0, a_confirmar: 0, em_falta: 7000, em_atraso: false }],
      pagamentos_pendentes: [],
      acordo: { id: 'a1', estado: 'proposto', quem_paga: 'plataforma', parte_cozinha_pct: 50, pct_1: 3, pct_2: 5, pct_3: 10, limite_2: 10, limite_3: 15, conta_bebidas: false, tecto_refeicao: 1000 },
      escalao: { media: 0, pct: 3 },
      beneficios: { pendente: 0, desbloqueado: 0, parte_cozinha_desbloqueada: 0, pago: 0, mes: 0, parte_cozinha_mes: 0 },
    }),
    decidirExtra: (...a: unknown[]) => (mockDecidir as (...x: unknown[]) => Promise<void>)(...a),
    registarDinheiro: (...a: unknown[]) => (mockDinheiro as (...x: unknown[]) => Promise<string>)(...a),
    aceitarAcordo: (...a: unknown[]) => (mockAceitar as (...x: unknown[]) => Promise<void>)(...a),
  };
});

test('escalões e parte da cozinha', () => {
  expect(textoEscaloes({ pct_1: 3, pct_2: 5, pct_3: 10, limite_2: 10, limite_3: 15 })).toBe('3% até 9 almoços por dia · 5% de 10 a 14 · 10% a partir de 15');
  expect(parteDaCozinha(100, { quem_paga: 'cozinha', parte_cozinha_pct: 50 })).toBe(100);
  expect(parteDaCozinha(101, { quem_paga: 'plataforma_cozinha', parte_cozinha_pct: 50 })).toBe(51);
  expect(parteDaCozinha(100, { quem_paga: 'plataforma', parte_cozinha_pct: 50 })).toBe(0);
});

test('cozinha: aprova parte das refeições extra, regista dinheiro e aceita o acordo', async () => {
  const ecra = renderRouter({ 'equipas/[id]': EquipaOperador }, { initialUrl: '/equipas/eq' });
  await act(async () => undefined);
  expect(ecra.getByText('João: mais 3 · Visita')).toBeTruthy();
  fireEvent.changeText(ecra.getByLabelText('Só'), '2');
  await act(async () => {
    fireEvent.press(ecra.getByText('Aprovar parte'));
  });
  expect(mockDecidir).toHaveBeenCalledWith('x1', 2);
  fireEvent.press(ecra.getByText('Recebi em dinheiro…'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Registar dinheiro recebido'));
  });
  expect(mockDinheiro).toHaveBeenCalledWith('eq', 'joao', '2026-11-01', 7000);
  await act(async () => {
    fireEvent.press(ecra.getByText('A cozinha aceita o acordo'));
  });
  expect(mockAceitar).toHaveBeenCalledWith('a1');
  // Sem permissão das Finanças: não propõe acordos nem confirma referências
  expect(ecra.queryByText('Propor novo acordo')).toBeNull();
});
