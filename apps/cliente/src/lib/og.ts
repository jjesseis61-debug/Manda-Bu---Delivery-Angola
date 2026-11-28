// Cartão do WhatsApp (Open Graph) da página de um prato partilhado: /p/{prato}?r={código}.
// Funções puras, sem imports: usadas pela função edge do Netlify (netlify/edge-functions/prato.ts),
// que as importa directamente, e testadas com o jest da app.

export type PratoPartilhado = {
  nome: string;
  preco: number;
  foto_url: string | null;
  marca: string;
  /** Presente quando o link traz um código de convite válido e o Convida está ligado */
  convite: { codigo: string; desconto: number; minimo: number } | null;
};

/** Escapa texto para ir dentro de atributos/HTML sem partir a página */
export function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/** Milhares com ponto, como na app ("9.000 Kz"), sem depender do ICU do servidor */
export function kz(n: number): string {
  return `${Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')} Kz`;
}

/** Código de convite do link (MB4812, e o antigo MB-4812) no formato da plataforma (MB4812), ou null */
export function codigoDoLink(r: string | null | undefined): string | null {
  const c = (r ?? '').trim().toUpperCase();
  return /^MB-?\d{4,6}$/.test(c) ? c.replace('-', '') : null;
}

/** Id do prato no caminho /p/{uuid} (ou null) */
export function idDoCaminho(caminho: string): string | null {
  const m = /^\/p\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/?$/i.exec(caminho);
  return m ? m[1].toLowerCase() : null;
}

/** Título e descrição do cartão: o benefício do amigo primeiro, quando há código */
export function textosCartao(p: PratoPartilhado): { titulo: string; descricao: string } {
  const titulo = `${p.nome.trim()} · ${p.marca}`;
  if (p.convite && p.convite.desconto > 0) {
    const cond = p.convite.minimo > 0 ? ` (pedidos a partir de ${kz(p.convite.minimo)})` : '';
    return {
      titulo,
      descricao: `${kz(p.preco)} · Ganha ${kz(p.convite.desconto)} de desconto no 1.º pedido com o código ${p.convite.codigo}${cond} 🍲`,
    };
  }
  return { titulo, descricao: `${kz(p.preco)} · Comida de casa, entregue quente 🍲` };
}

/** Etiquetas Open Graph de um cartão qualquer (prato, convite) no HTML da app (e troca o <title>) */
export function injectarMeta(
  html: string,
  c: { titulo: string; descricao: string; imagem: string | null; url: string; marca: string },
): string {
  const meta = [
    `<meta property="og:title" content="${esc(c.titulo)}">`,
    `<meta property="og:description" content="${esc(c.descricao)}">`,
    `<meta name="description" content="${esc(c.descricao)}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="${esc(c.marca)}">`,
    `<meta property="og:url" content="${esc(c.url)}">`,
    c.imagem ? `<meta property="og:image" content="${esc(c.imagem)}">` : '',
    `<meta name="twitter:card" content="${c.imagem ? 'summary_large_image' : 'summary'}">`,
  ]
    .filter(Boolean)
    .join('\n');
  const semTitulo = html.replace(/<title>[\s\S]*?<\/title>/i, '');
  const cabeca = `<title>${esc(c.titulo)}</title>\n${meta}\n`;
  return /<\/head>/i.test(semTitulo) ? semTitulo.replace(/<\/head>/i, `${cabeca}</head>`) : cabeca + semTitulo;
}

/** Acrescenta as etiquetas Open Graph do prato ao HTML da app */
export function injectarOg(html: string, p: PratoPartilhado, url: string): string {
  const { titulo, descricao } = textosCartao(p);
  return injectarMeta(html, { titulo, descricao, imagem: p.foto_url, url, marca: p.marca });
}

/** Código do caminho /c/{código} (MB4812 ou MB-4812), ou null */
export function codigoDoCaminho(caminho: string): string | null {
  const m = /^\/c\/([^/]+)\/?$/i.exec(caminho);
  return m ? codigoDoLink(decodeURIComponent(m[1])) : null;
}

/** Textos do cartão do convite: o que o amigo ganha primeiro (Cialdini), sem dados de quem convida */
export function textosConvite(
  codigo: string,
  marca: string,
  p: { desconto_indicado?: number; desconto_subtotal_minimo?: number } | null,
): { titulo: string; descricao: string } {
  const desconto = Number(p?.desconto_indicado ?? 0);
  const minimo = Number(p?.desconto_subtotal_minimo ?? 0);
  if (desconto > 0) {
    const cond = minimo > 0 ? ` (pedidos a partir de ${kz(minimo)})` : '';
    return {
      titulo: `Ganha ${kz(desconto)} no teu 1.º pedido · ${marca}`,
      descricao: `Um amigo convidou-te. Usa o código ${codigo}${cond}. Comida de casa, entregue quente 🍲`,
    };
  }
  return { titulo: `Um amigo convidou-te · ${marca}`, descricao: `Usa o código ${codigo}. Comida de casa, entregue quente 🍲` };
}
