/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import CardapioVisita from '@/app/visita/[cozinha]';

const mockSessao = { comConta: false };
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, ligada: () => false, sessao: mockSessao.comConta ? {} : null, perfil: mockSessao.comConta ? {} : null }),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
const mockGuardarDestino = jest.fn(async () => undefined);
const prato = (id: string, nome: string, preco: number, extra: object = {}) => ({
  id, nome, preco, descricao: null, categoria: null, foto_url: null, do_dia: false, cozinha_id: 'v', prato_base_id: null, pedidos_mes: 0,
  esgotado: false, montar: false, ...extra,
});
jest.mock('@/lib/visitante', () => ({
  guardarDestino: (...a: unknown[]) => mockGuardarDestino(...(a as [])),
  lerCardapioVisitante: async () => ({
    cozinha: { id: 'v', nome: 'Viana' },
    pratos: [prato('m', 'Muamba', 2500), prato('s', 'Strogonoff', 3000, { montar: true }), prato('c', 'Calulu', 2000, { esgotado: true })],
  }),
}));
const mockAdicionar = jest.fn();
const mockDefinirCozinha = jest.fn();
const mockCarrinho: { linhas: unknown[]; cozinha: { id: string; nome: string } | null } = { linhas: [], cozinha: null };
jest.mock('@/lib/carrinho', () => ({
  useCarrinho: () => ({
    linhas: mockCarrinho.linhas, quantidade: mockCarrinho.linhas.length, cozinhaActual: mockCarrinho.cozinha,
    adicionar: mockAdicionar, definirCozinha: mockDefinirCozinha, alterar: jest.fn(),
  }),
}));

const rotas = {
  'visita/[cozinha]': CardapioVisita,
  'montar/[id]': () => <Text>Montar</Text>,
  entrar: () => <Text>Entrar</Text>,
  explorar: () => <Text>Explorar</Text>,
  inicio: () => <Text>Início</Text>,
};

beforeEach(() => {
  mockAdicionar.mockClear();
  mockDefinirCozinha.mockClear();
  mockCarrinho.linhas = [];
  mockCarrinho.cozinha = null;
  mockSessao.comConta = false;
});

test('o visitante vê o cardápio da cozinha e adiciona um prato simples', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/visita/v' });
  await act(async () => undefined);
  expect(ecra.getByText('Muamba')).toBeTruthy();
  expect(ecra.getByText('Esgotado')).toBeTruthy();
  fireEvent.press(ecra.getByLabelText('Muamba, 2.500 Kz'));
  expect(mockDefinirCozinha).toHaveBeenCalledWith({ id: 'v', nome: 'Viana' });
  expect(mockAdicionar).toHaveBeenCalledWith(expect.objectContaining({ id: 'm', preco: 2500 }));
  expect(mockAdicionar.mock.calls[0][0]).not.toHaveProperty('montar');
});

test('prato com opções abre o ecrã de montar', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/visita/v' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByLabelText('Strogonoff, 3.000 Kz'));
  await act(async () => undefined);
  expect(ecra.getByText('Montar')).toBeTruthy();
});

test('«Pedir» só então pede o número, guarda o carrinho como destino e vai entrar', async () => {
  mockCarrinho.cozinha = { id: 'v', nome: 'Viana' };
  mockCarrinho.linhas = [{ chave: 'm', item: prato('m', 'Muamba', 2500), qtd: 2, opcoes: [], tirados: [] }];
  const ecra = renderRouter(rotas, { initialUrl: '/visita/v' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Pedir · 5.000 Kz'));
  expect(ecra.getByText('Só falta o teu número')).toBeTruthy();
  fireEvent.press(ecra.getByText('Continuar'));
  await act(async () => undefined);
  expect(mockGuardarDestino).toHaveBeenCalledWith('/carrinho');
  expect(ecra.getByText('Entrar')).toBeTruthy();
});

test('quem já tem conta vai para o início', async () => {
  mockSessao.comConta = true;
  const ecra = renderRouter(rotas, { initialUrl: '/visita/v' });
  await act(async () => undefined);
  expect(ecra.getByText('Início')).toBeTruthy();
});
