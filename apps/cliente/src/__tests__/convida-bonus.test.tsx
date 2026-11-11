/// <reference types="jest" />
import { renderRouter, waitFor } from 'expo-router/testing-library';

import Convida from '@/app/(tabs)/convida';
import { useSessao } from '@/lib/sessao';

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
