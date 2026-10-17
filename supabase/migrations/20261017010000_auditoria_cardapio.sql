-- Ecrã de auditoria do cardápio por cozinha: lista as alterações (pratos, perfil, morada, opções)
-- de UMA cozinha, com quem, quando e o que mudou (de→para). Mesma barreira por-cozinha do cardápio:
-- a chave-mestra vê qualquer cozinha; cardapio.gerir só as suas.

create or replace function auditoria_cardapio(p_cozinha uuid)
returns table(quando timestamptz, quem text, ref_tipo text, acao text, item text, mudou jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not pode_na_cozinha('cardapio.gerir', p_cozinha) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'cardapio.gerir';
  end if;
  return query
  select a.criado_em, a.funcionario_nome, a.ref_tipo, a.acao,
         coalesce((select c.nome from cardapio c where c.id = a.ref_id),
                  (select z.nome from cozinhas z where z.id = a.ref_id),
                  a.ref_tipo) as item,
         nullif(a.detalhe, '')::jsonb as mudou
    from auditoria a
   where (a.ref_tipo = 'cardapio' and a.ref_id in (select id from cardapio where cozinha_id = p_cozinha))
      or (a.ref_tipo = 'cozinhas' and a.ref_id = p_cozinha)
      or (a.ref_tipo = 'cozinhas_localizacao' and a.ref_id in (select id from cozinhas_localizacao where cozinha_id = p_cozinha))
      or (a.ref_tipo = 'opcoes_grupos' and a.ref_id in
            (select og.id from opcoes_grupos og join cardapio c on c.id = og.cardapio_id where c.cozinha_id = p_cozinha))
      or (a.ref_tipo = 'opcoes' and a.ref_id in
            (select o.id from opcoes o join opcoes_grupos og on og.id = o.grupo_id
              join cardapio c on c.id = og.cardapio_id where c.cozinha_id = p_cozinha))
   order by a.criado_em desc
   limit 200;
end $$;
revoke execute on function auditoria_cardapio(uuid) from public, anon;
grant  execute on function auditoria_cardapio(uuid) to authenticated;
