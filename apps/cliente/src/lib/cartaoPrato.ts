// Cartão do WhatsApp da página de um prato partilhado (/p/{prato}?r={código}), para o alojamento
// Cloudflare Pages (functions/p/[[caminho]].ts). Mesma lógica da função edge do Netlify: o WhatsApp
// lê o HTML com a FOTO, o nome, o preço e o desconto do convite; para pessoas é a própria app (PWA).
// Os dados vêm da função `prato` do Supabase (modo JSON). Se algo falhar, serve a app sem cartão.
import { codigoDoLink, idDoCaminho, injectarOg, type PratoPartilhado } from './og';

export type OpcoesCartao = {
  supabaseUrl: string;
  chavePublica: string;
  /** Para os testes; por defeito o fetch global */
  buscar?: (url: string, init?: RequestInit) => Promise<Response>;
};

export async function responderCartaoPrato(pedido: string, resposta: Response, o: OpcoesCartao): Promise<Response> {
  try {
    const url = new URL(pedido);
    const id = idDoCaminho(url.pathname);
    const tipo = resposta.headers.get('content-type') ?? '';
    if (!id || !resposta.ok || !tipo.includes('text/html')) return resposta;

    const base = o.supabaseUrl.replace(/\/+$/, '');
    const codigo = codigoDoLink(url.searchParams.get('r'));
    const api = `${base}/functions/v1/prato?formato=json&id=${id}${codigo ? `&r=${encodeURIComponent(codigo)}` : ''}`;
    const r = await (o.buscar ?? fetch)(api, { headers: { apikey: o.chavePublica }, signal: AbortSignal.timeout(2500) });
    if (!r.ok) return resposta;
    const prato = (await r.json()) as PratoPartilhado | null;
    if (!prato || typeof prato.nome !== 'string') return resposta;

    const html = injectarOg(await resposta.text(), prato, url.toString());
    const cabecalhos = new Headers(resposta.headers);
    cabecalhos.delete('content-length');
    cabecalhos.set('cache-control', 'public, max-age=0, must-revalidate');
    return new Response(html, { status: 200, headers: cabecalhos });
  } catch {
    return resposta;
  }
}
