/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import Registo from '@/app/registo';

const mockCodigo: { valor: string | null } = { valor: null };
jest.mock('@/lib/convite', () => ({ lerCodigoPendente: async () => mockCodigo.valor, limparCodigoPendente: async () => undefined }));
const mockSessao = {
  sessao: { user: { id: 'u' } },
  perfil: null,
  parametros: { desconto_indicado: 1000, desconto_subtotal_minimo: 5000 },
  ligada: () => true,
  actualizar: async () => undefined,
};
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));
const mockRegistar = jest.fn(async (..._a: unknown[]) => undefined);
const mockLigar = jest.fn(async (..._a: unknown[]) => 'ok');
jest.mock('@/lib/api', () => ({
  meuPerfil: async () => null,
  registarCliente: (...a: unknown[]) => mockRegistar(...a),
  ligarIndicacao: (...a: unknown[]) => mockLigar(...a),
  descontoGarantido: async () => 1000,
}));

const rotas = { registo: Registo, index: () => <Text>Porta</Text> };

beforeEach(() => {
  mockCodigo.valor = null;
  mockRegistar.mockClear();
  mockLigar.mockClear();
  mockLigar.mockResolvedValue('ok');
});

test('código vindo de um link: aparece aplicado e não se pode escrever outro', async () => {
  mockCodigo.valor = 'MB-1234';
  const ecra = renderRouter(rotas, { initialUrl: '/registo' });
  await act(async () => undefined);
  expect(ecra.getByText('🎁 Convite aplicado ✓')).toBeTruthy();
  expect(ecra.queryByPlaceholderText('1234')).toBeNull();
  fireEvent.changeText(ecra.getByPlaceholderText('O teu nome'), 'Ana');
  fireEvent.press(ecra.getByText('Criar conta'));
  await act(async () => undefined);
  expect(mockLigar).toHaveBeenCalledWith('MB1234');
});

test('«Continuar sem convite» tira o código (e não deixa pôr outro)', async () => {
  mockCodigo.valor = 'MB-1234';
  const ecra = renderRouter(rotas, { initialUrl: '/registo' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Continuar sem convite'));
  expect(ecra.queryByText('🎁 Convite aplicado ✓')).toBeNull();
  expect(ecra.queryByPlaceholderText('1234')).toBeNull();
  fireEvent.changeText(ecra.getByPlaceholderText('O teu nome'), 'Ana');
  fireEvent.press(ecra.getByText('Criar conta'));
  await act(async () => undefined);
  expect(mockLigar).not.toHaveBeenCalled();
});

test('sem link: o campo do código fica livre', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/registo' });
  await act(async () => undefined);
  expect(ecra.getByPlaceholderText('1234')).toBeTruthy();
});

test('sem link: basta escrever o número (o «MB» já está no campo)', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/registo' });
  await act(async () => undefined);
  fireEvent.changeText(ecra.getByPlaceholderText('O teu nome'), 'Ana');
  fireEvent.changeText(ecra.getByLabelText('Código (opcional)'), '4812');
  fireEvent.press(ecra.getByText('Criar conta'));
  await act(async () => undefined);
  expect(mockLigar).toHaveBeenCalledWith('MB4812');
});

test('o servidor recusa o código do link: só então se pode escrever outro', async () => {
  mockCodigo.valor = 'MB-1234';
  mockLigar.mockResolvedValueOnce('codigo_inexistente');
  const ecra = renderRouter(rotas, { initialUrl: '/registo' });
  await act(async () => undefined);
  fireEvent.changeText(ecra.getByPlaceholderText('O teu nome'), 'Ana');
  fireEvent.press(ecra.getByText('Criar conta'));
  await act(async () => undefined);
  fireEvent.changeText(ecra.getByLabelText('Outro código de convite (opcional)'), 'MB-5678');
  fireEvent.press(ecra.getByText('Usar este código'));
  await act(async () => undefined);
  expect(mockLigar).toHaveBeenLastCalledWith('MB5678');
  expect(ecra.getByText('Código aceite.')).toBeTruthy();
});
