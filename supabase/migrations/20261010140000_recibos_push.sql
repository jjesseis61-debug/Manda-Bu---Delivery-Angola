-- Limpeza de tokens inválidos pela 2ª fase do Expo (os "receipts").
-- O push devolve um "ticket" na hora (quase sempre ok), mas o resultado real da entrega ao
-- telemóvel (ex.: DeviceNotRegistered quando a app foi desinstalada) só aparece no "receipt",
-- disponível uns minutos depois. Guardamos aqui o ticket_id + token; mais tarde a edge function
-- consulta os receipts e desactiva os tokens que já não servem, para não voltar a enviar-lhes
-- e para os totais ("enviado a X pessoas") ficarem reais.

create table recibos_push (
  id uuid primary key default gen_random_uuid(),
  ticket_id text not null,
  token text not null,
  criado_em timestamptz not null default now()
);
alter table recibos_push enable row level security;
revoke all on recibos_push from public, anon, authenticated;
create index recibos_push_criado_idx on recibos_push (criado_em);

-- Guarda os tickets "ok" para verificar o receipt mais tarde. p_recibos: [{ticket_id, token}, ...]
create or replace function registar_recibos_push(p_recibos jsonb) returns integer
language sql security definer set search_path = public as $$
  with ins as (
    insert into recibos_push (ticket_id, token)
    select r->>'ticket_id', r->>'token'
    from jsonb_array_elements(coalesce(p_recibos, '[]'::jsonb)) as r
    where coalesce(r->>'ticket_id', '') <> '' and coalesce(r->>'token', '') <> ''
    returning 1
  )
  select count(*)::int from ins;
$$;

-- Tickets prontos para verificar (o Expo só tem o receipt uns minutos depois; retêm-se 24h).
create or replace function recibos_por_verificar(p_limite integer default 300, p_idade interval default interval '15 minutes')
returns table (id uuid, ticket_id text, token text)
language sql security definer set search_path = public as $$
  select id, ticket_id, token
  from recibos_push
  where criado_em <= now() - p_idade
  order by criado_em
  limit greatest(p_limite, 0);
$$;

-- Apaga os recibos já verificados, desactiva os tokens inválidos e limpa os que o Expo nunca
-- devolveu (passadas 24h os receipts expiram). Devolve quantos tokens foram desactivados.
create or replace function concluir_recibos(p_ids uuid[], p_tokens_invalidos text[]) returns integer
language plpgsql security definer set search_path = public as $$
declare v_desactivados integer := 0;
begin
  if p_tokens_invalidos is not null and array_length(p_tokens_invalidos, 1) is not null then
    v_desactivados := desactivar_tokens_push(p_tokens_invalidos);
  end if;
  if p_ids is not null and array_length(p_ids, 1) is not null then
    delete from recibos_push where id = any(p_ids);
  end if;
  delete from recibos_push where criado_em < now() - interval '24 hours';
  return v_desactivados;
end;
$$;

revoke execute on function registar_recibos_push(jsonb), recibos_por_verificar(integer, interval), concluir_recibos(uuid[], text[])
  from public, anon, authenticated;
grant execute on function registar_recibos_push(jsonb), recibos_por_verificar(integer, interval), concluir_recibos(uuid[], text[])
  to service_role;
