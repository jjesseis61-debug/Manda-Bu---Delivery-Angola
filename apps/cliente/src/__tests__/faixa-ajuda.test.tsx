/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import { FaixaConfianca } from '@/components/FaixaConfianca';

const mockAgente = { ligado: false };
const mockSessao = { perfil: { cliente_id: 'c' }, ligada: (c: string) => c === 'agente_atendimento' && mockAgente.ligado };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));

const rotas = {
  inicio: () => <FaixaConfianca />,
  ajuda: () => <Text>Assistente</Text>,
  contactos: () => <Text>Contactos</Text>,
};

test('com conta e o assistente desligado: «Problema? Resolvemos» abre os contactos', async () => {
  mockAgente.ligado = false;
  const ecra = renderRouter(rotas, { initialUrl: '/inicio' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByLabelText('Problema? Resolvemos. Falar connosco'));
  await act(async () => undefined);
  expect(ecra.getByText('Contactos')).toBeTruthy();
});

test('com o assistente ligado: abre a Ajuda', async () => {
  mockAgente.ligado = true;
  const ecra = renderRouter(rotas, { initialUrl: '/inicio' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByLabelText('Problema? Resolvemos. Falar connosco'));
  await act(async () => undefined);
  expect(ecra.getByText('Assistente')).toBeTruthy();
});
