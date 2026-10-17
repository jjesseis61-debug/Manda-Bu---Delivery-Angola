/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';
import { Text } from 'react-native';

import Ajuda from '@/app/ajuda';
import { enviarMensagemAtendimento, minhaConversaAtendimento, pedirPessoaAtendimento } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  minhaConversaAtendimento: jest.fn(),
  enviarMensagemAtendimento: jest.fn(),
  pedirPessoaAtendimento: jest.fn(),
}));
const mockSessao: { carregado: boolean; ligada: (c: string) => boolean } = { carregado: true, ligada: (c) => c === 'agente_atendimento' };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const conversa = {
  conversa_id: 'c1', estado: 'agente', a_escrever: false,
  mensagens: [
    { id: 'm1', autor: 'cliente', texto: 'Onde está o meu calulu?', criado_em: '2026-10-04T11:00:00Z', quem: null },
    { id: 'm2', autor: 'agente', texto: 'Está a ser preparado; atrasou uns 15 minutos.', criado_em: '2026-10-04T11:00:05Z', quem: null },
  ],
};

const abrir = () => renderRouter({ ajuda: Ajuda, inicio: () => <Text>Início</Text> }, { initialUrl: '/ajuda' });

beforeEach(() => {
  jest.clearAllMocks();
  mockSessao.ligada = (c: string) => c === 'agente_atendimento';
});

test('ajuda: mostra a conversa, envia uma mensagem e pede uma pessoa', async () => {
  (minhaConversaAtendimento as jest.Mock).mockResolvedValue(conversa);
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Está a ser preparado; atrasou uns 15 minutos.')).toBeTruthy());
  expect(ecra.getByText('Assistente Manda Bué')).toBeTruthy();
  fireEvent.changeText(ecra.getByLabelText('A tua mensagem'), '  E a entrega é grátis?  ');
  await act(async () => {
    fireEvent.press(ecra.getByText('Enviar'));
  });
  expect(enviarMensagemAtendimento).toHaveBeenCalledWith('E a entrega é grátis?');
  await act(async () => {
    fireEvent.press(ecra.getByText('Falar com uma pessoa'));
  });
  expect(pedirPessoaAtendimento).toHaveBeenCalled();
});

test('ajuda: com uma pessoa, mostra quem respondeu e não oferece outra vez a pessoa', async () => {
  (minhaConversaAtendimento as jest.Mock).mockResolvedValue({
    ...conversa, estado: 'humano',
    mensagens: [...conversa.mensagens,
      { id: 'm3', autor: 'funcionario', texto: 'Olá Ana, já vi o teu pedido.', criado_em: '2026-10-04T11:05:00Z', quem: 'Rita' }],
  });
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Rita · equipa Manda Bué')).toBeTruthy());
  expect(ecra.getByText('Um colega da equipa responde aqui assim que puder.')).toBeTruthy();
  expect(ecra.queryByText('Falar com uma pessoa')).toBeNull();
});

test('ajuda: com o interruptor desligado volta ao início', async () => {
  mockSessao.ligada = () => false;
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Início')).toBeTruthy());
  expect(minhaConversaAtendimento).not.toHaveBeenCalled();
});
