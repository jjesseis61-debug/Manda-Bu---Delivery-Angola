// Cartão do WhatsApp do link de convite (/c/{código}), para o Cloudflare Pages (functions/c/[[caminho]].ts).
// O WhatsApp lê o HTML com o desconto do amigo; para pessoas é a própria app (PWA), que abre em /c/{código},
// guarda o código e segue para o Início. Os valores vêm de visitante_convida (pública). Sem rede: cartão
// sem valores; se o caminho não tiver código válido, serve a app tal como está.
import { codigoDoCaminho, injectarMeta, textosConvite } from './og';

export type OpcoesConvite = {
  supabaseUrl: string;
  chavePublica: string;
  marca?: string;
  buscar?: (url: string, init?: RequestInit) => Promise<Response>;
};

export async function responderCartaoConvite(pedido: string, resposta: Response, o: OpcoesConvite): Promise<Response> {
  try {
    const url = new URL(pedido);
    const codigo = codigoDoCaminho(url.pathname);
    const tipo = resposta.headers.get('content-type') ?? '';
    if (!codigo || !resposta.ok || !tipo.includes('text/html')) return resposta;
    const marca = o.marca ?? 'Cozinha da Alexandra';

    let parametros: { desconto_indicado?: number; desconto_subtotal_minimo?: number } | null = null;
    try {
      const base = o.supabaseUrl.replace(/\/+$/, '');
      const r = await (o.buscar ?? fetch)(`${base}/rest/v1/rpc/visitante_convida`, {
        method: 'POST',
        headers: { apikey: o.chavePublica, Authorization: `Bearer ${o.chavePublica}`, 'Content-Type': 'application/json' },
        body: '{}',
        signal: AbortSignal.timeout(2500),
      });
      if (r.ok) parametros = (await r.json()) as typeof parametros;
    } catch {
      parametros = null;
    }

    const { titulo, descricao } = textosConvite(codigo, marca, parametros);
    const html = injectarMeta(await resposta.text(), { titulo, descricao, imagem: `${url.origin}/icons/icon-512.png`, url: url.toString(), marca });
    const cabecalhos = new Headers(resposta.headers);
    cabecalhos.delete('content-length');
    cabecalhos.set('cache-control', 'public, max-age=0, must-revalidate');
    return new Response(html, { status: 200, headers: cabecalhos });
  } catch {
    return resposta;
  }
}
