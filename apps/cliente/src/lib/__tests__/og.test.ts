import { codigoDoLink, idDoCaminho, injectarOg, kz, textosCartao, type PratoPartilhado } from '../og';

const prato: PratoPartilhado = {
  nome: 'Choco "frito"',
  preco: 12000,
  foto_url: 'https://x/foto.jpg',
  marca: 'Cozinha da Alexandra',
  convite: null,
};
const html = '<!doctype html><html><head><meta charset="utf-8"><title>Manda Bué</title></head><body></body></html>';

describe('og', () => {
  it('kz agrupa com ponto', () => {
    expect(kz(12000)).toBe('12.000 Kz');
    expect(kz(950)).toBe('950 Kz');
  });

  it('codigoDoLink aceita MB1234 e o antigo MB-1234, e devolve MB1234', () => {
    expect(codigoDoLink(' mb-4812 ')).toBe('MB4812');
    expect(codigoDoLink('MB4812')).toBe('MB4812');
    expect(codigoDoLink('MB-12')).toBeNull();
    expect(codigoDoLink('<script>')).toBeNull();
    expect(codigoDoLink(null)).toBeNull();
  });

  it('idDoCaminho lê o uuid de /p/{id}', () => {
    expect(idDoCaminho('/p/6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F')).toBe('6f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f');
    expect(idDoCaminho('/p/abc')).toBeNull();
    expect(idDoCaminho('/x/6f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f')).toBeNull();
  });

  it('sem código: preço e frase da marca', () => {
    expect(textosCartao(prato).descricao).toBe('12.000 Kz · Comida de casa, entregue quente 🍲');
  });

  it('com código: o desconto do amigo e o mínimo', () => {
    const d = textosCartao({ ...prato, convite: { codigo: 'MB-4812', desconto: 1000, minimo: 5000 } }).descricao;
    expect(d).toContain('Ganha 1.000 Kz de desconto no 1.º pedido com o código MB-4812');
    expect(d).toContain('a partir de 5.000 Kz');
  });

  it('injecta as etiquetas no <head>, troca o título e escapa o texto', () => {
    const out = injectarOg(html, prato, 'https://site/p/1?r=MB-4812');
    expect(out).toContain('<meta property="og:image" content="https://x/foto.jpg">');
    expect(out).toContain('<title>Choco &quot;frito&quot; · Cozinha da Alexandra</title>');
    expect(out).not.toContain('<title>Manda Bué</title>');
    expect(out).toContain('summary_large_image');
    expect(out.indexOf('og:title')).toBeLessThan(out.indexOf('</head>'));
  });

  it('sem foto: cartão pequeno e sem og:image', () => {
    const out = injectarOg(html, { ...prato, foto_url: null }, 'https://site/p/1');
    expect(out).not.toContain('og:image');
    expect(out).toContain('content="summary"');
  });
});
