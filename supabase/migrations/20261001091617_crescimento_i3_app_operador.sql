-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I3 · Servidor da app do operador
--
--   1. Entrada dos funcionários: funcionarios.telefone; o administrador
--      principal regista o número (definir_telefone_funcionario) e, no primeiro
--      login por SMS, ligar_funcionario() liga a conta ao funcionário.
--      meu_funcionario() devolve o funcionário e as permissões efectivas.
--   2. Leituras do operador, sempre com a permissão do organograma:
--      painel_programa (O1, indicacoes.ver), ganhos_em_verificacao (O2,
--      indicacoes.verificar), confirmar_ganhos_indicador (O2 "Confirmar todos"),
--      levantamentos_operador (O3, indicacoes.aprovar_pagamentos),
--      embaixadores (O4, plataforma.parametros), pedidos_operador (E1 e fila de
--      pedidos, entregas.registar / pedidos.gerir).
--   3. RLS só do que a I3 usa: leitura das caixas (E1 escolhe a caixa aberta).
--   4. N3 enfileirada por rever_ganho: completa o nome do amigo e o saldo da semana.
--   5. Auditoria das escritas directas em cozinhas e cardapio (O6).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Entrada dos funcionários
-- -----------------------------------------------------------------------------
alter table funcionarios add column if not exists telefone text;
create unique index funcionarios_telefone_key on funcionarios (normalizar_telefone(telefone))
  where telefone is not null and deletado_em is null;

create or replace function definir_telefone_funcionario(p_funcionario uuid, p_telefone text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_admin    uuid := funcionario_actual();
  v_telefone text := normalizar_telefone(p_telefone);
begin
  if v_admin is null or not exists (select 1 from funcionarios where id = v_admin and administrador_principal) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'administrador_principal';
  end if;
  if p_telefone is not null and (v_telefone is null or v_telefone !~ '^9\d{8}$') then
    raise exception 'numero_invalido' using errcode = 'P0001';
  end if;
  update funcionarios
     set telefone = v_telefone,
         -- novo número: a conta antiga deixa de entrar como este funcionário
         auth_user_id = case when normalizar_telefone(telefone) is distinct from v_telefone then null else auth_user_id end,
         atualizado_em = now()
   where id = p_funcionario and deletado_em is null;
  if not found then
    raise exception 'funcionario_inexistente' using errcode = 'P0001';
  end if;
  perform registar_auditoria('funcionario_telefone', 'funcionarios', p_funcionario,
                             jsonb_build_object('telefone', v_telefone));
end $$;

-- Primeiro login: liga a conta (telefone confirmado por SMS) ao funcionário com esse número
create or replace function ligar_funcionario() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  v_telefone text;
  v_func     uuid;
begin
  if v_uid is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  select id into v_func from funcionarios where auth_user_id = v_uid and deletado_em is null;
  if found then
    return v_func;
  end if;
  select normalizar_telefone(phone) into v_telefone from auth.users where id = v_uid;
  update funcionarios set auth_user_id = v_uid, atualizado_em = now()
   where v_telefone is not null and normalizar_telefone(telefone) = v_telefone
     and auth_user_id is null and deletado_em is null
  returning id into v_func;
  if v_func is not null then
    perform registar_auditoria('funcionario_ligado_app', 'funcionarios', v_func, '{}'::jsonb);
  end if;
  return v_func;
end $$;

create or replace function meu_funcionario() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'funcionario_id', f.id,
           'nome', f.nome,
           'cargo', f.cargo,
           'administrador_principal', f.administrador_principal,
           'permissoes', coalesce((select jsonb_agg(p.chave order by p.chave) from permissoes p
                                    where p.deletado_em is null and tem_permissao(p.chave)), '[]'))
    from funcionarios f
   where f.auth_user_id = auth.uid() and auth.uid() is not null and f.deletado_em is null;
$$;

-- -----------------------------------------------------------------------------
-- 2. Leituras do operador
-- -----------------------------------------------------------------------------
-- O1. Painel do programa num período [p_inicio, p_fim] (datas de Luanda)
create or replace function painel_programa(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz := (p_inicio::timestamp) at time zone 'Africa/Luanda';
  v_fim timestamptz := ((p_fim + 1)::timestamp) at time zone 'Africa/Luanda';
  r     jsonb;
begin
  perform exigir_permissao('indicacoes.ver');
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;

  with ganhos as (
    select * from ganhos_indicacao
     where deletado_em is null and criado_em >= v_ini and criado_em < v_fim
  ),
  pedidos_indicados as (
    select x.* from pedidos x
     where x.estado = 'entregue_pago' and x.deletado_em is null
       and x.entregue_em >= v_ini and x.entregue_em < v_fim
       and exists (select 1 from ligacoes_indicacao l where l.indicado_id = x.cliente_id and l.deletado_em is null)
  ),
  terminados as (
    select l.* from ligacoes_indicacao l
     where l.deletado_em is null and l.expira_em >= v_ini and l.expira_em < v_fim
  )
  select jsonb_build_object(
    'custo', (select coalesce(sum(valor), 0) from ganhos where estado in ('confirmado', 'pago'))
             + (select coalesce(sum(desconto_indicacao), 0) from pedidos_indicados),
    'ganhos', (select coalesce(sum(valor), 0) from ganhos where estado in ('confirmado', 'pago')),
    'descontos', (select coalesce(sum(desconto_indicacao), 0) from pedidos_indicados),
    'vendas_indicacao', (select coalesce(sum(subtotal + taxa_entrega - desconto_indicacao), 0) from pedidos_indicados),
    'clientes_novos', (select count(*) from ligacoes_indicacao l
                        join pedidos x on x.id = l.primeiro_pedido_id
                       where l.deletado_em is null and x.entregue_em >= v_ini and x.entregue_em < v_fim),
    'indicadores_activos', (select count(distinct indicador_id) from ganhos where estado in ('confirmado', 'pago')),
    'periodos_terminados', (select count(*) from terminados),
    'retidos', (select count(*) from terminados t
                 where exists (select 1 from pedidos x where x.cliente_id = t.indicado_id
                                 and x.estado = 'entregue_pago' and x.entregue_em > t.expira_em)),
    'revistos', (select count(*) from ganhos where revisto_em is not null),
    'anulados_verificacao', (select count(*) from ganhos where estado = 'anulado' and motivo = 'rejeitado_verificacao'),
    'em_verificacao', (select count(*) from ganhos_indicacao where estado = 'em_verificacao' and deletado_em is null),
    'top', coalesce((select jsonb_agg(t order by t.valor desc, t.amigos desc) from (
              select g.indicador_id, c.nome, ci.nivel, count(distinct g.indicado_id)::int as amigos, sum(g.valor)::int as valor
                from ganhos g join clientes c on c.id = g.indicador_id
                left join codigos_indicacao ci on ci.cliente_id = g.indicador_id
               where g.estado in ('confirmado', 'pago')
               group by g.indicador_id, c.nome, ci.nivel
               order by sum(g.valor) desc limit 10) t), '[]'))
  into r;
  return r;
end $$;

-- O2. Ganhos em verificação, com a informação de apoio à decisão
create or replace function ganhos_em_verificacao()
returns table (ganho_id uuid, criado_em timestamptz, valor integer, motivo text,
               indicador_id uuid, indicador_nome text, indicador_telefone text, indicador_nivel text,
               indicado_nome text, pedido_id uuid, pedido_dispositivo text, pagador_distinto boolean,
               ponto_tipo text, ponto_lat double precision, ponto_lng double precision, ponto_referencia text,
               numero_indicador text, numero_indicado text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('indicacoes.verificar');
  return query
  select g.id, g.criado_em, g.valor, g.motivo,
         g.indicador_id, ci.nome, ci.telefone, cod.nivel,
         cd.nome, x.id, x.dispositivo_id, x.pagador_distinto,
         pe.tipo, pe.lat, pe.lng, pe.referencia,
         (select pg.numero_destino from pagamentos_indicacao pg
           where pg.indicador_id = g.indicador_id and pg.numero_destino is not null
           order by pg.criado_em desc limit 1),
         (select pg.numero_destino from pagamentos_indicacao pg
           where pg.indicador_id = g.indicado_id and pg.numero_destino is not null
           order by pg.criado_em desc limit 1)
    from ganhos_indicacao g
    join clientes ci on ci.id = g.indicador_id
    join clientes cd on cd.id = g.indicado_id
    left join codigos_indicacao cod on cod.cliente_id = g.indicador_id
    left join pedidos x on x.id = g.pedido_id
    left join pontos_entrega pe on pe.id = x.ponto_entrega_id
   where g.estado = 'em_verificacao' and g.deletado_em is null
   order by ci.nome, g.indicador_id, g.criado_em;
end $$;

-- O2. "Confirmar todos" os ganhos em verificação de um indicador (cada um auditado)
create or replace function confirmar_ganhos_indicador(p_indicador uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare
  g   uuid;
  n   integer := 0;
begin
  perform exigir_permissao('indicacoes.verificar');
  for g in select id from ganhos_indicacao
            where indicador_id = p_indicador and estado = 'em_verificacao' and deletado_em is null
            order by criado_em loop
    perform rever_ganho(g, 'confirmar');
    n := n + 1;
  end loop;
  return n;
end $$;

-- O3. Levantamentos, com destaque para o primeiro levantamento de cada indicador
create or replace function levantamentos_operador(p_estado text default null)
returns table (pagamento_id uuid, criado_em timestamptz, indicador_id uuid, indicador_nome text,
               indicador_telefone text, valor integer, metodo text, numero_destino text, lote_id uuid,
               parcela integer, total_parcelas integer, estado text, referencia text, motivo_rejeicao text,
               pago_em timestamptz, primeiro_levantamento boolean, saldo_disponivel integer)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('indicacoes.aprovar_pagamentos');
  return query
  select pg.id, pg.criado_em, pg.indicador_id, c.nome, c.telefone, pg.valor, pg.metodo, pg.numero_destino,
         pg.lote_id, pg.parcela, pg.total_parcelas, pg.estado, pg.referencia, pg.motivo_rejeicao, pg.pago_em,
         not exists (select 1 from pagamentos_indicacao a
                      where a.indicador_id = pg.indicador_id and a.tipo = 'levantamento' and a.estado = 'pago'
                        and a.id <> pg.id and a.criado_em < pg.criado_em and a.deletado_em is null),
         s.saldo_disponivel
    from pagamentos_indicacao pg
    join clientes c on c.id = pg.indicador_id
    left join saldo_indicacao s on s.indicador_id = pg.indicador_id
   where pg.tipo = 'levantamento' and pg.deletado_em is null
     and (p_estado is null or pg.estado = p_estado)
   order by case pg.estado when 'pedido' then 0 when 'aprovado' then 1 else 2 end, pg.criado_em;
end $$;

-- O4. Embaixadores: actuais e elegíveis (indicados activos >= limiar_embaixador)
create or replace function embaixadores()
returns table (cliente_id uuid, nome text, telefone text, nivel text, indicados_activos integer,
               ganho_mes integer, elegivel boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('plataforma.parametros');
  return query
  with activos as (
    select l.indicador_id, count(*)::int as n
      from ligacoes_indicacao l
     where l.deletado_em is null and (l.expira_em is null or l.expira_em > now())
     group by l.indicador_id
  )
  select c.id, c.nome, c.telefone, cod.nivel, coalesce(a.n, 0),
         (select coalesce(sum(g.valor), 0)::int from ganhos_indicacao g
           where g.indicador_id = c.id and g.estado in ('confirmado', 'pago')
             and g.confirmado_em >= inicio_mes_luanda()),
         coalesce(a.n, 0) >= (select limiar_embaixador from parametros where unico)
    from codigos_indicacao cod
    join clientes c on c.id = cod.cliente_id
    left join activos a on a.indicador_id = c.id
   where cod.deletado_em is null
     and (cod.nivel = 'embaixador' or coalesce(a.n, 0) >= (select limiar_embaixador from parametros where unico))
   order by (cod.nivel = 'embaixador') desc, coalesce(a.n, 0) desc;
end $$;

-- E1 e fila de pedidos. O entregador (entregas.registar) vê os pedidos confirmados,
-- em preparação e em entrega; quem tem pedidos.gerir vê também os pendentes.
create or replace function pedidos_operador()
returns table (pedido_id uuid, criado_em timestamptz, estado text, cozinha_id uuid, cliente_nome text,
               cliente_telefone text, itens jsonb, subtotal integer, taxa_entrega integer,
               desconto_indicacao integer, credito_indicacao_usado integer, a_pagar integer,
               observacoes text, hora_prometida timestamptz, pagador_distinto boolean,
               ponto_entrega_id uuid, ponto_tipo text, ponto_lat double precision, ponto_lng double precision,
               ponto_referencia text, zona_nome text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_gerir    boolean := tem_permissao('pedidos.gerir');
begin
  if not (v_gerir or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  return query
  select x.id, x.criado_em, x.estado, x.cozinha_id, c.nome, c.telefone, x.itens,
         x.subtotal::int, x.taxa_entrega::int, x.desconto_indicacao::int, x.credito_indicacao_usado::int,
         (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado)::int,
         x.observacoes, x.hora_prometida, x.pagador_distinto,
         pe.id, pe.tipo, pe.lat, pe.lng, pe.referencia, z.nome
    from pedidos x
    join clientes c on c.id = x.cliente_id
    left join pontos_entrega pe on pe.id = x.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, x.zona_id)
   where x.deletado_em is null
     and x.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
     and (v_gerir or x.estado <> 'pendente')
   order by x.criado_em;
end $$;

-- -----------------------------------------------------------------------------
-- 3. RLS: caixas abertas para a entrega (regra 8)
-- -----------------------------------------------------------------------------
create policy ler on caixa for select to authenticated
  using (deletado_em is null and (tem_permissao('entregas.registar') or tem_permissao('pedidos.gerir')));
grant select on caixa to authenticated;

-- -----------------------------------------------------------------------------
-- 4. N3 enfileirada por rever_ganho: nome do amigo e saldo da semana
-- -----------------------------------------------------------------------------
create or replace function notificacoes_completar_dados() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  lig ligacoes_indicacao;
begin
  if new.codigo = 'N2' and not (new.dados ? 'ganho_por_pedido') then
    select * into lig from ligacoes_indicacao
     where indicador_id = new.cliente_id and deletado_em is null
     order by ligado_em desc limit 1;
    if found then
      new.dados := new.dados || jsonb_build_object('ganho_por_pedido', lig.ganho_por_pedido_garantido,
                                                   'duracao_dias', lig.duracao_dias_garantida);
    end if;
  elsif new.codigo = 'N3' then
    if not (new.dados ? 'indicado_nome') then
      new.dados := new.dados || jsonb_build_object('indicado_nome',
        (select split_part(trim(c.nome), ' ', 1) from pedidos x join clientes c on c.id = x.cliente_id
          where x.id = (new.dados ->> 'pedido_id')::uuid));
    end if;
    if not (new.dados ? 'saldo_semana') then
      new.dados := new.dados || jsonb_build_object('saldo_semana',
        (select coalesce(sum(valor), 0) from ganhos_indicacao
          where indicador_id = new.cliente_id and estado in ('confirmado', 'pago')
            and confirmado_em >= inicio_semana_luanda() and deletado_em is null));
    end if;
  end if;
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- 4b. Auditoria das escritas directas do O6 (cozinhas e cardápio)
-- -----------------------------------------------------------------------------
create or replace function auditar_alteracao_tabela() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_mudou jsonb := '{}';
begin
  if tg_op = 'UPDATE' then
    select coalesce(jsonb_object_agg(n.key, jsonb_build_object('de', o.value, 'para', n.value)), '{}')
      into v_mudou
      from jsonb_each(to_jsonb(new)) n
      join jsonb_each(to_jsonb(old)) o using (key)
     where n.value is distinct from o.value
       and n.key not in ('atualizado_em', 'sincronizado_em');
    if v_mudou = '{}' then
      return new;
    end if;
  end if;
  perform registar_auditoria(tg_table_name || case when tg_op = 'INSERT' then '_criada' else '_alterada' end,
                             tg_table_name, new.id,
                             case when tg_op = 'INSERT' then to_jsonb(new) else v_mudou end);
  return new;
end $$;

create trigger trg_auditar after insert or update on cozinhas
for each row execute function auditar_alteracao_tabela();
create trigger trg_auditar after insert or update on cardapio
for each row execute function auditar_alteracao_tabela();

-- -----------------------------------------------------------------------------
-- 5. Privilégios
-- -----------------------------------------------------------------------------
revoke execute on function definir_telefone_funcionario(uuid, text), ligar_funcionario(), meu_funcionario(),
                           painel_programa(date, date), ganhos_em_verificacao(), confirmar_ganhos_indicador(uuid),
                           levantamentos_operador(text), embaixadores(), pedidos_operador()
  from public, anon;
grant execute on function definir_telefone_funcionario(uuid, text), ligar_funcionario(), meu_funcionario(),
                          painel_programa(date, date), ganhos_em_verificacao(), confirmar_ganhos_indicador(uuid),
                          levantamentos_operador(text), embaixadores(), pedidos_operador()
  to authenticated;
revoke execute on function notificacoes_completar_dados() from public, anon, authenticated;
revoke execute on function auditar_alteracao_tabela() from public, anon, authenticated;
