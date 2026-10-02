-- Políticas RLS das tabelas base (pendente desde a I1, secção 8 do plano).
--
-- As 16 tabelas base tinham RLS activo sem políticas: só o servidor lhes
-- chegava. Abrem-se agora às apps do operador por permissão do organograma.
-- Os clientes continuam sem acesso directo (usam as funções do servidor).
--
-- Regras gerais:
--  * Tabelas com cozinha_id: além da permissão, o funcionário tem de ser da
--    cozinha (tem um turno lá) ou ter cozinhas.gerir. O administrador
--    principal tem todas as permissões.
--  * Append-only (vendas, movimentos de stock, pagamentos de crédito,
--    refeições, auditoria): sem política de UPDATE nem de DELETE.
--  * Nenhuma tabela tem política de DELETE: apaga-se com deletado_em.
--  * notificacoes_fila e contadores_zona continuam só do servidor.

-- -----------------------------------------------------------------------------
-- 1. Permissões novas no catálogo
-- -----------------------------------------------------------------------------
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'vendas.registar', 'Vendas e caixa',
   'Registar vendas, pré-encomendas, pedidos especiais e refeições da equipa; abrir e fechar a caixa'),
  ('servidor', 'stock.gerir', 'Stock',
   'Produtos, entradas e consumos de stock, distribuições para as cozinhas'),
  ('servidor', 'financas.gerir', 'Finanças',
   'Custos, limite de crédito e desconto dos clientes, notas de crédito'),
  ('servidor', 'clientes.gerir', 'Clientes',
   'Registar e editar os clientes do balcão'),
  ('servidor', 'equipa.gerir', 'Equipa',
   'Turnos e refeições da equipa'),
  ('servidor', 'auditoria.ver', 'Plataforma',
   'Consultar a auditoria')
on conflict (chave) do nothing;

-- -----------------------------------------------------------------------------
-- 2. Funções de apoio às políticas
-- -----------------------------------------------------------------------------
create or replace function e_administrador() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select administrador_principal from funcionarios
                    where id = funcionario_actual()), false);
$$;

-- Permissão p na cozinha c: sem cozinha (linha geral), ou membro da cozinha,
-- ou quem gere as cozinhas (inclui o administrador principal)
create or replace function pode_na_cozinha(p text, c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select tem_permissao(p)
     and (c is null or tem_permissao('cozinhas.gerir') or membro_da_cozinha(c));
$$;

revoke execute on function e_administrador()          from public, anon;
revoke execute on function pode_na_cozinha(text, uuid) from public, anon;
grant  execute on function e_administrador()          to authenticated;
grant  execute on function pode_na_cozinha(text, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Políticas
-- -----------------------------------------------------------------------------

-- auditoria: append-only e imutável (trigger auditoria_imutavel). Qualquer
-- funcionário regista as suas acções; só auditoria.ver consulta.
create policy ler on auditoria for select to authenticated
  using (tem_permissao('auditoria.ver'));
create policy criar on auditoria for insert to authenticated
  with check (e_funcionario() and funcionario_id = funcionario_actual() and not coalesce(bloqueado, false));

-- caixa: last-write-wins por posto+data (a leitura já existia desde a I3)
create policy criar on caixa for insert to authenticated
  with check (pode_na_cozinha('vendas.registar', cozinha_id) or pode_na_cozinha('entregas.registar', cozinha_id));
create policy editar on caixa for update to authenticated
  using (pode_na_cozinha('vendas.registar', cozinha_id) or pode_na_cozinha('entregas.registar', cozinha_id))
  with check (pode_na_cozinha('vendas.registar', cozinha_id) or pode_na_cozinha('entregas.registar', cozinha_id));

-- clientes: o balcão lê e regista; limite de crédito e desconto só com
-- financas.gerir (trigger abaixo); a ligação à conta (auth_user_id) só pelo servidor
create policy ler on clientes for select to authenticated
  using (tem_permissao('clientes.gerir') or tem_permissao('vendas.registar') or tem_permissao('financas.gerir'));
create policy criar on clientes for insert to authenticated
  with check (tem_permissao('clientes.gerir') and auth_user_id is null);
create policy editar on clientes for update to authenticated
  using (tem_permissao('clientes.gerir') or tem_permissao('financas.gerir'))
  with check (tem_permissao('clientes.gerir') or tem_permissao('financas.gerir'));

create or replace function clientes_proteger_campos() returns trigger
language plpgsql set search_path = public as $$
begin
  -- Só as escritas das apps; as funções do servidor (registar_cliente, …) passam
  if not e_escrita_cliente() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.auth_user_id is not null then
      raise exception 'campo_reservado' using errcode = '42501';
    end if;
    if (coalesce(new.limite_credito, 0) <> 0 or coalesce(new.desconto, 0) <> 0)
       and not tem_permissao('financas.gerir') then
      raise exception 'sem_permissao' using errcode = '42501';
    end if;
    return new;
  end if;
  if new.auth_user_id is distinct from old.auth_user_id then
    raise exception 'campo_reservado' using errcode = '42501';
  end if;
  if (new.limite_credito is distinct from old.limite_credito or new.desconto is distinct from old.desconto)
     and not tem_permissao('financas.gerir') then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if (new.tipo, new.nome, new.telefone, new.nif, new.pessoa_contacto, new.deletado_em)
     is distinct from (old.tipo, old.nome, old.telefone, old.nif, old.pessoa_contacto, old.deletado_em)
     and not tem_permissao('clientes.gerir') then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger trg_clientes_proteger_campos
before insert or update on clientes
for each row execute function clientes_proteger_campos();
revoke execute on function clientes_proteger_campos() from public, anon, authenticated;

-- custos: só finanças
create policy ler on custos for select to authenticated using (tem_permissao('financas.gerir'));
create policy criar on custos for insert to authenticated with check (tem_permissao('financas.gerir'));
create policy editar on custos for update to authenticated
  using (tem_permissao('financas.gerir')) with check (tem_permissao('financas.gerir'));

-- direcoes e funcionarios (organograma): só o administrador principal escreve.
-- Cada funcionário lê a sua ficha; a equipa inteira só quem gere a equipa.
create policy ler on direcoes for select to authenticated using (e_funcionario());
create policy criar on direcoes for insert to authenticated with check (e_administrador());
create policy editar on direcoes for update to authenticated
  using (e_administrador()) with check (e_administrador());

create policy ler on funcionarios for select to authenticated
  using (id = funcionario_actual() or e_administrador() or tem_permissao('equipa.gerir'));
create policy criar on funcionarios for insert to authenticated with check (e_administrador());
create policy editar on funcionarios for update to authenticated
  using (e_administrador()) with check (e_administrador());

-- distribuicoes: criação append-only; depois só avança o recebimento, a
-- devolução e a quebra (privilégio por coluna)
create policy ler on distribuicoes for select to authenticated
  using (pode_na_cozinha('stock.gerir', cozinha_id));
create policy criar on distribuicoes for insert to authenticated
  with check (pode_na_cozinha('stock.gerir', cozinha_id));
create policy editar on distribuicoes for update to authenticated
  using (pode_na_cozinha('stock.gerir', cozinha_id))
  with check (pode_na_cozinha('stock.gerir', cozinha_id));
revoke update on distribuicoes from authenticated;
grant update (status, recebido_por, hora_recebimento, quantidade_devolvida, historico_devolucoes,
              quantidade_quebra, historico_quebras, atualizado_em, dispositivo_id)
  on distribuicoes to authenticated;

-- movimentos de stock: append-only. Os consumos das vendas App cliente
-- continuam a ser descartados pelo trigger de guarda (I1).
create policy ler on estoque_diario for select to authenticated
  using (pode_na_cozinha('stock.gerir', cozinha_id));
create policy criar on estoque_diario for insert to authenticated
  with check (pode_na_cozinha('stock.gerir', cozinha_id));

create policy ler on estoque_longo_prazo for select to authenticated
  using (pode_na_cozinha('stock.gerir', cozinha_id));
create policy criar on estoque_longo_prazo for insert to authenticated
  with check (pode_na_cozinha('stock.gerir', cozinha_id));

-- locais e produtos: cadastros lidos por toda a equipa
create policy ler on locais for select to authenticated using (e_funcionario());
create policy criar on locais for insert to authenticated with check (tem_permissao('cozinhas.gerir'));
create policy editar on locais for update to authenticated
  using (tem_permissao('cozinhas.gerir')) with check (tem_permissao('cozinhas.gerir'));

create policy ler on produtos for select to authenticated using (e_funcionario());
create policy criar on produtos for insert to authenticated with check (tem_permissao('stock.gerir'));
create policy editar on produtos for update to authenticated
  using (tem_permissao('stock.gerir')) with check (tem_permissao('stock.gerir'));

-- pagamentos de crédito: append-only; o balcão recebe pagamentos, as notas
-- de crédito são das finanças
create policy ler on pagamentos_credito for select to authenticated
  using (tem_permissao('vendas.registar') or tem_permissao('financas.gerir'));
create policy criar on pagamentos_credito for insert to authenticated
  with check (tem_permissao('financas.gerir')
              or (tem_permissao('vendas.registar') and coalesce(origem, '') not ilike 'nota%'));

-- pré-encomendas e pedidos especiais: o balcão da cozinha
create policy ler on pre_encomendas for select to authenticated
  using (pode_na_cozinha('vendas.registar', cozinha_id));
create policy criar on pre_encomendas for insert to authenticated
  with check (pode_na_cozinha('vendas.registar', cozinha_id));
create policy editar on pre_encomendas for update to authenticated
  using (pode_na_cozinha('vendas.registar', cozinha_id))
  with check (pode_na_cozinha('vendas.registar', cozinha_id));

create policy ler on pedidos_especiais for select to authenticated
  using (pode_na_cozinha('vendas.registar', cozinha_id));
create policy criar on pedidos_especiais for insert to authenticated
  with check (pode_na_cozinha('vendas.registar', cozinha_id));
create policy editar on pedidos_especiais for update to authenticated
  using (pode_na_cozinha('vendas.registar', cozinha_id))
  with check (pode_na_cozinha('vendas.registar', cozinha_id));

-- refeições da equipa: append-only; cada um vê as suas
create policy ler on refeicoes_funcionarios for select to authenticated
  using (funcionario_id = funcionario_actual() or tem_permissao('equipa.gerir') or tem_permissao('vendas.registar'));
create policy criar on refeicoes_funcionarios for insert to authenticated
  with check (tem_permissao('equipa.gerir') or tem_permissao('vendas.registar'));

-- turnos: cada um vê os seus e os da sua cozinha; quem gere a equipa escreve
create policy ler on turnos for select to authenticated
  using (funcionario_id = funcionario_actual() or membro_da_cozinha(cozinha_id)
         or pode_na_cozinha('equipa.gerir', cozinha_id));
create policy criar on turnos for insert to authenticated
  with check (pode_na_cozinha('equipa.gerir', cozinha_id));
create policy editar on turnos for update to authenticated
  using (pode_na_cozinha('equipa.gerir', cozinha_id))
  with check (pode_na_cozinha('equipa.gerir', cozinha_id));

-- vendas: append-only. As vendas dos pedidos da app são só do servidor.
create policy ler on vendas for select to authenticated
  using (pode_na_cozinha('vendas.registar', cozinha_id) or pode_na_cozinha('relatorios.exportar', cozinha_id)
         or tem_permissao('financas.gerir'));
create policy criar on vendas for insert to authenticated
  with check (pode_na_cozinha('vendas.registar', cozinha_id)
              and pedido_id is null and origem is distinct from 'App cliente');
