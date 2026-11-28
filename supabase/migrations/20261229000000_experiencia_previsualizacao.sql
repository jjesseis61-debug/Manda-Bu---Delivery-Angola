-- Pré-visualização dos testes com grupo de controlo: um cliente que também é funcionário vê sempre o
-- desenho novo (grupo B), para a equipa o poder experimentar, e as visitas dele não entram na contagem
-- (Skinner: os números do teste ficam só com clientes de verdade).
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
  -- Pré-visualização: quem também trabalha na plataforma vê sempre o desenho novo (B) e não entra na contagem
  if funcionario_actual() is not null then
    return 'B';
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

