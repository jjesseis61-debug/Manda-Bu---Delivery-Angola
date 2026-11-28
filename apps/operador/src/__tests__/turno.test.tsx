/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Turno from '@/app/turno';
import { decidirPropostaTurno, lerPropostasTurno } from '@/lib/api';

jest.mock('@/lib/api', () => ({ lerPropostasTurno: jest.fn(), decidirPropostaTurno: jest.fn() }));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: ['c1'] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const base = { cozinha: 'Alexandra', criado_em: '2026-10-03T12:00:00Z', expira_em: '2026-10-03T12:30:00Z',
  decidido_por: null, decidido_em: null, erro: null, prato: null, motivo_cliente: null, mais_minutos: null, cliente: null };
const propostas = [
  { ...base, id: 'p1', tipo: 'avisar_atraso', pedido_id: 'x1', prioridade: 'alta', estado: 'pendente', cliente: 'Ana',
    explicacao: 'Passou 25 min da hora prometida.', motivo_cliente: 'A cozinha está com muitos pedidos', mais_minutos: 15 },
  { ...base, id: 'p2', tipo: 'pausar_prato', pedido_id: null, prato: 'Calulu de peixe', prioridade: 'media', estado: 'pendente',
    explicacao: 'Três cancelamentos do calulu hoje.' },
  { ...base, id: 'p3', tipo: 'confirmar', pedido_id: 'x2', prioridade: 'media', estado: 'aceite', decidido_por: 'Alexandra',
    explicacao: 'Por confirmar há 12 minutos.' },
];

beforeEach(() => jest.clearAllMocks());

test('gerente de turno: aceita o aviso com a mensagem editada e recusa a pausa', async () => {
  (lerPropostasTurno as jest.Mock).mockResolvedValue(propostas);
  const ecra = renderRouter({ turno: Turno }, { initialUrl: '/turno' });
  await waitFor(() => expect(ecra.getByText('Avisar o cliente do atraso · pedido de Ana')).toBeTruthy());
  expect(ecra.getByText('Pausar o prato: Calulu de peixe')).toBeTruthy();
  expect(ecra.getByText(/Aceite por Alexandra/)).toBeTruthy();
  fireEvent.changeText(ecra.getByLabelText('Mensagem para o cliente'), 'Estamos com muitos pedidos ao almoço');
  fireEvent.changeText(ecra.getByLabelText('Minutos a mais'), '20');
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Aceitar')[0]);
  });
  expect(decidirPropostaTurno).toHaveBeenCalledWith('p1', true, 'Estamos com muitos pedidos ao almoço', 20);
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Recusar')[1]);
  });
  expect(decidirPropostaTurno).toHaveBeenCalledWith('p2', false, null, null);
});
