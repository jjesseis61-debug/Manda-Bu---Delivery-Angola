/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';

import PagamentosAntes from '@/app/pagamentos-antes';
import { separarPagamentosAntes, type PagamentoAntes } from '@/lib/pagamentosAntes';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
jest.mock('@/components/Guarda', () => ({ Guarda: ({ children }: { children: unknown }) => children }));
const mockLista = jest.fn();
const mockDecidir = jest.fn(async (..._a: unknown[]) => undefined);
const mockDevolver = jest.fn(async (..._a: unknown[]) => undefined);
jest.mock('@/lib/pagamentosAntes', () => ({
  ...jest.requireActual('@/lib/pagamentosAntes'),
  pagamentosAntes: () => mockLista(),
  decidirPagamentoAntes: (...a: unknown[]) => mockDecidir(...a),
  devolverPagamentoAntes: (...a: unknown[]) => mockDevolver(...a),
}));

const pag = (id: string, extra: Partial<PagamentoAntes> = {}): PagamentoAntes => ({
  id, pedido_id: 'p' + id, cliente_nome: 'Bia ' + id, cliente_telefone: null, metodo: 'multicaixa_express', valor: 3000,
  referencia: 'MCX' + id, estado: 'pendente', motivo: null, criado_em: '2026-11-22T10:00:00Z', decidido_em: null,
  pedido_estado: 'confirmado', grupo_hora: '2026-11-22T12:00:00Z', cozinha_nome: 'Viana', a_devolver: false, ...extra,
});

test('separa a confirmar, a devolver e decididos', () => {
  const r = separarPagamentosAntes([
    pag('1'),
    pag('2', { estado: 'confirmado', pedido_estado: 'cancelado', a_devolver: true }),
    pag('3', { estado: 'rejeitado', motivo: 'x' }),
  ]);
  expect(r.aConfirmar.map((p) => p.id)).toEqual(['1']);
  expect(r.aDevolver.map((p) => p.id)).toEqual(['2']);
  expect(r.decididos.map((p) => p.id)).toEqual(['3']);
});

test('confirmar, rejeitar com motivo e registar devolução', async () => {
  mockLista.mockResolvedValue([pag('1'), pag('2', { estado: 'confirmado', pedido_estado: 'cancelado', a_devolver: true })]);
  const ecra = renderRouter({ p: PagamentosAntes }, { initialUrl: '/p' });
  await act(async () => undefined);
  expect(ecra.getByText('A confirmar (1)')).toBeTruthy();
  expect(ecra.getByText('A devolver (1)')).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getByText('Confirmar'));
  });
  expect(mockDecidir).toHaveBeenCalledWith('1', true);

  fireEvent.press(ecra.getByText('Rejeitar'));
  fireEvent.changeText(ecra.getByLabelText('Motivo (o cliente vê-o na app)'), 'Não está no extracto');
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Rejeitar')[0]);
  });
  expect(mockDecidir).toHaveBeenCalledWith('1', false, 'Não está no extracto');

  fireEvent.press(ecra.getByText('Registar devolução'));
  fireEvent.changeText(ecra.getByLabelText('Referência da devolução'), 'DEV-1');
  await act(async () => {
    fireEvent.press(ecra.getByText('Marcar devolvido'));
  });
  expect(mockDevolver).toHaveBeenCalledWith('2', 'DEV-1');
});
