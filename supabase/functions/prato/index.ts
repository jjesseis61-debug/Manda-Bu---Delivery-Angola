// Página de partilha de um prato: gera HTML com etiquetas Open Graph para o WhatsApp mostrar
// um cartão com a FOTO do prato, o nome e o preço. Quem abre no browser é reencaminhado para a
// Play Store (instala a app). Função PÚBLICA (deploy com --no-verify-jwt): o WhatsApp busca o URL
// sem sessão. Lê o prato com a chave de serviço — nome/foto/preço são informação pública.
import { createClient } from 'npm:@supabase/supabase-js@2';

const PLAY_STORE = 'https://play.google.com/store/apps/details?id=ao.mandabue.cliente';
const MARCA = 'Cozinha da Alexandra';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Escapa texto para poder ir dentro de atributos/html sem partir a página.
const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

// Milhares com ponto, como no resto da app ("9.000 Kz") — determinístico, sem depender do ICU.
const kz = (n: number) => `${Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')} Kz`;

function pagina({ titulo, descricao, imagem, url }: { titulo: string; descricao: string; imagem: string | null; url: string }) {
  const og = [
    `<meta property="og:title" content="${esc(titulo)}">`,
    `<meta property="og:description" content="${esc(descricao)}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:url" content="${esc(url)}">`,
    imagem ? `<meta property="og:image" content="${esc(imagem)}">` : '',
    imagem ? `<meta name="twitter:card" content="summary_large_image">` : '<meta name="twitter:card" content="summary">',
  ].join('\n    ');
  // O WhatsApp lê as etiquetas e NÃO segue o refresh; um humano é reencaminhado para a Play Store.
  return `<!doctype html>
<html lang="pt">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${esc(titulo)}</title>
    ${og}
    <meta http-equiv="refresh" content="0; url=${esc(PLAY_STORE)}">
    <link rel="canonical" href="${esc(PLAY_STORE)}">
  </head>
  <body style="font-family: -apple-system, Segoe UI, Roboto, Arial, sans-serif; padding: 24px; color:#1A1A1A;">
    <p>${esc(titulo)} — ${esc(descricao)}</p>
    <p>A abrir a app… Se não abrir, <a href="${esc(PLAY_STORE)}">toca aqui para instalar</a>.</p>
    <script>location.replace(${JSON.stringify(PLAY_STORE)});</script>
  </body>
</html>`;
}

Deno.serve(async (req) => {
  const html = (corpo: string, status = 200) =>
    new Response(corpo, {
      status,
      headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=300' },
    });

  try {
    const id = new URL(req.url).searchParams.get('id') ?? '';
    // Página genérica (ainda assim válida) quando o id falta ou é inválido / o prato não existe.
    const generica = () =>
      html(pagina({ titulo: MARCA, descricao: 'Comida de casa, entregue quente 🍲', imagem: null, url: PLAY_STORE }));

    if (!UUID.test(id)) return generica();

    const servico = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );
    const { data: prato } = await servico
      .from('cardapio')
      .select('nome, preco, foto_url, deletado_em, visivel_online')
      .eq('id', id)
      .maybeSingle();

    if (!prato || prato.deletado_em || prato.visivel_online === false) return generica();

    const titulo = `${prato.nome} — ${MARCA}`;
    const descricao = `${kz(prato.preco)} · Comida de casa, entregue quente 🍲`;
    return html(pagina({ titulo, descricao, imagem: prato.foto_url, url: `${new URL(req.url).origin}${new URL(req.url).pathname}?id=${id}` }));
  } catch {
    return html(pagina({ titulo: MARCA, descricao: 'Comida de casa, entregue quente 🍲', imagem: null, url: PLAY_STORE }));
  }
});
