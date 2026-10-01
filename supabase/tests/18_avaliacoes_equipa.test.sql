-- I5 · Avaliações (C9, C10, O7), N9 e reconhecimento de equipa com N12
begin;
\ir _helpers.psql
select plan(30);

select testes.def('alexandra', cozinha_padrao());
select testes.funcionalidade('avaliacoes', true);
with p as (insert into pratos_base (nome) values ('Muamba') returning id) select testes.def('muamba', id) from p;
with p as (insert into pratos_base (nome) values ('Calulu') returning id) select testes.def('calulu', id) from p;
with p as (insert into pratos_base (nome) values ('Funge') returning id) select testes.def('funge', id) from p;
with m as (insert into cardapio (nome, preco, prato_base_id) values ('Muamba de galinha', 2500, testes.u('muamba')) returning id)
select testes.def('c_muamba', id) from m;
with m as (insert into cardapio (nome, preco, prato_base_id) values ('Calulu de peixe', 3000, testes.u('calulu')) returning id)
select testes.def('c_calulu', id) from m;

select testes.def('ana', testes.cliente('Ana Maria Sousa'));
select testes.def('bia', testes.cliente('Bia'));
with z as (insert into zonas (nome, tipo, taxa) values ('Zona teste', 'Própria', 0) returning id)
select testes.def('zona', id) from z;
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa')), (testes.u('bia'), testes.u('casa'));

-- Pedido da Ana com Muamba e Calulu, entregue
select testes.entrar(testes.u('ana'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('ana'), testes.u('casa'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('c_muamba'), 'qtd', 1),
                                     jsonb_build_object('cardapio_id', testes.u('c_calulu'), 'qtd', 1)))
           returning id)
select testes.def('p_ana', id) from x;
reset role;
select testes.sair();
select testes.pagar(testes.u('p_ana'));

-- ---------------------------------------------------------------------------
-- C9. Avaliar pelo telemóvel
-- ---------------------------------------------------------------------------
select testes.entrar(testes.u('ana'));
set local role authenticated;
with a as (insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario, dispositivo_id)
           values (testes.u('p_ana'), testes.u('ana'), 5, 'Muito bom, chegou quente', 'telemovel-ana') returning id)
select testes.def('av_ana', id) from a;
insert into avaliacoes_pratos (avaliacao_id, prato_id, estrelas) values (testes.u('av_ana'), testes.u('muamba'), 5);
select testes.def('e_prato_fora', testes.erro(format(
  $$insert into avaliacoes_pratos (avaliacao_id, prato_id, estrelas) values (%L, %L, 4)$$, testes.v('av_ana'), testes.v('funge'))));
select testes.def('e_segunda', testes.erro(format(
  $$insert into avaliacoes (pedido_id, cliente_id, estrelas) values (%L, %L, 1)$$, testes.v('p_ana'), testes.v('ana'))));
select testes.def('e_editar', testes.erro(format($$update avaliacoes set estrelas = 1 where id = %L$$, testes.v('av_ana'))));
reset role;
select testes.sair();

select results_eq(format($$select estrelas, comentario, cozinha_id, oculta from avaliacoes where id = %L$$, testes.u('av_ana')),
                  format($$values (5, 'Muito bom, chegou quente'::text, %L::uuid, false)$$, testes.u('alexandra')),
                  'C9: o cliente avalia o seu pedido entregue (cozinha vem do pedido)');
select is((select count(*)::int from avaliacoes_pratos where avaliacao_id = testes.u('av_ana')), 1, 'C9: estrelas por prato');
select is(testes.v('e_prato_fora'), 'P0001:prato_fora_do_pedido', 'C9: só pratos do próprio pedido');
select matches(testes.v('e_segunda'), '^23505', 'C9: uma avaliação por pedido');
select matches(testes.v('e_editar'), '^42501', 'C9: a avaliação não se edita depois de enviada');

-- Pedido da Bia (sem pratos do cardápio), avaliação com pseudónimo
select testes.def('p_bia', testes.pedido(testes.u('bia'), testes.u('casa')));
select testes.pagar(testes.u('p_bia'));
select testes.entrar(testes.u('bia'));
set local role authenticated;
insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario, usar_pseudonimo)
values (testes.u('p_bia'), testes.u('bia'), 3, 'Demorou um pouco', true);
select testes.def('bia_ve_tabela', (select count(*) from avaliacoes));
select testes.def('bia_ve_lista', (select string_agg(autor || ':' || estrelas, ',' order by estrelas desc)
                                      from avaliacoes_publicas(testes.u('alexandra'))));
select testes.def('bia_ve_prato', (select string_agg(autor, ',') from avaliacoes_publicas(testes.u('alexandra'), testes.u('muamba'))));
select testes.def('pratos_ana', (select pratos::text from avaliacoes_publicas(testes.u('alexandra')) where estrelas = 5));
reset role;
select testes.sair();

-- ---------------------------------------------------------------------------
-- C10. Lista pública sem ids
-- ---------------------------------------------------------------------------
select is(testes.v('bia_ve_tabela')::int, 1, 'C10: o cliente só lê as suas linhas de avaliacoes (sem ids dos outros)');
select is(testes.v('bia_ve_lista'),
          'Ana S.:5,' || (select pseudonimo from perfil_destaques where cliente_id = testes.u('bia')) || ':3',
          'C10: autor com primeiro nome e inicial, ou pseudónimo');
select is(testes.v('bia_ve_prato'), 'Ana S.', 'C10: avaliações de um prato');
select is(testes.v('pratos_ana'), '[{"nome": "Muamba", "estrelas": 5}]', 'C10: estrelas por prato na lista');
select is((select count(*)::int from information_schema.parameters
            where specific_name like 'avaliacoes\_publicas\_%' and parameter_mode = 'OUT'
              and parameter_name ~* 'id$|^id|telefone'), 0, 'C10: avaliacoes_publicas() não devolve ids nem telefones');

-- Médias só com o mínimo (5)
select testes.entrar(testes.u('bia'));
select is(medias_avaliacoes(testes.u('alexandra')) -> 'cozinha', 'null'::jsonb, 'média da cozinha escondida abaixo do mínimo');
select testes.sair();
do $$
declare
  c uuid; p uuid;
begin
  for i in 1..3 loop
    c := testes.cliente('Cliente ' || i);
    p := testes.pedido(c, testes.u('casa'));
    perform testes.pagar(p);
    insert into avaliacoes (pedido_id, cliente_id, estrelas) values (p, c, 4);
  end loop;
end $$;
select testes.entrar(testes.u('bia'));
select is(medias_avaliacoes(testes.u('alexandra')) -> 'cozinha', '{"media": 4.0, "total": 5}'::jsonb,
          'média da cozinha com 5 avaliações');
select testes.sair();

-- Comentário oculto sai da lista; interruptor desligado esconde tudo
select testes.def('moderador', testes.funcionario('Moderador', array['avaliacoes.moderar']));
select testes.entrar_funcionario(testes.u('moderador'));
select results_eq($$select autor_nome, comentario, oculta from avaliacoes_moderacao() order by estrelas desc$$,
                  $$values ('Ana Maria Sousa'::text, 'Muito bom, chegou quente'::text, false),
                           ('Bia'::text, 'Demorou um pouco'::text, false)$$,
                  'O7: comentários recentes com o nome real (interno)');
select ocultar_avaliacao(testes.u('av_ana'));
set local role authenticated;
insert into palavras_filtradas (palavra) values ('palavrão');
update palavras_filtradas set deletado_em = now() where palavra = 'palavrão';
reset role;
select is((select deletado_em is not null from palavras_filtradas where palavra = 'palavrão'), true,
          'O7: o moderador adiciona e remove palavras filtradas pela app');
select testes.entrar(testes.u('bia'));
set local role authenticated;
select testes.def('e_bia_palavra', testes.erro($$insert into palavras_filtradas (palavra) values ('x')$$));
reset role;
select matches(testes.v('e_bia_palavra'), '^42501', 'O7: cliente não mexe nas palavras filtradas');
select testes.entrar(testes.u('bia'));
select throws_ok('select * from avaliacoes_moderacao()', '42501', 'sem_permissao', 'O7 exige avaliacoes.moderar');
select is((select count(*)::int from avaliacoes_publicas(testes.u('alexandra')) where comentario like 'Muito bom%'), 0,
          'O7: comentário ocultado sai da lista pública');
select testes.funcionalidade('avaliacoes', false);
select is((select count(*)::int from avaliacoes_publicas(testes.u('alexandra'))), 0, 'interruptor desligado: lista vazia');
select testes.funcionalidade('avaliacoes', true);
select testes.sair();

-- ---------------------------------------------------------------------------
-- N9
-- ---------------------------------------------------------------------------
select testes.def('cid', testes.cliente('Cid'));
select testes.def('p_cid', testes.pedido(testes.u('cid'), testes.u('casa')));
select testes.pagar(testes.u('p_cid'));
select job_n9_avaliacao();
select is((select count(*)::int from notificacoes_fila where codigo = 'N9' and cliente_id = testes.u('cid')), 0,
          'N9: ainda não passou 1 hora');
update pedidos set entregue_em = now() - interval '70 minutes' where id = testes.u('p_cid');
select job_n9_avaliacao();
select job_n9_avaliacao();
select is((select count(*)::int from notificacoes_fila where codigo = 'N9' and cliente_id = testes.u('cid')), 1,
          'N9: uma vez, 1 hora depois da entrega');
select is((texto_notificacao('N9', '{"refeicao": "almoço", "cozinha_nome": "Cozinha da Alexandra"}')).corpo,
          'Como estava o almoço da Cozinha da Alexandra? Avalia em 10 segundos.', 'N9: texto');
insert into notificacoes_fila (cliente_id, codigo, dados)
values (testes.u('ana'), 'N9', jsonb_build_object('pedido_id', testes.u('p_ana'), 'cozinha_nome', 'Cozinha da Alexandra'));
select is((select count(*)::int from notificacoes_por_enviar(1000) where cliente_id = testes.u('ana') and codigo = 'N9'), 0,
          'N9: pedido já avaliado -> não é enviada');

-- ---------------------------------------------------------------------------
-- O8 e N12
-- ---------------------------------------------------------------------------
select testes.funcionalidade('reconhecimento_equipa', true);
select testes.def('chefe', testes.funcionario('Chefe', array['equipa.reconhecer']));
select testes.def('rui', testes.funcionario('Rui Cozinheiro', array[]::text[]));
select testes.def('eva', testes.funcionario('Eva Tarde', array[]::text[]));
select testes.def('segunda', date_trunc('week', hoje_luanda())::date);
insert into turnos (funcionario_id, data, hora_inicio, hora_fim, periodo) values
  (testes.u('rui'), testes.v('segunda')::date, '07:00', '15:00', 'manha'),
  (testes.u('rui'), testes.v('segunda')::date + 1, '07:00', '15:00', 'manha'),
  (testes.u('eva'), testes.v('segunda')::date, '15:00', '22:00', 'tarde');

select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select testes.def('rui_eu', meu_funcionario());
select testes.def('e_rui_reconhece', testes.erro(format(
  $$insert into reconhecimentos_turno (cozinha_id, semana, periodo, tipo) values (%L, %L, 'manha', 'outro')$$,
  testes.v('alexandra'), testes.v('segunda'))));
select testes.def('rui_token', testes.erro($$select registar_token_push_funcionario('ExponentPushToken[rui-1]', 'android')$$));
reset role;
select testes.entrar_funcionario(testes.u('chefe'));
set local role authenticated;
insert into reconhecimentos_turno (cozinha_id, semana, periodo, tipo, nota)
values (testes.v('alexandra')::uuid, testes.v('segunda')::date, 'manha', 'entregas_a_horas', 'Todas as entregas a horas');
reset role;
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select testes.def('rui_ve', (select count(*) from reconhecimentos_turno));
reset role;
select testes.def('estranho', testes.funcionario('Sem Turnos', array[]::text[]));
select testes.entrar_funcionario(testes.u('estranho'));
set local role authenticated;
select testes.def('estranho_ve', (select count(*) from reconhecimentos_turno));
reset role;
select testes.sair();

select is(testes.v('rui_ve')::int, 1, 'O8: membro da cozinha vê os reconhecimentos');
select is(testes.v('estranho_ve')::int, 0, 'O8: quem não é da cozinha não os vê');
select is(testes.v('rui_eu')::jsonb -> 'cozinhas_equipa', jsonb_build_array(testes.u('alexandra')),
          'O8: membro da cozinha vê as métricas da sua cozinha');
select matches(testes.v('e_rui_reconhece'), '^42501', 'O8: só equipa.reconhecer regista reconhecimentos');
select results_eq($$select funcionario_id, (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N12'$$,
                  format($$values (%L::uuid, 'Parabéns, turno da manhã: entregas a horas esta semana!'::text)$$, testes.u('rui')),
                  'N12: só os membros do turno reconhecido, uma vez cada');
select is(testes.v('rui_token'), 'sem_erro', 'push: o funcionário regista o telemóvel');
select results_eq($$select destino, tokens from notificacoes_por_enviar(1000) where codigo = 'N12'$$,
                  $$values ('funcionario'::text, array['ExponentPushToken[rui-1]'])$$,
                  'N12 segue para o telemóvel do funcionário, com destino funcionário');
select throws_ok(format($$insert into notificacoes_fila (cliente_id, funcionario_id, codigo) values (%L, %L, 'N12')$$,
                        testes.u('ana'), testes.u('rui')),
                 '23514', null, 'uma notificação tem um só destinatário');

select * from finish();
rollback;
