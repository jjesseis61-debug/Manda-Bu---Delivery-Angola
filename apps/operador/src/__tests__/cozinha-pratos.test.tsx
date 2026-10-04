/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import EditarCozinha from '@/app/cozinhas/[id]';
import { guardarPrato, lerCardapio, lerCozinhas, lerDosesCardapio } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  definirFotoCozinha: jest.fn(),
  definirFotoPrato: jest.fn(),
  guardarCozinha: jest.fn(),
  guardarPrato: jest.fn(),
  lerCardapio: jest.fn(),
  lerCozinhas: jest.fn(),
  lerDosesCardapio: jest.fn(),
}));
jest.mock('@/components/LocalizacaoCozinha', () => ({ LocalizacaoCozinha: () => null }));
jest.mock('@/components/FotoEditavel', () => ({ FotoEditavel: () => null }));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: [] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const prato = (id: string, nome: string, categoria: string | null) => ({
  id, cozinha_id: 'k1', nome, descricao: null, categoria, preco: 3000, disponivel: true, do_dia: false, ordem: 0, foto_url: null, doses_dia: null,
});

beforeEach(() => {
  jest.clearAllMocks();
  (lerCozinhas as jest.Mock).mockResolvedValue([{ id: 'k1', nome: 'Viana', responsavel: 'Rosa', foto_url: null, historia: null,
    estado: 'activa', consentimento_publico: false, telefone_publico: null, whatsapp_publico: null, horario_publico: null }]);
  (lerCardapio as jest.Mock).mockResolvedValue([prato('m', 'Muamba', 'Composto'), prato('s', 'Sumo', 'Bebidas')]);
  (lerDosesCardapio as jest.Mock).mockResolvedValue([{ cardapio_id: 'm', restantes: 2, lancadas: 5 }]);
});

test('pratos: mostra as doses que restam, escolhe a categoria da lista e guarda as doses', async () => {
  const ecra = renderRouter({ 'cozinhas/[id]': EditarCozinha }, { initialUrl: '/cozinhas/k1' });
  await waitFor(() => expect(ecra.getByText(/restam 2 de 5/)).toBeTruthy());
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Editar')[0]);
  });
  expect(ecra.getByLabelText('Doses disponíveis hoje (em branco = sem limite)').props.value).toBe('2');
  fireEvent.press(ecra.getByText('Bebidas'));
  fireEvent.changeText(ecra.getByLabelText('Doses disponíveis hoje (em branco = sem limite)'), '10');
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar prato'));
  });
  expect(guardarPrato).toHaveBeenCalledWith(expect.objectContaining({ id: 'm', categoria: 'Bebidas', doses_dia: 10 }));
});

test('pratos: "Outra…" deixa escrever uma categoria nova; doses em branco = sem limite', async () => {
  const ecra = renderRouter({ 'cozinhas/[id]': EditarCozinha }, { initialUrl: '/cozinhas/k1' });
  await waitFor(() => expect(ecra.getAllByText('Editar').length).toBe(2));
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Editar')[1]);
  });
  fireEvent.press(ecra.getByText('Outra…'));
  fireEvent.changeText(ecra.getByLabelText('Nova categoria'), 'Sobremesas');
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar prato'));
  });
  expect(guardarPrato).toHaveBeenCalledWith(expect.objectContaining({ id: 's', categoria: 'Sobremesas', doses_dia: null }));
});
