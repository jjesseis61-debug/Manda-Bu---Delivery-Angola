/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Campanhas from '@/app/campanhas';
import { lerCozinhas } from '@/lib/api';
import { avisarCampanha, guardarCampanha, lerCampanhas } from '@/lib/condominios';

jest.mock('@/lib/supabase', () => ({ supabase: {} }));
jest.mock('@/lib/api', () => ({
  lerCozinhas: jest.fn().mockResolvedValue([]),
  lerZonasEntrega: jest.fn().mockResolvedValue([]),
  lerCardapio: jest.fn().mockResolvedValue([{ id: 'p1', nome: 'Muamba ', preco: 3000, cozinha_id: 'k1' }]),
  lerFuncionalidades: jest.fn(async () => [{ chave: 'condominios', activa: mockCondominios.ligados }]),
}));
const mockCondominios = { ligados: true };
jest.mock('@/lib/condominios', () => ({
  ...jest.requireActual('@/lib/condominios'),
  lerCampanhas: jest.fn(),
  lerCondominios: jest.fn().mockResolvedValue([{ id: 'c1', nome: 'Jardim', cozinha_id: 'k1' }]),
  guardarCampanha: jest.fn().mockResolvedValue('x'),
  avisarCampanha: jest.fn().mockResolvedValue(12),
  apagarCampanha: jest.fn(),
}));
const mockSessao = {
  carregado: true,
  sessao: {},
  funcionario: { id: 'f1', cozinhas_equipa: ['k1'] },
  pode: (_p: string) => true,
};
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const CAMP = {
  id: 'k', nome: 'Sexta no Jardim', descricao: null, condominio_id: 'c1', condominio: 'Jardim', zona_id: null, zona: null,
  cozinha_id: null, cozinha: null, tipo: 'percentagem', valor: 20, cardapio_ids: null, minimo_pedido: 0,
  inicio: '2026-11-16T10:00:00Z', fim: null, dias_semana: [5], hora_inicio: null, hora_fim: null, so_membros: true,
  limite_por_cliente: 1, limite_total: null, activa: true, avisado_em: null, em_curso: true,
  resultado: { pedidos: 3, entregues: 2, clientes: 3, vendas: 11200, desconto: 2800 },
};

test('mostra o resultado, avisa os clientes e cria uma campanha de condomínio', async () => {
  (lerCampanhas as jest.Mock).mockResolvedValue([CAMP]);
  const ecra = renderRouter({ campanhas: Campanhas }, { initialUrl: '/campanhas' });
  await waitFor(() => expect(ecra.getByText('🟢 Sexta no Jardim')).toBeTruthy());
  expect(ecra.getByText('3 pedidos · 3 clientes · 11.200 Kz vendidos · 2.800 Kz de desconto')).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getByText('Avisar os clientes'));
  });
  expect(avisarCampanha).toHaveBeenCalledWith('k');
  await waitFor(() => expect(ecra.getByText('Aviso enviado a 12 cliente(s).')).toBeTruthy());

  fireEvent.press(ecra.getByText('Nova campanha'));
  fireEvent.changeText(ecra.getByLabelText('Nome (ex.: Sexta no Jardim)'), 'Almoço barato');
  fireEvent.press(ecra.getByText('Jardim'));
  fireEvent.changeText(ecra.getByLabelText('Desconto (%, 1–90)'), '15');
  fireEvent.changeText(ecra.getByLabelText('Das (HH:MM)'), '12:00');
  fireEvent.changeText(ecra.getByLabelText('Às (HH:MM)'), '15:00');
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar campanha'));
  });
  expect(guardarCampanha).toHaveBeenCalledWith(
    expect.objectContaining({
      nome: 'Almoço barato', condominio_id: 'c1', zona_id: null, tipo: 'percentagem', valor: 15,
      hora_inicio: '12:00', hora_fim: '15:00', so_membros: true, cardapio_ids: null,
    }),
  );
});

beforeEach(() => {
  mockCondominios.ligados = true;
  mockSessao.pode = () => true;
  (guardarCampanha as jest.Mock).mockClear();
  (lerCozinhas as jest.Mock).mockResolvedValue([{ id: 'k1', nome: 'Maianga' }, { id: 'k2', nome: 'Viana' }]);
});

test('condomínios desligados: a campanha nova começa em «Todos»', async () => {
  mockCondominios.ligados = false;
  (lerCampanhas as jest.Mock).mockResolvedValue([]);
  const ecra = renderRouter({ campanhas: Campanhas }, { initialUrl: '/campanhas' });
  await waitFor(() => expect(ecra.getByText('Ainda não há campanhas.')).toBeTruthy());
  await act(async () => {
    fireEvent.press(ecra.getByText('Nova campanha'));
  });
  expect(ecra.getByText('Cozinha')).toBeTruthy();
  expect(ecra.getByText('Todas')).toBeTruthy();
});

test('«Pôr em promoção» no cardápio: abre a campanha com a cozinha e o prato', async () => {
  (lerCampanhas as jest.Mock).mockResolvedValue([]);
  const ecra = renderRouter({ campanhas: Campanhas }, { initialUrl: '/campanhas?cozinha=k1&prato=p1' });
  await waitFor(() => expect(ecra.getByText('Nova campanha')).toBeTruthy());
  await waitFor(() => expect(ecra.getByRole('checkbox', { name: /Muamba/, checked: true })).toBeTruthy());
  fireEvent.changeText(ecra.getByLabelText('Nome (ex.: Sexta no Jardim)'), 'Muamba da semana');
  fireEvent.changeText(ecra.getByLabelText('Desconto (%, 1–90)'), '20');
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar campanha'));
  });
  expect(guardarCampanha).toHaveBeenCalledWith(
    expect.objectContaining({ nome: 'Muamba da semana', condominio_id: null, zona_id: null, cozinha_id: 'k1', cardapio_ids: ['p1'], valor: 20 }),
  );
});

test('gerente do cardápio: só «Todos (pratos da minha cozinha)» e as suas cozinhas', async () => {
  mockSessao.pode = (p: string) => p === 'cardapio.gerir';
  (lerCampanhas as jest.Mock).mockResolvedValue([]);
  const ecra = renderRouter({ campanhas: Campanhas }, { initialUrl: '/campanhas' });
  await waitFor(() => expect(ecra.getByText('Ainda não há campanhas.')).toBeTruthy());
  await act(async () => {
    fireEvent.press(ecra.getByText('Nova campanha'));
  });
  expect(ecra.getByText('Todos (pratos da minha cozinha)')).toBeTruthy();
  expect(ecra.queryByText('Uma zona')).toBeNull();
  expect(ecra.queryByText('Todas')).toBeNull();
  expect(ecra.getByText('Maianga')).toBeTruthy();
  expect(ecra.queryByText('Viana')).toBeNull();
});
