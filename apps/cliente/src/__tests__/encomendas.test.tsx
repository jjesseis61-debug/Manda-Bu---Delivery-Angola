/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import NovaEncomenda from '@/app/encomenda/nova';
import Encomendas from '@/app/encomendas';
import { diasParaEncomenda, quandoEncomenda } from '@/lib/encomendas';

const mockSessao = { carregado: true, perfil: { cliente_id: 'c1' }, ligada: (c: string) => c === 'encomendas' };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));
const mockRpc = jest.fn();
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: (...a: unknown[]) => mockRpc(...a) } }));
jest.mock('@/lib/api', () => ({
  lerEnderecos: async () => [{ ponto_entrega_id: 'p1', nome: 'Casa da avó', pontos_entrega: { tipo: 'residencial', referencia: 'Rangel' } }],
}));

const base = {
  id: 'e1',
  criado_em: '2026-11-22T10:00:00Z',
  para_quando: '2026-11-28T12:00:00Z',
  pessoas: 8,
  nota: null,
  motivo: null,
  receita_id: 'r1',
  receita: 'Mufete',
  cozinha_nome: 'Rangel',
  preco: 25000,
  taxa_entrega: 1500,
  total: 26500,
  sinal: 13250,
  pedido_id: null,
  pago_antes: null,
  pagamento: null,
  local: 'Rangel',
};

beforeEach(() => mockRpc.mockReset());

test('dias: só a partir de 24 horas, e a hora de Luanda no texto', () => {
  const dias = diasParaEncomenda(new Date('2026-11-22T13:30:00Z')); // 14h30 em Luanda
  expect(dias[0]).toBe('2026-11-23'); // amanhã ainda há horas depois das 14h30
  expect(dias).toHaveLength(7);
  expect(diasParaEncomenda(new Date('2026-11-22T20:00:00Z'))[0]).toBe('2026-11-24'); // 21h: amanhã já não há
  expect(quandoEncomenda('2026-11-28T12:00:00Z')).toBe('Sáb 28/11 às 13h00');
});

test('encomendar: envia pessoas, dia, hora (Luanda) e morada, e abre a lista', async () => {
  jest.useFakeTimers({ now: new Date('2026-11-22T09:00:00Z'), doNotFake: ['nextTick', 'setImmediate', 'setTimeout', 'setInterval', 'queueMicrotask'] });
  mockRpc.mockImplementation(async (nome: string) => (nome === 'encomendar' ? { data: 'e1', error: null } : { data: [], error: null }));
  const ecra = renderRouter(
    { 'encomenda/nova': NovaEncomenda, encomendas: () => <Text>Lista</Text> },
    { initialUrl: '/encomenda/nova?receita=r1&titulo=Mufete' },
  );
  await act(async () => undefined);
  expect(ecra.getByText('🎉 Boda Bué · Mufete')).toBeTruthy();
  fireEvent.press(ecra.getByText('10'));
  fireEvent.press(ecra.getByText('19h00'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Pedir preço'));
  });
  expect(mockRpc).toHaveBeenCalledWith('encomendar', {
    p_receita: 'r1',
    p_pessoas: 10,
    p_para_quando: '2026-11-23T18:00:00.000Z',
    p_ponto: 'p1',
    p_nota: null,
  });
  expect(ecra.getByText('Lista')).toBeTruthy();
  jest.useRealTimers();
});

test('proposta: mostra total e sinal e aceita', async () => {
  mockRpc.mockImplementation(async (nome: string) =>
    nome === 'minhas_encomendas' ? { data: [{ ...base, estado: 'a_confirmar' }], error: null } : { data: 'ped1', error: null },
  );
  const ecra = renderRouter({ encomendas: Encomendas }, { initialUrl: '/encomendas' });
  await act(async () => undefined);
  expect(ecra.getByText('O preço está pronto: confirma para avançarmos.')).toBeTruthy();
  expect(ecra.getByText('26.500 Kz')).toBeTruthy();
  expect(ecra.getByText('13.250 Kz')).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getByText('Aceitar'));
  });
  expect(mockRpc).toHaveBeenCalledWith('encomenda_responder', { p_id: 'e1', p_aceitar: true });
});

test('confirmada: paga o sinal com a referência; depois fica a confirmar', async () => {
  let pagamento: unknown = null;
  mockRpc.mockImplementation(async (nome: string) => {
    if (nome === 'encomenda_pagar_sinal') {
      pagamento = { estado: 'pendente', valor: 13250, motivo: null };
      return { data: 'pag1', error: null };
    }
    return { data: [{ ...base, estado: 'confirmada', pedido_id: 'ped1', pagamento }], error: null };
  });
  const ecra = renderRouter({ encomendas: Encomendas }, { initialUrl: '/encomendas' });
  await act(async () => undefined);
  fireEvent.changeText(ecra.getByLabelText('Referência da transferência'), 'MCX-123');
  await act(async () => {
    fireEvent.press(ecra.getByText('Já paguei o sinal'));
  });
  expect(mockRpc).toHaveBeenCalledWith('encomenda_pagar_sinal', { p_id: 'e1', p_metodo: 'multicaixa_express', p_referencia: 'MCX-123' });
  expect(ecra.getByText(/Sinal de 13.250 Kz a confirmar/)).toBeTruthy();
  expect(ecra.queryByText('Cancelar encomenda')).toBeNull();
});
