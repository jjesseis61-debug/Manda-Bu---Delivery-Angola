// Rota/ETA do estafeta por estrada (Google Directions), chamada pela app do cliente enquanto o pedido
// está a caminho. É o "Gate B" do mapa: o serviço calcula a rota real com trânsito e guarda em
// rotas_estafeta; o posicao_entrega usa-a enquanto recente. Tudo com fallback total:
//   - sem a chave GOOGLE_ROTAS_API_KEY  -> devolve { fonte: 'estimativa' } e não chama o Google;
//   - com o interruptor `rota_google` desligado -> idem;
//   - qualquer erro (rede, resposta inesperada) -> { fonte: 'estimativa' }.
// Nunca estoura para o cliente: o ecrã continua a mostrar o tempo estimado pela distância.
//
// Autorização: usa o JWT do cliente para confirmar, via posicao_entrega, que o pedido é dele e está
// a caminho (e obter a posição do estafeta e o destino). A escrita no cache é feita com service role.
// Throttle: no máximo uma chamada ao Google por pedido a cada 60 s (reaproveita o cache entre chamadas).
import { createClient } from 'npm:@supabase/supabase-js@2';

const THROTTLE_MS = 60_000;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const estimativa = (extra: Record<string, unknown> = {}) =>
  new Response(JSON.stringify({ fonte: 'estimativa', ...extra }), {
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const chave = Deno.env.get('GOOGLE_ROTAS_API_KEY');
    const autorizacao = req.headers.get('Authorization') ?? '';
    if (!chave || !autorizacao) return estimativa();

    const { pedido } = await req.json().catch(() => ({ pedido: null }));
    if (!pedido || typeof pedido !== 'string') return estimativa();

    const url = Deno.env.get('SUPABASE_URL')!;
    // Cliente com o JWT do utilizador: só autoriza o que o próprio pode ver
    const comoUtilizador = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: autorizacao } },
      auth: { persistSession: false },
    });
    // Serviço: ler o interruptor e escrever o cache (ignora RLS)
    const servico = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });

    // Interruptor desligado -> nunca chama o Google
    const { data: inter } = await servico
      .from('funcionalidades')
      .select('activa')
      .eq('chave', 'rota_google')
      .maybeSingle();
    if (!inter?.activa) return estimativa();

    // Confirma a posse e obtém estafeta + destino (posicao_entrega já valida cliente e estado)
    const { data: pos, error } = await comoUtilizador.rpc('posicao_entrega', { p_pedido: pedido });
    if (error || !pos?.activo || !pos?.estafeta || !pos?.destino?.lat) return estimativa();

    // Throttle: se o cache ainda está fresco, reaproveita-o (não gasta chamada ao Google)
    const { data: cache } = await servico
      .from('rotas_estafeta')
      .select('minutos, km, polyline, atualizado_em')
      .eq('pedido_id', pedido)
      .maybeSingle();
    if (cache && Date.now() - new Date(cache.atualizado_em).getTime() < THROTTLE_MS) {
      return new Response(JSON.stringify({ fonte: 'google', ...cache }), {
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    // Google Directions: rota de condução com trânsito
    const origem = `${pos.estafeta.lat},${pos.estafeta.lng}`;
    const destino = `${pos.destino.lat},${pos.destino.lng}`;
    const g = new URL('https://maps.googleapis.com/maps/api/directions/json');
    g.searchParams.set('origin', origem);
    g.searchParams.set('destination', destino);
    g.searchParams.set('mode', 'driving');
    g.searchParams.set('departure_time', 'now');
    g.searchParams.set('key', chave);
    const resp = await fetch(g).then((r) => r.json()).catch(() => null);
    const perna = resp?.routes?.[0]?.legs?.[0];
    if (!perna) return estimativa();

    const segundos = perna.duration_in_traffic?.value ?? perna.duration?.value;
    const metros = perna.distance?.value;
    if (typeof segundos !== 'number') return estimativa();
    const minutos = Math.max(1, Math.ceil(segundos / 60));
    const km = typeof metros === 'number' ? Math.round(metros / 100) / 10 : null;
    const polyline = resp.routes[0].overview_polyline?.points ?? null;

    await servico
      .from('rotas_estafeta')
      .upsert({ pedido_id: pedido, minutos, km, polyline, atualizado_em: new Date().toISOString() });

    return new Response(JSON.stringify({ fonte: 'google', minutos, km, polyline }), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch {
    return estimativa();
  }
});
