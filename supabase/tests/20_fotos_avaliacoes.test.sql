-- I7 · Fotos nas avaliações: envio para o bucket privado, leitura e moderação (O7)
begin;
\ir _helpers.psql
select plan(19);

select testes.def('alexandra', cozinha_padrao());
select testes.funcionalidade('avaliacoes', true);
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('bia', testes.cliente('Bia Lima'));
select testes.def('p_ana', testes.pedido(testes.u('ana'), testes.ponto('residencial')));
select testes.pagar(testes.u('p_ana'));
insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario) values (testes.u('p_ana'), testes.u('ana'), 5, 'Muito bom');
select testes.def('av', (select id from avaliacoes where pedido_id = testes.u('p_ana')));

-- Interruptor desligado: não se envia
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_desligado', testes.erro(format($$insert into fotos_avaliacao (avaliacao_id, caminho) values (%L, 'x')$$, testes.v('av'))));
reset role;
select is(testes.v('e_desligado') ~ '^42501', true, 'interruptor desligado: sem fotos');

select testes.funcionalidade('avaliacoes_fotos', true);
select testes.entrar(testes.u('ana'));
set local role authenticated;
with f as (insert into fotos_avaliacao (avaliacao_id, caminho) values (testes.u('av'), '../outro/ficheiro.png')
           returning id, caminho, estado)
select testes.def('f1', id), testes.def('c1', caminho), testes.def('e1', estado) from f;
select testes.def('up_ok', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('fotos-avaliacoes', %L)$$, testes.v('c1'))));
select testes.def('up_outro', testes.erro($$insert into storage.objects (bucket_id, name) values ('fotos-avaliacoes', 'qualquer.jpg')$$));
with f as (insert into fotos_avaliacao (avaliacao_id, caminho) values (testes.u('av'), 'x') returning caminho)
select testes.def('c2', caminho) from f;
select testes.def('e_terceira', testes.erro(format($$insert into fotos_avaliacao (avaliacao_id, caminho) values (%L, 'x')$$, testes.v('av'))));
select testes.def('ana_ve', (select count(*) from storage.objects where bucket_id = 'fotos-avaliacoes'));
reset role;

select is(testes.v('c1'), testes.v('f1') || '.jpg', 'o caminho do ficheiro é do servidor (<id>.jpg)');
select is(testes.v('e1'), 'pendente', 'foto nova fica pendente');
select is(testes.v('up_ok'), 'sem_erro', 'o autor envia o ficheiro da sua foto');
select matches(testes.v('up_outro'), '^42501', 'não se envia para outro caminho');
select is(testes.v('e_terceira'), 'P0001:limite_fotos', 'no máximo 2 fotos por avaliação');
select is(testes.v('ana_ve')::int, 1, 'o autor vê a sua foto pendente');

-- Outro cliente: não envia para a foto da Ana nem a vê enquanto pendente
select testes.entrar(testes.u('bia'));
set local role authenticated;
select testes.def('e_bia_up', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('fotos-avaliacoes', %L)$$, testes.v('c2'))));
select testes.def('bia_ve_pendente', (select count(*) from storage.objects where bucket_id = 'fotos-avaliacoes'));
select testes.def('bia_lista_pendente', (select fotos::text from lista_avaliacoes(testes.u('alexandra'))));
reset role;
select matches(testes.v('e_bia_up'), '^42501', 'outro cliente não envia ficheiros para a foto de outra pessoa');
select is(testes.v('bia_ve_pendente')::int, 0, 'foto pendente é privada');
select is(testes.v('bia_lista_pendente'), '{}', 'foto pendente não aparece na lista pública');

-- O7: fila de moderação (só fotos com ficheiro) e decisão
select testes.def('moderador', testes.funcionario('Moderadora', array['avaliacoes.moderar']));
select testes.entrar_funcionario(testes.u('moderador'));
set local role authenticated;
select testes.def('fila', (select string_agg(caminho || '|' || autor_nome, ',') from fotos_pendentes()));
select testes.def('mod_ve', (select count(*) from storage.objects where bucket_id = 'fotos-avaliacoes'));
reset role;
select is(testes.v('fila'), testes.v('c1') || '|Ana Sousa', 'O7: fila só com as fotos já enviadas, com o autor');
select is(testes.v('mod_ve')::int, 1, 'O7: o moderador vê o ficheiro pendente');
select lives_ok(format($$select moderar_foto(%L, 'aprovada')$$, testes.v('f1')), 'O7: aprovar');
select testes.entrar(testes.u('bia'));
select throws_ok(format($$select moderar_foto(%L, 'rejeitada')$$, testes.v('f1')), '42501', 'sem_permissao', 'cliente não modera fotos');
select is(testes.erro('select * from fotos_pendentes()'), '42501:sem_permissao', 'O7 exige avaliacoes.moderar');

-- Depois de aprovada: pública
set local role authenticated;
select testes.def('bia_ve', (select count(*) from storage.objects where bucket_id = 'fotos-avaliacoes'));
select testes.def('bia_lista', (select fotos::text from lista_avaliacoes(testes.u('alexandra'))));
reset role;
select is(testes.v('bia_ve')::int, 1, 'foto aprovada fica visível');
select is(testes.v('bia_lista'), '{' || testes.v('c1') || '}', 'foto aprovada aparece na lista pública');

-- Avaliação ocultada ou interruptor desligado: a foto deixa de se ver
update avaliacoes set oculta = true where id = testes.u('av');
set local role authenticated;
select testes.def('bia_ve_oculta', (select count(*) from storage.objects where bucket_id = 'fotos-avaliacoes'));
reset role;
select is(testes.v('bia_ve_oculta')::int, 0, 'avaliação ocultada: a foto deixa de estar visível');
select testes.sair();
select ok(exists (select 1 from auditoria where acao = 'foto_moderada' and ref_id = testes.u('f1')), 'moderação auditada');

select * from finish();
rollback;
