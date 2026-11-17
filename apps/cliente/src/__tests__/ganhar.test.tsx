/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import Ganhar from '@/app/ganhar';

const mockSessao = { comConta: false };
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, ligada: () => false, sessao: mockSessao.comConta ? {} : null, perfil: mockSessao.comConta ? {} : null }),
}));
jest.mock('@/lib/supabase', () => ({ supabase: {} }));
const mockCodigo: { valor: string | null } = { valor: null };
jest.mock('@/lib/convite', () => ({ lerCodigoPendente: async () => mockCodigo.valor }));
const mockGuardarDestino = jest.fn(async (..._a: unknown[]) => undefined);
const mockRegras: { valor: unknown } = { valor: null };
jest.mock('@/lib/visitante', () => ({
  guardarDestino: (...a: unknown[]) => mockGuardarDestino(...a),
  lerRegrasConvida: async () => mockRegras.valor,
}));

const REGRAS = {
  ganho_por_pedido: 200, duracao_dias: 90, comissao_primeiro_pedido: false, desconto_indicado: 500, desconto_subtotal_minimo: 2000,
  levantamento_minimo: 5000, validade_saldo_meses: 12, limite_verificacao_semanal: 20000, bonus_boas_vindas: 300,
  limiar_embaixador: 5, limiar_ouro: 20, ganho_por_pedido_embaixador: 300, ganho_por_pedido_ouro: 400,
};
const rotas = { ganhar: Ganhar, entrar: () => <Text>Entrar</Text>, convida: () => <Text>Convida</Text>, explorar: () => <Text>Explorar</Text> };

beforeEach(() => {
  mockSessao.comConta = false;
  mockCodigo.valor = null;
  mockRegras.valor = REGRAS;
  mockGuardarDestino.mockClear();
});

test('o visitante vê as regras e os níveis, mas sem código', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/ganhar' });
  await act(async () => undefined);
  expect(ecra.getByText('Ganha 200 Kz por cada pedido dos teus amigos 🎉')).toBeTruthy();
  expect(ecra.getByText('3. Ganhas 200 Kz por cada pedido dele, a partir do 2.º.')).toBeTruthy();
  expect(ecra.getByText(/Bónus de boas-vindas: \+300 Kz/)).toBeTruthy();
  expect(ecra.getByText('• Embaixador (5 amigos ativos): 300 Kz por pedido.')).toBeTruthy();
  expect(ecra.getByText('🔒 O teu código aparece quando criares conta.')).toBeTruthy();
  expect(ecra.queryByText(/MB-\d/)).toBeNull();
});

test('«Criar conta e começar a ganhar» guarda o Convida como destino e vai entrar', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/ganhar' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Criar conta e começar a ganhar'));
  await act(async () => undefined);
  expect(mockGuardarDestino).toHaveBeenCalledWith('/convida');
  expect(ecra.getByText('Entrar')).toBeTruthy();
});

test('chegou por um convite: mostra o desconto que já tem', async () => {
  mockCodigo.valor = 'MB-1234';
  const ecra = renderRouter(rotas, { initialUrl: '/ganhar' });
  await act(async () => undefined);
  expect(ecra.getByText('🎁 Já tens 500 Kz de desconto no teu 1.º pedido, oferta de quem te convidou.')).toBeTruthy();
});

test('programa desligado: explica e não pede conta', async () => {
  mockRegras.valor = null;
  const ecra = renderRouter(rotas, { initialUrl: '/ganhar' });
  await act(async () => undefined);
  expect(ecra.getByText('O programa Convida e Ganha não está disponível de momento.')).toBeTruthy();
  expect(ecra.queryByText('Criar conta e começar a ganhar')).toBeNull();
});

test('quem já tem conta vai para o Convida verdadeiro', async () => {
  mockSessao.comConta = true;
  const ecra = renderRouter(rotas, { initialUrl: '/ganhar' });
  await act(async () => undefined);
  expect(ecra.getByText('Convida')).toBeTruthy();
});
