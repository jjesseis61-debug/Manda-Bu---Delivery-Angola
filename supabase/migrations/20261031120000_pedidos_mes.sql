-- Prova social por prato: "X pessoas pediram este mês".
-- Conta clientes DISTINTOS com pedido entregue e pago (estado 'entregue_pago') nos últimos
-- 30 dias, por prato do cardápio. É pré-calculado 1x/dia por pg_cron — contar nos pedidos.itens
-- (jsonb) a cada abertura do cardápio seria caro. Fica numa tabela à parte (cardapio_popularidade)
-- para NÃO disparar o trigger de auditoria do cardapio em cada atualização diária.

-- Limiar próprio: abaixo disto não se mostra o número (evita "3 pediram" em pratos novos).
alter table parametros add column if not exists limiar_pediram int not null default 20;

create table if not exists cardapio_popularidade (
  cardapio_id   uuid primary key references cardapio(id) on delete cascade,
  pessoas       int not null default 0,
  atualizado_em timestamptz not null default now()
);

alter table cardapio_popularidade enable row level security;
revoke all on cardapio_popularidade from anon, authenticated;
grant select on cardapio_popularidade to authenticated;
-- É só um agregado (uma contagem), não expõe ninguém; o cliente lê-o junto do cardápio.
drop policy if exists ler on cardapio_popularidade;
create policy ler on cardapio_popularidade for select to authenticated using (true);

-- Recalcula do zero: limpa e reinsere os pratos com pelo menos 1 pessoa nos últimos 30 dias.
create or replace function job_pedidos_mes() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from cardapio_popularidade;
  insert into cardapio_popularidade (cardapio_id, pessoas, atualizado_em)
  select c.id, count(distinct p.cliente_id), now()
    from pedidos p
    cross join lateral jsonb_array_elements(p.itens) it
    join cardapio c on c.id = (it ->> 'cardapio_id')::uuid
   where p.estado = 'entregue_pago'
     and p.deletado_em is null
     and p.criado_em >= now() - interval '30 days'
   group by c.id;
end $$;

revoke execute on function job_pedidos_mes() from public, anon, authenticated;

-- Agendar 1x/dia às 04:00 (hora do servidor), se o pg_cron existir.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_pedidos_mes', '0 4 * * *', 'select public.job_pedidos_mes()');
  end if;
end $$;

-- Preencher já, para não ficar tudo a 0 até ao primeiro job.
select job_pedidos_mes();
