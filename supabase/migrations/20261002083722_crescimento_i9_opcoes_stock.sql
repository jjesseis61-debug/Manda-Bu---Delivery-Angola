-- I9 · As opções dos pratos montáveis descontam stock.
-- Cada opção pode ter ingredientes (`componentes`, no mesmo formato da receita dos pratos base:
-- [{produto_id, quantidade, unidade}], por unidade do prato). Na venda gerada do pedido, o servidor
-- junta-os à receita: o mesmo produto soma-se, as regras de conversão, de "Longo Prazo" e de avisos
-- (stock_consumo_pendente) são as mesmas. Usa os ingredientes da opção no momento da venda.

alter table opcoes add column componentes jsonb not null default '[]'
  check (jsonb_typeof(componentes) = 'array' and jsonb_array_length(componentes) <= 20);
comment on column opcoes.componentes is
  'Ingredientes da opção por unidade do prato: [{produto_id, quantidade, unidade}]. Descontam stock na venda (I9).';

CREATE OR REPLACE FUNCTION public.consumir_stock_venda()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_componentes jsonb;
  v_opcoes      jsonb;
  c             record;
begin
  if new.stock_consumido_por <> 'servidor' or not new.movimenta_stock or coalesce(new.qtd, 0) <= 0 then
    return new;
  end if;
  -- Opções escolhidas no prato montado (I9): ingredientes de cada opção, por unidade do prato
  if new.pedido_id is not null and new.linha_pedido is not null then
    select coalesce(jsonb_agg(comp), '[]') into v_opcoes
      from pedidos x
      cross join jsonb_array_elements(coalesce(x.itens -> (new.linha_pedido - 1) -> 'opcoes', '[]')) e
      join opcoes o on o.id = (e ->> 'id')::uuid
      cross join jsonb_array_elements(o.componentes) comp
     where x.id = new.pedido_id;
  end if;
  if new.prato_base_id is null and coalesce(jsonb_array_length(v_opcoes), 0) = 0 then
    return new;
  end if;

  select componentes into v_componentes from pratos_base where id = new.prato_base_id;

  for c in
    with receita as (
      select (comp ->> 'produto_id')::uuid as produto_id, (comp ->> 'quantidade')::numeric as quantidade,
             comp ->> 'unidade' as unidade
        from jsonb_array_elements(coalesce(v_componentes, '[]')) comp
    ),
    excluidos as (
      select coalesce(x ->> 'produto_id', x #>> '{}')::uuid as produto_id
        from jsonb_array_elements(coalesce(new.componentes_excluidos, '[]')) x
    ),
    ajustados as (
      select (a ->> 'produto_id')::uuid as produto_id, (a ->> 'quantidade')::numeric as quantidade,
             a ->> 'unidade' as unidade
        from jsonb_array_elements(coalesce(new.componentes_ajustados, '[]')) a
    ),
    final as (
      select rc.produto_id,
             case when a.produto_id is not null then a.quantidade else rc.quantidade end as quantidade,
             case when a.produto_id is not null then a.unidade else rc.unidade end as unidade
        from receita rc left join ajustados a on a.produto_id = rc.produto_id
      union all
      select a.produto_id, a.quantidade, a.unidade
        from ajustados a
       where not exists (select 1 from receita rc where rc.produto_id = a.produto_id)
      union all
      -- Ingredientes mal escritos não podem travar a entrega: ficam como consumo pendente
      select case when comp ->> 'produto_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                  then (comp ->> 'produto_id')::uuid end,
             case when jsonb_typeof(comp -> 'quantidade') = 'number' then (comp ->> 'quantidade')::numeric end,
             comp ->> 'unidade'
        from jsonb_array_elements(coalesce(v_opcoes, '[]')) comp
    )
    select f.produto_id, bool_or(p.id is not null) as existe, max(p.tipo_estoque) as tipo_estoque,
           sum(quantidade_unidade_base(f.quantidade, f.unidade, p.categoria_medida)) * new.qtd as quantidade_base,
           bool_or(quantidade_unidade_base(f.quantidade, f.unidade, p.categoria_medida) is null) as desconhecida,
           string_agg(coalesce(f.unidade, ''), ', ') as unidade
      from final f
      left join produtos p on p.id = f.produto_id and p.deletado_em is null
     where f.produto_id is not null
       and not exists (select 1 from excluidos e where e.produto_id = f.produto_id)
     group by f.produto_id
  loop
    if not c.existe or c.tipo_estoque is null or c.desconhecida then
      perform registar_auditoria('stock_consumo_pendente', 'vendas', new.id,
        jsonb_build_object('produto_id', c.produto_id, 'unidade', c.unidade,
                           'motivo', case when not c.existe then 'produto_inexistente'
                                          when c.tipo_estoque is null then 'produto_sem_tipo_stock'
                                          else 'unidade_desconhecida' end));
    elsif c.tipo_estoque = 'Longo Prazo' and c.quantidade_base > 0 then
      insert into estoque_longo_prazo (dispositivo_id, sincronizado_em, data, cozinha_id, produto_id,
                                       tipo, quantidade, venda_id)
      values ('servidor', now(), new.data, new.cozinha_id, c.produto_id, 'Consumo', c.quantidade_base, new.id)
      on conflict (venda_id, produto_id) where venda_id is not null do nothing;
    end if;
    -- 'Diário': sem movimento por venda (fica para a reconciliação do dia)
  end loop;
  return new;
end $function$;
