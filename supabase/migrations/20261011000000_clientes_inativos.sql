-- Reconquista de clientes inativos (Fase 1).
-- Lista quem comprou antes e parou, e permite enviar um aviso de regresso (reusa N31), com:
--   * escalões por recência (a arrefecer 30-59, frio 60-89, adormecido 90+ dias sem comprar);
--   * grupo de controlo aleatório (não recebe) para medir o efeito real da campanha;
--   * exclusão de quem já foi contactado há pouco (não "treinar" o cliente a desaparecer).
-- Enquadramento: B. F. Skinner (reforço variável, time-boxed, excluir reincidentes, medir o reforço
-- real com controlo) + Albert Bandura (a mensagem, no ecrã, reconstrói autoeficácia e pertença).
-- "Comprou" = pedido entregue_pago; recência pela data de Luanda (fuso do negócio).

-- 1. Permissão (entra no catálogo do ecrã Pessoal automaticamente)
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'clientes.reconquista', 'Clientes',
   'Ver clientes inativos (lista e telefones) e enviar campanhas de regresso')
on conflict (chave) do nothing;

-- 2. Parâmetros configuráveis
alter table parametros
  add column reconquista_excluir_dias integer not null default 45
    check (reconquista_excluir_dias between 0 and 365),
  add column reconquista_controlo_pct integer not null default 15
    check (reconquista_controlo_pct between 0 and 50);
comment on column parametros.reconquista_excluir_dias is
  'Dias em que um cliente que já recebeu uma campanha de regresso não volta a ser contactado';
comment on column parametros.reconquista_controlo_pct is
  'Percentagem do grupo-alvo que fica de fora (controlo) para medir o efeito da campanha';

-- 3. Histórico de campanhas e os seus alvos (só servidor; o operador lê por RPC)
create table campanhas_reconquista (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  criado_por      uuid references funcionarios(id),
  criado_por_nome text,
  dias_min        integer not null,
  dias_max        integer,
  zona_id         uuid references zonas(id),
  titulo          text,
  corpo           text not null,
  link            text,
  controlo_pct    integer not null default 0,
  total_elegiveis integer not null default 0,
  total_enviados  integer not null default 0,
  total_controlo  integer not null default 0
);
create index campanhas_reconquista_criado_por_idx on campanhas_reconquista (criado_por);
create index campanhas_reconquista_zona_idx       on campanhas_reconquista (zona_id);
alter table campanhas_reconquista enable row level security;
revoke all on campanhas_reconquista from anon, authenticated;

create table campanha_reconquista_alvos (
  campanha_id  uuid not null references campanhas_reconquista(id) on delete cascade,
  cliente_id   uuid not null references clientes(id),
  grupo        text not null check (grupo in ('enviado', 'controlo')),
  alcancavel   boolean not null default false,  -- tinha dispositivo com push activo no envio
  dias_inativo integer not null,
  primary key (campanha_id, cliente_id)
);
create index campanha_reconquista_alvos_cliente_idx on campanha_reconquista_alvos (cliente_id);
alter table campanha_reconquista_alvos enable row level security;
revoke all on campanha_reconquista_alvos from anon, authenticated;

-- 4. Lista de clientes inativos (comprou e parou), para o escalão pedido
create or replace function clientes_inativos(p_dias_min int default 30, p_dias_max int default null,
                                             p_zona uuid default null)
returns table (cliente_id uuid, nome text, telefone text, ultimo_pedido date,
               dias_inativo int, total_pedidos int, tem_push boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('clientes.reconquista');
  return query
    with compras as (
      select p.cliente_id,
             max((p.entregue_em at time zone 'Africa/Luanda')::date) as ultimo,
             count(*)::int as n
        from pedidos p
       where p.deletado_em is null and p.estado = 'entregue_pago'
         and (p_zona is null or p.zona_id = p_zona)
       group by p.cliente_id)
    select c.id, c.nome, c.telefone, x.ultimo,
           ((now() at time zone 'Africa/Luanda')::date - x.ultimo) as dias,
           x.n,
           exists (select 1 from dispositivos_push d
                    where d.cliente_id = c.id and d.activo and d.deletado_em is null)
      from compras x
      join clientes c on c.id = x.cliente_id
     where c.deletado_em is null
       and ((now() at time zone 'Africa/Luanda')::date - x.ultimo) >= p_dias_min
       and (p_dias_max is null or ((now() at time zone 'Africa/Luanda')::date - x.ultimo) <= p_dias_max)
     order by ((now() at time zone 'Africa/Luanda')::date - x.ultimo) desc, c.nome;
end $$;

-- 5. Resumo por escalão (para os cartões do ecrã)
create or replace function clientes_inativos_resumo()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('clientes.reconquista');
  return (
    with base as (
      select c.id,
             ((now() at time zone 'Africa/Luanda')::date
               - max((p.entregue_em at time zone 'Africa/Luanda')::date)) as dias,
             exists (select 1 from dispositivos_push d
                      where d.cliente_id = c.id and d.activo and d.deletado_em is null) as push
        from clientes c
        join pedidos p on p.cliente_id = c.id
       where c.deletado_em is null and p.deletado_em is null and p.estado = 'entregue_pago'
       group by c.id)
    select jsonb_build_object(
      'a_arrefecer', jsonb_build_object(
          'total',    count(*) filter (where dias between 30 and 59),
          'com_push', count(*) filter (where dias between 30 and 59 and push)),
      'frio', jsonb_build_object(
          'total',    count(*) filter (where dias between 60 and 89),
          'com_push', count(*) filter (where dias between 60 and 89 and push)),
      'adormecido', jsonb_build_object(
          'total',    count(*) filter (where dias >= 90),
          'com_push', count(*) filter (where dias >= 90 and push)),
      'activos_ate_30', count(*) filter (where dias < 30))
    from base);
end $$;

-- 6. Enviar campanha: separa controlo, enfileira N31 aos alcançáveis, grava tudo. Devolve os totais.
create or replace function enviar_campanha_reconquista(
    p_dias_min int, p_dias_max int default null, p_zona uuid default null,
    p_titulo text default null, p_corpo text default null, p_link text default null,
    p_controlo_pct int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id      uuid;
  v_ctrl    int;
  v_excluir int;
  v_dados   jsonb;
  v_envpush int;
begin
  perform exigir_permissao('clientes.reconquista');
  if length(btrim(coalesce(p_corpo, ''))) = 0 then
    raise exception 'corpo_vazio' using errcode = '22023';
  end if;

  select reconquista_excluir_dias, coalesce(p_controlo_pct, reconquista_controlo_pct)
    into v_excluir, v_ctrl
    from parametros where unico;
  v_ctrl := greatest(0, least(50, coalesce(v_ctrl, 0)));

  v_dados := jsonb_strip_nulls(jsonb_build_object(
               'titulo', nullif(btrim(coalesce(p_titulo, '')), ''),
               'corpo',  btrim(p_corpo),
               'link',   nullif(btrim(coalesce(p_link, '')), '')));

  insert into campanhas_reconquista (criado_por, criado_por_nome, dias_min, dias_max, zona_id,
                                     titulo, corpo, link, controlo_pct)
  values (funcionario_actual(), (select nome from funcionarios where id = funcionario_actual()),
          p_dias_min, p_dias_max, p_zona,
          nullif(btrim(coalesce(p_titulo, '')), ''), btrim(p_corpo),
          nullif(btrim(coalesce(p_link, '')), ''), v_ctrl)
  returning id into v_id;

  -- Elegíveis = inativos do escalão menos quem já foi contactado há < v_excluir dias; controlo ao acaso.
  insert into campanha_reconquista_alvos (campanha_id, cliente_id, grupo, alcancavel, dias_inativo)
  with elegiveis as (
    select ci.cliente_id, ci.dias_inativo, ci.tem_push
      from clientes_inativos(p_dias_min, p_dias_max, p_zona) ci
     where not exists (
        select 1 from campanha_reconquista_alvos a
          join campanhas_reconquista k on k.id = a.campanha_id
         where a.cliente_id = ci.cliente_id and k.id <> v_id
           and k.criado_em > now() - make_interval(days => v_excluir))),
  numerado as (
    select e.*, row_number() over (order by random()) as rn, count(*) over () as tot
      from elegiveis e)
  select v_id, cliente_id,
         case when rn <= floor(tot * v_ctrl / 100.0) then 'controlo' else 'enviado' end,
         tem_push, dias_inativo
    from numerado;

  -- Enfileira só aos do grupo "enviado" com push activo (os outros ficam na lista para telefonar)
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select a.cliente_id, 'N31', v_dados
    from campanha_reconquista_alvos a
   where a.campanha_id = v_id and a.grupo = 'enviado' and a.alcancavel;
  get diagnostics v_envpush = row_count;

  update campanhas_reconquista c set
    total_elegiveis = (select count(*) from campanha_reconquista_alvos where campanha_id = v_id),
    total_enviados  = (select count(*) from campanha_reconquista_alvos where campanha_id = v_id and grupo = 'enviado'),
    total_controlo  = (select count(*) from campanha_reconquista_alvos where campanha_id = v_id and grupo = 'controlo')
   where c.id = v_id;

  perform registar_auditoria('campanha_reconquista', 'campanha', v_id,
            jsonb_build_object('dias_min', p_dias_min, 'dias_max', p_dias_max,
                               'controlo_pct', v_ctrl, 'enviados_push', v_envpush));

  return (select jsonb_build_object(
            'campanha_id', v_id, 'elegiveis', total_elegiveis,
            'enviados', total_enviados, 'controlo', total_controlo, 'enviados_push', v_envpush)
          from campanhas_reconquista where id = v_id);
end $$;

-- 7. Resultado de uma campanha: quem voltou a comprar nos 14 dias seguintes (enviados vs controlo)
create or replace function campanha_reconquista_resultado(p_campanha uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ini timestamptz;
begin
  perform exigir_permissao('clientes.reconquista');
  select criado_em into v_ini from campanhas_reconquista where id = p_campanha;
  if v_ini is null then raise exception 'campanha_inexistente' using errcode = 'P0001'; end if;
  return (
    with alvo as (select a.cliente_id, a.grupo from campanha_reconquista_alvos a where a.campanha_id = p_campanha),
    voltas as (
      select distinct a.cliente_id, a.grupo
        from alvo a
        join pedidos p on p.cliente_id = a.cliente_id
       where p.deletado_em is null and p.estado = 'entregue_pago'
         and p.entregue_em >= v_ini and p.entregue_em < v_ini + interval '14 days')
    select jsonb_build_object(
      'janela_dias', 14,
      'enviados',          (select count(*) from alvo   where grupo = 'enviado'),
      'enviados_voltaram', (select count(*) from voltas where grupo = 'enviado'),
      'controlo',          (select count(*) from alvo   where grupo = 'controlo'),
      'controlo_voltaram', (select count(*) from voltas where grupo = 'controlo')));
end $$;

-- 8. Histórico de campanhas (com o resultado embutido)
create or replace function listar_campanhas_reconquista(p_limite int default 50)
returns table (id uuid, criado_em timestamptz, criado_por_nome text, dias_min int, dias_max int,
               total_elegiveis int, total_enviados int, total_controlo int, resultado jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('clientes.reconquista');
  return query
    select c.id, c.criado_em, c.criado_por_nome, c.dias_min, c.dias_max,
           c.total_elegiveis, c.total_enviados, c.total_controlo,
           campanha_reconquista_resultado(c.id)
      from campanhas_reconquista c
     order by c.criado_em desc
     limit greatest(1, least(coalesce(p_limite, 50), 200));
end $$;

-- 9. Permissões de execução
revoke execute on function clientes_inativos(int, int, uuid)                          from public, anon;
revoke execute on function clientes_inativos_resumo()                                 from public, anon;
revoke execute on function enviar_campanha_reconquista(int, int, uuid, text, text, text, int) from public, anon;
revoke execute on function campanha_reconquista_resultado(uuid)                       from public, anon;
revoke execute on function listar_campanhas_reconquista(int)                          from public, anon;
grant  execute on function clientes_inativos(int, int, uuid)                          to authenticated;
grant  execute on function clientes_inativos_resumo()                                 to authenticated;
grant  execute on function enviar_campanha_reconquista(int, int, uuid, text, text, text, int) to authenticated;
grant  execute on function campanha_reconquista_resultado(uuid)                       to authenticated;
grant  execute on function listar_campanhas_reconquista(int)                          to authenticated;
