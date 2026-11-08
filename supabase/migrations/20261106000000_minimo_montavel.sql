-- =============================================================================
-- Valor mínimo para montar (prato montável)
-- -----------------------------------------------------------------------------
-- O operador pode definir um valor mínimo (base + extras) para o cliente poder
-- servir/adicionar o prato montável. A app mostra a mensagem e bloqueia abaixo
-- disso; o servidor volta a impor em opcoes_do_item (não se contorna pela app).
-- null/0 = sem mínimo.
-- =============================================================================

alter table cardapio add column if not exists minimo_montavel int
  check (minimo_montavel is null or minimo_montavel >= 0);

-- opcoes_do_item: valida as opções (min/máx por grupo), soma os extras e, quando
-- o prato tem minimo_montavel, impõe (base + extras) >= mínimo.
create or replace function opcoes_do_item(p_cardapio uuid, p_opcoes jsonb)
returns table (extra integer, opcoes jsonb, descricao text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_ids    uuid[] := '{}';
  g        record;
  n        integer;
  v_extra  integer;
  v_opcoes jsonb;
  v_desc   text;
  v_base   integer;
  v_min    integer;
begin
  if coalesce(jsonb_typeof(p_opcoes), 'null') <> 'null' then
    if jsonb_typeof(p_opcoes) <> 'array' or jsonb_array_length(p_opcoes) > 20 then
      raise exception 'opcao_invalida' using errcode = 'P0001';
    end if;
    begin
      select coalesce(array_agg(coalesce(e ->> 'id', e #>> '{}')::uuid), '{}') into v_ids
        from jsonb_array_elements(p_opcoes) e;
    exception when invalid_text_representation then
      raise exception 'opcao_invalida' using errcode = 'P0001';
    end;
  end if;
  if cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception 'opcao_invalida' using errcode = 'P0001';
  end if;
  if exists (select 1 from unnest(v_ids) x
              where not exists (select 1 from opcoes o join opcoes_grupos gr on gr.id = o.grupo_id
                                 where o.id = x and gr.cardapio_id = p_cardapio and o.disponivel
                                   and o.deletado_em is null and gr.deletado_em is null)) then
    raise exception 'opcao_invalida' using errcode = 'P0001';
  end if;
  for g in select gr.id, gr.nome, gr.minimo, gr.maximo from opcoes_grupos gr
            where gr.cardapio_id = p_cardapio and gr.deletado_em is null loop
    select count(*) into n from opcoes o where o.grupo_id = g.id and o.id = any(v_ids);
    if n < g.minimo then
      raise exception 'opcoes_em_falta' using errcode = 'P0001', detail = g.nome;
    end if;
    if n > g.maximo then
      raise exception 'opcoes_a_mais' using errcode = 'P0001', detail = g.nome;
    end if;
  end loop;

  select coalesce(sum(o.preco_extra), 0)::int,
         coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'nome', o.nome, 'preco_extra', o.preco_extra)
                            order by gr.ordem, gr.nome, o.ordem, o.nome), '[]'::jsonb),
         string_agg(o.nome, ', ' order by gr.ordem, gr.nome, o.ordem, o.nome)
    into v_extra, v_opcoes, v_desc
    from opcoes o join opcoes_grupos gr on gr.id = o.grupo_id
   where o.id = any(v_ids);

  -- Valor mínimo para montar (base + extras), imposto no servidor
  select preco, minimo_montavel into v_base, v_min from cardapio where id = p_cardapio;
  if coalesce(v_min, 0) > 0 and (coalesce(v_base, 0) + v_extra) < v_min then
    raise exception 'abaixo_do_minimo' using errcode = 'P0001', detail = v_min::text;
  end if;

  return query select v_extra, v_opcoes, v_desc;
end $$;
revoke execute on function opcoes_do_item(uuid, jsonb) from public, anon, authenticated;
