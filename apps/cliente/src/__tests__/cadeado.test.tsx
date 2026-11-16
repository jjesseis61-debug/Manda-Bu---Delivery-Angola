/// <reference types="jest" />
import { act, fireEvent, render, waitFor } from '@testing-library/react-native';
import { Text } from 'react-native';

import { EcraCadeado } from '@/components/EcraCadeado';
import { definirPin } from '@/lib/cadeado';
import { CadeadoProvider, useCadeado } from '@/lib/cadeadoContexto';

const mockCofre = new Map<string, string>();
jest.mock('expo-secure-store', () => ({
  getItemAsync: async (k: string) => mockCofre.get(k) ?? null,
  setItemAsync: async (k: string, v: string) => void mockCofre.set(k, v),
  deleteItemAsync: async (k: string) => void mockCofre.delete(k),
}));
jest.mock('expo-crypto', () => ({
  CryptoDigestAlgorithm: { SHA512: 'SHA-512' },
  digestStringAsync: async (_a: string, s: string) => `h(${s})`,
  getRandomBytes: (n: number) => new Uint8Array(n).fill(7),
}));
jest.mock('expo-local-authentication', () => ({
  hasHardwareAsync: async () => false,
  isEnrolledAsync: async () => false,
  authenticateAsync: jest.fn(),
}));
const mockSair = jest.fn();
const mockSessao = { carregado: true, sessao: { user: { id: 'u' } } as unknown, sair: mockSair };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

let resultado: boolean | null = null;
function Conteudo() {
  const { estado, confirmar } = useCadeado();
  return (
    <>
      <Text>Estado: {estado}</Text>
      <Text
        onPress={async () => {
          resultado = await confirmar('Confirma o levantamento');
        }}>
        Levantar
      </Text>
    </>
  );
}

function abrir() {
  return render(
    <CadeadoProvider>
      <Conteudo />
      <EcraCadeado />
    </CadeadoProvider>,
  );
}

beforeEach(() => {
  mockCofre.clear();
  resultado = null;
  mockSessao.sessao = { user: { id: 'u' } };
});

// O runner do GitHub é mais lento: dá margem às esperas (o hash do código e o cofre são assíncronos)
const ESPERA = 5000;

test('sem cadeado: abre logo e as acções não pedem código', async () => {
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Estado: aberto')).toBeTruthy(), { timeout: ESPERA });
  await act(async () => {
    fireEvent.press(ecra.getByText('Levantar'));
  });
  expect(resultado).toBe(true);
});

test('com cadeado: abre bloqueado, código errado avisa, o certo desbloqueia', async () => {
  await definirPin('2580', false);
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Introduz o teu código')).toBeTruthy(), { timeout: ESPERA });
  await act(async () => {
    fireEvent.changeText(ecra.getByLabelText('Código'), '1357');
  });
  await waitFor(() => expect(ecra.getByText(/Código errado \(1 de 10/)).toBeTruthy(), { timeout: ESPERA });
  await act(async () => {
    fireEvent.changeText(ecra.getByLabelText('Código'), '2580');
  });
  await waitFor(() => expect(ecra.getByText('Estado: aberto')).toBeTruthy(), { timeout: ESPERA });
});

test('acção sensível pede o código; cancelar não executa', async () => {
  await definirPin('2580', false);
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Introduz o teu código')).toBeTruthy(), { timeout: ESPERA });
  await act(async () => {
    fireEvent.changeText(ecra.getByLabelText('Código'), '2580');
  });
  await waitFor(() => expect(ecra.getByText('Estado: aberto')).toBeTruthy(), { timeout: ESPERA });
  await act(async () => {
    fireEvent.press(ecra.getByText('Levantar'));
  });
  await waitFor(() => expect(ecra.getByText('Confirma o levantamento')).toBeTruthy(), { timeout: ESPERA });
  await act(async () => {
    fireEvent.press(ecra.getByText('Cancelar'));
  });
  expect(resultado).toBe(false);
});

test('sem sessão (saiu da conta): o cadeado é apagado', async () => {
  await definirPin('2580', false);
  mockSessao.sessao = null;
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Estado: aberto')).toBeTruthy(), { timeout: ESPERA });
  expect(mockCofre.size).toBe(0);
});
