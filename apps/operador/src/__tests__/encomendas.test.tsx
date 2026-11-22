/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';

import Encomendas from '@/app/encomendas';
import { separarEncomendas, type EncomendaOperador } from '@/lib/encomendas';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
jest.mock('@/components/Guarda', () => ({ Guarda: ({ children }: { children: unknown }) => children }));
jest.mock('@/lib/api', () => ({
  lerCozinhas: async () => [
    { id: 'ran', nome: 'Rangel', estado: 'activa' },
    { id: 'kil', nome: 'Kilamba', estado: 'activa' },
    { id: 'velha', nome: 'Fechada', estado: 'inactiva' },
  ],
}));
const mockLista = jest.fn();
const mockEnviar = jest.fn(async (..._a: unknown[]) => undefined);
const mockResposta = jest.fn(async (..._a: unknown[]) => undefined);
const mockAprovar = jest.fn(async (..._a: unknown[]) => undefined);
jest.mock('@/lib/encomendas', () => ({
  ...jest.requireActual('@/lib/encomendas'),
  encomendasLista: () => mockLista(),
  enviarEncomendaCozinha: (...a: unknown[]) => mockEnviar(...a),
  responderEncomendaCozinha: (...a: unknown[]) => mockResposta(...a),
  aprovarEncomenda: (...a: unknown[]) => mockAprovar(...a),
}));

const enc = (id: string, extra: Partial<EncomendaOperador> = {}): EncomendaOperador => ({
  id, estado: 'pedida', criado_em: '2026-11-22T10:00:00Z', para_quando: '2026-11-28T12:00:00Z', pessoas: 8, nota: null, motivo: null,
  receita: 'Mufete', cozinha_id: null, cozinha_nome: null, preco_cozinha: null, nota_cozinha: null, preco: null, taxa_entrega: 0,
  total: null, sinal: 0, pedido_id: null, local: 'Rangel', cliente_nome: 'Clara', cliente_telefone: '923000000',
  pode_gerir: true, pode_propor: false, sugestoes: null, ...extra,
});

beforeEach(() => {
  mockLista.mockReset();
  mockEnviar.mockClear();
  mockResposta.mockClear();
  mockAprovar.mockClear();
});

test('por fazer: o operador escolhe/aprova; a cozinha propõe', () => {
  const r = separarEncomendas([
    enc('1'),
    enc('2', { estado: 'na_cozinha', cozinha_id: 'ran' }),
    enc('3', { estado: 'na_cozinha', pode_gerir: false, pode_propor: true }),
    enc('4', { estado: 'a_confirmar' }),
    enc('5', { estado: 'proposta' }),
  ]);
  expect(r.porFazer.map((e) => e.id)).toEqual(['1', '3', '5']);
  expect(r.outras.map((e) => e.id)).toEqual(['2', '4']);
});

test('pedida: sugere primeiro quem já fez o prato e envia à cozinha escolhida', async () => {
  mockLista.mockResolvedValue([enc('1', { sugestoes: [{ cozinha_id: 'ran', nome: 'Rangel', sabe_fazer: true, distancia_km: 3.2 }] })]);
  const ecra = renderRouter({ encomendas: Encomendas }, { initialUrl: '/encomendas' });
  await act(async () => undefined);
  expect(ecra.getByText('★ Rangel · 3,2 km')).toBeTruthy();
  expect(ecra.getByText('Kilamba')).toBeTruthy();
  expect(ecra.queryByText('Fechada')).toBeNull();
  await act(async () => {
    fireEvent.press(ecra.getByText('Enviar à cozinha'));
  });
  expect(mockEnviar).toHaveBeenCalledWith('1', 'ran');
});

test('a cozinha propõe o preço; o operador aprova com o preço da cozinha já escrito', async () => {
  mockLista.mockResolvedValue([enc('1', { estado: 'na_cozinha', cozinha_id: 'ran', pode_gerir: false, pode_propor: true })]);
  const ecra = renderRouter({ encomendas: Encomendas }, { initialUrl: '/encomendas' });
  await act(async () => undefined);
  expect(ecra.queryByText('Cancelar')).toBeNull();
  fireEvent.press(ecra.getByText('Propor preço'));
  fireEvent.changeText(ecra.getByLabelText('Preço do prato para 8 pessoas (Kz, sem a entrega)'), '24.000');
  await act(async () => {
    fireEvent.press(ecra.getByText('Enviar preço'));
  });
  expect(mockResposta).toHaveBeenCalledWith('1', 24000, '');

  mockLista.mockResolvedValue([enc('2', { estado: 'proposta', cozinha_id: 'ran', cozinha_nome: 'Rangel', preco_cozinha: 24000 })]);
  const op = renderRouter({ encomendas: Encomendas }, { initialUrl: '/encomendas' });
  await act(async () => undefined);
  fireEvent.press(op.getByText('Aprovar o preço'));
  expect(op.getByDisplayValue('24000')).toBeTruthy();
  await act(async () => {
    fireEvent.press(op.getByText('Aprovar e enviar ao cliente'));
  });
  expect(mockAprovar).toHaveBeenCalledWith('2', 24000);
});

test('recusar na cozinha exige o motivo', async () => {
  mockLista.mockResolvedValue([enc('1', { estado: 'na_cozinha', cozinha_id: 'ran', pode_gerir: false, pode_propor: true })]);
  const ecra = renderRouter({ encomendas: Encomendas }, { initialUrl: '/encomendas' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Não podemos'));
  fireEvent.press(ecra.getByText('Não podemos fazer'));
  expect(mockResposta).not.toHaveBeenCalled();
  fireEvent.changeText(ecra.getByLabelText('Porquê (ex.: sem peixe esta semana)'), 'Sem peixe');
  await act(async () => {
    fireEvent.press(ecra.getByText('Não podemos fazer'));
  });
  expect(mockResposta).toHaveBeenCalledWith('1', null, 'Sem peixe');
});
