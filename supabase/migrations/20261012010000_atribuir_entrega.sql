-- Atribuição explícita de entregas (modelo "push", a par do autosserviço).
-- O gerente/atendente da cozinha pode RESERVAR um pedido confirmado a um estafeta e avisá-lo; o
-- estafeta aceita (marca "em entrega") ou recusa (volta ao conjunto). A reserva expira sozinha ao fim
-- de parametros.entrega_reserva_min, voltando o pedido a estar disponível para qualquer estafeta.
-- Nada disto bloqueia o autosserviço: sem reserva activa, qualquer estafeta da cozinha continua a pegar.

alter table pedidos
  add column atribuido_a  uuid references funcionarios(id),
  add column atribuido_em timestamptz;
create index pedidos_atribuido_idx on pedidos (atribuido_a) where atribuido_a is not null;
comment on column pedidos.atribuido_a is 'Estafeta a quem o pedido foi reservado (I11+). Só o servidor escreve.';

alter table parametros
  add column entrega_reserva_min integer not null default 10 check (entrega_reserva_min between 1 and 120);
comment on column parametros.entrega_reserva_min is
  'Minutos que uma entrega fica reservada a um estafeta antes de voltar a ficar disponível para todos';

-- Proteger as colunas novas da escrita do cliente (só o servidor as escreve).
create or replace function pedidos_antes_actualizar()
 returns trigger language plpgsql set search_path to 'public'
as $function$
declare
  v_caixa  caixa;
  v_soma   numeric;
begin
  if e_escrita_cliente() then
    if new.estado is distinct from old.estado then
      raise exception 'estado_so_no_servidor' using errcode = '42501';
    end if;
    new.desconto_indicacao := old.desconto_indicacao;
    new.credito_indicacao_usado := old.credito_indicacao_usado;
    new.pago_pacote := old.pago_pacote;
    new.refeicoes_pacote := old.refeicoes_pacote;
    new.adesao_pacote_id := old.adesao_pacote_id;
    new.entregue_em := old.entregue_em;
    new.cliente_id := old.cliente_id;
    new.cozinha_id := old.cozinha_id;
    new.grupo_id := old.grupo_id;
    new.caixa_id := old.caixa_id;
    new.atribuido_a := old.atribuido_a;
    new.atribuido_em := old.atribuido_em;
    if new.pagador_distinto is distinct from old.pagador_distinto
       and not tem_permissao('entregas.registar') then
      raise exception 'sem_permissao' using errcode = '42501', detail = 'entregas.registar';
    end if;
  end if;

  if new.estado is distinct from old.estado then
    if not transicao_estado_valida(old.estado, new.estado) then
      raise exception 'transicao_invalida' using errcode = 'P0001',
        detail = old.estado || ' -> ' || new.estado;
    end if;
    if new.estado = 'entregue_pago' then
      if new.caixa_id is null then
        raise exception 'caixa_obrigatoria' using errcode = 'P0001';
      end if;
      select * into v_caixa from caixa where id = new.caixa_id;
      if not found or v_caixa.deletado_em is not null or v_caixa.fechamento is not null
         or v_caixa.cozinha_id <> new.cozinha_id then
        raise exception 'caixa_invalida' using errcode = 'P0001';
      end if;
      select coalesce(sum((x ->> 'valor')::numeric), 0) into v_soma
        from jsonb_array_elements(new.parcelas) x;
      if v_soma + new.credito_indicacao_usado + new.pago_pacote
         <> new.subtotal + new.taxa_entrega - new.desconto_indicacao then
        raise exception 'parcelas_nao_somam_valor_final' using errcode = 'P0001',
          detail = (v_soma + new.credito_indicacao_usado + new.pago_pacote)::text || ' <> '
                   || (new.subtotal + new.taxa_entrega - new.desconto_indicacao)::text;
      end if;
      new.entregue_em := coalesce(new.entregue_em, now());
    end if;
  end if;
  return new;
end $function$;

-- Ao entrar "em entrega": se estiver reservado a OUTRO estafeta (reserva activa) e quem marca não é
-- esse estafeta nem gerente da cozinha, bloqueia; caso contrário fica o entregador e a reserva liberta-se.
create or replace function pedidos_registar_entregador() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.estado = 'em_entrega' and old.estado is distinct from 'em_entrega' then
    if new.atribuido_a is not null
       and new.atribuido_a is distinct from funcionario_actual()
       and new.atribuido_em > now() - make_interval(mins => (select entrega_reserva_min from parametros where unico))
       and not pode_na_cozinha('pedidos.gerir', new.cozinha_id) then
      raise exception 'reservado_a_outro' using errcode = '42501';
    end if;
    new.entregador_id := coalesce(funcionario_actual(), new.entregador_id);
    new.atribuido_a := null;
    new.atribuido_em := null;
  end if;
  return new;
end $$;

-- Atribuir (reservar) um pedido a um estafeta e avisá-lo (N32 com o pedido, para o sino/push).
create or replace function atribuir_entrega(p_pedido uuid, p_estafeta uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_ped pedidos; v_resumo text; v_zona text;
begin
  select * into v_ped from pedidos where id = p_pedido and deletado_em is null;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  if not pode_na_cozinha('pedidos.gerir', v_ped.cozinha_id) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir';
  end if;
  if v_ped.estado not in ('confirmado', 'em_preparacao') then
    raise exception 'estado_nao_atribuivel' using errcode = 'P0001', detail = v_ped.estado;
  end if;
  if not tem_permissao_de(p_estafeta, 'entregas.registar') then
    raise exception 'nao_e_estafeta' using errcode = 'P0001';
  end if;
  update pedidos set atribuido_a = p_estafeta, atribuido_em = now(), atualizado_em = now() where id = p_pedido;
  select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || trim(coalesce(i ->> 'nome', 'Prato')), ', ')
    into v_resumo from jsonb_array_elements(v_ped.itens) i;
  select z.nome into v_zona from zonas z
   where z.id = coalesce((select zona_id from pontos_entrega where id = v_ped.ponto_entrega_id), v_ped.zona_id);
  insert into notificacoes_fila (funcionario_id, codigo, dados)
  values (p_estafeta, 'N32', jsonb_build_object(
            'titulo', 'Nova entrega para ti',
            'corpo', 'Tens uma entrega: ' || left(coalesce(v_resumo, 'Pedido'), 80)
                     || coalesce(' · ' || v_zona, '') || '. Abre para aceitar.',
            'pedido_id', p_pedido));
  perform registar_auditoria('entrega_atribuida', 'pedido', p_pedido, jsonb_build_object('estafeta', p_estafeta));
end $$;

-- Recusar/libertar a reserva (o estafeta reservado ou um gerente da cozinha).
create or replace function recusar_entrega(p_pedido uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_ped pedidos;
begin
  select * into v_ped from pedidos where id = p_pedido and deletado_em is null;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  if not (v_ped.atribuido_a = funcionario_actual() or pode_na_cozinha('pedidos.gerir', v_ped.cozinha_id)) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  update pedidos set atribuido_a = null, atribuido_em = null, atualizado_em = now() where id = p_pedido;
  perform registar_auditoria('entrega_recusada', 'pedido', p_pedido, jsonb_build_object('por', funcionario_actual()));
end $$;

-- Estafetas para o seletor de atribuição (carga actual e se está online), ordenados por menos carga.
create or replace function estafetas_para_atribuir(p_cozinha uuid)
returns table (funcionario_id uuid, nome text, a_levar int, online boolean)
language sql stable security definer set search_path = public as $$
  select f.id, f.nome,
         (select count(*) from pedidos p
           where p.entregador_id = f.id and p.estado = 'em_entrega' and p.deletado_em is null)::int,
         exists (select 1 from posicoes_entregadores pe
                  where pe.funcionario_id = f.id and pe.atualizado_em > now() - interval '2 minutes')
    from funcionarios f
   where f.deletado_em is null and tem_permissao_de(f.id, 'entregas.registar')
     and pode_na_cozinha('pedidos.gerir', p_cozinha)  -- barreira: só gerente da cozinha vê a lista
   order by (select count(*) from pedidos p
              where p.entregador_id = f.id and p.estado = 'em_entrega' and p.deletado_em is null), f.nome;
$$;

-- pedidos_operador passa a trazer a atribuição activa (reservado a quem, e se é a mim).
drop function if exists pedidos_operador();
create function pedidos_operador()
 returns table(pedido_id uuid, criado_em timestamptz, estado text, cozinha_id uuid, cliente_nome text,
               cliente_telefone text, itens jsonb, subtotal integer, taxa_entrega integer,
               desconto_indicacao integer, credito_indicacao_usado integer, a_pagar integer,
               observacoes text, hora_prometida timestamptz, pagador_distinto boolean,
               ponto_entrega_id uuid, ponto_tipo text, ponto_lat double precision, ponto_lng double precision,
               ponto_referencia text, zona_nome text,
               atribuido_a uuid, atribuido_a_nome text, atribuido_a_mim boolean)
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
         coalesce(r.activa and x.atribuido_a = v_me, false)
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

revoke execute on function atribuir_entrega(uuid, uuid), recusar_entrega(uuid),
                           estafetas_para_atribuir(uuid), pedidos_operador() from public, anon;
grant  execute on function atribuir_entrega(uuid, uuid), recusar_entrega(uuid),
                           estafetas_para_atribuir(uuid), pedidos_operador() to authenticated;
