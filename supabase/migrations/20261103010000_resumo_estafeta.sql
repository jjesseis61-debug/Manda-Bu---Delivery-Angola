-- Resumo do dia do estafeta: as entregas que ESTE estafeta concluiu hoje (hora de Luanda), com o
-- valor recebido em cada uma. Alimenta o bloco "feitas hoje / recebido hoje" e a secção "Feitas hoje"
-- na app do estafeta. Fica isolada do pedidos_operador (que só mostra o que está por fazer).
--
-- O valor segue a mesma fórmula do a_pagar do pedidos_operador. Só devolve as entregas do próprio
-- (entregador_id = funcionario_actual()), por isso é seguro para qualquer estafeta chamar.
create or replace function entregas_feitas_hoje()
 returns table(pedido_id uuid, cliente_nome text, entregue_em timestamptz, a_pagar integer)
 language sql stable security definer set search_path = public as $function$
  select p.id, c.nome, p.entregue_em,
         (p.subtotal + p.taxa_entrega - p.desconto_indicacao - p.credito_indicacao_usado
          - p.pago_pacote - p.valor_empresa)::int
    from pedidos p
    join clientes c on c.id = p.cliente_id
   where p.deletado_em is null
     and p.estado = 'entregue_pago'
     and p.entregador_id = funcionario_actual()
     and p.entregue_em is not null
     and (p.entregue_em at time zone 'Africa/Luanda')::date = (now() at time zone 'Africa/Luanda')::date
   order by p.entregue_em desc;
$function$;

-- Só a app (sessão autenticada) chama; nunca o anon nem o public.
revoke execute on function entregas_feitas_hoje() from public, anon;
grant  execute on function entregas_feitas_hoje() to authenticated;
