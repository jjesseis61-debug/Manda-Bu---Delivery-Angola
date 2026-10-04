-- Privilégios das funções SECURITY DEFINER: só a API das apps e as auxiliares
-- usadas em políticas, valores por defeito e triggers SECURITY INVOKER ficam
-- chamáveis pelas apps.
begin;
\ir _helpers.psql
select plan(8);

-- ---------------------------------------------------------------------------
-- 1. Funções que deixaram de ser chamáveis pelas apps
-- ---------------------------------------------------------------------------
select is((select string_agg(p.proname, ', ' order by p.proname)
             from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('origem_venda', 'auditar_consumo_bloqueado', 'gerar_codigo_grupo')
              and (has_function_privilege('anon', p.oid, 'execute')
                   or has_function_privilege('authenticated', p.oid, 'execute'))),
          null, 'origem_venda, auditar_consumo_bloqueado e gerar_codigo_grupo não são chamáveis pelas apps');

-- ---------------------------------------------------------------------------
-- 2. Lista fechada das funções SECURITY DEFINER chamáveis
-- ---------------------------------------------------------------------------
select is((select string_agg(p.proname, ', ' order by p.proname)
             from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.prosecdef
              and p.proname <> 'rls_auto_enable'
              and has_function_privilege('authenticated', p.oid, 'execute')
              and p.proname not in (
                -- API das apps
                'alterar_funcionalidade', 'alterar_parametros', 'aprovar_levantamento', 'avaliacao_permitida',
                'cancelar_pedido', 'contador_zona', 'definir_nivel_indicador', 'destaques_mes',
                'grupo_por_codigo', 'ligar_indicacao', 'marcar_pagador_distinto', 'marcar_pago',
                'metricas_turno', 'meu_desconto_indicacao', 'minha_posicao', 'moderar_foto',
                'mudar_estado_pedido', 'ocultar_avaliacao', 'pedir_levantamento', 'pessoas_como_tu',
                'pontos_entrega_proximos', 'registar_partilha', 'rejeitar_levantamento',
                'relatorio_cozinha', 'rever_ganho', 'total_pago_mes', 'usar_credito',
                -- API da app do cliente (I2)
                'registar_cliente', 'meu_perfil', 'orcamento_pedido', 'meus_amigos',
                'registar_token_push', 'remover_token_push',
                -- API da app do operador (I3)
                'definir_telefone_funcionario', 'ligar_funcionario', 'meu_funcionario', 'painel_programa',
                'ganhos_em_verificacao', 'confirmar_ganhos_indicador', 'levantamentos_operador', 'embaixadores',
                'pedidos_operador',
                -- I5: avaliações e push da equipa
                'avaliacoes_publicas', 'medias_avaliacoes', 'avaliacoes_moderacao', 'registar_token_push_funcionario',
                -- I6: pedidos de grupo (validar_novo_grupo é chamada pelo trigger da sessão da app)
                'grupo_detalhe', 'meus_grupos', 'fechar_grupo', 'cancelar_grupo', 'grupos_operador', 'mudar_estado_grupo',
                'validar_novo_grupo',
                -- I7: fotos (foto_pode_* nas políticas do storage; fotos_da_avaliacao no trigger da app)
                'lista_avaliacoes', 'fotos_pendentes', 'foto_pode_enviar', 'foto_pode_ver', 'fotos_da_avaliacao',
                -- I8: rede de cozinhas (cozinha_aceita_pedidos no trigger da criação de grupos)
                'cozinhas_para_pedir', 'relatorio_comparativo', 'cozinha_aceita_pedidos',
                -- apagar a conta pela app (exigido pelas lojas)
                'apagar_conta',
                -- I10 e I11: localização da cozinha e acompanhamento da entrega
                'localizacao_cozinha', 'registar_posicao_entrega', 'posicao_entrega',
                -- I12: pacotes pré-pagos
                'aderir_pacote', 'cancelar_adesao_pacote', 'usar_pacote', 'pausar_pacote', 'meu_pacote',
                'pacotes_a_minha_volta', 'confirmar_pagamento_pacote', 'reembolsar_pacote', 'adesoes_operador',
                -- caixa na app do operador
                'abrir_caixa', 'resumo_caixa', 'registar_sangria', 'fechar_caixa',
                -- comprovativos dos pagamentos electrónicos (conferir; as outras duas são usadas nas políticas do Storage)
                'conferir_comprovativo', 'comprovativo_caminho_valido', 'comprovativo_visivel',
                -- conferência financeira (extratos, fechos, histórico do pedido)
                'criar_extrato', 'confirmar_extrato', 'pedir_nova_leitura', 'registar_movimento_extrato',
                'apagar_movimento_extrato', 'ligar_movimento', 'relatorio_conciliacao', 'fecho_diario',
                'fecho_mensal', 'historico_pedido', 'extrato_caminho_valido',
                -- alertas de pedidos parados ou atrasados
                'informar_atraso', 'alertas_abertos',
                -- reclamações (análise automática) e estímulos mensais
                'fazer_reclamacao', 'minhas_reclamacoes', 'reclamacoes_lista', 'decidir_reclamacao',
                'relatorio_reclamacoes', 'gerar_estimulos', 'estimulos_do_mes', 'decidir_estimulo', 'pedir_nova_analise',
                -- agente investigador financeiro (as ferramentas do agente são só do serviço)
                'abrir_investigacoes', 'casos_investigacao_lista', 'decidir_caso', 'investigar_de_novo',
                -- analista do administrador
                'perguntar_analista', 'pedir_relatorio_analista', 'perguntas_analista_lista',
                -- vigilante do Convida e Ganha
                'abrir_vigilancia', 'casos_convida_lista', 'decidir_caso_convida', 'vigiar_de_novo',
                -- gerente de turno
                'propostas_turno_lista', 'decidir_proposta_turno',
                -- stock e compras
                'planos_compras_lista', 'pedir_plano_compras', 'marcar_compra',
                -- atendimento ao cliente
                'enviar_mensagem_atendimento', 'minha_conversa_atendimento', 'pedir_pessoa_atendimento',
                'conversas_atendimento_lista', 'conversa_atendimento', 'responder_atendimento', 'mudar_conversa_atendimento',
                -- contactos públicos
                'contactos',
                -- ingredientes que o cliente pode tirar (pratos montáveis)
                'componentes_dos_pratos',
                -- auxiliares usadas em políticas RLS, valores por defeito ou triggers SECURITY INVOKER
                'cliente_actual', 'cozinha_padrao', 'e_funcionario', 'funcionalidade_activa',
                'funcionario_actual', 'membro_da_cozinha', 'tem_permissao', 'e_administrador', 'pode_na_cozinha')),
          null, 'nenhuma função SECURITY DEFINER chamável fora da lista revista');

select is((select string_agg(p.proname, ', ' order by p.proname)
             from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.prosecdef
              and p.proname <> 'rls_auto_enable'
              and has_function_privilege('anon', p.oid, 'execute')),
          null, 'nenhuma função SECURITY DEFINER nossa é chamável sem sessão (anon)');

-- ---------------------------------------------------------------------------
-- 3. O que dependia das funções revogadas continua a funcionar
-- ---------------------------------------------------------------------------
-- Grupo criado por uma sessão do cliente: o código de convite é gerado
select testes.funcionalidade('pedidos_grupo', true);
select testes.def('gil', testes.cliente('Gil Organizador'));
with z as (insert into zonas (nome, tipo, taxa) values ('Zona da sede', 'Própria', 300) returning id)
select testes.def('zona_sede', id) from z;
select testes.def('sede', testes.ponto('empresa', null, null, testes.u('zona_sede')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('gil'), testes.u('sede'));
select testes.entrar(testes.u('gil'));
set local role authenticated;
select testes.def('e_grupo', testes.erro(format(
  $$insert into pedidos_grupo (organizador_id, ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
    values (%L, %L, now() + interval '3 hours', now() + interval '2 hours', 'individual')$$,
  testes.u('gil'), testes.u('sede'))));
reset role;
select testes.sair();
select is(testes.v('e_grupo'), 'sem_erro', 'cliente cria um grupo pela app');
select matches((select codigo_convite from pedidos_grupo where organizador_id = testes.u('gil')),
               '^G-[0-9A-F]{6}$', 'código de convite gerado sem gerar_codigo_grupo exposta');

-- Guarda do consumo: sessão do telemóvel a fingir ser o servidor continua bloqueada
with dados (chave, nome) as (values ('frango', 'Frango')),
     p as (insert into produtos (nome, tipo_estoque, categoria_medida)
           select nome, 'Longo Prazo', 'Peso' from dados returning id)
select testes.def('frango', id) from p;
with x as (insert into pratos_base (nome, componentes)
           values ('Frango assado', jsonb_build_array(jsonb_build_object(
                     'produto_id', testes.u('frango'), 'quantidade', 300, 'unidade', 'g')))
           returning id)
select testes.def('prato', id) from x;
with x as (
  insert into pedidos (cliente_id, subtotal, itens)
  values (testes.u('gil'), 2000, jsonb_build_array(jsonb_build_object(
            'nome', 'Frango assado', 'qtd', 1, 'preco_unitario', 2000, 'prato_base_id', testes.u('prato'))))
  returning id)
select testes.def('p', id) from x;
select testes.pagar(testes.u('p'));
select testes.def('venda', (select id from vendas where pedido_id = testes.u('p') and origem = 'App cliente'));
select testes.def('lp_antes', (select count(*) from estoque_longo_prazo));

create policy teste_inserir_stock on estoque_longo_prazo for insert to authenticated with check (true);
select testes.def('operador', testes.funcionario('Operadora', array[]::text[]));
select testes.entrar_funcionario(testes.u('operador'));
set local role authenticated;
select testes.def('e_spoof', testes.erro(format(
  $$insert into estoque_longo_prazo (dispositivo_id, produto_id, tipo, quantidade, venda_id)
    values ('servidor', %L, 'Consumo', 300, %L)$$, testes.u('frango'), testes.u('venda'))));
reset role;
select testes.sair();
select is((select count(*) from estoque_longo_prazo)::text, testes.v('lp_antes'),
          'sessão do telemóvel com dispositivo_id = servidor: consumo descartado');
select ok(exists (select 1 from auditoria where acao = 'consumo_dispositivo_bloqueado' and bloqueado
                    and detalhe::jsonb ->> 'venda_id' = testes.v('venda')
                    and detalhe::jsonb ->> 'dispositivo_id' = 'app (indicou servidor)'
                    and detalhe::jsonb ->> 'papel' = 'authenticated'),
          'tentativa auditada como bloqueada, com o papel da sessão');
select is((select quantidade from estoque_longo_prazo where venda_id = testes.u('venda')), 300.000,
          'consumo do servidor registado uma vez (300 g)');

select * from finish();
rollback;
