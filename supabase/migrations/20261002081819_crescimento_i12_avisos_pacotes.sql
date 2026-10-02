-- I12 · Avisos dos pacotes (interruptor `pacotes`):
--  N13 (cliente)  pagamento confirmado: o pacote está activo, com as refeições e a validade.
--  N14 (cliente)  pacote a acabar: quando restam 3 refeições ou menos (no momento em que se gastam) e,
--                 num job diário, 3 dias antes do fim se ainda houver refeições. Uma vez por adesão e motivo.
--  N15 (equipa)   nova adesão por confirmar: a quem tem pacotes.gerir (direcção, permissão extra ou
--                 administrador principal).

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
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N10', 'N11', 'N12', 'N13', 'N14', 'N15')
     and notificacao_valida(n.codigo, n.criado_em)
     and funcionalidade_activa(funcionalidade_da_notificacao(n.codigo))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
     and not (n.codigo = 'N9' and exists (select 1 from avaliacoes a where a.pedido_id::text = n.dados ->> 'pedido_id'))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$function$;

-- Funcionários com uma permissão (a mesma regra de tem_permissao, para todos)
create or replace function funcionarios_com_permissao(p text) returns setof uuid
language sql stable security definer set search_path = public as $$
  select f.id
    from funcionarios f
    left join direcoes d on d.id = f.direcao_id and d.deletado_em is null
   where f.deletado_em is null
     and case
           when f.administrador_principal then true
           when f.permissoes_extra ? p then coalesce((f.permissoes_extra ->> p)::boolean, false)
           else coalesce((d.permissoes ->> p)::boolean, false)
         end;
$$;

create or replace function adesoes_pacote_avisar() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_pacote   text;
  v_rest_ant integer;
  v_rest     integer;
begin
  if not funcionalidade_activa('pacotes') then return new; end if;
  select nome into v_pacote from pacotes where id = new.pacote_id;

  if tg_op = 'INSERT' then
    if new.estado = 'pendente' then
      insert into notificacoes_fila (funcionario_id, codigo, dados)
      select f, 'N15', jsonb_build_object('adesao_id', new.id, 'pacote', v_pacote, 'metodo', new.metodo,
                                          'preco', new.preco,
                                          'cliente_nome', (select split_part(trim(nome), ' ', 1) from clientes where id = new.cliente_id))
        from funcionarios_com_permissao('pacotes.gerir') f;
    end if;
    return new;
  end if;

  if new.estado = 'activa' and old.estado = 'pendente' then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (new.cliente_id, 'N13', jsonb_build_object('adesao_id', new.id, 'pacote', v_pacote,
                                                      'refeicoes', new.refeicoes + new.refeicoes_oferta,
                                                      'fim', to_char(new.fim, 'DD/MM')));
  end if;

  v_rest_ant := old.refeicoes + old.refeicoes_oferta - old.refeicoes_usadas;
  v_rest     := new.refeicoes + new.refeicoes_oferta - new.refeicoes_usadas;
  if new.estado = 'activa' and v_rest <= 3 and v_rest_ant > 3
     and not exists (select 1 from notificacoes_fila n
                      where n.cliente_id = new.cliente_id and n.codigo = 'N14'
                        and n.dados ->> 'adesao_id' = new.id::text and n.dados ->> 'motivo' = 'refeicoes') then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (new.cliente_id, 'N14', jsonb_build_object('adesao_id', new.id, 'pacote', v_pacote,
                                                      'motivo', 'refeicoes', 'restantes', v_rest));
  end if;
  return new;
end $$;

create trigger trg_avisar after insert or update on adesoes_pacote
for each row execute function adesoes_pacote_avisar();

-- Job diário: pacotes que terminam daqui a 3 dias e ainda têm refeições
create or replace function job_n14_pacotes() returns void
language sql security definer set search_path = public as $$
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select a.cliente_id, 'N14',
         jsonb_build_object('adesao_id', a.id, 'pacote', p.nome, 'motivo', 'validade',
                            'fim', to_char(a.fim, 'DD/MM'),
                            'restantes', a.refeicoes + a.refeicoes_oferta - a.refeicoes_usadas)
    from adesoes_pacote a join pacotes p on p.id = a.pacote_id
   where funcionalidade_activa('pacotes')
     and a.estado = 'activa' and a.deletado_em is null
     and a.fim = hoje_luanda() + 3
     and a.refeicoes_usadas < a.refeicoes + a.refeicoes_oferta
     and not exists (select 1 from notificacoes_fila n
                      where n.cliente_id = a.cliente_id and n.codigo = 'N14'
                        and n.dados ->> 'adesao_id' = a.id::text and n.dados ->> 'motivo' = 'validade'
                        and n.dados ->> 'fim' = to_char(a.fim, 'DD/MM'));
$$;

CREATE OR REPLACE FUNCTION public.agendar_jobs()
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
  execute $c$select cron.schedule('mb_notificacoes_expiradas', '30 3 * * *', 'select public.descartar_notificacoes_expiradas()')$c$;
  return 'agendado';
end $function$;

revoke execute on function funcionarios_com_permissao(text), adesoes_pacote_avisar(), job_n14_pacotes()
  from public, anon, authenticated;
