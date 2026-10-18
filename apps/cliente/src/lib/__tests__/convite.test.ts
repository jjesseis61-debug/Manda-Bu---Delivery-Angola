jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);

import { linkConvite } from '../convite';

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
