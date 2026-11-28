-- Feira (consignação): pratos de preço fixo, vendidos fora da app, por um feirante.
--
-- Fluxo: a cozinha cria uma feira para um feirante, carrega N pratos (preço fixo copiado do
-- cardápio), o feirante vende no local (ao vivo quando há rede, ou lançado no acerto do fecho) e,
-- no regresso, faz o acerto: vendidos (dinheiro/transferência), devolvidos e perdas. O sistema
-- reconcilia (esperado vs recebido). Permissão `feira.gerir`, sempre por cozinha.
--
-- Importante (sem dupla contagem): os pratos saem fisicamente da cozinha na carga; a "carga" É o
-- inventário de pratos prontos da feira. Não se mexe no stock de ingredientes (consumido ao cozinhar).
--
-- Visibilidade: os pratos de feira ficam com cardapio.visivel_online = false e NUNCA aparecem online.
--
-- Segurança: as tabelas têm RLS e nenhum acesso directo das apps (revoke all); tudo passa pelas
-- funções SECURITY DEFINER, gated por feira.gerir + pode_na_cozinha. Online-only (sem fila offline):
-- com rede regista-se ao vivo; sem rede, lança-se no acerto do fecho — a mesma matemática.

-- -----------------------------------------------------------------------------
-- 1. Permissão nova no catálogo
-- -----------------------------------------------------------------------------
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'feira.gerir', 'Feira',
   'Criar feiras, registar vendas no local e fazer o acerto no regresso')
on conflict (chave) do nothing;

-- -----------------------------------------------------------------------------
-- 2. Pratos escondidos do online
-- -----------------------------------------------------------------------------
alter table cardapio add column visivel_online boolean not null default true;
comment on column cardapio.visivel_online is
  'false = prato só de feira (consignação); não aparece aos clientes online.';

-- -----------------------------------------------------------------------------
-- 3. Tabelas (trancadas: só as funções SECURITY DEFINER acedem)
-- -----------------------------------------------------------------------------
create table feiras (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cozinha_id       uuid not null references cozinhas(id),
  vendedor_id      uuid not null references funcionarios(id),
  nome             text not null,
  data_saida       timestamptz not null default now(),
  estado           text not null default 'aberta' check (estado in ('aberta','fechada')),
  fechada_em       timestamptz,
  criado_por       uuid references funcionarios(id)
);
create index feiras_cozinha_idx  on feiras (cozinha_id, estado);
create index feiras_vendedor_idx on feiras (vendedor_id);
create index feiras_criado_idx   on feiras (criado_por);
alter table feiras enable row level security;
revoke all on feiras from anon, authenticated;

create table feira_itens (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  feira_id         uuid not null references feiras(id) on delete cascade,
  cardapio_id      uuid references cardapio(id),
  nome             text not null,
  preco_unit       integer not null check (preco_unit > 0),
  qtd_levada       integer not null check (qtd_levada > 0),
  qtd_vendida      integer not null default 0 check (qtd_vendida >= 0),
  qtd_devolvida    integer not null default 0 check (qtd_devolvida >= 0),
  qtd_perda        integer not null default 0 check (qtd_perda >= 0),
  check (qtd_vendida + qtd_devolvida + qtd_perda <= qtd_levada)
);
create index feira_itens_feira_idx    on feira_itens (feira_id);
create index feira_itens_cardapio_idx on feira_itens (cardapio_id);
alter table feira_itens enable row level security;
revoke all on feira_itens from anon, authenticated;

create table feira_vendas (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  feira_id         uuid not null references feiras(id) on delete cascade,
  item_id          uuid not null references feira_itens(id),
  qtd              integer not null check (qtd > 0),
  valor            integer not null check (valor >= 0),
  metodo           text not null check (metodo in ('dinheiro','transferencia')),
  referencia       text,
  lat              double precision check (lat is null or lat between -90 and 90),
  lng              double precision check (lng is null or lng between -180 and 180),
  vendido_em       timestamptz not null default now(),
  vendido_por      uuid references funcionarios(id)
);
create index feira_vendas_feira_idx    on feira_vendas (feira_id);
create index feira_vendas_item_idx     on feira_vendas (item_id);
create index feira_vendas_vendedor_idx on feira_vendas (vendido_por);
alter table feira_vendas enable row level security;
revoke all on feira_vendas from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4. API (SECURITY DEFINER, gated por feira.gerir + pode_na_cozinha)
-- -----------------------------------------------------------------------------
-- Criar uma feira para um feirante
create or replace function criar_feira(p_cozinha uuid, p_vendedor uuid, p_nome text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('feira.gerir');
  v_id   uuid;
begin
  if not pode_na_cozinha('feira.gerir', p_cozinha) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'feira.gerir';
  end if;
  if coalesce(btrim(p_nome), '') = '' then
    raise exception 'nome_obrigatorio' using errcode = 'P0001';
  end if;
  if not exists (select 1 from funcionarios where id = p_vendedor and deletado_em is null) then
    raise exception 'vendedor_inexistente' using errcode = 'P0001';
  end if;
  insert into feiras (cozinha_id, vendedor_id, nome, criado_por, dispositivo_id)
  values (p_cozinha, p_vendedor, btrim(p_nome), v_func, 'servidor')
  returning id into v_id;
  perform registar_auditoria('feira_criada', 'feiras', v_id);
  return v_id;
end $$;

-- Carregar um prato na feira (preço fixo copiado do cardápio da mesma cozinha)
create or replace function feira_adicionar_item(p_feira uuid, p_cardapio uuid, p_qtd integer)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_fe  feiras;
  v_ca  cardapio;
  v_id  uuid;
begin
  perform exigir_permissao('feira.gerir');
  select * into v_fe from feiras where id = p_feira and deletado_em is null;
  if not found or v_fe.estado <> 'aberta' or not pode_na_cozinha('feira.gerir', v_fe.cozinha_id) then
    raise exception 'feira_invalida' using errcode = 'P0001';
  end if;
  if p_qtd is null or p_qtd <= 0 then
    raise exception 'quantidade_invalida' using errcode = 'P0001';
  end if;
  select * into v_ca from cardapio where id = p_cardapio and cozinha_id = v_fe.cozinha_id and deletado_em is null;
  if not found then
    raise exception 'prato_inexistente' using errcode = 'P0001';
  end if;
  insert into feira_itens (feira_id, cardapio_id, nome, preco_unit, qtd_levada, dispositivo_id)
  values (p_feira, v_ca.id, v_ca.nome, v_ca.preco, p_qtd, 'servidor')
  returning id into v_id;
  return v_id;
end $$;

-- Registar uma venda no local (ao vivo). Devolve quantas unidades ainda restam do item.
create or replace function feira_vender(p_item uuid, p_qtd integer, p_metodo text,
                                        p_referencia text default null,
                                        p_lat double precision default null,
                                        p_lng double precision default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('feira.gerir');
  v_it   feira_itens;
  v_fe   feiras;
  v_rest integer;
begin
  select * into v_it from feira_itens where id = p_item and deletado_em is null;
  if not found then raise exception 'item_inexistente' using errcode = 'P0001'; end if;
  select * into v_fe from feiras where id = v_it.feira_id;
  if v_fe.estado <> 'aberta' or not pode_na_cozinha('feira.gerir', v_fe.cozinha_id) then
    raise exception 'feira_invalida' using errcode = 'P0001';
  end if;
  if p_qtd is null or p_qtd <= 0 then raise exception 'quantidade_invalida' using errcode = 'P0001'; end if;
  if p_metodo not in ('dinheiro','transferencia') then raise exception 'metodo_invalido' using errcode = 'P0001'; end if;
  if v_it.qtd_vendida + v_it.qtd_devolvida + v_it.qtd_perda + p_qtd > v_it.qtd_levada then
    raise exception 'sem_unidades' using errcode = 'P0001';
  end if;
  insert into feira_vendas (feira_id, item_id, qtd, valor, metodo, referencia, lat, lng, vendido_por, dispositivo_id)
  values (v_it.feira_id, v_it.id, p_qtd, p_qtd * v_it.preco_unit, p_metodo, nullif(btrim(coalesce(p_referencia,'')), ''),
          p_lat, p_lng, v_func, 'servidor');
  update feira_itens set qtd_vendida = qtd_vendida + p_qtd, atualizado_em = now() where id = v_it.id;
  select qtd_levada - qtd_vendida - qtd_devolvida - qtd_perda into v_rest from feira_itens where id = v_it.id;
  return v_rest;
end $$;

-- Acerto/fecho: define devolvidos e perdas por item e fecha a feira.
-- p_acertos = [{"item_id": uuid, "devolvida": int, "perda": int}, ...]
create or replace function feira_fechar(p_feira uuid, p_acertos jsonb default '[]'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_fe feiras;
  v_a  jsonb;
begin
  perform exigir_permissao('feira.gerir');
  select * into v_fe from feiras where id = p_feira and deletado_em is null;
  if not found or v_fe.estado <> 'aberta' or not pode_na_cozinha('feira.gerir', v_fe.cozinha_id) then
    raise exception 'feira_invalida' using errcode = 'P0001';
  end if;
  for v_a in select * from jsonb_array_elements(coalesce(p_acertos, '[]'::jsonb)) loop
    update feira_itens
       set qtd_devolvida = coalesce((v_a ->> 'devolvida')::int, qtd_devolvida),
           qtd_perda     = coalesce((v_a ->> 'perda')::int, qtd_perda),
           atualizado_em = now()
     where id = (v_a ->> 'item_id')::uuid and feira_id = p_feira;
  end loop;
  -- A constraint de cada item garante vendida+devolvida+perda <= levada
  update feiras set estado = 'fechada', fechada_em = now(), atualizado_em = now() where id = p_feira;
  perform registar_auditoria('feira_fechada', 'feiras', p_feira);
end $$;

-- Resumo/detalhe de uma feira: itens + totais + reconciliação (esperado vs recebido)
create or replace function feira_resumo(p_feira uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_fe       feiras;
  v_itens    jsonb;
  v_esperado integer;
  v_dinheiro integer;
  v_transf   integer;
begin
  select * into v_fe from feiras where id = p_feira and deletado_em is null;
  if not found or not pode_na_cozinha('feira.gerir', v_fe.cozinha_id) then
    raise exception 'feira_invalida' using errcode = 'P0001';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'item_id', i.id, 'nome', i.nome, 'preco_unit', i.preco_unit,
           'levada', i.qtd_levada, 'vendida', i.qtd_vendida,
           'devolvida', i.qtd_devolvida, 'perda', i.qtd_perda,
           'restante', i.qtd_levada - i.qtd_vendida - i.qtd_devolvida - i.qtd_perda) order by i.criado_em), '[]'::jsonb),
         coalesce(sum(i.qtd_vendida * i.preco_unit), 0)
    into v_itens, v_esperado
    from feira_itens i where i.feira_id = p_feira and i.deletado_em is null;
  select coalesce(sum(valor) filter (where metodo = 'dinheiro'), 0),
         coalesce(sum(valor) filter (where metodo = 'transferencia'), 0)
    into v_dinheiro, v_transf
    from feira_vendas where feira_id = p_feira and deletado_em is null;
  return jsonb_build_object(
    'id', v_fe.id, 'nome', v_fe.nome, 'estado', v_fe.estado,
    'cozinha_id', v_fe.cozinha_id, 'vendedor_id', v_fe.vendedor_id,
    'data_saida', v_fe.data_saida, 'fechada_em', v_fe.fechada_em,
    'itens', v_itens,
    'esperado', v_esperado, 'recebido_dinheiro', v_dinheiro, 'recebido_transferencia', v_transf,
    'recebido', v_dinheiro + v_transf, 'diferenca', (v_dinheiro + v_transf) - v_esperado);
end $$;

-- Lista das feiras de uma cozinha (recentes primeiro)
create or replace function listar_feiras(p_cozinha uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not pode_na_cozinha('feira.gerir', p_cozinha) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'feira.gerir';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', f.id, 'nome', f.nome, 'estado', f.estado, 'data_saida', f.data_saida,
             'vendedor', (select nome from funcionarios fu where fu.id = f.vendedor_id),
             'esperado', (select coalesce(sum(i.qtd_vendida * i.preco_unit), 0)
                            from feira_itens i where i.feira_id = f.id and i.deletado_em is null))
           order by f.data_saida desc)
      from feiras f where f.cozinha_id = p_cozinha and f.deletado_em is null), '[]'::jsonb);
end $$;

revoke execute on function criar_feira(uuid, uuid, text) from public, anon;
revoke execute on function feira_adicionar_item(uuid, uuid, integer) from public, anon;
revoke execute on function feira_vender(uuid, integer, text, text, double precision, double precision) from public, anon;
revoke execute on function feira_fechar(uuid, jsonb) from public, anon;
revoke execute on function feira_resumo(uuid) from public, anon;
revoke execute on function listar_feiras(uuid) from public, anon;
grant  execute on function criar_feira(uuid, uuid, text) to authenticated;
grant  execute on function feira_adicionar_item(uuid, uuid, integer) to authenticated;
grant  execute on function feira_vender(uuid, integer, text, text, double precision, double precision) to authenticated;
grant  execute on function feira_fechar(uuid, jsonb) to authenticated;
grant  execute on function feira_resumo(uuid) to authenticated;
grant  execute on function listar_feiras(uuid) to authenticated;
