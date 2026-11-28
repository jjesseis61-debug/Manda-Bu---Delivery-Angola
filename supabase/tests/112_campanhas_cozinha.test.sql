-- Campanhas de cozinha: o gerente do cardápio põe os pratos DA SUA cozinha em promoção para
-- todos; não cria por zona, nem para outras cozinhas, nem com pratos de outra cozinha.
begin;
\ir _helpers.psql
select plan(11);
select testes.funcionalidade('campanhas', true);

select testes.def('k', cozinha_padrao());
with c as (insert into cozinhas (nome, responsavel) values ('Outra Cozinha', 'Bia') returning id) select testes.def('k2', id) from c;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Muamba K', 4000, testes.u('k')) returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Funge K2', 3000, testes.u('k2')) returning id) select testes.def('funge', id) from m;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Zona K', 'Própria', 1000, 'Fixo') returning id) select testes.def('z', id) from z;

select testes.def('gerente', testes.funcionario('Gerente K', array['cardapio.gerir']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gerente'), testes.u('k'));
select testes.def('chefe', testes.funcionario('Chefe', array['cozinhas.gerir']));

select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('c1', guardar_campanha(jsonb_build_object('nome', 'Muamba da semana', 'cozinha_id', testes.u('k'),
  'tipo', 'percentagem', 'valor', 20, 'cardapio_ids', jsonb_build_array(testes.u('muamba'))))::text);
select testes.def('e_zona', testes.erro(format($$select guardar_campanha(jsonb_build_object('nome', 'Zona', 'cozinha_id', %L,
  'zona_id', %L, 'tipo', 'percentagem', 'valor', 10))$$, testes.u('k'), testes.u('z'))));
select testes.def('e_outra', testes.erro(format($$select guardar_campanha(jsonb_build_object('nome', 'Outra', 'cozinha_id', %L,
  'tipo', 'percentagem', 'valor', 10))$$, testes.u('k2'))));
select testes.def('e_todas', testes.erro($$select guardar_campanha(jsonb_build_object('nome', 'Todas', 'tipo', 'percentagem', 'valor', 10))$$));
select testes.def('e_prato', testes.erro(format($$select guardar_campanha(jsonb_build_object('nome', 'Prato alheio', 'cozinha_id', %L,
  'tipo', 'preco', 'valor', 1000, 'cardapio_ids', jsonb_build_array(%L)))$$, testes.u('k'), testes.u('funge'))));
select testes.def('lista', (select count(*) from jsonb_array_elements(campanhas_lista()))::text);
select testes.def('editar', testes.erro(format($$select guardar_campanha(jsonb_build_object('id', %L, 'nome', 'Muamba 25', 'cozinha_id', %L,
  'tipo', 'percentagem', 'valor', 25, 'cardapio_ids', jsonb_build_array(%L)))$$, testes.v('c1'), testes.u('k'), testes.u('muamba'))));
reset role; select testes.sair();

select ok(exists (select 1 from campanhas where id = testes.v('c1')::uuid and cozinha_id = testes.u('k') and zona_id is null and condominio_id is null),
          'o gerente cria a campanha dos pratos da sua cozinha para todos');
select matches(testes.v('e_zona'), '^42501', 'o gerente não cria campanha por zona');
select matches(testes.v('e_outra'), '^42501', 'o gerente não cria campanha para outra cozinha');
select matches(testes.v('e_todas'), '^42501', 'o gerente não cria campanha para todas as cozinhas');
select matches(testes.v('e_prato'), 'prato_de_outra_cozinha', 'não aceita pratos de outra cozinha');
select is(testes.v('lista'), '1', 'o gerente vê a sua campanha na lista');
select is(testes.v('editar'), 'sem_erro', 'o gerente edita a sua campanha');
select is((select valor from campanhas where id = testes.v('c1')::uuid), 25, 'a edição ficou gravada');

-- Quem gere todas as cozinhas continua a poder tudo
select testes.entrar_funcionario(testes.u('chefe'));
set local role authenticated;
select testes.def('c2', testes.erro(format($$select guardar_campanha(jsonb_build_object('nome', 'Zona toda', 'zona_id', %L,
  'tipo', 'percentagem', 'valor', 10))$$, testes.u('z'))));
select testes.def('lista2', (select count(*) from jsonb_array_elements(campanhas_lista()))::text);
reset role; select testes.sair();
select is(testes.v('c2'), 'sem_erro', 'cozinhas.gerir cria por zona');
select is(testes.v('lista2'), '2', 'cozinhas.gerir vê todas as campanhas');

-- Outro gerente (de outra cozinha) não vê nem apaga
select testes.def('g2', testes.funcionario('Gerente K2', array['cardapio.gerir']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('g2'), testes.u('k2'));
select testes.entrar_funcionario(testes.u('g2'));
set local role authenticated;
select testes.def('e_apagar', testes.erro(format($$select apagar_campanha(%L)$$, testes.v('c1'))));
reset role; select testes.sair();
select matches(testes.v('e_apagar'), '^42501', 'gerente de outra cozinha não apaga a campanha');

select * from finish();
rollback;
