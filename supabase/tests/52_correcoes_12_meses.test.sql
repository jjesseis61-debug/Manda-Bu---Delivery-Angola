-- Correcções do teste de 12 meses: regras de acesso calculadas uma vez por consulta; retenção do relatório
-- da cozinha pelo último pedido; rejeições do investigador pela taxa; limpeza diária de notificações e auditoria
begin;
\ir _helpers.psql
select plan(10);

-- (a) Nenhuma regra de acesso chama as funções da sessão linha a linha (só dentro de "(SELECT …)")
select is((select string_agg(tablename || '.' || policyname, ', ')
             from pg_policies
            where schemaname in ('public', 'storage')
              and regexp_replace(coalesce(qual, '') || ' ' || coalesce(with_check, ''),
                                 '\(\s*SELECT\s+(auth\.)?[a-z_]+\((''[^'']*''(::text)?)?\)\s+AS\s+[a-z_]+\)', '', 'gi')
                  ~ '(^|[^a-z_.])(cliente_actual|e_funcionario|funcionario_actual|e_administrador)\(\)|auth\.uid\(\)|(^|[^a-z_])(tem_permissao|funcionalidade_activa)\(''[^'']*''(::text)?\)'),
          null, 'as regras de acesso calculam a sessão uma vez por consulta');

select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('bia', testes.cliente('Bia Neto'));
select testes.def('p_ana', testes.pedido(testes.u('ana')));
select testes.def('p_bia', testes.pedido(testes.u('bia')));
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('vistos', (select string_agg(id::text, ',') from pedidos));
reset role;
select testes.sair();
select is(testes.v('vistos'), testes.v('p_ana'), 'e continuam a deixar cada cliente ver só os seus pedidos');

-- (b) Retenção: a Ana pediu há 100 e há 40 dias; a Bia só há 100 dias
select testes.def('p_ana2', testes.pedido(testes.u('ana')));
select testes.pagar(testes.u('p_ana'));
select testes.pagar(testes.u('p_ana2'));
select testes.pagar(testes.u('p_bia'));
alter table pedidos disable trigger user;
update pedidos set entregue_em = now() - interval '100 days' where id in (testes.u('p_ana'), testes.u('p_bia'));
update pedidos set entregue_em = now() - interval '40 days' where id = testes.u('p_ana2');
alter table pedidos enable trigger user;
select testes.def('dono', testes.funcionario('Dono', array['relatorios.exportar']));
select testes.entrar_funcionario(testes.u('dono'));
set local role authenticated;
select testes.def('rel', relatorio_cozinha(cozinha_padrao(), current_date - 120, current_date));
reset role;
select testes.sair();
select is(testes.v('rel')::jsonb -> 'retencao', '{"30": 50.0, "60": 50.0, "90": 0.0}'::jsonb,
          'retenção: voltou a pedir aos 30 e 60 dias (1 de 2 clientes), não aos 90');
select is((testes.v('rel')::jsonb ->> 'clientes_novos')::int, 2, 'clientes novos no período');

-- (c) Investigador: rejeições toleradas até 2 % dos comprovativos
select testes.def('caixa', testes.caixa());
create function pg_temp.comprovativos(p_func text, p_total int, p_rejeitados int) returns void language sql as $$
  insert into comprovativos_pagamento (pedido_id, caixa_id, cozinha_id, metodo, valor, referencia, referencia_chave, caminho,
                                       registado_por, estado, ia_estado, nota)
  select testes.pedido(testes.u('ana')), testes.u('caixa'), cozinha_padrao(), 'Multicaixa Express', 3000,
         p_func || '-' || i, chave_referencia(p_func || '-' || i), 'x/1.jpg', testes.u(p_func),
         case when i <= p_rejeitados then 'rejeitado' else 'conferido' end, 'confere',
         case when i <= p_rejeitados then 'Talão de outro dia' end
    from generate_series(1, p_total) i;
$$;
select testes.def('muitos', testes.funcionario('Estafeta com muitos', array['entregas.registar']));
select testes.def('acima', testes.funcionario('Estafeta acima', array['entregas.registar']));
select testes.def('poucos', testes.funcionario('Estafeta com poucos', array['entregas.registar']));
select pg_temp.comprovativos('muitos', 100, 2);
select pg_temp.comprovativos('acima', 100, 5);
select pg_temp.comprovativos('poucos', 10, 1);
select is((sinais_financeiros(testes.u('muitos'), current_date - 1, current_date) ->> 'pontuacao')::int, 0,
          '2 rejeitados em 100 comprovativos (2 %) não pontuam');
select is((sinais_financeiros(testes.u('acima'), current_date - 1, current_date) ->> 'pontuacao')::int, 9,
          '5 em 100: pontuam os 3 acima dos 2 tolerados (3 × 3)');
select is((sinais_financeiros(testes.u('poucos'), current_date - 1, current_date) ->> 'pontuacao')::int, 3,
          'com poucos comprovativos nada é tolerado: 1 rejeitado em 10 pontua');

-- (d) Limpeza diária
insert into notificacoes_fila (cliente_id, codigo, dados, criado_em, enviada_em, deletado_em) values
  (testes.u('ana'), 'N16', '{"t": "velha enviada"}', now() - interval '100 days', now() - interval '100 days', null),
  (testes.u('ana'), 'N9', '{"t": "velha descartada"}', now() - interval '100 days', null, now() - interval '99 days'),
  (testes.u('ana'), 'N16', '{"t": "recente enviada"}', now() - interval '10 days', now() - interval '10 days', null),
  (testes.u('ana'), 'N3', '{"t": "velha por enviar"}', now() - interval '100 days', null, null);
insert into auditoria (acao, detalhe, criado_em, data) values
  ('teste_velha', '{}', now() - interval '400 days', now() - interval '400 days'),
  ('teste_recente', '{}', now() - interval '200 days', now() - interval '200 days');
select testes.def('e_apagar', testes.erro($$delete from auditoria where acao = 'teste_velha'$$));
select testes.def('e_recente', testes.erro($$select set_config('mb.limpeza', 'auditoria', true);
                                            delete from auditoria where acao = 'teste_recente'$$));
select set_config('mb.limpeza', '', true);
select testes.def('limpeza', limpar_dados());
select is((select string_agg(dados ->> 't', ', ' order by dados ->> 't') from notificacoes_fila where cliente_id = testes.u('ana')),
          'recente enviada, velha por enviar',
          'apaga as notificações enviadas ou descartadas há mais de 90 dias; as outras ficam');
select ok(not exists (select 1 from auditoria where acao = 'teste_velha')
          and exists (select 1 from auditoria where acao = 'teste_recente')
          and exists (select 1 from auditoria where acao = 'limpeza_dados'),
          'apaga a auditoria com mais de um ano e regista a limpeza');
select ok(testes.v('e_apagar') like '42501:auditoria_imutavel%' and testes.v('e_recente') like '42501:auditoria_imutavel%'
          and not has_function_privilege('authenticated', 'limpar_dados()', 'execute')
          and not has_function_privilege('anon', 'limpar_dados()', 'execute'),
          'fora da limpeza a auditoria continua imutável (e nunca com menos de um ano); as apps não chamam a limpeza');

select * from finish();
rollback;
