-- Os endereços dos clientes passam a ficar na auditoria: criação e alteração, incluindo o apagar
-- (que é um update de deletado_em). Usa o mesmo gatilho genérico das outras tabelas auditadas.
create trigger trg_auditar after insert or update on enderecos_cliente
for each row execute function auditar_alteracao_tabela();
