-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I8 · Rede de cozinhas
--
--   1. Cozinhas para pedir (selector do cliente): activas; com multi_cozinha
--      desligado só a cozinha por defeito. Perfil (foto, história) só com
--      consentimento público e o interruptor perfil_cozinha.
--   2. O pedido é da cozinha escolhida (ou da do grupo): os pratos têm de ser dessa
--      cozinha e a cozinha tem de estar activa (pausada/inactiva não aceita pedidos).
--      O grupo pode ser criado noutra cozinha (com multi_cozinha).
--   3. Relatório comparativo das cozinhas num período (relatorios.exportar).
--   4. O10 e o ecrã do grupo (C13) dizem a cozinha do grupo.
--
-- O interruptor multi_cozinha não é ligado aqui.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Cozinhas para pedir
-- -----------------------------------------------------------------------------
create or replace function cozinha_aceita_pedidos(p_cozinha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from cozinhas c
                  where c.id = p_cozinha and c.estado = 'activa' and c.deletado_em is null
                    and (funcionalidade_activa('multi_cozinha') or c.id = cozinha_padrao()));
$$;

create or replace function cozinhas_para_pedir()
returns table (cozinha_id uuid, nome text, publica boolean, foto_url text, historia text, pratos integer)
language sql stable security definer set search_path = public as $$
  select c.id, c.nome,
         c.consentimento_publico and funcionalidade_activa('perfil_cozinha'),
         case when c.consentimento_publico and funcionalidade_activa('perfil_cozinha') then c.foto_url end,
         case when c.consentimento_publico and funcionalidade_activa('perfil_cozinha') then c.historia end,
         (select count(*)::int from cardapio m where m.cozinha_id = c.id and m.disponivel and m.deletado_em is null)
    from cozinhas c
   where cliente_actual() is not null and cozinha_aceita_pedidos(c.id)
   order by c.id = cozinha_padrao() desc, c.nome;
$$;

-- -----------------------------------------------------------------------------
-- 2. Pedido na cozinha escolhida
-- -----------------------------------------------------------------------------
create or replace function orcamento_pedido(p_itens jsonb, p_ponto_entrega uuid,
                                            p_cozinha uuid default null, p_grupo uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
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
    v_itens := v_itens || jsonb_strip_nulls(jsonb_build_object(
      'cardapio_id', v_card.id,
      'prato_base_id', v_card.prato_base_id,
      'nome', v_card.nome,
      'qtd', v_qtd::int,
      'preco_unitario', v_card.preco,
      'componentes_excluidos', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_excluidos', 'null') end,
      'componentes_ajustados', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_ajustados', 'null') end));
    v_subtotal := v_subtotal + v_qtd::int * v_card.preco;
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
end $$;

-- Grupo: com multi_cozinha a app escolhe a cozinha; tem de aceitar pedidos
create or replace function pedidos_grupo_validar() returns trigger
language plpgsql set search_path = public as $$
begin
  if e_escrita_cliente() then
    new.empresa_id := validar_novo_grupo(new.organizador_id, new.ponto_entrega_id, new.hora_entrega,
                                         new.prazo_adesao, new.modo_pagamento);
    if not funcionalidade_activa('multi_cozinha') or new.cozinha_id is null then
      new.cozinha_id := cozinha_padrao();
    end if;
    if not cozinha_aceita_pedidos(new.cozinha_id) then
      raise exception 'cozinha_indisponivel' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;

grant insert (cozinha_id) on pedidos_grupo to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Relatório comparativo das cozinhas (pedidos da app)
-- -----------------------------------------------------------------------------
create or replace function relatorio_comparativo(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'Africa/Luanda';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'Africa/Luanda';
  r jsonb;
begin
  perform exigir_permissao('relatorios.exportar');
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  with pagos as (
    select x.*, (x.subtotal + x.taxa_entrega - x.desconto_indicacao)::int as valor
      from pedidos x
     where x.estado = 'entregue_pago' and x.deletado_em is null
       and x.entregue_em >= v_ini and x.entregue_em < v_fim),
  primeiro as (   -- primeiro pedido pago de cada cliente em cada cozinha
    select x.cozinha_id, x.cliente_id, min(x.entregue_em) as em
      from pedidos x where x.estado = 'entregue_pago' and x.deletado_em is null
     group by x.cozinha_id, x.cliente_id),
  linhas as (
    select c.id, c.nome, c.estado,
           (select count(*) from pagos p where p.cozinha_id = c.id)::int as pedidos,
           (select coalesce(sum(p.valor), 0) from pagos p where p.cozinha_id = c.id)::int as vendas,
           (select count(*) from pedidos x where x.cozinha_id = c.id and x.estado = 'cancelado' and x.deletado_em is null
               and x.criado_em >= v_ini and x.criado_em < v_fim)::int as cancelados,
           (select count(distinct p.cliente_id) from pagos p where p.cozinha_id = c.id)::int as clientes,
           (select count(*) from primeiro f where f.cozinha_id = c.id and f.em >= v_ini and f.em < v_fim)::int as clientes_novos,
           (select count(*) from primeiro f where f.cozinha_id = c.id and f.em >= v_ini and f.em < v_fim
               and exists (select 1 from ligacoes_indicacao l where l.indicado_id = f.cliente_id))::int as clientes_indicacao,
           (select count(*) from pagos p where p.cozinha_id = c.id and p.hora_prometida is not null)::int as com_hora,
           (select count(*) from pagos p, parametros pa where pa.unico and p.cozinha_id = c.id and p.hora_prometida is not null
               and p.entregue_em <= p.hora_prometida + make_interval(mins => pa.tolerancia_entrega_min))::int as a_horas,
           (select round(avg(a.estrelas)::numeric, 1) from avaliacoes a
             where a.cozinha_id = c.id and not a.oculta and a.deletado_em is null
               and a.criado_em >= v_ini and a.criado_em < v_fim) as media_avaliacao,
           (select count(*) from avaliacoes a
             where a.cozinha_id = c.id and not a.oculta and a.deletado_em is null
               and a.criado_em >= v_ini and a.criado_em < v_fim)::int as avaliacoes
      from cozinhas c
     where c.deletado_em is null)
  select coalesce(jsonb_agg(jsonb_build_object(
           'cozinha_id', l.id, 'nome', l.nome, 'estado', l.estado,
           'pedidos', l.pedidos, 'vendas', l.vendas,
           'ticket_medio', case when l.pedidos > 0 then round(l.vendas::numeric / l.pedidos)::int end,
           'cancelados', l.cancelados, 'clientes', l.clientes,
           'clientes_novos', l.clientes_novos, 'clientes_indicacao', l.clientes_indicacao,
           'pct_a_horas', case when l.com_hora > 0 then round(100.0 * l.a_horas / l.com_hora, 1) end,
           'media_avaliacao', case when l.avaliacoes >= (select avaliacoes_minimo from parametros where unico)
                                   then l.media_avaliacao end,
           'avaliacoes', l.avaliacoes)
         order by l.vendas desc, l.nome), '[]')
    into r
    from linhas l;
  return r;
end $$;

-- -----------------------------------------------------------------------------
-- 4. O10 com a cozinha de cada grupo
-- -----------------------------------------------------------------------------
create or replace function grupos_operador(p_dia date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
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
                                   'a_pagar', (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado)::int,
                                   'observacoes', x.observacoes) order by x.criado_em)
                                  from pedidos x join clientes c on c.id = x.cliente_id
                                 where x.grupo_id = g.id and x.deletado_em is null), '[]'),
           'resumo', coalesce((select jsonb_agg(jsonb_build_object('nome', s.nome, 'qtd', s.qtd) order by s.nome)
                                 from (select i ->> 'nome' as nome, sum((i ->> 'qtd')::int) as qtd
                                         from pedidos x, jsonb_array_elements(x.itens) i
                                        where x.grupo_id = g.id and x.deletado_em is null and x.estado <> 'cancelado'
                                        group by i ->> 'nome') s), '[]'),
           'total_a_pagar', (select coalesce(sum(x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado), 0)::int
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
end $$;

-- C13: o grupo diz a cozinha (a app mostra o cardápio dessa cozinha)
create or replace function grupo_detalhe(p_codigo text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'grupo_id', g.id,
           'codigo_convite', g.codigo_convite,
           'cozinha_id', g.cozinha_id,
           'cozinha_nome', cz.nome,
           'hora_entrega', g.hora_entrega,
           'prazo_adesao', g.prazo_adesao,
           'estado', g.estado,
           'modo_pagamento', g.modo_pagamento,
           'local', pe.referencia,
           'organizador', split_part(trim(o.nome), ' ', 1),
           'sou_organizador', g.organizador_id = cliente_actual(),
           'taxa_estimada', taxa_grupo_estimada(g.id, cliente_actual()),
           'participantes', coalesce((
              select jsonb_agg(jsonb_build_object('nome', p.nome, 'estado', p.estado, 'sou_eu', p.sou_eu) order by p.primeiro, p.nome)
                from (select split_part(trim(c.nome), ' ', 1) as nome, x.cliente_id = cliente_actual() as sou_eu,
                             min(x.criado_em) as primeiro,
                             (array_agg(x.estado order by x.criado_em desc))[1] as estado
                        from pedidos x join clientes c on c.id = x.cliente_id
                       where x.grupo_id = g.id and x.deletado_em is null and x.estado <> 'cancelado'
                       group by c.nome, x.cliente_id) p), '[]'))
    from pedidos_grupo g
    join pontos_entrega pe on pe.id = g.ponto_entrega_id
    join clientes o on o.id = g.organizador_id
    join cozinhas cz on cz.id = g.cozinha_id
   where g.codigo_convite = upper(trim(p_codigo)) and g.deletado_em is null
     and cliente_actual() is not null and funcionalidade_activa('pedidos_grupo');
$$;

-- -----------------------------------------------------------------------------
-- 5. Privilégios
-- -----------------------------------------------------------------------------
revoke execute on function cozinhas_para_pedir(), relatorio_comparativo(date, date) from public, anon;
grant execute on function cozinhas_para_pedir(), relatorio_comparativo(date, date) to authenticated;
-- usada pelo trigger SECURITY INVOKER da criação de grupos
revoke execute on function cozinha_aceita_pedidos(uuid) from public, anon;
grant execute on function cozinha_aceita_pedidos(uuid) to authenticated;
revoke execute on function pedidos_grupo_validar() from public, anon, authenticated;
revoke execute on function orcamento_pedido(jsonb, uuid, uuid, uuid) from public, anon;
grant execute on function orcamento_pedido(jsonb, uuid, uuid, uuid) to authenticated;
