/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Pacotes from '@/app/pacotes';
import { adesoesPacote, caixasAbertas, confirmarPagamentoPacote, reembolsarPacote } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  adesoesPacote: jest.fn(),
  caixasAbertas: jest.fn(),
  confirmarPagamentoPacote: jest.fn(),
  reembolsarPacote: jest.fn(),
  lerCatalogoPacotes: jest.fn(async () => []),
  guardarPacote: jest.fn(),
}));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1' }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const base = {
  pacote: 'Almoço do Mês',
  cliente_nome: 'Ana Sousa',
  cliente_telefone: null,
  preco: 50000,
  refeicoes_total: 22,
  refeicoes_usadas: 2,
  inicio: null,
  fim: null,
  referencia: null,
  criado_em: '2026-10-02T09:00:00Z',
  reembolso_previsto: 45000,
  valor_reembolso: null,
};

beforeEach(() => {
  jest.clearAllMocks();
  (caixasAbertas as jest.Mock).mockResolvedValue([{ id: 'cx1', posto: 'Balcão', data: '2026-10-02', cozinha_id: 'k1' }]);
});

function abrir() {
  return renderRouter({ pacotes: Pacotes }, { initialUrl: '/pacotes' });
}

test('Multicaixa Express: só confirma com a referência', async () => {
  (adesoesPacote as jest.Mock).mockResolvedValue([{ ...base, adesao_id: 'a1', estado: 'pendente', metodo: 'multicaixa_express' }]);
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Ana Sousa · Almoço do Mês')).toBeTruthy());
  fireEvent.press(ecra.getByText('Confirmar pagamento'));
  fireEvent.changeText(ecra.getByDisplayValue(''), ' MCX-123 ');
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Confirmar pagamento')[0]);
  });
  expect(confirmarPagamentoPacote).toHaveBeenCalledWith('a1', 'MCX-123', null);
});

test('na loja: confirma com o caixa aberto, sem referência', async () => {
  (adesoesPacote as jest.Mock).mockResolvedValue([{ ...base, adesao_id: 'a2', estado: 'pendente', metodo: 'loja' }]);
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Na loja')).toBeTruthy());
  fireEvent.press(ecra.getByText('Confirmar pagamento'));
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Confirmar pagamento')[0]);
  });
  expect(confirmarPagamentoPacote).toHaveBeenCalledWith('a2', null, 'cx1');
});

test('activos: mostra o valor a devolver e reembolsa', async () => {
  (adesoesPacote as jest.Mock).mockResolvedValue([{ ...base, adesao_id: 'a3', estado: 'activa', metodo: 'unitel_money' }]);
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Activos')).toBeTruthy());
  await act(async () => {
    fireEvent.press(ecra.getByText('Activos'));
  });
  await waitFor(() => expect(ecra.getByText('Reembolsar')).toBeTruthy());
  fireEvent.press(ecra.getByText('Reembolsar'));
  expect(ecra.getByText(/Devolver 45.000 Kz/)).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Reembolsar')[0]);
  });
  expect(reembolsarPacote).toHaveBeenCalledWith('a3', '');
});
