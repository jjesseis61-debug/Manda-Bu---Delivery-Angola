-- Supabase Realtime: expõe as mudanças da tabela `pedidos` para a app actualizar o estado do
-- pedido ao vivo (sem esperar o refrescar). O Realtime respeita a RLS — cada cliente só recebe
-- as mudanças dos SEUS pedidos (a política de leitura de pedidos já garante isto).
--
-- Complementa (não substitui) o push: o Realtime só actualiza com a app aberta; o push (FCM)
-- é que chega com a app fechada. Aqui tratamos só do "ao vivo dentro da app".
--
-- Defensivo: cria a publicação se não existir (ambiente de teste local) e só adiciona a tabela
-- uma vez (em produção a publicação supabase_realtime já existe).
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedidos'
  ) then
    alter publication supabase_realtime add table pedidos;
  end if;
end $$;
