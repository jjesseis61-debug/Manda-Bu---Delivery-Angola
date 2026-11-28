-- Embaixador: parabéns ao subir de nível (N43) e descida suave semanal (N44).
begin;
\ir _helpers.psql
select plan(15);
update parametros set limiar_embaixador = 1, limiar_ouro = 30, despromocao_activa = true,
                      despromocao_carencia_dias = 30, despromocao_margem_pct = 80 where unico;
select testes.funcionalidade('indicacao', true);

select testes.def('ana', testes.cliente('Ana Embaixadora'));
select testes.def('bruno', testes.indicado(testes.u('ana'), 'Bruno'));
select testes.def('p1', testes.pedido(testes.u('bruno'), testes.ponto('residencial')));
select testes.pagar(testes.u('p1'));

-- 1) Subida automática → N43 com a comissão do novo nível
select is((select nivel from codigos_indicacao where cliente_id = testes.u('ana')), 'embaixador',
          'com 1 amigo activo (limiar 1) sobe a Embaixador');
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('ana') and codigo = 'N43'), 1,
          'parabéns N43 na fila');
select is((select (dados ->> 'ganho_por_pedido')::int from notificacoes_fila
            where cliente_id = testes.u('ana') and codigo = 'N43'),
          (select ganho_por_pedido_embaixador from parametros where unico), 'N43 leva a comissão de Embaixador');
select ok((select corpo from texto_notificacao('N43', (select dados from notificacoes_fila
            where cliente_id = testes.u('ana') and codigo = 'N43'))) like 'Parabéns, és Embaixador!%',
          'texto do N43');
select ok((select nivel_desde > now() - interval '1 minute' from codigos_indicacao where cliente_id = testes.u('ana')),
          'nivel_desde marca a mudança');
select ok(exists (select 1 from notificacoes_por_enviar(500) where codigo = 'N43' and cliente_id = testes.u('ana')),
          'N43 sai pelo envio de notificações');

-- 2) Carência: acabou de subir, não é avaliada
update ligacoes_indicacao set expira_em = now() - interval '1 day' where indicado_id = testes.u('bruno');
select is(job_despromocao_embaixador(), 0, 'dentro da carência ninguém desce');

-- 3) Passada a carência, com amigos activos suficientes, fica
update ligacoes_indicacao set expira_em = now() + interval '30 days' where indicado_id = testes.u('bruno');
update codigos_indicacao set nivel_desde = now() - interval '40 days' where cliente_id = testes.u('ana');
select is(job_despromocao_embaixador(), 0, 'com amigos activos mantém o nível');

-- 4) Sem amigos activos (vínculo expirou) → desce a normal, com aviso N44 simpático
update ligacoes_indicacao set expira_em = now() - interval '1 day' where indicado_id = testes.u('bruno');
select is(job_despromocao_embaixador(), 1, 'sem amigos activos desce');
select is((select nivel from codigos_indicacao where cliente_id = testes.u('ana')), 'normal', 'Embaixador → normal');
select ok((select corpo from texto_notificacao('N44', (select dados from notificacoes_fila
            where cliente_id = testes.u('ana') and codigo = 'N44')))
          like 'Passaste a nível normal porque tens 0 amigo(s) activo(s)%Faltam só 1 para voltares a Embaixador%',
          'texto do N44 diz quanto falta para voltar');

-- 5) Ouro desce UM degrau de cada vez, e recomeça a carência
select testes.def('olga', testes.cliente('Olga Ouro'));
update codigos_indicacao set nivel = 'ouro' where cliente_id = testes.u('olga');
update codigos_indicacao set nivel_desde = now() - interval '40 days' where cliente_id = testes.u('olga');
select job_despromocao_embaixador();
select is((select nivel from codigos_indicacao where cliente_id = testes.u('olga')), 'embaixador',
          'Ouro → Embaixador (não salta para normal)');
select is(job_despromocao_embaixador(), 0, 'depois de descer, nova carência');

-- 6) Interruptores
update codigos_indicacao set nivel_desde = now() - interval '40 days' where cliente_id = testes.u('olga');
update parametros set despromocao_activa = false where unico;
select is(job_despromocao_embaixador(), 0, 'descida desligada nos parâmetros');
select testes.funcionalidade('indicacao', false);
select ok(not exists (select 1 from notificacoes_por_enviar(500) where codigo in ('N43', 'N44')),
          'com o Convida desligado os avisos de nível não saem');

select * from finish();
rollback;
