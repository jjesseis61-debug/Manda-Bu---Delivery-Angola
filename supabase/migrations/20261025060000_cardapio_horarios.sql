-- Horários do cardápio: lista de janelas por prato (recorrente por dia da semana, ou uma vez por data).
-- Resolve o caso de horas diferentes por dia (ex.: Seg/Qua 08–11, Sáb 11–14) e dois turnos no mesmo dia.
-- Cada linha é uma janela. "Disponível agora" = existe uma janela cujo dia/data bate com hoje e a hora
-- atual (em Angola) está dentro. Continua sem agendador: a visibilidade é calculada na leitura.
-- A janela de uma vez da v1 (cardapio.disponivel_de/ate) continua a valer (o ajudante honra as duas).

create table cardapio_horarios (
  id          uuid primary key default gen_random_uuid(),
  cardapio_id uuid not null references cardapio(id) on delete cascade,
  dia_semana  int  check (dia_semana between 1 and 7),  -- ISO: 1=Seg … 7=Dom (null se for por data)
  data        date,                                     -- data específica (null se for por dia da semana)
  hora_inicio time not null,
  hora_fim    time not null,
  criado_em   timestamptz not null default now(),
  check (num_nonnulls(dia_semana, data) = 1)            -- exatamente um: dia da semana OU data
);
create index cardapio_horarios_cardapio_idx on cardapio_horarios (cardapio_id);
alter table cardapio_horarios enable row level security;
revoke all on cardapio_horarios from anon, authenticated;
grant select, insert, update, delete on cardapio_horarios to authenticated;
-- Só quem gere cozinhas vê e mexe nos horários (o cliente nunca lê esta tabela; a visibilidade dele
-- vem do ajudante abaixo, que fura a RLS).
create policy gerir on cardapio_horarios for all to authenticated
  using ((select tem_permissao('cozinhas.gerir')))
  with check ((select tem_permissao('cozinhas.gerir')));

-- Auditoria: quem mudou os horários (mesmo gatilho genérico do cardápio/cozinhas).
create trigger trg_auditar after insert or update on cardapio_horarios
for each row execute function auditar_alteracao_tabela();

-- A hora atual cai dentro de [ini, fim)? Trata janelas que cruzam a meia-noite (ex.: 22:00–02:00).
create or replace function janela_hora(p_t time, p_ini time, p_fim time) returns boolean
language sql immutable set search_path = public as $$
  select case when p_ini <= p_fim then p_t >= p_ini and p_t < p_fim
              else p_t >= p_ini or p_t < p_fim end;
$$;
grant execute on function janela_hora(time, time, time) to authenticated;

-- "Está disponível agora?" — honra a janela de uma vez (v1) E a lista de horários. Sem agenda nenhuma
-- => sempre disponível (como hoje). Hora de Angola (UTC+1, sem horário de verão). SECURITY DEFINER
-- para ler além da RLS; devolve só um booleano.
create or replace function cardapio_aberto_agora(p_id uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_de timestamptz; v_ate timestamptz;
  v_ts timestamptz := now() at time zone 'Africa/Luanda';
begin
  select disponivel_de, disponivel_ate into v_de, v_ate from cardapio where id = p_id;
  -- sem janela de uma vez e sem horários => sempre disponível
  if v_de is null and v_ate is null
     and not exists (select 1 from cardapio_horarios where cardapio_id = p_id) then
    return true;
  end if;
  -- janela de uma vez (v1)
  if (v_de is not null or v_ate is not null) and janela_aberta(v_de, v_ate) then
    return true;
  end if;
  -- lista de horários (recorrente por dia OU data específica)
  return exists (
    select 1 from cardapio_horarios h
     where h.cardapio_id = p_id
       and ( (h.dia_semana is not null and h.dia_semana = extract(isodow from v_ts)::int)
             or (h.data is not null and h.data = v_ts::date) )
       and janela_hora(v_ts::time, h.hora_inicio, h.hora_fim) );
end $$;
revoke execute on function cardapio_aberto_agora(uuid) from public, anon;
grant  execute on function cardapio_aberto_agora(uuid) to authenticated;

-- Leitura do cardápio: gestores veem tudo; clientes só o que está aberto agora (uma vez OU horários).
drop policy ler on cardapio;
create policy ler on cardapio for select to authenticated using (
  deletado_em is null
  and ( (select tem_permissao('cozinhas.gerir')) or cardapio_aberto_agora(id) )
);

-- Guarda do pedido: passa a usar o ajudante completo (uma vez + horários).
create or replace function cardapio_fora_da_janela(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select not cardapio_aberto_agora(p_id);
$$;
revoke execute on function cardapio_fora_da_janela(uuid) from public, anon;
grant  execute on function cardapio_fora_da_janela(uuid) to authenticated;
