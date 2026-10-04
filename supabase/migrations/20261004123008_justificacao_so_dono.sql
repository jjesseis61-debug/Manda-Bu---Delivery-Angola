-- Teste de segurança: a justificação de cancelamento só para o dono (ou para o serviço que envia a N16).
-- Antes, uma sessão autenticada sem cliente (telemóvel acabado de autenticar, ou funcionário) podia ler a
-- justificação de qualquer pedido sabendo o id. Agora bloqueia-se qualquer sessão 'authenticated' que não
-- seja o dono; o envio das notificações corre como serviço (não 'authenticated'), por isso mantém o texto.

create or replace function justificacao_cancelamento(p_pedido uuid, p_curta boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  p pedidos;
  v_prato text;
  v_mais int;
  v_devolvido text;
begin
  select * into p from pedidos where id = p_pedido;
  if not found or p.estado <> 'cancelado' then return null; end if;
  -- Só o próprio dono (ou o serviço, que envia as notificações e não corre como 'authenticated').
  -- Uma sessão autenticada sem cliente — ou de outro cliente — não lê a justificação de um pedido alheio.
  if cliente_actual() is distinct from p.cliente_id
     and coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'authenticated' then
    return null;
  end if;
  if p.cancelado_por = 'cliente' then return 'Cancelaste este pedido.'; end if;
  select split_part(i ->> 'nome', ' (', 1) into v_prato from jsonb_array_elements(p.itens) i limit 1;
  v_mais := greatest(jsonb_array_length(p.itens) - 1, 0);
  v_devolvido := case
    when coalesce(p.refeicoes_pacote, 0) > 0 and coalesce(p.credito_indicacao_usado, 0) > 0
      then 'as refeições do pacote e o saldo que usaste já foram devolvidos'
    when coalesce(p.refeicoes_pacote, 0) > 0
      then case when p.refeicoes_pacote = 1 then 'a refeição do pacote já foi devolvida' else 'as refeições do pacote já foram devolvidas' end
    when coalesce(p.credito_indicacao_usado, 0) > 0 then 'o saldo que usaste já foi devolvido'
  end;
  return case when p_curta then 'Lamentamos' else 'Lamentamos muito' end
         || ': tivemos de cancelar o teu pedido'
         || coalesce(' de ' || v_prato || case when v_mais = 1 then ' e mais 1 prato' when v_mais > 1 then format(' e mais %s pratos', v_mais) else '' end, '')
         || frase_motivo_cancelamento(p.motivo_cancelamento) || '.'
         || case when p_curta then '' else ' Sabemos que contavas com esta refeição.' end
         || ' Não tens nada a pagar' || coalesce(' e ' || v_devolvido, '') || '.'
         || case when p_curta then '' else ' Se quiseres, podes pedir já outro prato.' end;
end $function$;
