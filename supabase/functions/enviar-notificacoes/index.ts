// Envia a fila de notificações (clientes: N2–N11, N13, N14, N16; equipa: N12, N15, N17) pelo serviço de push da Expo.
// A app do cliente e a do operador são projectos Expo diferentes: a Expo recusa um pedido
// com tokens de projectos diferentes, por isso cada destino segue num pedido à parte.
//
// Chamada de minuto a minuto por pg_cron (agendar_envio). Só despacha
// o que já está na fila: os textos e os destinatários vêm do servidor
// (notificacoes_por_enviar) e os interruptores são respeitados lá.
// Autenticação própria (a função é publicada sem verificação de JWT, porque o pg_cron
// não tem sessão): o pedido tem de trazer o cabeçalho x-envio-segredo igual ao
// segredo ENVIO_SEGREDO da função (se existir) ou ao segredo guardado na base de dados
// (segredos_servidor, confirmado por segredo_envio_valido; é o que o cron de agendar_envio manda).
import { createClient } from 'npm:@supabase/supabase-js@2';

const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send';
const LOTE_EXPO = 100;

type Pendente = {
  id: string;
  destino: 'cliente' | 'funcionario';
  codigo: string;
  titulo: string;
  corpo: string;
  dados: Record<string, unknown>;
  tokens: string[];
};

type Mensagem = { to: string; title: string; body: string; sound: 'default'; data: Record<string, unknown> };
type Bilhete = { status: 'ok' | 'error'; details?: { error?: string } };

Deno.serve(async (req) => {
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });

  const recebido = req.headers.get('x-envio-segredo') ?? '';
  const segredo = Deno.env.get('ENVIO_SEGREDO');
  const autorizado =
    recebido !== '' &&
    ((!!segredo && recebido === segredo) ||
      (await supabase.rpc('segredo_envio_valido', { p_segredo: recebido })).data === true);
  if (!autorizado) {
    return Response.json({ erro: 'nao_autorizado' }, { status: 401 });
  }

  const { data, error } = await supabase.rpc('notificacoes_por_enviar', { p_limite: 200 });
  if (error) {
    return Response.json({ erro: error.message }, { status: 500 });
  }
  const pendentes = (data ?? []) as Pendente[];
  if (pendentes.length === 0) {
    return Response.json({ enviadas: 0, mensagens: 0, tokens_desactivados: 0 });
  }

  const mensagensDe = (n: Pendente): Mensagem[] =>
    n.tokens.map((token) => ({
      to: token,
      title: n.titulo,
      body: n.corpo,
      sound: 'default' as const,
      data: {
        codigo: n.codigo,
        notificacao_id: n.id,
        // Só o que a app precisa para abrir o ecrã certo
        ...('pedido_id' in n.dados ? { pedido_id: n.dados.pedido_id } : {}),
        ...('codigo_grupo' in n.dados ? { codigo_grupo: n.dados.codigo_grupo } : {}),
      },
    }));

  // Lotes de até 100 mensagens, um destino de cada vez, sem partir uma notificação entre dois
  // lotes: assim cada lote aceite pela Expo marca as suas notificações como enviadas logo a
  // seguir, e uma falha a meio não faz repetir o que já chegou aos telemóveis.
  type Lote = { ids: string[]; mensagens: Mensagem[] };
  const lotes: Lote[] = [];
  const semTelemovel: string[] = [];
  for (const destino of ['cliente', 'funcionario'] as const) {
    let actual: Lote = { ids: [], mensagens: [] };
    for (const n of pendentes.filter((p) => (p.destino === 'funcionario') === (destino === 'funcionario'))) {
      const m = mensagensDe(n);
      if (m.length === 0) {
        semTelemovel.push(n.id);
        continue;
      }
      if (actual.mensagens.length > 0 && actual.mensagens.length + m.length > LOTE_EXPO) {
        lotes.push(actual);
        actual = { ids: [], mensagens: [] };
      }
      actual.ids.push(n.id);
      actual.mensagens.push(...m);
    }
    if (actual.mensagens.length > 0) lotes.push(actual);
  }

  const marcar = async (ids: string[]): Promise<number> => {
    if (ids.length === 0) return 0;
    const { data: n, error: e } = await supabase.rpc('marcar_notificacoes_enviadas', { p_ids: ids });
    if (e) throw new Error(e.message);
    return (n as number | null) ?? 0;
  };

  let enviadas = 0;
  let mensagens = 0;
  let desactivados = 0;
  try {
    // Notificações sem nenhum telemóvel registado também saem da fila (não há a quem entregar)
    enviadas += await marcar(semTelemovel);
    for (const lote of lotes) {
      const resposta = await fetch(EXPO_PUSH_URL, {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify(lote.mensagens),
      });
      if (!resposta.ok) {
        // A Expo falhou: este lote e os seguintes ficam na fila para o próximo minuto;
        // os lotes anteriores já estão marcados e não se repetem
        return Response.json({ erro: `expo_${resposta.status}`, enviadas, mensagens }, { status: 502 });
      }
      enviadas += await marcar(lote.ids);
      mensagens += lote.mensagens.length;

      const corpo = (await resposta.json()) as { data?: Bilhete[] };
      const invalidos = (corpo.data ?? [])
        .map((bilhete, j) =>
          bilhete.status === 'error' && bilhete.details?.error === 'DeviceNotRegistered' ? lote.mensagens[j].to : null,
        )
        .filter((t): t is string => t !== null);
      if (invalidos.length > 0) {
        const r = await supabase.rpc('desactivar_tokens_push', { p_tokens: invalidos });
        desactivados += (r.data as number | null) ?? 0;
      }
    }
  } catch (e) {
    return Response.json({ erro: (e as Error).message, enviadas, mensagens }, { status: 500 });
  }

  return Response.json({ enviadas, mensagens, tokens_desactivados: desactivados });
});
