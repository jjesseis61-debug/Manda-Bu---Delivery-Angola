-- Balcão de panelas com grupo de controlo: interruptor próprio, visitas separadas da experiência
-- das fotografias e resultado só da experiência pedida.
begin;
\ir _helpers.psql
select plan(9);

select testes.def('c1', testes.cliente('Teste balcão'));
select ok(exists (select 1 from funcionalidades where chave = 'teste_balcao_panelas' and not activa), 'interruptor criado e desligado');

-- Desligado: sem grupo nem registo (mesmo com o teste das fotografias ligado)
select testes.funcionalidade('teste_fotos_inicio', true);
select testes.entrar(testes.u('c1'));
set local role authenticated;
select testes.def('off', coalesce(visita_experiencia('balcao_panelas'), 'nulo'));
reset role;
select is(testes.v('off'), 'nulo', 'desligado: sem grupo');
select is((select count(*)::int from experiencia_visitas where experiencia = 'balcao_panelas'), 0, 'desligado: nada registado');

-- Ligado: devolve o grupo fixo do cliente, conta a visita e guarda o tempo
select testes.funcionalidade('teste_balcao_panelas', true);
set local role authenticated;
select testes.def('g', visita_experiencia('balcao_panelas'));
select visita_experiencia('balcao_panelas', 30);
select visita_experiencia('fotos_inicio');
reset role;
select is(testes.v('g'), variante_experiencia('balcao_panelas', testes.u('c1')), 'ligado: devolve o grupo do cliente');
select is((select visitas from experiencia_visitas where experiencia = 'balcao_panelas'), 1, 'uma visita ao Servir o prato');
select is((select segundos_ate_adicionar from experiencia_visitas where experiencia = 'balcao_panelas'), 30, 'tempo até Adicionar');
select is((select count(*)::int from experiencia_visitas where experiencia = 'fotos_inicio'), 1, 'as fotografias contam à parte');

-- Resultado só desta experiência e com o interruptor dela
select testes.def('ana', testes.funcionario('Ana Analista', array['analista.usar']));
select testes.entrar_funcionario(testes.u('ana'));
set local role authenticated;
select testes.def('res', resultado_experiencia('balcao_panelas', testes.hoje() - 1, testes.hoje() + 1)::text);
select testes.def('e_res', testes.erro($$select resultado_experiencia('outra', current_date, current_date)$$));
reset role;
select is(((testes.v('res')::jsonb #>> '{grupos,A,visitas}')::int + (testes.v('res')::jsonb #>> '{grupos,B,visitas}')::int), 1,
          'o resultado conta só as visitas ao balcão');
select ok(testes.v('e_res') like '22023:%', 'experiência desconhecida é recusada no resultado');

select * from finish();
rollback;
