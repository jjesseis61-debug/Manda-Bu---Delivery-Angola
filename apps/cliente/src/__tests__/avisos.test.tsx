/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';
import { Text } from 'react-native';

import Avisos from '@/app/avisos';
import { marcarAvisosVistos, meusAvisos } from '@/lib/api';

jest.mock('@/lib/api', () => ({ meusAvisos: jest.fn(), marcarAvisosVistos: jest.fn().mockResolvedValue(1) }));
jest.mock('@/lib/pushWeb', () => ({ estadoPushWeb: async () => 'nao_suportado', ligarPushWeb: jest.fn() }));
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);
jest.mock('expo-notifications', () => ({ setNotificationHandler: () => undefined }));

test('mostra os avisos, marca-os como vistos e abre o ecrã certo ao tocar', async () => {
  (meusAvisos as jest.Mock).mockResolvedValue([
    { id: 'a1', codigo: 'N16', titulo: 'Manda Bué', corpo: 'O teu pedido foi confirmado.', dados: { pedido_id: 'p1' },
      criado_em: new Date().toISOString(), vista_em: null },
    { id: 'a2', codigo: 'N3', titulo: 'Manda Bué', corpo: 'Ganhaste 600 Kz com o pedido do Rui.', dados: {},
      criado_em: new Date().toISOString(), vista_em: '2026-11-10T10:00:00Z' },
  ]);
  const ecra = renderRouter(
    { avisos: Avisos, 'pedido/[id]': () => <Text>Pedido</Text>, convida: () => <Text>Convida</Text> },
    { initialUrl: '/avisos' },
  );
  await waitFor(() => expect(ecra.getByText('O teu pedido foi confirmado.')).toBeTruthy());
  expect(ecra.getByText('Ganhaste 600 Kz com o pedido do Rui.')).toBeTruthy();
  expect(marcarAvisosVistos).toHaveBeenCalledWith();
  await act(async () => {
    fireEvent.press(ecra.getByText('O teu pedido foi confirmado.'));
  });
  expect(ecra.getPathname()).toBe('/pedido/p1');
});

test('sem avisos explica o que vai aparecer', async () => {
  (meusAvisos as jest.Mock).mockResolvedValue([]);
  const ecra = renderRouter({ avisos: Avisos }, { initialUrl: '/avisos' });
  await waitFor(() => expect(ecra.getByText(/Ainda não tens avisos/)).toBeTruthy());
});
