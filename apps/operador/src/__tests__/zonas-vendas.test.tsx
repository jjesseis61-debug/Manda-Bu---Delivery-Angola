/// <reference types="jest" />
import { renderRouter, waitFor } from 'expo-router/testing-library';

import ZonasVendas from '@/app/zonas-vendas';
import { vendasPorZona } from '@/lib/api';
import { linhasCsvZonas, tendencia } from '@/lib/relatorio';

jest.mock('@/lib/api', () => ({ vendasPorZona: jest.fn() }));
jest.mock('@/lib/exportar', () => ({ escaparHtml: (t: string) => t, exportarCsv: jest.fn() }));
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, sessao: {}, funcionario: { id: 'f', cozinhas_equipa: [] }, pode: () => true }),
}));

const zonas = [{
  zona: 'Maianga', pedidos: 33, vendas: 90000, cozinhas: 2,
  pratos: [{ nome: 'Choco frito', qtd: 27, receita: 54000, qtd_anterior: 0, cozinha_top: 'Viana' }],
  opcoes: [{ nome: 'Arroz', qtd: 4 }],
  a_crescer: [{ nome: 'Choco frito', qtd: 27, qtd_anterior: 10 }],
}];

test('o que se compra em cada zona: pratos, cozinha que mais vende e a crescer', async () => {
  (vendasPorZona as jest.Mock).mockResolvedValue({ zonas });
  const ecra = renderRouter({ 'zonas-vendas': ZonasVendas }, { initialUrl: '/zonas-vendas' });
  await waitFor(() => expect(ecra.getByText('Maianga')).toBeTruthy());
  expect(ecra.getByText('1. Choco frito · Viana')).toBeTruthy();
  expect(ecra.getByText('27× · novo')).toBeTruthy();
  expect(ecra.getByText('A crescer: Choco frito (10→27)')).toBeTruthy();
});

test('tendência e CSV', () => {
  expect(tendencia(27, 10)).toBe('▲ 170%');
  expect(tendencia(8, 10)).toBe('▼ 20%');
  expect(tendencia(5, 5)).toBe('=');
  expect(tendencia(3, 0)).toBe('novo');
  expect(linhasCsvZonas(zonas)[1]).toEqual(['Maianga', 'Choco frito', 27, 54000, 0, 'Viana']);
});
