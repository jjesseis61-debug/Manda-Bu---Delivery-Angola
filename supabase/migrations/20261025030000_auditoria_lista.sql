-- Auditoria: ecrã geral no operador. A tabela `auditoria` guarda TUDO (logins, cardápio, caixa,
-- configuração, etc.) e é imutável + protegida por RLS (auditoria.ver). Até agora só havia o histórico
-- do cardápio; este RPC devolve o registo completo, com filtro por categoria e por data, para quem
-- tiver auditoria.ver. Reusa a permissão existente (sem permissão nova).
create or replace function auditoria_lista(
  p_categoria text default null, p_desde timestamptz default null, p_limite int default 200)
returns table (id uuid, criado_em timestamptz, quem text, acao text, ref_tipo text, detalhe text, bloqueado boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('auditoria.ver');
  return query
    select a.id, a.criado_em, coalesce(nullif(a.funcionario_nome, ''), 'sistema'),
           a.acao, a.ref_tipo, a.detalhe, a.bloqueado
      from auditoria a
     where a.deletado_em is null
       and (p_desde is null or a.criado_em >= p_desde)
       and (p_categoria is null
            or (p_categoria = 'login'    and a.ref_tipo = 'otp')
            or (p_categoria = 'cardapio' and a.ref_tipo in ('cardapio', 'opcoes', 'opcoes_grupos', 'cozinhas'))
            or (p_categoria = 'equipa'   and a.ref_tipo = 'funcionarios')
            or (p_categoria = 'caixa'    and a.ref_tipo in ('caixa', 'extratos'))
            or (p_categoria = 'clientes' and a.ref_tipo = 'clientes')
            or (p_categoria = 'config'   and (a.acao like 'config%' or a.acao like 'parametros%'
                                              or a.acao like 'permissoes%' or a.acao like 'funcionalidade%')))
     order by a.criado_em desc
     limit least(coalesce(p_limite, 200), 500);
end $$;
revoke execute on function auditoria_lista(text, timestamptz, int) from public, anon;
grant  execute on function auditoria_lista(text, timestamptz, int) to authenticated;
