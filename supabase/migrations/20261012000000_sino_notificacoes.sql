-- Sino de notificações do funcionário: um histórico das notificações DENTRO da app (além do push),
-- com estado de "vista" e contador de novas. Rede de segurança para quando o push falha ou passa
-- despercebido: o operador abre o sino e vê tudo (Novo pedido, alertas, avisos...).

alter table notificacoes_fila add column vista_em timestamptz;
create index notificacoes_fila_funcionario_novas_idx
  on notificacoes_fila (funcionario_id, criado_em desc)
  where funcionario_id is not null and deletado_em is null;

-- As minhas notificações (as do funcionário autenticado), já com o texto renderizado.
create or replace function minhas_notificacoes(p_limite int default 30)
returns table (id uuid, codigo text, titulo text, corpo text, dados jsonb,
               criado_em timestamptz, vista_em timestamptz)
language sql stable security definer set search_path = public as $$
  select n.id, n.codigo, t.titulo, t.corpo, n.dados, n.criado_em, n.vista_em
    from notificacoes_fila n
    cross join lateral texto_notificacao(n.codigo, n.dados) t
   where n.funcionario_id = funcionario_actual() and n.deletado_em is null
   order by n.criado_em desc
   limit greatest(1, least(coalesce(p_limite, 30), 100));
$$;

-- Quantas novas (não vistas) — para o badge do sino.
create or replace function contar_notificacoes_novas()
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from notificacoes_fila
   where funcionario_id = funcionario_actual() and deletado_em is null and vista_em is null;
$$;

-- Marcar como vistas (p_ids null = todas as não vistas); devolve quantas marcou.
create or replace function marcar_notificacoes_vistas(p_ids uuid[] default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v int;
begin
  update notificacoes_fila set vista_em = now(), atualizado_em = now()
   where funcionario_id = funcionario_actual() and deletado_em is null and vista_em is null
     and (p_ids is null or id = any(p_ids));
  get diagnostics v = row_count;
  return v;
end $$;

revoke execute on function minhas_notificacoes(int), contar_notificacoes_novas(),
                           marcar_notificacoes_vistas(uuid[]) from public, anon;
grant  execute on function minhas_notificacoes(int), contar_notificacoes_novas(),
                           marcar_notificacoes_vistas(uuid[]) to authenticated;
