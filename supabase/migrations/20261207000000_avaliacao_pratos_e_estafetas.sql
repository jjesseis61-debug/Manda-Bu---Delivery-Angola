-- =============================================================================
-- Correções do teste do dia completo (19/11/2026)
-- -----------------------------------------------------------------------------
-- 1. Estrelas por prato: a avaliação de cada prato, as médias por prato na app e o analista usam o
--    «prato base» do prato. Os pratos criados no cardápio não tinham prato base (em produção: 32 de
--    32), por isso o ecrã «Avaliar» só mostrava a nota geral e as médias por prato ficavam vazias.
--    Agora cada prato sem prato base ganha um seu (mesmo nome, mesma cozinha, sem ingredientes:
--    não mexe no stock nem nos montáveis), ao ser criado e, uma vez, os que já existem.
--    O nome acompanha o prato quando ele muda de nome (se o prato base for só dele).
--    Vale para os pedidos feitos daqui para a frente (os antigos guardaram o prato sem prato base).
-- 2. Lista de estafetas para atribuir uma entrega: o administrador principal tem todas as
--    permissões e aparecia como estafeta. Passa a aparecer só se lhe derem a permissão de entregas
--    de propósito (na direcção ou nas permissões extra).
-- =============================================================================

-- 1. Prato base automático ---------------------------------------------------------------------
create or replace function cardapio_prato_base_automatico() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.prato_base_id is null then
    insert into pratos_base (dispositivo_id, sincronizado_em, nome, cozinha_id)
    values ('servidor', now(), btrim(new.nome), new.cozinha_id)
    returning id into new.prato_base_id;
  end if;
  return new;
end $$;
revoke execute on function cardapio_prato_base_automatico() from public, anon, authenticated;

drop trigger if exists trg_0_prato_base on cardapio;
create trigger trg_0_prato_base before insert on cardapio
  for each row execute function cardapio_prato_base_automatico();

-- O prato muda de nome: o prato base (se for só dele) acompanha
create or replace function cardapio_nome_prato_base() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.prato_base_id is not null and new.nome is distinct from old.nome
     and not exists (select 1 from cardapio c where c.prato_base_id = new.prato_base_id and c.id <> new.id) then
    update pratos_base set nome = btrim(new.nome), atualizado_em = now() where id = new.prato_base_id;
  end if;
  return new;
end $$;
revoke execute on function cardapio_nome_prato_base() from public, anon, authenticated;

drop trigger if exists trg_prato_base_nome on cardapio;
create trigger trg_prato_base_nome after update of nome on cardapio
  for each row execute function cardapio_nome_prato_base();

-- Os pratos que já existem sem prato base (uma vez; idempotente)
do $$
declare c record; v uuid;
begin
  for c in select id, nome, cozinha_id from cardapio where prato_base_id is null loop
    insert into pratos_base (dispositivo_id, sincronizado_em, nome, cozinha_id)
    values ('servidor', now(), btrim(c.nome), c.cozinha_id) returning id into v;
    update cardapio set prato_base_id = v where id = c.id;
  end loop;
end $$;

-- 2. Estafetas para atribuir: o administrador principal só com a permissão dada de propósito ------
create or replace function estafetas_para_atribuir(p_cozinha uuid)
returns table(funcionario_id uuid, nome text, a_levar integer, online boolean)
language sql stable security definer set search_path = public as $$
  select f.id, f.nome,
         (select count(*) from pedidos p
           where p.entregador_id = f.id and p.estado = 'em_entrega' and p.deletado_em is null)::int,
         exists (select 1 from posicoes_entregadores pe
                  where pe.funcionario_id = f.id and pe.atualizado_em > now() - interval '2 minutes')
    from funcionarios f
    left join direcoes d on d.id = f.direcao_id and d.deletado_em is null
   where f.deletado_em is null and tem_permissao_de(f.id, 'entregas.registar')
     and (not coalesce(f.administrador_principal, false)
          or coalesce((f.permissoes_extra ->> 'entregas.registar')::boolean, false)
          or coalesce((d.permissoes ->> 'entregas.registar')::boolean, false))
     and pode_na_cozinha('pedidos.gerir', p_cozinha)  -- barreira: só gerente da cozinha vê a lista
   order by (select count(*) from pedidos p
              where p.entregador_id = f.id and p.estado = 'em_entrega' and p.deletado_em is null), f.nome;
$$;
