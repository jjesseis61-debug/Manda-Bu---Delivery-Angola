-- Faixa de confiança: a 3.ª frase só promete o tempo quando as entregas o cumprem (>= 90% em >= 30)
begin;
\ir _helpers.psql
select plan(5);

select testes.def('c', testes.cliente('Cliente Faixa'));
-- 30 entregas imediatas entregues e pagas; n_atrasadas chegam depois da hora prometida
create function pg_temp.semear(n int, n_atrasadas int) returns void language plpgsql as $$
declare p uuid;
begin
  for i in 1..n loop
    p := testes.pedido(testes.u('c'));
    perform testes.pagar(p);
    update pedidos set hora_prometida = now() - interval '1 hour',
                       entregue_em = now() - interval '1 hour' + case when i <= n_atrasadas then interval '20 minutes' else interval '-5 minutes' end
     where id = p;
  end loop;
end $$;

select is((pontualidade_entregas() ->> 'cumpre')::boolean, false, 'sem entregas: não promete tempo');
select pg_temp.semear(29, 0);
select is((pontualidade_entregas() ->> 'cumpre')::boolean, false, '29 entregas a tempo: ainda poucas para prometer');
select pg_temp.semear(1, 0);
select results_eq($$select (pontualidade_entregas() ->> 'cumpre')::boolean, (pontualidade_entregas() ->> 'a_tempo_pct')::int$$,
                  $$values (true, 100)$$, '30 entregas a tempo: promete o tempo');
select pg_temp.semear(5, 5);
select results_eq($$select (pontualidade_entregas() ->> 'cumpre')::boolean, (pontualidade_entregas() ->> 'a_tempo_pct')::int$$,
                  $$values (false, 86)$$, '30 de 35 a tempo (86%): volta a não prometer');
select is(has_function_privilege('anon', 'pontualidade_entregas()', 'execute'), false, 'só com sessão');

select * from finish();
rollback;
