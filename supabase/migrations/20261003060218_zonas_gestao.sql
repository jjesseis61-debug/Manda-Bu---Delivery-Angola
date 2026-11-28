-- Zonas de entrega (bairros) geridas pela app do operador.
-- Até aqui a tabela `zonas` só tinha leitura: sem zonas, o cliente não consegue guardar endereços
-- (o ecrã pede o bairro) e nenhum pedido tem taxa de entrega. Quem tem plataforma.parametros
-- cria, edita e apaga (deletado_em) zonas; as alterações ficam na auditoria.
-- Um ponto de entrega criado pelo cliente tem de ter zona (sem ela o orçamento recusa com
-- ponto_sem_zona depois de o endereço já estar guardado).

create policy criar on zonas for insert to authenticated
  with check (tem_permissao('plataforma.parametros'));
create policy editar on zonas for update to authenticated
  using (tem_permissao('plataforma.parametros')) with check (tem_permissao('plataforma.parametros'));

create trigger trg_auditar after insert or update on zonas
for each row execute function auditar_alteracao_tabela();

alter policy criar on pontos_entrega to authenticated
  with check (cliente_actual() is not null and zona_id is not null);
