/// <reference types="jest" />
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);
jest.mock('../api', () => ({ registarTokenPush: jest.fn(), removerTokenPush: jest.fn() }));

import { rotaDaNotificacao } from '../push';

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
  expect(rotaDaNotificacao({ codigo: 'N3' })).toBeNull();
  expect(rotaDaNotificacao(undefined)).toBeNull();
});
