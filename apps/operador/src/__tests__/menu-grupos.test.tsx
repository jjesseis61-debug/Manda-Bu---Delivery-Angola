/// <reference types="jest" />
import AsyncStorage from '@react-native-async-storage/async-storage';
import { fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Inicio, { agruparMenu, ecras, GRUPOS } from '@/app/inicio';

jest.mock('@/lib/api', () => ({
  contarNotificacoesNovas: jest.fn().mockResolvedValue(0),
  sairDeTodosOsDispositivos: jest.fn(),
}));

let mockPermissoes: string[] = [];
let mockAdmin = false;
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({
    carregado: true,
    sessao: {},
    funcionario: { funcionario_id: 'f1', nome: 'Ana', cargo: null, administrador_principal: mockAdmin, permissoes: mockPermissoes, cozinhas_equipa: [] },
    pode: (p: string) => mockPermissoes.includes(p),
    sair: jest.fn(),
  }),
}));

beforeEach(async () => {
  await AsyncStorage.clear();
  mockAdmin = false;
});

test('cada ecrã está num grupo conhecido; o serviço de entregas está em Logística e Finanças', () => {
  const ids = GRUPOS.map((g) => g.id) as string[];
  for (const e of ecras) {
    expect(e.grupos.length).toBeGreaterThan(0);
    e.grupos.forEach((g) => expect(ids).toContain(g));
  }
  const servico = ecras.find((e) => e.titulo === 'Serviço de entregas contratado');
  expect(servico?.grupos).toEqual(['logistica', 'financas']);
  const grupos = agruparMenu(ecras);
  expect(grupos.map((g) => g.id)).toEqual(ids);
  expect(grupos.find((g) => g.id === 'convida')?.entradas.map((e) => e.titulo)).toContain('Levantamentos');
  expect(grupos.find((g) => g.id === 'clientes')?.entradas.map((e) => e.titulo)).toContain('Pacotes do mês');
});

test('poucos atalhos: lista simples, sem grupos nem pesquisa', async () => {
  mockPermissoes = ['entregas.registar'];
  const ecra = renderRouter({ inicio: Inicio }, { initialUrl: '/inicio' });
  await waitFor(() => expect(ecra.getByText('Pedidos e entregas')).toBeTruthy());
  expect(ecra.queryByText(/Operação do dia/)).toBeNull();
  expect(ecra.queryByLabelText('Procurar funcionalidade')).toBeNull();
});

test('muitos atalhos: grupos fechados, abrir, favoritos e pesquisa', async () => {
  mockPermissoes = ['financas.conferir', 'pedidos.gerir', 'plataforma.parametros'];
  const ecra = renderRouter({ inicio: Inicio }, { initialUrl: '/inicio' });
  await waitFor(() => expect(ecra.getByText('Finanças (9)')).toBeTruthy());
  // grupos vazios não aparecem
  expect(ecra.queryByText(/^Equipa \(/)).toBeNull();
  expect(ecra.getByText('Programa Convida (1)')).toBeTruthy();
  expect(ecra.queryByText('Resultados do mês')).toBeNull();
  fireEvent.press(ecra.getByText('Finanças (9)'));
  expect(ecra.getByText('Resultados do mês')).toBeTruthy();
  await waitFor(async () => expect(await AsyncStorage.getItem('op.grupos_abertos')).toBe('["financas"]'));

  fireEvent.press(ecra.getByLabelText('Marcar Resultados do mês como favorito'));
  await waitFor(() => expect(ecra.getByText('★ Favoritos')).toBeTruthy());
  expect(ecra.getAllByText('Resultados do mês')).toHaveLength(2);
  expect(await AsyncStorage.getItem('op.favoritos.f1')).toBe('["Resultados do mês"]');

  // a pesquisa procura em todos os grupos e diz de onde vem
  fireEvent.changeText(ecra.getByLabelText('Procurar funcionalidade'), 'servico de entregas');
  expect(ecra.getByText('Serviço de entregas contratado')).toBeTruthy();
  expect(ecra.getByText('Logística · Finanças')).toBeTruthy();
});

test('favoritos e grupos abertos voltam guardados', async () => {
  mockPermissoes = ['financas.conferir', 'pedidos.gerir'];
  await AsyncStorage.setItem('op.favoritos.f1', '["Caixa"]');
  await AsyncStorage.setItem('op.grupos_abertos', '["logistica"]');
  mockPermissoes.push('vendas.registar');
  const ecra = renderRouter({ inicio: Inicio }, { initialUrl: '/inicio' });
  await waitFor(() => expect(ecra.getByText('★ Favoritos')).toBeTruthy());
  expect(ecra.getByText('Caixa')).toBeTruthy();
  expect(ecra.getByText('Estafetas e despacho')).toBeTruthy();
});
