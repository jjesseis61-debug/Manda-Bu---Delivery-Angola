-- Reconquista de clientes inativos: escalões por recência, resumo, campanha com grupo de controlo,
-- exclusão de recém-contactados, enfileiramento N31 só aos alcançáveis, medição e barreira de permissão.
begin;
\ir _helpers.psql
select plan(15);

select testes.def('cz', cozinha_padrao());
with z as (insert into zonas (nome, tipo, taxa) values ('Zona T', 'Própria', 500) returning id)
  select testes.def('zona', id) from z;
select testes.def('ponto', testes.ponto('residencial', null, null, testes.u('zona')));

select testes.def('gestor', testes.funcionario('Gestor Clientes', array['clientes.reconquista']));
select testes.def('semperm', testes.funcionario('Sem Permissão', array['entregas.registar']));

-- Clientes com última compra em recências diferentes
select testes.def('a', testes.cliente('Cli A'));   -- 45 dias: a arrefecer
select testes.def('b', testes.cliente('Cli B'));   -- 75 dias: frio
select testes.def('c', testes.cliente('Cli C'));   -- 120 dias: adormecido
select testes.def('f', testes.cliente('Cli F'));   -- 100 dias: adormecido (2.º, para o controlo 50%)
select testes.def('d', testes.cliente('Cli D'));   -- 10 dias: activo
select testes.def('e', testes.cliente('Cli E'));   -- nunca comprou

-- Compra entregue e paga, recuada p_dias (o entregue_em fora do contexto cliente é editável)
create function pg_temp.comprou(p_cli text, p_dias int) returns void language plpgsql as $$
declare pid uuid;
begin
  insert into pedidos (cliente_id, ponto_entrega_id, zona_id, cozinha_id, subtotal, itens)
  values (testes.u(p_cli), testes.u('ponto'), testes.u('zona'), testes.u('cz'), 3000,
          jsonb_build_array(jsonb_build_object('nome', 'Calulu', 'qtd', 1, 'preco_unitario', 3000)))
  returning id into pid;
  perform testes.pagar(pid);
  update pedidos set entregue_em = now() - make_interval(days => p_dias) where id = pid;
end $$;

select pg_temp.comprou('a', 45);
select pg_temp.comprou('b', 75);
select pg_temp.comprou('c', 120);
select pg_temp.comprou('f', 100);
select pg_temp.comprou('d', 10);
-- Cli A tem app com push activo; Cli C não (fica só para telefonar)
insert into dispositivos_push (cliente_id, token, plataforma, activo) values (testes.u('a'), 'tok-a', 'android', true);

-- ---- Leituras (como gestor com a permissão) ----
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('n30',   (select count(*)::int from clientes_inativos(30)));
select testes.def('arref', (select string_agg(nome, ',' order by nome) from clientes_inativos(30, 59)));
select testes.def('push_a',(select tem_push::text from clientes_inativos(30, 59) limit 1));
select testes.def('ador',  (select string_agg(nome, ',' order by nome) from clientes_inativos(90)));
select testes.def('res',   clientes_inativos_resumo()::text);
reset role;
select testes.sair();

select is(testes.v('n30')::int, 4, 'inativos (>=30 dias): A, B, C e F — não o D (activo) nem o E (nunca comprou)');
select is(testes.v('arref'), 'Cli A', 'escalão a arrefecer (30-59): só o Cli A');
select is(testes.v('push_a'), 'true', 'o Cli A conta como alcançável por push');
select is(testes.v('ador'), 'Cli C,Cli F', 'escalão adormecido (90+): Cli C e Cli F');
select is((testes.v('res')::jsonb -> 'a_arrefecer' ->> 'total')::int, 1, 'resumo: 1 a arrefecer');
select is((testes.v('res')::jsonb -> 'frio' ->> 'total')::int, 1, 'resumo: 1 frio');
select is((testes.v('res')::jsonb -> 'adormecido' ->> 'total')::int, 2, 'resumo: 2 adormecidos');
select is((testes.v('res')::jsonb ->> 'activos_ate_30')::int, 1, 'resumo: 1 activo (<30 dias)');

-- ---- Campanha SEND: a arrefecer, 0% controlo ----
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('env', enviar_campanha_reconquista(30, 59, null, 'Voltámos!', 'O teu Calulu espera-te.', null, 0)::text);
reset role;
select testes.sair();
select is((testes.v('env')::jsonb ->> 'enviados')::int, 1, 'campanha envia ao Cli A');
select is((testes.v('env')::jsonb ->> 'enviados_push')::int, 1, 'enfileira N31 só ao alcançável (Cli A tem push)');
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('a') and codigo = 'N31'), 1,
          'o Cli A recebe uma notificação N31 na fila');

-- ---- Campanha repetida (exclusão de recém-contactados) ----
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('env2', enviar_campanha_reconquista(30, 59, null, 'Outra', 'Outra vez', null, 0)::text);
-- ---- Campanha CTRL: adormecido (Cli C e F), 50% controlo -> 1 controlo, 1 enviado ----
select testes.def('env3', enviar_campanha_reconquista(90, null, null, 'Ctrl', 'Volta ao sabor de casa.', null, 50)::text);
reset role;
select testes.sair();
select is((testes.v('env2')::jsonb ->> 'elegiveis')::int, 0, 'quem foi contactado há pouco não entra na campanha seguinte');
select is((testes.v('env3')::jsonb ->> 'controlo')::int, 1, 'com 50% de controlo e 2 alvos, 1 fica no controlo (e 1 recebe)');

-- ---- Medição: o Cli A volta a comprar dentro da janela ----
select pg_temp.comprou('a', 0);
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('res_send', campanha_reconquista_resultado((testes.v('env')::jsonb ->> 'campanha_id')::uuid)::text);
reset role;
select testes.sair();
select is((testes.v('res_send')::jsonb ->> 'enviados_voltaram')::int, 1, 'o resultado conta o Cli A como regressado');

-- ---- Barreira de permissão ----
select testes.entrar_funcionario(testes.u('semperm'));
set local role authenticated;
select testes.def('e_perm', testes.erro($$select clientes_inativos(30)$$));
reset role;
select testes.sair();
select matches(testes.v('e_perm'), '^42501', 'sem clientes.reconquista não vê os inativos');

select * from finish();
rollback;
