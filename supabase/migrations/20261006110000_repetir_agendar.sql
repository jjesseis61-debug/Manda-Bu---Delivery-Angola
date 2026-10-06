-- Agendar a entrega de um pedido (uma vez). Coluna agendado_para:
--   * null        → entregar o quanto antes (como até agora)
--   * data futura → entregar a essa hora. A hora_prometida passa a ser essa, os alertas contam a
--     partir dela e o pedido só entra na fila activa da cozinha ~90 min antes.
-- ("Repetir pedido" é só na app do cliente — repõe os pratos no carrinho — e não precisa de servidor.)

alter table pedidos add column agendado_para timestamptz;
comment on column pedidos.agendado_para is
  'Entrega agendada pelo cliente; null = o quanto antes. Só futuro (validado no trigger).';
create index pedidos_agendado_idx on pedidos (agendado_para)
  where agendado_para is not null and deletado_em is null;

-- A app do cliente escreve esta coluna ao criar o pedido (grant por coluna, como as outras)
grant insert (agendado_para) on pedidos to authenticated;

-- Validação do agendamento feito pela app do cliente: entre 20 minutos e 14 dias no futuro.
create or replace function pedidos_validar_agendado() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.agendado_para is not null and e_escrita_cliente() then
    if new.grupo_id is not null then
      new.agendado_para := null; -- num grupo, a hora de entrega é a do grupo
    elsif new.agendado_para < now() + interval '20 minutes'
       or new.agendado_para > now() + interval '14 days' then
      raise exception 'agendamento_invalido' using errcode = 'P0001', detail = 'entre 20 minutos e 14 dias';
    end if;
  end if;
  return new;
end $$;

revoke execute on function pedidos_validar_agendado() from public, anon, authenticated;

create trigger trg_pedidos_05_agendado before insert on pedidos
for each row execute function pedidos_validar_agendado();

-- hora_prometida passa a respeitar o agendamento
create or replace function pedidos_hora_prometida() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.grupo_id is not null then
    new.hora_prometida := (select hora_entrega from pedidos_grupo where id = new.grupo_id);
  elsif new.agendado_para is not null then
    new.hora_prometida := new.agendado_para;
  else
    new.hora_prometida := coalesce(new.criado_em, now())
                          + make_interval(mins => (select tempo_entrega_min from parametros where unico));
  end if;
  return new;
end $$;
revoke execute on function pedidos_hora_prometida() from public, anon, authenticated;

-- Alertas: o "sem confirmação" conta a partir da hora agendada (não da criação), para um pedido
-- agendado para amanhã não ser dado como "por confirmar há muito tempo" hoje.
create or replace function job_alertas_pedidos() returns int
language plpgsql security definer set search_path = public as $$
declare
  p   parametros;
  x   record;
  n   int := 0;
  v_resumo text;
  v_estado_nome text;
begin
  select * into p from parametros where unico;

  -- 1. Pedidos por confirmar há demasiado tempo (referência: hora agendada, se houver)
  for x in
    select pe.*, c.nome as cliente_nome,
           floor(extract(epoch from now() - coalesce(pe.agendado_para, pe.criado_em)) / 60)::int as minutos
      from pedidos pe join clientes c on c.id = pe.cliente_id
     where pe.deletado_em is null and pe.estado = 'pendente' and pe.grupo_id is null
       and coalesce(pe.agendado_para, pe.criado_em) < now() - make_interval(mins => p.alerta_confirmacao_min)
       and coalesce(pe.agendado_para, pe.criado_em) > now() - interval '6 hours'
       and not exists (select 1 from alertas_pedido a where a.pedido_id = pe.id and a.tipo = 'sem_confirmacao')
  loop
    select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || trim(coalesce(i ->> 'nome', 'Prato')), ', ')
      into v_resumo from jsonb_array_elements(x.itens) i;
    insert into alertas_pedido (dispositivo_id, sincronizado_em, pedido_id, cliente_id, cozinha_id, tipo, minutos)
    values ('servidor', now(), x.id, x.cliente_id, x.cozinha_id, 'sem_confirmacao', x.minutos);
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select g, 'N18', jsonb_build_object('pedido_id', x.id, 'cliente_nome', split_part(trim(x.cliente_nome), ' ', 1),
                                        'resumo', left(coalesce(v_resumo, 'pedido'), 80), 'minutos', x.minutos)
      from gerentes_do_pedido(x.cozinha_id) g;
    perform registar_auditoria('alerta_sem_confirmacao', 'pedidos', x.id, jsonb_build_object('minutos', x.minutos));
    n := n + 1;
  end loop;

  -- 2. Pedidos que passaram a hora prometida e ainda não foram entregues
  for x in
    select pe.*, c.nome as cliente_nome,
           floor(extract(epoch from now() - pe.hora_prometida) / 60)::int as minutos
      from pedidos pe join clientes c on c.id = pe.cliente_id
     where pe.deletado_em is null and pe.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
       and pe.hora_prometida is not null
       and pe.hora_prometida < now() - make_interval(mins => p.alerta_atraso_min)
       and pe.hora_prometida > now() - interval '6 hours'
       and not exists (select 1 from alertas_pedido a where a.pedido_id = pe.id and a.tipo = 'atraso')
  loop
    v_estado_nome := case x.estado when 'pendente' then 'ainda por confirmar' when 'confirmado' then 'confirmado'
                                   when 'em_preparacao' then 'em preparação' else 'a caminho' end;
    insert into alertas_pedido (dispositivo_id, sincronizado_em, pedido_id, cliente_id, cozinha_id, tipo, minutos, cliente_avisado_em)
    values ('servidor', now(), x.id, x.cliente_id, x.cozinha_id, 'atraso', x.minutos, now());
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select g, 'N19', jsonb_build_object('pedido_id', x.id, 'cliente_nome', split_part(trim(x.cliente_nome), ' ', 1),
                                        'minutos', x.minutos, 'estado_nome', v_estado_nome)
      from (select gerentes_do_pedido(x.cozinha_id) g
            union select x.entregador_id where x.estado = 'em_entrega' and x.entregador_id is not null) s;
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (x.cliente_id, 'N20', jsonb_build_object('pedido_id', x.id, 'minutos', x.minutos));
    perform registar_auditoria('alerta_atraso', 'pedidos', x.id, jsonb_build_object('minutos', x.minutos, 'estado', x.estado));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function job_alertas_pedidos() from public, anon, authenticated;

-- Fila activa da cozinha: os agendados ainda longe (>90 min) ficam de fora até estar quase na hora.
create or replace function pedidos_operador()
 returns table(pedido_id uuid, criado_em timestamptz, estado text, cozinha_id uuid, cliente_nome text, cliente_telefone text, itens jsonb, subtotal integer, taxa_entrega integer, desconto_indicacao integer, credito_indicacao_usado integer, a_pagar integer, observacoes text, hora_prometida timestamptz, pagador_distinto boolean, ponto_entrega_id uuid, ponto_tipo text, ponto_lat double precision, ponto_lng double precision, ponto_referencia text, zona_nome text)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_gerir boolean := tem_permissao('pedidos.gerir');
begin
  if not (v_gerir or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  return query
  select x.id, x.criado_em, x.estado, x.cozinha_id, c.nome, c.telefone, x.itens,
         x.subtotal::int, x.taxa_entrega::int, x.desconto_indicacao::int, x.credito_indicacao_usado::int,
         (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado - x.pago_pacote)::int,
         x.observacoes, x.hora_prometida, x.pagador_distinto,
         pe.id, pe.tipo, pe.lat, pe.lng, pe.referencia, z.nome
    from pedidos x
    join clientes c on c.id = x.cliente_id
    left join pontos_entrega pe on pe.id = x.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, x.zona_id)
   where x.deletado_em is null
     and x.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
     and (v_gerir or x.estado <> 'pendente')
     and (x.agendado_para is null or x.agendado_para <= now() + interval '90 minutes')
   order by coalesce(x.agendado_para, x.criado_em);
end $function$;

-- Lista do que vem agendado (para a cozinha preparar na altura certa)
create or replace function pedidos_agendados()
returns table(pedido_id uuid, agendado_para timestamptz, cozinha_id uuid, cliente_nome text,
              itens jsonb, a_pagar integer, ponto_referencia text, zona_nome text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (tem_permissao('pedidos.gerir') or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  return query
  select x.id, x.agendado_para, x.cozinha_id, c.nome, x.itens,
         (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado - x.pago_pacote)::int,
         pe.referencia, z.nome
    from pedidos x
    join clientes c on c.id = x.cliente_id
    left join pontos_entrega pe on pe.id = x.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, x.zona_id)
   where x.deletado_em is null and x.estado in ('pendente', 'confirmado')
     and x.agendado_para is not null and x.agendado_para > now() + interval '90 minutes'
   order by x.agendado_para;
end $$;

revoke execute on function pedidos_agendados() from public, anon;
grant  execute on function pedidos_agendados() to authenticated;
