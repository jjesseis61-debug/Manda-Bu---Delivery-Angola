/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import PedidoDetalhe from '@/app/pedido/[id]';
import { fazerReclamacao, justificacaoCancelamento, lerPedido, minhasReclamacoes } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  lerPedido: jest.fn(),
  atrasoDoPedido: jest.fn(),
  avaliacaoPermitida: jest.fn(),
  minhaAvaliacao: jest.fn(),
  cancelarPedido: jest.fn(),
  minhasReclamacoes: jest.fn(),
  fazerReclamacao: jest.fn(),
  justificacaoCancelamento: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({
  supabase: { channel: () => ({ on: () => ({ subscribe: () => ({}) }) }), removeChannel: jest.fn() },
}));
jest.mock('@/components/AcompanharEntrega', () => ({ AcompanharEntrega: () => null }));
jest.mock('@/components/PessoasComoTu', () => ({ PessoasComoTu: () => null }));
jest.mock('@/components/PartilharCodigo', () => ({ PartilharCodigo: () => null }));
const mockSessao = { carregado: true, ligada: () => false };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));
jest.mock('@/lib/carrinho', () => ({ useCarrinho: () => ({ repor: jest.fn() }) }));

const pedido = {
  id: 'p1', criado_em: new Date().toISOString(), estado: 'entregue_pago',
  itens: [{ nome: 'Muamba', qtd: 1, preco_unitario: 3000 }], subtotal: 3000, taxa_entrega: 0, desconto_indicacao: 0,
  credito_indicacao_usado: 0, pago_pacote: 0, refeicoes_pacote: 0, observacoes: null, motivo_cancelamento: null,
  hora_prometida: null, entregue_em: new Date().toISOString(),
};
const abrir = () => renderRouter({ 'pedido/[id]': PedidoDetalhe }, { initialUrl: '/pedido/p1' });

beforeEach(() => {
  jest.clearAllMocks();
  (lerPedido as jest.Mock).mockResolvedValue(pedido);
});

test('o cliente reclama de um pedido e vê que foi recebida', async () => {
  (minhasReclamacoes as jest.Mock).mockResolvedValueOnce([]).mockResolvedValue([
    { id: 'r1', pedido_id: 'p1', origem: 'cliente', texto: 'Faltou o sumo', estado: 'aberta', resposta: null,
      criado_em: new Date().toISOString(), decidido_em: null },
  ]);
  (fazerReclamacao as jest.Mock).mockResolvedValue('r1');
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Tenho uma reclamação')).toBeTruthy());
  fireEvent.press(ecra.getByText('Tenho uma reclamação'));
  fireEvent.changeText(ecra.getByLabelText('O que correu mal?'), 'Faltou o sumo');
  await act(async () => {
    fireEvent.press(ecra.getByText('Enviar reclamação'));
  });
  expect(fazerReclamacao).toHaveBeenCalledWith('p1', 'Faltou o sumo');
  expect(ecra.getByText(/A cozinha vai ver o que aconteceu/)).toBeTruthy();
  expect(ecra.queryByText('Tenho uma reclamação')).toBeNull();
});

test('mostra a resposta da cozinha', async () => {
  (minhasReclamacoes as jest.Mock).mockResolvedValue([
    { id: 'r1', pedido_id: 'p1', origem: 'avaliacao', texto: 'Chegou frio', estado: 'resolvida',
      resposta: 'Tens razão, pedimos desculpa.', criado_em: new Date().toISOString(), decidido_em: new Date().toISOString() },
  ]);
  const ecra = abrir();
  await waitFor(() =>
    expect(ecra.getByText(/A cozinha respondeu à tua reclamação.*Tens razão, pedimos desculpa\./)).toBeTruthy(),
  );
  // a reclamação veio da avaliação: ainda pode reclamar pelo botão
  expect(ecra.getByText('Tenho uma reclamação')).toBeTruthy();
});

test('pedido cancelado pela cozinha: mostra a justificação completa do servidor', async () => {
  (lerPedido as jest.Mock).mockResolvedValue({ ...pedido, estado: 'cancelado', motivo_cancelamento: 'Acabou um ingrediente' });
  (minhasReclamacoes as jest.Mock).mockResolvedValue([]);
  (justificacaoCancelamento as jest.Mock).mockResolvedValue('Lamentamos muito: tivemos de cancelar o teu pedido de Muamba.');
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Lamentamos muito: tivemos de cancelar o teu pedido de Muamba.')).toBeTruthy());
  expect(justificacaoCancelamento).toHaveBeenCalledWith('p1');
  expect(ecra.queryByText('Acabou um ingrediente')).toBeNull();
});
