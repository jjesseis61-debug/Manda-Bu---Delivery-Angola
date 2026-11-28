-- As notificações da cozinha escolhiam os funcionários só pelos TURNOS. Desde a equipa fixa
-- (equipa_cozinha, atribuída no ecrã Pessoal), um gerente pode pertencer à cozinha sem ter turno — e
-- ficava de fora de tudo: "Novo pedido" (N17), alertas de pedidos atrasados/sem confirmar, alertas de
-- stock e a Central de Avisos "equipa da cozinha". Passa a considerar turno OU equipa fixa; e o gestor
-- geral (cozinhas.gerir) recebe as das cozinhas todas, coerente com o modelo de acessos.

-- Pertence à cozinha (para escolher destinatários): por turno OU pela equipa fixa.
create or replace function pertence_a_cozinha(p_func uuid, p_cozinha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from turnos t
                  where t.funcionario_id = p_func and t.cozinha_id = p_cozinha and t.deletado_em is null)
      or exists (select 1 from equipa_cozinha e
                  where e.funcionario_id = p_func and e.cozinha_id = p_cozinha);
$$;
revoke execute on function pertence_a_cozinha(uuid, uuid) from public, anon, authenticated;

-- Novo pedido para a cozinha (N17) + aviso ao cliente na mudança de estado (N16) — só muda a escolha dos
-- funcionários (turno OU equipa fixa OU gestor geral); o resto fica igual.
create or replace function pedidos_avisar() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_resumo text;
begin
  if tg_op = 'INSERT' then
    if new.estado <> 'pendente' or new.grupo_id is not null then return new; end if;
    select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || trim(coalesce(i ->> 'nome', 'Prato')), ', ')
      into v_resumo from jsonb_array_elements(new.itens) i;
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select f, 'N17', jsonb_build_object(
             'pedido_id', new.id, 'resumo', left(coalesce(v_resumo, 'Pedido'), 80),
             'zona', (select nome from zonas where id = new.zona_id),
             'total', new.subtotal + new.taxa_entrega - new.desconto_indicacao)
      from funcionarios_com_permissao('pedidos.gerir') f
     where (select administrador_principal from funcionarios where id = f)
        or tem_permissao_de(f, 'cozinhas.gerir')
        or pertence_a_cozinha(f, new.cozinha_id);
    return new;
  end if;

  if new.estado is not distinct from old.estado
     or new.estado not in ('confirmado', 'em_entrega', 'entregue_pago', 'cancelado') then
    return new;
  end if;
  -- Quem cancelou foi o próprio cliente: não precisa de aviso
  if new.estado = 'cancelado' and cliente_actual() is not distinct from new.cliente_id then return new; end if;
  insert into notificacoes_fila (cliente_id, codigo, dados)
  values (new.cliente_id, 'N16', jsonb_build_object(
            'pedido_id', new.id, 'estado', new.estado,
            'cozinha_nome', (select trim(nome) from cozinhas where id = new.cozinha_id),
            'motivo', new.motivo_cancelamento));
  return new;
end $$;
revoke execute on function pedidos_avisar() from public, anon, authenticated;

-- Alertas de pedidos (atrasados / sem confirmar)
create or replace function gerentes_do_pedido(p_cozinha uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select f from funcionarios_com_permissao('pedidos.gerir') f
   where (select administrador_principal from funcionarios where id = f)
      or tem_permissao_de(f, 'cozinhas.gerir')
      or pertence_a_cozinha(f, p_cozinha);
$$;
revoke execute on function gerentes_do_pedido(uuid) from public, anon, authenticated;

-- Alertas de stock
create or replace function responsaveis_stock(p_cozinha uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select f from funcionarios_com_permissao('stock.gerir') f
   where (select administrador_principal from funcionarios where id = f)
      or tem_permissao_de(f, 'cozinhas.gerir')
      or pertence_a_cozinha(f, p_cozinha);
$$;
revoke execute on function responsaveis_stock(uuid) from public, anon, authenticated;

-- Central de Avisos: "equipa de uma cozinha" (func_cozinha) passa a incluir a equipa fixa
create or replace function avisos_destinatarios(p_publico text, p_alvo jsonb)
returns table (cliente_id uuid, funcionario_id uuid)
language sql stable security definer set search_path to 'public' as $function$
  with base as (
    select distinct d.cliente_id, d.funcionario_id
      from dispositivos_push d
     where d.activo and d.deletado_em is null
  )
  select b.cliente_id, null::uuid
    from base b
   where p_publico = 'clientes_todos' and b.cliente_id is not null
  union all
  select b.cliente_id, null::uuid from base b
   where p_publico = 'clientes_zona' and b.cliente_id is not null
     and exists (select 1 from pedidos p where p.cliente_id = b.cliente_id and p.zona_id = (p_alvo ->> 'zona_id')::uuid)
  union all
  select b.cliente_id, null::uuid from base b
   where p_publico = 'clientes_cozinha' and b.cliente_id is not null
     and exists (select 1 from pedidos p where p.cliente_id = b.cliente_id and p.cozinha_id = (p_alvo ->> 'cozinha_id')::uuid)
  union all
  select (p_alvo ->> 'cliente_id')::uuid, null::uuid
   where p_publico = 'cliente' and nullif(p_alvo ->> 'cliente_id','') is not null
  union all
  select null::uuid, b.funcionario_id from base b
   where p_publico = 'func_todos' and b.funcionario_id is not null
  union all
  select null::uuid, b.funcionario_id from base b
   where p_publico = 'func_permissao' and b.funcionario_id is not null
     and tem_permissao_de(b.funcionario_id, p_alvo ->> 'permissao')
  union all
  select null::uuid, b.funcionario_id from base b
   where p_publico = 'func_cozinha' and b.funcionario_id is not null
     and pertence_a_cozinha(b.funcionario_id, (p_alvo ->> 'cozinha_id')::uuid);
$function$;
revoke execute on function avisos_destinatarios(text, jsonb) from public, anon, authenticated;
