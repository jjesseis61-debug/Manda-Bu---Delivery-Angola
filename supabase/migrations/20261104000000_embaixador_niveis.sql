-- =============================================================================
-- Embaixador — 2 níveis (Fase 2, economia)
-- -----------------------------------------------------------------------------
-- Evolui o programa de indicação para venda social com dois degraus:
--   Normal  →  Embaixador (>= limiar_embaixador indicados activos)
--           →  Embaixador Ouro (>= limiar_ouro indicados activos)
--
-- Decisões (com o Jesse, 2026-11-07; ver docs/plano-embaixador.md):
--  * Degrau BAIXO e motivador (comissão maior + bónus) entra cedo (5 activos).
--  * Degrau ALTO e sensível (isenção do limite semanal — o perk de hoje) fica
--    em cima (30 activos). Assim NÃO se baixa a segurança actual.
--  * "Activo" = indicado com pelo menos um ganho confirmado/pago E vínculo vivo
--    (não basta criar a ligação — isso seria trivialmente fraudável).
--  * Bónus de boas-vindas = uma vez por embaixador, na 1.ª vitória confirmada
--    (a "primeira vitória garantida" de Bandura; já prometida na app a todos).
--  * Promoção automática só SOBE de nível; a despromoção suave fica para um
--    cron posterior (nunca se retira um nível/benefício dentro do trigger).
--  * A comissão por ligação continua GARANTIDA pelo valor snapshot
--    (ganho_por_pedido_garantido); o nível só pode AUMENTAR a comissão, nunca
--    reduzi-la — greatest(snapshot, taxa_do_nivel).
--
-- Sem novas funções chamáveis por 'authenticated' → 12_privilegios não muda.
-- =============================================================================

-- ---------------------------------------------------------------- 1. Parâmetros
alter table parametros
  add column if not exists ganho_por_pedido_embaixador int not null default 150
    check (ganho_por_pedido_embaixador >= 0),
  add column if not exists ganho_por_pedido_ouro       int not null default 200
    check (ganho_por_pedido_ouro >= 0),
  add column if not exists bonus_boas_vindas            int not null default 300
    check (bonus_boas_vindas >= 0),
  add column if not exists limiar_ouro                  int not null default 30
    check (limiar_ouro > 0);

-- O limiar_embaixador de hoje (30) passa a ser o degrau de OURO; a entrada desce para 5.
update parametros set limiar_ouro = limiar_embaixador where unico and limiar_ouro = 30 and limiar_embaixador <> 30;
update parametros set limiar_ouro = greatest(limiar_ouro, limiar_embaixador) where unico;
update parametros set limiar_embaixador = 5 where unico and limiar_embaixador > 5;
alter table parametros alter column limiar_embaixador set default 5;

-- ---------------------------------------------------------------- 2. Níveis válidos
alter table codigos_indicacao drop constraint if exists codigos_indicacao_nivel_check;
alter table codigos_indicacao
  add constraint codigos_indicacao_nivel_check check (nivel in ('normal','embaixador','ouro'));

-- Setter manual (operador) passa a aceitar 'ouro'
create or replace function definir_nivel_indicador(p_cliente uuid, p_nivel text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform exigir_permissao('plataforma.parametros');
  if p_nivel not in ('normal','embaixador','ouro') then
    raise exception 'nivel_invalido' using errcode = 'P0001';
  end if;
  update codigos_indicacao set nivel = p_nivel, atualizado_em = now() where cliente_id = p_cliente;
  if not found then raise exception 'cliente_sem_codigo' using errcode = 'P0001'; end if;
  perform registar_auditoria('nivel_indicador_alterado', 'codigos_indicacao', p_cliente,
                             jsonb_build_object('nivel', p_nivel));
end $$;

-- ---------------------------------------------------------------- 3. Motor de ganhos
-- Reescreve processar_ganho_indicacao() com: comissão por nível (floor no valor
-- garantido), bónus de boas-vindas, isenção do limite semanal só para 'ouro' e
-- promoção automática (apenas sobe).
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
  v_valor         int;
  v_bonus         int := 0;
  n_activos       int;
  nivel_alvo      text;
  promovido_para  text;
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

  -- Nível actual do indicador (define a comissão e a isenção)
  select nivel into nivel_ind from codigos_indicacao where cliente_id = lig.indicador_id;
  nivel_ind := coalesce(nivel_ind, 'normal');

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

  -- Limite por local residencial: amigos DA MESMA PESSOA na mesma morada (vizinhos de prédio
  -- convidados por pessoas diferentes não se bloqueiam uns aos outros)
  select tipo into v_tipo_local from pontos_entrega where id = new.ponto_entrega_id;
  if v_estado = 'confirmado' and v_tipo_local = 'residencial' then
    select count(distinct g2.indicado_id) into indicados_local
      from pontos_entrega_proximos(new.ponto_entrega_id) pp(id)
      join pedidos x on x.ponto_entrega_id = pp.id
      join ganhos_indicacao g2 on g2.pedido_id = x.id
     where g2.estado <> 'anulado'
       and g2.indicador_id = lig.indicador_id
       and g2.indicado_id <> new.cliente_id;
    if indicados_local >= p.max_indicados_por_local then
      v_estado := 'em_verificacao'; v_motivo := 'limite_local';
    end if;
  end if;

  -- Limite semanal: isento APENAS para Embaixador Ouro (o perk sensível fica no topo)
  if v_estado = 'confirmado' and nivel_ind is distinct from 'ouro' then
    select coalesce(sum(valor), 0) into total_sem
      from ganhos_indicacao
     where indicador_id = lig.indicador_id
       and estado in ('confirmado','pago')
       and confirmado_em >= inicio_semana_luanda();
    if total_sem >= p.limite_verificacao_semanal then
      v_estado := 'em_verificacao'; v_motivo := 'limite_semanal';
    end if;
  end if;

  -- Comissão por nível, nunca abaixo do valor garantido na ligação
  v_valor := greatest(lig.ganho_por_pedido_garantido,
                      case nivel_ind
                        when 'ouro'       then p.ganho_por_pedido_ouro
                        when 'embaixador' then p.ganho_por_pedido_embaixador
                        else                   p.ganho_por_pedido
                      end);

  -- Bónus de boas-vindas: uma vez por embaixador, na 1.ª vitória confirmada
  if v_estado = 'confirmado' and p.bonus_boas_vindas > 0
     and not exists (select 1 from ganhos_indicacao
                      where indicador_id = lig.indicador_id and estado in ('confirmado','pago')) then
    v_bonus := p.bonus_boas_vindas;
    v_valor := v_valor + v_bonus;
  end if;

  insert into ganhos_indicacao
    (pedido_id, indicador_id, indicado_id, valor, estado, motivo, confirmado_em, dispositivo_id)
  values
    (new.id, lig.indicador_id, new.cliente_id, v_valor, v_estado, v_motivo,
     case when v_estado = 'confirmado' then now() end, 'servidor')
  returning id into v_ganho;

  perform registar_auditoria('ganho_indicacao_criado', 'ganhos_indicacao', v_ganho,
    jsonb_build_object('estado', v_estado, 'motivo', v_motivo, 'pedido_id', new.id,
                       'nivel', nivel_ind, 'valor', v_valor, 'bonus_boas_vindas', v_bonus));

  if v_estado = 'confirmado' then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N3', jsonb_build_object(
      'pedido_id', new.id,
      'valor', v_valor,
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

  -- Promoção automática (só sobe): conta indicados ACTIVOS = com ganho confirmado/pago
  -- e vínculo vivo. Alinhada com meu_perfil.indicados_activos.
  if v_estado = 'confirmado' then
    select count(distinct g3.indicado_id) into n_activos
      from ganhos_indicacao g3
      join ligacoes_indicacao l3
        on l3.indicado_id = g3.indicado_id and l3.indicador_id = g3.indicador_id
       and l3.deletado_em is null
     where g3.indicador_id = lig.indicador_id
       and g3.estado in ('confirmado','pago')
       and (l3.expira_em is null or l3.expira_em > now());

    nivel_alvo := case when n_activos >= p.limiar_ouro       then 'ouro'
                       when n_activos >= p.limiar_embaixador  then 'embaixador'
                       else 'normal' end;

    update codigos_indicacao
       set nivel = nivel_alvo, atualizado_em = now()
     where cliente_id = lig.indicador_id
       and (case nivel      when 'ouro' then 2 when 'embaixador' then 1 else 0 end)
         < (case nivel_alvo when 'ouro' then 2 when 'embaixador' then 1 else 0 end)
    returning nivel into promovido_para;

    if promovido_para is not null then
      perform registar_auditoria('nivel_indicador_promovido', 'codigos_indicacao', lig.indicador_id,
                                 jsonb_build_object('nivel', promovido_para, 'indicados_activos', n_activos));
    end if;
  end if;

  return new;
end $$;

-- ---------------------------------------------------------------- 4. Perfil (app)
-- Expõe o nível e o nº de indicados activos para o painel do embaixador.
-- (Os limiares vêm da tabela parametros, que a app já lê por select('*').)
create or replace function meu_perfil() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'cliente_id', c.id,
           'nome', c.nome,
           'primeiro_nome', split_part(trim(c.nome), ' ', 1),
           'tipo', c.tipo,
           'telefone', c.telefone,
           'codigo', ci.codigo,
           'pseudonimo', pd.pseudonimo,
           'suspensa', c.suspensa_em is not null,
           'recuperar_ate', c.purgar_em,
           'nivel', coalesce(ci.nivel, 'normal'),
           'indicados_activos', (
             select count(distinct g.indicado_id)::int
               from ganhos_indicacao g
               join ligacoes_indicacao l2
                 on l2.indicado_id = g.indicado_id and l2.indicador_id = g.indicador_id
                and l2.deletado_em is null
              where g.indicador_id = c.id
                and g.estado in ('confirmado','pago')
                and (l2.expira_em is null or l2.expira_em > now())),
           'tem_ligacao', exists (select 1 from ligacoes_indicacao l
                                   where l.indicado_id = c.id and l.deletado_em is null),
           'cliente_novo', not cliente_ja_comprou(c.id))
    from clientes c
    left join codigos_indicacao ci on ci.cliente_id = c.id
    left join perfil_destaques pd on pd.cliente_id = c.id
   where c.auth_user_id = auth.uid() and auth.uid() is not null and c.deletado_em is null;
$$;
