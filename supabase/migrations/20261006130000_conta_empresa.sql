-- Conta de empresa (B2B): uma empresa paga os almoços dos seus funcionários, ao mês, com fatura.
-- O funcionário (cliente membro) põe o pedido "na conta da empresa": a empresa cobre até um limite
-- por refeição e o cliente só paga a diferença na entrega. A parte da empresa entra na venda como
-- uma parcela "Conta da empresa" (como o Crédito de indicação), por isso não é dinheiro cobrado na
-- entrega — é faturado à empresa ao fim do mês (relatorio_empresa). A fatura fiscal continua a ser
-- emitida pelo software certificado na cozinha.
-- MVP: só pedidos individuais (nos grupos a conta-empresa não se aplica).

create table empresas (
  id              uuid primary key default gen_random_uuid(),
  dispositivo_id  text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  sincronizado_em timestamptz,
  deletado_em     timestamptz,
  nome            text not null check (length(nome) between 1 and 120),
  limite_refeicao integer not null default 0 check (limite_refeicao between 0 and 1000000),
  activa          boolean not null default true
);
comment on table empresas is 'Contas de empresa (B2B). Escrita só pelo servidor; a fatura real sai do software certificado.';

create table empresa_membros (
  id              uuid primary key default gen_random_uuid(),
  dispositivo_id  text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  sincronizado_em timestamptz,
  deletado_em     timestamptz,
  empresa_id      uuid not null references empresas(id),
  cliente_id      uuid not null references clientes(id)
);
-- Um cliente só pode estar numa empresa de cada vez (entre os activos)
create unique index empresa_membros_cliente_key on empresa_membros (cliente_id) where deletado_em is null;
create index empresa_membros_empresa_idx on empresa_membros (empresa_id) where deletado_em is null;

alter table empresas enable row level security;
alter table empresa_membros enable row level security;
revoke all on empresas, empresa_membros from anon, authenticated;
create trigger trg_0_so_servidor before insert or update or delete on empresas
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_0_so_servidor before insert or update or delete on empresa_membros
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_auditar after insert or update on empresas
for each row execute function auditar_alteracao_tabela();
create trigger trg_auditar after insert or update on empresa_membros
for each row execute function auditar_alteracao_tabela();

-- Pedido: ligação à empresa e parte coberta por ela
alter table pedidos add column empresa_id uuid references empresas(id);
alter table pedidos add column valor_empresa integer not null default 0 check (valor_empresa >= 0);
create index pedidos_empresa_idx on pedidos (empresa_id) where empresa_id is not null;
grant insert (empresa_id) on pedidos to authenticated;

-- Ao criar o pedido: valida a filiação e calcula a parte da empresa (limitada e só fora de grupo)
create or replace function pedidos_conta_empresa() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_limite int;
begin
  if new.empresa_id is null or new.grupo_id is not null then
    new.empresa_id := case when new.grupo_id is not null then null else new.empresa_id end;
    new.valor_empresa := 0;
    return new;
  end if;
  select e.limite_refeicao into v_limite
    from empresas e
    join empresa_membros m on m.empresa_id = e.id
   where e.id = new.empresa_id and m.cliente_id = new.cliente_id
     and e.activa and e.deletado_em is null and m.deletado_em is null;
  if not found then
    new.empresa_id := null;
    new.valor_empresa := 0;
  else
    new.valor_empresa := least(greatest(new.subtotal + new.taxa_entrega - new.desconto_indicacao, 0), v_limite);
  end if;
  return new;
end $$;
revoke execute on function pedidos_conta_empresa() from public, anon, authenticated;

create trigger trg_pedidos_06_empresa before insert on pedidos
for each row execute function pedidos_conta_empresa();

-- A venda passa a incluir a parte da empresa como parcela "Conta da empresa" (não é dinheiro).
-- Reproduz a versão em vigor (uma venda por linha, parcelas distribuídas) + a parcela da empresa.
create or replace function gerar_venda_pedido() returns trigger
language plpgsql security definer set search_path = public as $function$
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
            else '[]'::jsonb end
    || case when new.valor_empresa > 0
            then jsonb_build_array(jsonb_build_object('metodo', 'Conta da empresa',
                                                      'valor', new.valor_empresa,
                                                      'empresa_id', new.empresa_id))
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

-- a_pagar (o que o cliente paga na entrega) passa a descontar a parte da empresa
create or replace function pedidos_operador()
 returns table(pedido_id uuid, criado_em timestamptz, estado text, cozinha_id uuid, cliente_nome text, cliente_telefone text, itens jsonb, subtotal integer, taxa_entrega integer, desconto_indicacao integer, credito_indicacao_usado integer, a_pagar integer, observacoes text, hora_prometida timestamptz, pagador_distinto boolean, ponto_entrega_id uuid, ponto_tipo text, ponto_lat double precision, ponto_lng double precision, ponto_referencia text, zona_nome text)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_gerir boolean := tem_permissao('pedidos.gerir');
begin
  if not (v_gerir or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  return query
  select x.id, x.criado_em, x.estado, x.cozinha_id, c.nome, c.telefone, x.itens,
         x.subtotal::int, x.taxa_entrega::int, x.desconto_indicacao::int, x.credito_indicacao_usado::int,
         (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado - x.pago_pacote - x.valor_empresa)::int,
         x.observacoes, x.hora_prometida, x.pagador_distinto,
         pe.id, pe.tipo, pe.lat, pe.lng, pe.referencia, z.nome
    from pedidos x
    join clientes c on c.id = x.cliente_id
    left join pontos_entrega pe on pe.id = x.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, x.zona_id)
   where x.deletado_em is null
     and x.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
     and (v_gerir or x.estado <> 'pendente')
     and (x.agendado_para is null or x.agendado_para <= now() + interval '90 minutes')
   order by coalesce(x.agendado_para, x.criado_em);
end $function$;

create or replace function pedidos_agendados()
returns table(pedido_id uuid, agendado_para timestamptz, cozinha_id uuid, cliente_nome text,
              itens jsonb, a_pagar integer, ponto_referencia text, zona_nome text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (tem_permissao('pedidos.gerir') or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  return query
  select x.id, x.agendado_para, x.cozinha_id, c.nome, x.itens,
         (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado - x.pago_pacote - x.valor_empresa)::int,
         pe.referencia, z.nome
    from pedidos x
    join clientes c on c.id = x.cliente_id
    left join pontos_entrega pe on pe.id = x.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, x.zona_id)
   where x.deletado_em is null and x.estado in ('pendente', 'confirmado')
     and x.agendado_para is not null and x.agendado_para > now() + interval '90 minutes'
   order by x.agendado_para;
end $$;

-- =====================================================================
-- Gestão das empresas (quem tem clientes.gerir) e conta do cliente
-- =====================================================================

create or replace function criar_empresa(p_nome text, p_limite int default 0) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not tem_permissao('clientes.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_nome is null or length(btrim(p_nome)) = 0 then raise exception 'nome_invalido' using errcode = 'P0001'; end if;
  if coalesce(p_limite, 0) < 0 or coalesce(p_limite, 0) > 1000000 then raise exception 'limite_invalido' using errcode = 'P0001'; end if;
  insert into empresas (nome, limite_refeicao, dispositivo_id) values (btrim(p_nome), coalesce(p_limite, 0), 'servidor')
  returning id into v_id;
  return v_id;
end $$;

create or replace function editar_empresa(p_id uuid, p_nome text, p_limite int, p_activa boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('clientes.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_nome is null or length(btrim(p_nome)) = 0 then raise exception 'nome_invalido' using errcode = 'P0001'; end if;
  update empresas set nome = btrim(p_nome), limite_refeicao = greatest(0, least(coalesce(p_limite, 0), 1000000)),
                      activa = coalesce(p_activa, activa), atualizado_em = now()
   where id = p_id and deletado_em is null;
  if not found then raise exception 'empresa_inexistente' using errcode = 'P0001'; end if;
end $$;

create or replace function listar_empresas() returns table (id uuid, nome text, limite_refeicao int, activa boolean, membros int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('clientes.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return query
    select e.id, e.nome, e.limite_refeicao, e.activa,
           (select count(*)::int from empresa_membros m where m.empresa_id = e.id and m.deletado_em is null)
      from empresas e where e.deletado_em is null order by e.activa desc, e.nome;
end $$;

-- Adiciona um membro pelo código que o cliente partilha (MB-dddd)
create or replace function empresa_adicionar_membro(p_empresa uuid, p_codigo text) returns void
language plpgsql security definer set search_path = public as $$
declare v_cliente uuid;
begin
  if not tem_permissao('clientes.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select cliente_id into v_cliente from codigos_indicacao where upper(codigo) = upper(btrim(p_codigo));
  if v_cliente is null then raise exception 'cliente_inexistente' using errcode = 'P0001'; end if;
  if not exists (select 1 from empresas where id = p_empresa and deletado_em is null) then
    raise exception 'empresa_inexistente' using errcode = 'P0001';
  end if;
  -- sai de qualquer empresa anterior (um cliente, uma empresa)
  update empresa_membros set deletado_em = now(), atualizado_em = now()
   where cliente_id = v_cliente and deletado_em is null;
  insert into empresa_membros (empresa_id, cliente_id, dispositivo_id) values (p_empresa, v_cliente, 'servidor');
end $$;

create or replace function empresa_remover_membro(p_empresa uuid, p_cliente uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('clientes.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  update empresa_membros set deletado_em = now(), atualizado_em = now()
   where empresa_id = p_empresa and cliente_id = p_cliente and deletado_em is null;
end $$;

create or replace function empresa_membros_lista(p_empresa uuid) returns table (cliente_id uuid, nome text, codigo text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('clientes.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return query
    select c.id, c.nome, ci.codigo
      from empresa_membros m
      join clientes c on c.id = m.cliente_id
      left join codigos_indicacao ci on ci.cliente_id = c.id
     where m.empresa_id = p_empresa and m.deletado_em is null
     order by c.nome;
end $$;

-- Relatório mensal: base da fatura única à empresa
create or replace function relatorio_empresa(p_empresa uuid, p_ano int, p_mes int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini date;
  v_fim date;
  r jsonb;
begin
  if not tem_permissao('clientes.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  v_ini := make_date(p_ano, p_mes, 1);
  v_fim := (v_ini + interval '1 month')::date;
  select jsonb_build_object(
    'empresa', (select nome from empresas where id = p_empresa),
    'mes', to_char(v_ini, 'MM/YYYY'),
    'total', coalesce(sum(x.valor_empresa), 0)::int,
    'pedidos', coalesce(jsonb_agg(jsonb_build_object(
                 'data', x.entregue_em, 'cliente', c.nome, 'valor', x.valor_empresa,
                 'itens', (select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || coalesce(i ->> 'nome', 'prato'), ', ')
                             from jsonb_array_elements(x.itens) i))
               order by x.entregue_em), '[]'::jsonb))
    into r
    from pedidos x join clientes c on c.id = x.cliente_id
   where x.empresa_id = p_empresa and x.valor_empresa > 0 and x.estado = 'entregue_pago'
     and x.entregue_em >= v_ini and x.entregue_em < v_fim and x.deletado_em is null;
  return r;
end $$;

-- Cliente: a sua conta de empresa (se for membro activo)
create or replace function minha_empresa() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  select jsonb_build_object('empresa_id', e.id, 'nome', e.nome, 'limite_refeicao', e.limite_refeicao)
    into r
    from empresa_membros m join empresas e on e.id = m.empresa_id
   where m.cliente_id = cliente_actual() and cliente_actual() is not null
     and m.deletado_em is null and e.deletado_em is null and e.activa;
  return r;
end $$;

revoke execute on function criar_empresa(text, int), editar_empresa(uuid, text, int, boolean), listar_empresas(),
  empresa_adicionar_membro(uuid, text), empresa_remover_membro(uuid, uuid), empresa_membros_lista(uuid),
  relatorio_empresa(uuid, int, int), minha_empresa() from public, anon;
grant execute on function criar_empresa(text, int), editar_empresa(uuid, text, int, boolean), listar_empresas(),
  empresa_adicionar_membro(uuid, text), empresa_remover_membro(uuid, uuid), empresa_membros_lista(uuid),
  relatorio_empresa(uuid, int, int), minha_empresa() to authenticated;
