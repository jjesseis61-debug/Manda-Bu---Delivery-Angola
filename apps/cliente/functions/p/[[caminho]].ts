// Cloudflare Pages Function: /p/{prato}?r={código} (cartão do WhatsApp do prato partilhado).
// A lógica está em src/lib/cartaoPrato.ts (testada com o jest da app). Valores públicos por defeito;
// podem trocar-se nas variáveis do projecto no Cloudflare (SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY).
import { responderCartaoPrato } from '../../src/lib/cartaoPrato';

type Contexto = {
  request: Request;
  env: { SUPABASE_URL?: string; SUPABASE_PUBLISHABLE_KEY?: string };
  next(): Promise<Response>;
};

export const onRequestGet = async (c: Contexto): Promise<Response> => {
  const resposta = await c.next();
  return responderCartaoPrato(c.request.url, resposta, {
    supabaseUrl: c.env.SUPABASE_URL ?? 'https://laruvuambdovnkojwrzp.supabase.co',
    chavePublica: c.env.SUPABASE_PUBLISHABLE_KEY ?? 'sb_publishable_VoD7AGU0YCNyTJjiNmwJ-Q_FaRL1-aM',
  });
};
