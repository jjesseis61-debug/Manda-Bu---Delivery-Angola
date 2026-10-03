-- "Mesmo local" pelos pontos próximos (índice de coordenadas) dá o mesmo que mesmo_ponto_entrega
begin;
\ir _helpers.psql
select plan(6);

select setseed(0.5);
-- 400 pontos em 20 grupos apertados (alguns a menos de 25 m uns dos outros), dois tipos
select testes.def('n' || g, testes.ponto(case when g % 4 = 0 then 'empresa' else 'residencial' end,
                                         -8.80 - (g % 20) * 0.01 + (random() - 0.5) * 0.0008,
                                         13.20 + (g % 20) * 0.01 + (random() - 0.5) * 0.0008))
  from generate_series(1, 400) g;

select is((select count(*)::int
             from generate_series(1, 400, 7) g, lateral (select testes.u('n' || g) as a) s
            where array(select x from pontos_entrega_proximos(s.a) x order by x)
                  <> array(select b.id from pontos_entrega b where mesmo_ponto_entrega(b.id, s.a) order by b.id)),
          0, 'em 58 pontos ao acaso, os pontos próximos são exactamente os de mesmo_ponto_entrega');

-- fronteira do raio (25 m): 1 grau de longitude a -8.9 ≈ 109 857 m
select testes.def('c', testes.ponto('residencial', -8.9, 13.3));
select testes.def('a24', testes.ponto('residencial', -8.9, 13.3 + 24 / 109857.0));
select testes.def('a26', testes.ponto('residencial', -8.9, 13.3 + 26 / 109857.0));
select testes.def('e10', testes.ponto('empresa', -8.9, 13.3 + 10 / 109857.0));
select is(array(select x from pontos_entrega_proximos(testes.u('c')) x where x in (testes.u('a24'), testes.u('a26'), testes.u('e10')))::text,
          array[testes.u('a24')]::text, 'a 24 m conta, a 26 m não, e um ponto de outro tipo também não');

update parametros set raio_mesmo_local_m = 100 where unico;
select ok(testes.u('a26') in (select pontos_entrega_proximos(testes.u('c'))), 'o raio segue o parâmetro (100 m: o ponto a 26 m passa a contar)');

select testes.def('sem', testes.ponto('residencial', -12.5, 13.5));
select is(array(select pontos_entrega_proximos(testes.u('sem')))::text, array[testes.u('sem')]::text,
          'ponto isolado (Benguela): só ele próprio');

select ok(not has_function_privilege('authenticated', 'pontos_entrega_proximos(uuid)', 'execute')
          and not has_function_privilege('anon', 'pontos_entrega_proximos(uuid)', 'execute'),
          'a função não está exposta na API');

select ok(position('mesmo_ponto_entrega' in (select prosrc from pg_proc where proname = 'processar_ganho_indicacao')) = 0
          and position('mesmo_ponto_entrega' in (select prosrc from pg_proc where proname = 'avaliar_desconto_indicacao')) = 0,
          'nenhuma das verificações percorre o histórico ponto a ponto');

select * from finish();
rollback;
