-- Fotos dos pratos: bucket público; só cozinhas.gerir envia, troca ou apaga, em caminhos válidos
begin;
\ir _helpers.psql
select plan(9);

with m as (insert into cardapio (nome, preco) values ('Muamba', 2500) returning id) select testes.def('prato', id) from m;
select testes.def('chefe', testes.funcionario('Chefe', array['cozinhas.gerir']));
select testes.def('caixa_f', testes.funcionario('Caixa', array['vendas.registar']));
select testes.def('ana', testes.cliente('Ana Sousa'));

select is((select public::text || ':' || file_size_limit from storage.buckets where id = 'fotos-pratos'), 'true:5242880',
          'bucket fotos-pratos é público, até 5 MB');

select testes.entrar_funcionario(testes.u('chefe'));
set local role authenticated;
select testes.def('ok', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('fotos-pratos', 'pratos/%s/foto-1.jpg')$$, testes.v('prato'))));
select testes.def('ok_cozinha', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('fotos-pratos', 'cozinhas/%s/capa.jpg')$$, cozinha_padrao())));
select testes.def('e_prato', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('fotos-pratos', 'pratos/%s/foto.jpg')$$, gen_random_uuid())));
select testes.def('e_pasta', testes.erro($$insert into storage.objects (bucket_id, name) values ('fotos-pratos', 'outra/coisa.jpg')$$));
select testes.def('e_ext', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('fotos-pratos', 'pratos/%s/script.exe')$$, testes.v('prato'))));
with d as (delete from storage.objects where bucket_id = 'fotos-pratos' and name like 'cozinhas/%' returning 1)
select testes.def('apagou', (select count(*) from d));
reset role;
select is(testes.v('ok'), 'sem_erro', 'cozinhas.gerir envia a foto de um prato');
select is(testes.v('ok_cozinha'), 'sem_erro', 'cozinhas.gerir envia a foto de uma cozinha');
select ok(testes.v('e_prato') like '42501:%' and testes.v('e_pasta') like '42501:%' and testes.v('e_ext') like '42501:%',
          'prato inexistente, pasta errada ou extensão errada: recusado');
select is(testes.v('apagou')::int, 1, 'cozinhas.gerir apaga uma foto');

select testes.entrar_funcionario(testes.u('caixa_f'));
set local role authenticated;
select testes.def('e_caixa', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('fotos-pratos', 'pratos/%s/foto-2.jpg')$$, testes.v('prato'))));
with d as (delete from storage.objects where bucket_id = 'fotos-pratos' returning 1) select testes.def('caixa_apagou', (select count(*) from d));
reset role;
select ok(testes.v('e_caixa') like '42501:%', 'sem cozinhas.gerir não envia fotos');
select is(testes.v('caixa_apagou')::int, 0, 'sem cozinhas.gerir não apaga fotos');

select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_cliente', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('fotos-pratos', 'pratos/%s/foto-3.jpg')$$, testes.v('prato'))));
select testes.def('cliente_ve', (select count(*) from storage.objects where bucket_id = 'fotos-pratos'));
reset role;
select ok(testes.v('e_cliente') like '42501:%', 'o cliente não envia fotos');
select is(testes.v('cliente_ve')::int, 1, 'o cliente vê as fotos dos pratos');

select * from finish();
rollback;
