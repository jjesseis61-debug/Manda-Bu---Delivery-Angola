-- Atendimento ao cliente: mensagens do cliente (sessão, interruptor, texto, limite), reserva sem respostas em dobro,
-- ferramentas só com os dados do próprio cliente e sem telefone, resposta do agente, passagem para uma pessoa (N29),
-- resposta de uma pessoa (N30), quem vê o quê, devolver ao agente, fechar, erros e interruptor
begin;
\ir _helpers.psql
select plan(17);

select testes.funcionalidade('agente_atendimento', true);
select testes.def('cz', cozinha_padrao());
select testes.def('ana', testes.cliente('Ana Sousa', 'Particular', '923000111'));
select testes.def('bia', testes.cliente('Bia Neto', 'Particular', '923000222'));
select testes.def('rita', testes.funcionario('Rita Apoio', array['atendimento.responder']));
select testes.def('gil', testes.funcionario('Gil Gerente', array['pedidos.gerir']));
select testes.def('ponto', testes.ponto('residencial'));
create function pg_temp.pedido(p_cliente text, p_prato text) returns uuid language sql as $$
  insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, subtotal, itens)
  values (testes.u(p_cliente), testes.u('ponto'), testes.u('cz'), 3500,
          jsonb_build_array(jsonb_build_object('nome', p_prato, 'qtd', 1, 'preco_unitario', 3500)))
  returning id;
$$;
select testes.def('P1', pg_temp.pedido('ana', 'Muamba'));
select testes.def('P2', pg_temp.pedido('ana', 'Calulu'));
select testes.def('P3', pg_temp.pedido('bia', 'Cachupa'));
insert into alertas_pedido (pedido_id, cliente_id, cozinha_id, tipo, minutos, motivo, mais_minutos)
values (testes.u('P2'), testes.u('ana'), testes.u('cz'), 'atraso', 25, 'A cozinha está com muitos pedidos', 15);
insert into cardapio (cozinha_id, nome, preco, do_dia) values (testes.u('cz'), 'Muamba de galinha', 3500, true);

-- O cliente escreve
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_vazio', testes.erro($$select enviar_mensagem_atendimento('   ')$$));
select testes.def('c_ana', enviar_mensagem_atendimento('Onde está o meu calulu?') ->> 'conversa_id');
reset role;
select testes.entrar(testes.u('bia'));
set local role authenticated;
select testes.def('c_bia', enviar_mensagem_atendimento('Quanto custa a entrega?') ->> 'conversa_id');
reset role;
select testes.sair();
set local role authenticated;
select testes.def('e_anon', testes.erro($$select enviar_mensagem_atendimento('olá')$$));
reset role;
select ok(testes.v('e_vazio') = 'P0001:texto_invalido' and testes.v('e_anon') like '42501:%'
          and (select count(*) from conversas_atendimento where ia_estado = 'pendente') = 2,
          'cada cliente com sessão abre a sua conversa (sem sessão ou texto vazio não)');

-- Reserva: uma conversa de cada vez, e não outra vez enquanto o agente responde
select testes.def('r1', reservar_atendimento());
select testes.def('r2', reservar_atendimento());
select ok(testes.v('r1')::jsonb ->> 'id' = testes.v('c_ana') and testes.v('r1')::jsonb ->> 'primeiro_nome' = 'Ana'
          and testes.v('r1')::jsonb -> 'mensagens' -> 0 ->> 'texto' = 'Onde está o meu calulu?'
          and testes.v('r2')::jsonb ->> 'id' = testes.v('c_bia') and reservar_atendimento() is null,
          'reserva a conversa mais antiga com as últimas mensagens e o primeiro nome; depois a outra; depois nada');
select testes.entrar(testes.u('ana'));
set local role authenticated;
select enviar_mensagem_atendimento('É o pedido de hoje.');
reset role;
select testes.sair();
select ok(reservar_atendimento(testes.u('c_ana')) is null
          and (select ia_estado from conversas_atendimento where id = testes.u('c_ana')) = 'a_responder',
          'uma mensagem nova enquanto o agente responde não abre uma segunda resposta');

-- Ferramentas: só os dados deste cliente, sem telefone
select testes.def('ped', atd_pedidos(testes.u('c_ana')));
select ok(jsonb_array_length(testes.v('ped')::jsonb) = 2 and testes.v('ped') not like '%Cachupa%'
          and (select e -> 'atraso' ->> 'motivo_dado_ao_cliente' from jsonb_array_elements(testes.v('ped')::jsonb) e
                where e ->> 'pedido_id' = testes.v('P2')) = 'A cozinha está com muitos pedidos',
          'pedidos: só os do cliente da conversa, com o atraso e o motivo');
select testes.def('conta', atd_conta(testes.u('c_ana')));
select ok(testes.v('conta')::jsonb ->> 'primeiro_nome' = 'Ana' and testes.v('conta') not like '%923000%'
          and testes.v('conta') not like '%Sousa%' and testes.v('ped') not like '%923000%'
          and testes.v('conta')::jsonb -> 'convida_e_ganha' ->> 'codigo' is not null,
          'conta: primeiro nome e Convida e Ganha, sem apelido nem telefone');
select ok(exists (select 1 from jsonb_array_elements(atd_informacoes() -> 'cozinhas') z, jsonb_array_elements(z -> 'pratos_disponiveis') p
                  where p ->> 'prato' = 'Muamba de galinha' and (p ->> 'preco_kz')::int = 3500)
          and atd_informacoes() -> 'regras' ->> 'tempo_de_entrega_min' is not null,
          'informação pública: pratos disponíveis e regras');

-- Resposta do agente (com a mensagem nova pelo meio, a conversa volta a ficar por responder)
select testes.def('reg1', registar_atendimento(testes.u('c_ana'), 'respondida',
  jsonb_build_object('texto', 'O teu calulu está atrasado uns 15 minutos: a cozinha está com muitos pedidos.', 'passar_a_pessoa', false)));
select ok(testes.v('reg1') = 'respondida'
          and (select ia_estado from conversas_atendimento where id = testes.u('c_ana')) = 'pendente'
          and exists (select 1 from mensagens_atendimento where conversa_id = testes.u('c_ana') and autor = 'agente'),
          'guarda a resposta do agente; como chegou outra mensagem, volta a ficar por responder');
select reservar_atendimento(testes.u('c_ana'));
select testes.def('reg2', registar_atendimento(testes.u('c_ana'), 'respondida',
  jsonb_build_object('texto', 'Vou passar-te a um colega para ver a compensação.', 'passar_a_pessoa', true, 'motivo', 'pede compensação pelo atraso')));
select ok(testes.v('reg2') = 'humano'
          and (select estado = 'humano' and motivo_humano = 'pede compensação pelo atraso' from conversas_atendimento where id = testes.u('c_ana')),
          'o agente passa a conversa a uma pessoa com o motivo');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N29' and funcionario_id = testes.u('rita')),
          'Atendimento: Ana precisa de uma pessoa (pede compensação pelo atraso). Abre para responder.',
          'N29 a quem atende, com o primeiro nome e o motivo');
select testes.entrar(testes.u('ana'));
set local role authenticated;
select enviar_mensagem_atendimento('Estou à espera.');
reset role;
select testes.sair();
select ok(not exists (select 1 from notificacoes_fila where codigo = 'N29' and funcionario_id = testes.u('gil'))
          and (select count(*) from notificacoes_fila where codigo = 'N29' and funcionario_id = testes.u('rita')) = 1
          and (select ia_estado from conversas_atendimento where id = testes.u('c_ana')) = 'livre',
          'com uma pessoa, o agente não responde e o aviso não se repete em 10 minutos; quem não atende não é avisado');

-- Uma pessoa responde
select testes.entrar_funcionario(testes.u('gil'));
set local role authenticated;
select testes.def('e_gil', testes.erro($$select conversas_atendimento_lista()$$));
reset role;
select testes.entrar_funcionario(testes.u('rita'));
set local role authenticated;
select testes.def('lista', conversas_atendimento_lista());
select testes.def('detalhe', conversa_atendimento(testes.u('c_ana')));
select responder_atendimento(testes.u('c_ana'), 'Olá Ana, vamos oferecer-te a entrega no próximo pedido.');
reset role;
select testes.sair();
select ok(testes.v('e_gil') like '42501:%' and jsonb_array_length(testes.v('lista')::jsonb) = 2
          and testes.v('lista')::jsonb -> 0 ->> 'id' = testes.v('c_ana')
          and testes.v('detalhe')::jsonb ->> 'telefone' is null and jsonb_array_length(testes.v('detalhe')::jsonb -> 'pedidos') = 2,
          'só quem atende vê as conversas (as que precisam de uma pessoa primeiro), sem o telefone se não gere clientes');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N30' and cliente_id = testes.u('ana')),
          'Resposta do apoio Manda Bué: Olá Ana, vamos oferecer-te a entrega no próximo pedido.', 'N30 ao cliente com a resposta');

-- O que cada cliente vê
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('minha', minha_conversa_atendimento());
reset role;
select testes.entrar(testes.u('bia'));
set local role authenticated;
select testes.def('dela', minha_conversa_atendimento());
select testes.def('linhas_bia', (select count(*) from mensagens_atendimento));
reset role;
select testes.sair();
select ok((testes.v('minha')::jsonb -> 'mensagens' -> -1 ->> 'quem') = 'Rita' and testes.v('minha')::jsonb ->> 'estado' = 'humano'
          and jsonb_array_length(testes.v('dela')::jsonb -> 'mensagens') = 1 and testes.v('linhas_bia') = '1'
          and testes.v('dela') not like '%calulu%',
          'cada cliente vê só a sua conversa (com o primeiro nome de quem respondeu)');

-- Devolver ao agente, fechar e recomeçar
select testes.entrar_funcionario(testes.u('rita'));
set local role authenticated;
select mudar_conversa_atendimento(testes.u('c_ana'), 'agente');
select testes.def('estado_dev', (select estado from conversas_atendimento where id = testes.u('c_ana')));
select mudar_conversa_atendimento(testes.u('c_ana'), 'fechada');
select testes.def('e_fechada', testes.erro(format($$select responder_atendimento(%L, 'olá')$$, testes.v('c_ana'))));
reset role;
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('c_ana2', enviar_mensagem_atendimento('Outra pergunta.') ->> 'conversa_id');
reset role;
select testes.sair();
select ok(testes.v('estado_dev') = 'agente' and testes.v('e_fechada') = 'P0001:conversa_fechada'
          and testes.v('c_ana2') <> testes.v('c_ana')
          and exists (select 1 from auditoria where acao = 'atendimento_fechado' and funcionario_nome = 'Rita Apoio'),
          'devolver ao agente, fechar (na auditoria) e uma mensagem nova abre outra conversa');

-- Erros do agente: à terceira passa para uma pessoa; o cliente também pode pedir uma pessoa
select registar_atendimento(testes.u('c_bia'), 'erro', null, 'falha 1');
select reservar_atendimento(testes.u('c_bia'));
select registar_atendimento(testes.u('c_bia'), 'erro', null, 'falha 2');
select reservar_atendimento(testes.u('c_bia'));
select testes.def('r_bia', registar_atendimento(testes.u('c_bia'), 'erro', null, 'falha 3'));
select ok(testes.v('r_bia') = 'humano'
          and exists (select 1 from mensagens_atendimento where conversa_id = testes.u('c_bia') and autor = 'sistema' and texto like 'Não consegui responder%'),
          'três erros: a conversa passa para uma pessoa e o cliente é avisado na conversa');
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('pessoa', pedir_pessoa_atendimento());
reset role;
select testes.sair();
select ok(testes.v('pessoa') = 'humano' and (select estado from conversas_atendimento where id = testes.u('c_ana2')) = 'humano',
          'o cliente pede para falar com uma pessoa');

-- Limite diário e interruptor
update parametros set atendimento_mensagens_dia = 1 where unico;
select testes.entrar(testes.u('bia'));
set local role authenticated;
select testes.def('e_limite', testes.erro($$select enviar_mensagem_atendimento('Mais uma.')$$));
reset role;
select testes.sair();
select testes.funcionalidade('agente_atendimento', false);
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_off', testes.erro($$select enviar_mensagem_atendimento('Olá')$$));
reset role;
select testes.sair();
select ok(testes.v('e_limite') = 'P0001:limite_diario' and testes.v('e_off') = 'P0001:funcionalidade_inactiva'
          and reservar_atendimento() is null
          and not has_function_privilege('authenticated', 'atd_pedidos(uuid)', 'execute')
          and not has_function_privilege('authenticated', 'registar_atendimento(uuid, text, jsonb, text)', 'execute'),
          'limite de mensagens por dia; interruptor desligado = parado; as ferramentas só o serviço as chama');

select * from finish();
rollback;
