-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I4 · Lançamento aberto
--
--   1. C5: "Não mostrar os meus ganhos" (perfil_destaques.ocultar_ganhos). Na
--      lista de destaques os valores de quem escolheu esconder ficam vazios para
--      os outros; o próprio continua a ver os seus.
--   2. N5 leva o prato do dia (cardápio da cozinha por defeito).
--   3. Textos de N5, N6 e N7 e envio pela Edge Function. No envio volta a
--      respeitar as preferências do cliente (N5 e N7 podem ser desligadas).
--
-- Os interruptores não são ligados aqui: ligam-se no O5 (auditado).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. C5: esconder os ganhos na lista
-- -----------------------------------------------------------------------------
alter table perfil_destaques add column ocultar_ganhos boolean not null default false;
grant update (ocultar_ganhos) on perfil_destaques to authenticated;

create or replace function destaques_mes()
returns table (posicao int, nome_exibido text, amigos int, valor int,
               valor_min int, valor_max int, sou_eu boolean)
language sql stable security definer set search_path = public as $$
  with r as materialized (select * from ranking_mes()),
       n as (select count(*) as total from r)
  select r.posicao, r.nome_exibido, r.amigos,
         case when n.total >= p.limiar_intervalos and v.mostrar then r.valor end,
         case when n.total <  p.limiar_intervalos and v.mostrar then (r.valor / p.tamanho_intervalo) * p.tamanho_intervalo end,
         case when n.total <  p.limiar_intervalos and v.mostrar then (r.valor / p.tamanho_intervalo + 1) * p.tamanho_intervalo end,
         r.cliente_id = cliente_actual()
    from r
    cross join n
    cross join parametros p
    join perfil_destaques pd on pd.cliente_id = r.cliente_id
    cross join lateral (select (not pd.ocultar_ganhos or r.cliente_id = cliente_actual()) as mostrar) v
   where p.unico and funcionalidade_activa('destaques')
     and r.posicao <= p.tamanho_top
   order by r.posicao;
$$;

-- -----------------------------------------------------------------------------
-- 2. N5 com o prato do dia
-- -----------------------------------------------------------------------------
create or replace function job_n5_lembrete() returns void
language sql security definer set search_path = public as $$
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select ci.cliente_id, 'N5',
         jsonb_build_object('prato_do_dia',
           (select string_agg(m.nome, ', ' order by m.ordem, m.nome) from cardapio m
             where m.do_dia and m.disponivel and m.deletado_em is null and m.cozinha_id = cozinha_padrao()))
    from codigos_indicacao ci
    join preferencias_notificacao pn on pn.cliente_id = ci.cliente_id
   where funcionalidade_activa('indicacao')
     and extract(isodow from hoje_luanda()) between 1 and 5
     and ci.ultima_partilha_em is not null and ci.deletado_em is null
     and pn.lembrete_almoco
     and (select count(*) from notificacoes_fila n
           where n.cliente_id = ci.cliente_id and n.codigo = 'N5'
             and n.criado_em >= inicio_semana_luanda()) < 2;
$$;

-- -----------------------------------------------------------------------------
-- 3. Textos e envio de N5, N6 e N7
-- -----------------------------------------------------------------------------
create or replace function texto_notificacao(p_codigo text, p_dados jsonb, out titulo text, out corpo text)
language sql stable set search_path = public as $$
  select 'Manda Bué',
         case p_codigo
           when 'N2' then format('%s entrou com o teu código! Ganhas %s em cada pedido durante %s dias.',
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'Um amigo'),
                                 formatar_kz((p_dados ->> 'ganho_por_pedido')::numeric),
                                 p_dados ->> 'duracao_dias')
           when 'N3' then format('+%s: o pedido de %s foi entregue. Saldo desta semana: %s.',
                                 formatar_kz((p_dados ->> 'valor')::numeric),
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'um amigo'),
                                 formatar_kz((p_dados ->> 'saldo_semana')::numeric))
           when 'N4' then format('Passaste os %s esta semana. Os próximos ganhos ficam em verificação e são pagos assim que confirmarmos os pedidos.',
                                 formatar_kz((p_dados ->> 'limite')::numeric))
           when 'N5' then case when nullif(p_dados ->> 'prato_do_dia', '') is not null
                               then format('Hoje há %s. Partilha o teu código com os colegas antes do almoço.',
                                           p_dados ->> 'prato_do_dia')
                               else 'Partilha o teu código com os colegas antes do almoço.' end
           when 'N6' then format('O período de %s termina em 5 dias. Convida mais amigos para continuares a ganhar.',
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'um amigo'))
           when 'N7' then format('%s, estás em %s.º lugar este mês. %s para entrares no top %s.',
                                 p_dados ->> 'nome_exibido', p_dados ->> 'posicao',
                                 case when (p_dados ->> 'amigos_em_falta')::int = 1 then 'Falta 1 amigo'
                                      else format('Faltam %s amigos', p_dados ->> 'amigos_em_falta') end,
                                 p_dados ->> 'tamanho_top')
           when 'N8' then format('Pagámos %s por %s. Referência: %s.',
                                 formatar_kz((p_dados ->> 'valor')::numeric),
                                 case p_dados ->> 'metodo'
                                   when 'multicaixa_express' then 'Multicaixa Express'
                                   when 'unitel_money' then 'Unitel Money'
                                   else coalesce(p_dados ->> 'metodo', '') end,
                                 p_dados ->> 'referencia')
         end;
$$;

-- Notificações por enviar: N2–N8, com o interruptor ligado e, para N5 e N7, a
-- preferência do cliente ainda ligada no momento do envio.
create or replace function notificacoes_pendentes(p_limite integer default 100)
returns table (id uuid, cliente_id uuid, codigo text, titulo text, corpo text, dados jsonb, tokens text[])
language sql stable security definer set search_path = public as $$
  select n.id, n.cliente_id, n.codigo, t.titulo, t.corpo, n.dados,
         coalesce((select array_agg(d.token order by d.atualizado_em desc) from dispositivos_push d
                    where d.cliente_id = n.cliente_id and d.activo and d.deletado_em is null), '{}')
    from notificacoes_fila n
    cross join lateral texto_notificacao(n.codigo, n.dados) t
    left join preferencias_notificacao pn on pn.cliente_id = n.cliente_id and pn.deletado_em is null
   where n.enviada_em is null and n.deletado_em is null
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8')
     and funcionalidade_activa(funcionalidade_da_notificacao(n.codigo))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$$;

revoke execute on function texto_notificacao(text, jsonb)  from public, anon, authenticated;
revoke execute on function notificacoes_pendentes(integer) from public, anon, authenticated;
revoke execute on function job_n5_lembrete()               from public, anon, authenticated;
grant execute on function texto_notificacao(text, jsonb), notificacoes_pendentes(integer) to service_role;
