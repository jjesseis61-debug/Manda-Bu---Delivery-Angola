-- Receitas R3: métricas (abrir -> pedir) e aviso de nova receita.
-- O aviso reutiliza a Central de Avisos (código N31, personalizado) com um link para a receita, por
-- isso não toca nas funções de texto/envio: basta o cliente passar a encaminhar pelo link.

-- 1. Métricas: a app conta quantos abrem a receita e quantos tocam em "Pedir" a partir dela.
create or replace function receita_abriu(p_id uuid) returns void
language sql security definer set search_path = public as $$
  update receitas set aberturas = aberturas + 1
   where id = p_id and estado = 'publicada' and deletado_em is null;
$$;

create or replace function receita_tocou_pedir(p_id uuid) returns void
language sql security definer set search_path = public as $$
  update receitas set toques_pedir = toques_pedir + 1
   where id = p_id and estado = 'publicada' and deletado_em is null;
$$;

revoke execute on function receita_abriu(uuid)       from public, anon;
revoke execute on function receita_tocou_pedir(uuid) from public, anon;
grant  execute on function receita_abriu(uuid)       to authenticated;
grant  execute on function receita_tocou_pedir(uuid) to authenticated;

-- 2. Aviso de nova receita a todos os clientes (push + sino). Exige receitas.gerir; reaproveita o
--    aviso personalizado N31 com um link para a receita (o cliente encaminha pelo link ao tocar).
create or replace function avisar_nova_receita(p_id uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_titulo text;
  v_n      integer := 0;
begin
  perform exigir_permissao('receitas.gerir');
  select titulo into v_titulo from receitas
   where id = p_id and estado = 'publicada' and deletado_em is null;
  if v_titulo is null then
    raise exception 'receita_nao_publicada' using errcode = 'P0001';
  end if;
  insert into notificacoes_fila (cliente_id, funcionario_id, codigo, dados)
  select d.cliente_id, null, 'N31',
         jsonb_build_object('titulo', 'Nova receita 🍲',
                            'corpo', v_titulo || ' — vê na Cozinha de casa.',
                            'link', '/receita/' || p_id)
    from avisos_destinatarios('clientes_todos', '{}'::jsonb) d
   where d.cliente_id is not null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

revoke execute on function avisar_nova_receita(uuid) from public, anon;
grant  execute on function avisar_nova_receita(uuid) to authenticated;
