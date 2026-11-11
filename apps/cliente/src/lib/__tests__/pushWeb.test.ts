import { chaveParaBytes, estadoPushWeb } from '../pushWeb';

jest.mock('../api', () => ({ registarPushWeb: jest.fn(), removerPushWeb: jest.fn() }));

test('a chave VAPID (base64url) converte-se para os 65 bytes que o navegador pede', () => {
  const b = chaveParaBytes('BAD66DhB2sT_x9jMn3QbqawnSNKpDtjBWbfydGKA3jNgX3lnQDGt0jmm7dc7HAofT39GAQOjqIgxJLJ2lv4W6xU');
  expect(b.length).toBe(65);
  expect(b[0]).toBe(4); // ponto não comprimido da curva P-256
});

test('na app instalada (não web) o push da web não se usa', async () => {
  expect(await estadoPushWeb()).toBe('nao_suportado');
});
