-- Teste de 6 meses: com o histórico a crescer, cada entrega de um amigo indicado ficava mais lenta.
-- A verificação "quantos indicados no mesmo local" (processar_ganho_indicacao) percorria TODOS os
-- ganhos de indicação e calculava a distância a cada um (mesmo_ponto_entrega linha a linha); o
-- mesmo no limite de descontos por local (avaliar_desconto_indicacao, sobre todos os pedidos com
-- desconto). Agora procuram-se primeiro os pontos de entrega próximos pela caixa de coordenadas
-- (índice pontos_entrega_lat_lng_idx) e só depois os pedidos e ganhos desses pontos (índices
-- pedidos_ponto_entrega_id_idx e ganhos_indicacao_pedido_id_key). O resultado é o mesmo de
-- mesmo_ponto_entrega: o próprio ponto, ou pontos do mesmo tipo a <= raio_mesmo_local_m.

-- Pontos de entrega "no mesmo local" que p_ponto (inclui o próprio).
-- 1 grau de latitude = 111 195 m; a caixa usa 111 000 m (um pouco maior) e a distância exacta
-- decide, por isso nenhum ponto que mesmo_ponto_entrega aceitaria fica de fora.
create or replace function pontos_entrega_proximos(p_ponto uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select p_ponto
  union
  select lb.id
    from pontos_entrega la
    join parametros p on p.unico
    join pontos_entrega lb
      on lb.tipo = la.tipo
     and lb.lat between la.lat - p.raio_mesmo_local_m / 111000.0 and la.lat + p.raio_mesmo_local_m / 111000.0
     and lb.lng between la.lng - p.raio_mesmo_local_m / (111000.0 * greatest(cos(radians(la.lat)), 0.01))
                    and la.lng + p.raio_mesmo_local_m / (111000.0 * greatest(cos(radians(la.lat)), 0.01))
   where la.id = p_ponto
     and distancia_m(la.lat, la.lng, lb.lat, lb.lng) <= p.raio_mesmo_local_m;
$$;
revoke execute on function pontos_entrega_proximos(uuid) from public, anon, authenticated;

create or replace function processar_ganho_indicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  p               parametros;
  lig             ligacoes_indicacao;
  v_tipo_local    text;
  nivel_ind       text;
  total_sem       int;
  indicados_local int;
  v_estado        text := 'confirmado';
  v_motivo        text := null;
  v_ganho         uuid;
  g               record;
begin
  -- Estorno de um pedido já pago: ganhos ainda não pagos são anulados
  if old.estado = 'entregue_pago' and new.estado <> 'entregue_pago' then
    for g in update ganhos_indicacao
                set estado = 'anulado', motivo = 'pedido_estornado'
              where pedido_id = new.id and estado in ('em_verificacao','confirmado')
             returning id loop
      perform registar_auditoria('ganho_indicacao_anulado', 'ganhos_indicacao', g.id,
                                 jsonb_build_object('motivo', 'pedido_estornado', 'pedido_id', new.id));
    end loop;
    return new;
  end if;

  if new.estado <> 'entregue_pago' or old.estado = 'entregue_pago' then
    return new;
  end if;
  if not funcionalidade_activa('indicacao') then return new; end if;

  select * into p from parametros where unico;
  select * into lig from ligacoes_indicacao
   where indicado_id = new.cliente_id and deletado_em is null
   for update;
  if not found then return new; end if;

  -- 1.º pedido pago: arranca o período (duração garantida na ligação)
  if lig.expira_em is null then
    update ligacoes_indicacao
       set primeiro_pedido_id = new.id,
           expira_em = coalesce(new.entregue_em, now()) + make_interval(days => lig.duracao_dias_garantida),
           desconto_usado = (new.desconto_indicacao > 0)
     where id = lig.id
    returning * into lig;
  end if;

  if now() > lig.expira_em then return new; end if;
  if exists (select 1 from ganhos_indicacao where pedido_id = new.id) then
    return new;
  end if;

  -- Sinal forte: mesmo dispositivo (campo comum dispositivo_id; linhas criadas
  -- pelo servidor têm dispositivo_id = 'servidor' e não contam)
  if exists (
    select 1 from pedidos a
     where a.cliente_id = lig.indicador_id
       and a.dispositivo_id is not null and a.dispositivo_id <> 'servidor'
       and a.dispositivo_id in (select b.dispositivo_id from pedidos b
                                 where b.cliente_id = new.cliente_id
                                   and b.dispositivo_id is not null
                                   and b.dispositivo_id <> 'servidor')) then
    v_estado := 'anulado'; v_motivo := 'mesmo_dispositivo';
  end if;

  -- Sinal médio: mesmo número de levantamento
  if v_estado = 'confirmado' and exists (
    select 1 from pagamentos_indicacao a
     where a.indicador_id = lig.indicador_id and a.numero_destino is not null
       and a.numero_destino in (select b.numero_destino from pagamentos_indicacao b
                                 where b.indicador_id = new.cliente_id
                                   and b.numero_destino is not null)) then
    v_estado := 'em_verificacao'; v_motivo := 'numero_pagamento_partilhado';
  end if;

  -- Limite por local residencial
  select tipo into v_tipo_local from pontos_entrega where id = new.ponto_entrega_id;
  if v_estado = 'confirmado' and v_tipo_local = 'residencial' then
    select count(distinct g2.indicado_id) into indicados_local
      from pontos_entrega_proximos(new.ponto_entrega_id) pp(id)
      join pedidos x on x.ponto_entrega_id = pp.id
      join ganhos_indicacao g2 on g2.pedido_id = x.id
     where g2.estado <> 'anulado'
       and g2.indicado_id <> new.cliente_id;
    if indicados_local >= p.max_indicados_por_local then
      v_estado := 'em_verificacao'; v_motivo := 'limite_local';
    end if;
  end if;

  -- Limite semanal (não se aplica a Embaixadores)
  if v_estado = 'confirmado' then
    select nivel into nivel_ind from codigos_indicacao where cliente_id = lig.indicador_id;
    if nivel_ind is distinct from 'embaixador' then
      select coalesce(sum(valor), 0) into total_sem
        from ganhos_indicacao
       where indicador_id = lig.indicador_id
         and estado in ('confirmado','pago')
         and confirmado_em >= inicio_semana_luanda();
      if total_sem >= p.limite_verificacao_semanal then
        v_estado := 'em_verificacao'; v_motivo := 'limite_semanal';
      end if;
    end if;
  end if;

  insert into ganhos_indicacao
    (pedido_id, indicador_id, indicado_id, valor, estado, motivo, confirmado_em, dispositivo_id)
  values
    (new.id, lig.indicador_id, new.cliente_id, lig.ganho_por_pedido_garantido, v_estado, v_motivo,
     case when v_estado = 'confirmado' then now() end, 'servidor')
  returning id into v_ganho;

  perform registar_auditoria('ganho_indicacao_criado', 'ganhos_indicacao', v_ganho,
    jsonb_build_object('estado', v_estado, 'motivo', v_motivo, 'pedido_id', new.id));

  if v_estado = 'confirmado' then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N3', jsonb_build_object(
      'pedido_id', new.id,
      'valor', lig.ganho_por_pedido_garantido,
      'indicado_nome', (select split_part(trim(nome), ' ', 1) from clientes where id = new.cliente_id),
      'saldo_semana', (select coalesce(sum(valor), 0) from ganhos_indicacao
                        where indicador_id = lig.indicador_id and estado in ('confirmado','pago')
                          and confirmado_em >= inicio_semana_luanda())));
  elsif v_estado = 'em_verificacao' and v_motivo = 'limite_semanal'
        and not exists (select 1 from ganhos_indicacao
                         where indicador_id = lig.indicador_id
                           and motivo = 'limite_semanal'
                           and criado_em >= inicio_semana_luanda()
                           and pedido_id <> new.id) then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N4', jsonb_build_object('limite', p.limite_verificacao_semanal));
  end if;

  return new;
end $$;

create or replace function avaliar_desconto_indicacao(p_cliente uuid, p_ponto uuid)
returns table (valor int, motivo text)
language plpgsql stable security definer set search_path = public as $$
declare
  p      parametros;
  lig    ligacoes_indicacao;
  v_tipo text;
  usados int;
begin
  if not funcionalidade_activa('indicacao') then
    return query select 0, 'programa_inactivo'; return;
  end if;
  select * into p from parametros where unico;
  select * into lig from ligacoes_indicacao where indicado_id = p_cliente and deletado_em is null;
  if not found then return query select 0, 'sem_ligacao'; return; end if;
  if lig.desconto_usado then return query select 0, 'desconto_usado'; return; end if;
  if cliente_ja_comprou(p_cliente) then return query select 0, 'cliente_nao_novo'; return; end if;

  -- Já há um pedido em curso com o desconto (evita o desconto em dois pedidos)
  if exists (select 1 from pedidos
              where cliente_id = p_cliente and desconto_indicacao > 0 and deletado_em is null
                and estado not in ('cancelado','estornado')) then
    return query select 0, 'desconto_em_curso'; return;
  end if;

  select tipo into v_tipo from pontos_entrega where id = p_ponto;
  if v_tipo = 'residencial' then
    select count(*) into usados
      from pontos_entrega_proximos(p_ponto) pp(id)
      join pedidos x on x.ponto_entrega_id = pp.id
     where x.desconto_indicacao > 0 and x.estado = 'entregue_pago' and x.deletado_em is null;
    if usados >= p.max_descontos_por_local then
      return query select 0, 'limite_local'; return;
    end if;
  end if;

  -- Valor garantido no momento da ligação (não o parâmetro actual)
  return query select lig.desconto_garantido, 'ok';
end $$;
