/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Conferencia from '@/app/conferencia';
import { abrirInvestigacoes, decidirCaso, lerCasosInvestigacao, lerExtratos } from '@/lib/api';

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
  lerCasosInvestigacao: jest.fn(),
  abrirInvestigacoes: jest.fn(),
  decidirCaso: jest.fn(),
  investigarDeNovo: jest.fn(),
}));
jest.mock('@/lib/fotos', () => ({ enviarExtrato: jest.fn(), escolherFicheiroExtrato: jest.fn(), escolherFoto: jest.fn() }));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: ['c1'] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const caso = {
  id: 'k1', funcionario: 'Rui Mateus', cargo: 'Estafeta', inicio: '2026-09-01', fim: '2026-09-30',
  sinais: { comprovativos: 40, rejeitados: 1, nao_conferem: 2, ilegiveis: 0, sem_extrato: 2, valor_sem_extrato: 7500,
            caixas_com_diferenca: 0, soma_diferencas: 0 },
  pontuacao: 13, estado: 'investigado', ia_nota: null, risco: 'medio',
  resumo: 'Dois pagamentos sem extrato; um parece referência mal escrita.',
  conclusao: {
    factos: [{ texto: 'MCX-9003 (3.500 Kz) não está no extrato; há 3.500 Kz com MCX-9030 no dia anterior.', pedido_id: 'p9' }],
    explicacoes_possiveis: ['Referência mal escrita'], recomendacao: 'Pedir o talão ao Rui.',
    perguntas_ao_funcionario: ['Tens o talão do MCX-9003?'],
  },
  passos: [{ ferramenta: 'comprovativos_do_funcionario', entrada: {}, resultado: '' },
           { ferramenta: 'entradas_do_extrato_parecidas', entrada: {}, resultado: '' }],
  investigado_em: '2026-10-03T10:00:00Z', decisao: null, decisao_nota: null, decidido_por: null, decidido_em: null,
  criado_em: '2026-10-03T09:00:00Z',
};

beforeEach(() => {
  jest.clearAllMocks();
  (lerExtratos as jest.Mock).mockResolvedValue([]);
  (lerCasosInvestigacao as jest.Mock).mockResolvedValue([caso]);
});

test('investigações: dossiê do agente, o que consultou e decisão humana', async () => {
  const ecra = renderRouter({ conferencia: Conferencia }, { initialUrl: '/conferencia' });
  fireEvent.press(ecra.getByText('Investigações'));
  await waitFor(() => expect(ecra.getByText(/Risco médio: Dois pagamentos sem extrato/)).toBeTruthy());
  fireEvent.press(ecra.getByText('Ver dossiê e decidir'));
  expect(ecra.getByText(/há 3\.500 Kz com MCX-9030/)).toBeTruthy();
  expect(ecra.getByText('• Tens o talão do MCX-9003?')).toBeTruthy();
  expect(ecra.getByText('2. Procurou entradas parecidas no extrato')).toBeTruthy();
  fireEvent.changeText(ecra.getByLabelText('Nota (o que se confirmou)'), 'Era o MCX-9030, mal escrito.');
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar decisão'));
  });
  expect(decidirCaso).toHaveBeenCalledWith('k1', 'erro_operacional', 'Era o MCX-9030, mal escrito.');
});

test('abrir as investigações de um período', async () => {
  (abrirInvestigacoes as jest.Mock).mockResolvedValue(2);
  const ecra = renderRouter({ conferencia: Conferencia }, { initialUrl: '/conferencia' });
  fireEvent.press(ecra.getByText('Investigações'));
  fireEvent.changeText(ecra.getByLabelText('De (AAAA-MM-DD)'), '2026-09-01');
  fireEvent.changeText(ecra.getByLabelText('Até (AAAA-MM-DD)'), '2026-09-30');
  await act(async () => {
    fireEvent.press(ecra.getByText('Abrir investigações do período'));
  });
  expect(abrirInvestigacoes).toHaveBeenCalledWith('2026-09-01', '2026-09-30');
  expect(ecra.getByText(/2 caso\(s\) aberto\(s\)/)).toBeTruthy();
});
