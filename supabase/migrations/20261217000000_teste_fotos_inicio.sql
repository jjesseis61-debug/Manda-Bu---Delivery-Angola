-- Teste com grupo de controlo (Skinner) do cartão do prato no Início:
--   A = fotografia grande (como era), B = fotografia média ao lado do nome (o desenho novo).
-- Com o interruptor «teste_fotos_inicio» ligado, cada cliente cai sempre no mesmo grupo (metade/metade,
-- pelo id); a app regista uma visita por dia ao Início e o tempo até ao primeiro «Adicionar».
-- O resultado compara os dois grupos pelos pedidos reais (não cancelados) feitos nos dias de visita.
-- Desligado: ninguém é registado e todos vêem B.
insert into funcionalidades (chave, activa, dispositivo_id)
values ('teste_fotos_inicio', false, 'servidor')
on conflict (chave) do nothing;

create table if not exists experiencia_visitas (
  experiencia            text not null,
  cliente_id             uuid not null references clientes(id) on delete cascade,
  dia                    date not null,
  variante               text not null check (variante in ('A', 'B')),
  visitas                integer not null default 1 check (visitas >= 0),
  -- O mais rápido do dia entre abrir o Início e tocar no primeiro «Adicionar»
  segundos_ate_adicionar integer check (segundos_ate_adicionar between 0 and 3600),
  primary key (experiencia, cliente_id, dia)
);
create index if not exists experiencia_visitas_cliente_idx on experiencia_visitas (cliente_id);
alter table experiencia_visitas enable row level security;
revoke all on experiencia_visitas from public, anon, authenticated;

-- Grupo fixo do cliente numa experiência (metade/metade pelo primeiro byte do md5)
create or replace function variante_experiencia(p_experiencia text, p_cliente uuid) returns text
language sql immutable set search_path = public as $$
  select case when get_byte(decode(md5(p_experiencia || ':' || p_cliente::text), 'hex'), 0) % 2 = 0 then 'A' else 'B' end
$$;
revoke execute on function variante_experiencia(text, uuid) from public, anon, authenticated;

-- Chamada pela app: sem segundos conta uma visita; com segundos guarda o tempo até ao primeiro
-- «Adicionar» (sem contar outra visita). Devolve o grupo, ou null (visitante, interruptor desligado).
create or replace function visita_experiencia(p_experiencia text, p_segundos_ate_adicionar integer default null)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_cliente  uuid := cliente_actual();
  v_variante text;
  v_dia      date := (now() at time zone 'Africa/Luanda')::date;
  v_seg      integer;
begin
  if p_experiencia is distinct from 'fotos_inicio' then
    raise exception 'experiencia_desconhecida' using errcode = '22023';
  end if;
  if v_cliente is null or not funcionalidade_activa('teste_fotos_inicio') then
    return null;
  end if;
  v_variante := variante_experiencia(p_experiencia, v_cliente);
  if p_segundos_ate_adicionar is null then
    insert into experiencia_visitas (experiencia, cliente_id, dia, variante)
    values (p_experiencia, v_cliente, v_dia, v_variante)
    on conflict (experiencia, cliente_id, dia) do update set visitas = experiencia_visitas.visitas + 1;
  else
    v_seg := least(greatest(p_segundos_ate_adicionar, 0), 3600);
    insert into experiencia_visitas (experiencia, cliente_id, dia, variante, visitas, segundos_ate_adicionar)
    values (p_experiencia, v_cliente, v_dia, v_variante, 0, v_seg)
    on conflict (experiencia, cliente_id, dia) do update
      set segundos_ate_adicionar = least(coalesce(experiencia_visitas.segundos_ate_adicionar, excluded.segundos_ate_adicionar),
                                         excluded.segundos_ate_adicionar);
  end if;
  return v_variante;
end $$;
revoke execute on function visita_experiencia(text, integer) from public, anon;
grant execute on function visita_experiencia(text, integer) to authenticated;

-- Resultado por grupo entre duas datas (Luanda): dias com visita, dias que acabaram em pedido,
-- conversão, pedidos, valor médio do pedido e mediana do tempo até ao primeiro «Adicionar».
create or replace function resultado_experiencia(p_experiencia text, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb;
begin
  if not tem_permissao('analista.usar') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'analista.usar';
  end if;
  with dias as (
    select e.variante, e.cliente_id, e.dia, e.visitas, e.segundos_ate_adicionar
      from experiencia_visitas e
     where e.experiencia = p_experiencia and e.dia between p_de and p_ate and e.visitas > 0
  ), ped as (
    select d.variante, d.cliente_id, d.dia, p.id, p.subtotal
      from dias d
      join pedidos p on p.cliente_id = d.cliente_id
                    and (p.criado_em at time zone 'Africa/Luanda')::date = d.dia
                    and p.estado <> 'cancelado' and p.deletado_em is null
  ), por as (
    select g.variante,
           (select count(distinct cliente_id) from dias where variante = g.variante)::int as clientes,
           (select count(*) from dias where variante = g.variante)::int as dias_visita,
           (select coalesce(sum(visitas), 0) from dias where variante = g.variante)::int as visitas,
           (select count(distinct (cliente_id, dia)) from ped where variante = g.variante)::int as dias_com_pedido,
           (select count(*) from ped where variante = g.variante)::int as pedidos,
           (select round(avg(subtotal))::int from ped where variante = g.variante) as valor_medio,
           (select percentile_cont(0.5) within group (order by segundos_ate_adicionar)
              from dias where variante = g.variante and segundos_ate_adicionar is not null) as mediana_segundos
      from (values ('A'), ('B')) g(variante)
  )
  select jsonb_object_agg(variante, jsonb_build_object(
           'clientes', clientes, 'dias_visita', dias_visita, 'visitas', visitas,
           'dias_com_pedido', dias_com_pedido,
           'conversao_pct', case when dias_visita > 0 then round(100.0 * dias_com_pedido / dias_visita, 1) end,
           'pedidos', pedidos, 'valor_medio', valor_medio,
           'mediana_segundos', case when mediana_segundos is not null then round(mediana_segundos::numeric)::int end))
    into v
    from por;
  return jsonb_build_object('experiencia', p_experiencia, 'de', p_de, 'ate', p_ate,
                            'activo', funcionalidade_activa('teste_fotos_inicio'), 'grupos', v);
end $$;
revoke execute on function resultado_experiencia(text, date, date) from public, anon;
grant execute on function resultado_experiencia(text, date, date) to authenticated;
