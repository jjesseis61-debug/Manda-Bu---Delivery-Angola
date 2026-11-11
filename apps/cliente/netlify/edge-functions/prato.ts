// Netlify Edge Function: /p/{prato}?r={código}
// O WhatsApp (e outras redes) lê esta página para montar o cartão com a FOTO do prato, o nome,
// o preço e — quando o link traz o código de quem partilhou — o desconto do 1.º pedido.
// Para pessoas, a página é a própria app web (PWA): a rota /p/[id] guarda o código e abre o prato.
// Os dados vêm da função `prato` do Supabase (modo JSON). Se falhar, serve a app sem cartão.
import { codigoDoLink, idDoCaminho, injectarOg, type PratoPartilhado } from '../../src/lib/og.ts';

declare const Netlify: { env: { get(nome: string): string | undefined } };

const SUPABASE_URL = 'https://laruvuambdovnkojwrzp.supabase.co';
const CHAVE_PUBLICA = 'sb_publishable_VoD7AGU0YCNyTJjiNmwJ-Q_FaRL1-aM';

export default async (req: Request, context: { next(): Promise<Response> }) => {
  const resposta = await context.next();
  try {
    const url = new URL(req.url);
    const id = idDoCaminho(url.pathname);
    const tipo = resposta.headers.get('content-type') ?? '';
    if (!id || !resposta.ok || !tipo.includes('text/html')) return resposta;

    const base = (Netlify.env.get('SUPABASE_URL') ?? SUPABASE_URL).replace(/\/+$/, '');
    const codigo = codigoDoLink(url.searchParams.get('r'));
    const api = `${base}/functions/v1/prato?formato=json&id=${id}${codigo ? `&r=${encodeURIComponent(codigo)}` : ''}`;
    const r = await fetch(api, {
      headers: { apikey: Netlify.env.get('SUPABASE_PUBLISHABLE_KEY') ?? CHAVE_PUBLICA },
      signal: AbortSignal.timeout(2500),
    });
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
};

export const config = { path: '/p/*' };
