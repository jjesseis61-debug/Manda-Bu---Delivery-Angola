-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I1 · Decisões (vendas por item, caixa, estorno)
--
--   1. duracao_dias_garantida na ligação, usada no cálculo de expira_em.
--   2. Uma venda por item do pedido (linha_pedido): taxa de entrega só na
--      primeira linha; desconto e parcelas repartidos proporcionalmente, com o
--      arredondamento na última linha; a soma das vendas = valor final (regra 7).
--   3. Regra 8: marcar entregue_pago exige a caixa (posto) onde o dinheiro
--      entrou; a venda regista esse local (vendas.local = caixa.posto).
--   4. Regra 3: a venda de compensação do estorno não repõe stock
--      (movimenta_stock = false, qtd = 0).
--   5. Catálogo de permissões do organograma (inclui pedidos.gerir e
--      entregas.registar).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Duração garantida na ligação
-- -----------------------------------------------------------------------------
alter table ligacoes_indicacao
  add column duracao_dias_garantida int check (duracao_dias_garantida > 0);
update ligacoes_indicacao l set duracao_dias_garantida = p.duracao_dias
  from parametros p where p.unico;
alter table ligacoes_indicacao alter column duracao_dias_garantida set not null;

create or replace function ligar_indicacao(p_codigo text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_cliente   uuid := cliente_actual();
  v_indicador uuid;
  v_ligacao   uuid;
begin
  if not funcionalidade_activa('indicacao') then return 'programa_inactivo'; end if;
  if v_cliente is null then return 'sem_sessao'; end if;

  select cliente_id into v_indicador
    from codigos_indicacao
   where codigo = upper(trim(p_codigo)) and deletado_em is null;
  if v_indicador is null then return 'codigo_inexistente'; end if;
  if v_indicador = v_cliente then return 'proprio_codigo'; end if;
  if exists (select 1 from ligacoes_indicacao where indicado_id = v_cliente) then
    return 'ja_ligado';
  end if;
  if cliente_ja_comprou(v_cliente) then return 'cliente_nao_novo'; end if;

  -- Os valores em vigor ficam garantidos para esta ligação
  insert into ligacoes_indicacao (indicado_id, indicador_id, dispositivo_id,
                                  ganho_por_pedido_garantido, desconto_garantido, duracao_dias_garantida)
  select v_cliente, v_indicador, 'servidor', p.ganho_por_pedido, p.desconto_indicado, p.duracao_dias
    from parametros p where p.unico
  returning id into v_ligacao;

  insert into notificacoes_fila (cliente_id, codigo, dados)
  select v_indicador, 'N2', jsonb_build_object('indicado_nome', split_part(trim(nome), ' ', 1))
    from clientes where id = v_cliente;

  perform registar_auditoria('indicacao_ligada', 'ligacoes_indicacao', v_ligacao,
                             jsonb_build_object('indicador_id', v_indicador, 'indicado_id', v_cliente));
  return 'ok';
end $$;

create or replace function processar_ganho_indicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  p               parametros;
  lig             ligacoes_indicacao;
  v_tipo_local    text;
  nivel_ind       text;
  total_sem       int;
  indicados_local int;
  v_estado        text := 'confirmado';
  v_motivo        text := null;
  v_ganho         uuid;
  g               record;
begin
  -- Estorno de um pedido já pago: ganhos ainda não pagos são anulados
  if old.estado = 'entregue_pago' and new.estado <> 'entregue_pago' then
    for g in update ganhos_indicacao
                set estado = 'anulado', motivo = 'pedido_estornado'
              where pedido_id = new.id and estado in ('em_verificacao','confirmado')
             returning id loop
      perform registar_auditoria('ganho_indicacao_anulado', 'ganhos_indicacao', g.id,
                                 jsonb_build_object('motivo', 'pedido_estornado', 'pedido_id', new.id));
    end loop;
    return new;
  end if;

  if new.estado <> 'entregue_pago' or old.estado = 'entregue_pago' then
    return new;
  end if;
  if not funcionalidade_activa('indicacao') then return new; end if;

  select * into p from parametros where unico;
  select * into lig from ligacoes_indicacao
   where indicado_id = new.cliente_id and deletado_em is null
   for update;
  if not found then return new; end if;

  -- 1.º pedido pago: arranca o período (duração garantida na ligação)
  if lig.expira_em is null then
    update ligacoes_indicacao
       set primeiro_pedido_id = new.id,
           expira_em = coalesce(new.entregue_em, now()) + make_interval(days => lig.duracao_dias_garantida),
           desconto_usado = (new.desconto_indicacao > 0)
     where id = lig.id
    returning * into lig;
  end if;

  if now() > lig.expira_em then return new; end if;
  if exists (select 1 from ganhos_indicacao where pedido_id = new.id) then
    return new;
  end if;

  -- Sinal forte: mesmo dispositivo (campo comum dispositivo_id; linhas criadas
  -- pelo servidor têm dispositivo_id = 'servidor' e não contam)
  if exists (
    select 1 from pedidos a
     where a.cliente_id = lig.indicador_id
       and a.dispositivo_id is not null and a.dispositivo_id <> 'servidor'
       and a.dispositivo_id in (select b.dispositivo_id from pedidos b
                                 where b.cliente_id = new.cliente_id
                                   and b.dispositivo_id is not null
                                   and b.dispositivo_id <> 'servidor')) then
    v_estado := 'anulado'; v_motivo := 'mesmo_dispositivo';
  end if;

  -- Sinal médio: mesmo número de levantamento
  if v_estado = 'confirmado' and exists (
    select 1 from pagamentos_indicacao a
     where a.indicador_id = lig.indicador_id and a.numero_destino is not null
       and a.numero_destino in (select b.numero_destino from pagamentos_indicacao b
                                 where b.indicador_id = new.cliente_id
                                   and b.numero_destino is not null)) then
    v_estado := 'em_verificacao'; v_motivo := 'numero_pagamento_partilhado';
  end if;

  -- Limite por local residencial
  select tipo into v_tipo_local from pontos_entrega where id = new.ponto_entrega_id;
  if v_estado = 'confirmado' and v_tipo_local = 'residencial' then
    select count(distinct g2.indicado_id) into indicados_local
      from ganhos_indicacao g2 join pedidos x on x.id = g2.pedido_id
     where g2.estado <> 'anulado'
       and g2.indicado_id <> new.cliente_id
       and x.ponto_entrega_id is not null
       and mesmo_ponto_entrega(x.ponto_entrega_id, new.ponto_entrega_id);
    if indicados_local >= p.max_indicados_por_local then
      v_estado := 'em_verificacao'; v_motivo := 'limite_local';
    end if;
  end if;

  -- Limite semanal (não se aplica a Embaixadores)
  if v_estado = 'confirmado' then
    select nivel into nivel_ind from codigos_indicacao where cliente_id = lig.indicador_id;
    if nivel_ind is distinct from 'embaixador' then
      select coalesce(sum(valor), 0) into total_sem
        from ganhos_indicacao
       where indicador_id = lig.indicador_id
         and estado in ('confirmado','pago')
         and confirmado_em >= inicio_semana_luanda();
      if total_sem >= p.limite_verificacao_semanal then
        v_estado := 'em_verificacao'; v_motivo := 'limite_semanal';
      end if;
    end if;
  end if;

  insert into ganhos_indicacao
    (pedido_id, indicador_id, indicado_id, valor, estado, motivo, confirmado_em, dispositivo_id)
  values
    (new.id, lig.indicador_id, new.cliente_id, lig.ganho_por_pedido_garantido, v_estado, v_motivo,
     case when v_estado = 'confirmado' then now() end, 'servidor')
  returning id into v_ganho;

  perform registar_auditoria('ganho_indicacao_criado', 'ganhos_indicacao', v_ganho,
    jsonb_build_object('estado', v_estado, 'motivo', v_motivo, 'pedido_id', new.id));

  if v_estado = 'confirmado' then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N3', jsonb_build_object(
      'pedido_id', new.id,
      'valor', lig.ganho_por_pedido_garantido,
      'indicado_nome', (select split_part(trim(nome), ' ', 1) from clientes where id = new.cliente_id),
      'saldo_semana', (select coalesce(sum(valor), 0) from ganhos_indicacao
                        where indicador_id = lig.indicador_id and estado in ('confirmado','pago')
                          and confirmado_em >= inicio_semana_luanda())));
  elsif v_estado = 'em_verificacao' and v_motivo = 'limite_semanal'
        and not exists (select 1 from ganhos_indicacao
                         where indicador_id = lig.indicador_id
                           and motivo = 'limite_semanal'
                           and criado_em >= inicio_semana_luanda()
                           and pedido_id <> new.id) then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N4', jsonb_build_object('limite', p.limite_verificacao_semanal));
  end if;

  return new;
end $$;

-- -----------------------------------------------------------------------------
-- 2 e 3. Vendas por item, com a caixa onde o dinheiro entrou
-- -----------------------------------------------------------------------------
alter table pedidos add column caixa_id uuid references caixa(id);   -- só o servidor escreve
create index pedidos_caixa_idx on pedidos (caixa_id);

alter table vendas
  add column linha_pedido     int,                                  -- n.º do item no pedido (1, 2, ...)
  add column caixa_id         uuid references caixa(id),
  add column movimenta_stock  boolean not null default true;        -- false na venda de compensação
create index vendas_caixa_idx on vendas (caixa_id);

drop index vendas_pedido_origem_key;
create unique index vendas_pedido_linha_origem_key
  on vendas (pedido_id, linha_pedido, origem) where pedido_id is not null;

-- Valor final do pedido = subtotal + taxa − desconto de indicação.
-- As parcelas do pedido (mais o crédito de indicação) têm de somar o valor final (regra 7).
create or replace function pedidos_antes_actualizar() returns trigger
language plpgsql set search_path = public as $$
declare
  v_caixa  caixa;
  v_soma   numeric;
begin
  if e_escrita_cliente() then
    -- O estado só muda no servidor (mudar_estado_pedido, cancelar_pedido)
    if new.estado is distinct from old.estado then
      raise exception 'estado_so_no_servidor' using errcode = '42501';
    end if;
    -- Campos que só o servidor escreve
    new.desconto_indicacao := old.desconto_indicacao;
    new.credito_indicacao_usado := old.credito_indicacao_usado;
    new.entregue_em := old.entregue_em;
    new.cliente_id := old.cliente_id;
    new.cozinha_id := old.cozinha_id;
    new.grupo_id := old.grupo_id;
    new.caixa_id := old.caixa_id;
    if new.pagador_distinto is distinct from old.pagador_distinto
       and not tem_permissao('entregas.registar') then
      raise exception 'sem_permissao' using errcode = '42501', detail = 'entregas.registar';
    end if;
  end if;

  if new.estado is distinct from old.estado then
    if not transicao_estado_valida(old.estado, new.estado) then
      raise exception 'transicao_invalida' using errcode = 'P0001',
        detail = old.estado || ' -> ' || new.estado;
    end if;
    if new.estado = 'entregue_pago' then
      -- Regra 8: caixa aberta da mesma cozinha onde o dinheiro entrou
      if new.caixa_id is null then
        raise exception 'caixa_obrigatoria' using errcode = 'P0001';
      end if;
      select * into v_caixa from caixa where id = new.caixa_id;
      if not found or v_caixa.deletado_em is not null or v_caixa.fechamento is not null
         or v_caixa.cozinha_id <> new.cozinha_id then
        raise exception 'caixa_invalida' using errcode = 'P0001';
      end if;
      -- Regra 7: parcelas + crédito = valor final
      select coalesce(sum((x ->> 'valor')::numeric), 0) into v_soma
        from jsonb_array_elements(new.parcelas) x;
      if v_soma + new.credito_indicacao_usado
         <> new.subtotal + new.taxa_entrega - new.desconto_indicacao then
        raise exception 'parcelas_nao_somam_valor_final' using errcode = 'P0001',
          detail = (v_soma + new.credito_indicacao_usado)::text || ' <> '
                   || (new.subtotal + new.taxa_entrega - new.desconto_indicacao)::text;
      end if;
      new.entregue_em := coalesce(new.entregue_em, now());
    end if;
  end if;
  return new;
end $$;

-- Mudança de estado pelo servidor. Para entregue_pago: p_caixa obrigatória e,
-- opcionalmente, as parcelas efectivamente recebidas na entrega.
drop function mudar_estado_pedido(uuid, text, text);
create or replace function mudar_estado_pedido(p_pedido uuid, p_estado text, p_motivo text default null,
                                               p_caixa uuid default null, p_parcelas jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_de text;
begin
  if not (tem_permissao('pedidos.gerir')
          or (p_estado in ('em_entrega','entregue_pago') and tem_permissao('entregas.registar'))) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_parcelas is not null and jsonb_typeof(p_parcelas) <> 'array' then
    raise exception 'parcelas_invalidas' using errcode = 'P0001';
  end if;
  select estado into v_de from pedidos where id = p_pedido and deletado_em is null for update;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  update pedidos
     set estado = p_estado,
         caixa_id = case when p_estado = 'entregue_pago' then coalesce(p_caixa, caixa_id) else caixa_id end,
         parcelas = case when p_estado = 'entregue_pago' and p_parcelas is not null then p_parcelas
                         else parcelas end,
         motivo_cancelamento = case when p_estado = 'cancelado' then coalesce(p_motivo, motivo_cancelamento)
                                    else motivo_cancelamento end
   where id = p_pedido;
  perform registar_auditoria('pedido_estado', 'pedidos', p_pedido,
    jsonb_build_object('de', v_de, 'para', p_estado, 'motivo', p_motivo, 'caixa_id', p_caixa));
end $$;

-- Venda por item:
--   bruto   : subtotal repartido pelos itens (qtd × preço), arredondamento na última linha
--   taxa    : só na linha 1
--   desconto: proporcional a (bruto + taxa), arredondamento na última linha
--   parcelas: cada parcela repartida proporcionalmente ao total da linha; em cada
--             linha a última parcela acerta o total da linha; na última linha cada
--             parcela acerta o seu total. Soma de todas as vendas = valor final.
-- Estorno: uma venda de compensação por linha, com valores negativos, qtd 0 e
--          movimenta_stock = false (não repõe stock — regra 3).
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
                        local, caixa_id, movimenta_stock, registado_por)
    select 'servidor', now(), now(), v.cozinha_id, v.pedido_id, v.linha_pedido, 'App cliente (estorno)',
           v.cliente_id, v.produto, 0, v.prato_base_id, -v.valor_antes_desconto, -v.desconto_aplicado,
           -v.valor_total, -v.taxa_entrega,
           coalesce((select jsonb_agg(p || jsonb_build_object('valor', -((p ->> 'valor')::numeric)))
                       from jsonb_array_elements(v.parcelas) p), '[]'::jsonb),
           v.credito, v.entrega, v.zona_nome, v.tipo_entrega, v.local, v.caixa_id, false, funcionario_actual()
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
                        cliente_id, produto, qtd, prato_base_id, valor_antes_desconto, desconto_aplicado,
                        valor_total, taxa_entrega, parcelas, credito, entrega, zona_nome, tipo_entrega,
                        local, caixa_id, movimenta_stock, registado_por)
    values ('servidor', now(), now(), new.cozinha_id, new.id, i, 'App cliente',
            new.cliente_id, coalesce(v_item ->> 'nome', 'Prato'), coalesce((v_item ->> 'qtd')::numeric, 1),
            (v_item ->> 'prato_base_id')::uuid, v_bruto + v_taxa, v_desc, v_total, v_taxa, v_parc_l,
            false, true, v_zona.nome, v_zona.tipo, v_caixa.posto, new.caixa_id, true, funcionario_actual())
    on conflict (pedido_id, linha_pedido, origem) where pedido_id is not null do nothing;
  end loop;

  perform registar_auditoria('venda_gerada', 'pedidos', new.id,
    jsonb_build_object('linhas', v_n, 'valor_final', v_final, 'caixa_id', new.caixa_id, 'posto', v_caixa.posto));
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- 5. Catálogo de permissões do organograma
-- -----------------------------------------------------------------------------
-- As permissões continuam a ser atribuídas em direcoes.permissoes e
-- funcionarios.permissoes_extra; o catálogo diz à app do operador quais existem.
create table permissoes (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  chave            text not null unique,
  grupo            text not null,
  descricao        text not null
);
insert into permissoes (chave, grupo, descricao, dispositivo_id) values
  ('indicacoes.ver',                'Programa de indicação', 'Painel do programa e relatórios', 'servidor'),
  ('indicacoes.verificar',          'Programa de indicação', 'Confirmar ou anular ganhos em verificação', 'servidor'),
  ('indicacoes.aprovar_pagamentos', 'Programa de indicação', 'Aprovar e marcar levantamentos', 'servidor'),
  ('plataforma.parametros',         'Plataforma',            'Alterar parâmetros, interruptores e nível Embaixador', 'servidor'),
  ('avaliacoes.moderar',            'Avaliações',            'Aprovar fotos e ocultar comentários', 'servidor'),
  ('cozinhas.gerir',                'Cozinhas',              'Criar e editar cozinhas e perfis', 'servidor'),
  ('equipa.reconhecer',             'Equipa',                'Registar reconhecimentos de turno', 'servidor'),
  ('relatorios.exportar',           'Relatórios',            'Exportar relatórios de cozinha', 'servidor'),
  ('pedidos.gerir',                 'Pedidos',               'Mudar o estado dos pedidos da app (confirmar, preparar, cancelar, estornar)', 'servidor'),
  ('entregas.registar',             'Pedidos',               'Marcar pedidos em entrega e entregues e pagos (com a caixa); marcar "pago por outra pessoa"', 'servidor');

create trigger trg_0_so_servidor before insert or update or delete on permissoes
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on permissoes
for each row execute function sync_receber();
alter table permissoes enable row level security;
revoke all on permissoes from anon;
revoke insert, update, delete, truncate on permissoes from authenticated;
create policy ler on permissoes for select to authenticated using (deletado_em is null);
comment on table permissoes is 'Sincronização: só servidor (catálogo). Telemóvel só lê.';

-- -----------------------------------------------------------------------------
-- Execução de funções
-- -----------------------------------------------------------------------------
revoke execute on function pedidos_antes_actualizar() from public, anon, authenticated;
revoke execute on function gerar_venda_pedido() from public, anon, authenticated;
revoke execute on function processar_ganho_indicacao() from public, anon, authenticated;
revoke execute on function mudar_estado_pedido(uuid, text, text, uuid, jsonb) from public, anon;
grant  execute on function mudar_estado_pedido(uuid, text, text, uuid, jsonb) to authenticated;
