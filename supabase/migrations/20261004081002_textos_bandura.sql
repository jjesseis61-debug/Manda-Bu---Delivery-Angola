-- Textos das notificações revistos à luz de Albert Bandura (autoeficácia, objectivos próximos, estado emocional e
-- desengajamento moral):
--   N4  o sucesso vem primeiro e a verificação explica-se como procedimento, não como suspeita;
--   N5  um objectivo pequeno e alcançável ("basta um colega pedir") em vez de um apelo genérico;
--   N16 o cancelamento pede desculpa, tranquiliza (não se cobra nada) e dá o passo seguinte;
--   N24 e N26 deixam de rotular pessoas e códigos com "risco alto": factos a confirmar, a decisão é humana.

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
                             else 'Pedimos desculpa: a cozinha teve de cancelar o teu pedido'
                                  || coalesce(' (' || nullif(trim(p_dados ->> 'motivo'), '') || ')', '')
                                  || '. Não te cobramos nada. Podes escolher outro prato.'
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
         end;
$function$;
