-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I1 · Endurecimento
--
-- Correcções aos avisos do Supabase (Database Advisors) depois de aplicar
-- modelo_base, crescimento_i1 e crescimento_i1_ajustes:
--   1. search_path fixo em todas as funções (lint 0011).
--   2. Funções de trigger sem EXECUTE para anon/authenticated (lints 0028/0029):
--      só correm como triggers. Funções auxiliares usadas apenas dentro de
--      funções do servidor deixam de ser chamáveis pelas apps.
--   3. Índices em todas as chaves estrangeiras (lint 0001).
--   4. Corrige o nome do índice de vendas.local, renomeado por engano na
--      migração de ajustes (vendas_local_idx contém "local_id").
-- =============================================================================

-- 1. search_path fixo
alter function distancia_m(float8, float8, float8, float8) set search_path = public;
alter function inicio_semana_luanda()                      set search_path = public;
alter function inicio_dia_luanda()                         set search_path = public;
alter function inicio_mes_luanda()                         set search_path = public;
alter function hoje_luanda()                               set search_path = public;
alter function normalizar_telefone(text)                   set search_path = public;
alter function e_escrita_cliente()                         set search_path = public;
alter function transicao_estado_valida(text, text)         set search_path = public;
alter function funcionalidade_da_notificacao(text)         set search_path = public;
alter function auditoria_imutavel()                        set search_path = public;
alter function sync_receber()                              set search_path = public;
alter function bloquear_escrita_dispositivo()              set search_path = public;
alter function fotos_antes_inserir()                       set search_path = public;
alter function pedidos_grupo_antes_inserir()               set search_path = public;
alter function pontos_entrega_antes_inserir()              set search_path = public;
alter function pedidos_proteger_insercao()                 set search_path = public;
alter function pedidos_antes_actualizar()                  set search_path = public;
alter function reconhecimentos_antes_inserir()             set search_path = public;

-- 2. Funções de trigger: só correm como triggers (o EXECUTE só é verificado
--    ao criar o trigger, por isso retirá-lo não afecta o funcionamento)
do $$
declare
  f text;
begin
  foreach f in array array[
    'auditoria_imutavel()', 'sync_receber()', 'configuracao_alterada()', 'cliente_registado()',
    'pedidos_proteger_insercao()', 'calcular_desconto_indicacao()', 'pedidos_depois_inserir()',
    'pedidos_antes_actualizar()', 'processar_ganho_indicacao()', 'reverter_credito_pedido()',
    'gerar_venda_pedido()', 'validar_endereco_cliente()', 'pontos_entrega_antes_inserir()',
    'avaliacoes_antes_inserir()', 'fotos_antes_inserir()', 'pedidos_grupo_antes_inserir()',
    'reconhecimentos_antes_inserir()', 'reconhecimentos_depois_inserir()',
    'bloquear_escrita_dispositivo()',
    -- auxiliares usadas só dentro de funções security definer
    'mesmo_ponto_entrega(uuid,uuid)', 'exigir_permissao(text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
end $$;

-- 3. Índices nas chaves estrangeiras
create index if not exists avaliacoes_cliente_idx              on avaliacoes (cliente_id);
create index if not exists avaliacoes_pratos_prato_idx         on avaliacoes_pratos (prato_id);
create index if not exists distribuicoes_produto_idx           on distribuicoes (produto_id);
create index if not exists fotos_avaliacao_avaliacao_idx       on fotos_avaliacao (avaliacao_id);
create index if not exists funcionarios_direcao_idx            on funcionarios (direcao_id);
create index if not exists ganhos_indicacao_pagamento_idx      on ganhos_indicacao (pagamento_id);
create index if not exists ligacoes_indicacao_primeiro_idx     on ligacoes_indicacao (primeiro_pedido_id);
create index if not exists pagamentos_credito_cliente_idx      on pagamentos_credito (cliente_id);
create index if not exists pagamentos_indicacao_pedido_idx     on pagamentos_indicacao (pedido_id);
create index if not exists pedidos_zona_idx                    on pedidos (zona_id);
create index if not exists pedidos_especiais_cliente_idx       on pedidos_especiais (cliente_id);
create index if not exists pedidos_grupo_cozinha_idx           on pedidos_grupo (cozinha_id);
create index if not exists pedidos_grupo_empresa_idx           on pedidos_grupo (empresa_id);
create index if not exists pedidos_grupo_organizador_idx       on pedidos_grupo (organizador_id);
create index if not exists pedidos_grupo_ponto_entrega_idx     on pedidos_grupo (ponto_entrega_id);
create index if not exists pontos_entrega_criado_por_idx       on pontos_entrega (criado_por_cliente);
create index if not exists pre_encomendas_cliente_idx          on pre_encomendas (cliente_id);
create index if not exists refeicoes_funcionarios_func_idx     on refeicoes_funcionarios (funcionario_id);
create index if not exists turnos_funcionario_idx              on turnos (funcionario_id);
create index if not exists vendas_prato_base_idx               on vendas (prato_base_id);

-- 4. Nome correcto do índice de vendas.local (posto de venda)
alter index if exists vendas_ponto_entrega_idx rename to vendas_local_idx;
