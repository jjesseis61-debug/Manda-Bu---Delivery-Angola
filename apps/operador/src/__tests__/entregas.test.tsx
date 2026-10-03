/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Entregas from '@/app/entregas';
import { alertasAbertos, caixasAbertas, informarAtraso, lerCozinhas, pedidosOperador } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  pedidosOperador: jest.fn(),
  caixasAbertas: jest.fn(),
  lerCozinhas: jest.fn(),
  alertasAbertos: jest.fn(),
  informarAtraso: jest.fn(),
  mudarEstado: jest.fn(),
  marcarPagadorDistinto: jest.fn(),
}));
jest.mock('@/lib/fotos', () => ({ enviarComprovativo: jest.fn(), escolherFoto: jest.fn() }));
jest.mock('@/lib/partilharLocalizacao', () => ({ usePartilharLocalizacao: () => ({ aCaminho: 0, erro: null }) }));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: ['c1'] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const pedido = (id: string, estado: string, cliente: string) => ({
  pedido_id: id, criado_em: '2026-10-03T11:00:00Z', estado, cozinha_id: 'c1', cliente_nome: cliente, cliente_telefone: null,
  itens: [{ nome: 'Chocos', qtd: 1 }], subtotal: 6000, taxa_entrega: 1000, desconto_indicacao: 0, credito_indicacao_usado: 0,
  a_pagar: 7000, observacoes: null, hora_prometida: '2026-10-03T11:45:00Z', pagador_distinto: false,
  ponto_entrega_id: `pt-${id}`, ponto_tipo: 'residencial', ponto_lat: null, ponto_lng: null, ponto_referencia: null, zona_nome: 'Viana',
});

test('mostra os pedidos parados e atrasados e avisa o cliente do motivo', async () => {
  (pedidosOperador as jest.Mock).mockResolvedValue([pedido('p1', 'pendente', 'Ana'), pedido('p2', 'em_preparacao', 'Bruno')]);
  (caixasAbertas as jest.Mock).mockResolvedValue([]);
  (lerCozinhas as jest.Mock).mockResolvedValue([]);
  (alertasAbertos as jest.Mock).mockResolvedValue([
    { pedido_id: 'p1', tipo: 'sem_confirmacao', minutos: 7, motivo: null, mais_minutos: null, criado_em: '', motivo_em: null },
    { pedido_id: 'p2', tipo: 'atraso', minutos: 12, motivo: null, mais_minutos: null, criado_em: '', motivo_em: null },
  ]);
  const ecra = renderRouter({ entregas: Entregas }, { initialUrl: '/entregas' });
  await waitFor(() => expect(ecra.getByText('Por confirmar há mais de 7 minutos.')).toBeTruthy());
  expect(ecra.getByText('Atrasado 12 min. Diz ao cliente o motivo.')).toBeTruthy();

  fireEvent.press(ecra.getAllByText('Avisar cliente do atraso…')[1]);
  fireEvent.press(ecra.getByText('Trânsito'));
  fireEvent.changeText(ecra.getByDisplayValue(''), '15');
  await act(async () => {
    fireEvent.press(ecra.getByText('Avisar o cliente'));
  });
  expect(informarAtraso).toHaveBeenCalledWith('p2', 'Trânsito', 15);
});
