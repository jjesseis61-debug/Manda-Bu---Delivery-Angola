/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import Explorar from '@/app/explorar';

jest.mock('@/lib/sessao', () => ({ useSessao: () => ({ carregado: true, ligada: () => false, sessao: null, perfil: null }) }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
const mockCozinhas = jest.fn();
const mockGuardarZona = jest.fn(async (..._a: unknown[]) => undefined);
jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('@/lib/visitante', () => ({
  ...jest.requireActual('@/lib/visitante'),
  guardarZonaVisitante: (...a: unknown[]) => mockGuardarZona(...a),
  lerZonasVisitante: async () => [
    { id: 'z1', nome: 'Talatona', taxa: 500, entrega_gratis_acima: 10000 },
    { id: 'z2', nome: 'Viana', taxa: 0, entrega_gratis_acima: null },
  ],
  lerCozinhasVisitante: (...a: unknown[]) => mockCozinhas(...a),
}));

const rotas = { explorar: Explorar, 'visita/[cozinha]': () => <Text>Cardápio</Text> };

beforeEach(() => mockCozinhas.mockReset());

test('escolhe o bairro e vê as cozinhas da mais perto para a mais longe', async () => {
  mockCozinhas.mockResolvedValue([
    { id: 'a', nome: 'Cozinha Talatona', pratos: 4, distancia_km: 0.8, foto_url: null },
    { id: 'b', nome: 'Cozinha Maianga', pratos: 1, distancia_km: 12.3, foto_url: null },
  ]);
  const ecra = renderRouter(rotas, { initialUrl: '/explorar' });
  await act(async () => undefined);
  expect(ecra.getByText('Onde queres receber a comida?')).toBeTruthy();
  expect(ecra.getByText('Viana · entrega grátis')).toBeTruthy();
  fireEvent.press(ecra.getByText('Talatona · entrega 500 Kz'));
  await act(async () => undefined);
  expect(mockCozinhas).toHaveBeenCalledWith('z1');
  expect(mockGuardarZona).toHaveBeenCalledWith(expect.objectContaining({ id: 'z1', taxa: 500 }));
  expect(ecra.getByText('Entrega para Talatona: 500 Kz · grátis a partir de 10.000 Kz.')).toBeTruthy();
  expect(ecra.getByText('4 pratos · a 0,8 km')).toBeTruthy();
  fireEvent.press(ecra.getByLabelText('Ver o cardápio de Cozinha Maianga'));
  await act(async () => undefined);
  expect(ecra.getByText('Cardápio')).toBeTruthy();
});

test('uma só cozinha: abre logo o cardápio', async () => {
  mockCozinhas.mockResolvedValue([{ id: 'a', nome: 'Cozinha Talatona', pratos: 4, distancia_km: null, foto_url: null }]);
  const ecra = renderRouter(rotas, { initialUrl: '/explorar' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('O meu bairro não está na lista'));
  await act(async () => undefined);
  expect(mockCozinhas).toHaveBeenCalledWith(null);
  expect(ecra.getByText('Cardápio')).toBeTruthy();
});
