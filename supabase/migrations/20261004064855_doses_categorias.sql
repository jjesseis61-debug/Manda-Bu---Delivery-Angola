-- Cardápio: doses disponíveis e categorias limpas.
--
-- Doses do dia: a cozinha pode lançar quantas doses tem de um prato ("restam 20"). Em branco não há limite. Cada
-- pedido gasta doses e um pedido cancelado devolve-as (as restantes calculam-se dos pedidos feitos desde que as doses
-- foram lançadas, sem os cancelados). Chegando a 0 o prato aparece esgotado; um cliente não consegue pedir mais do que
-- as que restam (o pedido trava a linha do prato, para dois clientes não ficarem com a última). No dia seguinte o
-- limite deixa de valer e a cozinha lança as doses do dia. Pedidos da equipa contam mas não são travados.
--
-- Categorias: texto livre que divide o cardápio em secções na app do cliente. Ao gravar, tiram-se espaços a mais,
-- a primeira letra fica maiúscula e, se a cozinha já tiver a mesma categoria escrita de outra forma (maiúsculas),
-- usa-se a que já existe; assim não aparecem secções repetidas. As existentes são corrigidas.

alter table cardapio
  add column doses_dia integer check (doses_dia >= 0 and doses_dia <= 100000),
  add column doses_definidas_em timestamptz;
comment on column cardapio.doses_dia is 'Doses que a cozinha tinha quando as lançou (null = sem limite); valem só no dia em que foram lançadas';
comment on column cardapio.doses_definidas_em is 'Quando as doses foram lançadas (o servidor preenche ao mudar doses_dia)';

-- Doses que restam hoje (null = sem limite)
create or replace function doses_restantes(p_cardapio uuid) returns integer
language sql stable security definer set search_path = public as $$
  select greatest(c.doses_dia - coalesce((
           select sum(coalesce((i ->> 'qtd')::int, 1))
             from pedidos p, jsonb_array_elements(p.itens) i
            where p.cozinha_id = c.cozinha_id and p.deletado_em is null and p.estado <> 'cancelado'
              and p.criado_em >= c.doses_definidas_em
              and i ->> 'cardapio_id' = c.id::text), 0), 0)::int
    from cardapio c
   where c.id = p_cardapio and c.doses_dia is not null and c.doses_definidas_em is not null
     and (c.doses_definidas_em at time zone 'Africa/Luanda')::date = (now() at time zone 'Africa/Luanda')::date;
$$;
revoke execute on function doses_restantes(uuid) from public, anon, authenticated;

-- Para as apps: as doses que restam de cada prato com limite de uma cozinha
create or replace function doses_cardapio(p_cozinha uuid) returns table (cardapio_id uuid, restantes integer, lancadas integer)
language sql stable security definer set search_path = public as $$
  select c.id, doses_restantes(c.id), c.doses_dia
    from cardapio c
   where c.cozinha_id = p_cozinha and c.deletado_em is null and doses_restantes(c.id) is not null;
$$;
revoke execute on function doses_cardapio(uuid) from public, anon;
grant execute on function doses_cardapio(uuid) to authenticated;

-- Ao mudar as doses, regista quando; e limpa a categoria
create or replace function cardapio_normalizar() returns trigger
language plpgsql set search_path = public as $$
declare
  v text;
  v_existente text;
begin
  if tg_op = 'INSERT' or new.doses_dia is distinct from old.doses_dia then
    new.doses_definidas_em := case when new.doses_dia is null then null else now() end;
  end if;
  v := nullif(regexp_replace(trim(coalesce(new.categoria, '')), '\s+', ' ', 'g'), '');
  if v is not null then
    v := upper(left(v, 1)) || substr(v, 2);
    select categoria into v_existente from cardapio
     where cozinha_id = new.cozinha_id and id <> new.id and deletado_em is null
       and lower(trim(categoria)) = lower(v) and categoria = trim(categoria)
     limit 1;
    v := coalesce(v_existente, v);
  end if;
  new.categoria := v;
  return new;
end $$;
revoke execute on function cardapio_normalizar() from public, anon, authenticated;
create trigger trg_0_normalizar before insert or update on cardapio
for each row execute function cardapio_normalizar();

-- Corrige as categorias existentes (o trigger normaliza; a primeira de cada cozinha dá a grafia)
update cardapio set categoria = categoria, atualizado_em = now() where categoria is not null and categoria is distinct from
  upper(left(nullif(regexp_replace(trim(categoria), '\s+', ' ', 'g'), ''), 1)) || substr(nullif(regexp_replace(trim(categoria), '\s+', ' ', 'g'), ''), 2);

-- Pedido feito pela app: trava o prato e confirma que ainda há doses para todas as linhas dele
create or replace function pedidos_doses() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_rest integer;
begin
  if not e_escrita_cliente() then return new; end if;
  for r in select (i ->> 'cardapio_id')::uuid as cardapio_id, sum(coalesce((i ->> 'qtd')::int, 1)) as qtd
             from jsonb_array_elements(coalesce(new.itens, '[]')) i
            where i ->> 'cardapio_id' ~* '^[0-9a-f-]{36}$'
            group by 1 loop
    perform 1 from cardapio where id = r.cardapio_id and doses_dia is not null for update;
    if found then
      v_rest := doses_restantes(r.cardapio_id);
      if v_rest is not null and v_rest < r.qtd then
        raise exception 'doses_esgotadas' using errcode = 'P0001',
          detail = (select nome from cardapio where id = r.cardapio_id);
      end if;
    end if;
  end loop;
  return new;
end $$;
revoke execute on function pedidos_doses() from public, anon, authenticated;
create trigger trg_pedidos_01_doses before insert on pedidos
for each row execute function pedidos_doses();

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
    -- Doses do dia (a cozinha lançou quantas tem): não se pede mais do que as que restam
    if coalesce(doses_restantes(v_card.id), v_qtd::int) < v_qtd then
      raise exception 'doses_esgotadas' using errcode = 'P0001', detail = v_card.nome;
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
