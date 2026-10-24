// Gera um RASCUNHO de receita com o Claude, a partir de um tema (ou de um prato do catálogo).
// Chamada pela app do operador (botão "Gerar rascunho"). O rascunho fica por rever e publicar — o
// Claude nunca publica. Sem a chave ANTHROPIC_API_KEY devolve "indisponivel".
//
// Autorização: a inserção é feita com o JWT do operador, por isso a RLS exige a permissão
// receitas.gerir (quem não a tem recebe erro). A cozinha do CTA é a cozinha padrão.
import Anthropic from 'npm:@anthropic-ai/sdk';
import { createClient } from 'npm:@supabase/supabase-js@2';

const MODELO = 'claude-opus-5-5';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

const SISTEMA =
  'És o editor de culinária da Manda Bué, em Angola. Escreves receitas caseiras angolanas em ' +
  'português de Portugal, claras e curtas, para uma app usada com dados móveis caros. ' +
  'Responde SEMPRE só com JSON válido, sem texto à volta, no formato ' +
  '{"titulo": "...", "resumo": "uma linha", "corpo": "ingredientes e passos, com uma nota cultural curta"}. ' +
  'O corpo usa texto simples com quebras de linha (sem markdown). Não inventes marcas nem preços.';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const autorizacao = req.headers.get('Authorization') ?? '';
    if (!autorizacao) return json({ erro: 'sem_sessao' }, 401);

    const { tema, prato_base_id } = await req.json().catch(() => ({ tema: null, prato_base_id: null }));

    const url = Deno.env.get('SUPABASE_URL')!;
    const comoUtilizador = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: autorizacao } },
      auth: { persistSession: false },
    });
    const servico = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });

    // Semente: um prato do catálogo ou um tema livre
    let semente = typeof tema === 'string' ? tema.trim() : '';
    if (!semente && typeof prato_base_id === 'string') {
      const { data } = await servico.from('pratos_base').select('nome').eq('id', prato_base_id).maybeSingle();
      semente = (data?.nome as string | undefined) ?? '';
    }
    if (!semente) return json({ erro: 'sem_tema' }, 400);

    const chave = Deno.env.get('ANTHROPIC_API_KEY');
    if (!chave) return json({ erro: 'indisponivel' }, 503);

    const anthropic = new Anthropic({ apiKey: chave, maxRetries: 1 });
    const resposta = await anthropic.beta.messages.create({
      model: MODELO,
      max_tokens: 1500,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: SISTEMA,
      messages: [{ role: 'user', content: `Escreve uma receita angolana para: ${semente}` }],
    } as never);

    // deno-lint-ignore no-explicit-any
    const r = resposta as any;
    if (r.stop_reason === 'refusal') return json({ erro: 'indisponivel' }, 503);
    const texto = (r.content as { type: string; text?: string }[])
      .filter((b) => b.type === 'text').map((b) => b.text ?? '').join('').trim();
    const limpo = texto.replace(/^```(json)?/i, '').replace(/```$/i, '').trim();
    let rascunho: { titulo?: string; resumo?: string; corpo?: string };
    try {
      rascunho = JSON.parse(limpo);
    } catch {
      return json({ erro: 'resposta_invalida' }, 502);
    }
    if (!rascunho.titulo || !rascunho.corpo) return json({ erro: 'resposta_invalida' }, 502);

    const { data: coz } = await servico.rpc('cozinha_padrao');

    // Inserção com o JWT do operador: a RLS exige receitas.gerir
    const { data: criada, error } = await comoUtilizador
      .from('receitas')
      .insert({
        titulo: rascunho.titulo,
        resumo: rascunho.resumo ?? null,
        corpo: rascunho.corpo,
        cozinha_id: coz ?? null,
        estado: 'rascunho',
        origem: 'claude',
      })
      .select('id')
      .single();
    if (error) return json({ erro: error.message }, 403);

    return json({ id: (criada as { id: string }).id });
  } catch (e) {
    return json({ erro: (e as Error).message }, 500);
  }
});
