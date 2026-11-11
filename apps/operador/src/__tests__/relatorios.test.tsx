/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Relatorios from '@/app/relatorios';
import { lerCozinhas, relatorioCozinhaDetalhado } from '@/lib/api';

jest.mock('@/lib/api', () => ({ lerCozinhas: jest.fn(), relatorioComparativo: jest.fn(), relatorioCozinhaDetalhado: jest.fn() }));
jest.mock('@/lib/exportar', () => ({ escaparHtml: (t: string) => t, exportarCsv: jest.fn(), exportarPdf: jest.fn() }));
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, sessao: {}, funcionario: { id: 'f', nome: 'Rita', cozinhas_equipa: [] }, pode: () => true }),
}));

const resumo = {
  pedidos: 2, vendas_brutas: 6000, desconto_convite: 500, saldo_convida: 0, descontos: 500, vendas_liquidas: 5500,
  pago_pacote: 0, valor_empresa: 0, taxas_entrega: 1000, ticket_medio: 3000, cancelados: 1, cancelados_valor: 3000,
  cancelados_cliente: 0, cancelados_cozinha: 1, clientes: 2, clientes_novos: 2, avaliacao_media: 4.5, avaliacoes: 2,
  a_horas_pct: 100, comissao_percent: 10, comissao: 600, a_receber_cozinha: 5400,
};

test('gera o relatório de hoje com o valor a receber e abre as secções', async () => {
  (lerCozinhas as jest.Mock).mockResolvedValue([{ id: 'k1', nome: 'Viana' }]);
  (relatorioCozinhaDetalhado as jest.Mock).mockResolvedValue({
    cozinha: 'Viana', inicio: '2026-11-11', fim: '2026-11-11', resumo, anterior: { ...resumo, a_receber_cozinha: 0 },
    por_dia: [], por_hora: [], por_dia_semana: null, pratos: [{ cardapio_id: 'c', nome: 'Calulu', qtd: 3, receita: 6000, pct: 100 }],
    opcoes_montados: [], montado_valor_medio: null, sem_vendas: [], pagamentos: [], tempo_medio_min: null, agendados: 0,
    grupo_empresa: 0, cancelamentos_motivos: [], estafetas: [], preparadores: [], zonas: [], estrelas: {}, reclamacoes: 0,
    reclamacoes_abertas: 0, convida: { pedidos_com_desconto: 0, comissoes_geradas: 0 },
  });
  const ecra = renderRouter({ relatorios: Relatorios }, { initialUrl: '/relatorios' });
  await waitFor(() => expect(ecra.getByText('Gerar relatório')).toBeTruthy());
  await act(async () => {
    fireEvent.press(ecra.getByText('Gerar relatório'));
  });
  expect(relatorioCozinhaDetalhado).toHaveBeenCalledWith('k1', expect.any(String), expect.any(String));
  expect(ecra.getByText('A receber pela cozinha')).toBeTruthy();
  expect(ecra.getByText('5.400 Kz')).toBeTruthy();
  expect(ecra.queryByText('3× Calulu')).toBeNull();
  fireEvent.press(ecra.getByText(/Cardápio \(o que vendemos\)/));
  expect(ecra.getByText('3× Calulu')).toBeTruthy();
});
