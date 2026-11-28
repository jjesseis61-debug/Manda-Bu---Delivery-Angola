/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { useState } from 'react';
import { Pressable, Text } from 'react-native';

import { LoginNecessario } from '@/components/LoginNecessario';

jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
const mockActualizar = jest.fn(async () => undefined);
jest.mock('@/lib/sessao', () => ({ useSessao: () => ({ actualizar: mockActualizar }) }));
const mockOtp = jest.fn(async (..._a: unknown[]) => ({ error: null }));
const mockVerificar = jest.fn(async (..._a: unknown[]) => ({ error: null }));
jest.mock('@/lib/supabase', () => ({
  supabase: {
    auth: { signInWithOtp: (...a: unknown[]) => mockOtp(...a), verifyOtp: (...a: unknown[]) => mockVerificar(...a) },
    rpc: () => Promise.resolve({ data: null, error: null }),
  },
}));
const mockPerfil: { valor: unknown } = { valor: { cliente_id: 'c1' } };
jest.mock('@/lib/api', () => ({ meuPerfil: async () => mockPerfil.valor }));
const mockGuardarDestino = jest.fn(async (..._a: unknown[]) => undefined);
jest.mock('@/lib/visitante', () => ({ guardarDestino: (...a: unknown[]) => mockGuardarDestino(...a) }));

function Carrinho() {
  const [aberto, setAberto] = useState(true);
  return (
    <>
      <Text>{aberto ? 'Carrinho (folha aberta)' : 'Carrinho'}</Text>
      <Pressable onPress={() => setAberto(true)}>
        <Text>Pedir</Text>
      </Pressable>
      <LoginNecessario visivel={aberto} titulo="Só falta o teu número" motivo="Para a cozinha te entregar." destino="/carrinho" aoFechar={() => setAberto(false)} />
    </>
  );
}
const rotas = { carrinho: Carrinho, registo: () => <Text>Registo</Text> };

beforeEach(() => {
  mockOtp.mockClear();
  mockVerificar.mockClear();
  mockGuardarDestino.mockClear();
  mockPerfil.valor = { cliente_id: 'c1' };
});

async function entrarComCodigo(ecra: ReturnType<typeof renderRouter>) {
  fireEvent.changeText(ecra.getByPlaceholderText('923 456 789'), '923456789');
  fireEvent.press(ecra.getByText('Receber código'));
  await act(async () => undefined);
  expect(mockOtp).toHaveBeenCalledWith({ phone: '+244923456789' });
  expect(ecra.getByText('Escreve o código que enviámos para +244923456789.')).toBeTruthy();
  fireEvent.changeText(ecra.getAllByLabelText('Código de confirmação')[1], '123456');
  await act(async () => undefined);
}

test('número e código na folha: quem já tem conta fica no mesmo ecrã', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/carrinho' });
  await act(async () => undefined);
  await entrarComCodigo(ecra);
  expect(mockVerificar).toHaveBeenCalledWith({ phone: '+244923456789', token: '123456', type: 'sms' });
  expect(mockActualizar).toHaveBeenCalled();
  expect(ecra.getByText('Carrinho')).toBeTruthy(); // a folha fechou e continua no carrinho
});

test('cliente novo: segue para o registo (só o nome) e guarda o destino', async () => {
  mockPerfil.valor = null;
  const ecra = renderRouter(rotas, { initialUrl: '/carrinho' });
  await act(async () => undefined);
  await entrarComCodigo(ecra);
  expect(mockGuardarDestino).toHaveBeenCalledWith('/carrinho');
  expect(ecra.getByText('Registo')).toBeTruthy();
});

test('a folha diz para que serve o número', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/carrinho' });
  await act(async () => undefined);
  expect(ecra.getByText('Só usamos o teu número para os teus pedidos.')).toBeTruthy();
});

test('número inválido: explica e não envia', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/carrinho' });
  await act(async () => undefined);
  fireEvent.changeText(ecra.getByPlaceholderText('923 456 789'), '12');
  fireEvent.press(ecra.getByText('Receber código'));
  await act(async () => undefined);
  expect(mockOtp).not.toHaveBeenCalled();
  expect(ecra.getByText('Escreve um número angolano com 9 dígitos (ex.: 923 456 789).')).toBeTruthy();
});

test('✕ fecha a folha sem castigo', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/carrinho' });
  await act(async () => undefined);
  fireEvent.press(ecra.getAllByLabelText('Fechar')[1]);
  expect(ecra.getByText('Carrinho')).toBeTruthy();
});
