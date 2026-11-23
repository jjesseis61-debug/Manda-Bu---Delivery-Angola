-- «Kota da Cozinha»: selo de respeito para as cozinheiras parceiras com anos de cozinha de casa.
-- O operador (cozinhas.gerir) liga-o na ficha da cozinha; o cliente vê-o no perfil público da cozinha
-- (só aparece com o perfil público autorizado, como o nome, a foto e a história).
alter table cozinhas add column if not exists selo_kota boolean not null default false;
comment on column cozinhas.selo_kota is 'Selo «Kota da Cozinha» no perfil público (dado pelo operador)';
