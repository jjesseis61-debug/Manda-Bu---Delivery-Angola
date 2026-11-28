/// <reference types="jest" />
import { responderCartaoConvite } from '@/lib/cartaoConvite';
import { codigoDoCaminho, textosConvite } from '@/lib/og';

const HTML = '<html><head><title>Manda Bué</title></head><body><div id="root"></div></body></html>';
const app = () => new Response(HTML, { status: 200, headers: { 'content-type': 'text/html; charset=utf-8' } });
const opcoes = (resposta: unknown, ok = true) => ({
  supabaseUrl: 'https://x.supabase.co/',
  chavePublica: 'chave',
  buscar: jest.fn(async () => new Response(JSON.stringify(resposta), { status: ok ? 200 : 500 })),
});

test('código do caminho /c/…: aceita MB4812 e o antigo MB-4812; recusa o resto', () => {
  expect(codigoDoCaminho('/c/MB4812')).toBe('MB4812');
  expect(codigoDoCaminho('/c/mb-4812/')).toBe('MB4812');
  expect(codigoDoCaminho('/c/xpto')).toBeNull();
  expect(codigoDoCaminho('/p/MB4812')).toBeNull();
});

test('cartão do convite: o desconto do amigo primeiro (Cialdini), sem dados de quem convida', async () => {
  const o = opcoes({ desconto_indicado: 1000, desconto_subtotal_minimo: 5000 });
  const r = await responderCartaoConvite('https://manda-bue.pages.dev/c/mb-4812', app(), o);
  const html = await r.text();
  expect(html).toContain('og:title" content="Ganha 1.000 Kz no teu 1.º pedido · Cozinha da Alexandra"');
  expect(html).toContain('Usa o código MB4812 (pedidos a partir de 5.000 Kz)');
  expect(html).toContain('og:image" content="https://manda-bue.pages.dev/icons/icon-512.png"');
  expect(o.buscar).toHaveBeenCalledWith('https://x.supabase.co/rest/v1/rpc/visitante_convida', expect.objectContaining({ method: 'POST' }));
});

test('servidor em baixo: cartão sem valores; outras páginas ficam iguais', async () => {
  const semRede = await responderCartaoConvite('https://manda-bue.pages.dev/c/MB4812', app(), opcoes(null, false));
  expect(await semRede.text()).toContain('og:title" content="Um amigo convidou-te · Cozinha da Alexandra"');
  const fora = await responderCartaoConvite('https://manda-bue.pages.dev/inicio', app(), opcoes({}));
  expect(await fora.text()).toBe(HTML);
  expect(textosConvite('MB1', 'X', { desconto_indicado: 500 }).descricao).toBe('Um amigo convidou-te. Usa o código MB1. Comida de casa, entregue quente 🍲');
});
