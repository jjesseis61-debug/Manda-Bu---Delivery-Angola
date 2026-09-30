-- Estrutura de I1: interruptores, parâmetros, Cozinha da Alexandra, cozinha_id,
-- registo de cliente, auditoria imutável e RLS activo.
begin;
\ir _helpers.psql
select plan(19);

-- Interruptores: existem os 10 e estão todos desligados
select is((select count(*)::int from funcionalidades), 10, 'existem 10 interruptores');
select is((select count(*)::int from funcionalidades where activa), 0, 'todos os interruptores desligados');

-- Parâmetros iniciais
select results_eq(
  $$select ganho_por_pedido, duracao_dias, desconto_indicado, limite_verificacao_semanal,
           levantamento_minimo, limite_parcelamento, max_descontos_por_local, max_indicados_por_local
      from parametros$$,
  $$values (100, 60, 500, 10000, 2000, 20000, 3, 3)$$,
  'parâmetros com os valores iniciais');

-- Cozinha da Alexandra, sem consentimento público até decisão (16.1)
select results_eq(
  $$select nome, estado, consentimento_publico from cozinhas$$,
  $$values ('Cozinha da Alexandra'::text, 'activa'::text, false)$$,
  'Cozinha da Alexandra criada, activa e sem perfil público');

-- cozinha_id obrigatório nas tabelas operacionais
select col_not_null('pratos_base', 'cozinha_id', 'pratos_base.cozinha_id not null');
select col_not_null('turnos', 'cozinha_id', 'turnos.cozinha_id not null');
select col_not_null('caixa', 'cozinha_id', 'caixa.cozinha_id not null');
select col_not_null('estoque_diario', 'cozinha_id', 'estoque_diario.cozinha_id not null');
select col_not_null('estoque_longo_prazo', 'cozinha_id', 'estoque_longo_prazo.cozinha_id not null');
select col_not_null('vendas', 'cozinha_id', 'vendas.cozinha_id not null');
select col_not_null('pedidos', 'cozinha_id', 'pedidos.cozinha_id not null');

-- Linha nova sem cozinha fica na Cozinha da Alexandra
insert into turnos (data, hora_inicio, hora_fim) values (current_date, '08:00', '14:00');
select is((select c.nome from turnos t join cozinhas c on c.id = t.cozinha_id limit 1),
          'Cozinha da Alexandra', 'cozinha_id por defeito = Cozinha da Alexandra');

-- Registo de cliente: código MB-dddd e pseudónimo sem dados pessoais
select testes.def('joana', testes.cliente('Joana Kiala', 'Particular', '923456789'));
select matches(testes.codigo(testes.u('joana')), '^MB-[0-9]{4}$', 'código no formato MB- + 4 dígitos');
select ok((select pseudonimo !~* '(joana|kiala|923456789)'
             from perfil_destaques where cliente_id = testes.u('joana')),
          'pseudónimo não deriva do nome nem do telefone');
select is((select mostrar_nome_real or sair_da_lista from perfil_destaques where cliente_id = testes.u('joana')),
          false, 'privacidade por defeito');

-- Auditoria é append-only
select registar_auditoria('teste', 'clientes', testes.u('joana'));
select throws_ok($$update auditoria set acao = 'x'$$, '42501', 'auditoria_imutavel',
                 'auditoria não aceita UPDATE');
select throws_ok($$delete from auditoria$$, '42501', 'auditoria_imutavel',
                 'auditoria não aceita DELETE');

-- RLS activo em todas as tabelas novas
select is(
  (select count(*)::int from pg_class
    where relname in ('parametros','funcionalidades','cozinhas','pontos_entrega','enderecos_cliente',
                      'pedidos','codigos_indicacao','ligacoes_indicacao','ganhos_indicacao',
                      'pagamentos_indicacao','perfil_destaques','preferencias_notificacao',
                      'avaliacoes','avaliacoes_pratos','fotos_avaliacao','palavras_filtradas',
                      'reconhecimentos_turno','pedidos_grupo','notificacoes_fila','contadores_zona')
      and relnamespace = 'public'::regnamespace and not relrowsecurity),
  0, 'RLS activo em todas as tabelas novas');

-- Alteração de interruptor fica na auditoria
select testes.funcionalidade('indicacao', true);
select ok(exists (select 1 from auditoria where acao = 'funcionalidades_alterados'),
          'mudança de interruptor auditada');

select * from finish();
rollback;
