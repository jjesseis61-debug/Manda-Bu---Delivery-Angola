/// <reference types="jest" />
import { fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Acertos, { nomeSemana, textoSaldo } from '@/app/acertos';
import { acertosSemana, definirFaturaAcerto, fecharAcerto, registarPagamentoAcerto } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  acertosSemana: jest.fn(),
  fecharAcerto: jest.fn(),
  registarPagamentoAcerto: jest.fn(),
  definirFaturaAcerto: jest.fn(),
}));
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, sessao: {}, funcionario: { id: 'f', cozinhas_equipa: [] }, pode: () => true }),
}));

const totais = { pedidos: 2, vendas: 13000, taxas_entrega: 3000, comissao: 1300, convida_plataforma: 1000, pago_pacote: 5000, valor_empresa: 0, saldo: -1700 };
const semana = (estado: 'aberto' | 'fechado' | 'pago', pago = 0) => ({
  semana_inicio: '2026-11-09',
  semana_fim: '2026-11-15',
  pode_fechar: true,
  cozinhas: [
    {
      cozinha_id: 'cz', cozinha_nome: 'Tia Rosa', acerto_id: estado === 'aberto' ? null : 'a1', estado,
      numero_fatura: null, totais, comissao_percent: 10, pago, por_pagar: estado === 'fechado' ? 1700 - pago : 0,
    },
  ],
});

beforeEach(() => jest.clearAllMocks());

test('nome da semana e texto do saldo', () => {
  expect(nomeSemana('2026-11-09', '2026-11-15')).toBe('9–15 nov 2026');
  expect(nomeSemana('2026-10-26', '2026-11-01')).toBe('26 out – 1 nov 2026');
  expect(textoSaldo(1800)).toBe('A cozinha paga 1.800 Kz');
  expect(textoSaldo(-1700)).toBe('A plataforma paga 1.700 Kz');
  expect(textoSaldo(0)).toBe('Nada a acertar');
});

test('semana aberta: mostra as contas e fecha a semana', async () => {
  (acertosSemana as jest.Mock).mockResolvedValue(semana('aberto'));
  (fecharAcerto as jest.Mock).mockResolvedValue('a1');
  const ecra = renderRouter({ acertos: Acertos }, { initialUrl: '/acertos' });
  await waitFor(() => expect(ecra.getByText('Tia Rosa')).toBeTruthy());
  expect(ecra.getByText('9–15 nov 2026')).toBeTruthy();
  expect(ecra.getByText('Comissão (10%)')).toBeTruthy();
  expect(ecra.getByText('A plataforma paga 1.700 Kz')).toBeTruthy();
  fireEvent.press(ecra.getByText('Fechar a semana'));
  await waitFor(() => expect(fecharAcerto).toHaveBeenCalledWith('cz', '2026-11-09'));
});

test('semana fechada: regista o pagamento e o número da fatura', async () => {
  (acertosSemana as jest.Mock).mockResolvedValue(semana('fechado'));
  (registarPagamentoAcerto as jest.Mock).mockResolvedValue({ pago: 1700, falta: 0, estado: 'pago' });
  const ecra = renderRouter({ acertos: Acertos }, { initialUrl: '/acertos' });
  await waitFor(() => expect(ecra.getByText('Por pagar')).toBeTruthy());
  expect(ecra.getByText('A pagar às cozinhas')).toBeTruthy();
  fireEvent.press(ecra.getByText('Registar pagamento'));
  fireEvent.changeText(ecra.getByLabelText('Referência (obrigatória)'), 'TRF-0042');
  fireEvent.press(ecra.getByText('Registar o que a plataforma pagou'));
  await waitFor(() => expect(registarPagamentoAcerto).toHaveBeenCalledWith('a1', 1700, 'Transferência', 'TRF-0042'));
  fireEvent.press(ecra.getByText('Número da fatura'));
  fireEvent.changeText(ecra.getByLabelText('Número da fatura (software certificado)'), 'FT 2026/118');
  fireEvent.press(ecra.getByText('Guardar o número'));
  await waitFor(() => expect(definirFaturaAcerto).toHaveBeenCalledWith('a1', 'FT 2026/118'));
});
