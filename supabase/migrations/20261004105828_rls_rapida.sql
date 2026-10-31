-- Regras de acesso (RLS) rápidas com muitos dados (encontrado no teste de 12 meses).
-- As funções da sessão (cliente_actual, e_funcionario, funcionario_actual, e_administrador, auth.uid,
-- tem_permissao e funcionalidade_activa com texto fixo) eram chamadas uma vez POR LINHA: com 71 mil
-- pedidos, um cliente esperava 8,6 s para ver os seus. Dentro de (select …) o Postgres calcula-as uma
-- vez por consulta (InitPlan) e o resultado é o mesmo: 0,04 s. As chamadas que dependem da linha
-- (pode_na_cozinha(…, cozinha_id), membro_da_cozinha(cozinha_id), …) ficam como estavam.
-- 93 regras.

alter policy "ler" on public.adesoes_pacote
  using (((cliente_id = (select cliente_actual())) OR (select tem_permissao('pacotes.gerir'))));

alter policy "ler" on public.alertas_pedido
  using (((deletado_em IS NULL) AND ((cliente_id = (select cliente_actual())) OR (select tem_permissao('pedidos.gerir')) OR pode_na_cozinha('vendas.registar'::text, cozinha_id) OR (EXISTS ( SELECT 1
   FROM pedidos x
  WHERE ((x.id = alertas_pedido.pedido_id) AND (x.entregador_id IS NOT NULL) AND (x.entregador_id = (select funcionario_actual()))))))));

alter policy "criar" on public.auditoria
  with check (((select e_funcionario()) AND (funcionario_id = (select funcionario_actual())) AND (NOT COALESCE(bloqueado, false))));

alter policy "ler" on public.auditoria
  using ((select tem_permissao('auditoria.ver')));

alter policy "criar" on public.avaliacoes
  with check (((cliente_id = (select cliente_actual())) AND avaliacao_permitida(pedido_id)));

alter policy "ler" on public.avaliacoes
  using (((cliente_id = (select cliente_actual())) OR (select e_funcionario())));

alter policy "criar" on public.avaliacoes_pratos
  with check ((EXISTS ( SELECT 1
   FROM avaliacoes a
  WHERE ((a.id = avaliacoes_pratos.avaliacao_id) AND (a.cliente_id = (select cliente_actual()))))));

alter policy "ler" on public.caixa
  using (((deletado_em IS NULL) AND ((select tem_permissao('vendas.registar')) OR (select tem_permissao('entregas.registar')) OR (select tem_permissao('pedidos.gerir')))));

alter policy "criar" on public.cardapio
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "editar" on public.cardapio
  using ((select tem_permissao('cozinhas.gerir')))
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "ler" on public.casos_convida
  using (((deletado_em IS NULL) AND (select tem_permissao('indicacoes.verificar'))));

alter policy "ler" on public.casos_investigacao
  using (((deletado_em IS NULL) AND (select tem_permissao('financas.conferir')) AND ((funcionario_id IS DISTINCT FROM (select funcionario_actual())) OR (select e_administrador()))));

alter policy "criar" on public.clientes
  with check (((select tem_permissao('clientes.gerir')) AND (auth_user_id IS NULL)));

alter policy "editar" on public.clientes
  using (((select tem_permissao('clientes.gerir')) OR (select tem_permissao('financas.gerir'))))
  with check (((select tem_permissao('clientes.gerir')) OR (select tem_permissao('financas.gerir'))));

alter policy "ler" on public.clientes
  using (((select tem_permissao('clientes.gerir')) OR (select tem_permissao('vendas.registar')) OR (select tem_permissao('financas.gerir'))));

alter policy "ler" on public.codigos_indicacao
  using (((cliente_id = (select cliente_actual())) OR (select tem_permissao('indicacoes.ver'))));

alter policy "ler" on public.comprovativos_pagamento
  using (((deletado_em IS NULL) AND (pode_na_cozinha('vendas.registar'::text, cozinha_id) OR (select tem_permissao('pedidos.gerir')) OR (select tem_permissao('financas.conferir')))));

alter policy "ler" on public.conversas_atendimento
  using (((deletado_em IS NULL) AND ((cliente_id = (select cliente_actual())) OR (select tem_permissao('atendimento.responder')))));

alter policy "criar" on public.cozinhas
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "editar" on public.cozinhas
  using ((select tem_permissao('cozinhas.gerir')))
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "ler_publicas" on public.cozinhas
  using ((((estado = 'activa'::text) AND consentimento_publico AND (deletado_em IS NULL)) OR (select e_funcionario())));

alter policy "criar" on public.cozinhas_localizacao
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "editar" on public.cozinhas_localizacao
  using ((select tem_permissao('cozinhas.gerir')))
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "ler" on public.cozinhas_localizacao
  using ((select e_funcionario()));

alter policy "criar" on public.custos
  with check ((select tem_permissao('financas.gerir')));

alter policy "editar" on public.custos
  using ((select tem_permissao('financas.gerir')))
  with check ((select tem_permissao('financas.gerir')));

alter policy "ler" on public.custos
  using ((select tem_permissao('financas.gerir')));

alter policy "criar" on public.direcoes
  with check ((select e_administrador()));

alter policy "editar" on public.direcoes
  using ((select e_administrador()))
  with check ((select e_administrador()));

alter policy "ler" on public.direcoes
  using ((select e_funcionario()));

alter policy "criar" on public.enderecos_cliente
  with check ((cliente_id = (select cliente_actual())));

alter policy "editar" on public.enderecos_cliente
  using ((cliente_id = (select cliente_actual())))
  with check ((cliente_id = (select cliente_actual())));

alter policy "ler" on public.enderecos_cliente
  using (((cliente_id = (select cliente_actual())) OR (select e_funcionario())));

alter policy "ler" on public.estimulos_mensais
  using (((deletado_em IS NULL) AND ((select tem_permissao('equipa.gerir')) OR ((estado = 'aprovado'::text) AND (funcionario_id IS NOT NULL) AND (funcionario_id = (select funcionario_actual()))))));

alter policy "ler" on public.extrato_movimentos
  using (((deletado_em IS NULL) AND (select tem_permissao('financas.conferir'))));

alter policy "ler" on public.extratos
  using (((deletado_em IS NULL) AND (select tem_permissao('financas.conferir'))));

alter policy "criar" on public.fotos_avaliacao
  with check (((select funcionalidade_activa('avaliacoes_fotos')) AND (EXISTS ( SELECT 1
   FROM avaliacoes a
  WHERE ((a.id = fotos_avaliacao.avaliacao_id) AND (a.cliente_id = (select cliente_actual())))))));

alter policy "ler" on public.fotos_avaliacao
  using (((estado = 'aprovada'::text) OR (EXISTS ( SELECT 1
   FROM avaliacoes a
  WHERE ((a.id = fotos_avaliacao.avaliacao_id) AND (a.cliente_id = (select cliente_actual()))))) OR (select tem_permissao('avaliacoes.moderar'))));

alter policy "criar" on public.funcionarios
  with check ((select e_administrador()));

alter policy "editar" on public.funcionarios
  using ((select e_administrador()))
  with check ((select e_administrador()));

alter policy "ler" on public.funcionarios
  using (((id = (select funcionario_actual())) OR (select e_administrador()) OR (select tem_permissao('equipa.gerir'))));

alter policy "ler" on public.ganhos_indicacao
  using (((indicador_id = (select cliente_actual())) OR (select tem_permissao('indicacoes.ver')) OR (select tem_permissao('indicacoes.verificar'))));

alter policy "ler" on public.ligacoes_indicacao
  using (((indicador_id = (select cliente_actual())) OR (indicado_id = (select cliente_actual())) OR (select tem_permissao('indicacoes.ver'))));

alter policy "criar" on public.locais
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "editar" on public.locais
  using ((select tem_permissao('cozinhas.gerir')))
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "ler" on public.locais
  using ((select e_funcionario()));

alter policy "ler" on public.mensagens_atendimento
  using (((deletado_em IS NULL) AND (EXISTS ( SELECT 1
   FROM conversas_atendimento c
  WHERE ((c.id = mensagens_atendimento.conversa_id) AND ((c.cliente_id = (select cliente_actual())) OR (select tem_permissao('atendimento.responder'))))))));

alter policy "criar" on public.opcoes
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "editar" on public.opcoes
  using ((select tem_permissao('cozinhas.gerir')))
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "ler" on public.opcoes
  using (((deletado_em IS NULL) OR (select tem_permissao('cozinhas.gerir'))));

alter policy "criar" on public.opcoes_grupos
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "editar" on public.opcoes_grupos
  using ((select tem_permissao('cozinhas.gerir')))
  with check ((select tem_permissao('cozinhas.gerir')));

alter policy "ler" on public.opcoes_grupos
  using (((deletado_em IS NULL) OR (select tem_permissao('cozinhas.gerir'))));

alter policy "criar" on public.pacotes
  with check ((select tem_permissao('pacotes.gerir')));

alter policy "editar" on public.pacotes
  using ((select tem_permissao('pacotes.gerir')))
  with check ((select tem_permissao('pacotes.gerir')));

alter policy "ler" on public.pacotes
  using (((activo AND (deletado_em IS NULL)) OR (select e_funcionario())));

alter policy "criar" on public.pagamentos_credito
  with check (((select tem_permissao('financas.gerir')) OR ((select tem_permissao('vendas.registar')) AND (COALESCE(origem, ''::text) !~~* 'nota%'::text))));

alter policy "ler" on public.pagamentos_credito
  using (((select tem_permissao('vendas.registar')) OR (select tem_permissao('financas.gerir'))));

alter policy "ler" on public.pagamentos_indicacao
  using (((indicador_id = (select cliente_actual())) OR (select tem_permissao('indicacoes.ver')) OR (select tem_permissao('indicacoes.aprovar_pagamentos'))));

alter policy "moderar" on public.palavras_filtradas
  using ((select tem_permissao('avaliacoes.moderar')))
  with check ((select tem_permissao('avaliacoes.moderar')));

alter policy "criar" on public.pedidos
  with check (((cliente_id = (select cliente_actual())) OR (select tem_permissao('pedidos.gerir'))));

alter policy "editar_operador" on public.pedidos
  using ((select tem_permissao('pedidos.gerir')))
  with check ((select tem_permissao('pedidos.gerir')));

alter policy "ler" on public.pedidos
  using (((cliente_id = (select cliente_actual())) OR (select e_funcionario())));

alter policy "criar" on public.pedidos_grupo
  with check (((select funcionalidade_activa('pedidos_grupo')) AND ((select cliente_actual()) IS NOT NULL)));

alter policy "editar" on public.pedidos_grupo
  using (((organizador_id = (select cliente_actual())) OR (select tem_permissao('pedidos.gerir'))))
  with check (((organizador_id = (select cliente_actual())) OR (select tem_permissao('pedidos.gerir'))));

alter policy "ler" on public.pedidos_grupo
  using (((organizador_id = (select cliente_actual())) OR (EXISTS ( SELECT 1
   FROM pedidos x
  WHERE ((x.grupo_id = pedidos_grupo.id) AND (x.cliente_id = (select cliente_actual()))))) OR (select e_funcionario())));

alter policy "editar" on public.perfil_destaques
  using ((cliente_id = (select cliente_actual())))
  with check ((cliente_id = (select cliente_actual())));

alter policy "ler" on public.perfil_destaques
  using (((cliente_id = (select cliente_actual())) OR (select e_funcionario())));

alter policy "ler" on public.perguntas_analista
  using (((deletado_em IS NULL) AND (select tem_permissao('analista.usar')) AND ((funcionario_id IS NULL) OR (funcionario_id = (select funcionario_actual())) OR (select e_administrador()))));

alter policy "criar" on public.pontos_entrega
  with check ((((select cliente_actual()) IS NOT NULL) AND (zona_id IS NOT NULL)));

alter policy "editar" on public.pontos_entrega
  using ((criado_por_cliente = (select cliente_actual())))
  with check ((criado_por_cliente = (select cliente_actual())));

alter policy "ler" on public.pontos_entrega
  using (((criado_por_cliente = (select cliente_actual())) OR (EXISTS ( SELECT 1
   FROM enderecos_cliente e
  WHERE ((e.ponto_entrega_id = pontos_entrega.id) AND (e.cliente_id = (select cliente_actual()))))) OR (select e_funcionario())));

alter policy "editar" on public.preferencias_notificacao
  using ((cliente_id = (select cliente_actual())))
  with check ((cliente_id = (select cliente_actual())));

alter policy "ler" on public.preferencias_notificacao
  using ((cliente_id = (select cliente_actual())));

alter policy "criar" on public.produtos
  with check ((select tem_permissao('stock.gerir')));

alter policy "editar" on public.produtos
  using ((select tem_permissao('stock.gerir')))
  with check ((select tem_permissao('stock.gerir')));

alter policy "ler" on public.produtos
  using ((select e_funcionario()));

alter policy "ler" on public.reclamacoes
  using (((deletado_em IS NULL) AND ((select tem_permissao('clientes.gerir')) OR pode_na_cozinha('pedidos.gerir'::text, cozinha_id))));

alter policy "criar" on public.reconhecimentos_turno
  with check ((select tem_permissao('equipa.reconhecer')));

alter policy "ler" on public.reconhecimentos_turno
  using (((select tem_permissao('equipa.reconhecer')) OR membro_da_cozinha(cozinha_id)));

alter policy "criar" on public.refeicoes_funcionarios
  with check (((select tem_permissao('equipa.gerir')) OR (select tem_permissao('vendas.registar'))));

alter policy "ler" on public.refeicoes_funcionarios
  using (((funcionario_id = (select funcionario_actual())) OR (select tem_permissao('equipa.gerir')) OR (select tem_permissao('vendas.registar'))));

alter policy "ler" on public.turnos
  using (((funcionario_id = (select funcionario_actual())) OR membro_da_cozinha(cozinha_id) OR pode_na_cozinha('equipa.gerir'::text, cozinha_id)));

alter policy "ler" on public.vendas
  using ((pode_na_cozinha('vendas.registar'::text, cozinha_id) OR pode_na_cozinha('relatorios.exportar'::text, cozinha_id) OR (select tem_permissao('financas.gerir'))));

alter policy "criar" on public.zonas
  with check ((select tem_permissao('plataforma.parametros')));

alter policy "editar" on public.zonas
  using ((select tem_permissao('plataforma.parametros')))
  with check ((select tem_permissao('plataforma.parametros')));

alter policy "comprovativos_enviar" on storage.objects
  with check (((bucket_id = 'comprovativos'::text) AND ((select tem_permissao('entregas.registar')) OR (select tem_permissao('pedidos.gerir'))) AND comprovativo_caminho_valido(name)));

alter policy "comprovativos_ler" on storage.objects
  using (((bucket_id = 'comprovativos'::text) AND ((owner = (select auth.uid())) OR comprovativo_visivel(name))));

alter policy "extratos_enviar" on storage.objects
  with check (((bucket_id = 'extratos'::text) AND (select tem_permissao('financas.conferir')) AND extrato_caminho_valido(name)));

alter policy "extratos_ler" on storage.objects
  using (((bucket_id = 'extratos'::text) AND (select tem_permissao('financas.conferir'))));

alter policy "fotos_pratos_apagar" on storage.objects
  using (((bucket_id = 'fotos-pratos'::text) AND (select tem_permissao('cozinhas.gerir'))));

alter policy "fotos_pratos_enviar" on storage.objects
  with check (((bucket_id = 'fotos-pratos'::text) AND (select tem_permissao('cozinhas.gerir')) AND foto_prato_caminho_valido(name)));

alter policy "fotos_pratos_trocar" on storage.objects
  using (((bucket_id = 'fotos-pratos'::text) AND (select tem_permissao('cozinhas.gerir'))))
  with check (((bucket_id = 'fotos-pratos'::text) AND (select tem_permissao('cozinhas.gerir')) AND foto_prato_caminho_valido(name)));
