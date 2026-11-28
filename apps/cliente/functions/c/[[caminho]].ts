// Cloudflare Pages Function: /c/{código} (cartão do WhatsApp do link de convite).
// A lógica está em src/lib/cartaoConvite.ts (testada com o jest da app). Valores públicos por defeito;
// podem trocar-se nas variáveis do projecto no Cloudflare (SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY).
import { responderCartaoConvite } from '../../src/lib/cartaoConvite';

type Contexto = {
  request: Request;
  env: { SUPABASE_URL?: string; SUPABASE_PUBLISHABLE_KEY?: string };
  next(): Promise<Response>;
};

export const onRequestGet = async (c: Contexto): Promise<Response> => {
  const resposta = await c.next();
  return responderCartaoConvite(c.request.url, resposta, {
    supabaseUrl: c.env.SUPABASE_URL ?? 'https://laruvuambdovnkojwrzp.supabase.co',
    chavePublica: c.env.SUPABASE_PUBLISHABLE_KEY ?? 'sb_publishable_VoD7AGU0YCNyTJjiNmwJ-Q_FaRL1-aM',
  });
};
