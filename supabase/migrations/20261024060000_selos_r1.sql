-- Cartão de selos (R1): a cada N pedidos entregues e pagos, o próximo tem FRETE GRÁTIS.
-- Fica PRONTO e DESLIGADO: só conta e só se aplica com o interruptor 'selos' ligado — por isso, com
-- ele desligado, o comportamento é idêntico ao de hoje. O prémio (frete grátis) reutiliza a
-- taxa_entrega existente, por isso flui para a venda/caixa sem tocar em mais nada. Âmbito: global
-- (qualquer cozinha). Nº de selos configurável no painel (parametros.selos_necessarios).
-- A geração/aviso e outros tipos de prémio ficam para fases seguintes.

-- 1. Interruptor (nasce desligado)
insert into funcionalidades (chave, activa, dispositivo_id) values ('selos', false, 'servidor')
  on conflict (chave) do nothing;

-- 2. Parâmetro configurável (o operador muda no painel; alterar_parametros aceita qualquer coluna)
alter table parametros add column if not exists selos_necessarios integer not null default 8;

-- 3. Marca no pedido: este pedido gastou um prémio de selos (frete grátis)
alter table pedidos add column if not exists selo_premio boolean not null default false;

-- 4. Progresso do cliente (para a app mostrar). null = interruptor desligado ou sem sessão.
create or replace function meus_selos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cli    uuid := cliente_actual();
  v_n      integer;
  v_pagos  integer;
  v_usados integer;
  v_prog   integer;
begin
  if v_cli is null or not funcionalidade_activa('selos') then
    return null;
  end if;
  v_n := greatest(coalesce((select selos_necessarios from parametros where unico), 8), 1);
  select count(*) into v_pagos from pedidos
   where cliente_id = v_cli and estado = 'entregue_pago' and deletado_em is null;
  select count(*) into v_usados from pedidos
   where cliente_id = v_cli and selo_premio and estado not in ('cancelado', 'estornado') and deletado_em is null;
  v_prog := v_pagos - v_usados * v_n;  -- selos no cartão actual
  return jsonb_build_object(
    'necessarios', v_n,
    'progresso', v_prog,
    'tem_premio', (v_pagos / v_n) - v_usados >= 1,
    'faltam', case when (v_pagos / v_n) - v_usados >= 1 then 0 else v_n - v_prog end);
end $$;

revoke execute on function meus_selos() from public, anon;
grant  execute on function meus_selos() to authenticated;

-- 5. Aplicar o prémio ao criar o pedido: corre DEPOIS do cálculo da taxa (trg_pedidos_00_cardapio).
--    Com o interruptor desligado é no-op. Conta global (qualquer cozinha). Um pedido cancelado/
--    estornado liberta o prémio (não conta em v_usados), por isso nunca se perde um selo por engano.
create or replace function pedidos_aplicar_selo() returns trigger
language plpgsql set search_path = public as $$
declare
  v_n      integer;
  v_pagos  integer;
  v_usados integer;
begin
  if e_escrita_cliente() and funcionalidade_activa('selos') then
    v_n := greatest(coalesce((select selos_necessarios from parametros where unico), 8), 1);
    select count(*) into v_pagos from pedidos
     where cliente_id = new.cliente_id and estado = 'entregue_pago' and deletado_em is null;
    select count(*) into v_usados from pedidos
     where cliente_id = new.cliente_id and selo_premio and estado not in ('cancelado', 'estornado') and deletado_em is null;
    if (v_pagos / v_n) - v_usados >= 1 then
      new.selo_premio := true;
      new.taxa_entrega := 0;  -- frete grátis
    end if;
  end if;
  return new;
end $$;

revoke execute on function pedidos_aplicar_selo() from public, anon, authenticated;

create trigger trg_pedidos_50_selo before insert on pedidos
  for each row execute function pedidos_aplicar_selo();
