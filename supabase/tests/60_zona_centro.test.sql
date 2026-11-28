-- Centro (ponto de referência) opcional das zonas de entrega: coluna e a restrição tudo-ou-nada
-- com coordenadas dentro do intervalo. Não define a fronteira do bairro.
begin;
\ir _helpers.psql
select plan(6);

select has_column('zonas', 'centro_lat', 'zonas tem centro_lat');
select has_column('zonas', 'centro_lng', 'zonas tem centro_lng');

-- Sem centro é válido (o campo é opcional)
select lives_ok(
  $$insert into zonas (nome) values ('Zona sem centro')$$,
  'zona sem centro é aceite');

-- Par válido dentro do intervalo
select lives_ok(
  $$insert into zonas (nome, centro_lat, centro_lng) values ('Zona com centro', -8.84, 13.23)$$,
  'zona com centro válido é aceite');

-- Coordenada fora do intervalo é recusada (violação de check, sqlstate 23514)
select matches(
  testes.erro($$insert into zonas (nome, centro_lat, centro_lng) values ('Zona má', 200, 13.23)$$),
  '^23514',
  'latitude fora do intervalo é recusada');

-- Meio par (só latitude) é recusado: tem de ser tudo-ou-nada
select matches(
  testes.erro($$insert into zonas (nome, centro_lat) values ('Zona meio par', -8.84)$$),
  '^23514',
  'centro incompleto (só latitude) é recusado');

select finish();
rollback;
