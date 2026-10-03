-- Gerente de turno (Claude com ferramentas). Nas horas de serviço, de 5 em 5 minutos, o agente olha para cada
-- cozinha com pedidos em curso (fila, atrasos, estafetas, cancelamentos e reclamações do dia) e PROPÕE acções
-- ao gerente: avisar o cliente de um atraso (com o motivo escrito), confirmar um pedido parado, pausar um prato,
-- pedir reforço de estafetas ou deixar uma nota. Nada acontece sem o gerente: ao aceitar, a acção corre com as
-- permissões dele (informar_atraso, mudar_estado_pedido, pausa do prato). As propostas caducam em 30 minutos.
-- Interruptor: funcionalidade agente_turno (desligada até ser testada).

insert into funcionalidades (chave, activa, dispositivo_id) values ('agente_turno', false, 'servidor')
on conflict (chave) do nothing;

alter table parametros
  add column turno_hora_inicio integer not null default 9 check (turno_hora_inicio between 0 and 23),
  add column turno_hora_fim integer not null default 23 check (turno_hora_fim between 1 and 24);
comment on column parametros.turno_hora_inicio is 'Hora de Luanda a partir da qual o gerente de turno trabalha';
comment on column parametros.turno_hora_fim is 'Hora de Luanda até à qual o gerente de turno trabalha';

create table propostas_turno (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cozinha_id       uuid not null references cozinhas(id),
  tipo             text not null check (tipo in ('avisar_atraso', 'confirmar', 'pausar_prato', 'reforco', 'nota')),
  pedido_id        uuid references pedidos(id),
  cardapio_id      uuid references cardapio(id),
  prioridade       text not null default 'media' check (prioridade in ('alta', 'media', 'baixa')),
  explicacao       text not null check (char_length(explicacao) <= 500),
  motivo_cliente   text check (char_length(motivo_cliente) <= 200),
  mais_minutos     integer check (mais_minutos between 1 and 240),
  estado           text not null default 'pendente' check (estado in ('pendente', 'aceite', 'recusada', 'expirada')),
  expira_em        timestamptz not null default now() + interval '30 minutes',
  decidido_por     uuid references funcionarios(id),
  decidido_em      timestamptz,
  erro             text
);
create unique index propostas_turno_pedido_key on propostas_turno (tipo, pedido_id) where estado = 'pendente' and pedido_id is not null;
create unique index propostas_turno_prato_key on propostas_turno (tipo, cardapio_id) where estado = 'pendente' and cardapio_id is not null;
create index propostas_turno_cozinha_idx on propostas_turno (cozinha_id, criado_em);
create index propostas_turno_pedido_idx on propostas_turno (pedido_id);
create index propostas_turno_cardapio_idx on propostas_turno (cardapio_id);
create index propostas_turno_decidido_por_idx on propostas_turno (decidido_por);
create trigger trg_0_so_servidor before insert or update or delete on propostas_turno
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on propostas_turno
for each row execute function sync_receber();
alter table propostas_turno enable row level security;
revoke all on propostas_turno from anon;
revoke insert, update, delete, truncate on propostas_turno from authenticated;
grant select on propostas_turno to authenticated;
create policy ler on propostas_turno for select to authenticated
  using (deletado_em is null and pode_na_cozinha('pedidos.gerir', cozinha_id));
comment on table propostas_turno is 'Sincronização: só servidor (propostas do gerente de turno). Telemóvel só lê.';

-- Quando o agente olhou para cada cozinha pela última vez
create table turno_analises (
  cozinha_id uuid primary key references cozinhas(id) on delete cascade,
  ultima_em  timestamptz not null default now()
);
alter table turno_analises enable row level security;
revoke all on turno_analises from anon, authenticated;
comment on table turno_analises is 'Só servidor: última vez que o gerente de turno analisou cada cozinha.';

-- ---------------------------------------------------------------- ferramentas (só leitura, só o serviço)
-- Permissão de um funcionário qualquer (o tem_permissao é para quem está na sessão)
create or replace function tem_permissao_de(p_func uuid, p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case
             when f.administrador_principal then true
             when f.permissoes_extra ? p then coalesce((f.permissoes_extra ->> p)::boolean, false)
             else coalesce((d.permissoes ->> p)::boolean, false)
           end
      from funcionarios f
      left join direcoes d on d.id = f.direcao_id and d.deletado_em is null
     where f.id = p_func and f.deletado_em is null), false);
$$;
revoke execute on function tem_permissao_de(uuid, text) from public, anon, authenticated;

-- A situação de uma cozinha agora (sem nomes nem contactos de clientes)
create or replace function situacao_turno(p_cozinha uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with par as (select alerta_atraso_min, alerta_confirmacao_min from parametros where unico),
  x as (select p.* from pedidos p where p.cozinha_id = p_cozinha and p.deletado_em is null and p.grupo_id is null
         and p.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')),
  hoje as (select p.* from pedidos p where p.cozinha_id = p_cozinha and p.deletado_em is null
            and (p.criado_em at time zone 'Africa/Luanda')::date = (now() at time zone 'Africa/Luanda')::date)
  select jsonb_build_object(
    'agora', to_char(now() at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'),
    'cozinha', (select trim(nome) from cozinhas where id = p_cozinha),
    'limites', (select jsonb_build_object('minutos_para_confirmar', alerta_confirmacao_min, 'tolerancia_atraso_min', alerta_atraso_min) from par),
    'pedidos_em_curso', coalesce((select jsonb_agg(jsonb_build_object(
        'pedido_id', x.id, 'estado', x.estado,
        'minutos_desde_o_pedido', floor(extract(epoch from now() - x.criado_em) / 60)::int,
        'minutos_ate_a_hora_prometida', case when x.hora_prometida is not null
                                             then floor(extract(epoch from x.hora_prometida - now()) / 60)::int end,
        'itens', (select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || coalesce(i ->> 'nome', 'Prato'), ', ') from jsonb_array_elements(x.itens) i),
        'zona', (select nome from zonas where id = x.zona_id),
        'estafeta', (select nome from funcionarios where id = x.entregador_id),
        'alerta_atraso', (select jsonb_build_object('minutos', a.minutos, 'motivo_ja_dado', a.motivo) from alertas_pedido a
                           where a.pedido_id = x.id and a.tipo = 'atraso' and a.deletado_em is null),
        'cliente_ja_reclamou', exists (select 1 from reclamacoes r where r.pedido_id = x.id))
      order by x.criado_em) from x), '[]'),
    'estafetas_de_turno', coalesce((select jsonb_agg(jsonb_build_object(
        'nome', f.nome,
        'pedidos_a_levar', (select count(*) from x where x.entregador_id = f.id and x.estado = 'em_entrega'),
        'ultima_posicao_ha_min', (select floor(extract(epoch from now() - max(pe.criado_em)) / 60)::int
                                    from posicoes_entregadores pe where pe.funcionario_id = f.id)))
      from turnos t join funcionarios f on f.id = t.funcionario_id
     where t.cozinha_id = p_cozinha and t.deletado_em is null and t.data = (now() at time zone 'Africa/Luanda')::date
       and (tem_permissao_de(f.id, 'entregas.registar'))), '[]'),
    'hoje', jsonb_build_object(
      'pedidos', (select count(*) from hoje),
      'entregues', (select count(*) from hoje where estado = 'entregue_pago'),
      'cancelados', (select count(*) from hoje where estado = 'cancelado'),
      'pedidos_ultima_hora', (select count(*) from hoje where criado_em > now() - interval '1 hour'),
      'reclamacoes', (select count(*) from reclamacoes r where r.cozinha_id = p_cozinha
                        and (r.criado_em at time zone 'Africa/Luanda')::date = (now() at time zone 'Africa/Luanda')::date)),
    'pratos_disponiveis', coalesce((select jsonb_agg(jsonb_build_object('cardapio_id', c.id, 'nome', c.nome, 'do_dia', c.do_dia,
                                     'vendidos_hoje', (select coalesce(sum(coalesce((i ->> 'qtd')::int, 1)), 0) from hoje h, jsonb_array_elements(h.itens) i
                                                        where i ->> 'cardapio_id' = c.id::text and h.estado <> 'cancelado'),
                                     'cancelados_hoje', (select count(*) from hoje h, jsonb_array_elements(h.itens) i
                                                          where i ->> 'cardapio_id' = c.id::text and h.estado = 'cancelado'))
                                     order by c.ordem)
                                     from cardapio c where c.cozinha_id = p_cozinha and c.disponivel and c.deletado_em is null), '[]'),
    'propostas_pendentes', coalesce((select jsonb_agg(jsonb_build_object('tipo', tipo, 'pedido_id', pedido_id, 'cardapio_id', cardapio_id))
                                       from propostas_turno where cozinha_id = p_cozinha and estado = 'pendente' and expira_em > now()), '[]'));
$$;

-- Há alguma coisa que mereça a atenção do gerente? (só então se chama o Claude, para poupar)
create or replace function turno_precisa_atencao(p_cozinha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  with par as (select alerta_confirmacao_min from parametros where unico),
  x as (select p.* from pedidos p where p.cozinha_id = p_cozinha and p.deletado_em is null and p.grupo_id is null
         and p.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega'))
  select
    -- pedido por confirmar perto do limite
    exists (select 1 from x, par where x.estado = 'pendente'
              and x.criado_em < now() - make_interval(secs => par.alerta_confirmacao_min * 60 * 0.7))
    -- atraso sem motivo dado ao cliente
    or exists (select 1 from x join alertas_pedido a on a.pedido_id = x.id and a.tipo = 'atraso' and a.motivo is null)
    -- pedido que vai passar da hora prometida nos próximos 10 minutos e ainda não saiu
    or exists (select 1 from x where x.estado in ('pendente', 'confirmado', 'em_preparacao')
                 and x.hora_prometida is not null and x.hora_prometida < now() + interval '10 minutes')
    -- cancelamentos hoje
    or (select count(*) from pedidos p where p.cozinha_id = p_cozinha and p.estado = 'cancelado' and p.deletado_em is null
          and (p.criado_em at time zone 'Africa/Luanda')::date = (now() at time zone 'Africa/Luanda')::date
          and p.atualizado_em > now() - interval '1 hour') >= 2
    -- fila grande para os estafetas que há
    or (select count(*) from x where x.estado in ('confirmado', 'em_preparacao'))
       > 3 * greatest(1, (select count(*) from turnos t where t.cozinha_id = p_cozinha and t.deletado_em is null
                            and t.data = (now() at time zone 'Africa/Luanda')::date
                            and tem_permissao_de(t.funcionario_id, 'entregas.registar')));
$$;
revoke execute on function turno_precisa_atencao(uuid) from public, anon, authenticated;

-- Escolhe a próxima cozinha a analisar (com algo a pedir atenção, não vista nos últimos 5 minutos, nas horas de serviço)
create or replace function reservar_turno() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  par parametros;
  v_hora int := extract(hour from now() at time zone 'Africa/Luanda');
  v_coz uuid;
begin
  if not funcionalidade_activa('agente_turno') then return null; end if;
  select * into par from parametros where unico;
  if v_hora < par.turno_hora_inicio or v_hora >= par.turno_hora_fim then return null; end if;
  -- caducam as propostas antigas
  update propostas_turno set estado = 'expirada', atualizado_em = now() where estado = 'pendente' and expira_em <= now();
  select c.id into v_coz from cozinhas c
    left join turno_analises t on t.cozinha_id = c.id
   where c.deletado_em is null
     and (t.ultima_em is null or t.ultima_em < now() - interval '5 minutes')
     and turno_precisa_atencao(c.id)
   order by t.ultima_em nulls first
   limit 1;
  if v_coz is null then return null; end if;
  insert into turno_analises (cozinha_id, ultima_em) values (v_coz, now())
  on conflict (cozinha_id) do update set ultima_em = now();
  return jsonb_build_object('cozinha_id', v_coz, 'situacao', situacao_turno(v_coz));
end $$;

-- Guarda as propostas do agente (valida cada uma; não repete o que já está pendente) e avisa os gerentes (N27)
create or replace function registar_propostas_turno(p_cozinha uuid, p_propostas jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  p jsonb;
  n int := 0;
  v_ok boolean;
begin
  for p in select * from jsonb_array_elements(coalesce(p_propostas, '[]')) loop
    v_ok := case p ->> 'tipo'
      when 'avisar_atraso' then exists (select 1 from pedidos x where x.id::text = p ->> 'pedido_id' and x.cozinha_id = p_cozinha
                                          and x.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega'))
                                and nullif(trim(p ->> 'motivo_cliente'), '') is not null
      when 'confirmar' then exists (select 1 from pedidos x where x.id::text = p ->> 'pedido_id' and x.cozinha_id = p_cozinha and x.estado = 'pendente')
      when 'pausar_prato' then exists (select 1 from cardapio c where c.id::text = p ->> 'cardapio_id' and c.cozinha_id = p_cozinha and c.disponivel)
      when 'reforco' then true
      when 'nota' then true
      else false end;
    continue when not v_ok or nullif(trim(p ->> 'explicacao'), '') is null;
    insert into propostas_turno (dispositivo_id, sincronizado_em, cozinha_id, tipo, pedido_id, cardapio_id, prioridade,
                                 explicacao, motivo_cliente, mais_minutos)
    values ('servidor', now(), p_cozinha, p ->> 'tipo',
            case when p ->> 'tipo' in ('avisar_atraso', 'confirmar') then (p ->> 'pedido_id')::uuid end,
            case when p ->> 'tipo' = 'pausar_prato' then (p ->> 'cardapio_id')::uuid end,
            case when p ->> 'prioridade' in ('alta', 'media', 'baixa') then p ->> 'prioridade' else 'media' end,
            left(trim(p ->> 'explicacao'), 500),
            case when p ->> 'tipo' = 'avisar_atraso' then left(trim(p ->> 'motivo_cliente'), 200) end,
            case when p ->> 'tipo' = 'avisar_atraso' and (p ->> 'mais_minutos') ~ '^\d+$'
                 then least(greatest((p ->> 'mais_minutos')::int, 1), 240) end)
    on conflict do nothing;
    if found then n := n + 1; end if;
  end loop;
  if n > 0 then
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select g, 'N27', jsonb_build_object('cozinha_id', p_cozinha, 'propostas', n,
                                        'cozinha', (select trim(nome) from cozinhas where id = p_cozinha))
      from gerentes_do_pedido(p_cozinha) g;
  end if;
  return n;
end $$;

-- ---------------------------------------------------------------- pela app (gerente)
create or replace function propostas_turno_lista() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('pedidos.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'cozinha', trim(c.nome), 'tipo', p.tipo, 'pedido_id', p.pedido_id, 'prato', ca.nome,
             'prioridade', p.prioridade, 'explicacao', p.explicacao, 'motivo_cliente', p.motivo_cliente,
             'mais_minutos', p.mais_minutos, 'estado', case when p.estado = 'pendente' and p.expira_em <= now() then 'expirada' else p.estado end,
             'criado_em', p.criado_em, 'expira_em', p.expira_em, 'decidido_por', d.nome, 'decidido_em', p.decidido_em, 'erro', p.erro,
             'cliente', (select split_part(trim(cl.nome), ' ', 1) from pedidos x join clientes cl on cl.id = x.cliente_id where x.id = p.pedido_id))
           order by (p.estado = 'pendente' and p.expira_em > now()) desc,
                    case p.prioridade when 'alta' then 0 when 'media' then 1 else 2 end, p.criado_em desc)
      from propostas_turno p join cozinhas c on c.id = p.cozinha_id
      left join cardapio ca on ca.id = p.cardapio_id
      left join funcionarios d on d.id = p.decidido_por
     where p.deletado_em is null and pode_na_cozinha('pedidos.gerir', p.cozinha_id)
       and p.criado_em > now() - interval '12 hours'), '[]');
end $$;
revoke execute on function propostas_turno_lista() from public, anon;
grant execute on function propostas_turno_lista() to authenticated;

-- O gerente aceita (a acção corre com as permissões dele) ou recusa
create or replace function decidir_proposta_turno(p_id uuid, p_aceitar boolean, p_motivo text default null,
                                                  p_mais_minutos int default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  p propostas_turno;
  v_cozinha uuid;
begin
  select * into p from propostas_turno where id = p_id and deletado_em is null for update;
  if not found then raise exception 'proposta_inexistente' using errcode = 'P0001'; end if;
  if not coalesce(pode_na_cozinha('pedidos.gerir', p.cozinha_id), false) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p.estado <> 'pendente' or p.expira_em <= now() then raise exception 'proposta_expirada' using errcode = 'P0001'; end if;
  if p_aceitar then
    if p.tipo = 'avisar_atraso' then
      perform informar_atraso(p.pedido_id, coalesce(nullif(trim(p_motivo), ''), p.motivo_cliente), coalesce(p_mais_minutos, p.mais_minutos));
    elsif p.tipo = 'confirmar' then
      perform mudar_estado_pedido(p.pedido_id, 'confirmado', null, null, null);
    elsif p.tipo = 'pausar_prato' then
      select cozinha_id into v_cozinha from cardapio where id = p.cardapio_id;
      update cardapio set disponivel = false, atualizado_em = now() where id = p.cardapio_id and cozinha_id = p.cozinha_id;
      perform registar_auditoria('prato_pausado', 'cardapio', p.cardapio_id, jsonb_build_object('proposta_id', p.id));
    end if;
  end if;
  update propostas_turno
     set estado = case when p_aceitar then 'aceite' else 'recusada' end,
         decidido_por = funcionario_actual(), decidido_em = now(), atualizado_em = now()
   where id = p.id;
  perform registar_auditoria(case when p_aceitar then 'proposta_turno_aceite' else 'proposta_turno_recusada' end,
    'propostas_turno', p.id, jsonb_build_object('tipo', p.tipo, 'pedido_id', p.pedido_id, 'cardapio_id', p.cardapio_id));
  return case when p_aceitar then 'aceite' else 'recusada' end;
end $$;
revoke execute on function decidir_proposta_turno(uuid, boolean, text, int) from public, anon;
grant execute on function decidir_proposta_turno(uuid, boolean, text, int) to authenticated;

create or replace function agendar_turno(p_url text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format($f$select cron.schedule('turno', '*/5 * * * *', %L)$f$,
    format('select net.http_post(url := %L, body := ''{}''::jsonb, timeout_milliseconds := 150000, headers := jsonb_build_object('
           '''Content-Type'', ''application/json'', ''x-envio-segredo'', '
           '(select valor from public.segredos_servidor where chave = ''envio_notificacoes'')))', p_url));
  return 'agendado';
end $$;

do $$
declare f text;
begin
  foreach f in array array['situacao_turno(uuid)', 'reservar_turno()', 'registar_propostas_turno(uuid, jsonb)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
revoke execute on function agendar_turno(text) from public, anon, authenticated;
