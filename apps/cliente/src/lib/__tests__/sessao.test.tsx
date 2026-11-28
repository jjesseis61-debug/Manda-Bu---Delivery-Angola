/// <reference types="jest" />
import { act, render } from '@testing-library/react-native';
import { useEffect } from 'react';
import { Text } from 'react-native';

const mockSessaoActual: { valor: unknown } = { valor: null };
let mockAoMudar: ((e: string, s: unknown) => void) | null = null;
jest.mock('../supabase', () => ({
  supabase: {
    auth: {
      getSession: async () => ({ data: { session: mockSessaoActual.valor } }),
      onAuthStateChange: (cb: (e: string, s: unknown) => void) => {
        mockAoMudar = cb;
        return { data: { subscription: { unsubscribe: () => undefined } } };
      },
    },
    rpc: async () => ({ data: { multi_cozinha: true }, error: null }),
  },
}));
jest.mock('../api', () => ({
  meuPerfil: async () => ({ cliente_id: 'c1', primeiro_nome: 'Ana' }),
  lerConfiguracao: async () => ({ parametros: {}, funcionalidades: { indicacao: true } }),
}));

import { SessaoProvider, useSessao } from '../sessao';

let mockActualizar: (() => Promise<void>) | null = null;
function Ver() {
  const { perfil, actualizar } = useSessao();
  // Guarda o actualizar do primeiro desenho (ainda sem sessão), como a folha de login fazia
  useEffect(() => {
    if (!mockActualizar) mockActualizar = actualizar;
  }, [actualizar]);
  return <Text>{perfil ? `perfil:${(perfil as { primeiro_nome: string }).primeiro_nome}` : 'sem perfil'}</Text>;
}

test('depois de entrar, «actualizar» de um desenho antigo não apaga o perfil (regressão: ia para Criar conta)', async () => {
  const ecra = render(
    <SessaoProvider>
      <Ver />
    </SessaoProvider>,
  );
  await act(async () => undefined);
  expect(ecra.getByText('sem perfil')).toBeTruthy();

  // Entra (o código foi aceite): a sessão passa a existir
  mockSessaoActual.valor = { user: { id: 'u1' } };
  await act(async () => {
    mockAoMudar?.('SIGNED_IN', mockSessaoActual.valor);
  });
  expect(ecra.getByText('perfil:Ana')).toBeTruthy();

  // A folha chamava o actualizar que tinha guardado de antes do login
  await act(async () => {
    await mockActualizar?.();
  });
  expect(ecra.getByText('perfil:Ana')).toBeTruthy();
});
