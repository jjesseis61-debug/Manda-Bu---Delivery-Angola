-- Aviso N27 (sugestões do gerente de turno) aos gerentes da cozinha; caduca em 30 minutos, como as propostas.

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
           when 'N21' then format('Reclamação de %s%s%s',
                                  coalesce(nullif(p_dados ->> 'cliente_nome', ''), 'um cliente'),
                                  case when (p_dados ->> 'estrelas') is not null then format(' (%s★)', p_dados ->> 'estrelas') else '' end,
                                  coalesce(': ' || nullif(trim(p_dados ->> 'texto'), ''), ' sobre um pedido. Vê os detalhes e responde.'))
           when 'N22' then format('Sobre a tua reclamação: %s', p_dados ->> 'resposta')
           when 'N23' then p_dados ->> 'mensagem'
           when 'N24' then format('Investigação: risco alto nos pagamentos de %s (%s a %s). %s',
                                  coalesce(nullif(p_dados ->> 'funcionario_nome', ''), 'um funcionário'),
                                  p_dados ->> 'inicio', p_dados ->> 'fim', coalesce(p_dados ->> 'resumo', ''))
           when 'N25' then format('O relatório de %s de %s está pronto. Abre o Analista para o ler.',
                                  p_dados ->> 'mes', p_dados ->> 'ano')
           when 'N26' then format('Convida e Ganha: risco alto no código %s. %s',
                                  coalesce(nullif(p_dados ->> 'codigo', ''), '—'), coalesce(p_dados ->> 'resumo', ''))
           when 'N27' then format('Gerente de turno: %s na %s. Abre para aceitar ou recusar.',
                                  case when (p_dados ->> 'propostas')::int = 1 then '1 sugestão'
                                       else (p_dados ->> 'propostas') || ' sugestões' end,
                                  coalesce(nullif(p_dados ->> 'cozinha', ''), 'cozinha'))
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
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N10', 'N11', 'N12', 'N13', 'N14', 'N15', 'N16', 'N17', 'N18', 'N19', 'N20', 'N21', 'N22', 'N23', 'N24', 'N25', 'N26', 'N27')
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
    when p_codigo = 'N24' then 'agente_investigador'
    when p_codigo = 'N25' then 'agente_analista'
    when p_codigo = 'N26' then 'agente_vigilante'
    when p_codigo = 'N27' then 'agente_turno'
    -- N16 a N23: avisos do próprio pedido (estado, pedido novo, atrasos, reclamações) e estímulos, sem interruptor
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
           when 'N21' then interval '24 hours'   -- reclamação nova (gerente)
           when 'N27' then interval '30 minutes' -- sugestões do gerente de turno (caducam)
           when 'N7'  then interval '24 hours'   -- destaques da semana
           when 'N9'  then interval '24 hours'   -- pedido para avaliar
           when 'N6'  then interval '48 hours'   -- ligação a expirar
           when 'N14' then interval '48 hours'   -- pacote a acabar
           else            interval '7 days'     -- ganhos, levantamentos, reconhecimentos
         end;
$function$;

