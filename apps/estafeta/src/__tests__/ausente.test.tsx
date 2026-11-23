/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';

import Entrega from '@/app/entrega/[id]';

jest.mock('@/components/Guarda', () => ({ Guarda: ({ children }: { children: unknown }) => children }));
jest.mock('@/components/MapaEntregas', () => ({ MapaEntregas: () => null }));
jest.mock('@/lib/fotos', () => ({ enviarComprovativo: jest.fn(), escolherFoto: jest.fn() }));
jest.mock('@/lib/entregasCache', () => ({ guardarCaixasCache: async () => undefined, lerCaixasCache: async () => [], lerEntregasCache: async () => [] }));
jest.mock('@/lib/filaOffline', () => ({ enfileirar: jest.fn(), pedidosNaFila: async () => new Set() }));
jest.mock('@/lib/sincronizar', () => ({ semRede: () => false }));
const mockAusencia = jest.fn(async (..._a: unknown[]) => 1);
jest.mock('@/lib/api', () => ({
  caixasAbertas: async () => [],
  mudarEstado: jest.fn(),
  registarAusencia: (...a: unknown[]) => mockAusencia(...a),
  pedidosOperador: async () => [
    {
      pedido_id: 'p1', criado_em: '2026-11-23T10:00:00Z', estado: 'em_entrega', cozinha_id: 'k1', cliente_nome: 'Carla', cliente_telefone: null,
      itens: [{ nome: 'Muamba', qtd: 1, preco_unitario: 3000 }], subtotal: 3000, taxa_entrega: 700, desconto_indicacao: 0,
      credito_indicacao_usado: 0, a_pagar: 3700, observacoes: null, hora_prometida: null, pagador_distinto: null,
      ponto_entrega_id: null, ponto_tipo: null, ponto_lat: null, ponto_lng: null, ponto_referencia: 'Casa da Carla', zona_nome: 'Maianga',
      atribuido_a: null, atribuido_a_nome: null, atribuido_a_mim: true, minha: true,
    },
  ],
}));

test('em entrega: regista «cliente ausente» com a nota e diz o que fazer a seguir', async () => {
  const ecra = renderRouter({ 'entrega/[id]': Entrega }, { initialUrl: '/entrega/p1' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Cliente ausente / não atende'));
  fireEvent.changeText(ecra.getByLabelText('Nota (opcional): ex. portão fechado, telefone desligado'), 'Portão fechado');
  await act(async () => {
    fireEvent.press(ecra.getByText('Registar cliente ausente'));
  });
  expect(mockAusencia).toHaveBeenCalledWith('p1', 'Portão fechado');
  expect(ecra.getByText(/Registado: cliente ausente \(1\.ª vez\)/)).toBeTruthy();
});
