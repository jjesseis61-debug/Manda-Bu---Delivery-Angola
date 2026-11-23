-- Compromisso nos agendados: o estafeta regista «cliente ausente»; o cliente do grupo A confirma
-- «vou estar»; lembrete 1 h antes repete as palavras dele; resultado por grupo.
begin;
\ir _helpers.psql
select plan(10);

select testes.funcionalidade('compromisso_agendados', true);
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Zona CP', 'Própria', 700, 'Fixo') returning id)
  select testes.def('zona', id) from z;
select testes.def('cli', testes.cliente('Carla Compromisso'));
select testes.def('outro', testes.cliente('Outro Compromisso'));
select testes.def('casa', testes.ponto('residencial', -8.83, 13.24, testes.u('zona')));
update pontos_entrega set referencia = 'Casa da Carla' where id = testes.u('casa');
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('cli'), testes.u('casa'));

-- Pedido agendado para daqui a 1 h (escrito pelo servidor, como num ensaio)
select testes.def('ped', testes.pedido(testes.u('cli'), testes.u('casa')));
update pedidos set agendado_para = now() + interval '1 hour', estado = 'confirmado' where id = testes.u('ped');

-- O cliente confirma; outro cliente não confirma por ele
select testes.entrar(testes.u('cli'));
set local role authenticated;
select testes.def('grupo', meu_grupo_compromisso());
select confirmar_presenca(testes.u('ped'));
reset role;
select testes.entrar(testes.u('outro'));
set local role authenticated;
select testes.def('e_outro', testes.erro(format($$select confirmar_presenca(%L)$$, testes.v('ped'))));
reset role;
select ok(testes.v('grupo') in ('A', 'B'), 'o cliente tem grupo no teste');
select ok((select presenca_confirmada_em is not null from pedidos where id = testes.u('ped')), '«Sim, vou estar» fica registado');
select is(testes.v('e_outro'), 'P0001:pedido_nao_agendado', 'outro cliente não confirma por ele');

-- Lembrete 1 h antes, com as palavras do cliente; não repete
select is(job_lembrete_agendados(), 1, 'um lembrete para o pedido agendado');
select ok((select dados ->> 'corpo' from notificacoes_fila where dados ->> 'pedido_id' = testes.v('ped') and dados ->> 'tipo' = 'lembrete_agendado')
            like 'Disseste que estarias em Casa da Carla às %', 'o lembrete repete o compromisso');
select is(job_lembrete_agendados(), 0, 'o lembrete não se repete');

-- Estafeta: só regista ausência com o pedido em entrega
select testes.def('est', testes.funcionario('Edu Estafeta', array['entregas.registar']));
select testes.entrar_funcionario(testes.u('est'));
set local role authenticated;
select testes.def('e_cedo', testes.erro(format($$select registar_ausencia(%L)$$, testes.v('ped'))));
reset role;
update pedidos set estado = 'em_entrega' where id = testes.u('ped');
select testes.entrar_funcionario(testes.u('est'));
set local role authenticated;
select testes.def('n', registar_ausencia(testes.u('ped'), 'Portão fechado')::text);
reset role;
select is(testes.v('e_cedo'), 'P0001:estado_invalido', 'ausência só com o pedido em entrega');
select is(testes.v('n'), '1', 'ausência registada');

-- Resultado por grupo (analista)
select testes.def('an', testes.funcionario('Ana Analista', array['analista.usar']));
select testes.entrar_funcionario(testes.u('an'));
set local role authenticated;
select testes.def('res', resultado_compromisso(current_date - 1, current_date + 1)::text);
reset role;
select is((testes.v('res')::jsonb -> testes.v('grupo') ->> 'com_ausencia')::int, 1, 'o resultado conta a ausência no grupo do cliente');
select is((testes.v('res')::jsonb -> testes.v('grupo') ->> 'confirmados')::int, 1, 'e o compromisso');

select * from finish();
rollback;
