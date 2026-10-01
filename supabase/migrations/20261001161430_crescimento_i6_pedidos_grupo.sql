-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I6 · Pedidos de grupo
--
--   1. C12: criar grupo pela app, validado no servidor (ponto de trabalho do próprio
--      cliente, prazo e hora coerentes, modo "empresa" só para clientes Empresa).
--      O organizador não altera o grupo directamente: fecha ou cancela por funções.
--   2. Pedido dentro do grupo: ponto e zona do grupo, desconto avaliado no ponto do
--      grupo; a taxa da entrega única fica a 0 até ao fecho.
--   3. Fecho do grupo (prazo de adesão, organizador ou operador): reparte a taxa da
--      zona pelos pedidos (regra_taxa_grupo: dividir; ou toda no pedido da empresa).
--   4. N10 com a hora do grupo; N11 15 minutos antes do prazo; envio de N10 e N11.
--   5. C13: grupo_detalhe (participantes por primeiro nome) e meus_grupos.
--   6. O10: grupos do dia com todos os pedidos e o resumo dos pratos; mudar o estado
--      de todos os pedidos de um grupo de uma vez. O grupo fica "entregue" quando
--      todos os pedidos estão entregues (ou cancelados).
--
-- O interruptor pedidos_grupo não é ligado aqui.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Criar grupo (C12)
-- -----------------------------------------------------------------------------
create or replace function validar_novo_grupo(p_organizador uuid, p_ponto uuid, p_hora timestamptz,
                                              p_prazo timestamptz, p_modo text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  v_cli   clientes;
  v_ponto pontos_entrega;
begin
  -- Chamada pela sessão da app (trigger SECURITY INVOKER): só para o próprio cliente
  if cliente_actual() is distinct from p_organizador then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  select * into v_cli from clientes where id = p_organizador and deletado_em is null;
  if not found then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  select * into v_ponto from pontos_entrega where id = p_ponto and deletado_em is null;
  if not found or v_ponto.tipo <> 'empresa'
     or not exists (select 1 from enderecos_cliente e
                     where e.ponto_entrega_id = p_ponto and e.cliente_id = p_organizador and e.deletado_em is null) then
    raise exception 'grupo_ponto_invalido' using errcode = 'P0001';
  end if;
  if v_ponto.zona_id is null then
    raise exception 'ponto_sem_zona' using errcode = 'P0001';
  end if;
  if p_prazo is null or p_hora is null or p_prazo < now() + interval '5 minutes'
     or p_hora < p_prazo + interval '15 minutes' or p_hora > now() + interval '7 days' then
    raise exception 'grupo_horas_invalidas' using errcode = 'P0001';
  end if;
  if p_modo = 'empresa' and v_cli.tipo <> 'Empresa' then
    raise exception 'grupo_empresa_invalida' using errcode = 'P0001';
  end if;
  return case when v_cli.tipo = 'Empresa' then v_cli.id end;
end $$;

-- SECURITY INVOKER: só aqui se sabe se é a app a escrever (corre depois de
-- trg_pedidos_grupo_antes_inserir, que já fixou o organizador)
create or replace function pedidos_grupo_validar() returns trigger
language plpgsql set search_path = public as $$
begin
  if e_escrita_cliente() then
    new.empresa_id := validar_novo_grupo(new.organizador_id, new.ponto_entrega_id, new.hora_entrega,
                                         new.prazo_adesao, new.modo_pagamento);
    if not funcionalidade_activa('multi_cozinha') then
      new.cozinha_id := cozinha_padrao();
    end if;
  end if;
  return new;
end $$;

create trigger trg_pedidos_grupo_validar
before insert on pedidos_grupo
for each row execute function pedidos_grupo_validar();

-- A app só escreve estas colunas ao criar; não altera grupos (fecha/cancela por funções)
revoke insert, update on pedidos_grupo from authenticated;
grant insert (id, dispositivo_id, criado_em, atualizado_em, organizador_id, ponto_entrega_id,
              hora_entrega, prazo_adesao, modo_pagamento)
  on pedidos_grupo to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Pedido dentro do grupo: preço no servidor
-- -----------------------------------------------------------------------------
-- Taxa por pessoa se o grupo fechasse agora com mais este cliente (informativa, C13)
create or replace function taxa_grupo_estimada(p_grupo uuid, p_cliente uuid default null) returns integer
language sql stable security definer set search_path = public as $$
  select case
           when g.modo_pagamento = 'empresa' or (p.regra_taxa_grupo = 'empresa' and g.empresa_id is not null)
             then case when coalesce(p_cliente, cliente_actual()) = g.empresa_id then round(coalesce(z.taxa, 0))::int else 0 end
           else ceil(coalesce(z.taxa, 0)
                     / greatest(1, (select count(distinct x.cliente_id) from pedidos x
                                     where x.grupo_id = g.id and x.deletado_em is null and x.estado <> 'cancelado')
                                   + case when exists (select 1 from pedidos x
                                                        where x.grupo_id = g.id and x.cliente_id = coalesce(p_cliente, cliente_actual())
                                                          and x.deletado_em is null and x.estado <> 'cancelado')
                                          then 0 else 1 end))::int
         end
    from pedidos_grupo g
    join pontos_entrega pe on pe.id = g.ponto_entrega_id
    left join zonas z on z.id = pe.zona_id
    cross join parametros p
   where g.id = p_grupo and p.unico;
$$;

create or replace function orcamento_pedido(p_itens jsonb, p_ponto_entrega uuid,
                                            p_cozinha uuid default null, p_grupo uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_cliente  uuid := cliente_actual();
  v_cozinha  uuid := case when funcionalidade_activa('multi_cozinha')
                          then coalesce(p_cozinha, cozinha_padrao()) else cozinha_padrao() end;
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
    v_grupo := grupo_para_adesao(p_grupo);
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

create or replace function pedidos_precos_cardapio() returns trigger
language plpgsql set search_path = public as $$
declare
  o jsonb;
begin
  if e_escrita_cliente() then
    o := orcamento_pedido(new.itens, new.ponto_entrega_id, new.cozinha_id, new.grupo_id);
    new.itens := o -> 'itens';
    new.subtotal := (o ->> 'subtotal')::int;
    new.taxa_entrega := (o ->> 'taxa_entrega')::int;
    new.zona_id := (o ->> 'zona_id')::uuid;
  end if;
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Fecho do grupo e repartição da taxa
-- -----------------------------------------------------------------------------
create or replace function fechar_grupo_interno(p_grupo uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  g        pedidos_grupo;
  v_taxa   integer;
  v_regra  text;
  v_n      integer;
  v_base   integer;
  v_resto  integer;
  v_alvo   uuid;
begin
  select * into g from pedidos_grupo where id = p_grupo and deletado_em is null for update;
  if not found or g.estado <> 'aberto' then
    return;
  end if;
  select round(coalesce(z.taxa, 0))::int into v_taxa
    from pontos_entrega pe left join zonas z on z.id = pe.zona_id where pe.id = g.ponto_entrega_id;
  select regra_taxa_grupo into v_regra from parametros where unico;

  select count(*) into v_n from pedidos
   where grupo_id = g.id and deletado_em is null and estado not in ('cancelado', 'entregue_pago', 'estornado');
  if v_n = 0 then
    update pedidos_grupo set estado = 'cancelado', atualizado_em = now() where id = g.id;
    perform registar_auditoria('grupo_fechado', 'pedidos_grupo', g.id, jsonb_build_object('pedidos', 0, 'estado', 'cancelado'));
    return;
  end if;

  -- Taxa toda no pedido da empresa (modo empresa, ou regra "empresa" com organizador Empresa)
  if g.empresa_id is not null and (g.modo_pagamento = 'empresa' or v_regra = 'empresa') then
    select id into v_alvo from pedidos
     where grupo_id = g.id and cliente_id = g.empresa_id and deletado_em is null
       and estado not in ('cancelado', 'entregue_pago', 'estornado')
     order by criado_em limit 1;
  end if;

  if v_alvo is not null then
    update pedidos set taxa_entrega = case when id = v_alvo then v_taxa else 0 end, atualizado_em = now()
     where grupo_id = g.id and deletado_em is null and estado not in ('cancelado', 'entregue_pago', 'estornado');
  else
    -- Dividir: parte inteira igual; os primeiros a aderir levam 1 Kz a mais até somar a taxa
    v_base := v_taxa / v_n;
    v_resto := v_taxa - v_base * v_n;
    update pedidos x set taxa_entrega = v_base + case when o.ordem <= v_resto then 1 else 0 end, atualizado_em = now()
      from (select id, row_number() over (order by criado_em, id) as ordem from pedidos
             where grupo_id = g.id and deletado_em is null and estado not in ('cancelado', 'entregue_pago', 'estornado')) o
     where x.id = o.id;
  end if;

  update pedidos_grupo set estado = 'fechado', atualizado_em = now() where id = g.id;
  perform registar_auditoria('grupo_fechado', 'pedidos_grupo', g.id,
    jsonb_build_object('pedidos', v_n, 'taxa', v_taxa, 'taxa_na_empresa', v_alvo is not null));
end $$;

-- Organizador ou operador fecha o grupo antes do prazo
create or replace function fechar_grupo(p_grupo uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pedidos_grupo where id = p_grupo and deletado_em is null
                    and (organizador_id = cliente_actual() or tem_permissao('pedidos.gerir'))) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if (select estado from pedidos_grupo where id = p_grupo) <> 'aberto' then
    raise exception 'estado_invalido' using errcode = 'P0001';
  end if;
  perform fechar_grupo_interno(p_grupo);
end $$;

-- Cancelar o grupo: os pedidos ainda não preparados são cancelados
create or replace function cancelar_grupo(p_grupo uuid, p_motivo text default null) returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  if not exists (select 1 from pedidos_grupo where id = p_grupo and deletado_em is null
                    and (organizador_id = cliente_actual() or tem_permissao('pedidos.gerir'))) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if (select estado from pedidos_grupo where id = p_grupo) not in ('aberto', 'fechado') then
    raise exception 'estado_invalido' using errcode = 'P0001';
  end if;
  if exists (select 1 from pedidos where grupo_id = p_grupo and deletado_em is null
                and estado in ('em_preparacao', 'em_entrega', 'entregue_pago')) then
    raise exception 'grupo_em_preparacao' using errcode = 'P0001';
  end if;
  update pedidos set estado = 'cancelado', motivo_cancelamento = coalesce(nullif(trim(p_motivo), ''), 'Grupo cancelado')
   where grupo_id = p_grupo and deletado_em is null and estado in ('pendente', 'confirmado');
  get diagnostics n = row_count;
  update pedidos_grupo set estado = 'cancelado', atualizado_em = now() where id = p_grupo;
  perform registar_auditoria('grupo_cancelado', 'pedidos_grupo', p_grupo,
                             jsonb_build_object('motivo', p_motivo, 'pedidos_cancelados', n));
  return n;
end $$;

-- O grupo acompanha os pedidos: em preparação e entregue
create or replace function pedidos_grupo_acompanhar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.grupo_id is not null and new.estado is distinct from old.estado then
    if new.estado in ('em_preparacao', 'em_entrega') then
      update pedidos_grupo set estado = 'em_preparacao', atualizado_em = now()
       where id = new.grupo_id and estado in ('aberto', 'fechado');
    elsif new.estado in ('entregue_pago', 'cancelado')
          and not exists (select 1 from pedidos where grupo_id = new.grupo_id and deletado_em is null
                             and estado not in ('entregue_pago', 'cancelado', 'estornado'))
          and exists (select 1 from pedidos where grupo_id = new.grupo_id and deletado_em is null
                         and estado = 'entregue_pago') then
      update pedidos_grupo set estado = 'entregue', atualizado_em = now()
       where id = new.grupo_id and estado in ('fechado', 'em_preparacao');
    end if;
  end if;
  return new;
end $$;

create trigger trg_pedidos_grupo_acompanhar
after update of estado on pedidos
for each row execute function pedidos_grupo_acompanhar();

-- -----------------------------------------------------------------------------
-- 4. N10 com a hora, N11 e o job dos grupos
-- -----------------------------------------------------------------------------
create or replace function notificacoes_completar_dados() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  lig ligacoes_indicacao;
begin
  if new.codigo = 'N2' and not (new.dados ? 'ganho_por_pedido') then
    select * into lig from ligacoes_indicacao
     where indicador_id = new.cliente_id and deletado_em is null
     order by ligado_em desc limit 1;
    if found then
      new.dados := new.dados || jsonb_build_object('ganho_por_pedido', lig.ganho_por_pedido_garantido,
                                                   'duracao_dias', lig.duracao_dias_garantida);
    end if;
  elsif new.codigo = 'N3' then
    if not (new.dados ? 'indicado_nome') then
      new.dados := new.dados || jsonb_build_object('indicado_nome',
        (select split_part(trim(c.nome), ' ', 1) from pedidos x join clientes c on c.id = x.cliente_id
          where x.id = (new.dados ->> 'pedido_id')::uuid));
    end if;
    if not (new.dados ? 'saldo_semana') then
      new.dados := new.dados || jsonb_build_object('saldo_semana',
        (select coalesce(sum(valor), 0) from ganhos_indicacao
          where indicador_id = new.cliente_id and estado in ('confirmado', 'pago')
            and confirmado_em >= inicio_semana_luanda() and deletado_em is null));
    end if;
  elsif new.codigo in ('N10', 'N11') and not (new.dados ? 'hora') then
    -- Hora do grupo para o texto e código do link para a app abrir o grupo
    new.dados := new.dados || (select jsonb_build_object('hora', to_char(g.hora_entrega at time zone 'Africa/Luanda', 'HH24"h"MI'),
                                                         'codigo_grupo', g.codigo_convite)
                                 from pedidos_grupo g where g.id = (new.dados ->> 'grupo_id')::uuid);
  end if;
  return new;
end $$;

-- De 5 em 5 minutos: N11 15 minutos antes do prazo; fecho dos grupos com o prazo passado
create or replace function job_grupos() returns void
language plpgsql security definer set search_path = public as $$
declare
  g uuid;
begin
  if not funcionalidade_activa('pedidos_grupo') then
    return;
  end if;
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select distinct m.cliente_id, 'N11', jsonb_build_object('grupo_id', gr.id)
    from pedidos_grupo gr
    cross join lateral (select gr.organizador_id as cliente_id
                        union
                        select x.cliente_id from pedidos x
                         where x.grupo_id = gr.id and x.deletado_em is null and x.estado <> 'cancelado') m
   where gr.estado = 'aberto' and gr.deletado_em is null
     and gr.prazo_adesao > now() and gr.prazo_adesao <= now() + interval '15 minutes'
     and not exists (select 1 from notificacoes_fila n
                      where n.codigo = 'N11' and n.cliente_id = m.cliente_id
                        and n.dados ->> 'grupo_id' = gr.id::text);
  for g in select id from pedidos_grupo
            where estado = 'aberto' and deletado_em is null and prazo_adesao <= now() loop
    perform fechar_grupo_interno(g);
  end loop;
end $$;

create or replace function agendar_jobs() returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron_ausente';
  end if;
  execute $c$select cron.schedule('mb_contadores_zona', '0 * * * *',    'select public.job_contadores_zona()')$c$;
  execute $c$select cron.schedule('mb_n6_expiracao',    '0 7 * * *',    'select public.job_n6_expiracao()')$c$;
  execute $c$select cron.schedule('mb_n5_lembrete',     '0 10 * * 1-5', 'select public.job_n5_lembrete()')$c$;
  execute $c$select cron.schedule('mb_n7_destaques',    '0 7 * * 1',    'select public.job_n7_destaques()')$c$;
  execute $c$select cron.schedule('mb_n9_avaliacao',    '*/15 * * * *', 'select public.job_n9_avaliacao()')$c$;
  execute $c$select cron.schedule('mb_grupos',          '*/5 * * * *',  'select public.job_grupos()')$c$;
  return 'agendado';
end $$;

select agendar_jobs();

create or replace function texto_notificacao(p_codigo text, p_dados jsonb, out titulo text, out corpo text)
language sql stable set search_path = public as $$
  select 'Manda Bué',
         case p_codigo
           when 'N2' then format('%s entrou com o teu código! Ganhas %s em cada pedido durante %s dias.',
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'Um amigo'),
                                 formatar_kz((p_dados ->> 'ganho_por_pedido')::numeric),
                                 p_dados ->> 'duracao_dias')
           when 'N3' then format('+%s: o pedido de %s foi entregue. Saldo desta semana: %s.',
                                 formatar_kz((p_dados ->> 'valor')::numeric),
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'um amigo'),
                                 formatar_kz((p_dados ->> 'saldo_semana')::numeric))
           when 'N4' then format('Passaste os %s esta semana. Os próximos ganhos ficam em verificação e são pagos assim que confirmarmos os pedidos.',
                                 formatar_kz((p_dados ->> 'limite')::numeric))
           when 'N5' then case when nullif(p_dados ->> 'prato_do_dia', '') is not null
                               then format('Hoje há %s. Partilha o teu código com os colegas antes do almoço.',
                                           p_dados ->> 'prato_do_dia')
                               else 'Partilha o teu código com os colegas antes do almoço.' end
           when 'N6' then format('O período de %s termina em 5 dias. Convida mais amigos para continuares a ganhar.',
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'um amigo'))
           when 'N7' then format('%s, estás em %s.º lugar este mês. %s para entrares no top %s.',
                                 p_dados ->> 'nome_exibido', p_dados ->> 'posicao',
                                 case when (p_dados ->> 'amigos_em_falta')::int = 1 then 'Falta 1 amigo'
                                      else format('Faltam %s amigos', p_dados ->> 'amigos_em_falta') end,
                                 p_dados ->> 'tamanho_top')
           when 'N8' then format('Pagámos %s por %s. Referência: %s.',
                                 formatar_kz((p_dados ->> 'valor')::numeric),
                                 case p_dados ->> 'metodo'
                                   when 'multicaixa_express' then 'Multicaixa Express'
                                   when 'unitel_money' then 'Unitel Money'
                                   else coalesce(p_dados ->> 'metodo', '') end,
                                 p_dados ->> 'referencia')
           when 'N9' then format('Como estava o %s da %s? Avalia em 10 segundos.',
                                 coalesce(p_dados ->> 'refeicao', 'almoço'), p_dados ->> 'cozinha_nome')
           when 'N10' then format('%s juntou-se ao teu grupo das %s. Já são %s.',
                                  coalesce(nullif(p_dados ->> 'participante_nome', ''), 'Um colega'),
                                  p_dados ->> 'hora', p_dados ->> 'participantes')
           when 'N11' then format('O grupo das %s fecha em 15 minutos.', p_dados ->> 'hora')
           when 'N12' then format('Parabéns, turno da %s: %s!',
                                  case p_dados ->> 'periodo' when 'manha' then 'manhã' else p_dados ->> 'periodo' end,
                                  case p_dados ->> 'tipo'
                                    when 'entregas_a_horas'  then 'entregas a horas esta semana'
                                    when 'menos_desperdicio' then 'menos desperdício esta semana'
                                    when 'caixa_certa'       then 'caixa certa esta semana'
                                    else coalesce(nullif(trim(p_dados ->> 'nota'), ''), 'bom trabalho esta semana') end)
         end;
$$;

create or replace function notificacoes_por_enviar(p_limite integer default 100)
returns table (id uuid, cliente_id uuid, funcionario_id uuid, destino text, codigo text,
               titulo text, corpo text, dados jsonb, tokens text[])
language sql stable security definer set search_path = public as $$
  select n.id, n.cliente_id, n.funcionario_id,
         case when n.funcionario_id is not null then 'funcionario' else 'cliente' end,
         n.codigo, t.titulo, t.corpo, n.dados,
         coalesce((select array_agg(d.token order by d.atualizado_em desc) from dispositivos_push d
                    where d.activo and d.deletado_em is null
                      and (d.cliente_id = n.cliente_id or d.funcionario_id = n.funcionario_id)), '{}')
    from notificacoes_fila n
    cross join lateral texto_notificacao(n.codigo, n.dados) t
    left join preferencias_notificacao pn on pn.cliente_id = n.cliente_id and pn.deletado_em is null
   where n.enviada_em is null and n.deletado_em is null
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N10', 'N11', 'N12')
     and funcionalidade_activa(funcionalidade_da_notificacao(n.codigo))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
     and not (n.codigo = 'N9' and exists (select 1 from avaliacoes a where a.pedido_id::text = n.dados ->> 'pedido_id'))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$$;

-- -----------------------------------------------------------------------------
-- 5. C13: o grupo visto pelos colegas
-- -----------------------------------------------------------------------------
-- Pelo código do link (antes ou depois de aderir): sem ids de clientes nem telefones
create or replace function grupo_detalhe(p_codigo text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'grupo_id', g.id,
           'codigo_convite', g.codigo_convite,
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
   where g.codigo_convite = upper(trim(p_codigo)) and g.deletado_em is null
     and cliente_actual() is not null and funcionalidade_activa('pedidos_grupo');
$$;

-- Grupos do próprio cliente (organizados ou com pedido), das últimas 24 horas em diante
create or replace function meus_grupos()
returns table (codigo_convite text, hora_entrega timestamptz, prazo_adesao timestamptz, estado text,
               local text, sou_organizador boolean, participantes integer)
language sql stable security definer set search_path = public as $$
  select g.codigo_convite, g.hora_entrega, g.prazo_adesao, g.estado, pe.referencia,
         g.organizador_id = cliente_actual(),
         (select count(distinct x.cliente_id)::int from pedidos x
           where x.grupo_id = g.id and x.deletado_em is null and x.estado <> 'cancelado')
    from pedidos_grupo g join pontos_entrega pe on pe.id = g.ponto_entrega_id
   where g.deletado_em is null and funcionalidade_activa('pedidos_grupo')
     and g.hora_entrega >= now() - interval '1 day'
     and (g.organizador_id = cliente_actual()
          or exists (select 1 from pedidos x where x.grupo_id = g.id and x.cliente_id = cliente_actual()
                                               and x.deletado_em is null))
   order by g.hora_entrega;
$$;

-- -----------------------------------------------------------------------------
-- 6. O10: grupos do dia
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
    join clientes o on o.id = g.organizador_id
    join pontos_entrega pe on pe.id = g.ponto_entrega_id
    left join zonas z on z.id = pe.zona_id
   where g.deletado_em is null
     and (g.hora_entrega at time zone 'Africa/Luanda')::date = v_dia;
  return r;
end $$;

-- Mudar o estado de todos os pedidos de um grupo de uma vez (confirmar, preparar, sair)
create or replace function mudar_estado_grupo(p_grupo uuid, p_estado text) returns integer
language plpgsql security definer set search_path = public as $$
declare
  x record;
  n integer := 0;
  v_ordem text[] := array['pendente', 'confirmado', 'em_preparacao', 'em_entrega'];
begin
  if p_estado not in ('confirmado', 'em_preparacao', 'em_entrega') then
    raise exception 'estado_invalido' using errcode = 'P0001';
  end if;
  if not exists (select 1 from pedidos_grupo where id = p_grupo and deletado_em is null) then
    raise exception 'grupo_inexistente' using errcode = 'P0001';
  end if;
  for x in select id, estado from pedidos
            where grupo_id = p_grupo and deletado_em is null
              and array_position(v_ordem, estado) < array_position(v_ordem, p_estado)
            order by criado_em loop
    perform mudar_estado_pedido(x.id, p_estado);   -- verifica a permissão e audita cada pedido
    n := n + 1;
  end loop;
  return n;
end $$;

-- -----------------------------------------------------------------------------
-- 7. Privilégios
-- -----------------------------------------------------------------------------
revoke execute on function grupo_detalhe(text), meus_grupos(), fechar_grupo(uuid), cancelar_grupo(uuid, text),
                           grupos_operador(date), mudar_estado_grupo(uuid, text)
  from public, anon;
grant execute on function grupo_detalhe(text), meus_grupos(), fechar_grupo(uuid), cancelar_grupo(uuid, text),
                          grupos_operador(date), mudar_estado_grupo(uuid, text)
  to authenticated;
revoke execute on function validar_novo_grupo(uuid, uuid, timestamptz, timestamptz, text) from public, anon;
grant execute on function validar_novo_grupo(uuid, uuid, timestamptz, timestamptz, text) to authenticated;
revoke execute on function taxa_grupo_estimada(uuid, uuid)  from public, anon, authenticated;
revoke execute on function fechar_grupo_interno(uuid)       from public, anon, authenticated;
revoke execute on function job_grupos()                     from public, anon, authenticated;
revoke execute on function agendar_jobs()                   from public, anon, authenticated;
revoke execute on function pedidos_grupo_validar()          from public, anon, authenticated;
revoke execute on function pedidos_grupo_acompanhar()       from public, anon, authenticated;
revoke execute on function pedidos_precos_cardapio()        from public, anon, authenticated;
revoke execute on function notificacoes_completar_dados()   from public, anon, authenticated;
revoke execute on function texto_notificacao(text, jsonb)   from public, anon, authenticated;
revoke execute on function notificacoes_por_enviar(integer) from public, anon, authenticated;
grant execute on function notificacoes_por_enviar(integer), texto_notificacao(text, jsonb) to service_role;
revoke execute on function orcamento_pedido(jsonb, uuid, uuid, uuid) from public, anon;
grant execute on function orcamento_pedido(jsonb, uuid, uuid, uuid) to authenticated;
