-- Conferência financeira com leitura automática (Claude) e sempre com conferência humana.
--  1. Comprovativos: a leitura automática lê a foto (valor, referência, data) e compara com o que o
--     estafeta escreveu (ia_estado: confere / diverge / ilegivel / indisponivel). É só um aviso: quem
--     confere continua a ser o gerente (conferir_comprovativo), com ou sem leitura automática.
--  2. Extratos (banco, Multicaixa, Unitel Money): carregados em PDF ou foto; a leitura automática tira
--     as entradas, ou alguém com financas.conferir escreve-as à mão. O servidor cruza cada entrada com
--     os comprovativos (referência; senão valor e data ±2 dias) e mostra o que sobra dos dois lados.
--  3. Fecho diário (por caixa) e fecho mensal (por dia, conciliação e por funcionário).
--  4. Histórico do pedido: quem fez cada passo, do pedido ao fecho da caixa.
-- A chamada ao Claude é feita pela Edge Function ler-documentos (pg_cron de minuto a minuto); sem a
-- chave ANTHROPIC_API_KEY os documentos ficam "indisponivel" e a conferência faz-se à mão.

insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'financas.conferir', 'Finanças',
   'Carregar extratos, conferir com os comprovativos e ver os fechos diário e mensal')
on conflict (chave) do nothing;

-- ---------------------------------------------------------------- 1. leitura dos comprovativos
alter table comprovativos_pagamento
  add column ia_estado     text not null default 'pendente'
    check (ia_estado in ('pendente', 'a_ler', 'confere', 'diverge', 'ilegivel', 'indisponivel')),
  add column ia_valor      numeric,
  add column ia_referencia text,
  add column ia_data       date,
  add column ia_nota       text,
  add column ia_lido_em    timestamptz,
  add column ia_tentativas int not null default 0;
create index comprovativos_ia_pendente_idx on comprovativos_pagamento (criado_em) where ia_estado = 'pendente';

-- O resumo da caixa mostra o resultado da leitura automática de cada comprovativo
create or replace function resumo_caixa(p_caixa uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c        caixa := caixa_para_gerir(p_caixa, false);
  v_vendas numeric;
  v_pedidos int;
  v_pac    numeric;
  v_npac   int;
  v_sang   numeric;
  v_comp   jsonb;
begin
  select coalesce(sum((p ->> 'valor')::numeric), 0), count(distinct v.pedido_id)
    into v_vendas, v_pedidos
    from vendas v cross join lateral jsonb_array_elements(v.parcelas) p
   where v.caixa_id = c.id and v.deletado_em is null and p ->> 'metodo' = 'Dinheiro';
  select coalesce(sum(preco), 0), count(*) into v_pac, v_npac
    from adesoes_pacote
   where caixa_id = c.id and metodo = 'loja' and deletado_em is null and estado in ('activa', 'reembolsada');
  select coalesce(sum((s ->> 'valor')::numeric), 0) into v_sang from jsonb_array_elements(c.sangrias) s;
  -- Pagamentos electrónicos da caixa: referência e foto do comprovativo, para conferir antes de fechar
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', k.id, 'pedido_id', k.pedido_id, 'cliente_nome', cl.nome, 'metodo', k.metodo, 'valor', k.valor,
           'referencia', k.referencia, 'caminho', k.caminho, 'estado', k.estado, 'nota', k.nota,
           'ia_estado', k.ia_estado, 'ia_valor', k.ia_valor, 'ia_referencia', k.ia_referencia, 'ia_nota', k.ia_nota,
           'registado_por', f.nome, 'criado_em', k.criado_em) order by k.criado_em), '[]')
    into v_comp
    from comprovativos_pagamento k
    join pedidos x on x.id = k.pedido_id
    join clientes cl on cl.id = x.cliente_id
    left join funcionarios f on f.id = k.registado_por
   where k.caixa_id = c.id and k.deletado_em is null;
  return jsonb_build_object(
    'caixa_id', c.id, 'posto', c.posto, 'data', c.data, 'cozinha_id', c.cozinha_id,
    'aberta_por', c.funcionario_nome, 'troco_inicial', coalesce(c.troco_inicial, 0),
    'dinheiro_vendas', v_vendas, 'pedidos', v_pedidos, 'dinheiro_pacotes', v_pac, 'pacotes', v_npac,
    'sangrias', v_sang, 'lista_sangrias', c.sangrias,
    'esperado', coalesce(c.troco_inicial, 0) + v_vendas + v_pac - v_sang,
    'electronico', (select coalesce(sum((e ->> 'valor')::numeric), 0) from jsonb_array_elements(v_comp) e),
    'comprovativos', v_comp,
    'por_conferir', (select count(*) from jsonb_array_elements(v_comp) e where e ->> 'estado' = 'por_conferir'),
    'rejeitados', (select count(*) from jsonb_array_elements(v_comp) e where e ->> 'estado' = 'rejeitado'),
    'valor_rejeitado', (select coalesce(sum((e ->> 'valor')::numeric), 0) from jsonb_array_elements(v_comp) e
                         where e ->> 'estado' = 'rejeitado'),
    'fechamento', c.fechamento);
end $function$;

-- ---------------------------------------------------------------- 2. extratos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('extratos', 'extratos', false, 20971520, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

create table extratos (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  conta            text not null,               -- ex.: Multicaixa Express (BAI), Unitel Money
  periodo_inicio   date not null,
  periodo_fim      date not null,
  caminho          text,                        -- ficheiro no bucket extratos
  tipo_ficheiro    text check (tipo_ficheiro in ('pdf', 'imagem')),
  estado           text not null default 'aguarda_ficheiro'
    check (estado in ('aguarda_ficheiro', 'por_ler', 'a_ler', 'lido', 'ilegivel', 'indisponivel', 'manual')),
  ia_nota          text,
  ia_lido_em       timestamptz,
  ia_tentativas    int not null default 0,
  carregado_por    uuid references funcionarios(id),
  check (periodo_fim >= periodo_inicio and periodo_fim - periodo_inicio <= 62)
);
create index extratos_periodo_idx on extratos (periodo_inicio, periodo_fim);
create index extratos_carregado_idx on extratos (carregado_por);

create table extrato_movimentos (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  extrato_id       uuid not null references extratos(id),
  data             date not null,
  valor            numeric not null check (valor > 0),
  referencia       text,
  referencia_chave text,
  descricao        text,
  origem           text not null check (origem in ('ia', 'manual')),
  registado_por    uuid references funcionarios(id),
  comprovativo_id  uuid references comprovativos_pagamento(id),
  ligacao          text check (ligacao in ('automatica', 'manual')),
  ligado_por       uuid references funcionarios(id)
);
create unique index extrato_movimentos_comprovativo_key on extrato_movimentos (comprovativo_id)
  where comprovativo_id is not null and deletado_em is null;
create index extrato_movimentos_extrato_idx on extrato_movimentos (extrato_id);
create index extrato_movimentos_data_idx on extrato_movimentos (data);
create index extrato_movimentos_registado_idx on extrato_movimentos (registado_por);
create index extrato_movimentos_ligado_idx on extrato_movimentos (ligado_por);

do $$
declare t text;
begin
  foreach t in array array['extratos', 'extrato_movimentos'] loop
    execute format('create trigger trg_0_so_servidor before insert or update or delete on %I
                    for each row execute function bloquear_escrita_dispositivo()', t);
    execute format('create trigger trg_sync_receber before insert or update on %I
                    for each row execute function sync_receber()', t);
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('create policy ler on %I for select to authenticated
                    using (deletado_em is null and tem_permissao(''financas.conferir''))', t);
  end loop;
end $$;
comment on table extratos is 'Sincronização: só servidor (carregado pela app, lido pela leitura automática). Telemóvel só lê.';
comment on table extrato_movimentos is 'Sincronização: só servidor (leitura automática ou escrito à mão por financas.conferir). Telemóvel só lê.';

-- Ficheiro do extrato: <extrato_id>/<nome>.pdf|jpg|png|webp, enquanto o extrato espera o ficheiro
create or replace function extrato_caminho_valido(p_nome text) returns boolean
language sql stable security definer set search_path = public as $$
  select split_part(p_nome, '/', 3) = ''
     and split_part(p_nome, '/', 2) ~ '^[A-Za-z0-9_-]{1,80}\.(pdf|jpg|jpeg|png|webp)$'
     and exists (select 1 from extratos e where e.id::text = split_part(p_nome, '/', 1)
                    and e.deletado_em is null and e.estado = 'aguarda_ficheiro');
$$;
revoke execute on function extrato_caminho_valido(text) from public, anon;
grant execute on function extrato_caminho_valido(text) to authenticated;

create policy extratos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'extratos' and tem_permissao('financas.conferir') and extrato_caminho_valido(name));
create policy extratos_ler on storage.objects for select to authenticated
  using (bucket_id = 'extratos' and tem_permissao('financas.conferir'));

-- Os comprovativos também podem ser vistos por quem confere as finanças
create or replace function comprovativo_visivel(p_nome text) returns boolean
language sql stable security definer set search_path = public as $$
  select tem_permissao('pedidos.gerir') or tem_permissao('financas.conferir')
      or exists (select 1 from pedidos x where x.id::text = split_part(p_nome, '/', 1)
                    and pode_na_cozinha('vendas.registar', x.cozinha_id));
$$;
alter policy ler on comprovativos_pagamento
  using (deletado_em is null and (pode_na_cozinha('vendas.registar', cozinha_id) or tem_permissao('pedidos.gerir')
                                  or tem_permissao('financas.conferir')));

-- Referência sem espaços nem pontuação, em maiúsculas (para comparar)
create or replace function chave_referencia(p text) returns text
language sql immutable set search_path = public as $$
  select nullif(upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')), '');
$$;

create index comprovativos_chave_referencia_idx on comprovativos_pagamento (chave_referencia(referencia))
  where deletado_em is null;

create or replace function exigir_financas() returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return funcionario_actual();
end $$;
revoke execute on function exigir_financas() from public, anon, authenticated;

-- Carregar um extrato: cria o registo (a app envia depois o ficheiro e confirma)
create or replace function criar_extrato(p_conta text, p_inicio date, p_fim date) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_financas();
  v_id   uuid;
begin
  if nullif(trim(p_conta), '') is null or length(p_conta) > 80 then
    raise exception 'conta_invalida' using errcode = 'P0001';
  end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 62 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  insert into extratos (dispositivo_id, sincronizado_em, conta, periodo_inicio, periodo_fim, carregado_por)
  values ('servidor', now(), trim(p_conta), p_inicio, p_fim, v_func) returning id into v_id;
  perform registar_auditoria('extrato_criado', 'extratos', v_id,
    jsonb_build_object('conta', trim(p_conta), 'inicio', p_inicio, 'fim', p_fim));
  return v_id;
end $$;

-- Ficheiro enviado: o extrato fica à espera da leitura automática.
-- Sem ficheiro (p_caminho null): os movimentos vão ser escritos à mão.
create or replace function confirmar_extrato(p_extrato uuid, p_caminho text) returns void
language plpgsql security definer set search_path = public as $$
declare
  e extratos;
begin
  perform exigir_financas();
  select * into e from extratos where id = p_extrato and deletado_em is null for update;
  if not found then raise exception 'extrato_inexistente' using errcode = 'P0001'; end if;
  if e.estado <> 'aguarda_ficheiro' then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
  if p_caminho is null then
    update extratos set estado = 'manual', atualizado_em = now() where id = e.id;
  else
    if split_part(p_caminho, '/', 1) <> e.id::text
       or not exists (select 1 from storage.objects o where o.bucket_id = 'extratos' and o.name = p_caminho) then
      raise exception 'ficheiro_inexistente' using errcode = 'P0001';
    end if;
    update extratos
       set caminho = p_caminho, estado = 'por_ler', atualizado_em = now(),
           tipo_ficheiro = case when p_caminho ~* '\.pdf$' then 'pdf' else 'imagem' end
     where id = e.id;
  end if;
  perform registar_auditoria('extrato_carregado', 'extratos', e.id, jsonb_build_object('caminho', p_caminho));
end $$;

-- Pedir outra leitura automática (ex.: depois de configurar a chave, ou de uma leitura ilegível)
create or replace function pedir_nova_leitura(p_tipo text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  k comprovativos_pagamento;
begin
  if p_tipo = 'extrato' then
    perform exigir_financas();
    update extratos set estado = 'por_ler', ia_tentativas = 0, ia_nota = null, atualizado_em = now()
     where id = p_id and deletado_em is null and caminho is not null
       and estado in ('lido', 'ilegivel', 'indisponivel', 'manual');
    if not found then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
  elsif p_tipo = 'comprovativo' then
    select * into k from comprovativos_pagamento where id = p_id and deletado_em is null;
    if not found then raise exception 'comprovativo_inexistente' using errcode = 'P0001'; end if;
    if not (tem_permissao('financas.conferir') or pode_na_cozinha('vendas.registar', k.cozinha_id)) then
      raise exception 'sem_permissao' using errcode = '42501';
    end if;
    update comprovativos_pagamento set ia_estado = 'pendente', ia_tentativas = 0, ia_nota = null, atualizado_em = now()
     where id = p_id;
  else
    raise exception 'tipo_invalido' using errcode = 'P0001';
  end if;
  perform registar_auditoria('leitura_pedida', case when p_tipo = 'extrato' then 'extratos' else 'comprovativos_pagamento' end,
                             p_id, '{}'::jsonb);
end $$;

-- ---------------------------------------------------------------- conciliação
-- Liga cada entrada do extrato ainda sem par a um comprovativo: primeiro pela referência,
-- depois pelo mesmo valor no dia (ou até 2 dias de diferença), o mais próximo primeiro.
create or replace function conciliar_extrato(p_extrato uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  m   extrato_movimentos;
  k   uuid;
  n   int := 0;
begin
  for m in select * from extrato_movimentos
            where extrato_id = p_extrato and deletado_em is null and comprovativo_id is null
            order by data, valor loop
    k := null;
    if m.referencia_chave is not null then
      select c.id into k from comprovativos_pagamento c
       where c.deletado_em is null and chave_referencia(c.referencia) = m.referencia_chave and c.valor = m.valor
         and not exists (select 1 from extrato_movimentos x where x.comprovativo_id = c.id and x.deletado_em is null)
       limit 1;
    end if;
    if k is null then
      select c.id into k from comprovativos_pagamento c
       where c.deletado_em is null and c.valor = m.valor
         and abs((c.criado_em at time zone 'Africa/Luanda')::date - m.data) <= 2
         and not exists (select 1 from extrato_movimentos x where x.comprovativo_id = c.id and x.deletado_em is null)
       order by abs((c.criado_em at time zone 'Africa/Luanda')::date - m.data), c.criado_em
       limit 1;
    end if;
    if k is not null then
      update extrato_movimentos set comprovativo_id = k, ligacao = 'automatica', atualizado_em = now() where id = m.id;
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke execute on function conciliar_extrato(uuid) from public, anon, authenticated;

-- Entrada escrita à mão (quando a leitura automática não está disponível ou falhou)
create or replace function registar_movimento_extrato(p_extrato uuid, p_data date, p_valor numeric,
                                                      p_referencia text default null, p_descricao text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_financas();
  e      extratos;
  v_id   uuid;
begin
  select * into e from extratos where id = p_extrato and deletado_em is null;
  if not found then raise exception 'extrato_inexistente' using errcode = 'P0001'; end if;
  if p_valor is null or p_valor <= 0 or p_valor > 100000000 then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  if p_data is null or p_data < e.periodo_inicio - 3 or p_data > e.periodo_fim + 3 then
    raise exception 'data_fora_do_periodo' using errcode = 'P0001';
  end if;
  insert into extrato_movimentos (dispositivo_id, sincronizado_em, extrato_id, data, valor, referencia, referencia_chave,
                                  descricao, origem, registado_por)
  values ('servidor', now(), e.id, p_data, p_valor, nullif(trim(p_referencia), ''), chave_referencia(p_referencia),
          left(nullif(trim(p_descricao), ''), 200), 'manual', v_func)
  returning id into v_id;
  if e.estado in ('aguarda_ficheiro', 'indisponivel', 'ilegivel') then
    update extratos set estado = 'manual', atualizado_em = now() where id = e.id;
  end if;
  perform conciliar_extrato(e.id);
  perform registar_auditoria('extrato_movimento_manual', 'extratos', e.id,
    jsonb_build_object('movimento_id', v_id, 'data', p_data, 'valor', p_valor, 'referencia', p_referencia));
  return v_id;
end $$;

create or replace function apagar_movimento_extrato(p_movimento uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare
  m extrato_movimentos;
begin
  perform exigir_financas();
  if nullif(trim(p_motivo), '') is null then raise exception 'motivo_obrigatorio' using errcode = 'P0001'; end if;
  select * into m from extrato_movimentos where id = p_movimento and deletado_em is null for update;
  if not found then raise exception 'movimento_inexistente' using errcode = 'P0001'; end if;
  update extrato_movimentos set deletado_em = now(), atualizado_em = now() where id = m.id;
  perform registar_auditoria('extrato_movimento_apagado', 'extratos', m.extrato_id,
    jsonb_build_object('movimento_id', m.id, 'valor', m.valor, 'data', m.data, 'motivo', trim(p_motivo)));
end $$;

-- Ligação feita por uma pessoa (ou desligar, com p_comprovativo null)
create or replace function ligar_movimento(p_movimento uuid, p_comprovativo uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_financas();
  m      extrato_movimentos;
begin
  select * into m from extrato_movimentos where id = p_movimento and deletado_em is null for update;
  if not found then raise exception 'movimento_inexistente' using errcode = 'P0001'; end if;
  if p_comprovativo is not null then
    if not exists (select 1 from comprovativos_pagamento where id = p_comprovativo and deletado_em is null) then
      raise exception 'comprovativo_inexistente' using errcode = 'P0001';
    end if;
    if exists (select 1 from extrato_movimentos where comprovativo_id = p_comprovativo and deletado_em is null and id <> m.id) then
      raise exception 'comprovativo_ja_ligado' using errcode = 'P0001';
    end if;
  end if;
  update extrato_movimentos
     set comprovativo_id = p_comprovativo, ligacao = case when p_comprovativo is null then null else 'manual' end,
         ligado_por = case when p_comprovativo is null then null else v_func end, atualizado_em = now()
   where id = m.id;
  perform registar_auditoria(case when p_comprovativo is null then 'extrato_movimento_desligado' else 'extrato_movimento_ligado' end,
                             'extratos', m.extrato_id,
                             jsonb_build_object('movimento_id', m.id, 'comprovativo_id', p_comprovativo, 'antes', m.comprovativo_id));
end $$;

-- O que bate e o que sobra dos dois lados, num período
create or replace function relatorio_conciliacao(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r jsonb;
begin
  perform exigir_financas();
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 92 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  with comp as (
    select c.*, (c.criado_em at time zone 'Africa/Luanda')::date as dia,
           cl.nome as cliente_nome, fr.nome as registado_nome, fc.nome as conferido_nome,
           exists (select 1 from extratos e where e.deletado_em is null and e.estado in ('lido', 'manual')
                     and (c.criado_em at time zone 'Africa/Luanda')::date between e.periodo_inicio and e.periodo_fim) as coberto,
           (select m.id from extrato_movimentos m where m.comprovativo_id = c.id and m.deletado_em is null) as movimento_id
      from comprovativos_pagamento c
      join pedidos x on x.id = c.pedido_id
      join clientes cl on cl.id = x.cliente_id
      left join funcionarios fr on fr.id = c.registado_por
      left join funcionarios fc on fc.id = c.conferido_por
     where c.deletado_em is null
       and (c.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim
  ), mov as (
    select m.*, e.conta from extrato_movimentos m join extratos e on e.id = m.extrato_id
     where m.deletado_em is null and e.deletado_em is null and m.data between p_inicio and p_fim
  )
  select jsonb_build_object(
    'inicio', p_inicio, 'fim', p_fim,
    'encontrados', coalesce((select jsonb_agg(jsonb_build_object(
        'comprovativo_id', c.id, 'pedido_id', c.pedido_id, 'cliente_nome', c.cliente_nome, 'metodo', c.metodo,
        'valor', c.valor, 'referencia', c.referencia, 'dia', c.dia, 'movimento_id', c.movimento_id,
        'ligacao', (select ligacao from extrato_movimentos where id = c.movimento_id)) order by c.dia)
      from comp c where c.movimento_id is not null), '[]'),
    'comprovativos_sem_extrato', coalesce((select jsonb_agg(jsonb_build_object(
        'comprovativo_id', c.id, 'pedido_id', c.pedido_id, 'cliente_nome', c.cliente_nome, 'metodo', c.metodo,
        'valor', c.valor, 'referencia', c.referencia, 'dia', c.dia, 'estado', c.estado, 'ia_estado', c.ia_estado,
        'registado_por', c.registado_nome, 'conferido_por', c.conferido_nome) order by c.dia)
      from comp c where c.movimento_id is null and c.coberto), '[]'),
    'aguardam_extrato', (select count(*) from comp c where c.movimento_id is null and not c.coberto),
    'movimentos_sem_comprovativo', coalesce((select jsonb_agg(jsonb_build_object(
        'movimento_id', m.id, 'extrato_id', m.extrato_id, 'conta', m.conta, 'data', m.data, 'valor', m.valor,
        'referencia', m.referencia, 'descricao', m.descricao, 'origem', m.origem) order by m.data)
      from mov m where m.comprovativo_id is null), '[]'),
    'totais', jsonb_build_object(
      'comprovativos', (select coalesce(sum(valor), 0) from comp),
      'encontrados', (select coalesce(sum(valor), 0) from comp where movimento_id is not null),
      'sem_extrato', (select coalesce(sum(valor), 0) from comp where movimento_id is null and coberto),
      'movimentos', (select coalesce(sum(valor), 0) from mov),
      'movimentos_sem_comprovativo', (select coalesce(sum(valor), 0) from mov where comprovativo_id is null)))
  into r;
  return r;
end $$;

-- ---------------------------------------------------------------- 3. fechos
-- Fecho do dia: cada caixa (dinheiro e electrónicos) e os avisos do dia
create or replace function fecho_diario(p_dia date, p_cozinha uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_fin boolean := tem_permissao('financas.conferir');
  r     jsonb;
begin
  if p_dia is null then raise exception 'periodo_invalido' using errcode = 'P0001'; end if;
  if not v_fin and not (p_cozinha is not null and pode_na_cozinha('vendas.registar', p_cozinha)) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  with cx as (
    select c.*, z.nome as cozinha_nome,
           (select coalesce(sum(k.valor), 0) from comprovativos_pagamento k where k.caixa_id = c.id and k.deletado_em is null) as electronico,
           (select count(*) from comprovativos_pagamento k where k.caixa_id = c.id and k.deletado_em is null and k.estado = 'por_conferir') as por_conferir,
           (select count(*) from comprovativos_pagamento k where k.caixa_id = c.id and k.deletado_em is null and k.estado = 'rejeitado') as rejeitados,
           (select count(*) from comprovativos_pagamento k where k.caixa_id = c.id and k.deletado_em is null and k.ia_estado in ('diverge', 'ilegivel')) as ia_alertas
      from caixa c join cozinhas z on z.id = c.cozinha_id
     where c.deletado_em is null and c.data = p_dia and (p_cozinha is null or c.cozinha_id = p_cozinha)
  ), ped as (
    select x.* from pedidos x
     where x.deletado_em is null and (p_cozinha is null or x.cozinha_id = p_cozinha)
       and ((x.entregue_em at time zone 'Africa/Luanda')::date = p_dia
            or (x.estado = 'cancelado' and (x.atualizado_em at time zone 'Africa/Luanda')::date = p_dia))
  )
  select jsonb_build_object(
    'dia', p_dia,
    'caixas', coalesce((select jsonb_agg(jsonb_build_object(
        'caixa_id', c.id, 'posto', c.posto, 'cozinha', trim(c.cozinha_nome), 'aberta_por', c.funcionario_nome,
        'fechada', c.fechamento is not null, 'fechada_por', c.fechamento ->> 'funcionario_nome',
        'esperado', (c.fechamento ->> 'esperado')::numeric, 'contado', (c.fechamento ->> 'contado')::numeric,
        'diferenca', (c.fechamento ->> 'diferenca')::numeric, 'electronico', c.electronico,
        'por_conferir', c.por_conferir, 'rejeitados', c.rejeitados, 'ia_alertas', c.ia_alertas) order by c.cozinha_nome, c.posto)
      from cx c), '[]'),
    'pedidos_entregues', (select count(*) from ped where estado = 'entregue_pago'),
    'cancelados', (select count(*) from ped where estado = 'cancelado'),
    'vendido', (select coalesce(sum(subtotal + taxa_entrega - desconto_indicacao), 0) from ped where estado = 'entregue_pago'),
    'electronico', (select coalesce(sum(electronico), 0) from cx),
    'diferenca_caixas', (select coalesce(sum((fechamento ->> 'diferenca')::numeric), 0) from cx),
    'caixas_abertas', (select count(*) from cx where fechamento is null),
    'alertas', coalesce((select jsonb_agg(a) from (
        select jsonb_build_object('tipo', 'caixa_diferenca', 'caixa_id', c.id, 'posto', c.posto,
                                  'valor', (c.fechamento ->> 'diferenca')::numeric, 'quem', c.fechamento ->> 'funcionario_nome') a
          from cx c where c.fechamento is not null and (c.fechamento ->> 'diferenca')::numeric <> 0
        union all
        select jsonb_build_object('tipo', 'caixa_aberta', 'caixa_id', c.id, 'posto', c.posto, 'quem', c.funcionario_nome)
          from cx c where c.fechamento is null
        union all
        select jsonb_build_object('tipo', case when k.estado = 'rejeitado' then 'comprovativo_rejeitado' else 'ia_' || k.ia_estado end,
                                  'comprovativo_id', k.id, 'pedido_id', k.pedido_id, 'metodo', k.metodo, 'valor', k.valor,
                                  'referencia', k.referencia, 'ia_valor', k.ia_valor, 'ia_referencia', k.ia_referencia,
                                  'quem', (select nome from funcionarios where id = k.registado_por))
          from comprovativos_pagamento k join cx c on c.id = k.caixa_id
         where k.deletado_em is null and (k.estado = 'rejeitado' or k.ia_estado in ('diverge', 'ilegivel'))) s), '[]'))
  into r;
  return r;
end $$;

-- Fecho do mês: um resumo por dia, a conciliação com os extratos e os sinais por funcionário
create or replace function fecho_mensal(p_ano int, p_mes int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini date;
  v_fim date;
  v_conc jsonb;
  r jsonb;
begin
  perform exigir_financas();
  if p_ano is null or p_mes is null or p_mes not between 1 and 12 or p_ano not between 2020 and 2100 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  v_ini := make_date(p_ano, p_mes, 1);
  v_fim := (v_ini + interval '1 month - 1 day')::date;
  v_conc := relatorio_conciliacao(v_ini, v_fim);
  with dias as (select d::date as dia from generate_series(v_ini, v_fim, interval '1 day') d),
  ped as (select (x.entregue_em at time zone 'Africa/Luanda')::date as dia, x.*
            from pedidos x where x.deletado_em is null and x.estado = 'entregue_pago'
             and (x.entregue_em at time zone 'Africa/Luanda')::date between v_ini and v_fim),
  din as (select (v.data at time zone 'Africa/Luanda')::date as dia, (p ->> 'valor')::numeric as valor
            from vendas v cross join lateral jsonb_array_elements(v.parcelas) p
           where v.deletado_em is null and v.pedido_id is not null and p ->> 'metodo' = 'Dinheiro'
             and (v.data at time zone 'Africa/Luanda')::date between v_ini and v_fim),
  comp as (select (k.criado_em at time zone 'Africa/Luanda')::date as dia, k.*
             from comprovativos_pagamento k where k.deletado_em is null
              and (k.criado_em at time zone 'Africa/Luanda')::date between v_ini and v_fim),
  cx as (select c.* from caixa c where c.deletado_em is null and c.data between v_ini and v_fim),
  sem_ext as (select (e ->> 'comprovativo_id')::uuid as id from jsonb_array_elements(v_conc -> 'comprovativos_sem_extrato') e)
  select jsonb_build_object(
    'ano', p_ano, 'mes', p_mes, 'inicio', v_ini, 'fim', v_fim,
    'dias', coalesce((select jsonb_agg(jsonb_build_object(
        'dia', d.dia,
        'pedidos', (select count(*) from ped where ped.dia = d.dia),
        'vendido', (select coalesce(sum(subtotal + taxa_entrega - desconto_indicacao), 0) from ped where ped.dia = d.dia),
        'dinheiro', (select coalesce(sum(valor), 0) from din where din.dia = d.dia),
        'electronico', (select coalesce(sum(valor), 0) from comp where comp.dia = d.dia),
        'diferenca_caixas', (select coalesce(sum((fechamento ->> 'diferenca')::numeric), 0) from cx where cx.data = d.dia))
      order by d.dia) from dias d
      where exists (select 1 from ped where ped.dia = d.dia) or exists (select 1 from cx where cx.data = d.dia)), '[]'),
    'totais', jsonb_build_object(
      'pedidos', (select count(*) from ped),
      'vendido', (select coalesce(sum(subtotal + taxa_entrega - desconto_indicacao), 0) from ped),
      'dinheiro', (select coalesce(sum(valor), 0) from din),
      'electronico', (select coalesce(sum(valor), 0) from comp),
      'diferenca_caixas', (select coalesce(sum((fechamento ->> 'diferenca')::numeric), 0) from cx),
      'caixas_por_fechar', (select count(*) from cx where fechamento is null)),
    'conciliacao', v_conc,
    'por_funcionario', coalesce((select jsonb_agg(f order by (f ->> 'valor_sem_extrato')::numeric desc, f ->> 'nome') from (
        select jsonb_build_object(
          'funcionario_id', fu.id, 'nome', fu.nome,
          'comprovativos', (select count(*) from comp where comp.registado_por = fu.id),
          'rejeitados', (select count(*) from comp where comp.registado_por = fu.id and comp.estado = 'rejeitado'),
          'ia_alertas', (select count(*) from comp where comp.registado_por = fu.id and comp.ia_estado in ('diverge', 'ilegivel')),
          'sem_extrato', (select count(*) from comp where comp.registado_por = fu.id and comp.id in (select id from sem_ext)),
          'valor_sem_extrato', (select coalesce(sum(valor), 0) from comp where comp.registado_por = fu.id and comp.id in (select id from sem_ext)),
          'conferiu', (select count(*) from comp where comp.conferido_por = fu.id),
          'conferiu_sem_extrato', (select count(*) from comp where comp.conferido_por = fu.id and comp.estado = 'conferido'
                                     and comp.id in (select id from sem_ext)),
          'diferenca_caixas', (select coalesce(sum((cx.fechamento ->> 'diferenca')::numeric), 0) from cx
                                where (cx.fechamento ->> 'funcionario_id')::uuid = fu.id)) f
          from funcionarios fu
         where exists (select 1 from comp where comp.registado_por = fu.id or comp.conferido_por = fu.id)
            or exists (select 1 from cx where (cx.fechamento ->> 'funcionario_id')::uuid = fu.id)) s), '[]'))
  into r;
  return r;
end $$;

-- ---------------------------------------------------------------- 4. histórico do pedido
create or replace function historico_pedido(p_pedido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  x pedidos;
  r jsonb;
begin
  select * into x from pedidos where id = p_pedido;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  if not (tem_permissao('pedidos.gerir') or tem_permissao('financas.conferir')
          or pode_na_cozinha('vendas.registar', x.cozinha_id)
          or (tem_permissao('entregas.registar') and x.entregador_id is not null and x.entregador_id = funcionario_actual())) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
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

-- ---------------------------------------------------------------- leitura automática (Edge Function)
-- Reserva o que falta ler (só a Edge Function, com a chave de serviço). Os documentos ficam "a_ler";
-- uma reserva com mais de 5 minutos (execução interrompida) volta a poder ser lida.
create or replace function reservar_documentos(p_limite int default 5) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_comp jsonb;
  v_ext  jsonb;
begin
  with escolhidos as (
    select id from comprovativos_pagamento
     where deletado_em is null
       and (ia_estado = 'pendente' or (ia_estado = 'a_ler' and atualizado_em < now() - interval '5 minutes'))
     order by criado_em limit greatest(1, least(coalesce(p_limite, 5), 20))
     for update skip locked
  ), r as (
    update comprovativos_pagamento k set ia_estado = 'a_ler', atualizado_em = now()
      from escolhidos e where k.id = e.id
    returning k.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'caminho', r.caminho, 'metodo', r.metodo, 'valor', r.valor, 'referencia', r.referencia,
           'dia', (r.criado_em at time zone 'Africa/Luanda')::date)), '[]')
    into v_comp from r;
  with escolhido as (
    select id from extratos
     where deletado_em is null and caminho is not null
       and (estado = 'por_ler' or (estado = 'a_ler' and atualizado_em < now() - interval '5 minutes'))
     order by criado_em limit 1
     for update skip locked
  ), r as (
    update extratos e set estado = 'a_ler', atualizado_em = now()
      from escolhido x where e.id = x.id
    returning e.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'caminho', r.caminho, 'tipo_ficheiro', r.tipo_ficheiro, 'conta', r.conta,
           'inicio', r.periodo_inicio, 'fim', r.periodo_fim)), '[]')
    into v_ext from r;
  return jsonb_build_object('comprovativos', v_comp, 'extratos', v_ext);
end $$;

-- Resultado da leitura de um comprovativo: compara com o que o estafeta escreveu
create or replace function registar_leitura_comprovativo(p_id uuid, p_resultado text, p_valor numeric default null,
                                                         p_referencia text default null, p_data date default null,
                                                         p_nota text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  k comprovativos_pagamento;
  v_estado text;
begin
  select * into k from comprovativos_pagamento where id = p_id for update;
  if not found then raise exception 'comprovativo_inexistente' using errcode = 'P0001'; end if;
  if p_resultado = 'erro' then
    -- falha passageira (rede, limite de pedidos): tenta mais 2 vezes, depois fica indisponível
    update comprovativos_pagamento
       set ia_tentativas = ia_tentativas + 1,
           ia_estado = case when ia_tentativas + 1 >= 3 then 'indisponivel' else 'pendente' end,
           ia_nota = left(p_nota, 300), atualizado_em = now()
     where id = k.id returning ia_estado into v_estado;
    return v_estado;
  end if;
  v_estado := case p_resultado
    when 'lido' then
      case when p_valor is not null and p_valor = k.valor
                and chave_referencia(p_referencia) is not null
                and (chave_referencia(p_referencia) = chave_referencia(k.referencia)
                     or position(chave_referencia(k.referencia) in chave_referencia(p_referencia)) > 0
                     or position(chave_referencia(p_referencia) in chave_referencia(k.referencia)) > 0)
           then 'confere' else 'diverge' end
    when 'ilegivel' then 'ilegivel'
    when 'indisponivel' then 'indisponivel'
    else null end;
  if v_estado is null then raise exception 'resultado_invalido' using errcode = 'P0001'; end if;
  update comprovativos_pagamento
     set ia_estado = v_estado, ia_valor = p_valor, ia_referencia = left(p_referencia, 80), ia_data = p_data,
         ia_nota = left(p_nota, 300), ia_lido_em = now(), atualizado_em = now()
   where id = k.id;
  perform registar_auditoria('comprovativo_lido', 'comprovativos_pagamento', k.id,
    jsonb_build_object('resultado', v_estado, 'valor', p_valor, 'referencia', p_referencia, 'pedido_id', k.pedido_id));
  return v_estado;
end $$;

-- Resultado da leitura de um extrato: as entradas encontradas e a conciliação
create or replace function registar_leitura_extrato(p_id uuid, p_resultado text, p_movimentos jsonb default '[]',
                                                    p_nota text default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  e   extratos;
  m   jsonb;
  n   int := 0;
begin
  select * into e from extratos where id = p_id for update;
  if not found then raise exception 'extrato_inexistente' using errcode = 'P0001'; end if;
  if p_resultado = 'erro' then
    update extratos
       set ia_tentativas = ia_tentativas + 1,
           estado = case when ia_tentativas + 1 >= 3 then 'indisponivel' else 'por_ler' end,
           ia_nota = left(p_nota, 300), atualizado_em = now()
     where id = e.id;
    return 0;
  end if;
  if p_resultado not in ('lido', 'ilegivel', 'indisponivel') then
    raise exception 'resultado_invalido' using errcode = 'P0001';
  end if;
  if p_resultado = 'lido' then
    -- uma releitura substitui as entradas lidas antes (as escritas à mão ficam)
    update extrato_movimentos set deletado_em = now(), atualizado_em = now()
     where extrato_id = e.id and origem = 'ia' and deletado_em is null;
    for m in select * from jsonb_array_elements(coalesce(p_movimentos, '[]')) loop
      continue when (m ->> 'valor') is null or (m ->> 'valor')::numeric <= 0 or (m ->> 'data') is null;
      insert into extrato_movimentos (dispositivo_id, sincronizado_em, extrato_id, data, valor, referencia,
                                      referencia_chave, descricao, origem)
      values ('servidor', now(), e.id, (m ->> 'data')::date, (m ->> 'valor')::numeric,
              left(nullif(trim(m ->> 'referencia'), ''), 80), chave_referencia(m ->> 'referencia'),
              left(nullif(trim(m ->> 'descricao'), ''), 200), 'ia');
      n := n + 1;
    end loop;
  end if;
  update extratos
     set estado = p_resultado, ia_nota = left(p_nota, 300), ia_lido_em = now(), atualizado_em = now()
   where id = e.id;
  if p_resultado = 'lido' then perform conciliar_extrato(e.id); end if;
  perform registar_auditoria('extrato_lido', 'extratos', e.id, jsonb_build_object('resultado', p_resultado, 'movimentos', n));
  return n;
end $$;

-- Agenda a leitura automática de minuto a minuto (mesmo segredo do envio de avisos)
create or replace function agendar_leitura(p_url text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format($f$select cron.schedule('ler-documentos', '* * * * *', %L)$f$,
    format('select net.http_post(url := %L, body := ''{}''::jsonb, timeout_milliseconds := 120000, headers := jsonb_build_object('
           '''Content-Type'', ''application/json'', ''x-envio-segredo'', '
           '(select valor from public.segredos_servidor where chave = ''envio_notificacoes'')))', p_url));
  return 'agendado';
end $$;

-- ---------------------------------------------------------------- execução
revoke execute on function chave_referencia(text) from public, anon;
grant execute on function chave_referencia(text) to authenticated;
revoke execute on function reservar_documentos(int) from public, anon, authenticated;
revoke execute on function registar_leitura_comprovativo(uuid, text, numeric, text, date, text) from public, anon, authenticated;
revoke execute on function registar_leitura_extrato(uuid, text, jsonb, text) from public, anon, authenticated;
revoke execute on function agendar_leitura(text) from public, anon, authenticated;
grant execute on function reservar_documentos(int) to service_role;
grant execute on function registar_leitura_comprovativo(uuid, text, numeric, text, date, text) to service_role;
grant execute on function registar_leitura_extrato(uuid, text, jsonb, text) to service_role;
do $$
declare f text;
begin
  foreach f in array array['criar_extrato(text, date, date)', 'confirmar_extrato(uuid, text)', 'pedir_nova_leitura(text, uuid)',
                           'registar_movimento_extrato(uuid, date, numeric, text, text)', 'apagar_movimento_extrato(uuid, text)',
                           'ligar_movimento(uuid, uuid)', 'relatorio_conciliacao(date, date)', 'fecho_diario(date, uuid)',
                           'fecho_mensal(int, int)', 'historico_pedido(uuid)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
