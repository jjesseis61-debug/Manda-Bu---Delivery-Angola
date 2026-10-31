-- Atendimento ao cliente (Claude com ferramentas). O cliente escreve no ecrã Ajuda da app; o agente responde em
-- segundos, usando só os dados desse cliente (os seus pedidos, o estado, atrasos e motivos, o Convida e Ganha, o
-- pacote, as reclamações) e a informação pública (cardápio, zonas e taxas, regras). O Claude vê o primeiro nome do
-- cliente mas nunca o telefone, a morada nem dados de outros clientes. Não promete reembolsos, compensações nem
-- descontos e não mexe em pedidos: reclamações, alergias e tudo o que precise de uma decisão passam para uma pessoa
-- (N29 a quem tem atendimento.responder), que responde no ecrã Atendimento da app do operador (N30 ao cliente).
-- Se o agente falhar três vezes ou não estiver configurado, a conversa passa logo para uma pessoa.
-- Interruptor: funcionalidade agente_atendimento (desligada até ser testada; desligada, o ecrã Ajuda não aparece).

insert into funcionalidades (chave, activa, dispositivo_id) values ('agente_atendimento', false, 'servidor')
on conflict (chave) do nothing;
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'atendimento.responder', 'Clientes',
   'Responder às conversas do atendimento que o agente passou para uma pessoa')
on conflict (chave) do nothing;

alter table parametros
  add column atendimento_mensagens_dia integer not null default 40 check (atendimento_mensagens_dia between 1 and 500);
comment on column parametros.atendimento_mensagens_dia is 'Mensagens ao atendimento por cliente e por dia (controla o custo e o abuso)';

create table conversas_atendimento (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cliente_id       uuid not null references clientes(id),
  estado           text not null default 'agente' check (estado in ('agente', 'humano', 'fechada')),
  ia_estado        text not null default 'livre' check (ia_estado in ('livre', 'pendente', 'a_responder')),
  ia_tentativas    integer not null default 0,
  ia_nota          text,
  reservada_em     timestamptz,
  mensagens_na_reserva integer not null default 0,   -- mensagens do cliente quando o agente pegou na conversa
  motivo_humano    text,
  atendido_por     uuid references funcionarios(id),
  ultima_mensagem_em timestamptz not null default now(),
  fechada_em       timestamptz
);
create unique index conversas_atendimento_aberta_key on conversas_atendimento (cliente_id) where estado <> 'fechada' and deletado_em is null;
create index conversas_atendimento_pendente_idx on conversas_atendimento (ultima_mensagem_em) where ia_estado <> 'livre';
create index conversas_atendimento_estado_idx on conversas_atendimento (estado, ultima_mensagem_em);
create index conversas_atendimento_atendido_idx on conversas_atendimento (atendido_por);

create table mensagens_atendimento (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  conversa_id      uuid not null references conversas_atendimento(id),
  autor            text not null check (autor in ('cliente', 'agente', 'funcionario', 'sistema')),
  funcionario_id   uuid references funcionarios(id),
  texto            text not null check (char_length(texto) between 1 and 2000)
);
create index mensagens_atendimento_conversa_idx on mensagens_atendimento (conversa_id, criado_em);
create index mensagens_atendimento_funcionario_idx on mensagens_atendimento (funcionario_id);

do $$
declare t text;
begin
  foreach t in array array['conversas_atendimento', 'mensagens_atendimento'] loop
    execute format('create trigger trg_0_so_servidor before insert or update or delete on %I for each row execute function bloquear_escrita_dispositivo()', t);
    execute format('create trigger trg_sync_receber before insert or update on %I for each row execute function sync_receber()', t);
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
end $$;
create policy ler on conversas_atendimento for select to authenticated
  using (deletado_em is null and (cliente_id = cliente_actual() or tem_permissao('atendimento.responder')));
create policy ler on mensagens_atendimento for select to authenticated
  using (deletado_em is null and exists (select 1 from conversas_atendimento c where c.id = conversa_id
                                          and (c.cliente_id = cliente_actual() or tem_permissao('atendimento.responder'))));
comment on table conversas_atendimento is 'Sincronização: só servidor (conversas do atendimento ao cliente). Telemóvel só lê.';
comment on table mensagens_atendimento is 'Sincronização: só servidor (mensagens do atendimento ao cliente). Telemóvel só lê.';

-- Passa a conversa para uma pessoa e avisa quem atende (N29)
create or replace function passar_a_pessoa(p_conversa uuid, p_motivo text, p_mensagem text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  c conversas_atendimento;
begin
  update conversas_atendimento
     set estado = 'humano', ia_estado = 'livre', motivo_humano = left(p_motivo, 300), atualizado_em = now()
   where id = p_conversa and estado <> 'fechada'
  returning * into c;
  if not found then return; end if;
  if p_mensagem is not null then
    insert into mensagens_atendimento (dispositivo_id, sincronizado_em, conversa_id, autor, texto)
    values ('servidor', now(), c.id, 'sistema', p_mensagem);
  end if;
  insert into notificacoes_fila (funcionario_id, codigo, dados)
  select f, 'N29', jsonb_build_object('conversa_id', c.id, 'motivo', left(p_motivo, 120),
                                      'cliente_nome', (select split_part(trim(nome), ' ', 1) from clientes where id = c.cliente_id))
    from funcionarios_com_permissao('atendimento.responder') f
   where c.atendido_por is null or f = c.atendido_por;
end $$;
revoke execute on function passar_a_pessoa(uuid, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- pela app do cliente
create or replace function enviar_mensagem_atendimento(p_texto text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  v_texto text := trim(coalesce(p_texto, ''));
  c conversas_atendimento;
begin
  if v_cliente is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not funcionalidade_activa('agente_atendimento') then raise exception 'funcionalidade_inactiva' using errcode = 'P0001'; end if;
  if char_length(v_texto) not between 1 and 1000 then raise exception 'texto_invalido' using errcode = 'P0001'; end if;
  if (select count(*) from mensagens_atendimento m join conversas_atendimento x on x.id = m.conversa_id
       where x.cliente_id = v_cliente and m.autor = 'cliente' and m.criado_em >= inicio_dia_luanda())
     >= (select atendimento_mensagens_dia from parametros where unico) then
    raise exception 'limite_diario' using errcode = 'P0001';
  end if;
  select * into c from conversas_atendimento
   where cliente_id = v_cliente and estado <> 'fechada' and deletado_em is null for update;
  if not found then
    insert into conversas_atendimento (dispositivo_id, sincronizado_em, cliente_id)
    values ('servidor', now(), v_cliente) returning * into c;
  end if;
  insert into mensagens_atendimento (dispositivo_id, sincronizado_em, conversa_id, autor, texto)
  values ('servidor', now(), c.id, 'cliente', v_texto);
  update conversas_atendimento
     set ultima_mensagem_em = now(), atualizado_em = now(),
         -- se o agente já está a responder, não se reserva outra vez: registar_atendimento vê a mensagem nova
         ia_estado = case when estado = 'agente' and ia_estado = 'livre' then 'pendente' else ia_estado end,
         ia_tentativas = case when estado = 'agente' and ia_estado = 'livre' then 0 else ia_tentativas end
   where id = c.id;
  -- Com uma pessoa: avisa quem está a atender (ou todos, se ninguém pegou ainda), no máximo de 10 em 10 minutos
  if c.estado = 'humano' and not exists (select 1 from notificacoes_fila n where n.codigo = 'N29'
                                           and n.dados ->> 'conversa_id' = c.id::text and n.criado_em > now() - interval '10 minutes') then
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select f, 'N29', jsonb_build_object('conversa_id', c.id, 'motivo', 'nova mensagem do cliente',
                                        'cliente_nome', (select split_part(trim(nome), ' ', 1) from clientes where id = v_cliente))
      from funcionarios_com_permissao('atendimento.responder') f
     where c.atendido_por is null or f = c.atendido_por;
  end if;
  return jsonb_build_object('conversa_id', c.id, 'estado', c.estado);
end $$;
revoke execute on function enviar_mensagem_atendimento(text) from public, anon;
grant execute on function enviar_mensagem_atendimento(text) to authenticated;

create or replace function minha_conversa_atendimento() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'conversa_id', c.id, 'estado', c.estado,
           'a_escrever', c.estado = 'agente' and c.ia_estado <> 'livre',
           'mensagens', coalesce((select jsonb_agg(jsonb_build_object(
                            'id', m.id, 'autor', m.autor, 'texto', m.texto, 'criado_em', m.criado_em,
                            'quem', case when m.autor = 'funcionario' then (select split_part(trim(nome), ' ', 1) from funcionarios where id = m.funcionario_id) end)
                            order by m.criado_em)
                          from (select * from mensagens_atendimento where conversa_id = c.id and deletado_em is null
                                 order by criado_em desc limit 80) m), '[]'))
    from conversas_atendimento c
   where c.cliente_id = cliente_actual() and c.deletado_em is null
     and (c.estado <> 'fechada' or c.fechada_em > now() - interval '1 day')
   order by (c.estado <> 'fechada') desc, c.ultima_mensagem_em desc
   limit 1;
$$;
revoke execute on function minha_conversa_atendimento() from public, anon;
grant execute on function minha_conversa_atendimento() to authenticated;

create or replace function pedir_pessoa_atendimento() returns text
language plpgsql security definer set search_path = public as $$
declare
  c conversas_atendimento;
begin
  if cliente_actual() is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into c from conversas_atendimento where cliente_id = cliente_actual() and estado <> 'fechada' and deletado_em is null;
  if not found then raise exception 'sem_conversa' using errcode = 'P0001'; end if;
  if c.estado = 'humano' then return 'humano'; end if;
  perform passar_a_pessoa(c.id, 'o cliente pediu para falar com uma pessoa',
                          'Pediste para falar com uma pessoa. Um colega responde-te aqui assim que puder.');
  return 'humano';
end $$;
revoke execute on function pedir_pessoa_atendimento() from public, anon;
grant execute on function pedir_pessoa_atendimento() to authenticated;

-- ---------------------------------------------------------------- ferramentas do agente (só leitura, só o serviço)
-- Todas recebem a conversa e só devolvem dados do cliente dessa conversa
create or replace function atd_pedidos(p_conversa uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'pedido_id', p.id,
           'feito_em', to_char(p.criado_em at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'),
           'estado', p.estado,
           'itens', (select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || coalesce(i ->> 'nome', 'Prato'), ', ') from jsonb_array_elements(p.itens) i),
           'total_kz', p.subtotal + p.taxa_entrega - p.desconto_indicacao - p.credito_indicacao_usado,
           'taxa_entrega_kz', p.taxa_entrega, 'desconto_convida_kz', p.desconto_indicacao,
           'pago_com_pacote', p.refeicoes_pacote > 0,
           'cozinha', (select trim(nome) from cozinhas where id = p.cozinha_id),
           'hora_prometida', to_char(p.hora_prometida at time zone 'Africa/Luanda', 'HH24:MI'),
           'entregue_em', to_char(p.entregue_em at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'),
           'motivo_cancelamento', p.motivo_cancelamento,
           'atraso', (select jsonb_build_object('minutos', a.minutos, 'motivo_dado_ao_cliente', a.motivo, 'mais_minutos', a.mais_minutos)
                        from alertas_pedido a where a.pedido_id = p.id and a.tipo = 'atraso' and a.deletado_em is null),
           'reclamacao', (select jsonb_build_object('estado', r.estado, 'resposta', r.resposta) from reclamacoes r
                           where r.pedido_id = p.id and r.deletado_em is null order by r.criado_em desc limit 1))
           order by p.criado_em desc), '[]')
    from (select p.* from pedidos p join conversas_atendimento c on c.cliente_id = p.cliente_id
           where c.id = p_conversa and p.deletado_em is null
           order by p.criado_em desc limit 8) p;
$$;

create or replace function atd_conta(p_conversa uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'primeiro_nome', split_part(trim(cl.nome), ' ', 1),
    'convida_e_ganha', jsonb_build_object(
       'codigo', (select codigo from codigos_indicacao where cliente_id = cl.id),
       'amigos_ligados', (select count(*) from ligacoes_indicacao l where l.indicador_id = cl.id and l.deletado_em is null),
       'saldo_disponivel_kz', coalesce(s.saldo_disponivel, 0), 'em_verificacao_kz', coalesce(s.em_verificacao, 0),
       'ganho_esta_semana_kz', coalesce(s.ganho_semana, 0),
       'levantamento_minimo_kz', (select levantamento_minimo from parametros where unico),
       'ultimo_levantamento', (select jsonb_build_object('valor_kz', pg.valor, 'estado', pg.estado,
                                                         'pedido_em', (pg.criado_em at time zone 'Africa/Luanda')::date)
                                 from pagamentos_indicacao pg where pg.indicador_id = cl.id and pg.deletado_em is null
                                order by pg.criado_em desc limit 1)),
    'pacote', (select jsonb_build_object('pacote', p.nome, 'estado', a.estado,
                                         'refeicoes_restantes', a.refeicoes + a.refeicoes_oferta - a.refeicoes_usadas,
                                         'inicio', a.inicio, 'fim', a.fim, 'pausa_restante_dias', a.pausa_max_dias - a.pausa_dias_usados)
                 from adesoes_pacote a join pacotes p on p.id = a.pacote_id
                where a.cliente_id = cl.id and a.deletado_em is null and a.estado in ('pendente', 'activa')
                order by (a.estado = 'activa') desc, a.criado_em desc limit 1),
    'reclamacoes_por_responder', (select count(*) from reclamacoes r where r.cliente_id = cl.id and r.deletado_em is null
                                     and r.decidido_em is null))
    from conversas_atendimento c join clientes cl on cl.id = c.cliente_id
    left join saldo_indicacao s on s.indicador_id = cl.id
   where c.id = p_conversa;
$$;

create or replace function atd_informacoes() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'cozinhas', coalesce((select jsonb_agg(jsonb_build_object(
        'cozinha', trim(z.nome), 'estado', z.estado,
        'pratos_disponiveis', coalesce((select jsonb_agg(jsonb_build_object('prato', c.nome, 'descricao', c.descricao,
                                                                           'preco_kz', c.preco, 'prato_do_dia', c.do_dia) order by c.ordem)
                                          from cardapio c where c.cozinha_id = z.id and c.disponivel and c.deletado_em is null), '[]')))
        from cozinhas z where z.deletado_em is null), '[]'),
    'zonas', coalesce((select jsonb_agg(jsonb_build_object('zona', nome, 'taxa_kz', taxa, 'tipo', tipo,
                                                          'por_km_kz', case when modo_calculo = 'Distância' then tarifa_por_km end) order by nome)
                         from zonas where deletado_em is null), '[]'),
    'regras', (select jsonb_build_object(
        'tempo_de_entrega_min', tempo_entrega_min,
        'convida_e_ganha', jsonb_build_object('desconto_do_amigo_no_1o_pedido_kz', desconto_indicado,
                                              'ganho_por_pedido_do_amigo_kz', ganho_por_pedido, 'durante_dias', duracao_dias,
                                              'levantamento_minimo_kz', levantamento_minimo),
        'pacotes', (select coalesce(jsonb_agg(jsonb_build_object('pacote', nome, 'refeicoes', refeicoes + refeicoes_oferta,
                                                                 'preco_kz', preco, 'validade_dias', validade_dias,
                                                                 'entrega_gratis', entrega_gratis) order by ordem), '[]')
                      from pacotes where activo and deletado_em is null))
                from parametros where unico),
    'agora', to_char(now() at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'));
$$;

-- ---------------------------------------------------------------- Edge Function atendimento
create or replace function reservar_atendimento(p_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c conversas_atendimento;
begin
  if not funcionalidade_activa('agente_atendimento') then return null; end if;
  select * into c from conversas_atendimento
   where deletado_em is null and estado = 'agente' and (p_id is null or id = p_id)
     and (ia_estado = 'pendente' or (ia_estado = 'a_responder' and reservada_em < now() - interval '2 minutes'))
   order by ultima_mensagem_em limit 1 for update skip locked;
  if not found then return null; end if;
  update conversas_atendimento
     set ia_estado = 'a_responder', reservada_em = now(), atualizado_em = now(),
         mensagens_na_reserva = (select count(*) from mensagens_atendimento where conversa_id = c.id and autor = 'cliente')
   where id = c.id;
  return jsonb_build_object(
    'id', c.id,
    'primeiro_nome', (select split_part(trim(nome), ' ', 1) from clientes where id = c.cliente_id),
    'agora', to_char(now() at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'),
    'mensagens', coalesce((select jsonb_agg(jsonb_build_object('autor', m.autor, 'texto', m.texto,
                                                              'quando', to_char(m.criado_em at time zone 'Africa/Luanda', 'HH24:MI'))
                                            order by m.criado_em)
                             from (select * from mensagens_atendimento where conversa_id = c.id and deletado_em is null
                                    order by criado_em desc limit 20) m), '[]'));
end $$;

create or replace function registar_atendimento(p_id uuid, p_resultado text, p_resposta jsonb default null, p_nota text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  c conversas_atendimento;
  v_novas boolean;
begin
  select * into c from conversas_atendimento where id = p_id for update;
  if not found then raise exception 'conversa_inexistente' using errcode = 'P0001'; end if;
  if c.estado <> 'agente' then return c.estado; end if;   -- entretanto passou para uma pessoa ou fechou
  if p_resultado = 'erro' and c.ia_tentativas + 1 < 3 then
    update conversas_atendimento set ia_tentativas = ia_tentativas + 1, ia_estado = 'pendente', ia_nota = left(p_nota, 300),
                                     atualizado_em = now() where id = c.id;
    return 'pendente';
  end if;
  if p_resultado in ('erro', 'indisponivel') then
    update conversas_atendimento set ia_nota = left(p_nota, 300) where id = c.id;
    perform passar_a_pessoa(c.id, 'o agente não conseguiu responder',
                            'Não consegui responder agora. Passei a conversa a um colega, que te responde aqui assim que puder.');
    return 'humano';
  end if;
  if p_resultado <> 'respondida' or nullif(trim(p_resposta ->> 'texto'), '') is null then
    raise exception 'resultado_invalido' using errcode = 'P0001';
  end if;
  insert into mensagens_atendimento (dispositivo_id, sincronizado_em, conversa_id, autor, texto)
  values ('servidor', now(), c.id, 'agente', left(trim(p_resposta ->> 'texto'), 1500));
  v_novas := (select count(*) from mensagens_atendimento where conversa_id = c.id and autor = 'cliente') > c.mensagens_na_reserva;
  update conversas_atendimento
     set ia_estado = case when v_novas then 'pendente' else 'livre' end, ia_tentativas = 0, ia_nota = left(p_nota, 300),
         ultima_mensagem_em = now(), atualizado_em = now()
   where id = c.id;
  if coalesce((p_resposta ->> 'passar_a_pessoa')::boolean, false) then
    perform passar_a_pessoa(c.id, coalesce(nullif(trim(p_resposta ->> 'motivo'), ''), 'o agente passou a conversa'));
    return 'humano';
  end if;
  return 'respondida';
end $$;

create or replace function agendar_atendimento(p_url text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format($f$select cron.schedule('atendimento', '* * * * *', %L)$f$,
    format('select net.http_post(url := %L, body := ''{}''::jsonb, timeout_milliseconds := 60000, headers := jsonb_build_object('
           '''Content-Type'', ''application/json'', ''x-envio-segredo'', '
           '(select valor from public.segredos_servidor where chave = ''envio_notificacoes'')))', p_url));
  return 'agendado';
end $$;

-- ---------------------------------------------------------------- pela app do operador
create or replace function conversas_atendimento_lista() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('atendimento.responder') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id, 'cliente', split_part(trim(cl.nome), ' ', 1), 'estado', c.estado, 'motivo', c.motivo_humano,
             'atendido_por', f.nome, 'ultima_mensagem_em', c.ultima_mensagem_em,
             'ultima_mensagem', (select left(m.texto, 120) from mensagens_atendimento m where m.conversa_id = c.id
                                  order by m.criado_em desc limit 1),
             'ultima_do_cliente', (select m.autor = 'cliente' from mensagens_atendimento m where m.conversa_id = c.id
                                    order by m.criado_em desc limit 1))
           order by case c.estado when 'humano' then 0 when 'agente' then 1 else 2 end, c.ultima_mensagem_em desc)
      from conversas_atendimento c join clientes cl on cl.id = c.cliente_id
      left join funcionarios f on f.id = c.atendido_por
     where c.deletado_em is null and (c.estado <> 'fechada' or c.fechada_em > now() - interval '7 days')), '[]');
end $$;
revoke execute on function conversas_atendimento_lista() from public, anon;
grant execute on function conversas_atendimento_lista() to authenticated;

create or replace function conversa_atendimento(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c conversas_atendimento;
begin
  if not tem_permissao('atendimento.responder') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into c from conversas_atendimento where id = p_id and deletado_em is null;
  if not found then raise exception 'conversa_inexistente' using errcode = 'P0001'; end if;
  return jsonb_build_object(
    'id', c.id, 'estado', c.estado, 'motivo', c.motivo_humano,
    'cliente', (select split_part(trim(nome), ' ', 1) from clientes where id = c.cliente_id),
    'telefone', case when tem_permissao('clientes.gerir') then (select telefone from clientes where id = c.cliente_id) end,
    'mensagens', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'autor', m.autor, 'texto', m.texto, 'criado_em', m.criado_em,
                                                               'quem', (select nome from funcionarios where id = m.funcionario_id))
                                            order by m.criado_em)
                             from mensagens_atendimento m where m.conversa_id = c.id and m.deletado_em is null), '[]'),
    'pedidos', atd_pedidos(c.id));
end $$;
revoke execute on function conversa_atendimento(uuid) from public, anon;
grant execute on function conversa_atendimento(uuid) to authenticated;

create or replace function responder_atendimento(p_id uuid, p_texto text) returns text
language plpgsql security definer set search_path = public as $$
declare
  c conversas_atendimento;
  v_texto text := trim(coalesce(p_texto, ''));
begin
  if not tem_permissao('atendimento.responder') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if char_length(v_texto) not between 1 and 1500 then raise exception 'texto_invalido' using errcode = 'P0001'; end if;
  select * into c from conversas_atendimento where id = p_id and deletado_em is null for update;
  if not found then raise exception 'conversa_inexistente' using errcode = 'P0001'; end if;
  if c.estado = 'fechada' then raise exception 'conversa_fechada' using errcode = 'P0001'; end if;
  insert into mensagens_atendimento (dispositivo_id, sincronizado_em, conversa_id, autor, funcionario_id, texto)
  values ('servidor', now(), c.id, 'funcionario', funcionario_actual(), v_texto);
  update conversas_atendimento
     set estado = 'humano', ia_estado = 'livre', atendido_por = funcionario_actual(), ultima_mensagem_em = now(), atualizado_em = now()
   where id = c.id;
  insert into notificacoes_fila (cliente_id, codigo, dados)
  values (c.cliente_id, 'N30', jsonb_build_object('conversa_id', c.id, 'texto', left(v_texto, 150)));
  perform registar_auditoria('atendimento_respondido', 'conversas_atendimento', c.id, '{}'::jsonb);
  return 'respondida';
end $$;
revoke execute on function responder_atendimento(uuid, text) from public, anon;
grant execute on function responder_atendimento(uuid, text) to authenticated;

-- Fecha a conversa ou devolve-a ao agente
create or replace function mudar_conversa_atendimento(p_id uuid, p_estado text) returns text
language plpgsql security definer set search_path = public as $$
declare
  c conversas_atendimento;
begin
  if not tem_permissao('atendimento.responder') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_estado not in ('agente', 'fechada') then raise exception 'dados_invalidos' using errcode = 'P0001'; end if;
  select * into c from conversas_atendimento where id = p_id and deletado_em is null for update;
  if not found then raise exception 'conversa_inexistente' using errcode = 'P0001'; end if;
  if c.estado = 'fechada' then raise exception 'conversa_fechada' using errcode = 'P0001'; end if;
  update conversas_atendimento
     set estado = p_estado, ia_estado = 'livre', ia_tentativas = 0,
         fechada_em = case when p_estado = 'fechada' then now() end, atualizado_em = now()
   where id = c.id;
  insert into mensagens_atendimento (dispositivo_id, sincronizado_em, conversa_id, autor, texto)
  values ('servidor', now(), c.id, 'sistema',
          case p_estado when 'fechada' then 'Conversa terminada. Se precisares de mais alguma coisa, escreve de novo.'
                        else 'O assistente volta a responder nesta conversa.' end);
  perform registar_auditoria('atendimento_' || case p_estado when 'fechada' then 'fechado' else 'devolvido_ao_agente' end,
                             'conversas_atendimento', c.id, '{}'::jsonb);
  return p_estado;
end $$;
revoke execute on function mudar_conversa_atendimento(uuid, text) from public, anon;
grant execute on function mudar_conversa_atendimento(uuid, text) to authenticated;

do $$
declare f text;
begin
  foreach f in array array['atd_pedidos(uuid)', 'atd_conta(uuid)', 'atd_informacoes()', 'reservar_atendimento(uuid)',
                           'registar_atendimento(uuid, text, jsonb, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
revoke execute on function agendar_atendimento(text) from public, anon, authenticated;
