-- Balcão com recipientes próprios (fase 2): cada comida no recipiente em que se serve de verdade
-- (Rogers: o que se vê na cantina e em casa). A app deduz o recipiente pelo nome; a cozinha pode escolhê-lo
-- no operador para o grupo e, se for diferente, para uma opção. Sopa, pão e molho vão ao lado do prato;
-- sobremesa e fruta no prato da sobremesa; bebidas no tabuleiro.
-- O desenho mudou: o teste recomeça com contagem nova («balcao_recipientes»), para não misturar as duas
-- versões no grupo B (Skinner). O interruptor novo herda o estado do antigo, e o antigo fica desligado.

alter table opcoes_grupos add column if not exists recipiente text
  check (recipiente in ('panela', 'barro', 'tigela', 'cartucho', 'travessa', 'saladeira', 'malga', 'cesto', 'molheira', 'taca', 'fruteira', 'copo', 'lata'));
alter table opcoes add column if not exists recipiente text
  check (recipiente in ('panela', 'barro', 'tigela', 'cartucho', 'travessa', 'saladeira', 'malga', 'cesto', 'molheira', 'taca', 'fruteira', 'copo', 'lata'));
comment on column opcoes_grupos.recipiente is
  'Recipiente do grupo no balcão do cliente; null = a app deduz pelo nome (batata frita em cartucho, sopa em malga...)';
comment on column opcoes.recipiente is
  'Recipiente desta opção quando é diferente do do grupo; null = o do grupo';

insert into funcionalidades (chave, activa, dispositivo_id)
values ('teste_balcao_recipientes', coalesce((select activa from funcionalidades where chave = 'teste_balcao_panelas'), false), 'servidor')
on conflict (chave) do nothing;
update funcionalidades set activa = false where chave = 'teste_balcao_panelas' and activa;

-- O prato modelo copiado para as cozinhas novas leva também os recipientes
create or replace function clonar_montavel(p_cozinha uuid, p_modelo uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_modelo uuid := coalesce(p_modelo, modelo_montavel());
  m        cardapio;
  v_novo   uuid;
  g        record;
  v_grupo  uuid;
begin
  if p_modelo is not null and not e_montavel(p_modelo) then
    raise exception 'modelo_invalido' using errcode = 'P0001';
  end if;
  if v_modelo is null
     or not exists (select 1 from cozinhas where id = p_cozinha and deletado_em is null) then
    return null;
  end if;
  select * into m from cardapio where id = v_modelo;
  if exists (select 1 from cardapio c
              where c.cozinha_id = p_cozinha and c.deletado_em is null
                and lower(trim(c.nome)) = lower(trim(m.nome))) then
    return null;
  end if;

  insert into cardapio (dispositivo_id, cozinha_id, prato_base_id, nome, descricao, categoria, preco,
                        foto_url, disponivel, do_dia, ordem, visivel_online, minimo_montavel)
  values ('servidor', p_cozinha, m.prato_base_id, m.nome, m.descricao, m.categoria, m.preco,
          m.foto_url, false, false, m.ordem, m.visivel_online, m.minimo_montavel)
  returning id into v_novo;

  for g in select * from opcoes_grupos
            where cardapio_id = v_modelo and deletado_em is null order by ordem, criado_em loop
    insert into opcoes_grupos (dispositivo_id, cardapio_id, nome, minimo, maximo, ordem, recipiente)
    values ('servidor', v_novo, g.nome, g.minimo, g.maximo, g.ordem, g.recipiente)
    returning id into v_grupo;
    insert into opcoes (dispositivo_id, grupo_id, nome, preco_extra, disponivel, ordem, componentes, foto_url, recipiente)
    select 'servidor', v_grupo, o.nome, o.preco_extra, o.disponivel, o.ordem, o.componentes, o.foto_url, o.recipiente
      from opcoes o
     where o.grupo_id = g.id and o.deletado_em is null
     order by o.ordem, o.criado_em;
  end loop;

  perform registar_auditoria('montavel_clonado', 'cardapio', v_novo,
                             jsonb_build_object('modelo', v_modelo, 'cozinha', p_cozinha));
  return v_novo;
end $$;
revoke execute on function clonar_montavel(uuid, uuid) from public, anon, authenticated;

-- Visitas e resultado aceitam a contagem nova (a antiga continua consultável)
create or replace function visita_experiencia(p_experiencia text, p_segundos_ate_adicionar integer default null)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_cliente  uuid := cliente_actual();
  v_variante text;
  v_dia      date := (now() at time zone 'Africa/Luanda')::date;
  v_seg      integer;
begin
  if p_experiencia is null or p_experiencia not in ('fotos_inicio', 'balcao_panelas', 'balcao_recipientes') then
    raise exception 'experiencia_desconhecida' using errcode = '22023';
  end if;
  if v_cliente is null or not funcionalidade_activa('teste_' || p_experiencia) then
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

create or replace function resultado_experiencia(p_experiencia text, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb;
begin
  if not tem_permissao('analista.usar') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'analista.usar';
  end if;
  if p_experiencia is null or p_experiencia not in ('fotos_inicio', 'balcao_panelas', 'balcao_recipientes') then
    raise exception 'experiencia_desconhecida' using errcode = '22023';
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
                            'activo', funcionalidade_activa('teste_' || p_experiencia), 'grupos', v);
end $$;
revoke execute on function resultado_experiencia(text, date, date) from public, anon;
grant execute on function resultado_experiencia(text, date, date) to authenticated;
