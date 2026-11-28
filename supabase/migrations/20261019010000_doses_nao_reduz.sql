-- Regra das doses: uma vez lançadas, não se retiram.
--
-- O operador normal só pode ACRESCENTAR doses lançadas hoje (5 -> 7). Não pode reduzir (7 -> 6).
-- Só o administrador principal pode reduzir/corrigir. Para impedir o truque de ir a "sem limite"
-- e voltar a um número menor, guardamos o PICO do dia (o máximo lançado nesse dia) e ninguém,
-- sem ser admin, pode pôr um número abaixo desse pico. Num dia novo o pico reinicia.
alter table cardapio
  add column doses_pico_dia  integer check (doses_pico_dia >= 0 and doses_pico_dia <= 100000),
  add column doses_pico_data date;
comment on column cardapio.doses_pico_dia is 'Máximo de doses lançadas no dia doses_pico_data; o operador normal não pode baixar doses_dia abaixo deste valor (só o admin principal)';

create or replace function cardapio_doses_nao_reduz() returns trigger
language plpgsql set search_path = public as $$
declare
  v_hoje date := (now() at time zone 'Africa/Luanda')::date;
  v_pico integer;
begin
  if tg_op = 'INSERT' then
    -- Criar o prato já é lançar: o pico começa no que for inserido hoje.
    if new.doses_dia is not null then
      new.doses_pico_dia := new.doses_dia;
      new.doses_pico_data := v_hoje;
    end if;
    return new;
  end if;

  -- UPDATE: só interessa quando as doses mudam
  if new.doses_dia is not distinct from old.doses_dia then
    return new;
  end if;

  -- Pico lançado HOJE (dia novo reinicia a zero)
  v_pico := case when old.doses_pico_data = v_hoje then coalesce(old.doses_pico_dia, 0) else 0 end;

  -- Operador normal: não pode pôr um número abaixo do pico de hoje. "Sem limite" (null) é sempre
  -- permitido (aumenta a disponibilidade), mas o pico mantém-se para não dar para descer por ali.
  if not e_administrador() and new.doses_dia is not null and new.doses_dia < v_pico then
    raise exception 'doses_nao_reduz' using errcode = '42501',
      detail = 'Só o administrador principal pode reduzir doses já lançadas hoje.';
  end if;

  new.doses_pico_dia := greatest(v_pico, coalesce(new.doses_dia, v_pico));
  new.doses_pico_data := v_hoje;
  return new;
end $$;

revoke execute on function cardapio_doses_nao_reduz() from public, anon, authenticated;

-- Corre depois do trg_0_normalizar (que trata de doses_definidas_em e categoria)
create trigger trg_1_doses_nao_reduz before insert or update on cardapio
for each row execute function cardapio_doses_nao_reduz();
