-- =============================================================================
-- Cozinha de condomínio — Fase 2
-- -----------------------------------------------------------------------------
--  1. Lista de espera: com as vagas cheias, quem pede pelo link fica em espera (se o condomínio a
--     tiver ligada). Quando sai alguém ou as vagas sobem, o primeiro da espera entra sozinho
--     (activo, ou pendente se a cozinha aprova cada morador) e recebe um aviso.
--  2. Campanhas (promoções) por condomínio, por zona de entrega ou para todos, de uma cozinha ou de
--     todas: percentagem nos pratos ou preço especial em pratos escolhidos; datas, dias da semana e
--     horas; pedido mínimo; só para membros do condomínio; limites por cliente e no total.
--     O desconto entra no PREÇO dos pratos do pedido (preco_original fica guardado em cada linha):
--     o valor a pagar, as vendas e os relatórios ficam certos sem mexer no resto do circuito.
--     Regra (decisão do dono, 16/11/2026): não acumula com o desconto de convite — vale o maior.
--     Quando vale a campanha, o desconto de convite não se gasta (fica para outro pedido).
--  3. Relatório do condomínio: membros, espera, pedidos, vendas, ticket médio, quem pede e o que sai.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Lista de espera
-- -----------------------------------------------------------------------------
alter table condominios add column if not exists lista_espera boolean not null default true;
-- A ordem da espera é a da hora do pedido (clock_timestamp distingue pedidos na mesma transacção)
alter table condominio_membros alter column criado_em set default clock_timestamp();
comment on column condominios.lista_espera is 'Com as vagas cheias, quem pede pelo link fica em lista de espera';

alter table condominio_membros drop constraint if exists condominio_membros_estado_check;
alter table condominio_membros add constraint condominio_membros_estado_check
  check (estado in ('pendente', 'activo', 'espera', 'recusado', 'removido'));
drop index if exists condominio_membros_um_por_cliente;
create unique index if not exists condominio_membros_um_por_cliente
  on condominio_membros (condominio_id, cliente_id) where estado in ('pendente', 'activo', 'espera');

-- Posição na lista de espera (1 = o próximo a entrar)
create or replace function condominio_posicao_espera(p_membro uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from condominio_membros a join condominio_membros m on m.id = p_membro
   where a.condominio_id = m.condominio_id and a.estado = 'espera'
     and (a.criado_em, a.id) <= (m.criado_em, m.id);
$$;
revoke execute on function condominio_posicao_espera(uuid) from public, anon, authenticated;

-- Passa os primeiros da espera para dentro enquanto houver vagas
create or replace function condominio_promover_espera(p_cond uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  c   condominios;
  m   condominio_membros;
  n   int := 0;
begin
  select * into c from condominios where id = p_cond and deletado_em is null;
  if not found then return 0; end if;
  loop
    exit when condominio_ocupadas(p_cond) >= c.vagas;
    select * into m from condominio_membros
     where condominio_id = p_cond and estado = 'espera'
     order by criado_em, id limit 1 for update skip locked;
    exit when not found;
    update condominio_membros
       set estado = case when c.aprovacao_manual then 'pendente' else 'activo' end,
           aprovado_em = case when c.aprovacao_manual then null else now() end,
           atualizado_em = now()
     where id = m.id;
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (m.cliente_id, 'N31', jsonb_build_object(
      'titulo', case when c.aprovacao_manual then 'Saíste da lista de espera' else 'Bem-vindo ao ' || c.nome || ' 🏘️' end,
      'corpo', case when c.aprovacao_manual
                    then 'Abriu uma vaga no ' || c.nome || '. A cozinha vai confirmar a tua entrada.'
                    else 'Abriu uma vaga e já estás na lista. Podes pedir na cozinha do condomínio quando estiveres lá.' end,
      'link', '/inicio'));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function condominio_promover_espera(uuid) from public, anon, authenticated;

-- Os membros em espera não ocupam vaga (condominio_ocupadas conta só activos + pendentes: já é assim)

-- Pedir para entrar: com as vagas cheias e a espera ligada, entra em espera (devolve 'espera')
create or replace function condominio_pedir_entrada(p_codigo text, p_bloco text, p_casa text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := cliente_actual();
  c     condominios;
  v_e   text;
begin
  if v_cli is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not funcionalidade_activa('condominios') then raise exception 'funcionalidade_inactiva' using errcode = 'P0001'; end if;
  select * into c from condominios where codigo = upper(trim(p_codigo)) and deletado_em is null for update;
  if not found then raise exception 'condominio_inexistente' using errcode = 'P0001'; end if;
  select estado into v_e from condominio_membros
   where condominio_id = c.id and cliente_id = v_cli and estado in ('pendente', 'activo', 'espera');
  if v_e is not null then return v_e; end if;
  if length(coalesce(trim(p_bloco), '') || coalesce(trim(p_casa), '')) = 0 then
    raise exception 'casa_obrigatoria' using errcode = 'P0001';
  end if;
  if condominio_lista_aberta(c) then
    v_e := case when c.aprovacao_manual then 'pendente' else 'activo' end;
  elsif c.lista_espera and c.inscricoes_abertas and (c.inscricoes_ate is null or now() < c.inscricoes_ate) then
    v_e := 'espera'; -- só falta vaga
  else
    raise exception 'lista_fechada' using errcode = 'P0001';
  end if;
  insert into condominio_membros (condominio_id, cliente_id, estado, bloco, casa, origem, aprovado_em)
  values (c.id, v_cli, v_e, nullif(trim(p_bloco), ''), nullif(trim(p_casa), ''), 'link',
          case when v_e = 'activo' then now() end);
  return v_e;
end $$;

-- O link mostra também a espera e a posição
create or replace function condominio_pelo_codigo(p_codigo text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c   condominios;
  m   condominio_membros;
begin
  if cliente_actual() is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not funcionalidade_activa('condominios') then return null; end if;
  select * into c from condominios where codigo = upper(trim(p_codigo)) and deletado_em is null;
  if not found then return null; end if;
  select * into m from condominio_membros
   where condominio_id = c.id and cliente_id = cliente_actual() and estado in ('pendente', 'activo', 'espera');
  return jsonb_build_object(
    'nome', c.nome,
    'cozinha', (select nome from cozinhas where id = c.cozinha_id),
    'lista_aberta', condominio_lista_aberta(c),
    'lista_espera', c.lista_espera and c.inscricoes_abertas and (c.inscricoes_ate is null or now() < c.inscricoes_ate),
    'em_espera', (select count(*) from condominio_membros where condominio_id = c.id and estado = 'espera'),
    'vagas_livres', greatest(c.vagas - condominio_ocupadas(c.id), 0),
    'inscricoes_ate', c.inscricoes_ate,
    'aprovacao_manual', c.aprovacao_manual,
    'meu_estado', m.estado,
    'minha_posicao', case when m.estado = 'espera' then condominio_posicao_espera(m.id) end);
end $$;

-- Recusar/remover liberta a vaga para a espera; a cozinha pode tirar alguém da espera
do $$
declare
  v_def  text := pg_get_functiondef('condominio_decidir_membro(uuid,text)'::regprocedure);
  v_novo text;
begin
  if position('condominio_promover_espera' in v_def) > 0 then return; end if; -- já aplicado
  -- remover também tira da espera
  v_novo := replace(v_def, $q$if m.estado not in ('pendente', 'activo') then raise exception 'estado_invalido'$q$,
                           $q$if m.estado not in ('pendente', 'activo', 'espera') then raise exception 'estado_invalido'$q$);
  v_novo := regexp_replace(v_novo, '(\n\s*perform\s+registar_auditoria\(''condominio_membro_''\s*\|\|\s*p_accao)',
    E'\n  perform condominio_promover_espera(m.condominio_id);\\1');
  if v_novo = v_def or position('condominio_promover_espera' in v_novo) = 0 or position($q$'activo', 'espera'$q$ in v_novo) = 0 then
    raise exception 'condominio_decidir_membro não tem o formato esperado';
  end if;
  execute v_novo;
end $$;

-- A lista e os membros mostram a espera
create or replace function condominio_membros_lista(p_cond uuid)
returns table (id uuid, cliente_nome text, telefone text, bloco text, casa text, estado text, origem text,
               criado_em timestamptz, ultimo_pedido timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not pode_gerir_condominio(p_cond) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return query
  select m.id, cl.nome, cl.telefone, m.bloco, m.casa, m.estado, m.origem, m.criado_em,
         (select max(p.criado_em) from pedidos p join condominios c on c.id = m.condominio_id
           where p.cliente_id = m.cliente_id and p.cozinha_id = c.cozinha_id and p.deletado_em is null)
    from condominio_membros m join clientes cl on cl.id = m.cliente_id
   where m.condominio_id = p_cond and m.estado in ('pendente', 'activo', 'espera')
   order by case m.estado when 'pendente' then 0 when 'activo' then 1 else 2 end,
            case when m.estado = 'espera' then m.criado_em end, cl.nome;
end $$;

do $$
declare
  v_def  text := pg_get_functiondef('condominios_lista()'::regprocedure);
  v_novo text;
begin
  if position('''espera''' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def, '(''codigo''\s*,\s*c\.codigo\s*,)',
    E'''lista_espera'', c.lista_espera,\n    ''espera'', (select count(*) from condominio_membros m where m.condominio_id = c.id and m.estado = ''espera''),\n    \\1');
  if v_novo = v_def then raise exception 'condominios_lista não tem o formato esperado'; end if;
  execute v_novo;
end $$;

-- guardar_condominio: lista_espera e, ao subir as vagas, entra quem está à espera
do $$
declare
  v_def  text := pg_get_functiondef('guardar_condominio(jsonb)'::regprocedure);
  v_novo text;
begin
  if position('lista_espera' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def, '(aprovacao_manual\s*=\s*coalesce\(\(p\s*->>\s*''aprovacao_manual''\)::boolean,\s*aprovacao_manual\),)',
    E'\\1\n           lista_espera = coalesce((p ->> ''lista_espera'')::boolean, lista_espera),');
  v_novo := regexp_replace(v_novo, '(\n\s*return\s+v_id;\s*\nend)',
    E'\n  update condominios set lista_espera = coalesce((p ->> ''lista_espera'')::boolean, lista_espera) where id = v_id;\n  perform condominio_promover_espera(v_id);\\1');
  if position('condominio_promover_espera' in v_novo) = 0 or position('lista_espera = coalesce' in v_novo) = 0 then
    raise exception 'guardar_condominio não tem o formato esperado';
  end if;
  execute v_novo;
end $$;

-- meus_condominios inclui a espera
create or replace function meus_condominios()
returns table (nome text, estado text, bloco text, casa text)
language sql stable security definer set search_path = public as $$
  select c.nome, m.estado, m.bloco, m.casa
    from condominio_membros m join condominios c on c.id = m.condominio_id and c.deletado_em is null
   where m.cliente_id = cliente_actual() and m.estado in ('pendente', 'activo', 'espera')
   order by c.nome;
$$;

-- -----------------------------------------------------------------------------
-- 2. Campanhas
-- -----------------------------------------------------------------------------
create table if not exists campanhas (
  id                 uuid primary key default gen_random_uuid(),
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  deletado_em        timestamptz,
  nome               text not null check (length(trim(nome)) between 2 and 60),
  descricao          text check (descricao is null or length(descricao) <= 200),
  condominio_id      uuid references condominios(id),
  zona_id            uuid references zonas(id),
  cozinha_id         uuid references cozinhas(id),
  tipo               text not null check (tipo in ('percentagem', 'preco')),
  valor              int not null check (valor > 0),
  cardapio_ids       uuid[],
  minimo_pedido      int not null default 0 check (minimo_pedido >= 0),
  inicio             timestamptz not null default now(),
  fim                timestamptz,
  dias_semana        int[] check (dias_semana is null or dias_semana <@ array[1,2,3,4,5,6,7]),
  hora_inicio        time,
  hora_fim           time,
  so_membros         boolean not null default false,
  limite_por_cliente int check (limite_por_cliente is null or limite_por_cliente > 0),
  limite_total       int check (limite_total is null or limite_total > 0),
  activa             boolean not null default true,
  avisado_em         timestamptz,
  check (tipo <> 'percentagem' or valor between 1 and 90),
  check (tipo <> 'preco' or cardinality(cardapio_ids) > 0),
  check (fim is null or fim > inicio),
  check ((hora_inicio is null) = (hora_fim is null)),
  check (not so_membros or condominio_id is not null)
);
comment on table campanhas is 'Promoções por condomínio/zona/cozinha: % nos pratos ou preço especial; não acumula com o convite (vale o maior)';
create index if not exists campanhas_condominio on campanhas (condominio_id);
create index if not exists campanhas_zona on campanhas (zona_id);
create index if not exists campanhas_cozinha on campanhas (cozinha_id);
alter table campanhas enable row level security;
revoke all on campanhas from anon, authenticated;
drop trigger if exists trg_auditar on campanhas;
create trigger trg_auditar after insert or update or delete on campanhas
  for each row execute function auditar_alteracao_tabela();

alter table pedidos add column if not exists campanha_id uuid references campanhas(id);
create index if not exists pedidos_campanha on pedidos (campanha_id) where campanha_id is not null;
comment on column pedidos.campanha_id is 'Campanha aplicada aos preços dos pratos (só o servidor escreve, pelo orçamento)';

-- Quem gere uma campanha: cozinhas.gerir; numa campanha de condomínio, também quem gere o condomínio
create or replace function pode_gerir_campanha(p_cond uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select tem_permissao('cozinhas.gerir') or (p_cond is not null and pode_gerir_condominio(p_cond));
$$;
revoke execute on function pode_gerir_campanha(uuid) from public, anon, authenticated;

-- Pedidos (não cancelados) que usaram a campanha, no total ou de um cliente
create or replace function campanha_usos(p_campanha uuid, p_cliente uuid default null)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from pedidos
   where campanha_id = p_campanha and deletado_em is null and estado not in ('cancelado', 'estornado')
     and (p_cliente is null or cliente_id = p_cliente);
$$;
revoke execute on function campanha_usos(uuid, uuid) from public, anon, authenticated;

-- A campanha vale agora para este pedido? (sem olhar para os pratos)
create or replace function campanha_vale(k campanhas, p_cozinha uuid, p_zona uuid, p_ponto uuid, p_cliente uuid,
                                         p_subtotal int, p_quando timestamptz default now())
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_ts timestamp := p_quando at time zone 'Africa/Luanda';
  c    condominios;
  pe   pontos_entrega;
begin
  if not k.activa or k.deletado_em is not null or p_quando < k.inicio or (k.fim is not null and p_quando >= k.fim) then
    return false;
  end if;
  if k.dias_semana is not null and not (extract(isodow from v_ts)::int = any (k.dias_semana)) then return false; end if;
  if k.hora_inicio is not null and not janela_hora(v_ts::time, k.hora_inicio, k.hora_fim) then return false; end if;
  if k.cozinha_id is not null and k.cozinha_id is distinct from p_cozinha then return false; end if;
  if k.zona_id is not null and k.zona_id is distinct from p_zona then return false; end if;
  if coalesce(p_subtotal, 0) < k.minimo_pedido then return false; end if;
  if k.condominio_id is not null then
    select * into c from condominios where id = k.condominio_id and deletado_em is null;
    if not found then return false; end if;
    select * into pe from pontos_entrega where id = p_ponto;
    if pe.lat is null or distancia_m(pe.lat, pe.lng, c.centro_lat, c.centro_lng) > c.raio_m + 50 then return false; end if;
    if k.so_membros and (p_cliente is null or not condominio_membro_activo(c.id, p_cliente)) then return false; end if;
  end if;
  if k.limite_total is not null and campanha_usos(k.id) >= k.limite_total then return false; end if;
  if k.limite_por_cliente is not null and p_cliente is not null
     and campanha_usos(k.id, p_cliente) >= k.limite_por_cliente then return false; end if;
  return true;
end $$;
revoke execute on function campanha_vale(campanhas, uuid, uuid, uuid, uuid, int, timestamptz) from public, anon, authenticated;

-- A melhor campanha para estes pratos: devolve {campanha_id, nome, itens, subtotal, poupanca} ou null
create or replace function aplicar_campanha(p_itens jsonb, p_cozinha uuid, p_zona uuid, p_ponto uuid, p_cliente uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_sub  int := (select coalesce(sum((i ->> 'qtd')::int * (i ->> 'preco_unitario')::int), 0) from jsonb_array_elements(p_itens) i);
  k      campanhas;
  v_itens jsonb;
  v_nova  int;
  v_poup  int;
  melhor  jsonb;
begin
  if not funcionalidade_activa('condominios') then return null; end if;
  for k in select * from campanhas where activa and deletado_em is null loop
    continue when not campanha_vale(k, p_cozinha, p_zona, p_ponto, p_cliente, v_sub);
    select jsonb_agg(case when novo < preco
                          then i || jsonb_build_object('preco_unitario', novo, 'preco_original', preco, 'campanha_id', k.id)
                          else i end order by n),
           coalesce(sum(qtd * novo), 0)
      into v_itens, v_nova
      from (select i, n, (i ->> 'qtd')::int as qtd, (i ->> 'preco_unitario')::int as preco,
                   case when k.cardapio_ids is not null and not ((i ->> 'cardapio_id')::uuid = any (k.cardapio_ids))
                          then (i ->> 'preco_unitario')::int
                        when k.tipo = 'percentagem'
                          then round((i ->> 'preco_unitario')::int * (100 - k.valor) / 100.0)::int
                        else least((i ->> 'preco_unitario')::int, k.valor) end as novo
              from jsonb_array_elements(p_itens) with ordinality as x(i, n)) t;
    v_poup := v_sub - v_nova;
    if v_poup > 0 and (melhor is null or v_poup > (melhor ->> 'poupanca')::int) then
      melhor := jsonb_build_object('campanha_id', k.id, 'nome', k.nome, 'itens', v_itens,
                                   'subtotal', v_nova, 'poupanca', v_poup);
    end if;
  end loop;
  return melhor;
end $$;
revoke execute on function aplicar_campanha(jsonb, uuid, uuid, uuid, uuid) from public, anon, authenticated;

-- orcamento_pedido: aplica a campanha (vale a maior: campanha ou convite) — acrescentado sem copiar
do $$
declare
  v_def  text := pg_get_functiondef('orcamento_pedido(jsonb,uuid,uuid,uuid)'::regprocedure);
  v_novo text;
begin
  if position('aplicar_campanha' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def, '(v_sem\s+text;)', E'\\1\n  v_camp     jsonb;');
  -- calcula a campanha antes do desconto de convite (pedidos de grupo ficam de fora)
  v_novo := regexp_replace(v_novo, '(\n\s*select\s+\*\s+into\s+v_desc\s+from\s+avaliar_desconto_indicacao)',
    E'\n  -- Campanha (promoção) para estes pratos, nesta zona/condomínio\n'
    || E'  if p_grupo is null then\n'
    || E'    v_camp := aplicar_campanha(v_itens, v_cozinha, v_zona.id, v_ponto.id, v_cliente);\n'
    || E'  end if;\\1');
  -- decide antes da entrega grátis: vale a maior (campanha ou convite)
  v_novo := regexp_replace(v_novo, '(\n\s*-- Entrega grátis a partir de um valor)',
    E'\n  -- Campanha ou convite: não acumulam, vale o maior; com a campanha o convite fica para outro pedido\n'
    || E'  if v_camp is not null then\n'
    || E'    if v_desconto > (v_camp ->> ''poupanca'')::int then\n'
    || E'      v_camp := null;\n'
    || E'    else\n'
    || E'      v_itens := v_camp -> ''itens'';\n'
    || E'      v_subtotal := (v_camp ->> ''subtotal'')::int;\n'
    || E'      if v_desconto > 0 then v_motivo := ''campanha''; end if;\n'
    || E'      v_desconto := 0;\n'
    || E'    end if;\n'
    || E'  end if;\\1');
  v_novo := regexp_replace(v_novo, '(''taxa_grupo_estimada''\s*,\s*v_estimada\s*,)',
    E'\\1\n    ''campanha_id'', v_camp ->> ''campanha_id'',\n'
    || E'    ''campanha'', case when v_camp is not null then jsonb_build_object(''nome'', v_camp ->> ''nome'', ''poupanca'', (v_camp ->> ''poupanca'')::int) end,');
  if position('v_camp     jsonb;' in v_novo) = 0 or position('aplicar_campanha(v_itens' in v_novo) = 0
     or position('vale o maior' in v_novo) = 0 or position('''campanha_id'', v_camp' in v_novo) = 0 then
    raise exception 'orcamento_pedido não tem o formato esperado';
  end if;
  execute v_novo;
end $$;

-- O pedido guarda a campanha (como o resto do orçamento)
do $$
declare
  v_def  text := pg_get_functiondef('pedidos_precos_cardapio()'::regprocedure);
  v_novo text;
begin
  if position('campanha_id' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def, '(new\.zona_id\s*:=\s*\(o\s*->>\s*''zona_id''\)::uuid;)',
    E'\\1\n    new.campanha_id := nullif(o ->> ''campanha_id'', '''')::uuid;');
  if v_novo = v_def then raise exception 'pedidos_precos_cardapio não tem o formato esperado'; end if;
  execute v_novo;
end $$;

-- Com campanha não há desconto de convite neste pedido (o convite não se gasta)
do $$
declare
  v_def  text := pg_get_functiondef('calcular_desconto_indicacao()'::regprocedure);
  v_novo text;
begin
  if position('campanha_id' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def, '(\n\s*return\s+new;\s*\nend)',
    E'\n  -- Campanha aplicada: não acumula com o convite (o orçamento já escolheu a campanha)\n'
    || E'  if new.campanha_id is not null then\n    new.desconto_indicacao := 0;\n  end if;\\1');
  if v_novo = v_def then raise exception 'calcular_desconto_indicacao não tem o formato esperado'; end if;
  execute v_novo;
end $$;

-- ---------------------------- gestão (operador) ----------------------------
create or replace function guardar_campanha(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid := nullif(p ->> 'id', '')::uuid;
  v_cond uuid := nullif(p ->> 'condominio_id', '')::uuid;
  v_ant  campanhas;
begin
  if v_id is not null then
    select * into v_ant from campanhas where id = v_id and deletado_em is null;
    if not found then raise exception 'campanha_inexistente' using errcode = 'P0001'; end if;
    if not pode_gerir_campanha(v_ant.condominio_id) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  end if;
  if not pode_gerir_campanha(v_cond) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  -- Quem só gere o condomínio não cria campanhas fora dele
  if v_cond is null and not tem_permissao('cozinhas.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if v_id is null then
    insert into campanhas (nome, descricao, condominio_id, zona_id, cozinha_id, tipo, valor, cardapio_ids, minimo_pedido,
                           inicio, fim, dias_semana, hora_inicio, hora_fim, so_membros, limite_por_cliente, limite_total, activa)
    values (trim(p ->> 'nome'), nullif(trim(p ->> 'descricao'), ''), v_cond, nullif(p ->> 'zona_id', '')::uuid,
            nullif(p ->> 'cozinha_id', '')::uuid, p ->> 'tipo', (p ->> 'valor')::int,
            (select array_agg(x::uuid) from jsonb_array_elements_text(nullif(p -> 'cardapio_ids', 'null')) x),
            coalesce((p ->> 'minimo_pedido')::int, 0), coalesce(nullif(p ->> 'inicio', '')::timestamptz, now()),
            nullif(p ->> 'fim', '')::timestamptz,
            (select array_agg(x::int) from jsonb_array_elements_text(nullif(p -> 'dias_semana', 'null')) x),
            nullif(p ->> 'hora_inicio', '')::time, nullif(p ->> 'hora_fim', '')::time,
            coalesce((p ->> 'so_membros')::boolean, false), nullif(p ->> 'limite_por_cliente', '')::int,
            nullif(p ->> 'limite_total', '')::int, coalesce((p ->> 'activa')::boolean, true))
    returning id into v_id;
  else
    update campanhas
       set nome = trim(p ->> 'nome'), descricao = nullif(trim(p ->> 'descricao'), ''), condominio_id = v_cond,
           zona_id = nullif(p ->> 'zona_id', '')::uuid, cozinha_id = nullif(p ->> 'cozinha_id', '')::uuid,
           tipo = p ->> 'tipo', valor = (p ->> 'valor')::int,
           cardapio_ids = (select array_agg(x::uuid) from jsonb_array_elements_text(nullif(p -> 'cardapio_ids', 'null')) x),
           minimo_pedido = coalesce((p ->> 'minimo_pedido')::int, 0),
           inicio = coalesce(nullif(p ->> 'inicio', '')::timestamptz, inicio), fim = nullif(p ->> 'fim', '')::timestamptz,
           dias_semana = (select array_agg(x::int) from jsonb_array_elements_text(nullif(p -> 'dias_semana', 'null')) x),
           hora_inicio = nullif(p ->> 'hora_inicio', '')::time, hora_fim = nullif(p ->> 'hora_fim', '')::time,
           so_membros = coalesce((p ->> 'so_membros')::boolean, false),
           limite_por_cliente = nullif(p ->> 'limite_por_cliente', '')::int, limite_total = nullif(p ->> 'limite_total', '')::int,
           activa = coalesce((p ->> 'activa')::boolean, activa), atualizado_em = now()
     where id = v_id;
  end if;
  return v_id;
end $$;
revoke execute on function guardar_campanha(jsonb) from public, anon;
grant  execute on function guardar_campanha(jsonb) to authenticated;

create or replace function apagar_campanha(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  k campanhas;
begin
  select * into k from campanhas where id = p_id and deletado_em is null;
  if not found then raise exception 'campanha_inexistente' using errcode = 'P0001'; end if;
  if not pode_gerir_campanha(k.condominio_id) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  update campanhas set deletado_em = now(), activa = false, atualizado_em = now() where id = p_id;
end $$;
revoke execute on function apagar_campanha(uuid) from public, anon;
grant  execute on function apagar_campanha(uuid) to authenticated;

-- Campanhas com os resultados (pedidos, clientes, vendas, desconto dado)
create or replace function campanhas_lista()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', k.id, 'nome', k.nome, 'descricao', k.descricao, 'condominio_id', k.condominio_id, 'condominio', c.nome,
    'zona_id', k.zona_id, 'zona', z.nome, 'cozinha_id', k.cozinha_id, 'cozinha', co.nome,
    'tipo', k.tipo, 'valor', k.valor, 'cardapio_ids', to_jsonb(k.cardapio_ids), 'minimo_pedido', k.minimo_pedido,
    'inicio', k.inicio, 'fim', k.fim, 'dias_semana', to_jsonb(k.dias_semana),
    'hora_inicio', to_char(k.hora_inicio, 'HH24:MI'), 'hora_fim', to_char(k.hora_fim, 'HH24:MI'),
    'so_membros', k.so_membros, 'limite_por_cliente', k.limite_por_cliente, 'limite_total', k.limite_total,
    'activa', k.activa, 'avisado_em', k.avisado_em,
    'em_curso', k.activa and now() >= k.inicio and (k.fim is null or now() < k.fim),
    'resultado', (select jsonb_build_object(
                    'pedidos', count(*),
                    'entregues', count(*) filter (where p.estado = 'entregue_pago'),
                    'clientes', count(distinct p.cliente_id),
                    'vendas', coalesce(sum(p.subtotal) filter (where p.estado = 'entregue_pago'), 0),
                    'desconto', coalesce((select sum((i ->> 'qtd')::int * ((i ->> 'preco_original')::int - (i ->> 'preco_unitario')::int))
                                            from pedidos p2, jsonb_array_elements(p2.itens) i
                                           where p2.campanha_id = k.id and p2.estado = 'entregue_pago' and p2.deletado_em is null
                                             and i ? 'preco_original'), 0))
                    from pedidos p
                   where p.campanha_id = k.id and p.deletado_em is null and p.estado not in ('cancelado', 'estornado'))
  ) order by k.activa desc, k.inicio desc), '[]')
  from campanhas k
  left join condominios c on c.id = k.condominio_id
  left join zonas z on z.id = k.zona_id
  left join cozinhas co on co.id = k.cozinha_id
  where k.deletado_em is null and pode_gerir_campanha(k.condominio_id);
$$;
revoke execute on function campanhas_lista() from public, anon;
grant  execute on function campanhas_lista() to authenticated;

-- Avisar os clientes da campanha (uma vez): membros do condomínio, ou quem pediu na zona nos últimos 90 dias
create or replace function campanha_avisar(p_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  k  campanhas;
  n  int;
  v_corpo text;
begin
  select * into k from campanhas where id = p_id and deletado_em is null for update;
  if not found then raise exception 'campanha_inexistente' using errcode = 'P0001'; end if;
  if not pode_gerir_campanha(k.condominio_id) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if k.avisado_em is not null then raise exception 'ja_avisado' using errcode = 'P0001'; end if;
  if k.condominio_id is null and k.zona_id is null then raise exception 'sem_publico' using errcode = 'P0001'; end if;
  v_corpo := coalesce(k.descricao,
    case k.tipo when 'percentagem' then k.valor || '% de desconto nos pratos'
                else 'Preço especial: ' || to_char(k.valor, 'FM999G999G999') || ' Kz' end)
    || case when k.fim is not null then ' — até ' || to_char(k.fim at time zone 'Africa/Luanda', 'DD/MM') else '' end || '.';
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select d.cliente_id, 'N31', jsonb_build_object('titulo', '🏷️ ' || k.nome, 'corpo', v_corpo, 'link', '/inicio')
    from (select m.cliente_id from condominio_membros m
           where k.condominio_id is not null and m.condominio_id = k.condominio_id and m.estado = 'activo'
          union
          select distinct p.cliente_id from pedidos p
           where k.condominio_id is null and k.zona_id is not null and p.zona_id = k.zona_id
             and p.deletado_em is null and p.criado_em > now() - interval '90 days') d
    join clientes cl on cl.id = d.cliente_id and cl.deletado_em is null;
  get diagnostics n = row_count;
  update campanhas set avisado_em = now() where id = p_id;
  perform registar_auditoria('campanha_avisada', 'campanhas', p_id, jsonb_build_object('clientes', n));
  return n;
end $$;
revoke execute on function campanha_avisar(uuid) from public, anon;
grant  execute on function campanha_avisar(uuid) to authenticated;

-- ------------------------------ app do cliente ------------------------------
-- Promoções que valem agora para a morada do cliente (cartaz no início)
create or replace function campanhas_para_mim(p_ponto uuid)
returns table (nome text, descricao text, tipo text, valor int, cozinha_id uuid, cozinha text, minimo_pedido int, fim timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_cli  uuid := cliente_actual();
  v_zona uuid;
begin
  if v_cli is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not funcionalidade_activa('condominios') then return; end if;
  select pe.zona_id into v_zona
    from pontos_entrega pe
    join enderecos_cliente ec on ec.ponto_entrega_id = pe.id and ec.cliente_id = v_cli and ec.deletado_em is null
   where pe.id = p_ponto;
  if not found then return; end if;
  return query
  select k.nome, k.descricao, k.tipo, k.valor, k.cozinha_id, co.nome, k.minimo_pedido, k.fim
    from campanhas k left join cozinhas co on co.id = k.cozinha_id
   where k.activa and k.deletado_em is null
     and (k.zona_id is null or k.zona_id = v_zona
          or k.zona_id = (select c.zona_id from condominios c where c.id = k.condominio_id))
     and campanha_vale(k, coalesce(k.cozinha_id, (select c.cozinha_id from condominios c where c.id = k.condominio_id)),
                       coalesce(k.zona_id, v_zona), p_ponto, v_cli, greatest(k.minimo_pedido, 0))
   order by k.fim nulls last
   limit 3;
end $$;
revoke execute on function campanhas_para_mim(uuid) from public, anon;
grant  execute on function campanhas_para_mim(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Relatório do condomínio
-- -----------------------------------------------------------------------------
create or replace function relatorio_condominio(p_cond uuid, p_inicio date, p_fim date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c     condominios;
  v_ini timestamptz := p_inicio::timestamp at time zone 'Africa/Luanda';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'Africa/Luanda';
  r     jsonb;
begin
  if not pode_gerir_condominio(p_cond) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 366 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  select * into c from condominios where id = p_cond;
  with p as (
    select x.* from pedidos x
     where x.cozinha_id = c.cozinha_id and x.deletado_em is null
       and x.criado_em >= v_ini and x.criado_em < v_fim
  ), e as (select * from p where estado = 'entregue_pago')
  select jsonb_build_object(
    'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
    'membros', jsonb_build_object(
       'activos', (select count(*) from condominio_membros where condominio_id = p_cond and estado = 'activo'),
       'pendentes', (select count(*) from condominio_membros where condominio_id = p_cond and estado = 'pendente'),
       'espera', (select count(*) from condominio_membros where condominio_id = p_cond and estado = 'espera'),
       'novos', (select count(*) from condominio_membros where condominio_id = p_cond and estado = 'activo'
                   and coalesce(aprovado_em, criado_em) >= v_ini and coalesce(aprovado_em, criado_em) < v_fim),
       'sairam', (select count(*) from condominio_membros where condominio_id = p_cond and estado = 'removido'
                    and removido_em >= v_ini and removido_em < v_fim),
       'vagas', c.vagas),
    'pedidos', (select count(*) from p),
    'entregues', (select count(*) from e),
    'cancelados', (select count(*) from p where estado in ('cancelado', 'estornado')),
    'vendas', (select coalesce(sum(subtotal), 0) from e),
    'ticket_medio', (select round(avg(subtotal)) from e),
    'clientes', (select count(distinct cliente_id) from e),
    'membros_que_pediram', (select count(distinct e.cliente_id) from e
                              join condominio_membros m on m.cliente_id = e.cliente_id and m.condominio_id = p_cond and m.estado = 'activo'),
    'com_campanha', (select count(*) from e where campanha_id is not null),
    'pratos', coalesce((select jsonb_agg(t order by (t ->> 'qtd')::int desc) from (
                select jsonb_build_object('nome', regexp_replace(i ->> 'nome', ' \([^()]*\)$', ''),
                                          'qtd', sum(coalesce((i ->> 'qtd')::int, 1))) as t
                  from e, jsonb_array_elements(e.itens) i
                 group by regexp_replace(i ->> 'nome', ' \([^()]*\)$', '')
                 order by sum(coalesce((i ->> 'qtd')::int, 1)) desc limit 5) s), '[]'),
    'horas', coalesce((select jsonb_agg(jsonb_build_object('hora', h, 'pedidos', n) order by n desc, h) from (
                select to_char(criado_em at time zone 'Africa/Luanda', 'HH24') as h, count(*) as n
                  from e group by 1 order by 2 desc limit 4) s), '[]')
  ) into r;
  return r;
end $$;
revoke execute on function relatorio_condominio(uuid, date, date) from public, anon;
grant  execute on function relatorio_condominio(uuid, date, date) to authenticated;

-- A cozinha acrescenta pelo telefone: quem estava em espera passa à frente se houver vaga
create or replace function condominio_adicionar_membro(p_cond uuid, p_telefone text, p_bloco text default null, p_casa text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  c      condominios;
  v_cli  uuid;
  m      condominio_membros;
  v_id   uuid;
begin
  if not pode_gerir_condominio(p_cond) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  select * into c from condominios where id = p_cond and deletado_em is null for update;
  if not found then raise exception 'condominio_inexistente' using errcode = 'P0001'; end if;
  select id into v_cli from clientes
   where normalizar_telefone(telefone) = normalizar_telefone(p_telefone) and deletado_em is null
   order by criado_em limit 1;
  if v_cli is null then
    raise exception 'cliente_nao_encontrado' using errcode = 'P0001',
      detail = 'O morador tem de criar conta na app com este número';
  end if;
  select * into m from condominio_membros
   where condominio_id = p_cond and cliente_id = v_cli and estado in ('pendente', 'activo', 'espera');
  if m.id is not null then
    if m.estado = 'espera' and condominio_ocupadas(p_cond) >= c.vagas then
      raise exception 'lista_cheia' using errcode = 'P0001';
    end if;
    update condominio_membros
       set estado = 'activo', aprovado_em = coalesce(aprovado_em, now()), atualizado_em = now(),
           bloco = coalesce(nullif(trim(p_bloco), ''), bloco), casa = coalesce(nullif(trim(p_casa), ''), casa)
     where id = m.id;
    return m.id;
  end if;
  if condominio_ocupadas(p_cond) >= c.vagas then
    raise exception 'lista_cheia' using errcode = 'P0001';
  end if;
  insert into condominio_membros (condominio_id, cliente_id, estado, bloco, casa, origem, aprovado_em)
  values (p_cond, v_cli, 'activo', nullif(trim(p_bloco), ''), nullif(trim(p_casa), ''), 'cozinha', now())
  returning id into v_id;
  perform registar_auditoria('condominio_membro_adicionado', 'condominio_membros', v_id, jsonb_build_object('condominio_id', p_cond));
  return v_id;
end $$;
