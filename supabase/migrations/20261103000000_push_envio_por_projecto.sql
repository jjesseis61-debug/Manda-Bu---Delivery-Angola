-- Envio de push agrupado por PROJECTO Expo (app), não por destino.
-- A Expo recusa um pedido que junte tokens de projectos Expo diferentes (erro
-- PUSH_TOO_MANY_EXPERIENCE_IDS). Com o scoping por app, a equipa passou a ter DOIS projectos Expo
-- (operador e estafeta). Como a função de envio juntava num só pedido todos os tokens de
-- "funcionário", sempre que uma notificação do operador (ex. N17) e uma do estafeta (N32) estavam
-- pendentes ao mesmo tempo o lote misturava os dois projectos, a Expo devolvia 400 e TODA a fila da
-- equipa ficava presa (nem o operador nem o estafeta recebiam).
--
-- Correcção: notificacoes_por_enviar passa a devolver também o app de CADA token (array `apps`,
-- paralelo a `tokens`), para a função de envio agrupar as mensagens por projecto e mandar um pedido
-- por projecto. A selecção dos tokens e os filtros ficam exactamente iguais aos de antes.

-- Muda o tipo de retorno (coluna nova), por isso é preciso apagar e recriar.
drop function if exists notificacoes_por_enviar(integer);
create function notificacoes_por_enviar(p_limite integer default 100)
 returns table(id uuid, cliente_id uuid, funcionario_id uuid, destino text, codigo text,
               titulo text, corpo text, dados jsonb, tokens text[], apps text[])
 language sql stable security definer set search_path = public as $function$
  select n.id, n.cliente_id, n.funcionario_id,
         case when n.funcionario_id is not null then 'funcionario' else 'cliente' end,
         n.codigo, t.titulo, t.corpo, n.dados,
         coalesce(d.tokens, '{}'), coalesce(d.apps, '{}')
    from notificacoes_fila n
    cross join lateral texto_notificacao(n.codigo, n.dados) t
    left join preferencias_notificacao pn on pn.cliente_id = n.cliente_id and pn.deletado_em is null
    -- tokens e apps na MESMA ordem (atualizado_em desc, token como desempate), para apps[i] ↔ tokens[i]
    left join lateral (
      select array_agg(dp.token order by dp.atualizado_em desc, dp.token) as tokens,
             array_agg(coalesce(dp.app, case when n.funcionario_id is not null then 'operador' else 'cliente' end)
                       order by dp.atualizado_em desc, dp.token) as apps
        from dispositivos_push dp
       where dp.activo and dp.deletado_em is null
         and (dp.cliente_id = n.cliente_id or dp.funcionario_id = n.funcionario_id)
         and (n.funcionario_id is null
              or coalesce(dp.app, 'operador') = any(apps_do_codigo(n.codigo)))
    ) d on true
   where n.enviada_em is null and n.deletado_em is null
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N10', 'N11', 'N12', 'N13',
                      'N14', 'N15', 'N16', 'N17', 'N18', 'N19', 'N20', 'N21', 'N22', 'N23', 'N24',
                      'N25', 'N26', 'N27', 'N28', 'N29', 'N30', 'N31', 'N32', 'N40')
     and notificacao_valida(n.codigo, n.criado_em)
     and (funcionalidade_da_notificacao(n.codigo) is null or funcionalidade_activa(funcionalidade_da_notificacao(n.codigo)))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
     and not (n.codigo = 'N9' and exists (select 1 from avaliacoes a where a.pedido_id::text = n.dados ->> 'pedido_id'))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$function$;

-- Privilégios como estavam: só o service_role chama (via edge function). É preciso revogar também
-- de anon e authenticated — no Supabase as default privileges dão-lhes execute em funções novas.
revoke execute on function notificacoes_por_enviar(integer) from public, anon, authenticated;
grant  execute on function notificacoes_por_enviar(integer) to service_role;
