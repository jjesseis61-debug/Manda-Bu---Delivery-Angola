jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);

import { esquecerProprioCodigo, guardarCodigoPendente, lerCodigoPendente, linkConvite, linkPartilhaPrato } from '../convite';

describe('linkConvite', () => {
  it('monta o link da Play Store com o código no referrer', () => {
    expect(linkConvite('MB-4812')).toBe(
      'https://play.google.com/store/apps/details?id=ao.mandabue.cliente&referrer=MB-4812',
    );
  });

  it('normaliza o código antes de o pôr no link', () => {
    expect(linkConvite('mb-4812')).toContain('referrer=MB-4812');
  });
});

describe('linkPartilhaPrato', () => {
  const id = '6f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f';
  it('aponta para a página do prato no site da app', () => {
    expect(linkPartilhaPrato(id)).toBe(`https://manda-bue.netlify.app/p/${id}`);
  });
  it('leva o código de convite (normalizado) no r', () => {
    expect(linkPartilhaPrato(id, 'mb-4812')).toBe(`https://manda-bue.netlify.app/p/${id}?r=MB-4812`);
  });
  it('ignora um código inválido', () => {
    expect(linkPartilhaPrato(id, 'xpto')).toBe(`https://manda-bue.netlify.app/p/${id}`);
  });
});

describe('código guardado do link', () => {
  const AsyncStorage = require('@react-native-async-storage/async-storage');
  beforeEach(() => AsyncStorage.clear());
  it('guarda o código de outra pessoa', async () => {
    expect(await guardarCodigoPendente('mb-1234', 'MB-4812')).toBe('MB-1234');
    expect(await lerCodigoPendente()).toBe('MB-1234');
  });
  it('não guarda o próprio código (quem abre o link que partilhou)', async () => {
    expect(await guardarCodigoPendente('mb-4812', 'MB-4812')).toBeNull();
    expect(await lerCodigoPendente()).toBeNull();
  });
  it('o primeiro link conta: um segundo link não troca o código', async () => {
    await guardarCodigoPendente('MB-1111');
    expect(await guardarCodigoPendente('MB-2222')).toBe('MB-1111');
    expect(await lerCodigoPendente()).toBe('MB-1111');
  });
  it('vale 30 dias; depois um link novo já conta', async () => {
    const t0 = 1_800_000_000_000;
    await guardarCodigoPendente('MB-1111', null, t0);
    const depois = t0 + 31 * 24 * 60 * 60 * 1000;
    expect(await lerCodigoPendente(depois)).toBeNull();
    expect(await guardarCodigoPendente('MB-2222', null, depois)).toBe('MB-2222');
  });
  it('o formato antigo (só o texto, sem data) já não conta', async () => {
    await AsyncStorage.setItem('manda-bue:codigo-convite', 'MB-9999');
    expect(await lerCodigoPendente()).toBeNull();
  });
  it('ao entrar, esquece o código guardado se for o próprio', async () => {
    await guardarCodigoPendente('MB-4812');
    await esquecerProprioCodigo('MB-4812');
    expect(await lerCodigoPendente()).toBeNull();
  });
});
