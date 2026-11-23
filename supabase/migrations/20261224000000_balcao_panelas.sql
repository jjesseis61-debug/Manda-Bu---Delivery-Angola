-- Balcão de panelas no «Servir o prato» com grupo de controlo (Skinner: medir antes de adoptar).
-- Com o interruptor «teste_balcao_panelas» ligado, metade dos clientes vê o balcão (B: panelas, concha
-- e prato em baixo) e a outra metade a lista de sempre (A). Desligado: todos vêem a lista e nada é registado.
-- Reaproveita experiencia_visitas: uma visita por dia ao «Servir o prato» e o tempo até «Adicionar».
-- O interruptor de cada experiência chama-se 'teste_' || experiência.
insert into funcionalidades (chave, activa, dispositivo_id)
values ('teste_balcao_panelas', false, 'servidor')
on conflict (chave) do nothing;

create or replace function visita_experiencia(p_experiencia text, p_segundos_ate_adicionar integer default null)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_cliente  uuid := cliente_actual();
  v_variante text;
  v_dia      date := (now() at time zone 'Africa/Luanda')::date;
  v_seg      integer;
begin
  if p_experiencia is null or p_experiencia not in ('fotos_inicio', 'balcao_panelas') then
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
  if p_experiencia is null or p_experiencia not in ('fotos_inicio', 'balcao_panelas') then
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
