-- Apagar endereço: o cliente apaga o próprio (deletado_em), não o alheio, e tudo fica na auditoria.
begin;
\ir _helpers.psql
select plan(4);

select testes.def('ana', testes.cliente('Ana'));
select testes.def('bia', testes.cliente('Bia'));
select testes.def('casa', testes.ponto('residencial'));

select testes.entrar(testes.u('ana'));
set local role authenticated;
with x as (insert into enderecos_cliente (cliente_id, ponto_entrega_id, nome)
           values (testes.u('ana'), testes.u('casa'), 'Casa') returning id)
  select testes.def('end', id) from x;
update enderecos_cliente set deletado_em = now() where id = testes.u('end');   -- apagar = update de deletado_em
reset role; select testes.sair();

select cmp_ok((select count(*)::int from auditoria where ref_tipo = 'enderecos_cliente'
                 and ref_id = testes.u('end') and acao = 'enderecos_cliente_criada'), '>=', 1,
              'criar um endereço fica na auditoria');
select cmp_ok((select count(*)::int from auditoria where ref_tipo = 'enderecos_cliente'
                 and ref_id = testes.u('end') and acao = 'enderecos_cliente_alterada'), '>=', 1,
              'apagar um endereço fica na auditoria');
select is((select count(*)::int from enderecos_cliente where id = testes.u('end') and deletado_em is null), 0,
          'o endereço apagado sai da lista do cliente');

-- Outro cliente NÃO apaga o endereço alheio (RLS filtra o update)
with y as (insert into enderecos_cliente (cliente_id, ponto_entrega_id, nome)
           values (testes.u('ana'), testes.u('casa'), 'Outra') returning id)
  select testes.def('end2', id) from y;
select testes.entrar(testes.u('bia'));
set local role authenticated;
update enderecos_cliente set deletado_em = now() where id = testes.u('end2');   -- 0 linhas: não é dela
reset role; select testes.sair();
select is((select deletado_em from enderecos_cliente where id = testes.u('end2')), null,
          'um cliente não apaga o endereço de outro');

select * from finish();
rollback;
