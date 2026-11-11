// Envia a fila de notificações (clientes e equipa) pelo serviço de push da Expo. Que códigos saem e
// para quem é decidido no servidor (notificacoes_por_enviar); esta função só despacha o que ela devolve.
// Cada app (cliente, operador, estafeta) é um projecto Expo diferente e a Expo recusa um pedido que
// junte tokens de projectos diferentes, por isso agrupa-se por app: um pedido à Expo por projecto.
//
// Chamada de minuto a minuto por pg_cron (agendar_envio). Só despacha
// o que já está na fila: os textos e os destinatários vêm do servidor
// (notificacoes_por_enviar) e os interruptores são respeitados lá.
// Autenticação própria (a função é publicada sem verificação de JWT, porque o pg_cron
// não tem sessão): o pedido tem de trazer o cabeçalho x-envio-segredo igual ao
// segredo ENVIO_SEGREDO da função (se existir) ou ao segredo guardado na base de dados
// (segredos_servidor, confirmado por segredo_envio_valido; é o que o cron de agendar_envio manda).
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send';
const EXPO_RECIBOS_URL = 'https://exp.host/--/api/v2/push/getReceipts';
const LOTE_EXPO = 100;
const LOTE_RECIBOS = 1000;
// Web Push (PWA): as assinaturas dos navegadores vêm com app = 'web' e o "token" é o JSON da
// assinatura. Saem por Web Push com as chaves VAPID (segredos VAPID_PUBLICA e VAPID_PRIVADA da
// função); sem as chaves, as assinaturas web são ignoradas e o resto funciona como antes.
const VAPID_PUBLICA = Deno.env.get('VAPID_PUBLICA') ?? '';
const VAPID_PRIVADA = Deno.env.get('VAPID_PRIVADA') ?? '';
const WEB_PUSH_LIGADO = VAPID_PUBLICA !== '' && VAPID_PRIVADA !== '';
if (WEB_PUSH_LIGADO) {
  webpush.setVapidDetails(Deno.env.get('VAPID_CONTACTO') ?? 'https://manda-bue.netlify.app', VAPID_PUBLICA, VAPID_PRIVADA);
}
type EnvioWeb = { id: string; token: string; payload: string };

/** Envia as notificações dos navegadores (PWA). Devolve os tokens que já não servem (404/410). */
async function enviarWeb(envios: EnvioWeb[]): Promise<string[]> {
  const mortos: string[] = [];
  await Promise.all(
    envios.map(async (e) => {
      try {
        await webpush.sendNotification(JSON.parse(e.token), e.payload, { TTL: 6 * 3600 });
      } catch (erro) {
        const codigo = (erro as { statusCode?: number }).statusCode;
        if (codigo === 404 || codigo === 410) mortos.push(e.token); // o navegador desistiu da assinatura
      }
    }),
  );
  return mortos;
}

// Erros do Expo que significam "este token já não serve" (app desinstalada, projecto errado)
const TOKEN_MORTO = new Set(['DeviceNotRegistered', 'MismatchSenderId', 'InvalidCredentials']);

type Pendente = {
  id: string;
  destino: 'cliente' | 'funcionario';
  codigo: string;
  titulo: string;
  corpo: string;
  dados: Record<string, unknown>;
  tokens: string[];
  // projecto Expo (app) de cada token, na mesma ordem que `tokens`. Pode faltar em dados antigos.
  apps?: string[];
};

type Mensagem = { to: string; title: string; body: string; sound: 'default'; data: Record<string, unknown> };
type Bilhete = { status: 'ok' | 'error'; id?: string; details?: { error?: string } };
type Recibo = { status: 'ok' | 'error'; details?: { error?: string } };

/** 2.ª fase: consulta os receipts dos envios já feitos e desactiva os tokens que falharam a
 *  entrega. Devolve quantos tokens foram desactivados. Nunca lança: uma falha aqui não deve
 *  travar o envio do minuto seguinte. */
async function verificarRecibos(supabase: ReturnType<typeof createClient>): Promise<number> {
  const { data, error } = await supabase.rpc('recibos_por_verificar', { p_limite: 300 });
  if (error) return 0;
  const recibos = (data ?? []) as { id: string; ticket_id: string; token: string }[];
  if (recibos.length === 0) return 0;

  const porTicket = new Map<string, { id: string; token: string }>();
  for (const r of recibos) porTicket.set(r.ticket_id, { id: r.id, token: r.token });

  const ids = [...porTicket.keys()];
  const idsProcessados: string[] = [];
  const invalidos: string[] = [];
  for (let i = 0; i < ids.length; i += LOTE_RECIBOS) {
    const chunk = ids.slice(i, i + LOTE_RECIBOS);
    const resposta = await fetch(EXPO_RECIBOS_URL, {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ ids: chunk }),
    });
    if (!resposta.ok) break; // tenta no próximo minuto; o que ficou por verificar continua na tabela
    const corpo = (await resposta.json()) as { data?: Record<string, Recibo> };
    for (const [ticketId, recibo] of Object.entries(corpo.data ?? {})) {
      const r = porTicket.get(ticketId);
      if (!r) continue;
      idsProcessados.push(r.id);
      if (recibo.status === 'error' && recibo.details?.error && TOKEN_MORTO.has(recibo.details.error)) {
        invalidos.push(r.token);
      }
    }
  }
  const r = await supabase.rpc('concluir_recibos', { p_ids: idsProcessados, p_tokens_invalidos: [...new Set(invalidos)] });
  return (r.data as number | null) ?? 0;
}

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
    // Mesmo sem envios novos, há receipts de envios anteriores para confirmar
    let d = 0;
    try {
      d = await verificarRecibos(supabase);
    } catch {
      // tenta no próximo minuto
    }
    return Response.json({ enviadas: 0, mensagens: 0, tokens_desactivados: d });
  }

  const dadosDe = (n: Pendente): Record<string, unknown> => ({
    codigo: n.codigo,
    notificacao_id: n.id,
    // Só o que a app precisa para abrir o ecrã certo
    ...('pedido_id' in n.dados ? { pedido_id: n.dados.pedido_id } : {}),
    ...('codigo_grupo' in n.dados ? { codigo_grupo: n.dados.codigo_grupo } : {}),
    ...('link' in n.dados ? { link: n.dados.link } : {}),
  });
  // Projecto Expo (app) de um token; se faltar (dados antigos), deduz-se pelo destino.
  const appDoToken = (n: Pendente, i: number): string =>
    n.apps?.[i] ?? (n.destino === 'funcionario' ? 'operador' : 'cliente');

  // Agrupa as mensagens de cada notificação pelo seu projecto Expo (app). Uma notificação pode
  // tocar mais do que um projecto (ex. N19: operador + estafeta) e, nesse caso, parte-se: só sai da
  // fila quando TODOS os seus projectos forem enviados.
  type NotifApp = { id: string; mensagens: Mensagem[] };
  const porApp = new Map<string, NotifApp[]>();
  const semTelemovel: string[] = [];
  const envioWeb: EnvioWeb[] = [];
  const soWeb: string[] = []; // notificações que só tinham navegadores: saem da fila depois do envio web
  const totalPorId = new Map<string, number>(); // nº de mensagens (tokens) por notificação
  for (const n of pendentes) {
    if (!n.tokens || n.tokens.length === 0) {
      semTelemovel.push(n.id);
      continue;
    }
    const data = dadosDe(n);
    const desta = new Map<string, Mensagem[]>(); // app -> mensagens desta notificação
    let expo = 0;
    n.tokens.forEach((token, i) => {
      const app = appDoToken(n, i);
      if (app === 'web') {
        // O tag evita mostrar duas vezes o mesmo aviso se a notificação tiver de ser repetida
        if (WEB_PUSH_LIGADO) {
          envioWeb.push({ id: n.id, token, payload: JSON.stringify({ title: n.titulo, body: n.corpo, data, tag: n.id }) });
        }
        return;
      }
      expo++;
      const msg: Mensagem = { to: token, title: n.titulo, body: n.corpo, sound: 'default', data };
      const arr = desta.get(app);
      if (arr) arr.push(msg);
      else desta.set(app, [msg]);
    });
    if (expo === 0) {
      soWeb.push(n.id);
      continue;
    }
    totalPorId.set(n.id, expo);
    for (const [app, msgs] of desta) {
      const arr = porApp.get(app);
      if (arr) arr.push({ id: n.id, mensagens: msgs });
      else porApp.set(app, [{ id: n.id, mensagens: msgs }]);
    }
  }

  // Lotes de até 100 mensagens, sempre dentro do mesmo projecto (app), sem partir a parte de uma
  // notificação que cabe no mesmo projecto entre dois lotes. porId guarda quantas mensagens cada
  // notificação leva neste lote, para só a marcar quando todas as suas mensagens saírem.
  type Lote = { ids: string[]; mensagens: Mensagem[]; porId: Map<string, number> };
  const lotes: Lote[] = [];
  for (const notifs of porApp.values()) {
    let actual: Lote = { ids: [], mensagens: [], porId: new Map() };
    for (const na of notifs) {
      if (actual.mensagens.length > 0 && actual.mensagens.length + na.mensagens.length > LOTE_EXPO) {
        lotes.push(actual);
        actual = { ids: [], mensagens: [], porId: new Map() };
      }
      actual.ids.push(na.id);
      actual.porId.set(na.id, (actual.porId.get(na.id) ?? 0) + na.mensagens.length);
      actual.mensagens.push(...na.mensagens);
    }
    if (actual.mensagens.length > 0) lotes.push(actual);
  }

  const marcar = async (ids: string[]): Promise<number> => {
    if (ids.length === 0) return 0;
    const { data: n, error: e } = await supabase.rpc('marcar_notificacoes_enviadas', { p_ids: ids });
    if (e) throw new Error(e.message);
    return (n as number | null) ?? 0;
  };
  // Conta as mensagens já enviadas de cada notificação e devolve as que ficaram completas.
  const enviadoPorId = new Map<string, number>();
  const completasDoLote = (lote: Lote): string[] => {
    const prontas: string[] = [];
    for (const [id, c] of lote.porId) {
      const total = (enviadoPorId.get(id) ?? 0) + c;
      enviadoPorId.set(id, total);
      if (total >= (totalPorId.get(id) ?? 0)) prontas.push(id);
    }
    return prontas;
  };

  let enviadas = 0;
  let mensagens = 0;
  let desactivados = 0;
  try {
    // Notificações sem nenhum telemóvel registado também saem da fila (não há a quem entregar)
    enviadas += await marcar(semTelemovel);
    // Navegadores (PWA): Web Push; as que só tinham navegadores saem logo da fila
    if (envioWeb.length > 0) {
      const mortos = await enviarWeb(envioWeb);
      mensagens += envioWeb.length;
      if (mortos.length > 0) {
        const r = await supabase.rpc('desactivar_tokens_push', { p_tokens: [...new Set(mortos)] });
        desactivados += (r.data as number | null) ?? 0;
      }
    }
    enviadas += await marcar(soWeb);
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
      enviadas += await marcar(completasDoLote(lote));
      mensagens += lote.mensagens.length;

      const corpo = (await resposta.json()) as { data?: Bilhete[] };
      const invalidos: string[] = [];
      const recibosNovos: { ticket_id: string; token: string }[] = [];
      (corpo.data ?? []).forEach((bilhete, j) => {
        const token = lote.mensagens[j]?.to;
        if (!token) return;
        if (bilhete.status === 'error' && bilhete.details?.error === 'DeviceNotRegistered') {
          invalidos.push(token); // a Expo já sabe na hora que não serve
        } else if (bilhete.status === 'ok' && bilhete.id) {
          recibosNovos.push({ ticket_id: bilhete.id, token }); // confirma-se no receipt (uns min depois)
        }
      });
      if (invalidos.length > 0) {
        const r = await supabase.rpc('desactivar_tokens_push', { p_tokens: invalidos });
        desactivados += (r.data as number | null) ?? 0;
      }
      if (recibosNovos.length > 0) {
        await supabase.rpc('registar_recibos_push', { p_recibos: recibosNovos });
      }
    }

    // 2.ª fase: confirma os receipts dos envios já feitos e desactiva os tokens que falharam a
    // entrega (DeviceNotRegistered, etc.). O Expo só tem o receipt uns minutos depois, por isso
    // só se verificam os tickets com idade suficiente (recibos_por_verificar).
    desactivados += await verificarRecibos(supabase);
  } catch (e) {
    return Response.json({ erro: (e as Error).message, enviadas, mensagens }, { status: 500 });
  }

  return Response.json({ enviadas, mensagens, tokens_desactivados: desactivados });
});
