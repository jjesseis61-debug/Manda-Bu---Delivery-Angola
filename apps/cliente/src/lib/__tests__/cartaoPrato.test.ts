/// <reference types="jest" />
import { responderCartaoPrato } from '@/lib/cartaoPrato';

const ID = '7712b3de-dd7a-4731-aed7-2c5721de6d4d';
const HTML = '<html><head><title>Manda Bué</title></head><body><div id="root"></div></body></html>';
const app = () => new Response(HTML, { status: 200, headers: { 'content-type': 'text/html; charset=utf-8' } });
const prato = { nome: 'Muamba', preco: 3500, foto_url: 'https://exemplo/muamba.jpg', marca: 'Manda Bué', convite: null };
const opcoes = (resposta: unknown, ok = true) => ({
  supabaseUrl: 'https://x.supabase.co/',
  chavePublica: 'chave',
  buscar: jest.fn(async () => new Response(JSON.stringify(resposta), { status: ok ? 200 : 500 })),
});

test('prato partilhado: o HTML da app leva o cartão (título, foto) e a função recebe o código do link', async () => {
  const o = opcoes(prato);
  const r = await responderCartaoPrato(`https://mandabue.ao/p/${ID}?r=mb-4812`, app(), o);
  const html = await r.text();
  expect(html).toContain('og:title" content="Muamba · Manda Bué"');
  expect(html).toContain('og:image" content="https://exemplo/muamba.jpg"');
  expect(o.buscar).toHaveBeenCalledWith(
    `https://x.supabase.co/functions/v1/prato?formato=json&id=${ID}&r=MB4812`,
    expect.objectContaining({ headers: { apikey: 'chave' } }),
  );
});

test('outras páginas, prato inexistente ou servidor em baixo: devolve a app sem mexer', async () => {
  const fora = await responderCartaoPrato('https://mandabue.ao/inicio', app(), opcoes(prato));
  expect(await fora.text()).toBe(HTML);
  const semPrato = await responderCartaoPrato(`https://mandabue.ao/p/${ID}`, app(), opcoes(null));
  expect(await semPrato.text()).toBe(HTML);
  const erro = await responderCartaoPrato(`https://mandabue.ao/p/${ID}`, app(), opcoes(prato, false));
  expect(await erro.text()).toBe(HTML);
});
