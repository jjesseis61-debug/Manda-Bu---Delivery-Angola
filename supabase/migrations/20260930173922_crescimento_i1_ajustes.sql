-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I1 · Ajustes
--
-- Decisões aplicadas (sem editar a migração I1):
--   1. pedidos: estado alterado só no servidor; ao chegar a entregue_pago gera
--      a venda (origem 'App cliente'); estorno gera a venda de compensação.
--   2. Nomes: locais_entrega -> pontos_entrega; local_id -> ponto_entrega_id.
--   3. Sincronização: 6 campos comuns também em parametros e funcionalidades;
--      tabelas escritas só pelo servidor rejeitam escritas de dispositivos;
--      estratégia de conflito registada em cada tabela (comment on table).
--   5. Valores garantidos na ligação: ganho_por_pedido_garantido e
--      desconto_garantido, usados no cálculo em vez dos parâmetros actuais.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 2. Nomes: pontos_entrega / ponto_entrega_id
-- -----------------------------------------------------------------------------
alter table locais_entrega rename to pontos_entrega;
alter table enderecos_cliente rename column local_id to ponto_entrega_id;
alter table pedidos           rename column local_id to ponto_entrega_id;
alter table pedidos_grupo     rename column local_id to ponto_entrega_id;

do $$
declare
  r record;
begin
  for r in select c.conrelid::regclass as tabela, c.conname
             from pg_constraint c
            where c.connamespace = 'public'::regnamespace
              and (c.conname like 'locais_entrega%' or c.conname like '%local_id%') loop
    execute format('alter table %s rename constraint %I to %I', r.tabela, r.conname,
                   replace(replace(r.conname, 'locais_entrega', 'pontos_entrega'), 'local_id', 'ponto_entrega_id'));
  end loop;
  for r in select indexname from pg_indexes
            where schemaname = 'public'
              and (indexname like 'locais_entrega%' or indexname like '%local_id%') loop
    execute format('alter index %I rename to %I', r.indexname,
                   replace(replace(r.indexname, 'locais_entrega', 'pontos_entrega'), 'local_id', 'ponto_entrega_id'));
  end loop;
end $$;

alter function locais_antes_inserir() rename to pontos_entrega_antes_inserir;
alter trigger trg_locais_antes_inserir on pontos_entrega rename to trg_pontos_entrega_antes_inserir;

-- Funções cujo nome ou parâmetros mudam
drop function mesmo_local(uuid, uuid);
drop function locais_proximos(float8, float8, text);
drop function meu_desconto_indicacao(uuid);
drop function avaliar_desconto_indicacao(uuid, uuid);

-- -----------------------------------------------------------------------------
-- 3. Sincronização: campos comuns em parametros e funcionalidades
-- -----------------------------------------------------------------------------
alter table parametros
  add column unico           boolean not null default true check (unico),
  add column dispositivo_id  text,
  add column sincronizado_em timestamptz,
  add column deletado_em     timestamptz;
alter table parametros add constraint parametros_unico_key unique (unico);

-- As vistas que liam parametros.id passam a ler parametros.unico antes de a coluna mudar
create or replace view media_avaliacoes_cozinha with (security_invoker = true) as
select a.cozinha_id, round(avg(a.estrelas)::numeric, 1) as media, count(*)::int as total
  from avaliacoes a
 where not a.oculta and a.deletado_em is null
 group by a.cozinha_id
having count(*) >= (select avaliacoes_minimo from parametros where unico);
create or replace view media_avaliacoes_prato with (security_invoker = true) as
select ap.prato_id, round(avg(ap.estrelas)::numeric, 1) as media, count(*)::int as total
  from avaliacoes_pratos ap
  join avaliacoes a on a.id = ap.avaliacao_id
 where not a.oculta and a.deletado_em is null and ap.deletado_em is null
 group by ap.prato_id
having count(*) >= (select avaliacoes_minimo from parametros where unico);

alter table parametros drop constraint parametros_pkey;
alter table parametros drop column id;
alter table parametros add column id uuid not null default gen_random_uuid();
alter table parametros add primary key (id);

alter table funcionalidades
  add column id              uuid not null default gen_random_uuid(),
  add column dispositivo_id  text,
  add column sincronizado_em timestamptz,
  add column deletado_em     timestamptz;
alter table funcionalidades drop constraint funcionalidades_pkey;
alter table funcionalidades add primary key (id);
alter table funcionalidades add constraint funcionalidades_chave_key unique (chave);

create trigger trg_sync_receber before insert or update on parametros
for each row execute function sync_receber();
create trigger trg_sync_receber before insert or update on funcionalidades
for each row execute function sync_receber();

-- Tabelas escritas só pelo servidor: nunca aceitam escritas vindas da fila de
-- saída de um dispositivo (sessões authenticated/anon), mesmo com permissão.
-- SECURITY INVOKER: dentro das funções do servidor current_user é o dono.
create or replace function bloquear_escrita_dispositivo() returns trigger
language plpgsql as $$
begin
  if e_escrita_cliente() then
    raise exception 'escrita_so_no_servidor' using errcode = '42501', detail = tg_table_name;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

do $$
declare
  t text;
begin
  foreach t in array array['parametros','funcionalidades','codigos_indicacao','ligacoes_indicacao',
                           'ganhos_indicacao','pagamentos_indicacao','notificacoes_fila','contadores_zona'] loop
    execute format('create trigger trg_0_so_servidor before insert or update or delete on %I
                    for each row execute function bloquear_escrita_dispositivo()', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated, anon', t);
  end loop;
end $$;

drop policy escrever on parametros;
drop policy escrever on funcionalidades;

-- Alteração de parâmetros e interruptores só por funções (auditadas pelo trigger)
create or replace function alterar_parametros(p_valores jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_cols text;
begin
  perform exigir_permissao('plataforma.parametros');
  if p_valores is null or jsonb_typeof(p_valores) <> 'object' or p_valores = '{}' then
    raise exception 'parametro_invalido' using errcode = 'P0001';
  end if;
  if exists (select 1 from jsonb_object_keys(p_valores) k
              where k in ('id','unico','criado_em','atualizado_em','atualizado_por','dispositivo_id',
                          'sincronizado_em','deletado_em')
                 or not exists (select 1 from information_schema.columns c
                                 where c.table_schema = 'public' and c.table_name = 'parametros'
                                   and c.column_name = k)) then
    raise exception 'parametro_invalido' using errcode = 'P0001';
  end if;
  select string_agg(format('%I', k), ', ') into v_cols from jsonb_object_keys(p_valores) k;
  execute format('update parametros set (%s) = (select %s from jsonb_populate_record(null::parametros, $1)) where unico',
                 v_cols, v_cols)
    using p_valores;
end $$;

create or replace function alterar_funcionalidade(p_chave text, p_activa boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform exigir_permissao('plataforma.parametros');
  update funcionalidades set activa = p_activa where chave = p_chave and deletado_em is null;
  if not found then raise exception 'funcionalidade_inexistente' using errcode = 'P0001'; end if;
end $$;

-- -----------------------------------------------------------------------------
-- 5. Valores garantidos na ligação
-- -----------------------------------------------------------------------------
alter table ligacoes_indicacao
  add column ganho_por_pedido_garantido int check (ganho_por_pedido_garantido >= 0),
  add column desconto_garantido         int check (desconto_garantido >= 0);
update ligacoes_indicacao l
   set ganho_por_pedido_garantido = p.ganho_por_pedido, desconto_garantido = p.desconto_indicado
  from parametros p where p.unico;
alter table ligacoes_indicacao
  alter column ganho_por_pedido_garantido set not null,
  alter column desconto_garantido set not null;

-- -----------------------------------------------------------------------------
-- Funções recriadas (novos nomes, parametros.unico, valores garantidos)
-- -----------------------------------------------------------------------------

create or replace function mesmo_ponto_entrega(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select a = b or exists (
    select 1 from pontos_entrega la, pontos_entrega lb, parametros p
    where la.id = a and lb.id = b and p.unico
      and la.tipo = lb.tipo
      and distancia_m(la.lat, la.lng, lb.lat, lb.lng) <= p.raio_mesmo_local_m
  );
$$;

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
      from pedidos x
     where x.desconto_indicacao > 0 and x.estado = 'entregue_pago' and x.deletado_em is null
       and x.ponto_entrega_id is not null
       and mesmo_ponto_entrega(x.ponto_entrega_id, p_ponto);
    if usados >= p.max_descontos_por_local then
      return query select 0, 'limite_local'; return;
    end if;
  end if;

  -- Valor garantido no momento da ligação (não o parâmetro actual)
  return query select lig.desconto_garantido, 'ok';
end $$;

create or replace function meu_desconto_indicacao(p_ponto uuid)
returns table (valor int, motivo text)
language sql stable security definer set search_path = public as $$
  select * from avaliar_desconto_indicacao(cliente_actual(), p_ponto);
$$;

create or replace function calcular_desconto_indicacao() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  g pedidos_grupo;
begin
  if new.grupo_id is not null then
    g := grupo_para_adesao(new.grupo_id);
    new.ponto_entrega_id := g.ponto_entrega_id;
    new.cozinha_id := g.cozinha_id;
  end if;

  if new.cozinha_id is null then
    new.cozinha_id := cozinha_padrao();
  end if;

  -- O servidor ignora qualquer valor enviado pela app e recalcula
  select d.valor into new.desconto_indicacao
    from avaliar_desconto_indicacao(new.cliente_id, new.ponto_entrega_id) d;
  return new;
end $$;

create or replace function ligar_indicacao(p_codigo text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_cliente   uuid := cliente_actual();
  v_indicador uuid;
  v_ligacao   uuid;
begin
  if not funcionalidade_activa('indicacao') then return 'programa_inactivo'; end if;
  if v_cliente is null then return 'sem_sessao'; end if;

  select cliente_id into v_indicador
    from codigos_indicacao
   where codigo = upper(trim(p_codigo)) and deletado_em is null;
  if v_indicador is null then return 'codigo_inexistente'; end if;
  if v_indicador = v_cliente then return 'proprio_codigo'; end if;
  if exists (select 1 from ligacoes_indicacao where indicado_id = v_cliente) then
    return 'ja_ligado';
  end if;
  if cliente_ja_comprou(v_cliente) then return 'cliente_nao_novo'; end if;

  -- Os valores em vigor ficam garantidos para esta ligação
  insert into ligacoes_indicacao (indicado_id, indicador_id, dispositivo_id,
                                  ganho_por_pedido_garantido, desconto_garantido)
  select v_cliente, v_indicador, 'servidor', p.ganho_por_pedido, p.desconto_indicado
    from parametros p where p.unico
  returning id into v_ligacao;

  insert into notificacoes_fila (cliente_id, codigo, dados)
  select v_indicador, 'N2', jsonb_build_object('indicado_nome', split_part(trim(nome), ' ', 1))
    from clientes where id = v_cliente;

  perform registar_auditoria('indicacao_ligada', 'ligacoes_indicacao', v_ligacao,
                             jsonb_build_object('indicador_id', v_indicador, 'indicado_id', v_cliente));
  return 'ok';
end $$;

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

  -- 1.º pedido pago: arranca o período
  if lig.expira_em is null then
    update ligacoes_indicacao
       set primeiro_pedido_id = new.id,
           expira_em = coalesce(new.entregue_em, now()) + make_interval(days => p.duracao_dias),
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
      from ganhos_indicacao g2 join pedidos x on x.id = g2.pedido_id
     where g2.estado <> 'anulado'
       and g2.indicado_id <> new.cliente_id
       and x.ponto_entrega_id is not null
       and mesmo_ponto_entrega(x.ponto_entrega_id, new.ponto_entrega_id);
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

create or replace function pedir_levantamento(p_valor int, p_metodo text, p_numero text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  p         parametros;
  v_numero  text := normalizar_telefone(p_numero);
  v_lote    uuid := gen_random_uuid();
  v_p1      int;
begin
  if not funcionalidade_activa('indicacao') then
    raise exception 'programa_inactivo' using errcode = 'P0001';
  end if;
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if p_metodo is null or p_metodo not in ('multicaixa_express','unitel_money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if v_numero is null or length(v_numero) <> 9 then
    raise exception 'numero_invalido' using errcode = 'P0001';
  end if;

  select * into p from parametros where unico;
  -- Um pedido de cada vez por cliente (evita gastar o mesmo saldo duas vezes)
  perform pg_advisory_xact_lock(hashtext('saldo_indicacao:' || v_cliente::text));

  if p_valor is null or p_valor < p.levantamento_minimo then
    raise exception 'abaixo_minimo' using errcode = 'P0001';
  end if;
  if p_valor > saldo_disponivel_de(v_cliente) then
    raise exception 'saldo_insuficiente' using errcode = 'P0001';
  end if;

  if p_valor > p.limite_parcelamento then
    v_p1 := ceil(p_valor / 2.0);
    insert into pagamentos_indicacao
      (indicador_id, valor, tipo, metodo, numero_destino, lote_id, parcela, total_parcelas, dispositivo_id)
    values
      (v_cliente, v_p1,           'levantamento', p_metodo, v_numero, v_lote, 1, 2, 'servidor'),
      (v_cliente, p_valor - v_p1, 'levantamento', p_metodo, v_numero, v_lote, 2, 2, 'servidor');
  else
    insert into pagamentos_indicacao
      (indicador_id, valor, tipo, metodo, numero_destino, lote_id, dispositivo_id)
    values (v_cliente, p_valor, 'levantamento', p_metodo, v_numero, v_lote, 'servidor');
  end if;

  perform registar_auditoria('levantamento_pedido', 'pagamentos_indicacao', v_lote,
    jsonb_build_object('valor', p_valor, 'metodo', p_metodo));
  return v_lote;
end $$;

create or replace function pontos_entrega_proximos(p_lat float8, p_lng float8, p_tipo text)
returns table (ponto_entrega_id uuid, tipo text, referencia text, distancia_m float8)
language sql stable security definer set search_path = public as $$
  select l.id, l.tipo,
         case when l.tipo = 'empresa' then l.referencia end,
         round(distancia_m(l.lat, l.lng, p_lat, p_lng)::numeric, 1)::float8
    from pontos_entrega l, parametros p
   where p.unico and l.deletado_em is null and l.tipo = p_tipo
     and cliente_actual() is not null
     and abs(l.lat - p_lat) < 0.01 and abs(l.lng - p_lng) < 0.01
     and distancia_m(l.lat, l.lng, p_lat, p_lng) <= p.raio_mesmo_local_m
   order by 4
   limit 5;
$$;

create or replace function validar_endereco_cliente() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select tipo from clientes where id = new.cliente_id) = 'Empresa'
     and (select tipo from pontos_entrega where id = new.ponto_entrega_id) <> 'empresa' then
    raise exception 'empresa_requer_ponto_empresa' using errcode = 'P0001';
  end if;
  return new;
end $$;

create or replace function avaliacao_permitida(p_pedido uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select funcionalidade_activa('avaliacoes') and exists (
    select 1 from pedidos x, parametros p
     where p.unico and x.id = p_pedido and x.cliente_id = cliente_actual()
       and x.estado = 'entregue_pago' and x.deletado_em is null
       and x.entregue_em >= now() - make_interval(days => p.prazo_avaliacao_dias));
$$;

create or replace function destaques_mes()
returns table (posicao int, nome_exibido text, amigos int, valor int,
               valor_min int, valor_max int, sou_eu boolean)
language sql stable security definer set search_path = public as $$
  with r as materialized (select * from ranking_mes()),
       n as (select count(*) as total from r)
  select r.posicao, r.nome_exibido, r.amigos,
         case when n.total >= p.limiar_intervalos then r.valor end,
         case when n.total <  p.limiar_intervalos then (r.valor / p.tamanho_intervalo) * p.tamanho_intervalo end,
         case when n.total <  p.limiar_intervalos then (r.valor / p.tamanho_intervalo + 1) * p.tamanho_intervalo end,
         r.cliente_id = cliente_actual()
    from r, n, parametros p
   where p.unico and funcionalidade_activa('destaques')
     and r.posicao <= p.tamanho_top
   order by r.posicao;
$$;

create or replace function minha_posicao()
returns table (posicao int, nome_exibido text, amigos int, valor int,
               amigos_em_falta int, no_top boolean)
language sql stable security definer set search_path = public as $$
  with r as materialized (select * from ranking_mes()),
       eu as (select * from r where r.cliente_id = cliente_actual()),
       p as (select * from parametros where unico),
       ultimo as (select r.amigos from r, p where r.posicao = p.tamanho_top)
  select eu.posicao,
         coalesce(eu.nome_exibido, (select pseudonimo from perfil_destaques where cliente_id = cliente_actual())),
         coalesce(eu.amigos, 0), coalesce(eu.valor, 0),
         case when eu.posicao <= p.tamanho_top then 0
              else greatest(1, coalesce((select amigos from ultimo), 0) - coalesce(eu.amigos, 0) + 1) end,
         coalesce(eu.posicao <= p.tamanho_top, false)
    from p left join eu on true
   where cliente_actual() is not null and funcionalidade_activa('destaques');
$$;

create or replace function pessoas_como_tu()
returns table (nome_exibido text, amigos int, valor int)
language sql volatile security definer set search_path = public as $$
  with p as (select * from parametros where unico),
       cand as materialized (
         select r.nome_exibido, r.amigos, r.valor
           from ranking_mes() r, p
          where r.cliente_id is distinct from cliente_actual()
            and r.amigos between p.pessoas_como_tu_min and p.pessoas_como_tu_max
          order by random()
          limit 3)
  select * from cand
   where (select count(*) from cand) >= 2 and funcionalidade_activa('pessoas_como_tu');
$$;

create or replace function contador_zona(p_zona uuid) returns int
language sql stable security definer set search_path = public as $$
  select case when funcionalidade_activa('contadores_zona') and cz.total >= p.contador_minimo
              then cz.total end
    from parametros p
    left join contadores_zona cz on cz.zona_id = p_zona and cz.data = hoje_luanda()
   where p.unico;
$$;

create or replace function job_contadores_zona() returns void
language sql security definer set search_path = public as $$
  insert into contadores_zona (zona_id, data, total, dispositivo_id)
  select l.zona_id, hoje_luanda(), count(*)::int, 'servidor'
    from pedidos x join pontos_entrega l on l.id = x.ponto_entrega_id
   where x.estado = 'entregue_pago' and x.deletado_em is null
     and x.entregue_em >= inicio_dia_luanda() and l.zona_id is not null
   group by l.zona_id
  on conflict (zona_id, data) do update set total = excluded.total;
$$;

create or replace function job_n7_destaques() returns void
language sql security definer set search_path = public as $$
  with r as materialized (select * from ranking_mes()),
       p as (select * from parametros where unico),
       ultimo as (select coalesce((select r.amigos from r, p where r.posicao = p.tamanho_top), 0) as amigos)
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select r.cliente_id, 'N7',
         jsonb_build_object('nome_exibido', r.nome_exibido, 'posicao', r.posicao,
                            'amigos_em_falta', greatest(1, u.amigos - r.amigos + 1),
                            'tamanho_top', p.tamanho_top)
    from r, p, ultimo u, preferencias_notificacao pn
   where funcionalidade_activa('destaques')
     and pn.cliente_id = r.cliente_id and pn.destaques
     and r.posicao > p.tamanho_top
     and u.amigos - r.amigos + 1 <= 3;
$$;

create or replace function pedidos_antes_actualizar() returns trigger
language plpgsql as $$
begin
  if e_escrita_cliente() then
    -- O estado só muda no servidor (mudar_estado_pedido, cancelar_pedido)
    if new.estado is distinct from old.estado then
      raise exception 'estado_so_no_servidor' using errcode = '42501';
    end if;
    -- Campos que só o servidor escreve
    new.desconto_indicacao := old.desconto_indicacao;
    new.credito_indicacao_usado := old.credito_indicacao_usado;
    new.entregue_em := old.entregue_em;
    new.cliente_id := old.cliente_id;
    new.cozinha_id := old.cozinha_id;
    new.grupo_id := old.grupo_id;
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
      new.entregue_em := coalesce(new.entregue_em, now());
    end if;
  end if;
  return new;
end $$;

-- Membro da cozinha (tem turnos nela); usado em métricas e reconhecimentos
create or replace function membro_da_cozinha(p_cozinha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from turnos t
                  where t.cozinha_id = p_cozinha and t.deletado_em is null
                    and t.funcionario_id = funcionario_actual());
$$;

create or replace function metricas_turno(p_cozinha uuid, p_semana date)
returns table (periodo text, quebras int, quantidade_quebra numeric,
               entregas int, entregas_a_horas int, pct_a_horas numeric,
               diferenca_caixa numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (tem_permissao('equipa.reconhecer')
          or membro_da_cozinha(p_cozinha)) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return query
  with janelas as (
    select t.data, t.periodo,
           (t.data + min(t.hora_inicio)) at time zone 'Africa/Luanda' as ini,
           (t.data + max(t.hora_fim))    at time zone 'Africa/Luanda' as fim,
           array_agg(t.funcionario_id) as membros
      from turnos t
     where t.cozinha_id = p_cozinha and t.deletado_em is null and t.periodo is not null
       and t.data between p_semana and p_semana + 6
     group by t.data, t.periodo),
  q as (
    select j.periodo, count(d.id)::int as n, coalesce(sum(d.quantidade_quebra), 0) as qtd
      from janelas j
      left join distribuicoes d on d.cozinha_id = p_cozinha and d.deletado_em is null
       and d.quantidade_quebra > 0 and d.criado_em between j.ini and j.fim
     group by j.periodo),
  e as (
    select j.periodo, count(x.id)::int as n,
           count(x.id) filter (where x.entregue_em <= x.hora_prometida
                                 + make_interval(mins => (select tolerancia_entrega_min from parametros where unico)))::int as a_horas
      from janelas j
      left join pedidos x on x.cozinha_id = p_cozinha and x.deletado_em is null
       and x.estado = 'entregue_pago' and x.hora_prometida is not null
       and x.entregue_em between j.ini and j.fim
     group by j.periodo),
  c as (
    select j.periodo, coalesce(sum(abs((cx.fechamento ->> 'diferenca')::numeric)), 0) as dif
      from janelas j
      left join caixa cx on cx.cozinha_id = p_cozinha and cx.deletado_em is null
       and cx.data = j.data and cx.funcionario_id = any (j.membros)
       and cx.fechamento ? 'diferenca'
     group by j.periodo)
  select q.periodo, q.n, q.qtd, e.n, e.a_horas,
         case when e.n > 0 then round(100.0 * e.a_horas / e.n, 1) end,
         c.dif
    from q join e using (periodo) join c using (periodo)
   order by array_position(array['manha','tarde','noite'], q.periodo);
end $$;

drop policy ler on reconhecimentos_turno;
create policy ler on reconhecimentos_turno for select to authenticated
  using (tem_permissao('equipa.reconhecer') or membro_da_cozinha(cozinha_id));

-- -----------------------------------------------------------------------------
-- 1. Pedidos: estado só no servidor; venda gerada na entrega
-- -----------------------------------------------------------------------------
drop policy gerir on pedidos;
revoke update on pedidos from authenticated;
grant update (atualizado_em, hora_prometida, observacoes, deletado_em) on pedidos to authenticated;
create policy editar_operador on pedidos for update to authenticated
  using (tem_permissao('pedidos.gerir')) with check (tem_permissao('pedidos.gerir'));

create or replace function mudar_estado_pedido(p_pedido uuid, p_estado text, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_de text;
begin
  if not (tem_permissao('pedidos.gerir')
          or (p_estado in ('em_entrega','entregue_pago') and tem_permissao('entregas.registar'))) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  select estado into v_de from pedidos where id = p_pedido and deletado_em is null for update;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  update pedidos
     set estado = p_estado,
         motivo_cancelamento = case when p_estado = 'cancelado' then coalesce(p_motivo, motivo_cancelamento)
                                    else motivo_cancelamento end
   where id = p_pedido;
  perform registar_auditoria('pedido_estado', 'pedidos', p_pedido,
                             jsonb_build_object('de', v_de, 'para', p_estado, 'motivo', p_motivo));
end $$;

create or replace function marcar_pagador_distinto(p_pedido uuid, p_valor boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform exigir_permissao('entregas.registar');
  update pedidos set pagador_distinto = p_valor where id = p_pedido and deletado_em is null;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  perform registar_auditoria('pedido_pagador_distinto', 'pedidos', p_pedido,
                             jsonb_build_object('pagador_distinto', p_valor));
end $$;

-- Venda gerada a partir do pedido (vendas é append-only):
--   entregue_pago -> venda 'App cliente'; estornado -> venda 'App cliente (estorno)'
--   com valores negativos. Uma de cada por pedido.
--   valor_total = subtotal + taxa − desconto de indicação; o crédito de indicação
--   é uma forma de pagamento e entra em parcelas ('Crédito indicação').
create unique index vendas_pedido_origem_key on vendas (pedido_id, origem) where pedido_id is not null;

create or replace function gerar_venda_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_sinal    int;
  v_zona     zonas;
  v_parcelas jsonb;
  v_venda    uuid;
begin
  if new.estado = 'entregue_pago' and old.estado is distinct from 'entregue_pago' then
    v_sinal := 1;
  elsif new.estado = 'estornado' and old.estado = 'entregue_pago' then
    v_sinal := -1;
  else
    return new;
  end if;

  select z.* into v_zona
    from pontos_entrega pe join zonas z on z.id = pe.zona_id
   where pe.id = new.ponto_entrega_id;
  if not found then
    select * into v_zona from zonas where id = new.zona_id;
  end if;

  v_parcelas := new.parcelas
    || case when new.credito_indicacao_usado > 0
            then jsonb_build_array(jsonb_build_object('metodo', 'Crédito indicação',
                                                      'valor', new.credito_indicacao_usado,
                                                      'cliente_id', new.cliente_id))
            else '[]'::jsonb end;

  insert into vendas (dispositivo_id, sincronizado_em, data, cozinha_id, pedido_id, origem, cliente_id,
                      produto, qtd, prato_base_id, valor_antes_desconto, desconto_aplicado, valor_total,
                      taxa_entrega, parcelas, credito, entrega, zona_nome, tipo_entrega, registado_por)
  values ('servidor', now(), now(), new.cozinha_id, new.id,
          case when v_sinal = 1 then 'App cliente' else 'App cliente (estorno)' end,
          new.cliente_id,
          (select string_agg(coalesce(i ->> 'qtd', '1') || 'x ' || coalesce(i ->> 'nome', 'prato'), ', ')
             from jsonb_array_elements(new.itens) i),
          v_sinal * (select coalesce(sum(coalesce((i ->> 'qtd')::numeric, 1)), 0)
                       from jsonb_array_elements(new.itens) i),
          case when jsonb_array_length(new.itens) = 1 then (new.itens -> 0 ->> 'prato_base_id')::uuid end,
          v_sinal * (new.subtotal + new.taxa_entrega),
          v_sinal * new.desconto_indicacao,
          v_sinal * (new.subtotal + new.taxa_entrega - new.desconto_indicacao),
          v_sinal * new.taxa_entrega,
          v_parcelas, false, true, v_zona.nome, v_zona.tipo, funcionario_actual())
  on conflict (pedido_id, origem) where pedido_id is not null do nothing
  returning id into v_venda;

  if v_venda is not null then
    perform registar_auditoria('venda_gerada', 'vendas', v_venda,
                               jsonb_build_object('pedido_id', new.id, 'sinal', v_sinal));
  end if;
  return new;
end $$;

create trigger trg_gerar_venda_pedido
after update of estado on pedidos
for each row execute function gerar_venda_pedido();

-- -----------------------------------------------------------------------------
-- 3. Estratégia de conflito de cada tabela nova
-- -----------------------------------------------------------------------------
comment on table parametros               is 'Sincronização: só servidor (alterar_parametros). Telemóvel só lê.';
comment on table funcionalidades          is 'Sincronização: só servidor (alterar_funcionalidade). Telemóvel só lê.';
comment on table cozinhas                 is 'Sincronização: last-write-wins; escrita só com cozinhas.gerir.';
comment on table pontos_entrega           is 'Sincronização: last-write-wins por atualizado_em (escritas antigas ignoradas).';
comment on table enderecos_cliente        is 'Sincronização: last-write-wins por atualizado_em.';
comment on table pedidos                  is 'Sincronização: criação pelo dispositivo (estado pendente); estado e campos de valor só no servidor.';
comment on table codigos_indicacao        is 'Sincronização: só servidor. Telemóvel só lê.';
comment on table ligacoes_indicacao       is 'Sincronização: só servidor (ligar_indicacao). Telemóvel só lê.';
comment on table ganhos_indicacao         is 'Sincronização: só servidor. Telemóvel só lê.';
comment on table pagamentos_indicacao     is 'Sincronização: só servidor (pedir_levantamento, usar_credito, marcar_pago). Telemóvel só lê.';
comment on table perfil_destaques         is 'Sincronização: last-write-wins em mostrar_nome_real e sair_da_lista.';
comment on table preferencias_notificacao is 'Sincronização: last-write-wins por atualizado_em.';
comment on table avaliacoes               is 'Sincronização: append-only; moderação só por funções.';
comment on table avaliacoes_pratos        is 'Sincronização: append-only.';
comment on table fotos_avaliacao          is 'Sincronização: append-only; moderação só por funções.';
comment on table palavras_filtradas       is 'Sincronização: last-write-wins; só moderadores.';
comment on table reconhecimentos_turno    is 'Sincronização: append-only.';
comment on table pedidos_grupo            is 'Sincronização: append-only na criação; last-write-wins no estado (organizador ou operador).';
comment on table notificacoes_fila        is 'Sincronização: não sincroniza; só servidor.';
comment on table contadores_zona          is 'Sincronização: não sincroniza; só servidor (contador_zona()).';

-- -----------------------------------------------------------------------------
-- Execução de funções
-- -----------------------------------------------------------------------------
revoke execute on function avaliar_desconto_indicacao(uuid, uuid) from public, anon, authenticated;
revoke execute on function membro_da_cozinha(uuid) from public, anon;
grant  execute on function membro_da_cozinha(uuid) to authenticated;
do $$
declare
  f text;
begin
  foreach f in array array[
    'mesmo_ponto_entrega(uuid,uuid)', 'meu_desconto_indicacao(uuid)',
    'pontos_entrega_proximos(float8,float8,text)', 'alterar_parametros(jsonb)',
    'alterar_funcionalidade(text,boolean)', 'mudar_estado_pedido(uuid,text,text)',
    'marcar_pagador_distinto(uuid,boolean)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- Garantia final: todos os interruptores desligados
update funcionalidades set activa = false where activa;
