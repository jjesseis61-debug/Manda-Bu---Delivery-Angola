// Envia a fila de notificações (N2, N3, N4, N8) pelo serviço de push da Expo.
//
// Chamada de minuto a minuto por pg_cron (agendar_envio_notificacoes). Só despacha
// o que já está na fila: os textos e os destinatários vêm do servidor
// (notificacoes_pendentes) e os interruptores são respeitados lá.
// Autenticação própria (a função é publicada sem verificação de JWT, porque o pg_cron
// não tem sessão): o pedido tem de trazer o cabeçalho x-envio-segredo igual ao
// segredo ENVIO_SEGREDO da função. Sem segredo configurado, recusa tudo.
import { createClient } from 'npm:@supabase/supabase-js@2';

const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send';
const LOTE_EXPO = 100;

type Pendente = {
  id: string;
  cliente_id: string;
  codigo: string;
  titulo: string;
  corpo: string;
  dados: Record<string, unknown>;
  tokens: string[];
};

type Mensagem = { to: string; title: string; body: string; sound: 'default'; data: Record<string, unknown> };
type Bilhete = { status: 'ok' | 'error'; details?: { error?: string } };

Deno.serve(async (req) => {
  const segredo = Deno.env.get('ENVIO_SEGREDO');
  if (!segredo) {
    return Response.json({ erro: 'segredo_nao_configurado' }, { status: 503 });
  }
  if (req.headers.get('x-envio-segredo') !== segredo) {
    return Response.json({ erro: 'nao_autorizado' }, { status: 401 });
  }

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });

  const { data, error } = await supabase.rpc('notificacoes_pendentes', { p_limite: 200 });
  if (error) {
    return Response.json({ erro: error.message }, { status: 500 });
  }
  const pendentes = (data ?? []) as Pendente[];
  if (pendentes.length === 0) {
    return Response.json({ enviadas: 0, mensagens: 0, tokens_desactivados: 0 });
  }

  const mensagens: Mensagem[] = pendentes.flatMap((n) =>
    n.tokens.map((token) => ({
      to: token,
      title: n.titulo,
      body: n.corpo,
      sound: 'default' as const,
      data: { codigo: n.codigo, notificacao_id: n.id },
    })),
  );

  const tokensInvalidos: string[] = [];
  for (let i = 0; i < mensagens.length; i += LOTE_EXPO) {
    const lote = mensagens.slice(i, i + LOTE_EXPO);
    const resposta = await fetch(EXPO_PUSH_URL, {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify(lote),
    });
    if (!resposta.ok) {
      // A Expo falhou: não marca nada como enviado; o próximo minuto volta a tentar
      return Response.json({ erro: `expo_${resposta.status}` }, { status: 502 });
    }
    const corpo = (await resposta.json()) as { data?: Bilhete[] };
    (corpo.data ?? []).forEach((bilhete, j) => {
      if (bilhete.status === 'error' && bilhete.details?.error === 'DeviceNotRegistered') {
        tokensInvalidos.push(lote[j].to);
      }
    });
  }

  let desactivados = 0;
  if (tokensInvalidos.length > 0) {
    const r = await supabase.rpc('desactivar_tokens_push', { p_tokens: tokensInvalidos });
    desactivados = (r.data as number | null) ?? 0;
  }

  // Notificações sem nenhum telemóvel registado também saem da fila (não há a quem entregar)
  const { data: enviadas, error: erroMarcar } = await supabase.rpc('marcar_notificacoes_enviadas', {
    p_ids: pendentes.map((n) => n.id),
  });
  if (erroMarcar) {
    return Response.json({ erro: erroMarcar.message }, { status: 500 });
  }

  return Response.json({ enviadas, mensagens: mensagens.length, tokens_desactivados: desactivados });
});
