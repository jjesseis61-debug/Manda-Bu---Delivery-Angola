/// <reference types="jest" />
jest.mock('../supabase', () => ({ supabase: {} }));
jest.mock('expo-image-picker', () => ({}));
jest.mock('expo-image-manipulator', () => ({}));

import { caminhoDoEndereco, caminhoFoto } from '../fotos';

test('caminho da foto no bucket fotos-pratos', () => {
  expect(caminhoFoto('pratos', 'abc', new Date(1000))).toBe('pratos/abc/1000.jpg');
  expect(caminhoFoto('cozinhas', 'k1', new Date(2000))).toBe('cozinhas/k1/2000.jpg');
});

test('caminho a partir do endereço público (só deste bucket)', () => {
  expect(
    caminhoDoEndereco('https://x.supabase.co/storage/v1/object/public/fotos-pratos/pratos/abc/1000.jpg'),
  ).toBe('pratos/abc/1000.jpg');
  expect(caminhoDoEndereco('https://outro.site/foto.jpg')).toBeNull();
  expect(caminhoDoEndereco(null)).toBeNull();
});
