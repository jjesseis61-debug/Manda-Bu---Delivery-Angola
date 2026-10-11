-- Conferência financeira: leitura automática dos comprovativos, extratos (lidos ou escritos à mão),
-- conciliação, fecho diário e mensal, histórico do pedido
begin;
\ir _helpers.psql
select plan(27);

select testes.funcionalidade('multi_cozinha', false);
select testes.def('cz', cozinha_padrao());
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir', 'vendas.registar']));
select testes.def('estafeta', testes.funcionario('Estafeta Rui', array['entregas.registar']));
select testes.def('estafeta2', testes.funcionario('Estafeta Zé', array['entregas.registar']));
select testes.def('financas', testes.funcionario('Contabilista', array['financas.conferir']));
select testes.def('outro', testes.funcionario('Sem finanças', array['indicacoes.ver']));
insert into turnos (data, funcionario_id, cozinha_id) values (testes.hoje(), testes.u('gerente'), testes.u('cz')),
                                                           (testes.hoje(), testes.u('estafeta'), testes.u('cz'));
select testes.def('cx', testes.caixa(testes.u('cz'), 'Balcão de teste'));
select testes.def('ana', testes.cliente('Ana Sousa'));

-- Três entregas pagas por via electrónica (3 000 Kz cada), registadas pelo estafeta Rui
create temp table ped as
select n, testes.pedido(testes.u('ana'), testes.ponto('residencial')) as id,
       (array['Multicaixa Express', 'Multicaixa Express', 'Unitel Money'])[n] as metodo,
       (array['MCX-1001', 'MCX-1002', 'UM-2001'])[n] as ref
  from generate_series(1, 3) n;
grant select on ped to authenticated;
update pedidos set estado = 'em_preparacao' where id in (select id from ped);
insert into storage.objects (bucket_id, name) select 'comprovativos', id || '/talao.jpg' from ped;
select testes.def('p' || n, id) from ped;
select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select mudar_estado_pedido(id, 'em_entrega', null, null, null) from ped order by n;
select mudar_estado_pedido(id, 'entregue_pago', null, testes.u('cx'),
         jsonb_build_array(jsonb_build_object('metodo', metodo, 'valor', 3000, 'referencia', ref, 'comprovativo', id || '/talao.jpg')))
  from ped order by n;
reset role;
select testes.def('k' || n, k.id) from ped join comprovativos_pagamento k on k.pedido_id = ped.id;

-- ---------------------------------------------------------------- leitura automática dos comprovativos
select is((select jsonb_array_length(reservar_documentos(10) -> 'comprovativos')), 3, 'os 3 comprovativos são reservados para a leitura automática');
select is((select jsonb_array_length(reservar_documentos(10) -> 'comprovativos')), 0, 'uma segunda execução não os lê outra vez');
select is(registar_leitura_comprovativo(testes.u('k1'), 'lido', 3000, 'mcx 1001', testes.hoje(), null), 'confere',
          'leitura com o mesmo valor e a mesma referência (escrita de outra maneira) -> confere');
select is(registar_leitura_comprovativo(testes.u('k2'), 'lido', 2500, 'MCX-1002', testes.hoje(), 'valor no talão: 2 500'), 'diverge',
          'valor lido diferente do registado -> diverge');
select is(array[registar_leitura_comprovativo(testes.u('k3'), 'erro', null, null, null, 'limite de pedidos'),
                registar_leitura_comprovativo(testes.u('k3'), 'erro', null, null, null, 'limite de pedidos'),
                registar_leitura_comprovativo(testes.u('k3'), 'erro', null, null, null, 'limite de pedidos')],
          array['pendente', 'pendente', 'indisponivel'], 'falha da leitura: tenta 3 vezes e fica indisponível (conferência humana)');
select ok(not has_function_privilege('authenticated', 'registar_leitura_comprovativo(uuid, text, numeric, text, date, text)', 'execute')
          and not has_function_privilege('authenticated', 'reservar_documentos(int)', 'execute')
          and has_function_privilege('service_role', 'registar_leitura_extrato(uuid, text, jsonb, text)', 'execute'),
          'só o serviço (Edge Function) regista leituras automáticas');
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select pedir_nova_leitura('comprovativo', testes.u('k3'));
select testes.def('res', resumo_caixa(testes.u('cx')));
reset role;
select is((select ia_estado from comprovativos_pagamento where id = testes.u('k3')), 'pendente', 'o gerente pede outra leitura');
select ok((select bool_or(e ->> 'ia_estado' = 'diverge') from jsonb_array_elements(testes.v('res')::jsonb -> 'comprovativos') e),
          'o resumo da caixa mostra o resultado da leitura automática');

-- ---------------------------------------------------------------- extrato
select testes.entrar_funcionario(testes.u('outro'));
set local role authenticated;
select testes.def('e_sem_perm', testes.erro($$select criar_extrato('BAI', testes.hoje(), testes.hoje())$$));
reset role;
select testes.entrar_funcionario(testes.u('financas'));
set local role authenticated;
select testes.def('ext', criar_extrato('Multicaixa Express (BAI)', testes.hoje() - 1, testes.hoje() + 1));
select testes.def('e_periodo', testes.erro($$select criar_extrato('BAI', testes.hoje(), testes.hoje() - 5)$$));
select testes.def('up_ok', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('extratos', '%s/extrato.pdf')$$, testes.v('ext'))));
select confirmar_extrato(testes.u('ext'), testes.v('ext') || '/extrato.pdf');
select testes.def('up_depois', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('extratos', '%s/outro.pdf')$$, testes.v('ext'))));
reset role;
select testes.entrar_funcionario(testes.u('outro'));
set local role authenticated;
select testes.def('up_outro', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('extratos', '%s/x.pdf')$$, testes.v('ext'))));
reset role;
select ok(testes.v('e_sem_perm') like '42501:%' and testes.v('up_outro') like '42501:%', 'sem financas.conferir não carrega extratos');
select is(testes.v('e_periodo'), 'P0001:periodo_invalido', 'período do extrato tem de fazer sentido');
select ok(testes.v('up_ok') = 'sem_erro' and testes.v('up_depois') like '42501:%', 'o ficheiro envia-se uma vez, enquanto o extrato o espera');
select is((select estado || '/' || tipo_ficheiro from extratos where id = testes.u('ext')), 'por_ler/pdf', 'extrato fica à espera da leitura automática');
select is((select jsonb_array_length(reservar_documentos(5) -> 'extratos')), 1, 'o extrato é reservado para a leitura');

-- leitura automática do extrato: 3 entradas
select is(registar_leitura_extrato(testes.u('ext'), 'lido', jsonb_build_array(
            jsonb_build_object('data', testes.hoje(), 'valor', 3000, 'referencia', 'MCX 1001', 'descricao', 'Pagamento MCX'),
            jsonb_build_object('data', testes.hoje(), 'valor', 3000, 'referencia', null, 'descricao', 'Transferência recebida'),
            jsonb_build_object('data', testes.hoje(), 'valor', 7777, 'referencia', 'XYZ-9', 'descricao', 'Depósito'))), 3,
          'a leitura do extrato regista as entradas');
select is((select comprovativo_id from extrato_movimentos where extrato_id = testes.u('ext') and valor = 3000 and referencia = 'MCX 1001'),
          testes.u('k1'), 'entrada ligada ao comprovativo pela referência');
select is((select comprovativo_id from extrato_movimentos where extrato_id = testes.u('ext') and valor = 3000 and referencia is null),
          testes.u('k2'), 'entrada sem referência ligada pelo valor e pelo dia');

select testes.entrar_funcionario(testes.u('financas'));
set local role authenticated;
select testes.def('conc', relatorio_conciliacao(testes.hoje() - 1, testes.hoje() + 1));
reset role;
select ok(jsonb_array_length(testes.v('conc')::jsonb -> 'encontrados') = 2
          and jsonb_array_length(testes.v('conc')::jsonb -> 'comprovativos_sem_extrato') = 1
          and testes.v('conc')::jsonb -> 'comprovativos_sem_extrato' -> 0 ->> 'referencia' = 'UM-2001'
          and testes.v('conc')::jsonb -> 'comprovativos_sem_extrato' -> 0 ->> 'registado_por' = 'Estafeta Rui'
          and jsonb_array_length(testes.v('conc')::jsonb -> 'movimentos_sem_comprovativo') = 1
          and (testes.v('conc')::jsonb -> 'movimentos_sem_comprovativo' -> 0 ->> 'valor')::numeric = 7777,
          'conciliação: 2 encontrados, 1 comprovativo sem extrato (com quem o registou), 1 entrada sem comprovativo');

-- conferência à mão (quando a leitura automática não está disponível)
select testes.entrar_funcionario(testes.u('financas'));
set local role authenticated;
select testes.def('mov_manual', registar_movimento_extrato(testes.u('ext'), testes.hoje(), 3000, 'UM 2001', 'Unitel Money'));
select testes.def('e_ligado', testes.erro(format($$select ligar_movimento(%L, %L)$$,
  (select id from extrato_movimentos where valor = 7777), testes.v('k1'))));
select testes.def('e_motivo', testes.erro(format($$select apagar_movimento_extrato(%L, ' ')$$, (select id from extrato_movimentos where valor = 7777))));
select apagar_movimento_extrato((select id from extrato_movimentos where valor = 7777), 'Depósito do dono, não é venda');
select testes.def('conc2', relatorio_conciliacao(testes.hoje() - 1, testes.hoje() + 1));
reset role;
select is((select comprovativo_id from extrato_movimentos where id = testes.u('mov_manual')), testes.u('k3'),
          'entrada escrita à mão também é ligada ao comprovativo');
select ok(testes.v('e_ligado') like 'P0001:comprovativo_ja_ligado%' and testes.v('e_motivo') like 'P0001:motivo_obrigatorio%',
          'um comprovativo só se liga a uma entrada; apagar uma entrada exige motivo');
select ok(jsonb_array_length(testes.v('conc2')::jsonb -> 'comprovativos_sem_extrato') = 0
          and jsonb_array_length(testes.v('conc2')::jsonb -> 'movimentos_sem_comprovativo') = 0
          and (testes.v('conc2')::jsonb -> 'totais' ->> 'encontrados')::numeric = 9000,
          'depois da conferência à mão tudo bate (9 000 Kz)');
select ok(exists (select 1 from auditoria where acao = 'extrato_movimento_manual' and funcionario_nome = 'Contabilista')
          and exists (select 1 from auditoria where acao = 'extrato_movimento_apagado' and detalhe like '%Depósito do dono%'),
          'entradas à mão e apagadas ficam na auditoria com quem e porquê');

-- ---------------------------------------------------------------- fechos
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('dia_gerente', testes.erro(format($$select fecho_diario(testes.hoje(), %L)$$, testes.v('cz'))));
select testes.def('dia_todas', testes.erro($$select fecho_diario(testes.hoje())$$));
select testes.def('mes_gerente', testes.erro($$select fecho_mensal(2026, 10)$$));
reset role;
select testes.entrar_funcionario(testes.u('financas'));
set local role authenticated;
select testes.def('dia', fecho_diario(testes.hoje()));
select testes.def('mes', fecho_mensal(extract(year from testes.hoje())::int, extract(month from testes.hoje())::int));
reset role;
select ok(testes.v('dia_gerente') = 'sem_erro' and testes.v('dia_todas') like '42501:%' and testes.v('mes_gerente') like '42501:%',
          'o gerente vê o fecho do dia da sua cozinha; o geral e o mensal são para financas.conferir');
select ok((testes.v('dia')::jsonb ->> 'electronico')::numeric = 9000 and (testes.v('dia')::jsonb ->> 'pedidos_entregues')::int = 3
          and exists (select 1 from jsonb_array_elements(testes.v('dia')::jsonb -> 'caixas') c where c ->> 'posto' = 'Balcão de teste')
          and exists (select 1 from jsonb_array_elements(testes.v('dia')::jsonb -> 'alertas') a where a ->> 'tipo' = 'ia_diverge' and a ->> 'quem' = 'Estafeta Rui')
          and exists (select 1 from jsonb_array_elements(testes.v('dia')::jsonb -> 'alertas') a where a ->> 'tipo' = 'caixa_aberta'),
          'fecho do dia: 3 entregas, 9 000 Kz electrónicos, avisos (leitura diverge, caixa por fechar)');
select ok((testes.v('mes')::jsonb -> 'totais' ->> 'electronico')::numeric = 9000
          and exists (select 1 from jsonb_array_elements(testes.v('mes')::jsonb -> 'por_funcionario') f
                       where f ->> 'nome' = 'Estafeta Rui' and (f ->> 'comprovativos')::int = 3 and (f ->> 'ia_alertas')::int = 1)
          and jsonb_array_length(testes.v('mes')::jsonb -> 'dias') >= 1,
          'fecho do mês: totais, conciliação e sinais por funcionário');

-- ---------------------------------------------------------------- histórico do pedido
select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select testes.def('hist', historico_pedido(testes.u('p1')));
reset role;
select testes.entrar_funcionario(testes.u('estafeta2'));
set local role authenticated;
select testes.def('e_hist', testes.erro(format($$select historico_pedido(%L)$$, testes.v('p1'))));
reset role;
select ok((select array_agg(e ->> 'acao' order by (e ->> 'em')::timestamptz) from jsonb_array_elements(testes.v('hist')::jsonb -> 'eventos') e)
            @> array['pedido_criado', 'pedido_estado', 'comprovativo_registado', 'extrato_automatica', 'comprovativo_lido']
          and testes.v('hist')::jsonb ->> 'entregador' = 'Estafeta Rui',
          'histórico: pedido, estados, comprovativo, leitura automática e ligação ao extrato, com quem fez cada passo');
select is((select e ->> 'quem' from jsonb_array_elements(testes.v('hist')::jsonb -> 'eventos') e where e ->> 'acao' = 'comprovativo_registado'),
          'Estafeta Rui', 'o comprovativo mostra quem o registou');
select ok(testes.v('e_hist') like '42501:%', 'outro estafeta não vê o histórico de um pedido que não levou');

select * from finish();
rollback;
