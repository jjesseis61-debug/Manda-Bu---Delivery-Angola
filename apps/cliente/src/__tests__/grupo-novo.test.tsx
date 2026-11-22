/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import NovoGrupo from '@/app/grupo/novo';

jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
const mockPerfil: { tipo: string } = { tipo: 'Particular' };
const mockSessao = { carregado: true, perfil: { cliente_id: 'c1', get tipo() { return mockPerfil.tipo; } }, ligada: (c: string) => c === 'pedidos_grupo' };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
jest.mock('@/lib/carrinho', () => ({ useCarrinho: () => ({ cozinha: null }) }));
const mockEnderecos = jest.fn();
const mockCriar = jest.fn(async (..._a: unknown[]) => 'G-ABC123');
jest.mock('@/lib/api', () => ({
  lerEnderecos: (...a: unknown[]) => mockEnderecos(...a),
  criarGrupo: (...a: unknown[]) => mockCriar(...a),
}));

const casa = { id: 'e1', nome: 'Casa', principal: true, ponto_entrega_id: 'pc', pontos_entrega: { id: 'pc', tipo: 'residencial', referencia: '500 casas', zona_id: 'z', zonas: { nome: 'Vila de Viana' } } };
const trabalho = { id: 'e2', nome: 'Trabalho', principal: false, ponto_entrega_id: 'pt', pontos_entrega: { id: 'pt', tipo: 'empresa', referencia: 'RNA', zona_id: 'z', zonas: { nome: 'Viana' } } };
const abrir = () => renderRouter({ 'grupo/novo': NovoGrupo, 'grupo/[codigo]': () => <Text>Grupo criado</Text> }, { initialUrl: '/grupo/novo' });

// Manhã em Luanda: há horas de entrega para escolher (à noite a lista fica vazia)
beforeAll(() => {
  jest.useFakeTimers({ now: new Date('2026-11-22T08:00:00Z'), doNotFake: ['nextTick', 'setImmediate', 'setTimeout', 'setInterval', 'clearTimeout', 'clearInterval', 'queueMicrotask', 'requestAnimationFrame', 'cancelAnimationFrame', 'performance', 'hrtime'] });
});
afterAll(() => jest.useRealTimers());

beforeEach(() => {
  mockCriar.mockClear();
  mockPerfil.tipo = 'Particular';
});

test('só com endereços de casa: o grupo é de família e cada um paga a sua parte', async () => {
  mockEnderecos.mockResolvedValue([casa]);
  const ecra = abrir();
  await act(async () => undefined);
  expect(ecra.getByText('Casa · 500 casas')).toBeTruthy();
  expect(ecra.queryByText(/Adiciona um endereço do tipo Trabalho/)).toBeNull();
  expect(ecra.queryByText('A empresa paga tudo')).toBeNull();
  fireEvent.press(ecra.getByText('13h00')); // às 9h de Luanda: fecha às 12h00
  await act(async () => {
    fireEvent.press(ecra.getByText('Criar grupo'));
  });
  expect(mockCriar).toHaveBeenCalledWith(expect.objectContaining({ pontoEntregaId: 'pc', tipo: 'familia', modo: 'individual' }));
});

test('vizinhos e quem recebe paga tudo', async () => {
  mockEnderecos.mockResolvedValue([casa]);
  const ecra = abrir();
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('🏘️ Vizinhos'));
  fireEvent.press(ecra.getByText('Quem recebe paga tudo'));
  expect(ecra.getByText('Quem recebe a entrega paga tudo ao estafeta (dinheiro ou Multicaixa) e acerta depois com os outros.')).toBeTruthy();
  fireEvent.press(ecra.getByText('13h00')); // às 9h de Luanda: fecha às 12h00
  await act(async () => {
    fireEvent.press(ecra.getByText('Criar grupo'));
  });
  expect(mockCriar).toHaveBeenCalledWith(expect.objectContaining({ tipo: 'vizinhos', modo: 'quem_recebe' }));
});

test('cliente Empresa: «a empresa paga» só no endereço de trabalho', async () => {
  mockPerfil.tipo = 'Empresa';
  mockEnderecos.mockResolvedValue([casa, trabalho]);
  const ecra = abrir();
  await act(async () => undefined);
  // O trabalho vem primeiro e o tipo natural é «Trabalho»
  expect(ecra.getByText('A empresa paga tudo')).toBeTruthy();
  fireEvent.press(ecra.getByText('Casa · 500 casas'));
  expect(ecra.queryByText('A empresa paga tudo')).toBeNull();
});

test('sem endereços: pede para adicionar um (qualquer tipo)', async () => {
  mockEnderecos.mockResolvedValue([]);
  const ecra = abrir();
  await act(async () => undefined);
  expect(ecra.getByText('Tudo chega junto num só endereço (casa, trabalho, igreja…). Adiciona primeiro esse endereço.')).toBeTruthy();
});
