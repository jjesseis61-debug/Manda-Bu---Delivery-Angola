/// <reference types="jest" />
import { renderRouter, waitFor } from 'expo-router/testing-library';

import Convida from '@/app/(tabs)/convida';
import { useSessao } from '@/lib/sessao';

jest.mock('@/lib/visitante', () => ({ limparDestino: async () => undefined }));
jest.mock('@/lib/sessao', () => ({ useSessao: jest.fn() }));
jest.mock('@/lib/api', () => ({
  lerSaldo: jest.fn().mockResolvedValue({ ganho_hoje: 0, ganho_semana: 0, saldo_disponivel: 0, em_verificacao: 0 }),
  meusAmigos: jest.fn().mockResolvedValue([]),
  registarPartilha: jest.fn(),
}));
jest.mock('@/components/PainelNivel', () => ({ PainelNivel: () => null }));
jest.mock('@/components/PessoasComoTu', () => ({ PessoasComoTu: () => null }));
jest.mock('@/components/PartilharCodigo', () => ({ PartilharCodigo: () => null }));

function sessao(bonus: number) {
  return {
    carregado: true,
    perfil: { cliente_id: 'c1', codigo: 'MB-1234' },
    parametros: { ganho_por_pedido: 390, desconto_indicado: 1000, bonus_boas_vindas: bonus },
    ligada: (c: string) => c === 'indicacao',
  };
}

test('com bónus: primeira vitória soma o bónus e explica-o', async () => {
  (useSessao as jest.Mock).mockReturnValue(sessao(300));
  const ecra = renderRouter({ convida: Convida }, { initialUrl: '/convida' });
  await waitFor(() => expect(ecra.getByText(/os teus primeiros 690 Kz/)).toBeTruthy());
  expect(ecra.getByText(/Bónus de boas-vindas: \+300 Kz extra na tua primeira comissão/)).toBeTruthy();
});

test('sem bónus: não fala dele', async () => {
  (useSessao as jest.Mock).mockReturnValue(sessao(0));
  const ecra = renderRouter({ convida: Convida }, { initialUrl: '/convida' });
  await waitFor(() => expect(ecra.getByText(/os teus primeiros 390 Kz/)).toBeTruthy());
  expect(ecra.queryByText(/Bónus de boas-vindas/)).toBeNull();
});

test('saldo a expirar: avisa quanto e quando', async () => {
  const { lerSaldo } = jest.requireMock('@/lib/api') as { lerSaldo: jest.Mock };
  lerSaldo.mockResolvedValueOnce({
    ganho_hoje: 0, ganho_semana: 0, saldo_disponivel: 1600, em_verificacao: 0,
    a_expirar_em_breve: 700, proxima_expiracao: '2026-12-01T10:00:00Z', total_expirado: 0,
  });
  (useSessao as jest.Mock).mockReturnValue(sessao(0));
  const ecra = renderRouter({ convida: Convida }, { initialUrl: '/convida' });
  await waitFor(() => expect(ecra.getByText(/700 Kz expiram a partir de/)).toBeTruthy());
});
