/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Conferencia from '@/app/conferencia';
import HistoricoPedidoEcra from '@/app/pedido/[id]';
import {
  fechoDiario,
  fechoMensal,
  historicoPedido,
  lerExtratos,
  lerMovimentos,
  ligarMovimento,
  registarMovimento,
} from '@/lib/api';

jest.mock('@/lib/api', () => ({
  fechoDiario: jest.fn(),
  fechoMensal: jest.fn(),
  lerExtratos: jest.fn(),
  lerMovimentos: jest.fn(),
  ligarMovimento: jest.fn(),
  registarMovimento: jest.fn(),
  apagarMovimento: jest.fn(),
  criarExtrato: jest.fn(),
  confirmarExtrato: jest.fn(),
  pedirNovaLeitura: jest.fn(),
  historicoPedido: jest.fn(),
}));
jest.mock('@/lib/fotos', () => ({ enviarExtrato: jest.fn(), escolherFicheiroExtrato: jest.fn(), escolherFoto: jest.fn() }));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: ['c1'] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const semExtrato = {
  comprovativo_id: 'k9', pedido_id: 'p9', cliente_nome: 'Ana', metodo: 'Unitel Money', valor: 3000, referencia: 'UM-2001',
  dia: '2026-10-03', estado: 'conferido', ia_estado: 'diverge', registado_por: 'Estafeta Rui', conferido_por: 'Gerente',
};

beforeEach(() => {
  jest.clearAllMocks();
  (lerExtratos as jest.Mock).mockResolvedValue([
    { id: 'e1', conta: 'Multicaixa Express BAI', periodo_inicio: '2026-10-01', periodo_fim: '2026-10-31', caminho: 'e1/1.pdf',
      tipo_ficheiro: 'pdf', estado: 'indisponivel', ia_nota: 'Leitura automática não configurada: confere à mão.', criado_em: '2026-10-03T10:00:00Z' },
  ]);
});

test('fecho do dia: caixas e avisos (leitura que não confere, com quem registou)', async () => {
  (fechoDiario as jest.Mock).mockResolvedValue({
    dia: '2026-10-03', pedidos_entregues: 3, cancelados: 0, vendido: 9000, electronico: 9000, diferenca_caixas: -500, caixas_abertas: 0,
    caixas: [{ caixa_id: 'x1', posto: 'Balcão', cozinha: 'Alexandra', aberta_por: 'Jesse', fechada: true, fechada_por: 'Jesse',
               esperado: 5000, contado: 4500, diferenca: -500, electronico: 9000, por_conferir: 0, rejeitados: 0, ia_alertas: 1 }],
    alertas: [{ tipo: 'ia_diverge', comprovativo_id: 'k2', pedido_id: 'p2', metodo: 'Multicaixa Express', valor: 3000,
                referencia: 'MCX-1002', ia_valor: 2500, ia_referencia: 'MCX-1002', quem: 'Estafeta Rui' }],
  });
  const ecra = renderRouter({ conferencia: Conferencia }, { initialUrl: '/conferencia' });
  await act(async () => {
    fireEvent.press(ecra.getByText('Ver fecho do dia'));
  });
  expect(fechoDiario).toHaveBeenCalled();
  expect(ecra.getByText('Comprovativo não confere com a foto')).toBeTruthy();
  expect(ecra.getByText(/na foto: 2\.500/)).toBeTruthy();
  expect(ecra.getByText('Estafeta Rui')).toBeTruthy();
});

test('fecho do mês: comprovativo sem extrato e ligação manual de uma entrada', async () => {
  (fechoMensal as jest.Mock).mockResolvedValue({
    ano: 2026, mes: 10, inicio: '2026-10-01', fim: '2026-10-31', dias: [],
    totais: { pedidos: 3, vendido: 9000, dinheiro: 0, electronico: 9000, diferenca_caixas: 0, caixas_por_fechar: 0 },
    conciliacao: {
      inicio: '2026-10-01', fim: '2026-10-31', encontrados: [], aguardam_extrato: 0,
      comprovativos_sem_extrato: [semExtrato],
      movimentos_sem_comprovativo: [{ movimento_id: 'm1', extrato_id: 'e1', conta: 'BAI', data: '2026-10-03', valor: 3000,
                                      referencia: null, descricao: 'Transferência', origem: 'manual' }],
      totais: { comprovativos: 3000, encontrados: 0, sem_extrato: 3000, movimentos: 3000, movimentos_sem_comprovativo: 3000 },
    },
    por_funcionario: [{ funcionario_id: 'f2', nome: 'Estafeta Rui', comprovativos: 3, rejeitados: 0, ia_alertas: 1, sem_extrato: 1,
                        valor_sem_extrato: 3000, conferiu: 0, conferiu_sem_extrato: 0, diferenca_caixas: 0 }],
  });
  const ecra = renderRouter({ conferencia: Conferencia }, { initialUrl: '/conferencia' });
  fireEvent.press(ecra.getByText('Fecho do mês'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Ver fecho do mês'));
  });
  expect(ecra.getByText('Comprovativos que não aparecem no extrato')).toBeTruthy();
  expect(ecra.getByText(/Registou: Estafeta Rui/)).toBeTruthy();
  fireEvent.press(ecra.getByText('Ligar a um comprovativo…'));
  await act(async () => {
    fireEvent.press(ecra.getByText(/Ligar a Unitel Money ref\. UM-2001/));
  });
  expect(ligarMovimento).toHaveBeenCalledWith('m1', 'k9');
});

test('extratos: sem leitura automática, junta uma entrada à mão', async () => {
  (lerMovimentos as jest.Mock).mockResolvedValue([]);
  const ecra = renderRouter({ conferencia: Conferencia }, { initialUrl: '/conferencia' });
  fireEvent.press(ecra.getByText('Extratos'));
  await waitFor(() => expect(ecra.getByText('Multicaixa Express BAI')).toBeTruthy());
  expect(ecra.getByText(/Leitura automática indisponível/)).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getByText('Ver entradas'));
  });
  const vazios = ecra.getAllByDisplayValue('');
  fireEvent.changeText(vazios[0], '2026-10-03');
  fireEvent.changeText(vazios[1], '3000');
  fireEvent.changeText(vazios[2], 'um 2001');
  await act(async () => {
    fireEvent.press(ecra.getByText('Juntar entrada'));
  });
  expect(registarMovimento).toHaveBeenCalledWith('e1', '2026-10-03', 3000, 'um 2001', null);
});

test('histórico do pedido: cada passo com quem o fez', async () => {
  (historicoPedido as jest.Mock).mockResolvedValue({
    pedido_id: 'p1', estado: 'entregue_pago', cliente: 'Ana Sousa', cozinha: 'Alexandra', entregador: 'Estafeta Rui', caixa: 'Balcão',
    valor: 3000, parcelas: [{ metodo: 'Multicaixa Express', valor: 3000, referencia: 'MCX-1001' }],
    eventos: [
      { em: '2026-10-03T11:00:00Z', acao: 'pedido_criado', quem: 'Ana Sousa', detalhe: null },
      { em: '2026-10-03T11:05:00Z', acao: 'pedido_estado', quem: 'Gerente', detalhe: { de: 'pendente', para: 'confirmado' } },
      { em: '2026-10-03T11:50:00Z', acao: 'comprovativo_registado', quem: 'Estafeta Rui',
        detalhe: { metodo: 'Multicaixa Express', valor: 3000, referencia: 'MCX-1001' } },
      { em: '2026-10-03T18:00:00Z', acao: 'comprovativo_conferido', quem: 'Gerente', detalhe: { referencia: 'MCX-1001' } },
    ],
  });
  const ecra = renderRouter({ 'pedido/[id]': HistoricoPedidoEcra }, { initialUrl: '/pedido/p1' });
  await waitFor(() => expect(ecra.getByText('Passo a passo')).toBeTruthy());
  expect(historicoPedido).toHaveBeenCalledWith('p1');
  expect(ecra.getByText('Mudou para «Confirmado»')).toBeTruthy();
  expect(ecra.getByText(/Registou o pagamento Multicaixa Express/)).toBeTruthy();
  expect(ecra.getAllByText('Estafeta Rui').length).toBeGreaterThan(0);
});
