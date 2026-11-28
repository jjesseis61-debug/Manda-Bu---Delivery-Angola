-- Teste de segurança (arrumação): tirar ao papel anónimo as concessões nas 5 tabelas do menu que
-- ficaram com GRANT ALL por defeito (cardapio, opcoes, opcoes_grupos, pacotes, cozinhas_localizacao).
-- Já hoje o anónimo não lê nada delas (não há política de leitura para o anónimo), por isso isto não
-- muda o comportamento — só remove a superfície a mais, alinhando com as outras tabelas (ex.: pedidos,
-- onde o anónimo não tem concessões). O papel authenticated fica como está: a equipa gere o menu.
revoke all on cardapio            from anon;
revoke all on opcoes              from anon;
revoke all on opcoes_grupos       from anon;
revoke all on pacotes             from anon;
revoke all on cozinhas_localizacao from anon;
