/// <reference types="jest" />
import { fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import EstafetasPagamentos, { mesActual } from '@/app/estafetas-pagamentos';
import Obrigacoes from '@/app/obrigacoes';
import Resultados from '@/app/resultados';
import ServicoEntregas from '@/app/servico-entregas';
import {
  definirDiasEstafeta,
  definirRemuneracaoEstafeta,
  estafetasPagamentos,
  fornecedoresEntrega,
  guardarFornecedorEntrega,
  obrigacoesResumo,
  pagarEstafetaMes,
  pagarFornecedorEntrega,
  resultadosMes,
} from '@/lib/api';

jest.mock('@/lib/api', () => ({
  estafetasPagamentos: jest.fn(),
  definirRemuneracaoEstafeta: jest.fn(),
  definirDiasEstafeta: jest.fn(),
  pagarEstafetaMes: jest.fn(),
  fornecedoresEntrega: jest.fn(),
  guardarFornecedorEntrega: jest.fn(),
  pagarFornecedorEntrega: jest.fn(),
  resultadosMes: jest.fn(),
  obrigacoesResumo: jest.fn(),
}));
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, sessao: {}, funcionario: { id: 'f', cozinhas_equipa: [] }, pode: () => true }),
}));

beforeEach(() => jest.clearAllMocks());

const carlos = {
  funcionario_id: 'e1', nome: 'Carlos', salario_mensal: 0, valor_dia: 0, valor_entrega: 0, dias_sugeridos: 2,
  dias_trabalhados: 2, dias_ajustados: false, entregas: 3, a_pagar: 0, valor_pago: null, metodo: null, referencia: null, pago_em: null,
};

test('mês corrente', () => {
  expect(mesActual(new Date(2026, 10, 21))).toBe('2026-11-01');
});

test('estafetas: define valores e dias, e paga', async () => {
  (estafetasPagamentos as jest.Mock)
    .mockResolvedValueOnce({ mes: '2026-10-01', pode_pagar: true, estafetas: [carlos] })
    .mockResolvedValueOnce({ mes: '2026-10-01', pode_pagar: true, estafetas: [{ ...carlos, salario_mensal: 50000, valor_dia: 1000, valor_entrega: 100, a_pagar: 52300 }] })
    .mockResolvedValue({ mes: '2026-10-01', pode_pagar: true, estafetas: [{ ...carlos, salario_mensal: 50000, valor_dia: 1000, valor_entrega: 100, dias_trabalhados: 4, dias_ajustados: true, a_pagar: 54300 }] });
  const ecra = renderRouter({ 'estafetas-pagamentos': EstafetasPagamentos }, { initialUrl: '/estafetas-pagamentos' });
  await waitFor(() => expect(ecra.getByText('Valores por definir')).toBeTruthy());
  fireEvent.press(ecra.getByText('Valores'));
  fireEvent.changeText(ecra.getByLabelText('Salário mensal (Kz)'), '50.000');
  fireEvent.changeText(ecra.getByLabelText('Valor por dia (Kz)'), '1000');
  fireEvent.changeText(ecra.getByLabelText('Valor por entrega (Kz)'), '100');
  fireEvent.press(ecra.getByText('Guardar os valores'));
  await waitFor(() => expect(definirRemuneracaoEstafeta).toHaveBeenCalledWith('e1', 50000, 1000, 100));
  await waitFor(() => expect(ecra.getByText('Valores guardados.')).toBeTruthy());
  fireEvent.press(await ecra.findByText('Dias'));
  fireEvent.changeText(ecra.getByLabelText('Dias trabalhados (sugeridos: 2)'), '4');
  fireEvent.press(ecra.getByText('Guardar os dias'));
  await waitFor(() => expect(definirDiasEstafeta).toHaveBeenCalledWith('e1', expect.any(String), 4));
  fireEvent.press(await ecra.findByText('Pagar'));
  fireEvent.changeText(ecra.getByLabelText('Referência (obrigatória)'), 'TRF-1');
  fireEvent.press(ecra.getByText(/^Pagar 54/));
  await waitFor(() => expect(pagarEstafetaMes).toHaveBeenCalledWith('e1', expect.any(String), 'Transferência', 'TRF-1'));
});

test('serviço contratado: cria com zonas e paga com fatura', async () => {
  const zonas = [{ id: 'z1', nome: 'Talatona', fornecedor_id: null }, { id: 'z2', nome: 'Viana', fornecedor_id: null }];
  (fornecedoresEntrega as jest.Mock)
    .mockResolvedValueOnce({ mes: '2026-10-01', pode_pagar: true, fornecedores: [], zonas })
    .mockResolvedValue({ mes: '2026-10-01', pode_pagar: true, zonas, fornecedores: [{
      fornecedor_id: 'f1', nome: 'Motas Lda', valor_entrega: 500, valor_mensal: 10000, activo: true, zonas: [{ id: 'z2', nome: 'Viana' }],
      entregas: 2, a_pagar: 11000, pago: false, valor_pago: null, metodo: null, referencia: null, numero_fatura: null, pago_em: null }] });
  const ecra = renderRouter({ 'servico-entregas': ServicoEntregas }, { initialUrl: '/servico-entregas' });
  fireEvent.press(await ecra.findByText('Novo serviço de entregas'));
  fireEvent.changeText(ecra.getByLabelText('Nome do serviço'), 'Motas Lda');
  fireEvent.changeText(ecra.getByLabelText('Valor por entrega (Kz)'), '500');
  fireEvent.changeText(ecra.getByLabelText('Valor mensal (Kz)'), '10000');
  fireEvent.press(ecra.getByText('Viana'));
  fireEvent.press(ecra.getByText('Guardar'));
  await waitFor(() =>
    expect(guardarFornecedorEntrega).toHaveBeenCalledWith({ id: null, nome: 'Motas Lda', valorEntrega: 500, valorMensal: 10000, zonas: ['z2'], activo: true }),
  );
  await waitFor(() => expect(ecra.getByText('Zonas: Viana')).toBeTruthy());
  fireEvent.press(ecra.getByText('Pagar'));
  fireEvent.changeText(ecra.getByLabelText('Referência (obrigatória)'), 'TRF-9');
  fireEvent.changeText(ecra.getByLabelText('Número da fatura do serviço (opcional)'), 'FT 12');
  fireEvent.press(ecra.getByText(/^Pagar 11/));
  await waitFor(() => expect(pagarFornecedorEntrega).toHaveBeenCalledWith('f1', expect.any(String), 'Transferência', 'TRF-9', 'FT 12'));
});

test('resultados: prejuízo e aviso de mês aberto', async () => {
  (resultadosMes as jest.Mock).mockResolvedValue({
    mes: '2026-11-01', fechado: false, pedidos: 5, vendas_cozinhas: 50000,
    receitas: { comissoes: 5000, taxas_entrega: 4000, saldos_expirados: 0, total: 9000 },
    custos: { estafetas: 56300, servico_entregas: 11000, convida_descontos: 1000, convida_ganhos: 300, compensacoes: 700, despesas_gerais: 0, total: 69300 },
    resultado: -60300, custo_por_entrega: 13460,
  });
  const ecra = renderRouter({ resultados: Resultados }, { initialUrl: '/resultados' });
  await waitFor(() => expect(ecra.getByText('Prejuízo do mês')).toBeTruthy());
  expect(ecra.getByText('Mês em curso: os valores ainda vão mudar.')).toBeTruthy();
  expect(ecra.getByText('Custo das entregas por pedido')).toBeTruthy();
});

test('obrigações: totais e avisos', async () => {
  (obrigacoesResumo as jest.Mock).mockResolvedValue({
    a_pagar: { saldos_convida: 1000, levantamentos_pedidos: 0, pacotes_por_consumir: 2000, acertos_cozinhas: 0, compensacoes: 500,
      estafetas_meses_anteriores: 0, servico_entregas_meses_anteriores: 0 },
    a_receber: { acertos_cozinhas: 7255, empresas: 30000, empresas_em_atraso: 30000 },
    por_fechar: { semanas_acertos: 1, vendas_sem_fatura: 31 },
  });
  const ecra = renderRouter({ obrigacoes: Obrigacoes }, { initialUrl: '/obrigacoes' });
  await waitFor(() => expect(ecra.getByText(/31 venda\(s\) sem fatura/)).toBeTruthy());
  expect(ecra.getByText('…das quais em atraso')).toBeTruthy();
  expect(ecra.getByText(/^3\.500/)).toBeTruthy();
});
