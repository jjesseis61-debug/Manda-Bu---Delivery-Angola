-- Anti-fraude: NO MÁXIMO um desconto de indicação por cliente, mesmo com pedidos simultâneos.
--
-- O uso normal (carrinho mono-cozinha, checkout sequencial) já estava protegido pela guarda
-- 'desconto_em_curso' em avaliar_desconto_indicacao. Mas dois pedidos em paralelo real (ex.: duas
-- sessões/aparelhos com a mesma conta) abrem uma janela de corrida: em READ COMMITTED, cada
-- transacção só vê o que já foi confirmado, por isso nenhuma via a outra e ambas apanhavam o desconto.
--
-- Duas camadas:
--  1. Lock por cliente no cálculo (before insert): serializa os pedidos simultâneos do mesmo
--     cliente — o 2.º espera o 1.º confirmar, vê o desconto em curso e fica a 0. Sem erro para o
--     cliente (o pedido sai, só sem desconto). Mesmo padrão já usado em pedir_levantamento.
--  2. Índice único parcial: garantia dura na base de dados — no limite, no máximo um pedido com
--     desconto activo por cliente. Defesa em profundidade, caso algum caminho salte o trigger.

create or replace function calcular_desconto_indicacao() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  g pedidos_grupo;
begin
  if new.grupo_id is not null then
    g := grupo_para_adesao(new.grupo_id);
    new.ponto_entrega_id := g.ponto_entrega_id;
    new.cozinha_id := g.cozinha_id;
  end if;

  if new.cozinha_id is null then
    new.cozinha_id := cozinha_padrao();
  end if;

  -- Serializa os pedidos simultâneos do mesmo cliente (fecha a janela de corrida do desconto).
  perform pg_advisory_xact_lock(hashtext('desconto_indicacao:' || coalesce(new.cliente_id::text, '')));

  -- O servidor ignora qualquer valor enviado pela app e recalcula
  select d.valor into new.desconto_indicacao
    from avaliar_desconto_indicacao(new.cliente_id, new.ponto_entrega_id) d;
  -- Nunca mais do que o valor do pedido: o valor final não fica negativo
  new.desconto_indicacao := least(coalesce(new.desconto_indicacao, 0),
                                  greatest(coalesce(new.subtotal, 0) + coalesce(new.taxa_entrega, 0), 0));
  -- O desconto de boas-vindas só vale a partir do subtotal mínimo (sai da margem dos pratos)
  if coalesce(new.subtotal, 0) < (select desconto_subtotal_minimo from parametros where unico) then
    new.desconto_indicacao := 0;
  end if;
  return new;
end $$;

-- Função de trigger: não é chamável pelas apps (igual à definição anterior).
revoke execute on function calcular_desconto_indicacao() from public, anon, authenticated;

-- Garantia dura: no máximo um pedido com desconto activo (não cancelado/estornado) por cliente.
create unique index if not exists pedidos_um_desconto_por_cliente
  on pedidos (cliente_id)
  where desconto_indicacao > 0 and estado not in ('cancelado', 'estornado');
