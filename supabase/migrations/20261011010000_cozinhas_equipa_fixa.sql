-- Correcção: o objeto do funcionário que as apps lêem (meu_funcionario) construía cozinhas_equipa
-- só a partir dos turnos. Desde a migração gestao_permissoes a cozinha pode ser atribuída pela equipa
-- fixa (equipa_cozinha) no ecrã Pessoal, e o servidor já a aceita (membro_da_cozinha inclui-a), mas o
-- objeto do funcionário não a mostrava — por isso a app não oferecia a cozinha (ex.: abrir caixa, ver
-- a fila dessa cozinha). Passa a ser a união dos turnos com a equipa fixa.
create or replace function meu_funcionario() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'funcionario_id', f.id,
           'nome', f.nome,
           'cargo', f.cargo,
           'administrador_principal', f.administrador_principal,
           'permissoes', coalesce((select jsonb_agg(p.chave order by p.chave) from permissoes p
                                    where p.deletado_em is null and tem_permissao(p.chave)), '[]'),
           'cozinhas_equipa', coalesce((
             select jsonb_agg(distinct cid) from (
               select t.cozinha_id as cid from turnos t
                where t.funcionario_id = f.id and t.deletado_em is null
               union
               select e.cozinha_id from equipa_cozinha e where e.funcionario_id = f.id
             ) s), '[]'))
    from funcionarios f
   where f.auth_user_id = auth.uid() and auth.uid() is not null and f.deletado_em is null;
$$;
