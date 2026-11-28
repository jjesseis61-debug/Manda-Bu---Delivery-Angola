-- Agente investigador financeiro (Claude com ferramentas). Para cada funcionário com sinais num período
-- (comprovativos rejeitados ou que não conferem com a foto, pagamentos sem entrada no extrato, caixas com
-- diferença) abre-se um caso. A Edge Function investigar dá ao Claude ferramentas SÓ DE LEITURA (histórico
-- dos pedidos, comprovativos, caixas, entradas do extrato parecidas, referências repetidas, comparação com
-- a equipa); o Claude investiga em vários passos e entrega um dossiê com o risco, os factos e as perguntas a
-- fazer. Não acusa, não bloqueia nem mexe em dinheiro: quem decide é quem tem financas.conferir (nunca o
-- próprio funcionário). Cada passo fica guardado no caso e na auditoria como "Agente Claude".
-- Interruptor: funcionalidade agente_investigador (desligada até ser testada).

insert into funcionalidades (chave, activa, dispositivo_id) values ('agente_investigador', false, 'servidor')
on conflict (chave) do nothing;

alter table parametros
  add column investigacao_pontuacao_min integer not null default 3 check (investigacao_pontuacao_min between 1 and 100);
comment on column parametros.investigacao_pontuacao_min is
  'Pontos de sinais (rejeitado 3, sem extrato 3, não confere 2, caixa com diferença 2, ilegível 1) para abrir um caso';

create table casos_investigacao (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  funcionario_id   uuid not null references funcionarios(id),
  inicio           date not null,
  fim              date not null check (fim >= inicio),
  sinais           jsonb not null,
  pontuacao        integer not null default 0,
  aberto_por       uuid references funcionarios(id),            -- null: aberto pelo job mensal
  estado           text not null default 'por_investigar'
                     check (estado in ('por_investigar', 'a_investigar', 'investigado', 'indisponivel')),
  ia_tentativas    integer not null default 0,
  ia_nota          text,
  risco            text check (risco in ('baixo', 'medio', 'alto')),
  resumo           text,
  conclusao        jsonb,                                       -- factos, explicações, recomendação, perguntas
  passos           jsonb not null default '[]',                 -- o que o agente consultou
  investigado_em   timestamptz,
  decisao          text check (decisao in ('sem_problema', 'erro_operacional', 'suspeita_confirmada')),
  decisao_nota     text check (char_length(decisao_nota) <= 500),
  decidido_por     uuid references funcionarios(id),
  decidido_em      timestamptz,
  unique (funcionario_id, inicio, fim)
);
create index casos_investigacao_pendente_idx on casos_investigacao (criado_em) where estado = 'por_investigar';
create index casos_investigacao_aberto_por_idx on casos_investigacao (aberto_por);
create index casos_investigacao_decidido_por_idx on casos_investigacao (decidido_por);
create trigger trg_0_so_servidor before insert or update or delete on casos_investigacao
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on casos_investigacao
for each row execute function sync_receber();
alter table casos_investigacao enable row level security;
revoke all on casos_investigacao from anon;
revoke insert, update, delete, truncate on casos_investigacao from authenticated;
grant select on casos_investigacao to authenticated;
-- Quem confere as finanças vê os casos, menos o seu (o administrador principal vê todos)
create policy ler on casos_investigacao for select to authenticated
  using (deletado_em is null and tem_permissao('financas.conferir')
         and (funcionario_id is distinct from funcionario_actual() or e_administrador()));
comment on table casos_investigacao is 'Sincronização: só servidor (casos do agente investigador financeiro). Telemóvel só lê.';

-- Sinais de um funcionário num período (Luanda)
create or replace function sinais_financeiros(p_func uuid, p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with comp as (
    select c.*,
           exists (select 1 from extratos e where e.deletado_em is null and e.estado in ('lido', 'manual')
                     and (c.criado_em at time zone 'Africa/Luanda')::date between e.periodo_inicio and e.periodo_fim) as coberto,
           exists (select 1 from extrato_movimentos m where m.comprovativo_id = c.id and m.deletado_em is null) as no_extrato
      from comprovativos_pagamento c
     where c.registado_por = p_func and c.deletado_em is null
       and (c.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  cx as (
    select c.*, (c.fechamento ->> 'diferenca')::numeric as diferenca from caixa c
     where c.deletado_em is null and c.fechamento is not null and (c.fechamento ->> 'funcionario_id')::uuid = p_func
       and c.data between p_inicio and p_fim),
  s as (
    select (select count(*) from comp) comprovativos,
           (select coalesce(sum(valor), 0) from comp) valor_comprovativos,
           (select count(*) from comp where estado = 'rejeitado') rejeitados,
           (select count(*) from comp where ia_estado = 'diverge') nao_conferem,
           (select count(*) from comp where ia_estado = 'ilegivel') ilegiveis,
           (select count(*) from comp where coberto and not no_extrato and estado <> 'rejeitado') sem_extrato,
           (select coalesce(sum(valor), 0) from comp where coberto and not no_extrato and estado <> 'rejeitado') valor_sem_extrato,
           (select count(*) from cx) caixas_fechadas,
           (select count(*) from cx where diferenca <> 0) caixas_com_diferenca,
           (select coalesce(sum(diferenca), 0) from cx) soma_diferencas)
  select jsonb_build_object(
    'comprovativos', comprovativos, 'valor_comprovativos', valor_comprovativos, 'rejeitados', rejeitados,
    'nao_conferem', nao_conferem, 'ilegiveis', ilegiveis, 'sem_extrato', sem_extrato,
    'valor_sem_extrato', valor_sem_extrato, 'caixas_fechadas', caixas_fechadas,
    'caixas_com_diferenca', caixas_com_diferenca, 'soma_diferencas', soma_diferencas,
    'pontuacao', rejeitados * 3 + sem_extrato * 3 + nao_conferem * 2 + caixas_com_diferenca * 2 + ilegiveis)
  from s;
$$;
revoke execute on function sinais_financeiros(uuid, date, date) from public, anon, authenticated;

-- Abre os casos do período (um por funcionário com pontos suficientes; não repete o mesmo período)
create or replace function abrir_investigacoes_periodo(p_inicio date, p_fim date, p_por uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_min int := (select investigacao_pontuacao_min from parametros where unico);
  n int;
begin
  with s as (
    select f.id, sinais_financeiros(f.id, p_inicio, p_fim) as sinais from funcionarios f where f.deletado_em is null
  ), novos as (
    insert into casos_investigacao (dispositivo_id, sincronizado_em, funcionario_id, inicio, fim, sinais, pontuacao, aberto_por)
    select 'servidor', now(), s.id, p_inicio, p_fim, s.sinais, (s.sinais ->> 'pontuacao')::int, p_por
      from s where (s.sinais ->> 'pontuacao')::int >= v_min
    on conflict (funcionario_id, inicio, fim) do nothing
    returning 1)
  select count(*) into n from novos;
  return n;
end $$;
revoke execute on function abrir_investigacoes_periodo(date, date, uuid) from public, anon, authenticated;

create or replace function abrir_investigacoes(p_inicio date, p_fim date) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_financas();
  n int;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 92 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  if not funcionalidade_activa('agente_investigador') then
    raise exception 'funcionalidade_inactiva' using errcode = 'P0001';
  end if;
  n := abrir_investigacoes_periodo(p_inicio, p_fim, v_func);
  perform registar_auditoria('investigacoes_abertas', 'casos_investigacao', null,
    jsonb_build_object('inicio', p_inicio, 'fim', p_fim, 'casos', n));
  return n;
end $$;
revoke execute on function abrir_investigacoes(date, date) from public, anon;
grant execute on function abrir_investigacoes(date, date) to authenticated;

-- Dia 3 de cada mês (com os extratos do mês já carregados): casos do mês anterior
create or replace function job_investigacoes() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_ini date := (date_trunc('month', now() at time zone 'Africa/Luanda') - interval '1 month')::date;
begin
  if not funcionalidade_activa('agente_investigador') then return 0; end if;
  return abrir_investigacoes_periodo(v_ini, (v_ini + interval '1 month - 1 day')::date, null);
end $$;
revoke execute on function job_investigacoes() from public, anon, authenticated;

-- Casos para a app (Conferência > Investigações)
create or replace function casos_investigacao_lista() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_func uuid := exigir_financas();
  v_admin boolean := e_administrador();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id, 'funcionario', f.nome, 'cargo', f.cargo, 'inicio', c.inicio, 'fim', c.fim,
             'sinais', c.sinais, 'pontuacao', c.pontuacao, 'estado', c.estado, 'ia_nota', c.ia_nota,
             'risco', c.risco, 'resumo', c.resumo, 'conclusao', c.conclusao, 'passos', c.passos,
             'investigado_em', c.investigado_em, 'decisao', c.decisao, 'decisao_nota', c.decisao_nota,
             'decidido_por', d.nome, 'decidido_em', c.decidido_em, 'criado_em', c.criado_em)
           order by (c.decisao is null) desc, case c.risco when 'alto' then 0 when 'medio' then 1 when 'baixo' then 2 else 3 end,
                    c.pontuacao desc, c.criado_em desc)
      from casos_investigacao c
      join funcionarios f on f.id = c.funcionario_id
      left join funcionarios d on d.id = c.decidido_por
     where c.deletado_em is null and (c.funcionario_id <> v_func or v_admin)
       and c.criado_em > now() - interval '180 days'), '[]');
end $$;
revoke execute on function casos_investigacao_lista() from public, anon;
grant execute on function casos_investigacao_lista() to authenticated;

-- Decisão humana sobre o caso (nunca do próprio funcionário)
create or replace function decidir_caso(p_id uuid, p_decisao text, p_nota text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_financas();
  c casos_investigacao;
begin
  select * into c from casos_investigacao where id = p_id and deletado_em is null for update;
  if not found then raise exception 'caso_inexistente' using errcode = 'P0001'; end if;
  if c.funcionario_id = v_func and not e_administrador() then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if c.decisao is not null then raise exception 'caso_decidido' using errcode = 'P0001'; end if;
  if p_decisao is null or p_decisao not in ('sem_problema', 'erro_operacional', 'suspeita_confirmada') then
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
  if char_length(trim(coalesce(p_nota, ''))) < 5 then raise exception 'nota_obrigatoria' using errcode = 'P0001'; end if;
  if char_length(p_nota) > 500 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  update casos_investigacao
     set decisao = p_decisao, decisao_nota = trim(p_nota), decidido_por = v_func, decidido_em = now(), atualizado_em = now()
   where id = c.id;
  perform registar_auditoria('caso_decidido', 'casos_investigacao', c.id,
    jsonb_build_object('decisao', p_decisao, 'risco_agente', c.risco, 'funcionario_id', c.funcionario_id));
end $$;
revoke execute on function decidir_caso(uuid, text, text) from public, anon;
grant execute on function decidir_caso(uuid, text, text) to authenticated;

-- Investigar de novo (com os dados de hoje: por exemplo, depois de carregar um extrato em falta)
create or replace function investigar_de_novo(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_financas();
  c casos_investigacao;
begin
  select * into c from casos_investigacao where id = p_id and deletado_em is null for update;
  if not found then raise exception 'caso_inexistente' using errcode = 'P0001'; end if;
  if c.funcionario_id = v_func and not e_administrador() then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if c.decisao is not null then raise exception 'caso_decidido' using errcode = 'P0001'; end if;
  update casos_investigacao
     set estado = 'por_investigar', ia_tentativas = 0, ia_nota = null,
         sinais = sinais_financeiros(c.funcionario_id, c.inicio, c.fim),
         pontuacao = (sinais_financeiros(c.funcionario_id, c.inicio, c.fim) ->> 'pontuacao')::int,
         atualizado_em = now()
   where id = c.id;
end $$;
revoke execute on function investigar_de_novo(uuid) from public, anon;
grant execute on function investigar_de_novo(uuid) to authenticated;

-- ---------------------------------------------------------------- histórico do pedido (partilhado com o agente)
-- Dados do histórico de um pedido, sem verificar permissões (só para outras funções do servidor)
create or replace function historico_pedido_dados(p_pedido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  x pedidos;
  r jsonb;
begin
  select * into x from pedidos where id = p_pedido;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  select jsonb_build_object(
    'pedido_id', x.id, 'estado', x.estado, 'cliente', (select nome from clientes where id = x.cliente_id),
    'cozinha', (select trim(nome) from cozinhas where id = x.cozinha_id),
    'entregador', (select nome from funcionarios where id = x.entregador_id),
    'caixa', (select posto from caixa where id = x.caixa_id),
    'valor', x.subtotal + x.taxa_entrega - x.desconto_indicacao, 'parcelas', x.parcelas,
    'eventos', coalesce((select jsonb_agg(ev order by (ev ->> 'em')::timestamptz) from (
        select jsonb_build_object('em', x.criado_em, 'acao', 'pedido_criado', 'quem',
                                  coalesce((select nome from clientes where id = x.cliente_id), 'cliente'), 'detalhe', null) ev
        union all
        select jsonb_build_object('em', a.data, 'acao', a.acao, 'quem', a.funcionario_nome,
                                  'detalhe', case when a.detalhe ~ '^\s*\{' then a.detalhe::jsonb end)
          from auditoria a
         where a.ref_id = x.id
            or a.ref_id in (select k.id from comprovativos_pagamento k where k.pedido_id = x.id)
        union all
        select jsonb_build_object('em', k.criado_em, 'acao', 'comprovativo_registado',
                                  'quem', (select nome from funcionarios where id = k.registado_por),
                                  'detalhe', jsonb_build_object('metodo', k.metodo, 'valor', k.valor, 'referencia', k.referencia,
                                                                'ia_estado', k.ia_estado, 'ia_valor', k.ia_valor, 'ia_referencia', k.ia_referencia))
          from comprovativos_pagamento k where k.pedido_id = x.id and k.deletado_em is null
        union all
        select jsonb_build_object('em', m.atualizado_em, 'acao', 'extrato_' || coalesce(m.ligacao, 'ligado'),
                                  'quem', coalesce((select nome from funcionarios where id = m.ligado_por), 'conferência automática'),
                                  'detalhe', jsonb_build_object('conta', e.conta, 'data', m.data, 'valor', m.valor, 'referencia', m.referencia))
          from extrato_movimentos m join extratos e on e.id = m.extrato_id
          join comprovativos_pagamento k on k.id = m.comprovativo_id
         where k.pedido_id = x.id and m.deletado_em is null
        union all
        select jsonb_build_object('em', (c.fechamento ->> 'fechado_em')::timestamptz, 'acao', 'caixa_fechada',
                                  'quem', c.fechamento ->> 'funcionario_nome',
                                  'detalhe', jsonb_build_object('posto', c.posto, 'diferenca', c.fechamento -> 'diferenca'))
          from caixa c where c.id = x.caixa_id and c.fechamento is not null) s), '[]'))
  into r;
  return r;
end $$;
revoke execute on function historico_pedido_dados(uuid) from public, anon, authenticated;

-- Histórico do pedido na app: as mesmas permissões de antes
create or replace function historico_pedido(p_pedido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  x pedidos;
begin
  select * into x from pedidos where id = p_pedido;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  if not (tem_permissao('pedidos.gerir') or tem_permissao('financas.conferir')
          or pode_na_cozinha('vendas.registar', x.cozinha_id)
          or (tem_permissao('entregas.registar') and x.entregador_id is not null and x.entregador_id = funcionario_actual())) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return historico_pedido_dados(p_pedido);
end $$;

-- ---------------------------------------------------------------- ferramentas do agente (só leitura, só o serviço)
-- Reserva um caso (um por execução, por causa do limite de tempo da Edge Function)
create or replace function reservar_caso() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c casos_investigacao;
begin
  if not funcionalidade_activa('agente_investigador') then return null; end if;
  select * into c from casos_investigacao
   where deletado_em is null and decisao is null
     and (estado = 'por_investigar' or (estado = 'a_investigar' and atualizado_em < now() - interval '5 minutes'))
   order by pontuacao desc, criado_em
   limit 1 for update skip locked;
  if not found then return null; end if;
  update casos_investigacao set estado = 'a_investigar', atualizado_em = now() where id = c.id;
  return agente_caso(c.id);
end $$;

-- O caso: quem, período, sinais, a média da equipa no mesmo período
create or replace function agente_caso(p_caso uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'caso_id', c.id, 'funcionario_id', c.funcionario_id, 'funcionario', f.nome, 'cargo', f.cargo,
    'inicio', c.inicio, 'fim', c.fim, 'sinais', sinais_financeiros(c.funcionario_id, c.inicio, c.fim),
    'casos_anteriores', (select coalesce(jsonb_agg(jsonb_build_object('inicio', a.inicio, 'fim', a.fim, 'risco', a.risco,
                                                                        'decisao', a.decisao)), '[]')
                           from casos_investigacao a where a.funcionario_id = c.funcionario_id and a.id <> c.id
                            and a.deletado_em is null))
  from casos_investigacao c join funcionarios f on f.id = c.funcionario_id
  where c.id = p_caso;
$$;

-- Comprovativos que o funcionário registou no período (sem nomes de clientes)
create or replace function agente_comprovativos(p_func uuid, p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'comprovativo_id', c.id, 'pedido_id', c.pedido_id,
           'quando', to_char(c.criado_em at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'),
           'metodo', c.metodo, 'valor', c.valor, 'referencia', c.referencia, 'estado', c.estado, 'nota_conferencia', c.nota,
           'conferido_por', (select nome from funcionarios where id = c.conferido_por),
           'leitura_foto', c.ia_estado, 'foto_valor', c.ia_valor, 'foto_referencia', c.ia_referencia, 'foto_data', c.ia_data,
           'periodo_com_extrato', exists (select 1 from extratos e where e.deletado_em is null and e.estado in ('lido', 'manual')
                                            and (c.criado_em at time zone 'Africa/Luanda')::date between e.periodo_inicio and e.periodo_fim),
           'encontrado_no_extrato', exists (select 1 from extrato_movimentos m where m.comprovativo_id = c.id and m.deletado_em is null))
         order by c.criado_em), '[]')
    from (select * from comprovativos_pagamento
           where registado_por = p_func and deletado_em is null
             and (criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim
           order by criado_em limit 80) c;
$$;

-- Caixas que o funcionário fechou no período
create or replace function agente_caixas(p_func uuid, p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'caixa_id', c.id, 'data', c.data, 'posto', c.posto, 'cozinha', (select trim(nome) from cozinhas where id = c.cozinha_id),
           'aberta_por', c.funcionario_nome, 'esperado', c.fechamento -> 'esperado', 'contado', c.fechamento -> 'contado',
           'diferenca', c.fechamento -> 'diferenca', 'observacao', c.fechamento -> 'observacao',
           'sangrias', jsonb_array_length(c.sangrias),
           'pedidos', (select count(*) from pedidos x where x.caixa_id = c.id and x.estado = 'entregue_pago'))
         order by c.data), '[]')
    from caixa c
   where c.deletado_em is null and c.fechamento is not null and (c.fechamento ->> 'funcionario_id')::uuid = p_func
     and c.data between p_inicio and p_fim;
$$;

-- Histórico de um pedido (sem o nome do cliente)
create or replace function agente_historico_pedido(p_pedido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r jsonb := historico_pedido_dados(p_pedido);
begin
  return (r - 'cliente') || jsonb_build_object('eventos',
    (select coalesce(jsonb_agg(case when e ->> 'acao' = 'pedido_criado' then e || '{"quem": "cliente"}'::jsonb else e end), '[]')
       from jsonb_array_elements(r -> 'eventos') e));
end $$;

-- Entradas do extrato sem comprovativo parecidas com um pagamento (mesmo valor, até N dias de distância)
create or replace function agente_entradas_parecidas(p_valor numeric, p_dia date, p_dias int default 3) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'movimento_id', m.id, 'conta', e.conta, 'data', m.data, 'valor', m.valor, 'referencia', m.referencia,
           'descricao', m.descricao, 'origem', m.origem) order by abs(m.data - p_dia)), '[]')
    from extrato_movimentos m join extratos e on e.id = m.extrato_id
   where m.deletado_em is null and e.deletado_em is null and m.comprovativo_id is null
     and m.valor = p_valor and m.data between p_dia - least(greatest(coalesce(p_dias, 3), 0), 10)
                                           and p_dia + least(greatest(coalesce(p_dias, 3), 0), 10);
$$;

-- A mesma referência (ou parecida) noutros comprovativos ou entradas do extrato
create or replace function agente_referencia(p_referencia text) returns jsonb
language sql stable security definer set search_path = public as $$
  with k as (select chave_referencia(p_referencia) as chave)
  select jsonb_build_object(
    'comprovativos', (select coalesce(jsonb_agg(jsonb_build_object(
                        'comprovativo_id', c.id, 'pedido_id', c.pedido_id, 'metodo', c.metodo, 'valor', c.valor,
                        'referencia', c.referencia, 'registado_por', (select nome from funcionarios where id = c.registado_por),
                        'quando', to_char(c.criado_em at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'), 'estado', c.estado)), '[]')
                        from comprovativos_pagamento c, k
                       where c.deletado_em is null and length(k.chave) >= 4
                         and (c.referencia_chave = k.chave or position(k.chave in c.referencia_chave) > 0
                              or position(c.referencia_chave in k.chave) > 0)),
    'entradas_extrato', (select coalesce(jsonb_agg(jsonb_build_object(
                           'movimento_id', m.id, 'data', m.data, 'valor', m.valor, 'referencia', m.referencia,
                           'ligado_a_comprovativo', m.comprovativo_id is not null)), '[]')
                           from extrato_movimentos m, k
                          where m.deletado_em is null and length(k.chave) >= 4 and m.referencia_chave is not null
                            and (m.referencia_chave = k.chave or position(k.chave in m.referencia_chave) > 0
                                 or position(m.referencia_chave in k.chave) > 0)))
  from k;
$$;

-- A equipa no mesmo período (para comparar: é um padrão desta pessoa ou de todos?)
create or replace function agente_equipa(p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('funcionario', s.nome, 'sinais', s.sinais)
                            order by (s.sinais ->> 'pontuacao')::int desc), '[]')
    from (select f.nome, sinais_financeiros(f.id, p_inicio, p_fim) as sinais from funcionarios f where f.deletado_em is null) s
   where (s.sinais ->> 'comprovativos')::int > 0 or (s.sinais ->> 'caixas_fechadas')::int > 0;
$$;

-- Resultado da investigação (risco alto -> N24 a quem confere as finanças, nunca ao próprio)
create or replace function registar_investigacao(p_caso uuid, p_resultado text, p_conclusao jsonb default null,
                                                 p_passos jsonb default '[]', p_nota text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  c casos_investigacao;
  v_estado text;
  v_risco text;
  v_nome text;
begin
  select * into c from casos_investigacao where id = p_caso for update;
  if not found then raise exception 'caso_inexistente' using errcode = 'P0001'; end if;
  if p_resultado = 'erro' then
    update casos_investigacao
       set ia_tentativas = ia_tentativas + 1,
           estado = case when ia_tentativas + 1 >= 3 then 'indisponivel' else 'por_investigar' end,
           ia_nota = left(p_nota, 300), atualizado_em = now()
     where id = c.id returning estado into v_estado;
    return v_estado;
  end if;
  if p_resultado = 'indisponivel' then
    update casos_investigacao set estado = 'indisponivel', ia_nota = left(p_nota, 300), atualizado_em = now() where id = c.id;
    return 'indisponivel';
  end if;
  if p_resultado <> 'investigado' or p_conclusao is null then raise exception 'resultado_invalido' using errcode = 'P0001'; end if;
  v_risco := case when p_conclusao ->> 'risco' in ('baixo', 'medio', 'alto') then p_conclusao ->> 'risco' else 'medio' end;
  update casos_investigacao
     set estado = 'investigado', risco = v_risco, resumo = left(p_conclusao ->> 'resumo', 600),
         conclusao = p_conclusao - 'risco' - 'resumo', passos = coalesce(p_passos, '[]'),
         ia_nota = left(p_nota, 300), investigado_em = now(), atualizado_em = now()
   where id = c.id;
  insert into auditoria (dispositivo_id, funcionario_id, funcionario_nome, acao, detalhe, ref_id, ref_tipo, sincronizado_em)
  values ('servidor', null, 'Agente Claude', 'caso_investigado',
          jsonb_build_object('risco', v_risco, 'funcionario_id', c.funcionario_id, 'passos', jsonb_array_length(coalesce(p_passos, '[]')))::text,
          c.id, 'casos_investigacao', now());
  if v_risco = 'alto' then
    select nome into v_nome from funcionarios where id = c.funcionario_id;
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select f, 'N24', jsonb_build_object('caso_id', c.id, 'funcionario_nome', v_nome, 'inicio', c.inicio, 'fim', c.fim,
                                        'resumo', left(p_conclusao ->> 'resumo', 140))
      from funcionarios_com_permissao('financas.conferir') f
     where f <> c.funcionario_id;
  end if;
  return 'investigado';
end $$;

-- Agenda o agente de 5 em 5 minutos (mesmo segredo do envio de avisos)
create or replace function agendar_investigacoes(p_url text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format($f$select cron.schedule('investigar', '*/5 * * * *', %L)$f$,
    format('select net.http_post(url := %L, body := ''{}''::jsonb, timeout_milliseconds := 150000, headers := jsonb_build_object('
           '''Content-Type'', ''application/json'', ''x-envio-segredo'', '
           '(select valor from public.segredos_servidor where chave = ''envio_notificacoes'')))', p_url));
  return 'agendado';
end $$;

do $$
declare f text;
begin
  foreach f in array array['reservar_caso()', 'agente_caso(uuid)', 'agente_comprovativos(uuid, date, date)',
                           'agente_caixas(uuid, date, date)', 'agente_historico_pedido(uuid)',
                           'agente_entradas_parecidas(numeric, date, int)', 'agente_referencia(text)',
                           'agente_equipa(date, date)', 'registar_investigacao(uuid, text, jsonb, jsonb, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
revoke execute on function agendar_investigacoes(text) from public, anon, authenticated;

