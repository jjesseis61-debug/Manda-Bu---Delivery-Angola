-- =============================================================================
-- Código de convite: mais espaço, sem zeros à esquerda e sem erro em registos simultâneos
-- (decisão do dono, 19/11/2026)
-- -----------------------------------------------------------------------------
--   * formato MB + 4 a 6 dígitos (até ~1 milhão de códigos; antes o teto era 4–5)
--   * os códigos novos nunca começam por 0 (MB1000…MB9999, depois MB10000…, MB100000…):
--     quem escreve só o número não se engana com os zeros. Os códigos antigos continuam válidos.
--   * dois registos no mesmo instante que sorteiem o mesmo número: o segundo sorteia outro, sem
--     erro para o cliente (antes a unicidade recusava e o registo falhava)
-- =============================================================================

-- Aceita MB4812, mb-4812, MB 4812, só 4812 (4 a 6 dígitos) → MB4812
create or replace function normalizar_codigo_convite(p text) returns text
language sql immutable set search_path = public as $$
  select case
           when x ~ '^[0-9]{4,6}$' then 'MB' || x
           when x ~ '^MB[0-9]{4,6}$' then x
         end
    from (select regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g') as x) s;
$$;

alter table codigos_indicacao drop constraint if exists codigos_indicacao_formato;
alter table codigos_indicacao add constraint codigos_indicacao_formato check (codigo ~ '^MB[0-9]{4,6}$');

/**
 * Código novo e livre: MB + 4 dígitos sem zero à esquerda (9.000 códigos); quando esse espaço
 * fica cheio (ou quase: 200 sorteios seguidos ocupados), passa a 5 e depois a 6 dígitos.
 */
create or replace function gerar_codigo_indicacao() returns text
language plpgsql security definer set search_path = public as $$
declare
  v text;
  digitos int := 4;
  tentativas int := 0;
begin
  while digitos < 6 and (select count(*) from codigos_indicacao
                          where codigo ~ ('^MB[1-9][0-9]{' || (digitos - 1) || '}$')) >= 9 * power(10, digitos - 1) loop
    digitos := digitos + 1;
  end loop;
  loop
    v := 'MB' || (power(10, digitos - 1)::bigint + floor(random() * 9 * power(10, digitos - 1))::bigint)::text;
    exit when not exists (select 1 from codigos_indicacao where codigo = v);
    tentativas := tentativas + 1;
    if tentativas >= 200 then
      if digitos >= 6 then raise exception 'sem códigos de convite livres'; end if;
      digitos := digitos + 1;
      tentativas := 0;
    end if;
  end loop;
  return v;
end $$;
revoke execute on function gerar_codigo_indicacao() from public, anon, authenticated;

-- O código do cliente: se outro registo, no mesmo instante, ficou com o mesmo número, sorteia outro
create or replace function preparar_cliente_programa(p_cliente uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from codigos_indicacao where cliente_id = p_cliente) then
    for i in 1..5 loop
      begin
        insert into codigos_indicacao (cliente_id, codigo, dispositivo_id)
        values (p_cliente, gerar_codigo_indicacao(), 'servidor')
        on conflict (cliente_id) do nothing;
        exit;
      exception when unique_violation then
        if i = 5 then raise; end if;
      end;
    end loop;
  end if;
  if not exists (select 1 from perfil_destaques where cliente_id = p_cliente) then
    insert into perfil_destaques (cliente_id, pseudonimo, dispositivo_id)
    values (p_cliente, gerar_pseudonimo(), 'servidor');
  end if;
  if not exists (select 1 from preferencias_notificacao where cliente_id = p_cliente) then
    insert into preferencias_notificacao (cliente_id, dispositivo_id)
    values (p_cliente, 'servidor');
  end if;
end $$;
revoke execute on function preparar_cliente_programa(uuid) from public, anon, authenticated;
