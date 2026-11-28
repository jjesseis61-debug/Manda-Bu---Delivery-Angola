/// <reference types="jest" />
import { act, fireEvent, render } from '@testing-library/react-native';

import { CompromissoPresenca } from '@/components/CompromissoPresenca';

const mockGrupo: { valor: string | null; erro: boolean } = { valor: 'A', erro: false };
const mockRpc = jest.fn();
jest.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: (nome: string, args?: unknown) => mockRpc(nome, args),
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { presenca_confirmada_em: null, pontos_entrega: { referencia: 'Casa da Carla', zonas: { nome: 'Maianga' } } }, error: null }) }) }),
    }),
  },
}));

beforeEach(() => {
  mockRpc.mockReset();
  mockRpc.mockImplementation(async (nome: string) =>
    nome === 'meu_grupo_compromisso'
      ? mockGrupo.erro
        ? { data: null, error: { message: 'x' } }
        : { data: mockGrupo.valor, error: null }
      : { data: null, error: null },
  );
});

test('grupo A: pergunta com a morada e a hora; «Sim, vou estar» confirma', async () => {
  mockGrupo.valor = 'A';
  mockGrupo.erro = false;
  const ecra = render(<CompromissoPresenca pedidoId="p1" agendadoPara="2026-11-24T12:00:00Z" />);
  await act(async () => undefined);
  expect(ecra.getByText('Vais estar em Casa da Carla às 13h00?')).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getByText('Sim, vou estar'));
  });
  expect(mockRpc).toHaveBeenCalledWith('confirmar_presenca', { p_pedido: 'p1' });
  expect(ecra.getByText('✓ Combinado: vais estar em Casa da Carla às 13h00. Lembramos-te 1 hora antes.')).toBeTruthy();
});

test('«Não vou poder» diz como mudar', async () => {
  mockGrupo.valor = 'A';
  const ecra = render(<CompromissoPresenca pedidoId="p1" agendadoPara="2026-11-24T12:00:00Z" />);
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Não vou poder'));
  expect(ecra.getByText(/Fala connosco já/)).toBeTruthy();
});

test('grupo B (controlo) ou servidor sem o teste: não mostra nada', async () => {
  mockGrupo.valor = 'B';
  const b = render(<CompromissoPresenca pedidoId="p1" agendadoPara="2026-11-24T12:00:00Z" />);
  await act(async () => undefined);
  expect(b.toJSON()).toBeNull();
  mockGrupo.erro = true;
  const sem = render(<CompromissoPresenca pedidoId="p1" agendadoPara="2026-11-24T12:00:00Z" />);
  await act(async () => undefined);
  expect(sem.toJSON()).toBeNull();
});
