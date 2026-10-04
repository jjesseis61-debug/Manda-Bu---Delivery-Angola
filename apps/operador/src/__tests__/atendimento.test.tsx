/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Atendimento from '@/app/atendimento';
import { lerConversaAtendimento, lerConversasAtendimento, mudarConversaAtendimento, responderAtendimento } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  lerConversasAtendimento: jest.fn(),
  lerConversaAtendimento: jest.fn(),
  responderAtendimento: jest.fn(),
  mudarConversaAtendimento: jest.fn(),
}));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: [] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const lista = [
  { id: 'c1', cliente: 'Ana', estado: 'humano', motivo: 'pede compensação pelo atraso', atendido_por: null,
    ultima_mensagem_em: '2026-10-04T11:00:00Z', ultima_mensagem: 'Estou à espera.', ultima_do_cliente: true },
  { id: 'c2', cliente: 'Bia', estado: 'agente', motivo: null, atendido_por: null,
    ultima_mensagem_em: '2026-10-04T10:00:00Z', ultima_mensagem: 'A entrega custa 500 Kz.', ultima_do_cliente: false },
];
const detalhe = {
  id: 'c1', estado: 'humano', motivo: 'pede compensação pelo atraso', cliente: 'Ana', telefone: null,
  mensagens: [
    { id: 'm1', autor: 'cliente', texto: 'O meu calulu atrasou.', criado_em: '2026-10-04T10:58:00Z', quem: null },
    { id: 'm2', autor: 'agente', texto: 'Vou passar-te a um colega.', criado_em: '2026-10-04T10:58:05Z', quem: null },
  ],
  pedidos: [{ pedido_id: 'p1', feito_em: '2026-10-04 10:30', estado: 'em_entrega', itens: '1× Calulu', total_kz: 3500 }],
};

beforeEach(() => jest.clearAllMocks());

test('atendimento: abre a conversa à espera, responde e devolve ao assistente', async () => {
  (lerConversasAtendimento as jest.Mock).mockResolvedValue(lista);
  (lerConversaAtendimento as jest.Mock).mockResolvedValue(detalhe);
  const ecra = renderRouter({ atendimento: Atendimento }, { initialUrl: '/atendimento' });
  await waitFor(() => expect(ecra.getByText('Ana · À espera de uma pessoa')).toBeTruthy());
  expect(ecra.getByText('pede compensação pelo atraso')).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getByText('Ana · À espera de uma pessoa'));
  });
  expect(ecra.getByText('O meu calulu atrasou.')).toBeTruthy();
  expect(ecra.getByText('2026-10-04 10:30 · em_entrega · 1× Calulu · 3.500 Kz')).toBeTruthy();
  fireEvent.changeText(ecra.getByLabelText('Resposta ao cliente'), ' Olá Ana, vamos oferecer-te a entrega. ');
  await act(async () => {
    fireEvent.press(ecra.getByText('Responder'));
  });
  expect(responderAtendimento).toHaveBeenCalledWith('c1', 'Olá Ana, vamos oferecer-te a entrega.');
  await act(async () => {
    fireEvent.press(ecra.getByText('Devolver ao assistente'));
  });
  expect(mudarConversaAtendimento).toHaveBeenCalledWith('c1', 'agente');
});
