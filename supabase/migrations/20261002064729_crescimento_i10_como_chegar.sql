-- I10 · "Como chegar": localização de cada cozinha, para o cliente lá chegar com o
-- Google Maps (botão que abre a navegação no telemóvel; sem API paga).
-- Interruptor `como_chegar` (desligado).
--
-- A localização fica numa tabela à parte e só se mostra aos clientes quando a
-- responsável o autoriza (`publica`): muitas cozinhas parceiras são casas.

insert into funcionalidades (chave, activa, dispositivo_id) values ('como_chegar', false, 'servidor')
on conflict (chave) do nothing;

create table cozinhas_localizacao (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cozinha_id       uuid not null unique references cozinhas(id),
  morada           text check (morada is null or length(morada) <= 200),
  horario          text check (horario is null or length(horario) <= 120),
  lat              double precision not null check (lat between -90 and 90),
  lng              double precision not null check (lng between -180 and 180),
  publica          boolean not null default false
);
comment on table cozinhas_localizacao is
  'Sincronização: Last-write-wins com atualizado_em; escrita só com cozinhas.gerir. Aos clientes só por localizacao_cozinha() e com publica (I10).';

alter table cozinhas_localizacao enable row level security;
create policy ler on cozinhas_localizacao for select to authenticated using (e_funcionario());
create policy criar on cozinhas_localizacao for insert to authenticated with check (tem_permissao('cozinhas.gerir'));
create policy editar on cozinhas_localizacao for update to authenticated
  using (tem_permissao('cozinhas.gerir')) with check (tem_permissao('cozinhas.gerir'));
grant select, insert, update on cozinhas_localizacao to authenticated;

create trigger trg_sync_receber before insert or update on cozinhas_localizacao
for each row execute function sync_receber('lww');
create trigger trg_auditar after insert or update on cozinhas_localizacao
for each row execute function auditar_alteracao_tabela();

-- Para o cliente: só com o interruptor, a cozinha activa e a localização pública
create or replace function localizacao_cozinha(p_cozinha uuid)
returns table (cozinha_id uuid, nome text, morada text, horario text, lat double precision, lng double precision)
language sql stable security definer set search_path = public as $$
  select c.id, c.nome, l.morada, l.horario, l.lat, l.lng
    from cozinhas_localizacao l
    join cozinhas c on c.id = l.cozinha_id
   where l.cozinha_id = p_cozinha and l.publica and l.deletado_em is null
     and c.estado = 'activa' and c.deletado_em is null
     and funcionalidade_activa('como_chegar');
$$;

revoke execute on function localizacao_cozinha(uuid) from public, anon;
grant  execute on function localizacao_cozinha(uuid) to authenticated;
