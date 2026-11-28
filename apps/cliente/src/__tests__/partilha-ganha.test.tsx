/// <reference types="jest" />
import AsyncStorage from '@react-native-async-storage/async-storage';
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';

import { BotaoPartilhar } from '@/components/BotaoPartilhar';
import { tirarPartilhaPendente } from '@/lib/partilhaPendente';

jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('@expo/vector-icons/Ionicons', () => () => null);
const mockSessao: { comConta: boolean } = { comConta: false };
const mockValor = {
  get perfil() {
    return mockSessao.comConta ? { cliente_id: 'c', codigo: 'MB-4812' } : null;
  },
  get parametros() {
    return mockSessao.comConta ? { desconto_indicado: 1000, desconto_subtotal_minimo: 5000 } : null;
  },
  ligada: () => true,
  actualizar: async () => undefined,
};
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockValor }));
jest.mock('@/lib/supabase', () => ({ supabase: {} }));
jest.mock('@/lib/api', () => ({ meuPerfil: async () => null }));
const mockPartilhar = jest.fn();
jest.mock('@/lib/partilha', () => ({
  ...jest.requireActual('@/lib/partilha'),
  partilharPrato: (...a: unknown[]) => mockPartilhar(...a),
}));
const mockRegras: { valor: unknown } = { valor: null };
jest.mock('@/lib/visitante', () => ({
  ...jest.requireActual('@/lib/visitante'),
  lerRegrasConvida: async () => mockRegras.valor,
}));

const REGRAS = { desconto_indicado: 1000, ganho_por_pedido: 600, comissao_primeiro_pedido: false };
const rotas = { prato: () => <BotaoPartilhar nome="Bitoque" id="p1" /> };

beforeEach(async () => {
  await AsyncStorage.clear();
  mockPartilhar.mockClear();
  mockSessao.comConta = false;
  mockRegras.valor = REGRAS;
});

test('sem conta: antes de partilhar propõe «Partilha e ganha» com os valores reais', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/prato' });
  fireEvent.press(ecra.getByLabelText('Partilhar Bitoque no WhatsApp'));
  await act(async () => undefined);
  expect(ecra.getByText('🎁 Partilha e ganha')).toBeTruthy();
  expect(ecra.getByText(/o teu amigo ganha/)).toBeTruthy();
  expect(mockPartilhar).not.toHaveBeenCalled();
});

test('«Partilhar sem código» partilha logo, sem código', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/prato' });
  fireEvent.press(ecra.getByLabelText('Partilhar Bitoque no WhatsApp'));
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Partilhar sem código'));
  expect(mockPartilhar).toHaveBeenCalledWith('Bitoque', 'p1', null);
});

test('«Entrar e partilhar» guarda a partilha para continuar depois de entrar e abre o login', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/prato' });
  fireEvent.press(ecra.getByLabelText('Partilhar Bitoque no WhatsApp'));
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Entrar e partilhar'));
  await act(async () => undefined);
  expect(ecra.getByText('Entra para partilhar com o teu código')).toBeTruthy();
  expect(await tirarPartilhaPendente()).toEqual({ nome: 'Bitoque', id: 'p1' });
});

test('o aviso aparece no máximo uma vez por dia', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/prato' });
  fireEvent.press(ecra.getByLabelText('Partilhar Bitoque no WhatsApp'));
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Partilhar sem código'));
  mockPartilhar.mockClear();
  fireEvent.press(ecra.getByLabelText('Partilhar Bitoque no WhatsApp'));
  await act(async () => undefined);
  expect(mockPartilhar).toHaveBeenCalledWith('Bitoque', 'p1', null);
});

test('com conta: partilha logo com o código, sem aviso', async () => {
  mockSessao.comConta = true;
  const ecra = renderRouter(rotas, { initialUrl: '/prato' });
  fireEvent.press(ecra.getByLabelText('Partilhar Bitoque no WhatsApp'));
  await act(async () => undefined);
  expect(mockPartilhar).toHaveBeenCalledWith('Bitoque', 'p1', { codigo: 'MB-4812', desconto: 1000, minimo: 5000 });
  expect(ecra.queryByText('🎁 Partilha e ganha')).toBeNull();
});

test('Convida desligado: partilha sem aviso', async () => {
  mockRegras.valor = null;
  const ecra = renderRouter(rotas, { initialUrl: '/prato' });
  fireEvent.press(ecra.getByLabelText('Partilhar Bitoque no WhatsApp'));
  await act(async () => undefined);
  expect(mockPartilhar).toHaveBeenCalledWith('Bitoque', 'p1', null);
});
