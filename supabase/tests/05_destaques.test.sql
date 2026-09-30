-- Secção 13 · Destaques e prova social (testes 26 a 30)
begin;
\ir _helpers.psql
select plan(16);

select testes.funcionalidade('indicacao', true);

-- Indicadores do mês (com telefones, para verificar que nunca aparecem)
select testes.cliente('Rita Sousa',  'Particular', '923100001') as rita \gset
select testes.cliente('Sérgio Lima', 'Particular', '923100002') as sergio \gset
select testes.cliente('Teresa Neto', 'Particular', '923100003') as teresa \gset
select testes.cliente('Ulisses Paz', 'Particular', '923100004') as ulisses \gset
select testes.cliente('Vera Costa',  'Particular', '923100005') as vera \gset
select testes.ganhos(:'rita', 12, 1000);     -- 12 amigos, 12.000 Kz
select testes.ganhos(:'sergio', 3, 500);     -- 3 amigos
select testes.ganhos(:'teresa', 1, 100);
select testes.ganhos(:'ulisses', 1, 100);
select testes.ganhos(:'vera', 5, 100);

-- Interruptor desligado: a lista não é devolvida
select is((select count(*)::int from destaques_mes()), 0, 'destaques desligado -> lista vazia');
select testes.funcionalidade('destaques', true);
select testes.funcionalidade('pessoas_como_tu', true);
select testes.funcionalidade('contadores_zona', true);

-- 26. Cliente com sair_da_lista -> não aparece
update perfil_destaques set sair_da_lista = true where cliente_id = :'ulisses';
select is((select count(*)::int from destaques_mes()), 4, '26. lista com 4 participantes');
select is((select count(*)::int from destaques_mes() d, perfil_destaques p
            where p.cliente_id = :'ulisses' and d.nome_exibido = p.pseudonimo), 0,
          '26. cliente com sair_da_lista não aparece em destaques_mes()');

-- Nome exibido: pseudónimo por defeito, primeiro nome só se o cliente escolher
update perfil_destaques set mostrar_nome_real = true where cliente_id = :'rita';
select results_eq($$select posicao, nome_exibido, amigos from destaques_mes() where posicao = 1$$,
                  $$values (1, 'Rita'::text, 12)$$, 'primeiro nome só com mostrar_nome_real');
select is((select nome_exibido from destaques_mes() where posicao = 2),
          (select pseudonimo from perfil_destaques where cliente_id = :'vera'),
          'pseudónimo por defeito');

-- 27. Menos de 20 participantes -> valores em intervalos
select results_eq($$select valor, valor_min, valor_max from destaques_mes() where posicao = 1$$,
                  $$values (null::int, 10000, 20000)$$,
                  '27. menos de 20 participantes -> valor em intervalo de 10.000 Kz');
select is((select count(*)::int from destaques_mes() where valor is not null), 0,
          '27. nenhum valor exacto com menos de 20 participantes');
update parametros set limiar_intervalos = 3;
select results_eq($$select valor, valor_min from destaques_mes() where posicao = 1$$,
                  $$values (12000, null::int)$$, 'acima do limiar -> valor exacto');
update parametros set limiar_intervalos = 20;

-- 28. destaques_mes() nunca devolve ids nem telefones
select is((select count(*)::int
             from information_schema.parameters
            where specific_name like 'destaques\_mes\_%' and parameter_mode = 'OUT'
              and (parameter_name ~* 'id$|^id|telefone|phone')), 0,
          '28. destaques_mes() não tem colunas de ids nem de telefones');
select is((select count(*)::int from destaques_mes() d, clientes c
            where d::text like '%' || c.id::text || '%'
               or (c.telefone is not null and d::text like '%' || c.telefone || '%')), 0,
          '28. nenhum valor devolvido contém ids ou telefones de clientes');

-- Posição própria e amigos em falta
select testes.entrar(:'vera');
select results_eq($$select posicao, amigos, amigos_em_falta, no_top from minha_posicao()$$,
                  $$values (2, 5, 0, true)$$, 'minha_posicao() do próprio cliente');
select is((select count(*)::int from destaques_mes() where sou_eu), 1, 'marca "(tu)" na própria linha');
select testes.sair();

-- 29. pessoas_como_tu(): menos de 2 exemplos -> vazio
select testes.cliente('Xavier Novo') as xavier \gset
select testes.entrar(:'xavier');
-- entre 3 e 10 amigos: Sérgio (3) e Vera (5); Rita tem 12
update perfil_destaques set sair_da_lista = true where cliente_id = :'sergio';
select is((select count(*)::int from pessoas_como_tu()), 0,
          '29. pessoas_como_tu() com menos de 2 exemplos -> vazio');
update perfil_destaques set sair_da_lista = false where cliente_id = :'sergio';
select results_eq($$select count(*)::int, min(amigos), max(amigos) from pessoas_como_tu()$$,
                  $$values (2, 3, 5)$$, 'com 2 exemplos reais -> devolve-os (3 a 10 amigos)');
select testes.sair();

-- 30. contador_zona() abaixo de 10 -> null
insert into zonas (nome) values ('Talatona') returning id as zona \gset
select testes.local('residencial', null, null, :'zona') as lz \gset
select testes.pagar(testes.pedido(testes.cliente('Z' || n), :'lz')) from generate_series(1, 9) n;
select job_contadores_zona();
select is(contador_zona(:'zona'), null, '30. contador_zona() com 9 pedidos -> null');
select testes.pagar(testes.pedido(testes.cliente('Z10'), :'lz'));
select job_contadores_zona();
select is(contador_zona(:'zona'), 10, 'contador_zona() com 10 pedidos -> 10');

select * from finish();
rollback;
