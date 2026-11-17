/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import Explorar from '@/app/explorar';

jest.mock('@/lib/sessao', () => ({ useSessao: () => ({ carregado: true, ligada: () => false, sessao: null, perfil: null }) }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
const mockCozinhas = jest.fn();
jest.mock('@/lib/visitante', () => ({
  lerZonasVisitante: async () => [{ id: 'z1', nome: 'Talatona' }, { id: 'z2', nome: 'Viana' }],
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
  fireEvent.press(ecra.getByText('Talatona'));
  await act(async () => undefined);
  expect(mockCozinhas).toHaveBeenCalledWith('z1');
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
