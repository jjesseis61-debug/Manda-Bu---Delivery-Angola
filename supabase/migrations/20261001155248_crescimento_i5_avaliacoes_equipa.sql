-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I5 · Avaliações e equipa
--
--   1. Avaliações sem ids para os clientes: cada cliente lê só as suas linhas de
--      `avaliacoes`; a lista pública (C10) e as médias saem de funções que
--      devolvem só estrelas, comentário, data, autor (primeiro nome + inicial ou
--      pseudónimo) e pratos. Estrelas por prato só para pratos do próprio pedido.
--   2. O7 (comentários): lista de moderação com o nome real (avaliacoes.moderar).
--   3. N9: 1 hora depois da entrega, se o pedido ainda não foi avaliado.
--   4. N12 para a equipa: a fila e os tokens de push passam a aceitar também
--      funcionários; ao registar um reconhecimento, os membros do turno recebem N12.
--   5. meu_funcionario() diz de que cozinhas o funcionário é membro (O8).
--
-- Os interruptores não são ligados aqui.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Avaliações: leitura pública por funções
-- -----------------------------------------------------------------------------
alter policy ler on avaliacoes
  using (cliente_id = cliente_actual() or e_funcionario());

-- Nome do autor: primeiro nome e inicial do apelido, ou o pseudónimo se o cliente preferir
create or replace function nome_autor_avaliacao(p_cliente uuid, p_pseudonimo boolean) returns text
language sql stable security definer set search_path = public as $$
  select case
           when p_pseudonimo then (select pseudonimo from perfil_destaques where cliente_id = p_cliente)
           else (select split_part(trim(c.nome), ' ', 1)
                        || case when array_length(regexp_split_to_array(trim(c.nome), '\s+'), 1) > 1
                                then ' ' || left((regexp_split_to_array(trim(c.nome), '\s+'))[array_length(regexp_split_to_array(trim(c.nome), '\s+'), 1)], 1) || '.'
                                else '' end
                   from clientes c where c.id = p_cliente)
         end;
$$;

-- C10: avaliações visíveis de uma cozinha (e, opcionalmente, de um prato)
create or replace function avaliacoes_publicas(p_cozinha uuid, p_prato uuid default null, p_limite integer default 30)
returns table (criado_em timestamptz, estrelas integer, comentario text, autor text, pratos jsonb)
language sql stable security definer set search_path = public as $$
  select a.criado_em, a.estrelas, a.comentario,
         nome_autor_avaliacao(a.cliente_id, a.usar_pseudonimo),
         coalesce((select jsonb_agg(jsonb_build_object('nome', pb.nome, 'estrelas', ap.estrelas) order by pb.nome)
                     from avaliacoes_pratos ap join pratos_base pb on pb.id = ap.prato_id
                    where ap.avaliacao_id = a.id and ap.deletado_em is null), '[]')
    from avaliacoes a
   where funcionalidade_activa('avaliacoes') and cliente_actual() is not null
     and a.cozinha_id = p_cozinha and not a.oculta and a.deletado_em is null
     and (p_prato is null or exists (select 1 from avaliacoes_pratos ap
                                      where ap.avaliacao_id = a.id and ap.prato_id = p_prato and ap.deletado_em is null))
   order by a.criado_em desc
   limit least(greatest(coalesce(p_limite, 30), 1), 100);
$$;

-- Médias da cozinha e dos pratos, só com o mínimo de avaliações (parametros.avaliacoes_minimo)
create or replace function medias_avaliacoes(p_cozinha uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when funcionalidade_activa('avaliacoes') and cliente_actual() is not null or e_funcionario() then
    jsonb_build_object(
      'cozinha', (select jsonb_build_object('media', m.media, 'total', m.total)
                    from media_avaliacoes_cozinha m where m.cozinha_id = p_cozinha),
      'pratos', coalesce((select jsonb_agg(jsonb_build_object('prato_base_id', m.prato_id, 'media', m.media, 'total', m.total))
                            from media_avaliacoes_prato m
                           where exists (select 1 from avaliacoes_pratos ap join avaliacoes a on a.id = ap.avaliacao_id
                                          where ap.prato_id = m.prato_id and a.cozinha_id = p_cozinha)), '[]'))
  end;
$$;

-- Estrelas por prato: só pratos que estavam no pedido avaliado
create or replace function avaliacoes_pratos_antes_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from avaliacoes a join pedidos x on x.id = a.pedido_id,
                        jsonb_array_elements(x.itens) i
                  where a.id = new.avaliacao_id and i ->> 'prato_base_id' = new.prato_id::text) then
    raise exception 'prato_fora_do_pedido' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger trg_avaliacoes_pratos_antes_inserir
before insert on avaliacoes_pratos
for each row execute function avaliacoes_pratos_antes_inserir();

-- -----------------------------------------------------------------------------
-- 2. O7: comentários recentes para moderação
-- -----------------------------------------------------------------------------
create or replace function avaliacoes_moderacao(p_dias integer default 14)
returns table (avaliacao_id uuid, criado_em timestamptz, cozinha_nome text, estrelas integer,
               comentario text, oculta boolean, autor_nome text, autor_publico text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('avaliacoes.moderar');
  return query
  select a.id, a.criado_em, cz.nome, a.estrelas, a.comentario, a.oculta, c.nome,
         nome_autor_avaliacao(a.cliente_id, a.usar_pseudonimo)
    from avaliacoes a
    join clientes c on c.id = a.cliente_id
    join cozinhas cz on cz.id = a.cozinha_id
   where a.deletado_em is null and a.comentario is not null
     and a.criado_em >= now() - make_interval(days => least(greatest(coalesce(p_dias, 14), 1), 90))
   order by a.criado_em desc;
end $$;

-- -----------------------------------------------------------------------------
-- 3. N9: pedir a avaliação 1 hora depois da entrega
-- -----------------------------------------------------------------------------
create or replace function job_n9_avaliacao() returns void
language sql security definer set search_path = public as $$
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select x.cliente_id, 'N9',
         jsonb_build_object('pedido_id', x.id, 'cozinha_nome', cz.nome,
                            'refeicao', case when extract(hour from x.entregue_em at time zone 'Africa/Luanda') < 16
                                             then 'almoço' else 'jantar' end)
    from pedidos x join cozinhas cz on cz.id = x.cozinha_id
   where funcionalidade_activa('avaliacoes')
     and x.estado = 'entregue_pago' and x.deletado_em is null
     and x.entregue_em <= now() - interval '1 hour'
     and x.entregue_em >  now() - interval '3 hours'
     and not exists (select 1 from avaliacoes a where a.pedido_id = x.id)
     and not exists (select 1 from notificacoes_fila n
                      where n.codigo = 'N9' and n.dados ->> 'pedido_id' = x.id::text);
$$;

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
  return 'agendado';
end $$;

select agendar_jobs();

-- -----------------------------------------------------------------------------
-- 4. N12: notificações e push também para funcionários
-- -----------------------------------------------------------------------------
alter table notificacoes_fila alter column cliente_id drop not null;
alter table notificacoes_fila add column funcionario_id uuid references funcionarios(id);
alter table notificacoes_fila add constraint notificacoes_fila_destino
  check (num_nonnulls(cliente_id, funcionario_id) = 1);
create index notificacoes_fila_funcionario_idx on notificacoes_fila (funcionario_id) where funcionario_id is not null;

alter table dispositivos_push alter column cliente_id drop not null;
alter table dispositivos_push add column funcionario_id uuid references funcionarios(id);
alter table dispositivos_push add constraint dispositivos_push_dono
  check (num_nonnulls(cliente_id, funcionario_id) = 1);
create index dispositivos_push_funcionario_idx on dispositivos_push (funcionario_id) where activo;

create or replace function registar_token_push(p_token text, p_plataforma text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
begin
  if v_cliente is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  if p_token is null or p_token !~ '^(ExponentPushToken|ExpoPushToken)\[[^\]]+\]$' then
    raise exception 'token_invalido' using errcode = 'P0001';
  end if;
  insert into dispositivos_push (cliente_id, token, plataforma, activo, dispositivo_id)
  values (v_cliente, p_token, p_plataforma, true, 'servidor')
  on conflict (token) do update
    set cliente_id = excluded.cliente_id, funcionario_id = null, plataforma = excluded.plataforma,
        activo = true, atualizado_em = now(), deletado_em = null;
end $$;

create or replace function registar_token_push_funcionario(p_token text, p_plataforma text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := funcionario_actual();
begin
  if v_func is null then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_token is null or p_token !~ '^(ExponentPushToken|ExpoPushToken)\[[^\]]+\]$' then
    raise exception 'token_invalido' using errcode = 'P0001';
  end if;
  insert into dispositivos_push (funcionario_id, token, plataforma, activo, dispositivo_id)
  values (v_func, p_token, p_plataforma, true, 'servidor')
  on conflict (token) do update
    set funcionario_id = excluded.funcionario_id, cliente_id = null, plataforma = excluded.plataforma,
        activo = true, atualizado_em = now(), deletado_em = null;
end $$;

create or replace function remover_token_push(p_token text) returns void
language sql security definer set search_path = public as $$
  update dispositivos_push set activo = false, atualizado_em = now()
   where token = p_token
     and (cliente_id = cliente_actual() or funcionario_id = funcionario_actual());
$$;

-- Ao registar um reconhecimento: auditoria e N12 para os membros do turno nessa semana
create or replace function reconhecimentos_depois_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform registar_auditoria('reconhecimento_turno', 'reconhecimentos_turno', new.id,
    jsonb_build_object('cozinha_id', new.cozinha_id, 'semana', new.semana,
                       'periodo', new.periodo, 'tipo', new.tipo));
  if funcionalidade_activa('reconhecimento_equipa') then
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select distinct t.funcionario_id, 'N12',
           jsonb_build_object('reconhecimento_id', new.id, 'periodo', new.periodo,
                              'tipo', new.tipo, 'nota', new.nota)
      from turnos t
     where t.cozinha_id = new.cozinha_id and t.periodo = new.periodo and t.deletado_em is null
       and t.data between new.semana and new.semana + 6
       and t.funcionario_id is not null;
  end if;
  return new;
end $$;

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
           when 'N12' then format('Parabéns, turno da %s: %s!',
                                  case p_dados ->> 'periodo' when 'manha' then 'manhã' else p_dados ->> 'periodo' end,
                                  case p_dados ->> 'tipo'
                                    when 'entregas_a_horas'  then 'entregas a horas esta semana'
                                    when 'menos_desperdicio' then 'menos desperdício esta semana'
                                    when 'caixa_certa'       then 'caixa certa esta semana'
                                    else coalesce(nullif(trim(p_dados ->> 'nota'), ''), 'bom trabalho esta semana') end)
         end;
$$;

-- Notificações por enviar, com o destino (cliente ou funcionário): a Edge Function
-- envia cada destino num pedido à Expo à parte (as duas apps são projectos diferentes).
-- Substitui notificacoes_pendentes (que fica só para a versão anterior da Edge Function).
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
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N12')
     and funcionalidade_activa(funcionalidade_da_notificacao(n.codigo))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
     and not (n.codigo = 'N9' and exists (select 1 from avaliacoes a where a.pedido_id::text = n.dados ->> 'pedido_id'))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$$;

-- -----------------------------------------------------------------------------
-- 5. meu_funcionario(): cozinhas de que é membro (O8)
-- -----------------------------------------------------------------------------
create or replace function meu_funcionario() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'funcionario_id', f.id,
           'nome', f.nome,
           'cargo', f.cargo,
           'administrador_principal', f.administrador_principal,
           'permissoes', coalesce((select jsonb_agg(p.chave order by p.chave) from permissoes p
                                    where p.deletado_em is null and tem_permissao(p.chave)), '[]'),
           'cozinhas_equipa', coalesce((select jsonb_agg(distinct t.cozinha_id) from turnos t
                                         where t.funcionario_id = f.id and t.deletado_em is null), '[]'))
    from funcionarios f
   where f.auth_user_id = auth.uid() and auth.uid() is not null and f.deletado_em is null;
$$;

-- -----------------------------------------------------------------------------
-- 6. Privilégios
-- -----------------------------------------------------------------------------
revoke execute on function avaliacoes_publicas(uuid, uuid, integer), medias_avaliacoes(uuid),
                           avaliacoes_moderacao(integer), registar_token_push_funcionario(text, text)
  from public, anon;
grant execute on function avaliacoes_publicas(uuid, uuid, integer), medias_avaliacoes(uuid),
                          avaliacoes_moderacao(integer), registar_token_push_funcionario(text, text)
  to authenticated;
revoke execute on function nome_autor_avaliacao(uuid, boolean)  from public, anon, authenticated;
revoke execute on function job_n9_avaliacao()                   from public, anon, authenticated;
revoke execute on function agendar_jobs()                       from public, anon, authenticated;
revoke execute on function avaliacoes_pratos_antes_inserir()    from public, anon, authenticated;
revoke execute on function notificacoes_por_enviar(integer)     from public, anon, authenticated;
revoke execute on function texto_notificacao(text, jsonb)       from public, anon, authenticated;
grant execute on function notificacoes_por_enviar(integer), texto_notificacao(text, jsonb) to service_role;
