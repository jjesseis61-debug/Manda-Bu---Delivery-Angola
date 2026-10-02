-- Apagar a conta pela app do cliente (exigido pela Google Play e pela App Store).
--
-- Os dados pessoais saem: nome, telefone, NIF, contacto, endereços, telemóveis
-- registados para push, notificações por enviar e o utilizador da Auth. Ficam,
-- sem ligação à pessoa, os registos de que a empresa precisa para as contas:
-- pedidos, vendas, pagamentos e ganhos do programa (o cliente passa a chamar-se
-- "Cliente removido"). As avaliações ficam com esse nome.
--
-- Não se apaga uma conta com um pedido, um levantamento ou um grupo a meio:
-- primeiro termina-se (ou cancela-se) e depois apaga-se.

create or replace function apagar_conta() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_cliente uuid := cliente_actual();
begin
  if v_uid is null or v_cliente is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  if exists (select 1 from pedidos where cliente_id = v_cliente and deletado_em is null
                and estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')) then
    raise exception 'pedido_em_curso' using errcode = 'P0001';
  end if;
  if exists (select 1 from pagamentos_indicacao where indicador_id = v_cliente and deletado_em is null
                and estado in ('pedido', 'aprovado')) then
    raise exception 'levantamento_em_curso' using errcode = 'P0001';
  end if;
  if exists (select 1 from pedidos_grupo where organizador_id = v_cliente and deletado_em is null
                and estado in ('aberto', 'fechado', 'em_preparacao')) then
    raise exception 'grupo_em_curso' using errcode = 'P0001';
  end if;

  update dispositivos_push set activo = false, deletado_em = now(), atualizado_em = now()
   where cliente_id = v_cliente and deletado_em is null;
  update enderecos_cliente set deletado_em = now(), atualizado_em = now()
   where cliente_id = v_cliente and deletado_em is null;
  update notificacoes_fila set deletado_em = now(), atualizado_em = now(), dispositivo_id = 'servidor'
   where cliente_id = v_cliente and enviada_em is null and deletado_em is null;
  update perfil_destaques set sair_da_lista = true, mostrar_nome_real = false, atualizado_em = now()
   where cliente_id = v_cliente;
  update clientes
     set nome = 'Cliente removido', telefone = null, nif = null, pessoa_contacto = null,
         auth_user_id = null, deletado_em = now(), atualizado_em = now(), dispositivo_id = 'servidor'
   where id = v_cliente;

  perform registar_auditoria('cliente_apagou_conta', 'clientes', v_cliente, '{}'::jsonb, false);

  -- O utilizador da Auth (com o telefone) sai também, a não ser que seja o de um funcionário
  if not exists (select 1 from funcionarios where auth_user_id = v_uid) then
    delete from auth.users where id = v_uid;
  end if;
end $$;

comment on function apagar_conta() is
  'Apaga a conta do cliente da sessão: dados pessoais e utilizador da Auth saem; pedidos, vendas e pagamentos ficam anónimos.';

revoke execute on function apagar_conta() from public, anon;
grant  execute on function apagar_conta() to authenticated;
