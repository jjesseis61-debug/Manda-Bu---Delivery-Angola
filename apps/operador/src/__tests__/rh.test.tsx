/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import EquipaRH from '@/app/rh';
import FichaRH from '@/app/rh/[id]';
import FolhaSalarios from '@/app/rh-folha';
import ParametrosRH from '@/app/rh-parametros';
import {
  rhFicha,
  rhFolha,
  rhFolhaAjustar,
  rhFolhaFechar,
  rhFolhaPagar,
  rhGuardarContrato,
  rhGuardarParametros,
  rhLista,
  rhParametros,
  rhSimular,
} from '@/lib/rh';

jest.mock('@/lib/supabase', () => ({ supabase: {} }));
jest.mock('@/lib/rh', () => ({
  ...jest.requireActual('@/lib/rh'),
  rhLista: jest.fn(),
  rhFicha: jest.fn(),
  rhGuardarFicha: jest.fn(),
  rhGuardarDocumento: jest.fn(),
  rhApagarDocumento: jest.fn(),
  rhGuardarContrato: jest.fn(),
  rhTerminarContrato: jest.fn(),
  rhGuardarEquipamento: jest.fn(),
  rhDevolverEquipamento: jest.fn(),
  rhSimular: jest.fn(),
  rhFolha: jest.fn(),
  rhFolhaAjustar: jest.fn(),
  rhFolhaFechar: jest.fn(),
  rhFolhaPagar: jest.fn(),
  rhParametros: jest.fn(),
  rhGuardarParametros: jest.fn(),
}));
const mockSessao = { carregado: true, sessao: {}, funcionario: { funcionario_id: 'f', cozinhas_equipa: [] }, pode: (_p: string) => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

beforeEach(() => {
  jest.clearAllMocks();
  mockSessao.pode = () => true;
});

test('equipa: contrato, salário e avisos', async () => {
  (rhLista as jest.Mock).mockResolvedValue([
    { funcionario_id: 'a', nome: 'Ana', cargo: 'Cozinheira', telefone: null, admissao: '2026-01-01', equipamentos: 0,
      contrato: { tipo: 'indeterminado', inicio: '2026-01-01', fim: null, salario_base: 200000 }, alertas: ['Caduca em breve: declaracao saude (01/12/2026)'] },
    { funcionario_id: 'b', nome: 'Rui', cargo: 'Estafeta', telefone: null, admissao: '2026-01-01', equipamentos: 1, contrato: null, alertas: ['Sem contrato registado'] },
  ]);
  const ecra = renderRouter({ 'rh/index': EquipaRH }, { initialUrl: '/rh' });
  await waitFor(() => expect(ecra.getByText('2 pessoas com avisos')).toBeTruthy());
  expect(ecra.getByText('200.000 Kz')).toBeTruthy();
  expect(ecra.getByText('Cozinheira · Sem prazo (tempo indeterminado)')).toBeTruthy();
  expect(ecra.getByText('⚠ Sem contrato registado')).toBeTruthy();
  expect(ecra.getByText('1 equipamento(s) entregue(s)')).toBeTruthy();
});

test('ficha: novo contrato com o salário simulado (INSS e IRT)', async () => {
  (rhFicha as jest.Mock).mockResolvedValue({
    funcionario_id: 'a', nome: 'Ana', cargo: 'Cozinheira', telefone: '923000001', ficha: null, documentos: [], contratos: [], equipamentos: [],
    alertas: ['Sem contrato registado'],
  });
  (rhSimular as jest.Mock).mockResolvedValue({ bruto: 270000, inss_trabalhador: 8100, inss_empresa: 21600, isento: 60000,
    materia_colectavel: 201900, irt: 31592, liquido: 230308, custo_empresa: 291600 });
  const ecra = renderRouter({ 'rh/[id]': FichaRH }, { initialUrl: '/rh/a' });
  await waitFor(() => expect(ecra.getByText('Sem contrato registado.')).toBeTruthy());
  fireEvent.press(ecra.getByText('Registar contrato'));
  expect(ecra.getByLabelText('Período experimental (dias)').props.value).toBe('60');
  fireEvent.changeText(ecra.getByLabelText('Início (DD/MM/AAAA)'), '01112026');
  fireEvent.changeText(ecra.getByLabelText('Salário base (Kz)'), '200000');
  fireEvent.changeText(ecra.getByLabelText('Subsídio de alimentação (Kz)'), '30000');
  fireEvent.changeText(ecra.getByLabelText('Subsídio de transporte (Kz)'), '40000');
  await waitFor(() => expect(ecra.getByText('230.308 Kz')).toBeTruthy(), { timeout: 2000 });
  expect(rhSimular).toHaveBeenLastCalledWith(200000, 30000, 40000, 0);
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar o contrato'));
  });
  expect(rhGuardarContrato).toHaveBeenCalledWith(
    expect.objectContaining({ funcionario_id: 'a', tipo: 'indeterminado', inicio: '2026-11-01', salario_base: 200000,
      subsidio_alimentacao: 30000, subsidio_transporte: 40000, periodo_experimental_dias: 60 }),
  );
});

const linha = {
  funcionario_id: 'a', nome: 'Ana', tipo: 'indeterminado', dias: 30, salario_base: 200000, sub_alimentacao: 30000, sub_transporte: 40000,
  outros_subsidios: 0, extras: 0, sub_ferias: 0, sub_natal: 0, descontos: 0, bruto: 270000, inss_trabalhador: 8100, inss_empresa: 21600,
  materia_colectavel: 201900, irt: 31592, liquido: 230308, nota: null, pago_em: null, metodo: null, referencia: null,
};
const totais = { bruto: 270000, inss_trabalhador: 8100, inss_empresa: 21600, irt: 31592, liquido: 230308, custo_empresa: 291600, por_pagar: 230308 };

test('folha: ajustar, fechar e pagar', async () => {
  (rhFolha as jest.Mock)
    .mockResolvedValueOnce({ mes: '2026-10-01', fechada: false, pode_fechar: true, linhas: [linha], totais, prestadores: [{ nome: 'Rui', funcao: 'Estafeta' }] })
    .mockResolvedValueOnce({ mes: '2026-10-01', fechada: false, pode_fechar: true, linhas: [linha], totais, prestadores: [] })
    .mockResolvedValue({ mes: '2026-10-01', fechada: true, pode_fechar: true, linhas: [linha], totais, prestadores: [] });
  const ecra = renderRouter({ 'rh-folha': FolhaSalarios }, { initialUrl: '/rh-folha' });
  await waitFor(() => expect(ecra.getByText('Folha em preparação (os valores ainda podem mudar)')).toBeTruthy());
  expect(ecra.getByText('A entregar ao Estado: Segurança Social 29.700 Kz e IRT 31.592 Kz.')).toBeTruthy();
  expect(ecra.getByText('Rui · Estafeta')).toBeTruthy();
  fireEvent.press(ecra.getByText('Ajustar'));
  fireEvent.changeText(ecra.getByLabelText('Horas extra e prémios (Kz)'), '10000');
  fireEvent(ecra.getByLabelText('Subsídio de férias'), 'valueChange', true);
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar o ajuste'));
  });
  expect(rhFolhaAjustar).toHaveBeenCalledWith(expect.any(String), 'a', { extras: 10000, descontos: 0, subFerias: true, subNatal: false, nota: null });
  await waitFor(() => expect(ecra.getByText('Fechar a folha do mês')).toBeTruthy());
  fireEvent.press(ecra.getByText('Fechar a folha do mês'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Sim, fechar a folha'));
  });
  expect(rhFolhaFechar).toHaveBeenCalled();
  await waitFor(() => expect(ecra.getByText('Por pagar')).toBeTruthy());
  fireEvent.press(ecra.getByText('Pagar'));
  fireEvent.changeText(ecra.getByLabelText('Referência (obrigatória)'), 'TRF-9');
  await act(async () => {
    fireEvent.press(ecra.getByText('Pagar 230.308 Kz'));
  });
  expect(rhFolhaPagar).toHaveBeenCalledWith(expect.any(String), 'a', 'Transferência', 'TRF-9');
});

test('folha: quem só paga não ajusta; quem só calcula não paga', async () => {
  mockSessao.pode = (p: string) => p === 'financas.salarios';
  (rhFolha as jest.Mock).mockResolvedValue({ mes: '2026-10-01', fechada: false, pode_fechar: true, linhas: [linha], totais, prestadores: [] });
  const ecra = renderRouter({ 'rh-folha': FolhaSalarios }, { initialUrl: '/rh-folha' });
  await waitFor(() => expect(ecra.getByText('Ana')).toBeTruthy());
  expect(ecra.queryByText('Ajustar')).toBeNull();
  expect(ecra.queryByText('Fechar a folha do mês')).toBeNull();
});

test('parâmetros: tabela do IRT editável', async () => {
  (rhParametros as jest.Mock).mockResolvedValue({
    parametros: { inss_trabalhador: 3, inss_empresa: 8, isencao_alimentacao: 30000, isencao_transporte: 30000, subsidio_ferias_pct: 50,
      subsidio_natal_pct: 50, referencia_legal: 'Lei n.º 14/25', atualizado_em: '2026-11-21T10:00:00Z' },
    escaloes: [
      { ordem: 1, limite_inferior: 0, limite_superior: 150000, parcela_fixa: 0, taxa: 0, excesso: 0 },
      { ordem: 2, limite_inferior: 150001, limite_superior: null, parcela_fixa: 12500, taxa: 16, excesso: 150000 },
    ],
  });
  const ecra = renderRouter({ 'rh-parametros': ParametrosRH }, { initialUrl: '/rh-parametros' });
  await waitFor(() => expect(ecra.getByText('2.º escalão: 150.001 Kz ou mais')).toBeTruthy());
  fireEvent.changeText(ecra.getByLabelText('Segurança Social do trabalhador (%)'), '3,5');
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar as taxas e a tabela'));
  });
  expect(rhGuardarParametros).toHaveBeenCalledWith(
    expect.objectContaining({
      inss_trabalhador: 3.5, inss_empresa: 8, isencao_alimentacao: 30000,
      escaloes: [
        { limite_inferior: 0, limite_superior: 150000, parcela_fixa: 0, taxa: 0, excesso: 0 },
        { limite_inferior: 150001, limite_superior: null, parcela_fixa: 12500, taxa: 16, excesso: 150000 },
      ],
    }),
  );
});
