-- Reclamações dos clientes (com análise do Claude) e estímulos mensais da equipa e dos clientes.
--  1. Reclamações: nascem de uma avaliação com poucas estrelas (parametros.reclamacao_estrelas_max) ou
--     do botão "Tenho uma reclamação" no pedido (fazer_reclamacao). O servidor junta os factos do
--     pedido (horas, atraso, alertas, itens, histórico do cliente); a Edge Function analisar-ia pede ao
--     Claude a categoria, a gravidade, se os factos lhe dão razão e uma resposta sugerida. Quem decide é
--     sempre o gerente (decidir_reclamacao), com ou sem análise automática; o cliente recebe a resposta (N22).
--  2. Estímulos mensais (Albert Bandura, autoeficácia): cada pessoa é comparada consigo própria no mês
--     anterior (experiência de mestria), recebe uma meta próxima e alcançável para o mês seguinte, vê o
--     melhor registo da equipa como modelo possível (aprendizagem vicariante) e um elogio concreto
--     (persuasão verbal). O bónus sugerido só aparece quando a meta do mês anterior foi atingida. O Claude
--     escreve a mensagem pessoal; o administrador aprova (decidir_estimulo) e só então a pessoa recebe (N23).
-- Sem a chave ANTHROPIC_API_KEY tudo funciona: a análise fica "indisponivel" e usa-se o texto base.

alter table parametros
  add column reclamacao_estrelas_max integer not null default 2 check (reclamacao_estrelas_max between 1 and 4),
  add column estimulo_bonus_meta integer not null default 5000 check (estimulo_bonus_meta between 0 and 1000000),
  add column estimulo_premio_cliente integer not null default 1000 check (estimulo_premio_cliente between 0 and 1000000),
  add column estimulo_top_clientes integer not null default 10 check (estimulo_top_clientes between 1 and 100);
comment on column parametros.reclamacao_estrelas_max is 'Avaliações com até estas estrelas viram reclamação';
comment on column parametros.estimulo_bonus_meta is 'Bónus sugerido (Kz) ao funcionário que atingiu a meta do mês anterior';
comment on column parametros.estimulo_premio_cliente is 'Prémio sugerido (Kz) ao cliente que atingiu a meta do mês anterior';
comment on column parametros.estimulo_top_clientes is 'Quantos clientes (os que mais compraram) entram nos estímulos do mês';

-- ---------------------------------------------------------------- 1. reclamações
create table reclamacoes (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  pedido_id        uuid not null references pedidos(id),
  cliente_id       uuid not null references clientes(id),
  cozinha_id       uuid references cozinhas(id),
  entregador_id    uuid references funcionarios(id),
  origem           text not null check (origem in ('avaliacao', 'cliente')),
  avaliacao_id     uuid references avaliacoes(id),
  estrelas         integer,
  texto            text check (char_length(texto) <= 500),
  -- análise automática (só um apoio)
  ia_estado        text not null default 'pendente'
                     check (ia_estado in ('pendente', 'a_analisar', 'analisada', 'indisponivel')),
  ia_tentativas    integer not null default 0,
  ia_categoria     text,
  ia_gravidade     text,
  ia_procedente    text,
  ia_fundamento    text,
  ia_resumo        text,
  ia_accao         text,
  ia_resposta      text,
  ia_compensacao   text,
  ia_nota          text,
  ia_analisada_em  timestamptz,
  -- decisão do gerente
  estado           text not null default 'aberta' check (estado in ('aberta', 'resolvida')),
  procedente       boolean,
  categoria        text check (categoria in ('atraso', 'qualidade', 'quantidade', 'pedido_errado', 'estafeta',
                                             'pagamento', 'app', 'outro')),
  resposta         text check (char_length(resposta) <= 500),
  compensacao      text check (compensacao in ('nenhuma', 'pedido_desculpa', 'desconto', 'reembolso_parcial',
                                                 'reembolso_total')),
  compensacao_valor integer check (compensacao_valor between 0 and 1000000),
  decidido_por     uuid references funcionarios(id),
  decidido_em      timestamptz,
  unique (pedido_id, origem)
);
create index reclamacoes_cliente_idx on reclamacoes (cliente_id);
create index reclamacoes_cozinha_idx on reclamacoes (cozinha_id, criado_em);
create index reclamacoes_entregador_idx on reclamacoes (entregador_id);
create index reclamacoes_avaliacao_idx on reclamacoes (avaliacao_id);
create index reclamacoes_decidido_por_idx on reclamacoes (decidido_por);
create index reclamacoes_ia_pendente_idx on reclamacoes (criado_em) where ia_estado = 'pendente';
create index reclamacoes_abertas_idx on reclamacoes (criado_em) where estado = 'aberta';
create trigger trg_0_so_servidor before insert or update or delete on reclamacoes
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on reclamacoes
for each row execute function sync_receber();
alter table reclamacoes enable row level security;
revoke all on reclamacoes from anon;
revoke insert, update, delete, truncate on reclamacoes from authenticated;
grant select on reclamacoes to authenticated;
-- O cliente vê as suas pela função minhas_reclamacoes (sem a análise interna)
create policy ler on reclamacoes for select to authenticated
  using (deletado_em is null and (tem_permissao('clientes.gerir') or pode_na_cozinha('pedidos.gerir', cozinha_id)));
comment on table reclamacoes is 'Sincronização: só servidor (reclamações, análise automática e decisão). Telemóvel só lê.';

-- Pode tratar a reclamação: gerente da cozinha do pedido ou quem gere os clientes
create or replace function pode_tratar_reclamacao(p_cozinha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(tem_permissao('clientes.gerir') or pode_na_cozinha('pedidos.gerir', p_cozinha), false);
$$;
revoke execute on function pode_tratar_reclamacao(uuid) from public, anon, authenticated;

-- Cria a reclamação e avisa os gerentes da cozinha (N21)
create or replace function criar_reclamacao(p_pedido uuid, p_origem text, p_texto text, p_estrelas int,
                                            p_avaliacao uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  x    pedidos;
  v_id uuid;
  v_nome text;
begin
  select * into x from pedidos where id = p_pedido;
  insert into reclamacoes (dispositivo_id, sincronizado_em, pedido_id, cliente_id, cozinha_id, entregador_id,
                           origem, avaliacao_id, estrelas, texto)
  values ('servidor', now(), x.id, x.cliente_id, x.cozinha_id, x.entregador_id, p_origem, p_avaliacao, p_estrelas,
          left(nullif(trim(p_texto), ''), 500))
  on conflict (pedido_id, origem) do nothing
  returning id into v_id;
  if v_id is null then return null; end if;
  select split_part(trim(nome), ' ', 1) into v_nome from clientes where id = x.cliente_id;
  insert into notificacoes_fila (funcionario_id, codigo, dados)
  select g, 'N21', jsonb_build_object('reclamacao_id', v_id, 'pedido_id', x.id, 'cliente_nome', v_nome,
                                      'estrelas', p_estrelas, 'texto', left(coalesce(nullif(trim(p_texto), ''), ''), 100))
    from gerentes_do_pedido(x.cozinha_id) g;
  perform registar_auditoria('reclamacao_criada', 'pedidos', x.id,
    jsonb_build_object('reclamacao_id', v_id, 'origem', p_origem, 'estrelas', p_estrelas));
  return v_id;
end $$;
revoke execute on function criar_reclamacao(uuid, text, text, int, uuid) from public, anon, authenticated;

-- Avaliação com poucas estrelas: vira reclamação
create or replace function avaliacoes_reclamacao() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.estrelas <= (select reclamacao_estrelas_max from parametros where unico) then
    perform criar_reclamacao(new.pedido_id, 'avaliacao', new.comentario, new.estrelas, new.id);
  end if;
  return new;
end $$;
revoke execute on function avaliacoes_reclamacao() from public, anon, authenticated;
create trigger trg_avaliacoes_reclamacao after insert on avaliacoes
for each row execute function avaliacoes_reclamacao();

-- O cliente reclama de um pedido seu (até 7 dias depois de o fazer)
create or replace function fazer_reclamacao(p_pedido uuid, p_texto text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  x pedidos;
  v_id uuid;
begin
  select * into x from pedidos where id = p_pedido and deletado_em is null;
  if not found or x.cliente_id is distinct from cliente_actual() then
    raise exception 'pedido_inexistente' using errcode = 'P0001';
  end if;
  if x.criado_em < now() - interval '7 days' then raise exception 'prazo_terminado' using errcode = 'P0001'; end if;
  if char_length(trim(coalesce(p_texto, ''))) < 5 then raise exception 'texto_curto' using errcode = 'P0001'; end if;
  if char_length(p_texto) > 500 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  v_id := criar_reclamacao(x.id, 'cliente', p_texto, null);
  if v_id is null then raise exception 'reclamacao_existente' using errcode = 'P0001'; end if;
  return v_id;
end $$;
revoke execute on function fazer_reclamacao(uuid, text) from public, anon;
grant execute on function fazer_reclamacao(uuid, text) to authenticated;

-- O que o cliente vê das suas reclamações: o texto, o estado e a resposta (nunca a análise interna)
create or replace function minhas_reclamacoes(p_pedido uuid default null) returns table (
  id uuid, pedido_id uuid, origem text, texto text, estado text, resposta text, criado_em timestamptz,
  decidido_em timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, r.pedido_id, r.origem, r.texto, r.estado, r.resposta, r.criado_em, r.decidido_em
    from reclamacoes r
   where r.deletado_em is null and r.cliente_id = cliente_actual() and cliente_actual() is not null
     and (p_pedido is null or r.pedido_id = p_pedido)
   order by r.criado_em desc;
$$;
revoke execute on function minhas_reclamacoes(uuid) from public, anon;
grant execute on function minhas_reclamacoes(uuid) to authenticated;

-- Factos do pedido que a análise compara com o que o cliente diz (sem nomes nem contactos)
create or replace function factos_reclamacao(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with r as (select * from reclamacoes where id = p_id),
  x as (select pe.* from pedidos pe join r on r.pedido_id = pe.id),
  passos as (
    select a.data, (a.detalhe::jsonb) ->> 'para' as para, (a.detalhe::jsonb) ->> 'motivo' as motivo
      from auditoria a join x on a.ref_id = x.id
     where a.acao = 'pedido_estado' and a.deletado_em is null)
  select jsonb_build_object(
    'pedido', (select jsonb_build_object(
        'feito_as', to_char(x.criado_em at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'),
        'estado', x.estado,
        'itens', (select coalesce(jsonb_agg(jsonb_build_object('nome', i ->> 'nome', 'qtd', coalesce((i ->> 'qtd')::int, 1))), '[]')
                    from jsonb_array_elements(x.itens) i),
        'total_kz', x.subtotal + x.taxa_entrega - x.desconto_indicacao,
        'observacoes', x.observacoes,
        'hora_prometida', to_char(x.hora_prometida at time zone 'Africa/Luanda', 'HH24:MI'),
        'confirmado_as', (select to_char(min(data) at time zone 'Africa/Luanda', 'HH24:MI') from passos where para = 'confirmado'),
        'saiu_as', (select to_char(min(data) at time zone 'Africa/Luanda', 'HH24:MI') from passos where para = 'em_entrega'),
        'entregue_as', to_char(x.entregue_em at time zone 'Africa/Luanda', 'HH24:MI'),
        'minutos_de_atraso_na_entrega', case when x.entregue_em is not null and x.hora_prometida is not null
                                             then greatest(0, floor(extract(epoch from x.entregue_em - x.hora_prometida) / 60)::int) end,
        'minutos_ate_entregar', case when x.entregue_em is not null
                                     then floor(extract(epoch from x.entregue_em - x.criado_em) / 60)::int end,
        'motivo_cancelamento', x.motivo_cancelamento,
        'pagamento', (select string_agg(distinct p ->> 'metodo', ', ') from jsonb_array_elements(x.parcelas) p))
      from x),
    'alertas', (select coalesce(jsonb_agg(jsonb_build_object('tipo', a.tipo, 'minutos', a.minutos, 'motivo_dado', a.motivo)), '[]')
                  from alertas_pedido a join x on a.pedido_id = x.id where a.deletado_em is null),
    'comprovativo_rejeitado', exists (select 1 from comprovativos_pagamento k join x on k.pedido_id = x.id
                                       where k.estado = 'rejeitado' and k.deletado_em is null),
    'cliente', (select jsonb_build_object(
        'pedidos_90_dias', (select count(*) from pedidos p2 where p2.cliente_id = r.cliente_id and p2.deletado_em is null
                              and p2.criado_em > now() - interval '90 days'),
        'reclamacoes_90_dias', (select count(*) from reclamacoes r2 where r2.cliente_id = r.cliente_id and r2.id <> r.id
                                  and r2.deletado_em is null and r2.criado_em > now() - interval '90 days'),
        'reclamacoes_com_razao_90_dias', (select count(*) from reclamacoes r2 where r2.cliente_id = r.cliente_id
                                            and r2.id <> r.id and r2.procedente and r2.criado_em > now() - interval '90 days'))
      from r),
    'avaliacao', (select jsonb_build_object('estrelas', av.estrelas,
                    'pratos', (select coalesce(jsonb_agg(jsonb_build_object('estrelas', ap.estrelas)), '[]')
                                 from avaliacoes_pratos ap where ap.avaliacao_id = av.id))
                    from avaliacoes av join r on av.id = r.avaliacao_id));
$$;
revoke execute on function factos_reclamacao(uuid) from public, anon, authenticated;

-- Reclamações para o ecrã do gerente (com a análise automática e os factos)
create or replace function reclamacoes_lista(p_estado text default 'aberta') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not coalesce(tem_permissao('clientes.gerir') or tem_permissao('pedidos.gerir'), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'pedido_id', r.pedido_id, 'criado_em', r.criado_em, 'origem', r.origem,
             'estrelas', r.estrelas, 'texto', r.texto, 'cliente_nome', c.nome, 'cozinha', cz.nome,
             'estafeta', f.nome, 'estado', r.estado,
             'ia_estado', r.ia_estado, 'ia_categoria', r.ia_categoria, 'ia_gravidade', r.ia_gravidade,
             'ia_procedente', r.ia_procedente, 'ia_fundamento', r.ia_fundamento, 'ia_resumo', r.ia_resumo,
             'ia_accao', r.ia_accao, 'ia_resposta', r.ia_resposta, 'ia_compensacao', r.ia_compensacao,
             'ia_nota', r.ia_nota,
             'procedente', r.procedente, 'categoria', r.categoria, 'resposta', r.resposta,
             'compensacao', r.compensacao, 'compensacao_valor', r.compensacao_valor,
             'decidido_por', d.nome, 'decidido_em', r.decidido_em,
             'factos', factos_reclamacao(r.id))
           order by r.criado_em desc)
      from reclamacoes r
      join clientes c on c.id = r.cliente_id
      left join cozinhas cz on cz.id = r.cozinha_id
      left join funcionarios f on f.id = r.entregador_id
      left join funcionarios d on d.id = r.decidido_por
     where r.deletado_em is null and pode_tratar_reclamacao(r.cozinha_id)
       and (coalesce(p_estado, 'todas') = 'todas' or r.estado = p_estado)
       and r.criado_em > now() - interval '90 days'), '[]');
end $$;
revoke execute on function reclamacoes_lista(text) from public, anon;
grant execute on function reclamacoes_lista(text) to authenticated;

-- O gerente decide: tem razão ou não, a resposta ao cliente (N22) e a compensação
create or replace function decidir_reclamacao(p_id uuid, p_procedente boolean, p_resposta text,
                                              p_categoria text default null, p_compensacao text default 'nenhuma',
                                              p_valor int default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  r reclamacoes;
begin
  select * into r from reclamacoes where id = p_id and deletado_em is null for update;
  if not found then raise exception 'reclamacao_inexistente' using errcode = 'P0001'; end if;
  if not pode_tratar_reclamacao(r.cozinha_id) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if r.estado <> 'aberta' then raise exception 'reclamacao_decidida' using errcode = 'P0001'; end if;
  if p_procedente is null then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  if char_length(trim(coalesce(p_resposta, ''))) < 5 then raise exception 'resposta_obrigatoria' using errcode = 'P0001'; end if;
  if char_length(p_resposta) > 500 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  if coalesce(p_compensacao, 'nenhuma') not in ('nenhuma', 'pedido_desculpa', 'desconto', 'reembolso_parcial', 'reembolso_total')
     or (p_categoria is not null and p_categoria not in ('atraso', 'qualidade', 'quantidade', 'pedido_errado', 'estafeta',
                                                         'pagamento', 'app', 'outro'))
     or (p_valor is not null and p_valor not between 0 and 1000000) then
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
  update reclamacoes
     set estado = 'resolvida', procedente = p_procedente, resposta = trim(p_resposta),
         categoria = coalesce(p_categoria, case when ia_categoria in ('atraso', 'qualidade', 'quantidade', 'pedido_errado',
                                                                      'estafeta', 'pagamento', 'app', 'outro')
                                                then ia_categoria else 'outro' end),
         compensacao = coalesce(p_compensacao, 'nenhuma'),
         compensacao_valor = case when coalesce(p_compensacao, 'nenhuma') in ('nenhuma', 'pedido_desculpa') then null else p_valor end,
         decidido_por = funcionario_actual(), decidido_em = now(), atualizado_em = now()
   where id = r.id;
  insert into notificacoes_fila (cliente_id, codigo, dados)
  values (r.cliente_id, 'N22', jsonb_build_object('reclamacao_id', r.id, 'pedido_id', r.pedido_id, 'resposta', trim(p_resposta)));
  perform registar_auditoria('reclamacao_decidida', 'pedidos', r.pedido_id,
    jsonb_build_object('reclamacao_id', r.id, 'procedente', p_procedente, 'compensacao', p_compensacao, 'valor', p_valor,
                       'ia_procedente', r.ia_procedente));
end $$;
revoke execute on function decidir_reclamacao(uuid, boolean, text, text, text, int) from public, anon;
grant execute on function decidir_reclamacao(uuid, boolean, text, text, text, int) to authenticated;

-- Resumo do mês: por categoria, cozinha e estafeta; quanto a análise automática acertou
create or replace function relatorio_reclamacoes(p_ano int, p_mes int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini date;
begin
  if not coalesce(tem_permissao('clientes.gerir') or tem_permissao('pedidos.gerir'), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_ano is null or p_mes is null or p_mes not between 1 and 12 or p_ano not between 2020 and 2100 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  v_ini := make_date(p_ano, p_mes, 1);
  return (
    with r as (select * from reclamacoes
                where deletado_em is null and pode_tratar_reclamacao(cozinha_id)
                  and (criado_em at time zone 'Africa/Luanda')::date >= v_ini
                  and (criado_em at time zone 'Africa/Luanda')::date < (v_ini + interval '1 month')::date)
    select jsonb_build_object(
      'ano', p_ano, 'mes', p_mes,
      'total', (select count(*) from r),
      'abertas', (select count(*) from r where estado = 'aberta'),
      'procedentes', (select count(*) from r where procedente),
      'horas_ate_responder', (select round((avg(extract(epoch from decidido_em - criado_em)) / 3600)::numeric, 1)
                                from r where decidido_em is not null),
      'compensacoes_kz', (select coalesce(sum(compensacao_valor), 0) from r),
      'ia_concordou', (select count(*) from r where procedente is not null and ia_procedente in ('sim', 'nao')
                          and (ia_procedente = 'sim') = procedente),
      'ia_com_opiniao', (select count(*) from r where procedente is not null and ia_procedente in ('sim', 'nao')),
      'por_categoria', coalesce((select jsonb_agg(jsonb_build_object('categoria', k, 'total', n, 'procedentes', p) order by n desc)
                                   from (select coalesce(categoria, ia_categoria, 'por_classificar') k, count(*) n,
                                                count(*) filter (where procedente) p
                                           from r group by 1) s), '[]'),
      'por_cozinha', coalesce((select jsonb_agg(jsonb_build_object('cozinha', cz.nome, 'total', s.n, 'procedentes', s.p) order by s.n desc)
                                 from (select cozinha_id, count(*) n, count(*) filter (where procedente) p from r group by 1) s
                                 left join cozinhas cz on cz.id = s.cozinha_id), '[]'),
      'por_estafeta', coalesce((select jsonb_agg(jsonb_build_object('estafeta', f.nome, 'total', s.n, 'procedentes', s.p) order by s.p desc, s.n desc)
                                  from (select entregador_id, count(*) n, count(*) filter (where procedente) p
                                          from r where entregador_id is not null group by 1) s
                                  join funcionarios f on f.id = s.entregador_id), '[]'))
  );
end $$;
revoke execute on function relatorio_reclamacoes(int, int) from public, anon;
grant execute on function relatorio_reclamacoes(int, int) to authenticated;

