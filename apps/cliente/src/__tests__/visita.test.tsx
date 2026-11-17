/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Linking, Text } from 'react-native';

import CardapioVisita from '@/app/visita/[cozinha]';

const mockSessao = { comConta: false };
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, ligada: () => false, sessao: mockSessao.comConta ? {} : null, perfil: mockSessao.comConta ? {} : null }),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
jest.mock('@/lib/api', () => ({ meuPerfil: async () => null }));
const mockGuardarDestino = jest.fn(async () => undefined);
const prato = (id: string, nome: string, preco: number, extra: object = {}) => ({
  id, nome, preco, descricao: null, categoria: null, foto_url: null, do_dia: false, cozinha_id: 'v', prato_base_id: null, pedidos_mes: 0,
  esgotado: false, montar: false, ...extra,
});
jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
const mockZona: { valor: unknown } = { valor: null };
jest.mock('@/lib/empresa', () => ({ CONTACTO_AJUDA: { whatsapp: '958077592', telefone: null, horario: null, email: null, morada: null } }));
jest.mock('@/lib/visitante', () => ({
  entregaVisitante: jest.requireActual('@/lib/visitante').entregaVisitante,
  lerZonaVisitante: async () => mockZona.valor,
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
  mockZona.valor = null;
});

test('o visitante vê o cardápio da cozinha e adiciona um prato simples', async () => {
  const ecra = renderRouter(rotas, { initialUrl: '/visita/v' });
  await act(async () => undefined);
  expect(ecra.queryByText('Pedir ›')).toBeNull(); // sem pratos, sem barra
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

test('«Pedir» só então pede o número, numa folha por cima do cardápio', async () => {
  mockCarrinho.cozinha = { id: 'v', nome: 'Viana' };
  mockCarrinho.linhas = [{ chave: 'm', item: prato('m', 'Muamba', 2500), qtd: 2, opcoes: [], tirados: [] }];
  const ecra = renderRouter(rotas, { initialUrl: '/visita/v' });
  await act(async () => undefined);
  // Barra fixa do carrinho, sempre à vista
  expect(ecra.getByText('🛒 2 pratos · 5.000 Kz')).toBeTruthy();
  fireEvent.press(ecra.getByText('Pedir ›'));
  // A folha de login abre por cima do cardápio, já com o campo do número
  expect(ecra.getByText('Só falta o teu número')).toBeTruthy();
  expect(ecra.getByText('Receber código')).toBeTruthy();
});

test('quem já tem conta vai para o início', async () => {
  mockSessao.comConta = true;
  const ecra = renderRouter(rotas, { initialUrl: '/visita/v' });
  await act(async () => undefined);
  expect(ecra.getByText('Início')).toBeTruthy();
});

test('com o bairro escolhido mostra a entrega e quanto falta para ser grátis', async () => {
  mockZona.valor = { id: 'z1', nome: 'Talatona', taxa: 500, entrega_gratis_acima: 10000 };
  mockCarrinho.cozinha = { id: 'v', nome: 'Viana' };
  mockCarrinho.linhas = [{ chave: 'm', item: prato('m', 'Muamba', 2500), qtd: 2, opcoes: [], tirados: [] }];
  const ecra = renderRouter(rotas, { initialUrl: '/visita/v' });
  await act(async () => undefined);
  expect(ecra.getByText('Entrega para Talatona: 500 Kz')).toBeTruthy();
  expect(ecra.getByText(/Junta mais 5.000 Kz e a entrega fica grátis/)).toBeTruthy();
  expect(ecra.getByText('Total estimado: 5.500 Kz')).toBeTruthy();
  expect(ecra.getByText('🛒 2 pratos · 5.500 Kz')).toBeTruthy();
  expect(ecra.getByText('🛵 Entrega para Talatona: 500 Kz · grátis a partir de 10.000 Kz')).toBeTruthy();
});

test('«Problema? Resolvemos» abre o WhatsApp de apoio ao visitante', async () => {
  const mockAbrir = jest.spyOn(Linking, 'openURL').mockResolvedValue(true);
  const ecra = renderRouter(rotas, { initialUrl: '/visita/v' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByLabelText('Problema? Resolvemos. Falar connosco'));
  expect(mockAbrir).toHaveBeenCalledWith('https://wa.me/244958077592');
});
