/// <reference types="jest" />
import { act, renderRouter } from 'expo-router/testing-library';

import PerfilCozinha from '@/app/cozinha';
import Destaques from '@/app/destaques';

const mockSessao = { carregado: true, parametros: { tamanho_top: 10 }, ligada: (c: string) => ['destaques', 'perfil_cozinha'].includes(c) };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));
jest.mock('@/lib/carrinho', () => ({ useCarrinho: () => ({ cozinhaActual: { id: 'via', nome: 'Viana' } }) }));
jest.mock('@/components/PessoasComoTu', () => ({ PessoasComoTu: () => null }));
jest.mock('@/components/MediaAvaliacao', () => ({ MediaAvaliacao: () => null }));
jest.mock('@/components/BlocoContactos', () => ({ BlocoContactos: () => null, temContacto: () => false }));
jest.mock('@/components/ComoChegar', () => ({ ComoChegar: () => null }));
const mockCozinha = jest.fn();
jest.mock('@/lib/api', () => ({
  destaquesMes: async () => [
    { posicao: 1, nome_exibido: 'Joana M.', amigos: 14, valor: 5460, valor_min: null, valor_max: null, sou_eu: false },
    { posicao: 2, nome_exibido: 'Paulo S.', amigos: 9, valor: null, valor_min: null, valor_max: null, sou_eu: true },
  ],
  minhaPosicao: async () => ({ posicao: 2, nome_exibido: 'Paulo S.', no_top: true, amigos_em_falta: 0 }),
  totalPagoMes: async () => 0,
  lerCozinhaPublica: () => mockCozinha(),
  lerCardapio: async () => [],
  lerContactos: async () => null,
  mediasAvaliacoes: async () => null,
}));

test('Destaques: o 1.º lugar é o Kamba do Mês; os outros ficam em «Também em destaque»', async () => {
  const ecra = renderRouter({ destaques: Destaques }, { initialUrl: '/destaques' });
  await act(async () => undefined);
  expect(ecra.getByText('Kamba do Mês')).toBeTruthy();
  expect(ecra.getByText('Joana M.')).toBeTruthy();
  expect(ecra.getByText('Trouxe 14 kambas este mês')).toBeTruthy();
  expect(ecra.getByText('Ganhou 5.460 Kz')).toBeTruthy();
  expect(ecra.getByText('Também em destaque')).toBeTruthy();
  expect(ecra.getByText(/2\. Paulo S\. \(tu\) · 9 kambas/)).toBeTruthy();
});

test('Cozinha: o selo Kota da Cozinha só aparece quando o operador o deu', async () => {
  mockCozinha.mockResolvedValue({ id: 'via', nome: 'Dona Teresa', foto_url: null, historia: null, selo_kota: true });
  const com = renderRouter({ cozinha: PerfilCozinha }, { initialUrl: '/cozinha' });
  await act(async () => undefined);
  expect(com.getByText('KOTA DA COZINHA')).toBeTruthy();
  com.unmount();

  mockCozinha.mockResolvedValue({ id: 'via', nome: 'Dona Teresa', foto_url: null, historia: null });
  const sem = renderRouter({ cozinha: PerfilCozinha }, { initialUrl: '/cozinha' });
  await act(async () => undefined);
  expect(sem.getByText('Dona Teresa')).toBeTruthy();
  expect(sem.queryByText('KOTA DA COZINHA')).toBeNull();
});
