/// <reference types="jest" />
import { renderRouter, waitFor } from 'expo-router/testing-library';

import SaldosExpirados from '@/app/saldos-expirados';
import { relatorioSaldosExpirados } from '@/lib/api';
import { linhasCsvExpirados } from '@/lib/relatorio';

jest.mock('@/lib/api', () => ({ relatorioSaldosExpirados: jest.fn() }));
jest.mock('@/lib/exportar', () => ({ escaparHtml: (t: string) => t, exportarCsv: jest.fn() }));
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, sessao: {}, funcionario: { id: 'f', cozinhas_equipa: [] }, pode: () => true }),
}));

const rel = {
  periodo: { inicio: '2027-11-01', fim: '2027-11-30' },
  validade_meses: 12,
  resumo: { total: 900, expiracoes: 1, clientes: 1, media: 900, maior: 900, avisados: 1 },
  por_mes: [{ mes: '2027-11', valor: 900, clientes: 1 }],
  lista: [{
    id: 'e1', data: '2027-11-15T02:10:00Z', cliente_id: 'c1', nome: 'Ana Saldo', telefone: '923111222', codigo: 'MB-1234',
    nivel: 'normal', valor: 900, ganhos_ate: '2026-11-15T02:10:00Z', ganhos_antigos: 1500, usado: 600, saldo_antes: 1600, avisado: true,
  }],
  a_expirar: { d30: 700, clientes_30: 1, d60: 700, clientes_60: 1, d90: 1200, clientes_90: 2 },
  a_expirar_lista: [{ cliente_id: 'c1', nome: 'Ana Saldo', telefone: '923111222', valor: 700, em_30_dias: 700, expira_em: '2027-11-25T10:00:00Z', saldo: 700 }],
  saldo_activo_total: 25000,
  expirado_sempre: 900,
};

test('saldos expirados: resumo, a expirar e lista', async () => {
  (relatorioSaldosExpirados as jest.Mock).mockResolvedValue(rel);
  const ecra = renderRouter({ 'saldos-expirados': SaldosExpirados }, { initialUrl: '/saldos-expirados' });
  await waitFor(() => expect(ecra.getByText('Total expirado')).toBeTruthy());
  expect(ecra.getAllByText('900 Kz').length).toBeGreaterThan(0);
  expect(ecra.getAllByText('700 Kz · 1 clientes').length).toBe(2);
  expect(ecra.getByText('1.200 Kz · 2 clientes')).toBeTruthy();
  expect(ecra.getByText(/Ganhos antigos 1.500 Kz · já usados 600 Kz/)).toBeTruthy();
  expect(ecra.getByText('1 de 1')).toBeTruthy();
});

test('CSV: resumo, por mês, expirações e a expirar', () => {
  const l = linhasCsvExpirados(rel);
  expect(l[2]).toEqual(['Total expirado (Kz)', 900]);
  expect(l.find((x) => x[0] === '2027-11-15')).toEqual(['2027-11-15', 'Ana Saldo', '923111222', 'MB-1234', 'normal', 900, 1500, 600, 1600, 'sim']);
  expect(l.at(-1)).toEqual(['Ana Saldo', '923111222', 700, 700, '2027-11-25', 700]);
});
