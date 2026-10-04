-- Pratos montáveis (regras de negócio, secção 2): o cliente pode tirar ingredientes da receita do prato por
-- escolha, e o que tira nunca é cobrado. O valor de cada ingrediente segue a secção 1: preço final por unidade de
-- compra = custo × (1 + margem%) × (1 + IVA% se aplicável), proporcional à quantidade da receita (na unidade base).
-- Sem produto, custo ou unidade conhecida o ingrediente vale 0 (não desconta). Os ajustes de quantidade deixam de
-- ser aceites da app do cliente (não tem como os pedir nem como os pagar). O stock já não desconta os excluídos.
-- O preço de um prato do cardápio pode ser 0 quando vem todo das opções (ex.: "Monta o teu prato"); o orçamento
-- recusa um item que fique a 0 Kz sem opções que lhe dêem preço.
-- Tudo só com o interruptor pratos_montaveis.

alter table cardapio drop constraint cardapio_preco_check;
alter table cardapio add constraint cardapio_preco_check check (preco >= 0);

-- Valor de um ingrediente na quantidade da receita (Kz, arredondado); 0 quando não se sabe calcular
create or replace function valor_componente(p_produto uuid, p_quantidade numeric, p_unidade text) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce((
    select round(quantidade_unidade_base(p_quantidade, p_unidade, p.categoria_medida)
                 / nullif(quantidade_unidade_base(1, p.unidade_compra, p.categoria_medida), 0)
                 * p.custo * (1 + coalesce(p.margem, 0) / 100)
                 * (1 + case when p.iva_aplicavel then coalesce(p.iva, 0) / 100 else 0 end))::int
      from produtos p
     where p.id = p_produto and p.deletado_em is null and p.custo is not null), 0);
$$;
revoke execute on function valor_componente(uuid, numeric, text) from public, anon, authenticated;

-- Ingredientes que o cliente pode tirar de cada prato (só os da receita, com o valor que deixa de pagar)
create or replace function componentes_dos_pratos(p_cardapio uuid[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'cardapio_id', c.id, 'produto_id', p.id, 'nome', p.nome,
           'quantidade', (k.comp ->> 'quantidade')::numeric, 'unidade', k.comp ->> 'unidade',
           'valor', valor_componente(p.id, (k.comp ->> 'quantidade')::numeric, k.comp ->> 'unidade'))
           order by c.id, k.ord), '[]')
    from cardapio c
    join pratos_base pb on pb.id = c.prato_base_id and pb.deletado_em is null
    cross join jsonb_array_elements(pb.componentes) with ordinality k(comp, ord)
    join produtos p on p.id::text = k.comp ->> 'produto_id' and p.deletado_em is null
   where c.id = any(p_cardapio) and c.deletado_em is null and cardinality(p_cardapio) <= 100
     and jsonb_typeof(k.comp -> 'quantidade') = 'number';
$$;
revoke execute on function componentes_dos_pratos(uuid[]) from public, anon;
grant execute on function componentes_dos_pratos(uuid[]) to authenticated;

-- Valida os ingredientes a tirar (da receita, sem repetir, sem tirar todos) e devolve o desconto e os nomes
create or replace function excluir_componentes(p_prato_base uuid, p_excluidos jsonb)
returns table (excluidos uuid[], desconto integer, nomes text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_ids uuid[];
  v_receita int;
begin
  if jsonb_typeof(p_excluidos) <> 'array' or jsonb_array_length(p_excluidos) > 30 then
    raise exception 'componentes_invalidos' using errcode = 'P0001';
  end if;
  begin
    select coalesce(array_agg(coalesce(e ->> 'produto_id', e #>> '{}')::uuid), '{}') into v_ids
      from jsonb_array_elements(p_excluidos) e;
  exception when invalid_text_representation then
    raise exception 'componentes_invalidos' using errcode = 'P0001';
  end;
  if cardinality(v_ids) = 0 then
    return query select '{}'::uuid[], 0, null::text;
    return;
  end if;
  if cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception 'componentes_invalidos' using errcode = 'P0001';
  end if;
  select count(*) into v_receita from pratos_base pb, jsonb_array_elements(pb.componentes) k where pb.id = p_prato_base;
  if exists (select 1 from unnest(v_ids) x
              where not exists (select 1 from pratos_base pb, jsonb_array_elements(pb.componentes) k
                                 where pb.id = p_prato_base and k ->> 'produto_id' = x::text)) then
    raise exception 'componentes_invalidos' using errcode = 'P0001';
  end if;
  if cardinality(v_ids) >= v_receita then
    raise exception 'componentes_todos_excluidos' using errcode = 'P0001';
  end if;
  return query
    select v_ids,
           coalesce(sum(valor_componente((k.comp ->> 'produto_id')::uuid,
                                         case when jsonb_typeof(k.comp -> 'quantidade') = 'number' then (k.comp ->> 'quantidade')::numeric end,
                                         k.comp ->> 'unidade')), 0)::int,
           string_agg(coalesce(p.nome, 'ingrediente'), ', ' order by k.ord)
      from pratos_base pb
      cross join jsonb_array_elements(pb.componentes) with ordinality k(comp, ord)
      left join produtos p on p.id::text = k.comp ->> 'produto_id'
     where pb.id = p_prato_base and (k.comp ->> 'produto_id')::uuid = any(v_ids);
end $$;
revoke execute on function excluir_componentes(uuid, jsonb) from public, anon, authenticated;

create or replace function orcamento_pedido(p_itens jsonb, p_ponto_entrega uuid, p_cozinha uuid DEFAULT NULL::uuid, p_grupo uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_motivo   text;
  v_grupo    pedidos_grupo;
  v_estimada integer;
  v_extra    integer;
  v_opcoes   jsonb;
  v_texto    text;
  v_preco    integer;
  v_excl     uuid[];
  v_desc_comp integer;
  v_sem      text;
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
    -- Um prato a 0 Kz só é válido com opções escolhidas que lhe dêem preço (ex.: "Monta o teu prato")
    if v_preco <= 0 then
      raise exception 'item_sem_preco' using errcode = 'P0001', detail = v_card.nome;
    end if;
    -- Componentes que o cliente tira por escolha: nunca são cobrados (regra 2); o valor de cada um vem do
    -- custo, margem e IVA do produto (regra 1). Os ajustes de quantidade não são aceites da app do cliente.
    v_excl := null; v_desc_comp := 0; v_sem := null;
    if funcionalidade_activa('pratos_montaveis') and v_card.prato_base_id is not null
       and coalesce(jsonb_typeof(v_item -> 'componentes_excluidos'), 'null') <> 'null' then
      select r.excluidos, r.desconto, r.nomes into v_excl, v_desc_comp, v_sem
        from excluir_componentes(v_card.prato_base_id, v_item -> 'componentes_excluidos') r;
      v_preco := greatest(v_preco - v_desc_comp, 0);
    end if;
    v_itens := v_itens || jsonb_strip_nulls(jsonb_build_object(
      'cardapio_id', v_card.id,
      'prato_base_id', v_card.prato_base_id,
      'nome', v_card.nome || coalesce(' (' || nullif(concat_ws('; ', v_texto, 'sem ' || v_sem), '') || ')', ''),
      'qtd', v_qtd::int,
      'preco_unitario', v_preco,
      'opcoes', case when v_texto is not null then v_opcoes end,
      'componentes_excluidos', case when cardinality(v_excl) > 0 then to_jsonb(v_excl) end,
      'desconto_componentes', nullif(v_desc_comp, 0)));
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
  v_motivo := v_desc.motivo;
  -- O desconto de boas-vindas só vale a partir do subtotal mínimo (sai da margem dos pratos)
  if v_desconto > 0 and v_subtotal < (select desconto_subtotal_minimo from parametros where unico) then
    v_desconto := 0;
    v_motivo := 'pedido_minimo';
  end if;

  return jsonb_build_object(
    'itens', v_itens,
    'subtotal', v_subtotal,
    'zona_id', v_zona.id,
    'zona_nome', v_zona.nome,
    'taxa_entrega', v_taxa,
    'desconto', v_desconto,
    'motivo_desconto', v_motivo,
    'desconto_subtotal_minimo', (select desconto_subtotal_minimo from parametros where unico),
    'total', v_subtotal + v_taxa - v_desconto,
    'taxa_grupo_estimada', v_estimada);
end $function$;
