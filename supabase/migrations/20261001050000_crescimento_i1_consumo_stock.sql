-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I1 · Consumo de stock das vendas de pedidos
--
-- Regra 3 (consumo): o servidor desconta o stock SÓ das vendas que ele próprio
-- gera a partir de pedidos da app do cliente. As vendas registadas pela app do
-- operador continuam a ser descontadas pela própria app; o servidor nunca lhes
-- toca. Cada venda tem um único responsável pelo desconto (vendas.stock_consumido_por).
--
--   1. Itens do pedido validados na criação: prato_base_id tem de existir e não
--      estar apagado; componentes excluídos/ajustados só com prato e bem formados.
--   2. vendas.stock_consumido_por ('dispositivo' | 'servidor'); um dispositivo
--      nunca consegue marcar 'servidor' nem mudar o valor depois.
--   3. estoque_longo_prazo.venda_id, único com produto_id: o mesmo consumo
--      nunca é registado duas vezes.
--   4. Conversão para a unidade base (g, ml, unidade).
--   5. gerar_venda_pedido copia os componentes do item e marca 'servidor'.
--   6. Trigger de consumo em vendas:
--        receita (pratos_base.componentes) − excluídos, com os ajustados;
--        só produtos 'Longo Prazo' (os 'Diário' ficam para a reconciliação);
--        quantidade × qtd da venda, convertida para a unidade base;
--        movimento 'Consumo' na cozinha da venda.
--      Componente com unidade desconhecida, produto inexistente ou sem tipo de
--      stock: a venda passa e fica um aviso na auditoria (stock_consumo_pendente).
--      Vendas com movimenta_stock = false (compensações de estorno) não descontam
--      nem repõem stock.
--
-- Formatos no item do pedido (e na venda):
--   componentes_excluidos: [produto_id, …]  (ou [{produto_id}, …])
--   componentes_ajustados: [{produto_id, quantidade, unidade}, …]
--     substitui a quantidade da receita para esse produto; se o produto não
--     estiver na receita, é acrescentado.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Validação dos itens do pedido
-- -----------------------------------------------------------------------------
create or replace function pedidos_validar_itens() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_item  jsonb;
  v_prato uuid;
  v_n     int := 0;
begin
  if tg_op = 'UPDATE' and new.itens is not distinct from old.itens then
    return new;
  end if;
  if jsonb_typeof(new.itens) is distinct from 'array' then
    raise exception 'itens_invalidos' using errcode = 'P0001';
  end if;

  for v_item in select * from jsonb_array_elements(new.itens) loop
    v_n := v_n + 1;
    v_prato := null;

    if jsonb_typeof(v_item -> 'prato_base_id') = 'string' then
      begin
        v_prato := (v_item ->> 'prato_base_id')::uuid;
      exception when invalid_text_representation then
        raise exception 'prato_invalido' using errcode = 'P0001',
          detail = format('item %s: %s', v_n, v_item ->> 'prato_base_id');
      end;
      if not exists (select 1 from pratos_base where id = v_prato and deletado_em is null) then
        raise exception 'prato_invalido' using errcode = 'P0001',
          detail = format('item %s: %s', v_n, v_prato);
      end if;
    elsif v_item ? 'prato_base_id' and jsonb_typeof(v_item -> 'prato_base_id') <> 'null' then
      raise exception 'prato_invalido' using errcode = 'P0001', detail = format('item %s', v_n);
    end if;

    if coalesce(jsonb_typeof(v_item -> 'componentes_excluidos'), 'null') <> 'null'
       or coalesce(jsonb_typeof(v_item -> 'componentes_ajustados'), 'null') <> 'null' then
      if v_prato is null then
        raise exception 'componentes_sem_prato' using errcode = 'P0001', detail = format('item %s', v_n);
      end if;
      begin
        perform coalesce(x ->> 'produto_id', x #>> '{}')::uuid
           from jsonb_array_elements(coalesce(nullif(v_item -> 'componentes_excluidos', 'null'), '[]')) x;
        if exists (select 1
                     from jsonb_array_elements(coalesce(nullif(v_item -> 'componentes_ajustados', 'null'), '[]')) a
                    where (a ->> 'produto_id')::uuid is null
                       or (a ->> 'quantidade')::numeric is null
                       or (a ->> 'quantidade')::numeric < 0) then
          raise exception 'componentes_invalidos' using errcode = 'P0001', detail = format('item %s', v_n);
        end if;
      exception
        when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range
             or cannot_coerce then
          raise exception 'componentes_invalidos' using errcode = 'P0001', detail = format('item %s', v_n);
      end;
    end if;
  end loop;
  return new;
end $$;

-- Corre antes de trg_pedidos_1_proteger (os triggers correm por ordem de nome)
create trigger trg_pedidos_0_validar_itens
before insert or update of itens on pedidos
for each row execute function pedidos_validar_itens();

-- -----------------------------------------------------------------------------
-- 2. Responsável pelo desconto de stock de cada venda
-- -----------------------------------------------------------------------------
alter table vendas add column stock_consumido_por text not null default 'dispositivo'
  check (stock_consumido_por in ('dispositivo', 'servidor'));
comment on column vendas.stock_consumido_por is
  'Quem desconta o stock desta venda: dispositivo (app do operador) ou servidor (vendas geradas de pedidos). Nunca os dois.';

-- Vendas já geradas pelo servidor a partir de pedidos: o responsável é o
-- servidor. Não se desconta retroactivamente (a actualização não dispara o
-- trigger de consumo, que é só de inserção).
update vendas set stock_consumido_por = 'servidor'
 where pedido_id is not null and dispositivo_id = 'servidor';

-- SECURITY INVOKER: precisa de saber quem escreve (e_escrita_cliente)
create or replace function vendas_proteger_consumo() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if e_escrita_cliente() then
      new.stock_consumido_por := 'dispositivo';
    end if;
  else
    new.stock_consumido_por := old.stock_consumido_por;
  end if;
  return new;
end $$;

create trigger trg_vendas_0_proteger_consumo
before insert or update on vendas
for each row execute function vendas_proteger_consumo();

-- -----------------------------------------------------------------------------
-- 3. Ligação do movimento de stock à venda
-- -----------------------------------------------------------------------------
alter table estoque_longo_prazo add column venda_id uuid references vendas(id);
create unique index estoque_lp_venda_produto_key on estoque_longo_prazo (venda_id, produto_id);
comment on column estoque_longo_prazo.venda_id is
  'Venda que originou o consumo (só nos consumos feitos pelo servidor). Único com produto_id.';

-- -----------------------------------------------------------------------------
-- 4. Conversão para a unidade base (grama, ml, unidade)
-- -----------------------------------------------------------------------------
-- Devolve null se a unidade for desconhecida ou não corresponder à
-- categoria de medida do produto (Peso/Volume/Unidade).
create or replace function quantidade_unidade_base(p_quantidade numeric, p_unidade text,
                                                   p_categoria_medida text default null)
returns numeric language sql immutable set search_path = public as $$
  select case
           -- sem unidade: a quantidade já está na unidade base
           when coalesce(trim(p_unidade), '') = '' then p_quantidade
           when u.categoria is null then null
           when p_categoria_medida is not null and u.categoria <> p_categoria_medida then null
           else p_quantidade * u.fator
         end
    from (select 1) x
    left join (values
      ('mg', 'Peso', 0.001), ('g', 'Peso', 1), ('gr', 'Peso', 1), ('grama', 'Peso', 1), ('gramas', 'Peso', 1),
      ('kg', 'Peso', 1000), ('quilo', 'Peso', 1000), ('quilos', 'Peso', 1000),
      ('quilograma', 'Peso', 1000), ('quilogramas', 'Peso', 1000),
      ('ml', 'Volume', 1), ('cl', 'Volume', 10), ('dl', 'Volume', 100),
      ('l', 'Volume', 1000), ('lt', 'Volume', 1000), ('litro', 'Volume', 1000), ('litros', 'Volume', 1000),
      ('u', 'Unidade', 1), ('un', 'Unidade', 1), ('und', 'Unidade', 1),
      ('unidade', 'Unidade', 1), ('unidades', 'Unidade', 1)
    ) u(unidade, categoria, fator) on u.unidade = lower(trim(p_unidade));
$$;

-- -----------------------------------------------------------------------------
-- 5. Venda gerada de um pedido: copia os componentes e marca 'servidor'
-- -----------------------------------------------------------------------------
create or replace function gerar_venda_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_itens     jsonb;
  v_parc      jsonb;
  v_n         int;
  v_m         int;
  v_final     int;
  v_base_tot  numeric;
  v_bruto     int;
  v_taxa      int;
  v_desc      int;
  v_total     int;
  v_acc_bruto int := 0;
  v_acc_desc  int := 0;
  v_acc_col   int[];
  v_linha_acc int;
  v_val       int;
  v_parc_l    jsonb;
  v_item      jsonb;
  v_zona      zonas;
  v_caixa     caixa;
  i           int;
  j           int;
begin
  -- Estorno: compensação das vendas registadas na entrega
  if new.estado = 'estornado' and old.estado = 'entregue_pago' then
    insert into vendas (dispositivo_id, sincronizado_em, data, cozinha_id, pedido_id, linha_pedido, origem,
                        cliente_id, produto, qtd, prato_base_id, valor_antes_desconto, desconto_aplicado,
                        valor_total, taxa_entrega, parcelas, credito, entrega, zona_nome, tipo_entrega,
                        local, caixa_id, movimenta_stock, stock_consumido_por, registado_por)
    select 'servidor', now(), now(), v.cozinha_id, v.pedido_id, v.linha_pedido, 'App cliente (estorno)',
           v.cliente_id, v.produto, 0, v.prato_base_id, -v.valor_antes_desconto, -v.desconto_aplicado,
           -v.valor_total, -v.taxa_entrega,
           coalesce((select jsonb_agg(p || jsonb_build_object('valor', -((p ->> 'valor')::numeric)))
                       from jsonb_array_elements(v.parcelas) p), '[]'::jsonb),
           v.credito, v.entrega, v.zona_nome, v.tipo_entrega, v.local, v.caixa_id, false, 'servidor',
           funcionario_actual()
      from vendas v
     where v.pedido_id = new.id and v.origem = 'App cliente'
    on conflict (pedido_id, linha_pedido, origem) where pedido_id is not null do nothing;
    perform registar_auditoria('venda_estornada', 'pedidos', new.id, '{}'::jsonb);
    return new;
  end if;

  if not (new.estado = 'entregue_pago' and old.estado is distinct from 'entregue_pago') then
    return new;
  end if;
  if exists (select 1 from vendas where pedido_id = new.id and origem = 'App cliente') then
    return new;
  end if;

  select z.* into v_zona from pontos_entrega pe join zonas z on z.id = pe.zona_id
   where pe.id = new.ponto_entrega_id;
  if not found then
    select * into v_zona from zonas where id = new.zona_id;
  end if;
  select * into v_caixa from caixa where id = new.caixa_id;

  v_itens := case when jsonb_array_length(new.itens) > 0 then new.itens
                  else jsonb_build_array(jsonb_build_object('nome', 'Pedido app', 'qtd', 1,
                                                            'preco_unitario', new.subtotal)) end;
  v_n := jsonb_array_length(v_itens);
  v_parc := new.parcelas
    || case when new.credito_indicacao_usado > 0
            then jsonb_build_array(jsonb_build_object('metodo', 'Crédito indicação',
                                                      'valor', new.credito_indicacao_usado,
                                                      'cliente_id', new.cliente_id))
            else '[]'::jsonb end;
  v_m := jsonb_array_length(v_parc);
  v_acc_col := array_fill(0, array[greatest(v_m, 1)]);
  v_final := new.subtotal + new.taxa_entrega - new.desconto_indicacao;
  select coalesce(sum(coalesce((x ->> 'qtd')::numeric, 1) * coalesce((x ->> 'preco_unitario')::numeric, 0)), 0)
    into v_base_tot from jsonb_array_elements(v_itens) x;

  for i in 1 .. v_n loop
    v_item := v_itens -> (i - 1);

    if i < v_n then
      v_bruto := case when v_base_tot > 0
                      then round(new.subtotal * coalesce((v_item ->> 'qtd')::numeric, 1)
                                 * coalesce((v_item ->> 'preco_unitario')::numeric, 0) / v_base_tot)
                      else round(new.subtotal::numeric / v_n) end;
      v_acc_bruto := v_acc_bruto + v_bruto;
    else
      v_bruto := new.subtotal - v_acc_bruto;
    end if;
    v_taxa := case when i = 1 then new.taxa_entrega else 0 end;

    if i < v_n then
      v_desc := case when new.subtotal + new.taxa_entrega > 0
                     then round(new.desconto_indicacao::numeric * (v_bruto + v_taxa)
                                / (new.subtotal + new.taxa_entrega))
                     else 0 end;
      v_acc_desc := v_acc_desc + v_desc;
    else
      v_desc := new.desconto_indicacao - v_acc_desc;
    end if;
    v_total := v_bruto + v_taxa - v_desc;

    v_parc_l := '[]'::jsonb;
    v_linha_acc := 0;
    for j in 1 .. v_m loop
      if i < v_n then
        if j < v_m then
          v_val := case when v_final > 0
                        then round(((v_parc -> (j - 1)) ->> 'valor')::numeric * v_total / v_final)
                        else 0 end;
        else
          v_val := v_total - v_linha_acc;
        end if;
      else
        v_val := ((v_parc -> (j - 1)) ->> 'valor')::numeric - v_acc_col[j];
      end if;
      v_acc_col[j] := v_acc_col[j] + v_val;
      v_linha_acc := v_linha_acc + v_val;
      v_parc_l := v_parc_l || jsonb_build_array((v_parc -> (j - 1)) || jsonb_build_object('valor', v_val));
    end loop;

    insert into vendas (dispositivo_id, sincronizado_em, data, cozinha_id, pedido_id, linha_pedido, origem,
                        cliente_id, produto, qtd, prato_base_id, componentes_excluidos, componentes_ajustados,
                        valor_antes_desconto, desconto_aplicado,
                        valor_total, taxa_entrega, parcelas, credito, entrega, zona_nome, tipo_entrega,
                        local, caixa_id, movimenta_stock, stock_consumido_por, registado_por)
    values ('servidor', now(), now(), new.cozinha_id, new.id, i, 'App cliente',
            new.cliente_id, coalesce(v_item ->> 'nome', 'Prato'), coalesce((v_item ->> 'qtd')::numeric, 1),
            (v_item ->> 'prato_base_id')::uuid,
            nullif(v_item -> 'componentes_excluidos', 'null'), nullif(v_item -> 'componentes_ajustados', 'null'),
            v_bruto + v_taxa, v_desc, v_total, v_taxa, v_parc_l,
            false, true, v_zona.nome, v_zona.tipo, v_caixa.posto, new.caixa_id, true, 'servidor',
            funcionario_actual())
    on conflict (pedido_id, linha_pedido, origem) where pedido_id is not null do nothing;
  end loop;

  perform registar_auditoria('venda_gerada', 'pedidos', new.id,
    jsonb_build_object('linhas', v_n, 'valor_final', v_final, 'caixa_id', new.caixa_id, 'posto', v_caixa.posto));
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- 6. Consumo de stock das vendas do servidor
-- -----------------------------------------------------------------------------
create or replace function consumir_stock_venda() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_componentes jsonb;
  c             record;
begin
  if new.stock_consumido_por <> 'servidor' or not new.movimenta_stock
     or new.prato_base_id is null or coalesce(new.qtd, 0) <= 0 then
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
      on conflict (venda_id, produto_id) do nothing;
    end if;
    -- 'Diário': sem movimento por venda (fica para a reconciliação do dia)
  end loop;
  return new;
end $$;

create trigger trg_vendas_consumir_stock
after insert on vendas
for each row execute function consumir_stock_venda();

-- -----------------------------------------------------------------------------
-- 7. Privilégios: funções de trigger só correm como triggers
-- -----------------------------------------------------------------------------
revoke execute on function pedidos_validar_itens()   from public, anon, authenticated;
revoke execute on function vendas_proteger_consumo() from public, anon, authenticated;
revoke execute on function consumir_stock_venda()    from public, anon, authenticated;
revoke execute on function gerar_venda_pedido()      from public, anon, authenticated;
