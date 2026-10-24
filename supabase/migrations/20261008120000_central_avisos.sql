-- =============================================================================
-- Central de Avisos (I13): enviar avisos/notificações segmentados a partir do
-- operador. Reaproveita TODA a infra existente (notificacoes_fila, dispositivos_push,
-- texto_notificacao, notificacoes_por_enviar, edge function enviar-notificacoes).
--
-- Públicos:
--   clientes_todos | clientes_zona {zona_id} | clientes_cozinha {cozinha_id} | cliente {cliente_id}
--   func_permissao {permissao} | func_cozinha {cozinha_id} | func_todos
--
-- O texto é livre (titulo + corpo), transportado no `dados` da fila; os códigos
-- N31 (clientes) e N32 (funcionários) dizem a texto_notificacao() para o usar.
-- Só quem tem `avisos.enviar` pode enviar/pré-ver/listar.
-- =============================================================================

-- 1. Permissão nova no catálogo
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'avisos.enviar', 'Avisos',
   'Enviar avisos a clientes (todos, por zona, por cozinha, específico) e a funcionários (por permissão, por cozinha, todos)')
on conflict (chave) do nothing;

-- 2. Registo dos avisos enviados (tabela trancada: só as funções SECURITY DEFINER acedem)
create table avisos (
  id              uuid primary key default gen_random_uuid(),
  dispositivo_id  text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  sincronizado_em timestamptz,
  deletado_em     timestamptz,
  titulo          text,
  corpo           text not null check (length(btrim(corpo)) between 1 and 500),
  link            text,
  publico         text not null check (publico in
                    ('clientes_todos','clientes_zona','clientes_cozinha','cliente',
                     'func_permissao','func_cozinha','func_todos')),
  alvo            jsonb not null default '{}',
  criado_por      uuid references funcionarios(id),
  criado_por_nome text,
  total           int not null default 0,
  enviado_em      timestamptz not null default now()
);
create index avisos_enviado_idx on avisos (enviado_em desc);
create index avisos_criado_por_idx on avisos (criado_por);
alter table avisos enable row level security;
revoke all on avisos from anon, authenticated;
comment on table avisos is 'Avisos segmentados enviados do operador (Central de Avisos). Acesso só por funções SECURITY DEFINER gated por avisos.enviar.';

-- 3. Expandir um público em destinatários COM dispositivo activo (partilhado por
--    enviar_aviso e pre_visualizar_aviso). Devolve (cliente_id, funcionario_id).
create or replace function avisos_destinatarios(p_publico text, p_alvo jsonb)
returns table (cliente_id uuid, funcionario_id uuid)
language sql stable security definer set search_path to 'public' as $function$
  with base as (
    select distinct d.cliente_id, d.funcionario_id
      from dispositivos_push d
     where d.activo and d.deletado_em is null
  )
  select b.cliente_id, null::uuid
    from base b
   where p_publico = 'clientes_todos' and b.cliente_id is not null
  union all
  select b.cliente_id, null::uuid from base b
   where p_publico = 'clientes_zona' and b.cliente_id is not null
     and exists (select 1 from pedidos p where p.cliente_id = b.cliente_id and p.zona_id = (p_alvo ->> 'zona_id')::uuid)
  union all
  select b.cliente_id, null::uuid from base b
   where p_publico = 'clientes_cozinha' and b.cliente_id is not null
     and exists (select 1 from pedidos p where p.cliente_id = b.cliente_id and p.cozinha_id = (p_alvo ->> 'cozinha_id')::uuid)
  union all
  select (p_alvo ->> 'cliente_id')::uuid, null::uuid
   where p_publico = 'cliente' and nullif(p_alvo ->> 'cliente_id','') is not null
  union all
  select null::uuid, b.funcionario_id from base b
   where p_publico = 'func_todos' and b.funcionario_id is not null
  union all
  select null::uuid, b.funcionario_id from base b
   where p_publico = 'func_permissao' and b.funcionario_id is not null
     and tem_permissao_de(b.funcionario_id, p_alvo ->> 'permissao')
  union all
  select null::uuid, b.funcionario_id from base b
   where p_publico = 'func_cozinha' and b.funcionario_id is not null
     and exists (select 1 from turnos t where t.funcionario_id = b.funcionario_id
                   and t.cozinha_id = (p_alvo ->> 'cozinha_id')::uuid);
$function$;

-- 4. Pré-visualizar: quantos destinatários (com dispositivo) o público abrange
create or replace function pre_visualizar_aviso(p_publico text, p_alvo jsonb default '{}')
returns integer
language plpgsql stable security definer set search_path to 'public' as $function$
begin
  perform exigir_permissao('avisos.enviar');
  return (select count(*)::int from avisos_destinatarios(p_publico, p_alvo));
end;
$function$;

-- 5. Enviar: grava o aviso, expande o público e enfileira. Devolve {id, total}.
create or replace function enviar_aviso(p_publico text, p_titulo text, p_corpo text,
                                        p_alvo jsonb default '{}', p_link text default null)
returns jsonb
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_id     uuid;
  v_codigo text;
  v_dados  jsonb;
  v_total  int;
begin
  perform exigir_permissao('avisos.enviar');
  if p_publico not in ('clientes_todos','clientes_zona','clientes_cozinha','cliente',
                       'func_permissao','func_cozinha','func_todos') then
    raise exception 'publico_invalido' using errcode = '22023', detail = coalesce(p_publico,'');
  end if;
  if length(btrim(coalesce(p_corpo,''))) = 0 then
    raise exception 'corpo_vazio' using errcode = '22023';
  end if;

  v_codigo := case when p_publico like 'func_%' then 'N32' else 'N31' end;
  v_dados  := jsonb_strip_nulls(jsonb_build_object(
                'titulo', nullif(btrim(coalesce(p_titulo,'')), ''),
                'corpo',  btrim(p_corpo),
                'link',   nullif(btrim(coalesce(p_link,'')), '')));

  insert into avisos (titulo, corpo, link, publico, alvo, criado_por, criado_por_nome)
  values (nullif(btrim(coalesce(p_titulo,'')), ''), btrim(p_corpo), nullif(btrim(coalesce(p_link,'')), ''),
          p_publico, coalesce(p_alvo,'{}'), funcionario_actual(),
          (select nome from funcionarios where id = funcionario_actual()))
  returning id into v_id;

  insert into notificacoes_fila (cliente_id, funcionario_id, codigo, dados)
  select r.cliente_id, r.funcionario_id, v_codigo, v_dados
    from avisos_destinatarios(p_publico, coalesce(p_alvo,'{}')) r
   where r.cliente_id is not null or r.funcionario_id is not null;
  get diagnostics v_total = row_count;

  update avisos set total = v_total, atualizado_em = now() where id = v_id;
  perform registar_auditoria('aviso_enviado', 'aviso', v_id,
            jsonb_build_object('total', v_total, 'publico', p_publico));
  return jsonb_build_object('id', v_id, 'total', v_total);
end;
$function$;

-- 6. Histórico de avisos
create or replace function listar_avisos(p_limite integer default 50)
returns table (id uuid, titulo text, corpo text, link text, publico text, alvo jsonb,
               total int, criado_por_nome text, enviado_em timestamptz)
language plpgsql stable security definer set search_path to 'public' as $function$
begin
  perform exigir_permissao('avisos.enviar');
  return query
    select a.id, a.titulo, a.corpo, a.link, a.publico, a.alvo, a.total, a.criado_por_nome, a.enviado_em
      from avisos a
     where a.deletado_em is null
     order by a.enviado_em desc
     limit greatest(coalesce(p_limite, 50), 1);
end;
$function$;

-- 7. Permissões de execução
revoke execute on function avisos_destinatarios(text, jsonb) from public, anon, authenticated;
revoke execute on function pre_visualizar_aviso(text, jsonb)  from public, anon;
revoke execute on function enviar_aviso(text, text, text, jsonb, text) from public, anon;
revoke execute on function listar_avisos(integer) from public, anon;
grant  execute on function pre_visualizar_aviso(text, jsonb)  to authenticated;
grant  execute on function enviar_aviso(text, text, text, jsonb, text) to authenticated;
grant  execute on function listar_avisos(integer) to authenticated;

-- 8. Motor de notificações: aceitar os códigos de aviso N31/N32
create or replace function texto_notificacao(p_codigo text, p_dados jsonb, OUT titulo text, OUT corpo text)
 RETURNS record
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select case when p_codigo in ('N31','N32') then coalesce(nullif(p_dados ->> 'titulo', ''), 'Manda Bué') else 'Manda Bué' end,
         case p_codigo
           when 'N2' then format('%s entrou com o teu código! Ganhas %s em cada pedido durante %s dias.',
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'Um amigo'),
                                 formatar_kz((p_dados ->> 'ganho_por_pedido')::numeric),
                                 p_dados ->> 'duracao_dias')
           when 'N3' then format('+%s: o pedido de %s foi entregue. Saldo desta semana: %s.',
                                 formatar_kz((p_dados ->> 'valor')::numeric),
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'um amigo'),
                                 formatar_kz((p_dados ->> 'saldo_semana')::numeric))
           when 'N4' then format('Grande semana: já ganhaste %s! A partir daqui confirmamos cada pedido antes de pagar. É só uma verificação: os teus ganhos continuam a contar.',
                                 formatar_kz((p_dados ->> 'limite')::numeric))
           when 'N5' then case when nullif(p_dados ->> 'prato_do_dia', '') is not null
                               then format('Hoje há %s. Basta um colega pedir com o teu código para ganhares %s.',
                                           p_dados ->> 'prato_do_dia',
                                           formatar_kz((select ganho_por_pedido from parametros where unico)))
                               else format('Basta um colega pedir hoje com o teu código para ganhares %s.',
                                           formatar_kz((select ganho_por_pedido from parametros where unico))) end
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
                             else coalesce(justificacao_cancelamento((p_dados ->> 'pedido_id')::uuid, true),
                                           'Lamentamos: tivemos de cancelar o teu pedido' || frase_motivo_cancelamento(p_dados ->> 'motivo')
                                           || '. Não tens nada a pagar.')
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
           when 'N21' then format('Reclamação de %s%s%s',
                                  coalesce(nullif(p_dados ->> 'cliente_nome', ''), 'um cliente'),
                                  case when (p_dados ->> 'estrelas') is not null then format(' (%s★)', p_dados ->> 'estrelas') else '' end,
                                  coalesce(': ' || nullif(trim(p_dados ->> 'texto'), ''), ' sobre um pedido. Vê os detalhes e responde.'))
           when 'N22' then format('Sobre a tua reclamação: %s', p_dados ->> 'resposta')
           when 'N23' then p_dados ->> 'mensagem'
           when 'N24' then format('Pagamentos a confirmar de %s (%s a %s): há diferenças por explicar. Abre a Conferência para ver os factos e decidir.',
                                  coalesce(nullif(p_dados ->> 'funcionario_nome', ''), 'um funcionário'),
                                  p_dados ->> 'inicio', p_dados ->> 'fim')
           when 'N25' then format('O relatório de %s de %s está pronto. Abre o Analista para o ler.',
                                  p_dados ->> 'mes', p_dados ->> 'ano')
           when 'N26' then format('Convida e Ganha: o código %s tem sinais a confirmar. Abre a Vigilância para ver os factos e decidir.',
                                  coalesce(nullif(p_dados ->> 'codigo', ''), '—'))
           when 'N27' then format('Gerente de turno: %s na %s. Abre para aceitar ou recusar.',
                                  case when (p_dados ->> 'propostas')::int = 1 then '1 sugestão'
                                       else (p_dados ->> 'propostas') || ' sugestões' end,
                                  coalesce(nullif(p_dados ->> 'cozinha', ''), 'cozinha'))
           when 'N28' then format('Compras na %s: %s. Abre o plano de compras.',
                                  coalesce(nullif(p_dados ->> 'cozinha', ''), 'cozinha'),
                                  concat_ws(' e ',
                                    case (p_dados ->> 'compras_hoje')::int when 0 then null when 1 then '1 produto a comprar hoje'
                                         else (p_dados ->> 'compras_hoje') || ' produtos a comprar hoje' end,
                                    case (p_dados ->> 'alertas_graves')::int when 0 then null when 1 then '1 alerta grave'
                                         else (p_dados ->> 'alertas_graves') || ' alertas graves' end))
           when 'N29' then format('Atendimento: %s precisa de uma pessoa (%s). Abre para responder.',
                                  coalesce(nullif(p_dados ->> 'cliente_nome', ''), 'um cliente'),
                                  coalesce(nullif(p_dados ->> 'motivo', ''), 'sem motivo'))
           when 'N30' then format('Resposta do apoio Manda Bué: %s', p_dados ->> 'texto')
           when 'N31' then p_dados ->> 'corpo'
           when 'N32' then p_dados ->> 'corpo'
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
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N10', 'N11', 'N12', 'N13', 'N14', 'N15', 'N16', 'N17', 'N18', 'N19', 'N20', 'N21', 'N22', 'N23', 'N24', 'N25', 'N26', 'N27', 'N28', 'N29', 'N30', 'N31', 'N32')
     and notificacao_valida(n.codigo, n.criado_em)
     and (funcionalidade_da_notificacao(n.codigo) is null or funcionalidade_activa(funcionalidade_da_notificacao(n.codigo)))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
     and not (n.codigo = 'N9' and exists (select 1 from avaliacoes a where a.pedido_id::text = n.dados ->> 'pedido_id'))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$function$;
