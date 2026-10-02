-- I9 · Pratos montáveis: o cliente monta o prato escolhendo opções por grupo
-- (por exemplo Base: funge ou arroz; Acompanhamentos: até 2; Extras), cada opção
-- com o seu preço extra. Interruptor `pratos_montaveis` (desligado).
--
-- O servidor valida as escolhas (opções do próprio prato, disponíveis, mínimo e
-- máximo por grupo) e soma os extras ao preço. O nome do item no pedido leva as
-- opções entre parênteses, por isso a cozinha, a entrega e a venda gerada as
-- mostram sem mais alterações. As opções ainda não descontam stock (o prato base
-- continua a descontar).

insert into funcionalidades (chave, activa, dispositivo_id) values ('pratos_montaveis', false, 'servidor')
on conflict (chave) do nothing;

-- -----------------------------------------------------------------------------
-- 1. Grupos de opções e opções
-- -----------------------------------------------------------------------------
create table opcoes_grupos (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cardapio_id      uuid not null references cardapio(id),
  nome             text not null check (length(trim(nome)) between 1 and 60),
  minimo           integer not null default 0 check (minimo >= 0),
  maximo           integer not null default 1 check (maximo >= 1 and maximo <= 20),
  ordem            integer not null default 0,
  check (minimo <= maximo)
);
create index opcoes_grupos_cardapio_idx on opcoes_grupos (cardapio_id, ordem);
comment on table opcoes_grupos is
  'Sincronização: Last-write-wins com atualizado_em; escrita só com cozinhas.gerir. Grupos de escolha de um prato montável (I9).';

create table opcoes (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  grupo_id         uuid not null references opcoes_grupos(id),
  nome             text not null check (length(trim(nome)) between 1 and 60),
  preco_extra      integer not null default 0 check (preco_extra >= 0),
  disponivel       boolean not null default true,
  ordem            integer not null default 0
);
create index opcoes_grupo_idx on opcoes (grupo_id, ordem);
comment on table opcoes is
  'Sincronização: Last-write-wins com atualizado_em; escrita só com cozinhas.gerir. O preço extra soma ao prato no servidor (I9).';

alter table opcoes_grupos enable row level security;
alter table opcoes enable row level security;
create policy ler on opcoes_grupos for select to authenticated using (deletado_em is null or tem_permissao('cozinhas.gerir'));
create policy criar on opcoes_grupos for insert to authenticated with check (tem_permissao('cozinhas.gerir'));
create policy editar on opcoes_grupos for update to authenticated
  using (tem_permissao('cozinhas.gerir')) with check (tem_permissao('cozinhas.gerir'));
create policy ler on opcoes for select to authenticated using (deletado_em is null or tem_permissao('cozinhas.gerir'));
create policy criar on opcoes for insert to authenticated with check (tem_permissao('cozinhas.gerir'));
create policy editar on opcoes for update to authenticated
  using (tem_permissao('cozinhas.gerir')) with check (tem_permissao('cozinhas.gerir'));
grant select, insert, update on opcoes_grupos, opcoes to authenticated;

create trigger trg_sync_receber before insert or update on opcoes_grupos
for each row execute function sync_receber('lww');
create trigger trg_sync_receber before insert or update on opcoes
for each row execute function sync_receber('lww');
create trigger trg_auditar after insert or update on opcoes_grupos
for each row execute function auditar_alteracao_tabela();
create trigger trg_auditar after insert or update on opcoes
for each row execute function auditar_alteracao_tabela();

-- -----------------------------------------------------------------------------
-- 2. Validação das escolhas de um item
-- -----------------------------------------------------------------------------
-- p_opcoes: lista de ids (o que a app envia) ou de objectos com id (o que fica no pedido).
-- Devolve o preço extra, as opções escolhidas e o texto para o nome do item.
create or replace function opcoes_do_item(p_cardapio uuid, p_opcoes jsonb)
returns table (extra integer, opcoes jsonb, descricao text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_ids uuid[] := '{}';
  g     record;
  n     integer;
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
  return query
    select coalesce(sum(o.preco_extra), 0)::int,
           coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'nome', o.nome, 'preco_extra', o.preco_extra)
                              order by gr.ordem, gr.nome, o.ordem, o.nome), '[]'::jsonb),
           string_agg(o.nome, ', ' order by gr.ordem, gr.nome, o.ordem, o.nome)
      from opcoes o join opcoes_grupos gr on gr.id = o.grupo_id
     where o.id = any(v_ids);
end $$;

-- -----------------------------------------------------------------------------
-- 3. Orçamento e pedido: igual à versão da I8, mais as opções
-- -----------------------------------------------------------------------------
create or replace function orcamento_pedido(p_itens jsonb, p_ponto_entrega uuid, p_cozinha uuid default null,
                                            p_grupo uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $function$
declare
  v_cliente  uuid := cliente_actual();
  v_cozinha  uuid;
  v_item     jsonb;
  v_qtd      numeric;
  v_card     cardapio;
  v_itens    jsonb := '[]';
  v_subtotal integer := 0;
  v_ponto    pontos_entrega;
  v_zona     zonas;
  v_taxa     integer := 0;
  v_desc     record;
  v_desconto integer;
  v_grupo    pedidos_grupo;
  v_estimada integer;
  v_extra    integer;
  v_opcoes   jsonb;
  v_texto    text;
  v_preco    integer;
begin
  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'pedido_vazio' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_itens) > 30 then
    raise exception 'itens_a_mais' using errcode = 'P0001';
  end if;

  -- Cozinha do pedido (I8): a do grupo; senão a escolhida pelo cliente (com multi_cozinha);
  -- senão a cozinha por defeito. Tem de estar activa para aceitar pedidos.
  if p_grupo is not null then
    v_grupo := grupo_para_adesao(p_grupo);
    v_cozinha := v_grupo.cozinha_id;
  elsif funcionalidade_activa('multi_cozinha') then
    v_cozinha := coalesce(p_cozinha, cozinha_padrao());
  else
    v_cozinha := cozinha_padrao();
  end if;
  if not cozinha_aceita_pedidos(v_cozinha) then
    raise exception 'cozinha_indisponivel' using errcode = 'P0001';
  end if;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    begin
      v_qtd := (v_item ->> 'qtd')::numeric;
      select * into v_card from cardapio
       where id = (v_item ->> 'cardapio_id')::uuid and deletado_em is null;
    exception when invalid_text_representation then
      raise exception 'item_indisponivel' using errcode = 'P0001';
    end;
    if v_qtd is null or v_qtd <> trunc(v_qtd) or v_qtd < 1 or v_qtd > 50 then
      raise exception 'quantidade_invalida' using errcode = 'P0001';
    end if;
    if v_card.id is null or not v_card.disponivel or v_card.cozinha_id <> v_cozinha then
      raise exception 'item_indisponivel' using errcode = 'P0001', detail = v_item ->> 'cardapio_id';
    end if;
    -- Prato montado (I9): as opções escolhidas validam-se e somam ao preço
    v_extra := 0; v_opcoes := null; v_texto := null;
    if funcionalidade_activa('pratos_montaveis') then
      select o.extra, o.opcoes, o.descricao into v_extra, v_opcoes, v_texto
        from opcoes_do_item(v_card.id, v_item -> 'opcoes') o;
    end if;
    v_preco := v_card.preco + coalesce(v_extra, 0);
    v_itens := v_itens || jsonb_strip_nulls(jsonb_build_object(
      'cardapio_id', v_card.id,
      'prato_base_id', v_card.prato_base_id,
      'nome', v_card.nome || coalesce(' (' || v_texto || ')', ''),
      'qtd', v_qtd::int,
      'preco_unitario', v_preco,
      'opcoes', case when v_texto is not null then v_opcoes end,
      'componentes_excluidos', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_excluidos', 'null') end,
      'componentes_ajustados', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_ajustados', 'null') end));
    v_subtotal := v_subtotal + v_qtd::int * v_preco;
    v_card := null;
  end loop;

  -- Pedido de grupo (I6): o ponto é o do grupo; a taxa da entrega única é repartida no
  -- fecho do grupo (fechar_grupo_interno), por isso aqui fica 0 e devolve-se a estimativa.
  if p_grupo is not null then
    select * into v_ponto from pontos_entrega where id = v_grupo.ponto_entrega_id;
    select * into v_zona from zonas where id = v_ponto.zona_id and deletado_em is null;
    if not found then
      raise exception 'ponto_sem_zona' using errcode = 'P0001';
    end if;
    v_estimada := taxa_grupo_estimada(p_grupo, v_cliente);
  else
    if p_ponto_entrega is null then
      raise exception 'ponto_obrigatorio' using errcode = 'P0001';
    end if;
    select * into v_ponto from pontos_entrega where id = p_ponto_entrega and deletado_em is null;
    if not found
       or (v_cliente is not null
           and v_ponto.criado_por_cliente is distinct from v_cliente
           and not exists (select 1 from enderecos_cliente e
                            where e.ponto_entrega_id = v_ponto.id and e.cliente_id = v_cliente
                              and e.deletado_em is null)) then
      raise exception 'ponto_invalido' using errcode = 'P0001';
    end if;
    select * into v_zona from zonas where id = v_ponto.zona_id and deletado_em is null;
    if not found then
      raise exception 'ponto_sem_zona' using errcode = 'P0001';
    end if;
    v_taxa := round(coalesce(v_zona.taxa, 0))::int;
  end if;

  select * into v_desc from avaliar_desconto_indicacao(v_cliente, v_ponto.id);
  -- O desconto nunca passa o valor do pedido (subtotal + taxa)
  v_desconto := least(coalesce(v_desc.valor, 0), v_subtotal + v_taxa);

  return jsonb_build_object(
    'itens', v_itens,
    'subtotal', v_subtotal,
    'zona_id', v_zona.id,
    'zona_nome', v_zona.nome,
    'taxa_entrega', v_taxa,
    'desconto', v_desconto,
    'motivo_desconto', v_desc.motivo,
    'total', v_subtotal + v_taxa - v_desconto,
    'taxa_grupo_estimada', v_estimada);
end $function$;

revoke execute on function opcoes_do_item(uuid, jsonb) from public, anon, authenticated;
revoke execute on function orcamento_pedido(jsonb, uuid, uuid, uuid) from public, anon;
grant  execute on function orcamento_pedido(jsonb, uuid, uuid, uuid) to authenticated;
