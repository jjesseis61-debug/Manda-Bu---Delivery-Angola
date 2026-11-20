/// <reference types="jest" />
import { fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Compensacoes from '@/app/compensacoes';
import ContasEmpresas, { mesAoLado, nomeMes, vencimentoSugerido } from '@/app/contas-empresas';
import Faturas from '@/app/faturas';
import {
  compensacoesLista,
  contasEmpresas,
  definirCargoCompensacao,
  emitirFaturaEmpresa,
  pagarCompensacao,
  pagarFaturaEmpresa,
  registarFaturaPedido,
  vendasSemFatura,
} from '@/lib/api';

jest.mock('@/lib/api', () => ({
  vendasSemFatura: jest.fn(),
  registarFaturaPedido: jest.fn(),
  compensacoesLista: jest.fn(),
  definirCargoCompensacao: jest.fn(),
  pagarCompensacao: jest.fn(),
  contasEmpresas: jest.fn(),
  emitirFaturaEmpresa: jest.fn(),
  pagarFaturaEmpresa: jest.fn(),
}));
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, sessao: {}, funcionario: { id: 'f', cozinhas_equipa: [] }, pode: () => true }),
}));

beforeEach(() => jest.clearAllMocks());

test('faturas: regista o número com o emissor por defeito da cozinha', async () => {
  (vendasSemFatura as jest.Mock).mockResolvedValue([
    { pedido_id: 'p1', entregue_em: '2026-11-18T12:00:00Z', cozinha_id: 'cz', cozinha_nome: 'Viana', faturacao: 'cozinha',
      cliente_nome: 'Ana', cliente_nif: '5000123', valor: 9500 },
  ]);
  const ecra = renderRouter({ faturas: Faturas }, { initialUrl: '/faturas' });
  await waitFor(() => expect(ecra.getByText('1 venda sem fatura')).toBeTruthy());
  expect(ecra.getByText('Ana · NIF 5000123')).toBeTruthy();
  fireEvent.press(ecra.getByText('Registar a fatura'));
  fireEvent.changeText(ecra.getByLabelText('Número da fatura'), 'FT V/12');
  fireEvent.press(ecra.getByText('Guardar'));
  await waitFor(() => expect(registarFaturaPedido).toHaveBeenCalledWith('p1', 'FT V/12', 'cozinha'));
  await waitFor(() => expect(ecra.getByText('Todas as vendas têm fatura.')).toBeTruthy());
});

const comp = {
  id: 'c1', criado_em: '2026-11-18T12:00:00Z', pedido_id: 'p1', cliente_nome: 'Joana', cliente_telefone: '923000003',
  cozinha_nome: 'Viana', tipo: 'reembolso_parcial', valor: 800, a_cargo: 'cozinha', estado: 'por_pagar',
  metodo: null, referencia: null, pago_em: null, categoria: 'qualidade', reclamacao: 'Veio fria',
};

test('compensações: muda o cargo e paga ao cliente', async () => {
  (compensacoesLista as jest.Mock).mockResolvedValue([comp]);
  const ecra = renderRouter({ compensacoes: Compensacoes }, { initialUrl: '/compensacoes' });
  await waitFor(() => expect(ecra.getByText('800 Kz')).toBeTruthy());
  expect(ecra.getByText('A cargo da cozinha (entra no acerto)')).toBeTruthy();
  fireEvent.press(ecra.getByText('Passar para a plataforma'));
  await waitFor(() => expect(definirCargoCompensacao).toHaveBeenCalledWith('c1', 'plataforma'));
  fireEvent.press(ecra.getByText('Pagar'));
  fireEvent.changeText(ecra.getByLabelText('Referência (obrigatória)'), 'UM-123');
  fireEvent.press(ecra.getByText('Pagar ao cliente'));
  await waitFor(() => expect(pagarCompensacao).toHaveBeenCalledWith('c1', 'Unitel Money', 'UM-123'));
});

test('contas das empresas: mês, fatura e pagamento', async () => {
  expect(nomeMes('2026-10-01')).toBe('outubro de 2026');
  expect(mesAoLado('2026-12-01', 1)).toBe('2027-01-01');
  expect(vencimentoSugerido('2026-10-01')).toBe('2026-11-15');
  (contasEmpresas as jest.Mock)
    .mockResolvedValueOnce({ mes: '2026-10-01', pode_faturar: true, em_atraso_total: 0, empresas: [
      { empresa_id: 'e1', nome: 'Sonangol', valor: 30000, pedidos: 10, fatura_id: null, numero: null, vencimento: null,
        estado: 'por_faturar', pago_em: null, referencia: null, em_atraso: null }] })
    .mockResolvedValue({ mes: '2026-10-01', pode_faturar: true, em_atraso_total: 30000, empresas: [
      { empresa_id: 'e1', nome: 'Sonangol', valor: 30000, pedidos: 10, fatura_id: 'f1', numero: 'FT 2026/90', vencimento: '2026-11-15',
        estado: 'emitida', pago_em: null, referencia: null, em_atraso: true }] });
  const ecra = renderRouter({ 'contas-empresas': ContasEmpresas }, { initialUrl: '/contas-empresas' });
  await waitFor(() => expect(ecra.getByText('Por faturar')).toBeTruthy());
  expect(ecra.getByText('10 almoços')).toBeTruthy();
  fireEvent.press(ecra.getByText('Registar a fatura do mês'));
  fireEvent.changeText(ecra.getByLabelText('Número da fatura'), 'FT 2026/90');
  fireEvent.press(ecra.getByText('Registar a fatura'));
  await waitFor(() => expect(emitirFaturaEmpresa).toHaveBeenCalledWith('e1', '2026-10-01', 'FT 2026/90', '2026-11-15'));
  await waitFor(() => expect(ecra.getByText('Em atraso')).toBeTruthy());
  expect(ecra.getByText('Em atraso (todas as empresas): 30.000 Kz')).toBeTruthy();
  fireEvent.press(ecra.getByText('Registar o pagamento'));
  fireEvent.changeText(ecra.getByLabelText('Referência (obrigatória)'), 'TRF-1');
  fireEvent.press(ecra.getAllByText('Registar o pagamento').at(-1)!);
  await waitFor(() => expect(pagarFaturaEmpresa).toHaveBeenCalledWith('f1', 'Transferência', 'TRF-1'));
});
