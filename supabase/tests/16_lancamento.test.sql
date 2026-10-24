-- I4 · Lançamento aberto: C5 (esconder ganhos na lista), textos e envio de N5, N6 e N7
begin;
\ir _helpers.psql
select plan(16);

select testes.funcionalidade('indicacao', true);
select testes.funcionalidade('destaques', true);

-- ---------------------------------------------------------------------------
-- C5. "Não mostrar os meus ganhos"
-- ---------------------------------------------------------------------------
select testes.def('rita', testes.cliente('Rita Sousa'));
select testes.def('vera', testes.cliente('Vera Costa'));
select testes.ganhos(testes.u('rita'), 12, 1000);
select testes.ganhos(testes.u('vera'), 5, 100);

select is((select ocultar_ganhos from perfil_destaques where cliente_id = testes.u('rita')), false,
          'C5: ganhos visíveis por defeito');

select testes.entrar(testes.u('rita'));
set local role authenticated;
update perfil_destaques set ocultar_ganhos = true, atualizado_em = now() where cliente_id = cliente_actual();
select testes.def('e_outro', testes.erro(format(
  $$update perfil_destaques set ocultar_ganhos = true where cliente_id = %L$$, testes.v('vera'))));
select testes.def('rita_ve', (select row(valor_min, valor_max)::text from destaques_mes() where sou_eu));
reset role;
select testes.entrar(testes.u('vera'));
set local role authenticated;
select testes.def('vera_ve_rita', (select row(posicao, amigos, valor, valor_min, valor_max)::text from destaques_mes() where posicao = 1));
select testes.def('vera_ve_vera', (select row(valor_min, valor_max)::text from destaques_mes() where sou_eu));
select testes.def('vera_pseudo', (select pseudonimo from perfil_destaques where cliente_id = cliente_actual()));
reset role;
select testes.sair();

select is((select ocultar_ganhos from perfil_destaques where cliente_id = testes.u('rita')), true,
          'C5: o cliente esconde os seus ganhos pela app');
select is((select ocultar_ganhos from perfil_destaques where cliente_id = testes.u('vera')), false,
          'C5: não altera o perfil de outro cliente');
select is(testes.v('vera_ve_rita'), '(1,12,,,)', 'C5: os outros vêem a posição e os amigos, sem valores');
select is(testes.v('rita_ve'), '(10000,20000)', 'C5: o próprio continua a ver os seus valores');
select is(testes.v('vera_ve_vera'), '(0,10000)', 'quem não escondeu continua com o valor em intervalo');

-- ---------------------------------------------------------------------------
-- Textos N5, N6, N7
-- ---------------------------------------------------------------------------
select is((texto_notificacao('N5', '{"prato_do_dia": "Muamba de galinha"}')).corpo,
          'Hoje há Muamba de galinha. Basta um colega pedir com o teu código para ganhares 100 Kz.', 'N5 com o prato do dia');
select is((texto_notificacao('N5', '{"prato_do_dia": null}')).corpo,
          'Basta um colega pedir hoje com o teu código para ganhares 100 Kz.', 'N5 sem prato do dia');
select is((texto_notificacao('N6', '{"indicado_nome": "Ana"}')).corpo,
          'O período de Ana termina em 5 dias. Convida mais amigos para continuares a ganhar.', 'N6');
select is((texto_notificacao('N7', '{"nome_exibido": "Palanca Azul", "posicao": 12, "amigos_em_falta": 3, "tamanho_top": 10}')).corpo,
          'Palanca Azul, estás em 12.º lugar este mês. Faltam 3 amigos para entrares no top 10.', 'N7 (plural)');
select is((texto_notificacao('N7', '{"nome_exibido": "Palanca Azul", "posicao": 11, "amigos_em_falta": 1, "tamanho_top": 10}')).corpo,
          'Palanca Azul, estás em 11.º lugar este mês. Falta 1 amigo para entrares no top 10.', 'N7 (singular)');

-- ---------------------------------------------------------------------------
-- N5 com o prato do dia e envio
-- ---------------------------------------------------------------------------
insert into cardapio (nome, preco, do_dia) values ('Muamba de galinha', 3000, true);
select testes.entrar(testes.u('vera'));
select registar_partilha();
select testes.sair();
select job_n5_lembrete();
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N5' and cliente_id = testes.u('vera')),
          case when extract(isodow from hoje_luanda()) between 1 and 5
               then 'Hoje há Muamba de galinha. Basta um colega pedir com o teu código para ganhares 100 Kz.' end,
          'N5 enfileirada (dias úteis) com o prato do dia do cardápio');

insert into notificacoes_fila (cliente_id, codigo, dados) values
  (testes.u('rita'), 'N5', '{}'),
  (testes.u('rita'), 'N6', '{"indicado_nome": "Ana"}'),
  (testes.u('rita'), 'N7', '{"nome_exibido": "Rita", "posicao": 11, "amigos_em_falta": 1, "tamanho_top": 10}');
select is((select array_agg(codigo order by codigo) from notificacoes_pendentes(1000) where cliente_id = testes.u('rita')),
          array['N5', 'N6', 'N7'], 'N5, N6 e N7 seguem para envio');

update preferencias_notificacao set lembrete_almoco = false, destaques = false where cliente_id = testes.u('rita');
select is((select array_agg(codigo order by codigo) from notificacoes_pendentes(1000) where cliente_id = testes.u('rita')),
          array['N6'], 'N5 e N7 desligadas pelo cliente depois de enfileiradas não são enviadas');

update preferencias_notificacao set lembrete_almoco = true, destaques = true where cliente_id = testes.u('rita');
select testes.funcionalidade('destaques', false);
select is((select array_agg(codigo order by codigo) from notificacoes_pendentes(1000) where cliente_id = testes.u('rita')),
          array['N5', 'N6'], 'interruptor destaques desligado: N7 não é enviada');

select testes.sair();
select is((select count(*)::int from destaques_mes()), 0, 'destaques desligado: lista vazia');

select * from finish();
rollback;
