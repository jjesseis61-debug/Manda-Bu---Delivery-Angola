/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Zonas from '@/app/zonas';
import { guardarZonaEntrega, lerZonasEntrega } from '@/lib/api';

jest.mock('@/lib/api', () => ({ lerZonasEntrega: jest.fn(), guardarZonaEntrega: jest.fn(), apagarZonaEntrega: jest.fn() }));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1' }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

test('sem zonas avisa e cria a primeira com o bairro e a taxa', async () => {
  (lerZonasEntrega as jest.Mock).mockResolvedValue([]);
  const ecra = renderRouter({ zonas: Zonas }, { initialUrl: '/zonas' });
  await waitFor(() => expect(ecra.getByText(/Ainda não há zonas de entrega/)).toBeTruthy());
  fireEvent.press(ecra.getByText('Nova zona de entrega'));
  const [nome, taxa] = ecra.getAllByDisplayValue('');
  fireEvent.changeText(nome, ' Talatona ');
  fireEvent.changeText(taxa, '500 Kz');
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar zona'));
  });
  expect(guardarZonaEntrega).toHaveBeenCalledWith({
    id: undefined,
    nome: 'Talatona',
    taxa: 500,
    tipo: 'Própria',
    centro_lat: null,
    centro_lng: null,
  });
});
