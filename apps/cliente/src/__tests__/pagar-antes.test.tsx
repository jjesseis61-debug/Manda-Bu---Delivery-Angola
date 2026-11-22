/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';

import { PagarAntes } from '@/components/PagarAntes';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
const mockInfo = jest.fn();
const mockPagar = jest.fn(async (..._a: unknown[]) => undefined);
jest.mock('@/lib/api', () => ({
  meuPagamentoAntes: (...a: unknown[]) => mockInfo(...a),
  pagarAntes: (...a: unknown[]) => mockPagar(...a),
}));

const base = { modo: 'individual', pode: true, falta: 3000, pago_antes: 0, ultimo: null };
const abrir = () => renderRouter({ pedido: () => <PagarAntes pedidoId="p1" /> }, { initialUrl: '/pedido' });

beforeEach(() => {
  mockInfo.mockReset();
  mockPagar.mockClear();
});

test('cada um paga: escreve a referência e envia «Já paguei»', async () => {
  mockInfo.mockResolvedValueOnce(base).mockResolvedValue({
    ...base, pode: false, ultimo: { estado: 'pendente', valor: 3000, metodo: 'unitel_money', referencia: 'UM-12345', motivo: null, criado_em: '' },
  });
  const ecra = abrir();
  await act(async () => undefined);
  expect(ecra.getByText('Paga já a tua parte: 3.000 Kz')).toBeTruthy();
  fireEvent.press(ecra.getByText('Unitel Money'));
  fireEvent.changeText(ecra.getByLabelText('Referência da transferência'), 'UM-12345');
  await act(async () => {
    fireEvent.press(ecra.getByText('Já paguei'));
  });
  expect(mockPagar).toHaveBeenCalledWith('p1', 'unitel_money', 'UM-12345');
  expect(ecra.getByText('⏳ Pagamento a confirmar')).toBeTruthy();
});

test('rejeitado: mostra o motivo e deixa enviar de novo', async () => {
  mockInfo.mockResolvedValue({
    ...base, ultimo: { estado: 'rejeitado', valor: 3000, metodo: 'multicaixa_express', referencia: 'X1', motivo: 'Referência não encontrada', criado_em: '' },
  });
  const ecra = abrir();
  await act(async () => undefined);
  expect(ecra.getByText('O pagamento anterior não foi aceite: Referência não encontrada. Confirma a referência e envia de novo.')).toBeTruthy();
  expect(ecra.getByText('Já paguei')).toBeTruthy();
});

test('pago: o estafeta não cobra nada; quem recebe paga: nada aparece', async () => {
  mockInfo.mockResolvedValue({ ...base, pode: false, falta: 0, pago_antes: 3000 });
  const ecra = abrir();
  await act(async () => undefined);
  expect(ecra.getByText('✓ A tua parte está paga (3.000 Kz). O estafeta não te cobra nada.')).toBeTruthy();

  mockInfo.mockResolvedValue({ ...base, modo: 'quem_recebe', pode: false });
  const outro = abrir();
  await act(async () => undefined);
  expect(outro.queryByText(/Paga já a tua parte/)).toBeNull();
});
