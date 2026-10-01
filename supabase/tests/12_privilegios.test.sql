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
                -- auxiliares usadas em políticas RLS, valores por defeito ou triggers SECURITY INVOKER
                'cliente_actual', 'cozinha_padrao', 'e_funcionario', 'funcionalidade_activa',
                'funcionario_actual', 'membro_da_cozinha', 'tem_permissao')),
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
select testes.def('sede', testes.ponto('empresa'));
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
