/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Custos from '@/app/cozinhas/[id]/custos';
import { custosDaCozinha, definirCustoItem } from '@/lib/api';

jest.mock('@/lib/api', () => ({ custosDaCozinha: jest.fn(), definirCustoItem: jest.fn().mockResolvedValue(undefined) }));
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, sessao: {}, funcionario: { id: 'f', cozinhas_equipa: [] }, pode: () => true }),
}));

test('mostra a margem e guarda só os custos alterados', async () => {
  (custosDaCozinha as jest.Mock).mockResolvedValue([
    { item_id: 'p1', tipo: 'prato', prato_id: 'p1', nome: 'Calulu', grupo: null, preco: 5000, custo: 3500, disponivel: true },
    { item_id: 'p2', tipo: 'prato', prato_id: 'p2', nome: 'Monta', grupo: null, preco: 0, custo: null, disponivel: true },
    { item_id: 'o1', tipo: 'opcao', prato_id: 'p2', nome: 'Arroz', grupo: 'Base', preco: 700, custo: null, disponivel: true },
  ]);
  const ecra = renderRouter({ 'cozinhas/[id]/custos': Custos }, { initialUrl: '/cozinhas/k1/custos' });
  await waitFor(() => expect(ecra.getByText(/margem 30%/)).toBeTruthy());
  fireEvent.changeText(ecra.getByLabelText('Custo de Arroz'), '300');
  expect(ecra.getByText(/margem 57,1%/)).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar 1 alteração(ões)'));
  });
  expect(definirCustoItem).toHaveBeenCalledTimes(1);
  expect(definirCustoItem).toHaveBeenCalledWith('o1', 300);
});
