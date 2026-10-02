/// <reference types="jest" />
import { act, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import { registarPosicaoEntrega } from '@/lib/api';
import { usePartilharLocalizacao } from '@/lib/partilharLocalizacao';

const mockRemover = jest.fn();
let mockAoMover: ((p: unknown) => void) | null = null;
jest.mock('expo-location', () => ({
  Accuracy: { High: 4 },
  requestForegroundPermissionsAsync: async () => ({ status: 'granted' }),
  getCurrentPositionAsync: async () => ({ coords: { latitude: -8.9, longitude: 13.18, accuracy: 10 } }),
  watchPositionAsync: async (_o: unknown, f: (p: unknown) => void) => {
    mockAoMover = f;
    return { remove: mockRemover };
  },
}));
jest.mock('@/lib/api', () => ({ registarPosicaoEntrega: jest.fn() }));
const mockRegistar = registarPosicaoEntrega as jest.Mock;

function Ecra({ tentar }: { tentar: boolean }) {
  const { aCaminho } = usePartilharLocalizacao(tentar, 0);
  return <Text>a caminho: {aCaminho}</Text>;
}

beforeEach(() => {
  mockRegistar.mockReset();
  mockRemover.mockReset();
  mockAoMover = null;
});

test('com pedidos a caminho envia a posição e continua a enviar ao mover-se', async () => {
  mockRegistar.mockResolvedValue(2);
  const ecra = renderRouter({ index: () => <Ecra tentar /> }, { initialUrl: '/' });
  await act(async () => undefined);
  expect(mockRegistar).toHaveBeenCalledWith(-8.9, 13.18, 10);
  expect(ecra.getByText('a caminho: 2')).toBeTruthy();
  expect(mockAoMover).not.toBeNull();

  // Último pedido entregue: o servidor devolve 0 e a app pára de seguir a posição
  mockRegistar.mockResolvedValue(0);
  await act(async () => mockAoMover?.({ coords: { latitude: -8.91, longitude: 13.18, accuracy: 8 } }));
  expect(mockRemover).toHaveBeenCalled();
  expect(ecra.getByText('a caminho: 0')).toBeTruthy();
});

test('sem pedidos a caminho não pede a localização', async () => {
  renderRouter({ index: () => <Ecra tentar={false} /> }, { initialUrl: '/' });
  await act(async () => undefined);
  expect(mockRegistar).not.toHaveBeenCalled();
});
