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

/** Código de convite no formato da plataforma (MB-1234 / MB-12345), ou null */
export function codigoDoLink(r: string | null | undefined): string | null {
  const c = (r ?? '').trim().toUpperCase();
  return /^MB-\d{4,5}$/.test(c) ? c : null;
}

/** Id do prato no caminho /p/{uuid} (ou null) */
export function idDoCaminho(caminho: string): string | null {
  const m = /^\/p\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/?$/i.exec(caminho);
  return m ? m[1].toLowerCase() : null;
}

/** Título e descrição do cartão: o benefício do amigo primeiro, quando há código */
export function textosCartao(p: PratoPartilhado): { titulo: string; descricao: string } {
  const titulo = `${p.nome} — ${p.marca}`;
  if (p.convite && p.convite.desconto > 0) {
    const cond = p.convite.minimo > 0 ? ` (pedidos a partir de ${kz(p.convite.minimo)})` : '';
    return {
      titulo,
      descricao: `${kz(p.preco)} · Ganha ${kz(p.convite.desconto)} de desconto no 1.º pedido com o código ${p.convite.codigo}${cond} 🍲`,
    };
  }
  return { titulo, descricao: `${kz(p.preco)} · Comida de casa, entregue quente 🍲` };
}

/** Acrescenta as etiquetas Open Graph ao HTML da app (e troca o <title>) */
export function injectarOg(html: string, p: PratoPartilhado, url: string): string {
  const { titulo, descricao } = textosCartao(p);
  const meta = [
    `<meta property="og:title" content="${esc(titulo)}">`,
    `<meta property="og:description" content="${esc(descricao)}">`,
    `<meta name="description" content="${esc(descricao)}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="${esc(p.marca)}">`,
    `<meta property="og:url" content="${esc(url)}">`,
    p.foto_url ? `<meta property="og:image" content="${esc(p.foto_url)}">` : '',
    `<meta name="twitter:card" content="${p.foto_url ? 'summary_large_image' : 'summary'}">`,
  ]
    .filter(Boolean)
    .join('\n');
  const semTitulo = html.replace(/<title>[\s\S]*?<\/title>/i, '');
  const cabeca = `<title>${esc(titulo)}</title>\n${meta}\n`;
  return /<\/head>/i.test(semTitulo) ? semTitulo.replace(/<\/head>/i, `${cabeca}</head>`) : cabeca + semTitulo;
}
