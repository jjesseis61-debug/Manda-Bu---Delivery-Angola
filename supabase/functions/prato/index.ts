// Prato partilhado. Função PÚBLICA (deploy com --no-verify-jwt): o WhatsApp busca o link sem sessão.
// Lê com a chave de serviço só informação pública (nome, preço, foto) e, se o link trouxer um
// código de convite válido, o desconto do 1.º pedido (parâmetros públicos do Convida).
//
//  * ?formato=json&id=…[&r=MB1234] → dados do prato em JSON (usados pela página do site da app,
//    Cloudflare Pages ou Netlify, que monta o cartão Open Graph; o Supabase serve HTML como
//    text/plain, por isso o cartão não pode ser feito aqui).
//  * ?id=…[&r=…] (links antigos) → reencaminha (302) para a página do prato no site da app.
import { createClient } from 'npm:@supabase/supabase-js@2';

// Endereço público da app web: o segredo SITE_URL das funções; por defeito o Cloudflare Pages
const SITE = (Deno.env.get('SITE_URL') ?? 'https://manda-bue.pages.dev').replace(/\/+$/, '');
const MARCA = 'Cozinha da Alexandra';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// MB4812 (e o antigo MB-4812, dos links já partilhados) -> MB4812
const CODIGO = /^MB-?\d{4,6}$/;

const CORS = { 'Access-Control-Allow-Origin': '*' };

function json(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'public, max-age=300' },
  });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const id = url.searchParams.get('id') ?? '';
  const r = (url.searchParams.get('r') ?? '').trim().toUpperCase();
  const codigo = CODIGO.test(r) ? r.replace('-', '') : null;

  if (url.searchParams.get('formato') !== 'json') {
    const destino = UUID.test(id) ? `${SITE}/p/${id.toLowerCase()}${codigo ? `?r=${codigo}` : ''}` : SITE;
    return new Response(null, { status: 302, headers: { Location: destino, 'Cache-Control': 'public, max-age=300' } });
  }

  if (!UUID.test(id)) return json(null, 404);
  try {
    const servico = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
      auth: { persistSession: false },
    });
    const { data: prato } = await servico
      .from('cardapio')
      .select('nome, preco, foto_url, deletado_em, visivel_online')
      .eq('id', id)
      .maybeSingle();
    if (!prato || prato.deletado_em || prato.visivel_online === false) return json(null, 404);

    let convite: { codigo: string; desconto: number; minimo: number } | null = null;
    if (codigo) {
      const [{ data: cod }, { data: func }, { data: par }] = await Promise.all([
        servico.from('codigos_indicacao').select('codigo').eq('codigo', codigo).is('deletado_em', null).maybeSingle(),
        servico.from('funcionalidades').select('activa').eq('chave', 'indicacao').maybeSingle(),
        servico.from('parametros').select('desconto_indicado, desconto_subtotal_minimo').eq('unico', true).maybeSingle(),
      ]);
      if (cod && func?.activa && par) {
        convite = {
          codigo,
          desconto: Number(par.desconto_indicado ?? 0),
          minimo: Number(par.desconto_subtotal_minimo ?? 0),
        };
      }
    }
    return json({ nome: prato.nome, preco: Number(prato.preco), foto_url: prato.foto_url ?? null, marca: MARCA, convite });
  } catch {
    return json(null, 500);
  }
});
