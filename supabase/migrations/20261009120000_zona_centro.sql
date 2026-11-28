-- Centro (ponto de referência) de cada zona de entrega.
-- O operador pode marcar um ponto no mapa (ou usar a localização actual) ao criar/editar a zona.
-- Não define a fronteira do bairro: serve para centrar o mapa do cliente nesse bairro e ajudar o
-- GPS/rota. Fica opcional (pode ser nulo) e usa a política de edição que já existe em `zonas`
-- (quem tem plataforma.parametros). Sem GRANTs por coluna, as colunas novas herdam a permissão.

alter table zonas
  add column if not exists centro_lat double precision,
  add column if not exists centro_lng double precision;

alter table zonas
  drop constraint if exists zonas_centro_valido;
-- Tudo-ou-nada e dentro do intervalo. O `=` entre os dois `is null` obriga a que ambos sejam
-- nulos ou ambos preenchidos (um check devolve TRUE/NULL como válido, por isso a parte do
-- intervalo tem de dar FALSE explícito quando falha, não NULL).
alter table zonas
  add constraint zonas_centro_valido check (
    (centro_lat is null) = (centro_lng is null)
    and (centro_lat is null or (centro_lat between -90 and 90 and centro_lng between -180 and 180))
  );

comment on column zonas.centro_lat is 'Latitude do centro de referência da zona (opcional); não é a fronteira do bairro.';
comment on column zonas.centro_lng is 'Longitude do centro de referência da zona (opcional); não é a fronteira do bairro.';
