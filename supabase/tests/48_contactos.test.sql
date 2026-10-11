-- Contactos públicos: gerais (Parâmetros, só com plataforma.parametros, validados) e de cada cozinha (cozinhas.gerir,
-- validados); contactos() só com sessão, só os campos públicos, sem cozinhas inactivas nem sem contactos; o
-- assistente do atendimento conhece-os
begin;
\ir _helpers.psql
select plan(9);

select testes.def('admin', testes.funcionario('Paula Admin', array['plataforma.parametros']));
select testes.def('gestor', testes.funcionario('Gil Cozinhas', array['cozinhas.gerir']));
select testes.def('rui', testes.funcionario('Rui Estafeta', array['entregas.registar']));
select testes.def('ana', testes.cliente('Ana Sousa'));
with c as (insert into cozinhas (nome, responsavel, estado, consentimento_publico) values ('Cozinha do Kilamba', 'Rosa Mendes', 'activa', false) returning id)
select testes.def('kil', id) from c;
with c as (insert into cozinhas (nome, responsavel, estado) values ('Cozinha Fechada', 'Joana', 'inactiva') returning id)
select testes.def('fechada', id) from c;
with c as (insert into cozinhas (nome, responsavel, estado) values ('Cozinha Sem Contactos', 'Marta', 'activa') returning id)
select testes.def('sem', id) from c;

-- Contactos gerais
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select testes.def('e_rui', testes.erro($$select alterar_parametros('{"contacto_telefone": "923000000"}')$$));
reset role;
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('e_email', testes.erro($$select alterar_parametros('{"contacto_email": "sem-arroba"}')$$));
select testes.def('e_tel', testes.erro($$select alterar_parametros('{"contacto_telefone": "liga-me"}')$$));
select alterar_parametros(jsonb_build_object('contacto_telefone', '+244 923 000 000', 'contacto_whatsapp', '923000001',
                                             'contacto_email', 'ola@mandabue.ao', 'contacto_horario', 'Seg a Sáb, 8h às 20h',
                                             'contacto_morada', 'Rua da Missão, Luanda'));
reset role;
select testes.sair();
select ok(testes.v('e_rui') like '42501:%' and testes.v('e_email') like '23514:%' and testes.v('e_tel') like '23514:%',
          'só quem gere os parâmetros muda os contactos gerais; email ou telefone inválidos são recusados');

-- Contactos das cozinhas
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
update cozinhas set telefone_publico = '923111222', whatsapp_publico = '+244923111222', horario_publico = 'Todos os dias, 10h às 22h'
 where id = testes.u('kil');
update cozinhas set telefone_publico = '923999888' where id = testes.u('fechada');
select testes.def('e_coz', testes.erro(format($$update cozinhas set telefone_publico = 'abc' where id = %L$$, testes.v('kil'))));
reset role;
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
update cozinhas set telefone_publico = '900000000' where id = testes.u('kil');
reset role;
select testes.sair();
select ok(testes.v('e_coz') like '23514:%' and (select telefone_publico from cozinhas where id = testes.u('kil')) = '923111222',
          'quem gere as cozinhas muda os contactos da cozinha (validados); os outros não');

-- O que o cliente vê
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('c', contactos());
reset role;
select testes.sair();
create function pg_temp.coz(p text) returns jsonb language sql as $$
  select e from jsonb_array_elements(testes.v('c')::jsonb -> 'cozinhas') e where e ->> 'id' = testes.v(p);
$$;
select is(testes.v('c')::jsonb -> 'geral',
          jsonb_build_object('telefone', '+244 923 000 000', 'whatsapp', '923000001', 'email', 'ola@mandabue.ao',
                             'horario', 'Seg a Sáb, 8h às 20h', 'morada', 'Rua da Missão, Luanda'),
          'o cliente vê os contactos gerais');
select ok(pg_temp.coz('kil') ->> 'telefone' = '923111222' and pg_temp.coz('kil') ->> 'whatsapp' = '+244923111222'
          and pg_temp.coz('kil') ->> 'horario' = 'Todos os dias, 10h às 22h' and pg_temp.coz('kil') ->> 'nome' = 'Cozinha do Kilamba',
          'e os da cozinha, mesmo sem o perfil público autorizado');
select ok(pg_temp.coz('fechada') is null and pg_temp.coz('sem') is null,
          'cozinhas inactivas ou sem contactos não aparecem');
select ok(testes.v('c') not like '%Rosa%' and testes.v('c') not like '%responsavel%',
          'só os campos públicos (sem o nome da responsável)');

select ok(not has_function_privilege('anon', 'contactos()', 'execute') and has_function_privilege('authenticated', 'contactos()', 'execute'),
          'sem sessão não se lê (como as outras funções do servidor)');
select ok(atd_informacoes() -> 'contactos' -> 'geral' ->> 'email' = 'ola@mandabue.ao',
          'o assistente do atendimento conhece os contactos');

-- Limpar um contacto
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select alterar_parametros('{"contacto_morada": null}');
reset role;
select testes.sair();
select ok((select contacto_morada is null and contacto_email = 'ola@mandabue.ao' from parametros where unico),
          'um contacto apaga-se sem mexer nos outros');

select * from finish();
rollback;
