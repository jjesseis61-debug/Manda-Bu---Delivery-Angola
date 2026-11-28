-- Avisos do dia-a-dia dos pedidos e envio automático das notificações.
--  N16 (cliente)  estado do pedido: confirmado, saiu para entrega, entregue, ou cancelado pela cozinha
--                 (quando é o próprio cliente a cancelar não se avisa). Sem interruptor: faz parte do pedido.
--  N17 (equipa)   pedido novo: a quem tem pedidos.gerir nessa cozinha (turnos) e ao administrador principal.
--                 Pedidos de grupo não avisam um a um (aparecem nos Grupos do dia quando o grupo fecha).
-- Envio: sem pg_cron nem pg_net nada saía da fila nem corriam os jobs (grupos, N9, contadores, N14...).
-- Liga as extensões quando existem (no Supabase existem; na base de testes local não) e guarda o
-- segredo do envio na base de dados: o cron manda-o à função enviar-notificacoes, que o confirma com
-- segredo_envio_valido (só service_role), sem segredo a configurar à mão.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net with schema extensions;
  end if;
  -- Função do Supabase (event trigger ensure_rls): não precisa de ser chamável pela API
  if exists (select 1 from pg_proc where proname = 'rls_auto_enable' and pronamespace = 'public'::regnamespace) then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Segredo do envio (só o servidor o lê)
-- -----------------------------------------------------------------------------
create table segredos_servidor (
  chave     text primary key,
  valor     text not null,
  criado_em timestamptz not null default now()
);
comment on table segredos_servidor is 'Só o servidor: segredos internos (ex.: o do envio das notificações). Sem acesso pela API.';
alter table segredos_servidor enable row level security;
revoke all on segredos_servidor from public, anon, authenticated;
insert into segredos_servidor (chave, valor)
values ('envio_notificacoes', replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''));

create or replace function segredo_envio_valido(p_segredo text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(p_segredo, '') <> ''
     and exists (select 1 from segredos_servidor where chave = 'envio_notificacoes' and valor = p_segredo);
$$;
revoke execute on function segredo_envio_valido(text) from public, anon, authenticated;
grant execute on function segredo_envio_valido(text) to service_role;

-- Agenda a chamada de minuto a minuto à função de envio, com o segredo guardado
create or replace function agendar_envio(p_url text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format($f$select cron.schedule('enviar-notificacoes', '* * * * *', %L)$f$,
    format('select net.http_post(url := %L, body := ''{}''::jsonb, headers := jsonb_build_object('
           '''Content-Type'', ''application/json'', ''x-envio-segredo'', '
           '(select valor from public.segredos_servidor where chave = ''envio_notificacoes'')))', p_url));
  return 'agendado';
end $$;
revoke execute on function agendar_envio(text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- N16 e N17
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.funcionalidade_da_notificacao(p_codigo text)
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
    -- N16, N17: avisos do próprio pedido, sem interruptor
  end;
$function$;

CREATE OR REPLACE FUNCTION public.texto_notificacao(p_codigo text, p_dados jsonb, OUT titulo text, OUT corpo text)
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
         end;
$function$;

CREATE OR REPLACE FUNCTION public.notificacao_valida(p_codigo text, p_criado_em timestamp with time zone)
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
           when 'N7'  then interval '24 hours'   -- destaques da semana
           when 'N9'  then interval '24 hours'   -- pedido para avaliar
           when 'N6'  then interval '48 hours'   -- ligação a expirar
           when 'N14' then interval '48 hours'   -- pacote a acabar
           else            interval '7 days'     -- ganhos, levantamentos, reconhecimentos
         end;
$function$;

CREATE OR REPLACE FUNCTION public.notificacoes_por_enviar(p_limite integer DEFAULT 100)
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
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N10', 'N11', 'N12', 'N13', 'N14', 'N15', 'N16', 'N17')
     and notificacao_valida(n.codigo, n.criado_em)
     and (funcionalidade_da_notificacao(n.codigo) is null or funcionalidade_activa(funcionalidade_da_notificacao(n.codigo)))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
     and not (n.codigo = 'N9' and exists (select 1 from avaliacoes a where a.pedido_id::text = n.dados ->> 'pedido_id'))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$function$;

create or replace function pedidos_avisar() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_resumo text;
begin
  if tg_op = 'INSERT' then
    if new.estado <> 'pendente' or new.grupo_id is not null then return new; end if;
    select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || trim(coalesce(i ->> 'nome', 'Prato')), ', ')
      into v_resumo from jsonb_array_elements(new.itens) i;
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select f, 'N17', jsonb_build_object(
             'pedido_id', new.id, 'resumo', left(coalesce(v_resumo, 'Pedido'), 80),
             'zona', (select nome from zonas where id = new.zona_id),
             'total', new.subtotal + new.taxa_entrega - new.desconto_indicacao)
      from funcionarios_com_permissao('pedidos.gerir') f
     where (select administrador_principal from funcionarios where id = f)
        or exists (select 1 from turnos t where t.funcionario_id = f and t.cozinha_id = new.cozinha_id
                      and t.deletado_em is null);
    return new;
  end if;

  if new.estado is not distinct from old.estado
     or new.estado not in ('confirmado', 'em_entrega', 'entregue_pago', 'cancelado') then
    return new;
  end if;
  -- Quem cancelou foi o próprio cliente: não precisa de aviso
  if new.estado = 'cancelado' and cliente_actual() is not distinct from new.cliente_id then return new; end if;
  insert into notificacoes_fila (cliente_id, codigo, dados)
  values (new.cliente_id, 'N16', jsonb_build_object(
            'pedido_id', new.id, 'estado', new.estado,
            'cozinha_nome', (select trim(nome) from cozinhas where id = new.cozinha_id),
            'motivo', new.motivo_cancelamento));
  return new;
end $$;
revoke execute on function pedidos_avisar() from public, anon, authenticated;

create trigger trg_avisar after insert or update of estado on pedidos
for each row execute function pedidos_avisar();
