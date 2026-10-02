-- I12 · Pacotes mensais pré-pagos ("Almoço do Mês"): o cliente compra um pacote de
-- refeições (por exemplo 20 + 2 de oferta, entrega grátis, válido 30 dias), paga
-- adiantado (Multicaixa Express, Unitel Money ou na loja) e cada pedido gasta
-- refeições do pacote em vez de ser pago na entrega. Interruptor `pacotes`.
--
-- Regras:
--  * A adesão fica pendente até a equipa confirmar o pagamento (pacotes.gerir).
--  * Cada unidade de prato gasta uma refeição e o pacote paga até valor_refeicao
--    dessa unidade (o resto, por exemplo extras caros, paga-se na entrega). Com
--    entrega grátis, o pacote paga também a taxa (excepto em pedidos de grupo,
--    cuja taxa só se conhece no fecho).
--  * O pacote entra no pedido como pagamento adiantado (pago_pacote), como o crédito
--    do Convida e Ganha: as parcelas da entrega mais o pacote somam o valor final e
--    a venda leva a parcela "Pacote". A receita conta quando a refeição é entregue.
--  * Pedido cancelado ou estornado: as refeições voltam ao pacote.
--  * Pausa: até pausa_max_dias por adesão, que prolongam a validade.
--  * Reembolso: as refeições pagas e não usadas, ao preço pago por refeição; as de
--    oferta não se reembolsam (as usadas contam primeiro como pagas).
--  * Prova social (efeito vicário): quantos clientes do mesmo local de entrega e da
--    mesma zona têm pacote, só a partir de contador_minimo, sem nomes.

insert into funcionalidades (chave, activa, dispositivo_id) values ('pacotes', false, 'servidor')
on conflict (chave) do nothing;
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'pacotes.gerir', 'Pacotes', 'Criar pacotes, confirmar pagamentos de adesões e fazer reembolsos')
on conflict (chave) do nothing;

-- -----------------------------------------------------------------------------
-- 1. Catálogo de pacotes e adesões
-- -----------------------------------------------------------------------------
create table pacotes (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  nome             text not null check (length(trim(nome)) between 1 and 60),
  descricao        text check (descricao is null or length(descricao) <= 300),
  refeicoes        integer not null check (refeicoes between 1 and 100),
  refeicoes_oferta integer not null default 0 check (refeicoes_oferta between 0 and 50),
  valor_refeicao   integer not null check (valor_refeicao > 0),
  preco            integer not null check (preco > 0),
  validade_dias    integer not null default 30 check (validade_dias between 1 and 120),
  pausa_max_dias   integer not null default 5 check (pausa_max_dias between 0 and 30),
  entrega_gratis   boolean not null default true,
  activo           boolean not null default true,
  ordem            integer not null default 0
);
comment on table pacotes is
  'Sincronização: Last-write-wins com atualizado_em; escrita só com pacotes.gerir. Catálogo de pacotes pré-pagos (I12).';

create table adesoes_pacote (
  id                uuid primary key default gen_random_uuid(),
  dispositivo_id    text,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  sincronizado_em   timestamptz,
  deletado_em       timestamptz,
  cliente_id        uuid not null references clientes(id),
  pacote_id         uuid not null references pacotes(id),
  estado            text not null default 'pendente'
                    check (estado in ('pendente', 'activa', 'cancelada', 'reembolsada')),
  metodo            text not null check (metodo in ('multicaixa_express', 'unitel_money', 'loja')),
  -- Condições garantidas no momento da adesão (o catálogo pode mudar depois)
  refeicoes         integer not null,
  refeicoes_oferta  integer not null,
  valor_refeicao    integer not null,
  preco             integer not null,
  validade_dias     integer not null,
  pausa_max_dias    integer not null,
  entrega_gratis    boolean not null,
  refeicoes_usadas  integer not null default 0 check (refeicoes_usadas >= 0),
  pausa_dias_usados integer not null default 0 check (pausa_dias_usados >= 0),
  inicio            date,
  fim               date,
  referencia        text,
  caixa_id          uuid references caixa(id),
  confirmado_por    uuid references funcionarios(id),
  pago_em           timestamptz,
  valor_reembolso   integer,
  reembolsado_em    timestamptz,
  check (refeicoes_usadas <= refeicoes + refeicoes_oferta)
);
create index adesoes_pacote_cliente_idx on adesoes_pacote (cliente_id, estado);
create index adesoes_pacote_pacote_idx on adesoes_pacote (pacote_id);
create index adesoes_pacote_caixa_idx on adesoes_pacote (caixa_id);
create index adesoes_pacote_confirmado_idx on adesoes_pacote (confirmado_por);
create unique index adesoes_pacote_uma_aberta on adesoes_pacote (cliente_id)
  where estado = 'pendente' and deletado_em is null;
comment on table adesoes_pacote is
  'Sincronização: Só o servidor escreve (aderir_pacote, confirmar_pagamento_pacote, usar_pacote, pausar_pacote, reembolsar_pacote). Adesões aos pacotes (I12).';

alter table pacotes enable row level security;
alter table adesoes_pacote enable row level security;
create policy ler on pacotes for select to authenticated using ((activo and deletado_em is null) or e_funcionario());
create policy criar on pacotes for insert to authenticated with check (tem_permissao('pacotes.gerir'));
create policy editar on pacotes for update to authenticated
  using (tem_permissao('pacotes.gerir')) with check (tem_permissao('pacotes.gerir'));
grant select, insert, update on pacotes to authenticated;
create policy ler on adesoes_pacote for select to authenticated
  using (cliente_id = cliente_actual() or tem_permissao('pacotes.gerir'));
revoke all on adesoes_pacote from anon, authenticated;
grant select on adesoes_pacote to authenticated;

create trigger trg_sync_receber before insert or update on pacotes
for each row execute function sync_receber('lww');
create trigger trg_auditar after insert or update on pacotes
for each row execute function auditar_alteracao_tabela();
create trigger trg_0_so_servidor before insert or update or delete on adesoes_pacote
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on adesoes_pacote
for each row execute function sync_receber();

-- -----------------------------------------------------------------------------
-- 2. O pacote no pedido
-- -----------------------------------------------------------------------------
alter table pedidos add column adesao_pacote_id uuid references adesoes_pacote(id);
alter table pedidos add column pago_pacote integer not null default 0 check (pago_pacote >= 0);
alter table pedidos add column refeicoes_pacote integer not null default 0 check (refeicoes_pacote >= 0);
create index pedidos_adesao_pacote_idx on pedidos (adesao_pacote_id);
comment on column pedidos.pago_pacote is 'Parte do valor final paga pelo pacote (I12). Só o servidor escreve.';

create or replace function pedidos_proteger_insercao()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if e_escrita_cliente() then
    -- O cliente só cria pedidos no estado inicial; campos do servidor começam vazios
    new.estado := 'pendente';
    new.entregue_em := null;
    new.credito_indicacao_usado := 0;
    new.pago_pacote := 0;
    new.refeicoes_pacote := 0;
    new.adesao_pacote_id := null;
    new.pagador_distinto := null;
    if not funcionalidade_activa('multi_cozinha') then
      new.cozinha_id := cozinha_padrao();
    end if;
  end if;
  return new;
end $function$;

create or replace function pedidos_antes_actualizar()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
    new.pago_pacote := old.pago_pacote;
    new.refeicoes_pacote := old.refeicoes_pacote;
    new.adesao_pacote_id := old.adesao_pacote_id;
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
      -- Regra 7: parcelas + crédito + pacote = valor final
      select coalesce(sum((x ->> 'valor')::numeric), 0) into v_soma
        from jsonb_array_elements(new.parcelas) x;
      if v_soma + new.credito_indicacao_usado + new.pago_pacote
         <> new.subtotal + new.taxa_entrega - new.desconto_indicacao then
        raise exception 'parcelas_nao_somam_valor_final' using errcode = 'P0001',
          detail = (v_soma + new.credito_indicacao_usado + new.pago_pacote)::text || ' <> '
                   || (new.subtotal + new.taxa_entrega - new.desconto_indicacao)::text;
      end if;
      new.entregue_em := coalesce(new.entregue_em, now());
    end if;
  end if;
  return new;
end $function$;

create or replace function gerar_venda_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            else '[]'::jsonb end
    || case when new.pago_pacote > 0
            then jsonb_build_array(jsonb_build_object('metodo', 'Pacote',
                                                      'valor', new.pago_pacote,
                                                      'adesao_pacote_id', new.adesao_pacote_id))
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
end $function$;

create or replace function pedidos_operador()
 RETURNS TABLE(pedido_id uuid, criado_em timestamp with time zone, estado text, cozinha_id uuid, cliente_nome text, cliente_telefone text, itens jsonb, subtotal integer, taxa_entrega integer, desconto_indicacao integer, credito_indicacao_usado integer, a_pagar integer, observacoes text, hora_prometida timestamp with time zone, pagador_distinto boolean, ponto_entrega_id uuid, ponto_tipo text, ponto_lat double precision, ponto_lng double precision, ponto_referencia text, zona_nome text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_gerir    boolean := tem_permissao('pedidos.gerir');
begin
  if not (v_gerir or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  return query
  select x.id, x.criado_em, x.estado, x.cozinha_id, c.nome, c.telefone, x.itens,
         x.subtotal::int, x.taxa_entrega::int, x.desconto_indicacao::int, x.credito_indicacao_usado::int,
         (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado - x.pago_pacote)::int,
         x.observacoes, x.hora_prometida, x.pagador_distinto,
         pe.id, pe.tipo, pe.lat, pe.lng, pe.referencia, z.nome
    from pedidos x
    join clientes c on c.id = x.cliente_id
    left join pontos_entrega pe on pe.id = x.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, x.zona_id)
   where x.deletado_em is null
     and x.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
     and (v_gerir or x.estado <> 'pendente')
   order by x.criado_em;
end $function$;

create or replace function grupos_operador(p_dia date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_dia date := coalesce(p_dia, hoje_luanda());
  r jsonb;
begin
  if not (tem_permissao('pedidos.gerir') or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'grupo_id', g.id,
           'cozinha_id', g.cozinha_id,
           'cozinha_nome', cz.nome,
           'hora_entrega', g.hora_entrega,
           'prazo_adesao', g.prazo_adesao,
           'estado', g.estado,
           'modo_pagamento', g.modo_pagamento,
           'organizador', o.nome,
           'organizador_telefone', o.telefone,
           'local', jsonb_build_object('referencia', pe.referencia, 'lat', pe.lat, 'lng', pe.lng, 'zona', z.nome),
           'pedidos', coalesce((select jsonb_agg(jsonb_build_object(
                                   'pedido_id', x.id, 'cliente_nome', c.nome, 'estado', x.estado, 'itens', x.itens,
                                   'a_pagar', (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado - x.pago_pacote)::int,
                                   'observacoes', x.observacoes) order by x.criado_em)
                                  from pedidos x join clientes c on c.id = x.cliente_id
                                 where x.grupo_id = g.id and x.deletado_em is null), '[]'),
           'resumo', coalesce((select jsonb_agg(jsonb_build_object('nome', s.nome, 'qtd', s.qtd) order by s.nome)
                                 from (select i ->> 'nome' as nome, sum((i ->> 'qtd')::int) as qtd
                                         from pedidos x, jsonb_array_elements(x.itens) i
                                        where x.grupo_id = g.id and x.deletado_em is null and x.estado <> 'cancelado'
                                        group by i ->> 'nome') s), '[]'),
           'total_a_pagar', (select coalesce(sum(x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado - x.pago_pacote), 0)::int
                               from pedidos x where x.grupo_id = g.id and x.deletado_em is null and x.estado <> 'cancelado'))
         order by g.hora_entrega), '[]')
    into r
    from pedidos_grupo g
    join cozinhas cz on cz.id = g.cozinha_id
    join clientes o on o.id = g.organizador_id
    join pontos_entrega pe on pe.id = g.ponto_entrega_id
    left join zonas z on z.id = pe.zona_id
   where g.deletado_em is null
     and (g.hora_entrega at time zone 'Africa/Luanda')::date = v_dia;
  return r;
end $function$;

-- Pedido cancelado ou estornado: as refeições voltam ao pacote
create or replace function pedidos_devolver_pacote() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.estado in ('cancelado', 'estornado') and old.estado is distinct from new.estado
     and old.adesao_pacote_id is not null and old.refeicoes_pacote > 0 then
    update adesoes_pacote set refeicoes_usadas = greatest(0, refeicoes_usadas - old.refeicoes_pacote),
                              atualizado_em = now()
     where id = old.adesao_pacote_id;
    perform registar_auditoria('pacote_refeicoes_devolvidas', 'adesoes_pacote', old.adesao_pacote_id,
      jsonb_build_object('pedido_id', new.id, 'refeicoes', old.refeicoes_pacote, 'estado', new.estado));
  end if;
  return new;
end $$;

create trigger trg_pedidos_devolver_pacote after update on pedidos
for each row execute function pedidos_devolver_pacote();

-- -----------------------------------------------------------------------------
-- 3. API do cliente
-- -----------------------------------------------------------------------------
-- Adesão em vigor do cliente (activa, dentro da validade e com refeições), se houver
create or replace function adesao_em_vigor(p_cliente uuid) returns adesoes_pacote
language sql stable security definer set search_path = public as $$
  select * from adesoes_pacote
   where cliente_id = p_cliente and estado = 'activa' and deletado_em is null
     and hoje_luanda() between inicio and fim
     and refeicoes_usadas < refeicoes + refeicoes_oferta
   order by fim limit 1;
$$;

create or replace function aderir_pacote(p_pacote uuid, p_metodo text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  v_pac     pacotes;
  v_id      uuid;
begin
  if not funcionalidade_activa('pacotes') then
    raise exception 'pacotes_inactivos' using errcode = 'P0001';
  end if;
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if p_metodo not in ('multicaixa_express', 'unitel_money', 'loja') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  select * into v_pac from pacotes where id = p_pacote and activo and deletado_em is null;
  if not found then raise exception 'pacote_indisponivel' using errcode = 'P0001'; end if;
  if exists (select 1 from adesoes_pacote where cliente_id = v_cliente and estado = 'pendente' and deletado_em is null) then
    raise exception 'adesao_pendente' using errcode = 'P0001';
  end if;
  insert into adesoes_pacote (cliente_id, pacote_id, metodo, refeicoes, refeicoes_oferta, valor_refeicao, preco,
                              validade_dias, pausa_max_dias, entrega_gratis, dispositivo_id)
  values (v_cliente, v_pac.id, p_metodo, v_pac.refeicoes, v_pac.refeicoes_oferta, v_pac.valor_refeicao, v_pac.preco,
          v_pac.validade_dias, v_pac.pausa_max_dias, v_pac.entrega_gratis, 'servidor')
  returning id into v_id;
  perform registar_auditoria('pacote_adesao_pedida', 'adesoes_pacote', v_id, jsonb_build_object('metodo', p_metodo));
  return v_id;
end $$;

create or replace function cancelar_adesao_pacote(p_adesao uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update adesoes_pacote set estado = 'cancelada', atualizado_em = now()
   where id = p_adesao and cliente_id = cliente_actual() and estado = 'pendente';
  if not found then raise exception 'adesao_inexistente' using errcode = 'P0001'; end if;
  perform registar_auditoria('pacote_adesao_cancelada', 'adesoes_pacote', p_adesao, '{}'::jsonb);
end $$;

-- Gasta refeições do pacote num pedido do próprio cliente (pendente ou confirmado).
-- Paga primeiro as unidades mais caras, até valor_refeicao cada; com entrega grátis, também a taxa.
create or replace function usar_pacote(p_pedido uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  ped       pedidos;
  ad        adesoes_pacote;
  v_rest    integer;
  v_n       integer := 0;
  v_valor   integer := 0;
  u         record;
begin
  if not funcionalidade_activa('pacotes') then
    raise exception 'pacotes_inactivos' using errcode = 'P0001';
  end if;
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  select * into ped from pedidos where id = p_pedido and deletado_em is null for update;
  if not found or ped.cliente_id <> v_cliente then
    raise exception 'pedido_inexistente' using errcode = 'P0001';
  end if;
  if ped.estado not in ('pendente', 'confirmado') then
    raise exception 'estado_invalido' using errcode = 'P0001';
  end if;
  if ped.adesao_pacote_id is not null then
    return ped.pago_pacote;   -- já aplicado (retentar não gasta duas vezes)
  end if;
  ad := adesao_em_vigor(v_cliente);
  if ad.id is null then raise exception 'sem_pacote' using errcode = 'P0001'; end if;
  select * into ad from adesoes_pacote where id = ad.id for update;
  v_rest := ad.refeicoes + ad.refeicoes_oferta - ad.refeicoes_usadas;

  for u in
    select least(coalesce((i ->> 'preco_unitario')::int, 0), ad.valor_refeicao) as valor
      from jsonb_array_elements(ped.itens) i
      cross join generate_series(1, greatest(coalesce((i ->> 'qtd')::int, 1), 1))
     order by coalesce((i ->> 'preco_unitario')::int, 0) desc
     limit v_rest
  loop
    v_n := v_n + 1;
    v_valor := v_valor + u.valor;
  end loop;
  if v_n = 0 then raise exception 'sem_pacote' using errcode = 'P0001'; end if;
  if ad.entrega_gratis and ped.grupo_id is null then
    v_valor := v_valor + ped.taxa_entrega;
  end if;
  -- Nunca mais do que o valor que falta pagar
  v_valor := least(v_valor, ped.subtotal + ped.taxa_entrega - ped.desconto_indicacao - ped.credito_indicacao_usado);

  update adesoes_pacote set refeicoes_usadas = refeicoes_usadas + v_n, atualizado_em = now() where id = ad.id;
  update pedidos set adesao_pacote_id = ad.id, pago_pacote = v_valor, refeicoes_pacote = v_n where id = p_pedido;
  perform registar_auditoria('pacote_usado', 'pedidos', p_pedido,
    jsonb_build_object('adesao_pacote_id', ad.id, 'refeicoes', v_n, 'valor', v_valor));
  return v_valor;
end $$;

-- Saldo do Convida e Ganha: nunca acima do que falta pagar depois do pacote
create or replace function usar_credito(p_pedido uuid, p_valor int)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  ped       pedidos;
  v_pag     uuid;
begin
  if not funcionalidade_activa('indicacao') then
    raise exception 'programa_inactivo' using errcode = 'P0001';
  end if;
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;

  select * into ped from pedidos where id = p_pedido and deletado_em is null for update;
  if not found or ped.cliente_id <> v_cliente then
    raise exception 'pedido_inexistente' using errcode = 'P0001';
  end if;
  if ped.estado not in ('pendente','confirmado') then
    raise exception 'estado_invalido' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('saldo_indicacao:' || v_cliente::text));

  if p_valor is null or p_valor <= 0 then
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
  if p_valor > saldo_disponivel_de(v_cliente) then
    raise exception 'saldo_insuficiente' using errcode = 'P0001';
  end if;
  if ped.credito_indicacao_usado + p_valor
     > ped.subtotal + ped.taxa_entrega - ped.desconto_indicacao - ped.pago_pacote then
    raise exception 'acima_do_valor_do_pedido' using errcode = 'P0001';
  end if;

  insert into pagamentos_indicacao (indicador_id, valor, tipo, pedido_id, estado, pago_em, dispositivo_id)
  values (v_cliente, p_valor, 'credito', p_pedido, 'pago', now(), 'servidor')
  returning id into v_pag;

  update pedidos set credito_indicacao_usado = credito_indicacao_usado + p_valor
   where id = p_pedido;

  perform aplicar_pagamentos_a_ganhos(v_cliente, v_pag);
  perform registar_auditoria('credito_indicacao_usado', 'pagamentos_indicacao', v_pag,
    jsonb_build_object('valor', p_valor, 'pedido_id', p_pedido));
  return ped.credito_indicacao_usado + p_valor;
end $$;

-- Pausa: prolonga a validade, até ao máximo de dias da adesão
create or replace function pausar_pacote(p_dias integer) returns date
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  ad        adesoes_pacote;
begin
  if not funcionalidade_activa('pacotes') then
    raise exception 'pacotes_inactivos' using errcode = 'P0001';
  end if;
  ad := adesao_em_vigor(v_cliente);
  if ad.id is null then raise exception 'sem_pacote' using errcode = 'P0001'; end if;
  if p_dias is null or p_dias < 1 or ad.pausa_dias_usados + p_dias > ad.pausa_max_dias then
    raise exception 'pausa_invalida' using errcode = 'P0001', detail = (ad.pausa_max_dias - ad.pausa_dias_usados)::text;
  end if;
  update adesoes_pacote set pausa_dias_usados = pausa_dias_usados + p_dias, fim = fim + p_dias, atualizado_em = now()
   where id = ad.id returning * into ad;
  perform registar_auditoria('pacote_pausado', 'adesoes_pacote', ad.id, jsonb_build_object('dias', p_dias));
  return ad.fim;
end $$;

-- O pacote do cliente: a adesão mais recente (pendente ou activa), com o que resta e a poupança
create or replace function meu_pacote() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'adesao_id', a.id, 'pacote', p.nome, 'estado', a.estado, 'metodo', a.metodo,
           'refeicoes_total', a.refeicoes + a.refeicoes_oferta, 'refeicoes_oferta', a.refeicoes_oferta,
           'refeicoes_usadas', a.refeicoes_usadas,
           'refeicoes_restantes', a.refeicoes + a.refeicoes_oferta - a.refeicoes_usadas,
           'valor_refeicao', a.valor_refeicao, 'preco', a.preco, 'entrega_gratis', a.entrega_gratis,
           'inicio', a.inicio, 'fim', a.fim,
           'pausa_restante', a.pausa_max_dias - a.pausa_dias_usados,
           'em_vigor', a.estado = 'activa' and hoje_luanda() between a.inicio and a.fim
                       and a.refeicoes_usadas < a.refeicoes + a.refeicoes_oferta,
           -- Poupança: o que o pacote pagou nos pedidos entregues menos o que essas refeições custaram no pacote
           'poupanca', greatest(0, coalesce((select sum(pe.pago_pacote) - round(sum(pe.refeicoes_pacote)::numeric * a.preco / a.refeicoes)
                                               from pedidos pe where pe.adesao_pacote_id = a.id
                                                and pe.estado = 'entregue_pago'), 0))::int)
    from adesoes_pacote a join pacotes p on p.id = a.pacote_id
   where a.cliente_id = cliente_actual() and a.deletado_em is null and a.estado in ('pendente', 'activa')
   order by (a.estado = 'activa') desc, a.criado_em desc
   limit 1;
$$;

-- Prova social (efeito vicário): quantos têm pacote no mesmo local de entrega e na mesma zona,
-- e a poupança média deste mês. Só a partir de contador_minimo; sem nomes.
create or replace function pacotes_a_minha_volta() returns jsonb
language sql stable security definer set search_path = public as $$
  with eu as (
    select distinct e.ponto_entrega_id, pe.zona_id
      from enderecos_cliente e join pontos_entrega pe on pe.id = e.ponto_entrega_id
     where e.cliente_id = cliente_actual() and e.deletado_em is null
  ),
  com_pacote as (
    select distinct a.cliente_id, e.ponto_entrega_id, pe.zona_id
      from adesoes_pacote a
      join enderecos_cliente e on e.cliente_id = a.cliente_id and e.deletado_em is null
      join pontos_entrega pe on pe.id = e.ponto_entrega_id
     where a.estado = 'activa' and hoje_luanda() between a.inicio and a.fim
  ),
  minimo as (select contador_minimo as m from parametros where unico)
  select jsonb_build_object(
    'no_meu_local', (select case when count(distinct c.cliente_id) >= (select m from minimo) then count(distinct c.cliente_id) end
                       from com_pacote c where c.ponto_entrega_id in (select ponto_entrega_id from eu)),
    'na_minha_zona', (select case when count(distinct c.cliente_id) >= (select m from minimo) then count(distinct c.cliente_id) end
                        from com_pacote c where c.zona_id in (select zona_id from eu)),
    'poupanca_media_mes', (select case when count(*) >= (select m from minimo) then round(avg(v))::int end
                             from (select a.id, sum(pe.pago_pacote) - round(sum(pe.refeicoes_pacote)::numeric * a.preco / a.refeicoes) as v
                                     from adesoes_pacote a join pedidos pe on pe.adesao_pacote_id = a.id
                                    where pe.estado = 'entregue_pago' and pe.entregue_em >= inicio_mes_luanda()
                                    group by a.id, a.preco, a.refeicoes) x))
   where funcionalidade_activa('pacotes');
$$;

-- -----------------------------------------------------------------------------
-- 4. API do operador (pacotes.gerir)
-- -----------------------------------------------------------------------------
create or replace function confirmar_pagamento_pacote(p_adesao uuid, p_referencia text default null,
                                                      p_caixa uuid default null) returns date
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('pacotes.gerir');
  ad     adesoes_pacote;
begin
  select * into ad from adesoes_pacote where id = p_adesao and deletado_em is null for update;
  if not found then raise exception 'adesao_inexistente' using errcode = 'P0001'; end if;
  if ad.estado <> 'pendente' then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
  if ad.metodo = 'loja' then
    if p_caixa is null or not exists (select 1 from caixa where id = p_caixa and fechamento is null and deletado_em is null) then
      raise exception 'caixa_obrigatoria' using errcode = 'P0001';
    end if;
  elsif nullif(trim(p_referencia), '') is null then
    raise exception 'referencia_obrigatoria' using errcode = 'P0001';
  end if;
  update adesoes_pacote
     set estado = 'activa', inicio = hoje_luanda(), fim = hoje_luanda() + validade_dias - 1,
         referencia = nullif(trim(p_referencia), ''), caixa_id = p_caixa, confirmado_por = v_func,
         pago_em = now(), atualizado_em = now()
   where id = p_adesao returning * into ad;
  perform registar_auditoria('pacote_pago', 'adesoes_pacote', p_adesao,
    jsonb_build_object('preco', ad.preco, 'metodo', ad.metodo, 'referencia', ad.referencia, 'caixa_id', p_caixa));
  return ad.fim;
end $$;

-- Reembolso das refeições pagas e não usadas (as de oferta não se reembolsam)
create or replace function reembolsar_pacote(p_adesao uuid, p_referencia text default null) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_func  uuid := exigir_permissao('pacotes.gerir');
  ad      adesoes_pacote;
  v_valor integer;
begin
  select * into ad from adesoes_pacote where id = p_adesao and deletado_em is null for update;
  if not found then raise exception 'adesao_inexistente' using errcode = 'P0001'; end if;
  if ad.estado <> 'activa' then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
  if exists (select 1 from pedidos where adesao_pacote_id = p_adesao and deletado_em is null
                and estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')) then
    raise exception 'pedido_em_curso' using errcode = 'P0001';
  end if;
  v_valor := floor(greatest(0, ad.refeicoes - ad.refeicoes_usadas)::numeric * ad.preco / ad.refeicoes)::int;
  update adesoes_pacote set estado = 'reembolsada', valor_reembolso = v_valor, reembolsado_em = now(),
                            referencia = coalesce(nullif(trim(p_referencia), ''), referencia), atualizado_em = now()
   where id = p_adesao;
  perform registar_auditoria('pacote_reembolsado', 'adesoes_pacote', p_adesao,
    jsonb_build_object('valor', v_valor, 'referencia', p_referencia, 'funcionario_id', v_func));
  return v_valor;
end $$;

-- Lista para o ecrã Pacotes do operador
create or replace function adesoes_operador(p_estado text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('pacotes.gerir');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'adesao_id', a.id, 'estado', a.estado, 'metodo', a.metodo, 'pacote', p.nome,
             'cliente_nome', c.nome, 'cliente_telefone', c.telefone, 'preco', a.preco,
             'refeicoes_total', a.refeicoes + a.refeicoes_oferta, 'refeicoes_usadas', a.refeicoes_usadas,
             'inicio', a.inicio, 'fim', a.fim, 'referencia', a.referencia, 'criado_em', a.criado_em,
             'reembolso_previsto', floor(greatest(0, a.refeicoes - a.refeicoes_usadas)::numeric * a.preco / a.refeicoes)::int,
             'valor_reembolso', a.valor_reembolso)
           order by (a.estado = 'pendente') desc, a.criado_em desc)
      from adesoes_pacote a join pacotes p on p.id = a.pacote_id join clientes c on c.id = a.cliente_id
     where a.deletado_em is null and (p_estado is null or a.estado = p_estado)), '[]'::jsonb);
end $$;

revoke execute on function pedidos_devolver_pacote() from public, anon, authenticated;
revoke execute on function adesao_em_vigor(uuid) from public, anon, authenticated;
revoke execute on function aderir_pacote(uuid, text), cancelar_adesao_pacote(uuid), usar_pacote(uuid),
                           pausar_pacote(integer), meu_pacote(), pacotes_a_minha_volta(),
                           confirmar_pagamento_pacote(uuid, text, uuid), reembolsar_pacote(uuid, text),
                           adesoes_operador(text) from public, anon;
grant execute on function aderir_pacote(uuid, text), cancelar_adesao_pacote(uuid), usar_pacote(uuid),
                          pausar_pacote(integer), meu_pacote(), pacotes_a_minha_volta(),
                          confirmar_pagamento_pacote(uuid, text, uuid), reembolsar_pacote(uuid, text),
                          adesoes_operador(text) to authenticated;
