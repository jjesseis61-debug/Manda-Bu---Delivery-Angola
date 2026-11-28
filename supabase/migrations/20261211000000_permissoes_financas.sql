-- Permissões de finanças separadas por área: cada ecrã de finanças passa a ter a sua permissão,
-- para se poder dar, por exemplo, o pagamento dos estafetas sem mostrar os resultados do mês.
-- financas.conferir fica só para a conferência (fecho do dia e do mês, extratos, comprovativos).
-- Quem já tinha financas.conferir recebe as permissões novas (não perde nada).

insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'financas.acertos',         'Finanças', 'Acertos semanais com as cozinhas: fechar, fatura e pagamentos'),
  ('servidor', 'financas.faturas',         'Finanças', 'Registar o número da fatura das vendas e quem a emite'),
  ('servidor', 'financas.compensacoes',    'Finanças', 'Compensações aos clientes: a cargo de quem e pagamento'),
  ('servidor', 'financas.empresas',        'Finanças', 'Contas das empresas (B2B): fatura do mês e pagamento'),
  ('servidor', 'financas.estafetas',       'Finanças', 'Pagamento dos estafetas: salário, valor por dia e por entrega'),
  ('servidor', 'financas.servico_entregas','Finanças', 'Serviço de entregas contratado: valores, zonas e pagamento'),
  ('servidor', 'financas.resultados',      'Finanças', 'Ver os resultados do mês (receitas, custos e resultado)'),
  ('servidor', 'financas.obrigacoes',      'Finanças', 'Ver as obrigações e a tesouraria (o que se deve e o que se tem a receber)')
on conflict (chave) do update set grupo = excluded.grupo, descricao = excluded.descricao, deletado_em = null, atualizado_em = now();

update permissoes set descricao = 'Conferência: fecho do dia e do mês, extratos e comprovativos', atualizado_em = now()
 where chave = 'financas.conferir';

-- Quem já tinha financas.conferir fica com as novas
update funcionarios
   set permissoes_extra = permissoes_extra || jsonb_build_object(
         'financas.acertos', true, 'financas.faturas', true, 'financas.compensacoes', true, 'financas.empresas', true,
         'financas.estafetas', true, 'financas.servico_entregas', true, 'financas.resultados', true, 'financas.obrigacoes', true),
       atualizado_em = now()
 where deletado_em is null and coalesce((permissoes_extra ->> 'financas.conferir')::boolean, false);

update direcoes
   set permissoes = permissoes || jsonb_build_object(
         'financas.acertos', true, 'financas.faturas', true, 'financas.compensacoes', true, 'financas.empresas', true,
         'financas.estafetas', true, 'financas.servico_entregas', true, 'financas.resultados', true, 'financas.obrigacoes', true),
       atualizado_em = now()
 where deletado_em is null and coalesce((permissoes ->> 'financas.conferir')::boolean, false);

-- Cada função passa a pedir a permissão da sua área (o resto da função fica igual)
do $$
declare
  m record;
  f record;
begin
  for m in select * from (values
      ('acertos_semana', 'financas.acertos'), ('conta_corrente_cozinha', 'financas.acertos'),
      ('definir_fatura_acerto', 'financas.acertos'), ('fechar_acerto', 'financas.acertos'),
      ('registar_pagamento_acerto', 'financas.acertos'), ('job_acertos_semana', 'financas.acertos'),
      ('vendas_sem_fatura', 'financas.faturas'), ('registar_fatura_pedido', 'financas.faturas'),
      ('definir_faturacao_cozinha', 'financas.faturas'),
      ('compensacoes_lista', 'financas.compensacoes'), ('definir_cargo_compensacao', 'financas.compensacoes'),
      ('pagar_compensacao', 'financas.compensacoes'),
      ('contas_empresas', 'financas.empresas'), ('emitir_fatura_empresa', 'financas.empresas'),
      ('pagar_fatura_empresa', 'financas.empresas'),
      ('estafetas_pagamentos', 'financas.estafetas'), ('definir_remuneracao_estafeta', 'financas.estafetas'),
      ('definir_dias_estafeta', 'financas.estafetas'), ('pagar_estafeta_mes', 'financas.estafetas'),
      ('fornecedores_entrega_lista', 'financas.servico_entregas'), ('guardar_fornecedor_entrega', 'financas.servico_entregas'),
      ('pagar_fornecedor_entrega', 'financas.servico_entregas'),
      ('resultados_mes', 'financas.resultados'),
      ('obrigacoes_resumo', 'financas.obrigacoes')) as t(nome, chave)
  loop
    for f in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = m.nome loop
      execute replace(pg_get_functiondef(f.oid), 'financas.conferir', m.chave);
    end loop;
  end loop;
end $$;

-- As fotos dos pagamentos dos acertos (acertos/<id>/...) também se vêem com financas.acertos
create or replace function comprovativo_visivel(p_nome text) returns boolean
language sql stable security definer set search_path = public as $$
  select tem_permissao('pedidos.gerir') or tem_permissao('financas.conferir')
      or (split_part(p_nome, '/', 1) = 'acertos' and tem_permissao('financas.acertos'))
      or exists (select 1 from pedidos x where x.id::text = split_part(p_nome, '/', 1)
                    and pode_na_cozinha('vendas.registar', x.cozinha_id));
$$;

drop policy if exists comprovativos_acertos_enviar on storage.objects;
create policy comprovativos_acertos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'comprovativos' and (select tem_permissao('financas.acertos')) and acerto_caminho_valido(name));
