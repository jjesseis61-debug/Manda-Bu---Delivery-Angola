/// <reference types="jest" />
import { act, fireEvent, renderRouter } from 'expo-router/testing-library';

import Receitas from '@/app/receitas';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: null, error: null }) } }));
jest.mock('@/components/Guarda', () => ({ Guarda: ({ children }: { children: unknown }) => children }));
jest.mock('@/components/FotoEditavel', () => ({ FotoEditavel: () => null }));
const mockGuardar = jest.fn(async (..._a: unknown[]) => 'r1');
const mockGuardarPratos = jest.fn(async (..._a: unknown[]) => 2);
jest.mock('@/lib/api', () => ({
  lerReceitasGerir: async () => [{ id: 'r1', titulo: 'Mufete de peixe', resumo: null, corpo: 'x', estado: 'publicada', cozinha_id: 'via', foto_url: null }],
  lerCozinhas: async () => [{ id: 'via', nome: 'Viana' }, { id: 'kil', nome: 'Kilamba' }],
  iaDasReceitasLigada: async () => false,
  metricasReceitas: async () => ({ r1: { aberturas: 12, toques: 5, pedidos: 2, interessados: 3, cozinhas: [] } }),
  lerTodosPratos: async () => [
    { id: 'm1', cozinha_id: 'via', nome: 'Mufete', preco: 4500, disponivel: true },
    { id: 'm2', cozinha_id: 'kil', nome: 'Mufete de tilápia', preco: 5000, disponivel: true },
    { id: 'm3', cozinha_id: 'kil', nome: 'Arroz', preco: 3000, disponivel: true },
  ],
  pratosDaReceita: async () => [],
  guardarReceita: (...a: unknown[]) => mockGuardar(...a),
  guardarPratosDaReceita: (...a: unknown[]) => mockGuardarPratos(...a),
}));

test('lista com os números da receita e o aviso de que ninguém a faz', async () => {
  const ecra = renderRouter({ r: Receitas }, { initialUrl: '/r' });
  await act(async () => undefined);
  expect(ecra.getByText('12 aberturas · 5 tocaram em «Pedir» · 2 pedidos · 3 querem que façam')).toBeTruthy();
  expect(ecra.getByText('⚠ Nenhuma cozinha faz este prato')).toBeTruthy();
});

test('editar: procura «mufete», escolhe pratos de duas cozinhas e guarda', async () => {
  const ecra = renderRouter({ r: Receitas }, { initialUrl: '/r' });
  await act(async () => undefined);
  fireEvent.press(ecra.getByText('Editar'));
  await act(async () => undefined);
  expect(ecra.getByText(/Nenhum prato escolhido/)).toBeTruthy();
  fireEvent.changeText(ecra.getByLabelText('Procurar prato ou cozinha'), 'mufete');
  expect(ecra.queryByText(/Arroz/)).toBeNull();
  fireEvent.press(ecra.getByText('Mufete · Viana · 4.500 Kz'));
  fireEvent.press(ecra.getByText('Mufete de tilápia · Kilamba · 5.000 Kz'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar alterações'));
  });
  expect(mockGuardar).toHaveBeenCalledWith(expect.objectContaining({ id: 'r1', cozinha_id: 'via' }));
  expect(mockGuardarPratos).toHaveBeenCalledWith('r1', ['m1', 'm2']);
});
