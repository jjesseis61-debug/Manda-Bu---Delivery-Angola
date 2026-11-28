-- Vista de estafeta: o pedidos_operador passa a dizer se o pedido é "meu" — reservado a mim (reserva
-- activa) OU já a entregar por mim (em entrega, entregador sou eu). Serve o modo estafeta na app, para
-- o estafeta ver só as suas entregas sem o ruído da gestão. Só muda o corpo da função (cálculo novo).

drop function if exists pedidos_operador();
create function pedidos_operador()
 returns table(pedido_id uuid, criado_em timestamptz, estado text, cozinha_id uuid, cliente_nome text,
               cliente_telefone text, itens jsonb, subtotal integer, taxa_entrega integer,
               desconto_indicacao integer, credito_indicacao_usado integer, a_pagar integer,
               observacoes text, hora_prometida timestamptz, pagador_distinto boolean,
               ponto_entrega_id uuid, ponto_tipo text, ponto_lat double precision, ponto_lng double precision,
               ponto_referencia text, zona_nome text,
               atribuido_a uuid, atribuido_a_nome text, atribuido_a_mim boolean, minha boolean)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_gerir   boolean := tem_permissao('pedidos.gerir');
  v_reserva int := (select entrega_reserva_min from parametros where unico);
  v_me      uuid := funcionario_actual();
begin
  if not (v_gerir or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  return query
  select x.id, x.criado_em, x.estado, x.cozinha_id, c.nome, c.telefone, x.itens,
         x.subtotal::int, x.taxa_entrega::int, x.desconto_indicacao::int, x.credito_indicacao_usado::int,
         (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado - x.pago_pacote - x.valor_empresa)::int,
         x.observacoes, x.hora_prometida, x.pagador_distinto,
         pe.id, pe.tipo, pe.lat, pe.lng, pe.referencia, z.nome,
         case when r.activa then x.atribuido_a end,
         case when r.activa then (select nome from funcionarios where id = x.atribuido_a) end,
         coalesce(r.activa and x.atribuido_a = v_me, false),
         coalesce((r.activa and x.atribuido_a = v_me)
                  or (x.estado = 'em_entrega' and x.entregador_id = v_me), false)
    from pedidos x
    join clientes c on c.id = x.cliente_id
    left join pontos_entrega pe on pe.id = x.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, x.zona_id)
    cross join lateral (select (x.atribuido_a is not null
                                and x.atribuido_em > now() - make_interval(mins => v_reserva)
                                and x.estado in ('confirmado', 'em_preparacao')) as activa) r
   where x.deletado_em is null
     and x.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
     and (v_gerir or x.estado <> 'pendente')
     and (x.agendado_para is null or x.agendado_para <= now() + interval '90 minutes')
   order by coalesce(x.agendado_para, x.criado_em);
end $function$;

revoke execute on function pedidos_operador() from public, anon;
grant  execute on function pedidos_operador() to authenticated;
