/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Analista from '@/app/analista';
import { lerPerguntasAnalista, pedirRelatorioAnalista, perguntarAnalista } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  lerPerguntasAnalista: jest.fn(),
  perguntarAnalista: jest.fn(),
  pedirRelatorioAnalista: jest.fn(),
}));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: [] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const respondida = {
  id: 'q1', tipo: 'pergunta', pergunta: 'Que cozinha vendeu mais?', inicio: null, fim: null, estado: 'respondida',
  resposta: 'A Alexandra vendeu mais: 120 pedidos, mais 15% do que em Agosto.',
  numeros: [{ rotulo: 'Alexandra', valor: '120 pedidos' }], sugestoes: ['Reforçar o almoço de sexta'],
  limitacoes: 'Só há dados desde Setembro.', ia_nota: null, passos: 3,
  criado_em: '2026-10-03T10:00:00Z', respondida_em: '2026-10-03T10:01:00Z', quem: 'Paula',
};

beforeEach(() => jest.clearAllMocks());

test('mostra a resposta com os números-chave, sugestões e limitações', async () => {
  (lerPerguntasAnalista as jest.Mock).mockResolvedValue([respondida]);
  const ecra = renderRouter({ analista: Analista }, { initialUrl: '/analista' });
  await waitFor(() => expect(ecra.getByText(/A Alexandra vendeu mais/)).toBeTruthy());
  expect(ecra.getByText('120 pedidos')).toBeTruthy();
  expect(ecra.getByText('• Reforçar o almoço de sexta')).toBeTruthy();
  expect(ecra.getByText('Limitações: Só há dados desde Setembro.')).toBeTruthy();
});

test('pergunta (com sugestão) e pede o relatório do mês', async () => {
  (lerPerguntasAnalista as jest.Mock).mockResolvedValue([]);
  (perguntarAnalista as jest.Mock).mockResolvedValue('q2');
  (pedirRelatorioAnalista as jest.Mock).mockResolvedValue('r1');
  const ecra = renderRouter({ analista: Analista }, { initialUrl: '/analista' });
  await waitFor(() => expect(ecra.getByText('Ainda não fizeste perguntas.')).toBeTruthy());
  fireEvent.press(ecra.getByText('Quantos clientes voltaram a comprar e de que bairros são?'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Perguntar'));
  });
  expect(perguntarAnalista).toHaveBeenCalledWith('Quantos clientes voltaram a comprar e de que bairros são?');
  fireEvent.changeText(ecra.getByLabelText('Relatório do mês (AAAA-MM)'), '2026-09');
  await act(async () => {
    fireEvent.press(ecra.getByText('Pedir relatório do mês'));
  });
  expect(pedirRelatorioAnalista).toHaveBeenCalledWith(2026, 9);
});
