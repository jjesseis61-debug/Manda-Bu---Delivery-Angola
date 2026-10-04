/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Compras from '@/app/compras';
import { lerCozinhas, lerPlanosCompras, marcarCompra, pedirPlanoCompras } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  lerCozinhas: jest.fn(),
  lerPlanosCompras: jest.fn(),
  marcarCompra: jest.fn(),
  pedirPlanoCompras: jest.fn(),
}));
const mockSessao = {
  carregado: true,
  sessao: {},
  funcionario: { id: 'f1', administrador_principal: false, cozinhas_equipa: ['c1'] },
  pode: (p: string) => p === 'stock.gerir',
};
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const plano = {
  id: 'pl1', cozinha_id: 'c1', cozinha: 'Viana', dia: '2026-10-03', origem: 'automatico', pedido_por: null, estado: 'pronto',
  resumo: 'O arroz chega para 10 dias; comprar peixe hoje.', criado_em: '2026-10-03T05:15:00Z', pronto_em: '2026-10-03T05:16:00Z',
  compras: [
    { produto_id: null, produto: 'Peixe carapau', quantidade: 5, unidade: 'kg', urgencia: 'hoje', custo_estimado: 15000,
      fornecedor: 'Mercado A', motivo: 'Compra diária para o calulu.', estado: 'pendente' },
    { produto_id: 'a1', produto: 'Arroz agulha', quantidade: 10, unidade: 'kg', urgencia: 'esta_semana', custo_estimado: null,
      fornecedor: null, motivo: 'Cobertura de 10 dias.', estado: 'comprado', decidido_por: 'Sara Stock' },
  ],
  alertas: [{ tipo: 'desvio', gravidade: 'alta', produto: 'Arroz agulha', texto: 'Faltam 500 g de ontem.' }],
};

beforeEach(() => {
  jest.clearAllMocks();
  (lerCozinhas as jest.Mock).mockResolvedValue([{ id: 'c1', nome: 'Viana' }, { id: 'c2', nome: 'Kilamba' }]);
});

test('stock e compras: mostra o plano das suas cozinhas, marca uma compra e desfaz outra', async () => {
  (lerPlanosCompras as jest.Mock).mockResolvedValue([plano]);
  const ecra = renderRouter({ compras: Compras }, { initialUrl: '/compras' });
  await waitFor(() => expect(ecra.getByText('Peixe carapau: 5 kg')).toBeTruthy());
  expect(ecra.queryByText('Kilamba')).toBeNull();
  expect(ecra.getByText('Comprar hoje · cerca de 15.000 Kz · Mercado A')).toBeTruthy();
  expect(ecra.getByText('Saída sem explicação · Arroz agulha: Faltam 500 g de ontem.')).toBeTruthy();
  expect(ecra.getByText('Comprado por Sara Stock')).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getByText('Comprado'));
  });
  expect(marcarCompra).toHaveBeenCalledWith('pl1', 0, 'comprado');
  await act(async () => {
    fireEvent.press(ecra.getByText('Desfazer'));
  });
  expect(marcarCompra).toHaveBeenCalledWith('pl1', 1, 'pendente');
});

test('stock e compras: sem plano, pede um agora', async () => {
  (lerPlanosCompras as jest.Mock).mockResolvedValue([]);
  (pedirPlanoCompras as jest.Mock).mockResolvedValue('pl2');
  const ecra = renderRouter({ compras: Compras }, { initialUrl: '/compras' });
  await waitFor(() => expect(ecra.getByText('Ainda não há plano de compras para esta cozinha.')).toBeTruthy());
  await act(async () => {
    fireEvent.press(ecra.getByText('Pedir plano agora'));
  });
  expect(pedirPlanoCompras).toHaveBeenCalledWith('c1');
});
