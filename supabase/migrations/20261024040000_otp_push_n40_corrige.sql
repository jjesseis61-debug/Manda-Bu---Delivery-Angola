-- Correção: o aviso de pedido de login (N40) entrava na fila e aparecia no sino, mas NÃO era
-- despachado como push (ficava "só no sistema"), porque a lista de envio parava no N32.
--   a) notificacoes_por_enviar: acrescenta o N40 à lista de códigos a empurrar.
--   b) notificacao_valida: dá ao N40 uma validade curta (10 min, como o código de login) — assim
--      um pedido antigo não dispara um push tarde, e os N40 já presos na fila não saem agora.

-- a) Lista de envio: N40 passa a ser despachado (igual ao "Novo pedido" N17)
create or replace function notificacoes_por_enviar(p_limite integer default 100)
 returns table(id uuid, cliente_id uuid, funcionario_id uuid, destino text, codigo text,
               titulo text, corpo text, dados jsonb, tokens text[])
 language sql stable security definer set search_path = public as $function$
  select n.id, n.cliente_id, n.funcionario_id,
         case when n.funcionario_id is not null then 'funcionario' else 'cliente' end,
         n.codigo, t.titulo, t.corpo, n.dados,
         coalesce((select array_agg(d.token order by d.atualizado_em desc) from dispositivos_push d
                    where d.activo and d.deletado_em is null
                      and (d.cliente_id = n.cliente_id or d.funcionario_id = n.funcionario_id)), '{}')
    from notificacoes_fila n
    cross join lateral texto_notificacao(n.codigo, n.dados) t
    left join preferencias_notificacao pn on pn.cliente_id = n.cliente_id and pn.deletado_em is null
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

-- b) Validade: o pedido de login só vale enquanto o código serve (10 min). Isto também faz
--    com que os N40 que ficaram presos na fila (do teste) não sejam empurrados agora.
create or replace function notificacao_valida(p_codigo text, p_criado_em timestamptz)
 returns boolean language sql stable set search_path = public as $function$
  select p_criado_em > now() - case p_codigo
           when 'N5'  then interval '2 hours'    -- lembrete do almoço: 11h, só até às 13h
           when 'N10' then interval '3 hours'    -- colega aderiu ao grupo
           when 'N11' then interval '3 hours'    -- grupo fechado
           when 'N16' then interval '2 hours'    -- estado do pedido: depois disso já não interessa
           when 'N17' then interval '2 hours'    -- pedido novo para a cozinha
           when 'N18' then interval '1 hour'     -- pedido sem confirmação
           when 'N19' then interval '2 hours'    -- pedido atrasado (gerente)
           when 'N20' then interval '2 hours'    -- pedido atrasado (cliente)
           when 'N21' then interval '24 hours'   -- reclamação nova (gerente)
           when 'N27' then interval '30 minutes' -- sugestões do gerente de turno (caducam)
           when 'N28' then interval '24 hours'   -- plano de compras
           when 'N29' then interval '24 hours'   -- conversa do atendimento à espera de uma pessoa
           when 'N40' then interval '10 minutes' -- pedido de login: só enquanto o código serve
           when 'N7'  then interval '24 hours'   -- destaques da semana
           when 'N9'  then interval '24 hours'   -- pedido para avaliar
           when 'N6'  then interval '48 hours'   -- ligação a expirar
           when 'N14' then interval '48 hours'   -- pacote a acabar
           else            interval '7 days'     -- ganhos, levantamentos, reconhecimentos
         end;
$function$;
