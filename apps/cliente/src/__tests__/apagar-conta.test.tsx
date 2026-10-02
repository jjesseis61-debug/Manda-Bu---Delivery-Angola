/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import ApagarConta from '@/app/apagar-conta';
import { apagarConta } from '@/lib/api';

jest.mock('@/lib/api', () => ({ apagarConta: jest.fn() }));
jest.mock('@/lib/sessao', () => ({ useSessao: () => ({ sair: async () => undefined }) }));
jest.mock('@/lib/carrinho', () => ({ useCarrinho: () => ({ limpar: () => undefined }) }));
const mockApagar = apagarConta as jest.Mock;

function abrir() {
  return renderRouter({ 'apagar-conta': ApagarConta, entrar: () => <Text>Entrar</Text> }, { initialUrl: '/apagar-conta' });
}

test('só apaga depois da segunda confirmação e volta à entrada', async () => {
  mockApagar.mockResolvedValue(undefined);
  const ecra = abrir();
  fireEvent.press(ecra.getByText('Apagar a minha conta'));
  expect(mockApagar).not.toHaveBeenCalled();
  await act(async () => {
    fireEvent.press(ecra.getByText('Sim, apagar a minha conta'));
  });
  expect(mockApagar).toHaveBeenCalledTimes(1);
  expect(ecra.getPathname()).toBe('/entrar');
});

test('mostra o motivo quando o servidor recusa', async () => {
  mockApagar.mockRejectedValue({ message: 'pedido_em_curso' });
  const ecra = abrir();
  fireEvent.press(ecra.getByText('Apagar a minha conta'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Sim, apagar a minha conta'));
  });
  expect(ecra.getByText(/Tens um pedido a meio/)).toBeTruthy();
  expect(ecra.getPathname()).toBe('/apagar-conta');
});
