-- Receitas (R1): o público só vê as publicadas e com o interruptor ligado; escrever exige receitas.gerir.
begin;
\ir _helpers.psql
select plan(15);

select testes.def('editor', testes.funcionario('Editor Receitas', array['receitas.gerir']));
select testes.def('sem',    testes.funcionario('Sem Receitas', array[]::text[]));

-- 1) Interruptor e permissão existem (interruptor desligado por omissão)
select is((select activa from funcionalidades where chave = 'receitas'), false, 'o interruptor receitas nasce desligado');
select is((select count(*)::int from permissoes where chave = 'receitas.gerir'), 1, 'a permissão receitas.gerir existe');

-- Conteúdo de teste (inserido como superutilizador, ignora a RLS): 1 publicada + 1 rascunho
insert into receitas (titulo, resumo, corpo, estado, cozinha_id, publicado_em)
  values ('Calulu de peixe', 'Clássico angolano', 'Ingredientes e passos...', 'publicada', cozinha_padrao(), now());
insert into receitas (titulo, corpo, estado) values ('Muamba (rascunho)', 'por acabar', 'rascunho');

-- 2) Com o interruptor DESLIGADO, o cliente não vê nenhuma receita
select is((select count(*)::int from receitas_publicas()), 0, 'desligado: receitas_publicas não devolve nada');

-- Ligar o interruptor
select testes.funcionalidade('receitas', true);

-- 3) Ligado: só a publicada aparece, com o nome da cozinha do CTA
select is((select count(*)::int from receitas_publicas()), 1, 'ligado: só a receita publicada aparece');
select is((select titulo from receitas_publicas()), 'Calulu de peixe', 'a que aparece é a publicada');
select isnt((select cozinha_nome from receitas_publicas()), null, 'traz o nome da cozinha (CTA)');

-- 4) O detalhe devolve o corpo da publicada e nada para o rascunho
select is((select corpo from receita_publica((select id from receitas where titulo = 'Calulu de peixe'))),
          'Ingredientes e passos...', 'receita_publica devolve o corpo da publicada');
select is((select count(*)::int from receita_publica((select id from receitas where titulo = 'Muamba (rascunho)'))), 0,
          'receita_publica não devolve um rascunho');

-- 5) RLS de escrita: sem receitas.gerir não se cria; com a permissão cria-se
select testes.entrar_funcionario(testes.u('sem'));
set local role authenticated;
select throws_ok($$insert into receitas (titulo, corpo) values ('Intrusa', 'x')$$, '42501',
                 null, 'sem receitas.gerir não pode criar receitas');
reset role; select testes.sair();

select testes.entrar_funcionario(testes.u('editor'));
set local role authenticated;
select lives_ok($$insert into receitas (titulo, corpo) values ('Nova', 'corpo')$$, 'com receitas.gerir cria receitas');
reset role; select testes.sair();

-- R3: métricas (abrir -> pedir)
select receita_abriu((select id from receitas where titulo = 'Calulu de peixe'));
select receita_tocou_pedir((select id from receitas where titulo = 'Calulu de peixe'));
select is((select aberturas from receitas where titulo = 'Calulu de peixe'), 1, 'receita_abriu incrementa as aberturas');
select is((select toques_pedir from receitas where titulo = 'Calulu de peixe'), 1, 'receita_tocou_pedir incrementa os toques');

-- R3: aviso de nova receita (N31 com link) a clientes com dispositivo; exige receitas.gerir
select testes.def('cli', testes.cliente('Cliente Push'));
insert into dispositivos_push (cliente_id, token, plataforma) values (testes.u('cli'), 'tok-cli', 'android');
select testes.entrar_funcionario(testes.u('sem'));
set local role authenticated;
select throws_ok(format($$select avisar_nova_receita(%L)$$, (select id from receitas where titulo = 'Calulu de peixe')),
                 '42501', null, 'avisar_nova_receita exige receitas.gerir');
reset role; select testes.sair();
select testes.entrar_funcionario(testes.u('editor'));
set local role authenticated;
select testes.def('enviados', avisar_nova_receita((select id from receitas where titulo = 'Calulu de peixe'))::text);
reset role; select testes.sair();
select cmp_ok(testes.v('enviados')::int, '>=', 1, 'avisa pelo menos 1 cliente');
select is((select count(*)::int from notificacoes_fila where codigo = 'N31' and cliente_id = testes.u('cli')
             and dados ->> 'link' = '/receita/' || (select id from receitas where titulo = 'Calulu de peixe')::text), 1,
          'enfileira N31 com o link da receita');

select * from finish();
rollback;
