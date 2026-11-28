-- Campanhas de cozinha: quem gere o cardápio de uma cozinha pode pôr os pratos DELA em promoção
-- para todos os clientes (sem condomínio nem zona). As outras campanhas continuam como estavam:
-- de condomínio (cozinhas.gerir ou quem gere o condomínio) e por zona/para todas as cozinhas
-- (cozinhas.gerir). Os pratos de uma campanha têm de ser da cozinha da campanha.

create or replace function pode_gerir_campanha_de(p_cond uuid, p_zona uuid, p_cozinha uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
           when p_cond is not null then pode_gerir_campanha(p_cond)
           else tem_permissao('cozinhas.gerir')
                or (p_zona is null and p_cozinha is not null and pode_na_cozinha('cardapio.gerir', p_cozinha))
         end;
$$;
revoke execute on function pode_gerir_campanha_de(uuid, uuid, uuid) from public, anon, authenticated;

create or replace function guardar_campanha(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid := nullif(p ->> 'id', '')::uuid;
  v_cond uuid := nullif(p ->> 'condominio_id', '')::uuid;
  v_zona uuid := nullif(p ->> 'zona_id', '')::uuid;
  v_coz  uuid := nullif(p ->> 'cozinha_id', '')::uuid;
  v_ant  campanhas;
begin
  if v_id is not null then
    select * into v_ant from campanhas where id = v_id and deletado_em is null;
    if not found then raise exception 'campanha_inexistente' using errcode = 'P0001'; end if;
    if not pode_gerir_campanha_de(v_ant.condominio_id, v_ant.zona_id, v_ant.cozinha_id) then
      raise exception 'sem_permissao' using errcode = '42501';
    end if;
  end if;
  if not pode_gerir_campanha_de(v_cond, v_zona, v_coz) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  -- Os pratos escolhidos têm de ser da cozinha da campanha
  if v_coz is not null and exists (
       select 1 from jsonb_array_elements_text(nullif(p -> 'cardapio_ids', 'null')) x
        where not exists (select 1 from cardapio c where c.id = x::uuid and c.cozinha_id = v_coz)) then
    raise exception 'prato_de_outra_cozinha' using errcode = 'P0001';
  end if;
  if v_id is null then
    insert into campanhas (nome, descricao, condominio_id, zona_id, cozinha_id, tipo, valor, cardapio_ids, minimo_pedido,
                           inicio, fim, dias_semana, hora_inicio, hora_fim, so_membros, limite_por_cliente, limite_total, activa)
    values (trim(p ->> 'nome'), nullif(trim(p ->> 'descricao'), ''), v_cond, nullif(p ->> 'zona_id', '')::uuid,
            nullif(p ->> 'cozinha_id', '')::uuid, p ->> 'tipo', (p ->> 'valor')::int,
            (select array_agg(x::uuid) from jsonb_array_elements_text(nullif(p -> 'cardapio_ids', 'null')) x),
            coalesce((p ->> 'minimo_pedido')::int, 0), coalesce(nullif(p ->> 'inicio', '')::timestamptz, now()),
            nullif(p ->> 'fim', '')::timestamptz,
            (select array_agg(x::int) from jsonb_array_elements_text(nullif(p -> 'dias_semana', 'null')) x),
            nullif(p ->> 'hora_inicio', '')::time, nullif(p ->> 'hora_fim', '')::time,
            coalesce((p ->> 'so_membros')::boolean, false), nullif(p ->> 'limite_por_cliente', '')::int,
            nullif(p ->> 'limite_total', '')::int, coalesce((p ->> 'activa')::boolean, true))
    returning id into v_id;
  else
    update campanhas
       set nome = trim(p ->> 'nome'), descricao = nullif(trim(p ->> 'descricao'), ''), condominio_id = v_cond,
           zona_id = nullif(p ->> 'zona_id', '')::uuid, cozinha_id = nullif(p ->> 'cozinha_id', '')::uuid,
           tipo = p ->> 'tipo', valor = (p ->> 'valor')::int,
           cardapio_ids = (select array_agg(x::uuid) from jsonb_array_elements_text(nullif(p -> 'cardapio_ids', 'null')) x),
           minimo_pedido = coalesce((p ->> 'minimo_pedido')::int, 0),
           inicio = coalesce(nullif(p ->> 'inicio', '')::timestamptz, inicio), fim = nullif(p ->> 'fim', '')::timestamptz,
           dias_semana = (select array_agg(x::int) from jsonb_array_elements_text(nullif(p -> 'dias_semana', 'null')) x),
           hora_inicio = nullif(p ->> 'hora_inicio', '')::time, hora_fim = nullif(p ->> 'hora_fim', '')::time,
           so_membros = coalesce((p ->> 'so_membros')::boolean, false),
           limite_por_cliente = nullif(p ->> 'limite_por_cliente', '')::int, limite_total = nullif(p ->> 'limite_total', '')::int,
           activa = coalesce((p ->> 'activa')::boolean, activa), atualizado_em = now()
     where id = v_id;
  end if;
  return v_id;
end $$;
revoke execute on function guardar_campanha(jsonb) from public, anon;
grant  execute on function guardar_campanha(jsonb) to authenticated;

-- Lista, apagar e avisar seguem a mesma regra
do $$
declare
  f text;
  v_def text;
  v_novo text;
begin
  foreach f in array array['campanhas_lista()', 'apagar_campanha(uuid)', 'campanha_avisar(uuid)'] loop
    v_def := pg_get_functiondef(f::regprocedure);
    v_novo := replace(v_def, 'pode_gerir_campanha(k.condominio_id)', 'pode_gerir_campanha_de(k.condominio_id, k.zona_id, k.cozinha_id)');
    if v_novo = v_def and position('pode_gerir_campanha_de(' in v_def) = 0 then
      raise exception '% não tem o formato esperado', f;
    end if;
    execute v_novo;
  end loop;
end $$;
