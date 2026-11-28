import * as LocalAuthentication from 'expo-local-authentication';

import { definirPin, esperaPorFalhas, estaActivo, estadoFalhas, removerCadeado, usaBiometria, validarPin, verificarPin } from '../cadeado';

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
  hasHardwareAsync: jest.fn().mockResolvedValue(true),
  isEnrolledAsync: jest.fn().mockResolvedValue(true),
  authenticateAsync: jest.fn(),
}));

beforeEach(() => mockCofre.clear());

test('códigos fáceis ou fora do tamanho são recusados', () => {
  expect(validarPin('123')).toMatch(/4 a 6/);
  expect(validarPin('1234567')).toMatch(/4 a 6/);
  expect(validarPin('12a4')).toMatch(/4 a 6/);
  expect(validarPin('1111')).toMatch(/repetir/);
  expect(validarPin('1234')).toMatch(/seguidos/);
  expect(validarPin('98765')).toMatch(/seguidos/);
  expect(validarPin('2580')).toBeNull();
  expect(validarPin('190427')).toBeNull();
});

test('o PIN nunca fica guardado em claro; certo abre, errado conta falhas', async () => {
  await definirPin('2580', false);
  expect(await estaActivo()).toBe(true);
  expect([...mockCofre.values()].some((v) => v === '2580')).toBe(false);
  expect(await verificarPin('2580')).toEqual({ ok: true });
  const r = await verificarPin('0000');
  expect(r).toMatchObject({ ok: false, falhas: 1, esgotado: false });
});

test('atraso progressivo e, ao fim de 10, só por SMS', async () => {
  expect(esperaPorFalhas(4)).toBe(0);
  expect(esperaPorFalhas(5)).toBe(30_000);
  expect(esperaPorFalhas(6)).toBe(60_000);
  expect(esperaPorFalhas(50)).toBe(300_000);
  await definirPin('2580', false);
  let t = 1_000_000;
  for (let i = 0; i < 5; i++) {
    await verificarPin('9999', t);
    t += 1;
  }
  // Durante a espera, nem o código certo passa
  expect(await verificarPin('2580', t)).toMatchObject({ ok: false });
  expect((await estadoFalhas(t)).esperaMs).toBeGreaterThan(0);
  // Depois da espera, o certo passa e limpa as falhas
  expect(await verificarPin('2580', t + 31_000)).toEqual({ ok: true });
  expect((await estadoFalhas(t + 31_000)).falhas).toBe(0);
  for (let i = 0; i < 10; i++) {
    await verificarPin('9999', t + 31_000 + i * 400_000);
  }
  expect(await verificarPin('2580', t + 10_000_000)).toMatchObject({ ok: false, esgotado: true });
});

test('biometria só conta se estiver ligada e o aparelho ainda a tiver', async () => {
  await definirPin('2580', true);
  expect(await usaBiometria()).toBe(true);
  (LocalAuthentication.isEnrolledAsync as jest.Mock).mockResolvedValueOnce(false);
  expect(await usaBiometria()).toBe(false);
});

test('remover apaga tudo', async () => {
  await definirPin('2580', true);
  await removerCadeado();
  expect(mockCofre.size).toBe(0);
  expect(await estaActivo()).toBe(false);
});
