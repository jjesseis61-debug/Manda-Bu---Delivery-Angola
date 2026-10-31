/// <reference types="jest" />
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);
jest.mock('../api', () => ({ registarTokenPush: jest.fn(), removerTokenPush: jest.fn() }));

import { rotaDaNotificacao, rotaDaNotificacaoNoApp } from '../push';

test('abre o ecrã de cada notificação da equipa', () => {
  expect(rotaDaNotificacao({ codigo: 'N12' })).toBe('/equipa');
  expect(rotaDaNotificacao({ codigo: 'N15' })).toBe('/pacotes');
  expect(rotaDaNotificacao({ codigo: 'N17' })).toBe('/entregas');
  expect(rotaDaNotificacao({ codigo: 'N18' })).toBe('/entregas');
  expect(rotaDaNotificacao({ codigo: 'N19' })).toBe('/entregas');
  expect(rotaDaNotificacao({ codigo: 'N21' })).toBe('/reclamacoes');
  expect(rotaDaNotificacao({ codigo: 'N23' })).toBeNull();
  expect(rotaDaNotificacao({ codigo: 'N24' })).toBe('/conferencia');
  expect(rotaDaNotificacao({ codigo: 'N25' })).toBe('/analista');
  expect(rotaDaNotificacao({ codigo: 'N26' })).toBe('/vigilancia');
  expect(rotaDaNotificacao({ codigo: 'N27' })).toBe('/turno');
  expect(rotaDaNotificacao({ codigo: 'N28' })).toBe('/compras');
  expect(rotaDaNotificacao({ codigo: 'N29' })).toBe('/atendimento');
  expect(rotaDaNotificacao({ codigo: 'N40' })).toBe('/otp-codigos');
  expect(rotaDaNotificacao({ codigo: 'N3' })).toBeNull();
  expect(rotaDaNotificacao(undefined)).toBeNull();
});

test('no sino: pedido abre segundo o papel; o resto abre o seu ecrã', () => {
  // Com pedido: o gerente vai ao histórico do pedido; o estafeta às suas entregas
  expect(rotaDaNotificacaoNoApp({ codigo: 'N17', pedido_id: 'abc' }, { podeGerir: true })).toBe('/pedido/abc');
  expect(rotaDaNotificacaoNoApp({ codigo: 'N18', pedido_id: 'abc' }, { podeGerir: false })).toBe('/entregas?meu=1');
  // Sem pedido: encaminha pelo mesmo mapa do push (login, reclamação…)
  expect(rotaDaNotificacaoNoApp({ codigo: 'N40' }, { podeGerir: true })).toBe('/otp-codigos');
  expect(rotaDaNotificacaoNoApp({ codigo: 'N21' }, { podeGerir: true })).toBe('/reclamacoes');
  // Sem destino conhecido: não clica
  expect(rotaDaNotificacaoNoApp({ codigo: 'N23' }, { podeGerir: true })).toBeNull();
  expect(rotaDaNotificacaoNoApp(undefined, { podeGerir: true })).toBeNull();
});
