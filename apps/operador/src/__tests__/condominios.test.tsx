/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Condominios from '@/app/condominios';
import { abrirFecharCozinha, decidirMembroCondominio, lerCondominios, lerMembrosCondominio } from '@/lib/condominios';

jest.mock('@/lib/supabase', () => ({ supabase: {} }));
jest.mock('@/lib/api', () => ({ lerCozinhas: jest.fn().mockResolvedValue([]), lerZonasEntrega: jest.fn().mockResolvedValue([]) }));
jest.mock('@/lib/condominios', () => ({
  ...jest.requireActual('@/lib/condominios'),
  lerCondominios: jest.fn(),
  lerMembrosCondominio: jest.fn(),
  abrirFecharCozinha: jest.fn(),
  decidirMembroCondominio: jest.fn(),
}));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1' }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const COND = {
  id: 'c1', nome: 'Jardim do Éden', cozinha_id: 'k1', cozinha: 'Cozinha Jardim', zona_id: null, zona: null,
  centro_lat: -8.9, centro_lng: 13.2, raio_m: 300, vagas: 50, inscricoes_ate: null, inscricoes_abertas: true,
  aprovacao_manual: true, modo_entrega: 'parceiro', parceiro_nome: 'Motos Já', codigo: 'AB12CD34', lista_aberta: true,
  cozinha_aberta: true, fechada_desde: null, reabre_em: null, activos: 32, pendentes: 1, activos_30d: 20,
};

test('mostra vagas, fecha a cozinha com hora de reabrir e aprova um morador', async () => {
  (lerCondominios as jest.Mock).mockResolvedValue([COND]);
  (lerMembrosCondominio as jest.Mock).mockResolvedValue([
    { id: 'm1', cliente_nome: 'Ana', telefone: '923000001', bloco: 'B', casa: '12', estado: 'pendente', origem: 'link', criado_em: '2026-11-16T10:00:00Z', ultimo_pedido: null },
  ]);
  const ecra = renderRouter({ condominios: Condominios }, { initialUrl: '/condominios' });
  await waitFor(() => expect(ecra.getByText('32/50 membros · 1 à espera de aprovação · lista aberta')).toBeTruthy());
  expect(ecra.getByText('Entregas: serviço contratado (Motos Já)')).toBeTruthy();

  fireEvent.press(ecra.getByText('Fechar a cozinha'));
  fireEvent.changeText(ecra.getByLabelText('Volta a abrir daqui a quantas horas? (1–24, opcional)'), '2');
  await act(async () => {
    fireEvent.press(ecra.getByText('Confirmar: fechar a cozinha'));
  });
  expect(abrirFecharCozinha).toHaveBeenCalledWith('k1', false, expect.any(String));

  fireEvent.press(ecra.getByText('Moradores (32 + 1 pendentes)'));
  await waitFor(() => expect(ecra.getByText('Ana · à espera de aprovação')).toBeTruthy());
  await act(async () => {
    fireEvent.press(ecra.getByText('Aprovar'));
  });
  expect(decidirMembroCondominio).toHaveBeenCalledWith('m1', 'aprovar');
});
