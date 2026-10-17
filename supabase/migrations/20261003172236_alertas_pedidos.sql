-- Alertas dos pedidos: o que está parado ou atrasado chega a quem pode resolver, e o cliente sabe porquê.
--  * Pedido por confirmar há mais de parametros.alerta_confirmacao_min (7 min): N18 aos gerentes da cozinha.
--  * Pedido que passou a hora prometida há mais de parametros.alerta_atraso_min (5 min) e ainda não foi
--    entregue: N19 aos gerentes (e ao estafeta que o leva) e N20 ao cliente ("está a demorar mais do que o
--    previsto"). O gerente ou o estafeta dizem o motivo (informar_atraso) e o cliente recebe outro N20 com
--    o motivo e a nova estimativa.
-- Cada alerta fica em alertas_pedido (um por pedido e tipo), para a app mostrar e para os relatórios.

alter table parametros
  add column alerta_confirmacao_min integer not null default 7 check (alerta_confirmacao_min between 1 and 120),
  add column alerta_atraso_min integer not null default 5 check (alerta_atraso_min between 0 and 120);
comment on column parametros.alerta_confirmacao_min is 'Minutos sem confirmação até avisar os gerentes (N18)';
comment on column parametros.alerta_atraso_min is 'Minutos depois da hora prometida até avisar gerentes e cliente do atraso (N19/N20)';

create table alertas_pedido (
  id                 uuid primary key default gen_random_uuid(),
  dispositivo_id     text,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  sincronizado_em    timestamptz,
  deletado_em        timestamptz,
  pedido_id          uuid not null references pedidos(id),
  cliente_id         uuid not null references clientes(id),
  cozinha_id         uuid references cozinhas(id),
  tipo               text not null check (tipo in ('sem_confirmacao', 'atraso')),
  minutos            integer not null default 0,     -- minutos de espera/atraso quando o alerta foi dado
  motivo             text,                            -- dito pelo gerente ou estafeta (atraso)
  mais_minutos       integer,                         -- nova estimativa dada ao cliente
  motivo_por         uuid references funcionarios(id),
  motivo_em          timestamptz,
  cliente_avisado_em timestamptz,
  unique (pedido_id, tipo)
);
create index alertas_pedido_cliente_idx on alertas_pedido (cliente_id);
create index alertas_pedido_cozinha_idx on alertas_pedido (cozinha_id, criado_em);
create index alertas_pedido_motivo_por_idx on alertas_pedido (motivo_por);
create trigger trg_0_so_servidor before insert or update or delete on alertas_pedido
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on alertas_pedido
for each row execute function sync_receber();
alter table alertas_pedido enable row level security;
revoke all on alertas_pedido from anon;
revoke insert, update, delete, truncate on alertas_pedido from authenticated;
grant select on alertas_pedido to authenticated;
create policy ler on alertas_pedido for select to authenticated
  using (deletado_em is null and (cliente_id = cliente_actual() or tem_permissao('pedidos.gerir')
                                  or pode_na_cozinha('vendas.registar', cozinha_id)
                                  or exists (select 1 from pedidos x where x.id = pedido_id
                                               and x.entregador_id is not null and x.entregador_id = funcionario_actual())));
comment on table alertas_pedido is 'Sincronização: só servidor (alertas de pedidos parados ou atrasados). Telemóvel só lê.';

-- Gerentes que recebem os avisos de um pedido: os da cozinha (com turno) e o administrador principal
create or replace function gerentes_do_pedido(p_cozinha uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select f from funcionarios_com_permissao('pedidos.gerir') f
   where (select administrador_principal from funcionarios where id = f)
      or exists (select 1 from turnos t where t.funcionario_id = f and t.cozinha_id = p_cozinha and t.deletado_em is null);
$$;
revoke execute on function gerentes_do_pedido(uuid) from public, anon, authenticated;

-- Corre de minuto a minuto: dá cada alerta uma só vez por pedido
create or replace function job_alertas_pedidos() returns int
language plpgsql security definer set search_path = public as $$
declare
  p   parametros;
  x   record;
  n   int := 0;
  v_resumo text;
  v_estado_nome text;
begin
  select * into p from parametros where unico;

  -- 1. Pedidos por confirmar há demasiado tempo
  for x in
    select pe.*, c.nome as cliente_nome,
           floor(extract(epoch from now() - pe.criado_em) / 60)::int as minutos
      from pedidos pe join clientes c on c.id = pe.cliente_id
     where pe.deletado_em is null and pe.estado = 'pendente' and pe.grupo_id is null
       and pe.criado_em < now() - make_interval(mins => p.alerta_confirmacao_min)
       and pe.criado_em > now() - interval '6 hours'
       and not exists (select 1 from alertas_pedido a where a.pedido_id = pe.id and a.tipo = 'sem_confirmacao')
  loop
    select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || trim(coalesce(i ->> 'nome', 'Prato')), ', ')
      into v_resumo from jsonb_array_elements(x.itens) i;
    insert into alertas_pedido (dispositivo_id, sincronizado_em, pedido_id, cliente_id, cozinha_id, tipo, minutos)
    values ('servidor', now(), x.id, x.cliente_id, x.cozinha_id, 'sem_confirmacao', x.minutos);
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select g, 'N18', jsonb_build_object('pedido_id', x.id, 'cliente_nome', split_part(trim(x.cliente_nome), ' ', 1),
                                        'resumo', left(coalesce(v_resumo, 'pedido'), 80), 'minutos', x.minutos)
      from gerentes_do_pedido(x.cozinha_id) g;
    perform registar_auditoria('alerta_sem_confirmacao', 'pedidos', x.id, jsonb_build_object('minutos', x.minutos));
    n := n + 1;
  end loop;

  -- 2. Pedidos que passaram a hora prometida e ainda não foram entregues
  for x in
    select pe.*, c.nome as cliente_nome,
           floor(extract(epoch from now() - pe.hora_prometida) / 60)::int as minutos
      from pedidos pe join clientes c on c.id = pe.cliente_id
     where pe.deletado_em is null and pe.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
       and pe.hora_prometida is not null
       and pe.hora_prometida < now() - make_interval(mins => p.alerta_atraso_min)
       and pe.hora_prometida > now() - interval '6 hours'
       and not exists (select 1 from alertas_pedido a where a.pedido_id = pe.id and a.tipo = 'atraso')
  loop
    v_estado_nome := case x.estado when 'pendente' then 'ainda por confirmar' when 'confirmado' then 'confirmado'
                                   when 'em_preparacao' then 'em preparação' else 'a caminho' end;
    insert into alertas_pedido (dispositivo_id, sincronizado_em, pedido_id, cliente_id, cozinha_id, tipo, minutos, cliente_avisado_em)
    values ('servidor', now(), x.id, x.cliente_id, x.cozinha_id, 'atraso', x.minutos, now());
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select g, 'N19', jsonb_build_object('pedido_id', x.id, 'cliente_nome', split_part(trim(x.cliente_nome), ' ', 1),
                                        'minutos', x.minutos, 'estado_nome', v_estado_nome)
      from (select gerentes_do_pedido(x.cozinha_id) g
            union select x.entregador_id where x.estado = 'em_entrega' and x.entregador_id is not null) s;
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (x.cliente_id, 'N20', jsonb_build_object('pedido_id', x.id, 'minutos', x.minutos));
    perform registar_auditoria('alerta_atraso', 'pedidos', x.id, jsonb_build_object('minutos', x.minutos, 'estado', x.estado));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function job_alertas_pedidos() from public, anon, authenticated;

-- O gerente (ou o estafeta que leva o pedido) diz ao cliente porque é que o pedido vai atrasar
create or replace function informar_atraso(p_pedido uuid, p_motivo text, p_mais_minutos int default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  x      pedidos;
  v_func uuid := funcionario_actual();
  v_min  int;
begin
  select * into x from pedidos where id = p_pedido and deletado_em is null;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  if not coalesce(pode_na_cozinha('pedidos.gerir', x.cozinha_id) or (v_func is not null and x.entregador_id = v_func), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if x.estado not in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega') then
    raise exception 'estado_invalido' using errcode = 'P0001';
  end if;
  if nullif(trim(p_motivo), '') is null then raise exception 'motivo_obrigatorio' using errcode = 'P0001'; end if;
  if length(p_motivo) > 200 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  if p_mais_minutos is not null and p_mais_minutos not between 1 and 240 then
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
  v_min := greatest(0, floor(extract(epoch from now() - coalesce(x.hora_prometida, now())) / 60)::int);
  insert into alertas_pedido (dispositivo_id, sincronizado_em, pedido_id, cliente_id, cozinha_id, tipo, minutos,
                              motivo, mais_minutos, motivo_por, motivo_em, cliente_avisado_em)
  values ('servidor', now(), x.id, x.cliente_id, x.cozinha_id, 'atraso', v_min,
          trim(p_motivo), p_mais_minutos, v_func, now(), now())
  on conflict (pedido_id, tipo) do update
     set motivo = excluded.motivo, mais_minutos = excluded.mais_minutos, motivo_por = excluded.motivo_por,
         motivo_em = now(), cliente_avisado_em = now(), atualizado_em = now();
  insert into notificacoes_fila (cliente_id, codigo, dados)
  values (x.cliente_id, 'N20', jsonb_build_object('pedido_id', x.id, 'motivo', trim(p_motivo), 'mais_minutos', p_mais_minutos));
  perform registar_auditoria('atraso_informado', 'pedidos', x.id,
    jsonb_build_object('motivo', trim(p_motivo), 'mais_minutos', p_mais_minutos));
end $$;
revoke execute on function informar_atraso(uuid, text, int) from public, anon;
grant execute on function informar_atraso(uuid, text, int) to authenticated;

-- Alertas dos pedidos ainda em curso (para o ecrã das entregas)
create or replace function alertas_abertos() returns table (
  pedido_id uuid, tipo text, minutos int, motivo text, mais_minutos int, criado_em timestamptz, motivo_em timestamptz)
language sql stable security definer set search_path = public as $$
  select a.pedido_id, a.tipo, a.minutos, a.motivo, a.mais_minutos, a.criado_em, a.motivo_em
    from alertas_pedido a join pedidos x on x.id = a.pedido_id
   where a.deletado_em is null and x.deletado_em is null
     and x.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
     and (tem_permissao('pedidos.gerir') or pode_na_cozinha('vendas.registar', x.cozinha_id)
          or (x.entregador_id is not null and x.entregador_id = funcionario_actual()));
$$;
revoke execute on function alertas_abertos() from public, anon;
grant execute on function alertas_abertos() to authenticated;

-- ---------------------------------------------------------------- avisos N18, N19, N20
create or replace function texto_notificacao(p_codigo text, p_dados jsonb, OUT titulo text, OUT corpo text)
 RETURNS record
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
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
           when 'N13' then format('O teu %s está activo: %s refeições até %s. Bom almoço!',
                                  p_dados ->> 'pacote', p_dados ->> 'refeicoes', p_dados ->> 'fim')
           when 'N14' then case
                             when p_dados ->> 'motivo' = 'validade'
                               then format('O teu %s termina a %s e ainda tens %s. Usa-as ou pausa o pacote.',
                                           p_dados ->> 'pacote', p_dados ->> 'fim',
                                           case when (p_dados ->> 'restantes')::int = 1 then '1 refeição'
                                                else format('%s refeições', p_dados ->> 'restantes') end)
                             when (p_dados ->> 'restantes')::int = 0
                               then format('Usaste as refeições todas do teu %s. Renova para continuares a almoçar sem pagar na entrega.',
                                           p_dados ->> 'pacote')
                             else format('%s no teu %s. Renova para continuares a almoçar sem pagar na entrega.',
                                         case when (p_dados ->> 'restantes')::int = 1 then 'Resta 1 refeição'
                                              else format('Restam %s refeições', p_dados ->> 'restantes') end,
                                         p_dados ->> 'pacote')
                           end
           when 'N15' then format('%s aderiu ao %s (%s, %s). Confirma o pagamento.',
                                  coalesce(nullif(p_dados ->> 'cliente_nome', ''), 'Um cliente'), p_dados ->> 'pacote',
                                  case p_dados ->> 'metodo'
                                    when 'multicaixa_express' then 'Multicaixa Express'
                                    when 'unitel_money' then 'Unitel Money'
                                    else 'na loja' end,
                                  formatar_kz((p_dados ->> 'preco')::numeric))
           when 'N16' then case p_dados ->> 'estado'
                             when 'confirmado' then format('A %s recebeu o teu pedido e já o está a preparar.',
                                                           coalesce(nullif(p_dados ->> 'cozinha_nome', ''), 'cozinha'))
                             when 'em_entrega' then 'O teu pedido saiu para entrega. Fica atento ao telefone.'
                             when 'entregue_pago' then 'Pedido entregue. Bom apetite!'
                             else 'O teu pedido foi cancelado pela cozinha'
                                  || coalesce(': ' || nullif(trim(p_dados ->> 'motivo'), ''), '') || '.'
                           end
           when 'N17' then format('Novo pedido: %s%s · %s.',
                                  coalesce(nullif(p_dados ->> 'resumo', ''), 'pedido'),
                                  coalesce(' · ' || nullif(p_dados ->> 'zona', ''), ''),
                                  formatar_kz((p_dados ->> 'total')::numeric))
           when 'N18' then format('O pedido de %s (%s) foi feito há %s minutos e ainda não foi confirmado.',
                                  coalesce(nullif(p_dados ->> 'cliente_nome', ''), 'um cliente'),
                                  coalesce(nullif(p_dados ->> 'resumo', ''), 'pedido'), p_dados ->> 'minutos')
           when 'N19' then format('O pedido de %s está atrasado %s minutos (%s). Avisa o cliente do motivo.',
                                  coalesce(nullif(p_dados ->> 'cliente_nome', ''), 'um cliente'), p_dados ->> 'minutos',
                                  coalesce(nullif(p_dados ->> 'estado_nome', ''), 'em curso'))
           when 'N20' then case when nullif(trim(p_dados ->> 'motivo'), '') is not null
                             then format('O teu pedido vai atrasar%s: %s. Pedimos desculpa pela espera.',
                                         case when (p_dados ->> 'mais_minutos') is not null
                                              then format(' cerca de %s minutos', p_dados ->> 'mais_minutos') else '' end,
                                         trim(p_dados ->> 'motivo'))
                             else 'O teu pedido está a demorar mais do que o previsto. Já avisámos a cozinha e damos-te notícias em breve.'
                           end
         end;
$function$;

create or replace function notificacao_valida(p_codigo text, p_criado_em timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select p_criado_em > now() - case p_codigo
           when 'N5'  then interval '2 hours'    -- lembrete do almoço: 11h, só até às 13h
           when 'N10' then interval '3 hours'    -- colega aderiu ao grupo
           when 'N11' then interval '3 hours'    -- grupo fechado
           when 'N16' then interval '2 hours'    -- estado do pedido: depois disso já não interessa
           when 'N17' then interval '2 hours'    -- pedido novo para a cozinha
           when 'N18' then interval '1 hour'     -- pedido sem confirmação
           when 'N19' then interval '2 hours'    -- pedido atrasado (gerente)
           when 'N20' then interval '2 hours'    -- pedido atrasado (cliente)
           when 'N7'  then interval '24 hours'   -- destaques da semana
           when 'N9'  then interval '24 hours'   -- pedido para avaliar
           when 'N6'  then interval '48 hours'   -- ligação a expirar
           when 'N14' then interval '48 hours'   -- pacote a acabar
           else            interval '7 days'     -- ganhos, levantamentos, reconhecimentos
         end;
$function$;

create or replace function notificacoes_por_enviar(p_limite integer DEFAULT 100)
 RETURNS TABLE(id uuid, cliente_id uuid, funcionario_id uuid, destino text, codigo text, titulo text, corpo text, dados jsonb, tokens text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N10', 'N11', 'N12', 'N13', 'N14', 'N15', 'N16', 'N17', 'N18', 'N19', 'N20')
     and notificacao_valida(n.codigo, n.criado_em)
     and (funcionalidade_da_notificacao(n.codigo) is null or funcionalidade_activa(funcionalidade_da_notificacao(n.codigo)))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
     and not (n.codigo = 'N9' and exists (select 1 from avaliacoes a where a.pedido_id::text = n.dados ->> 'pedido_id'))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$function$;

create or replace function funcionalidade_da_notificacao(p_codigo text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_codigo in ('N1','N2','N3','N4','N5','N6','N8') then 'indicacao'
    when p_codigo = 'N7'  then 'destaques'
    when p_codigo = 'N9'  then 'avaliacoes'
    when p_codigo in ('N10','N11') then 'pedidos_grupo'
    when p_codigo = 'N12' then 'reconhecimento_equipa'
    when p_codigo in ('N13','N14','N15') then 'pacotes'
    -- N16 a N20: avisos do próprio pedido (estado, pedido novo, atrasos), sem interruptor
  end;
$function$;

create or replace function agendar_jobs()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  execute $c$select cron.schedule('mb_n14_pacotes',     '0 8 * * *',    'select public.job_n14_pacotes()')$c$;
  execute $c$select cron.schedule('mb_alertas_pedidos', '* * * * *',  'select public.job_alertas_pedidos()')$c$;
  execute $c$select cron.schedule('mb_notificacoes_expiradas', '30 3 * * *', 'select public.descartar_notificacoes_expiradas()')$c$;
  return 'agendado';
end $function$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_alertas_pedidos', '* * * * *', 'select public.job_alertas_pedidos()');
  end if;
end $$;
