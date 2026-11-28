-- Quem preparou o pedido: campo de primeira classe na ficha do pedido.
-- Até agora "quem preparou" só se sabia pela auditoria (quem pôs o pedido em preparação). Passa a
-- ficar numa coluna própria, capturada automaticamente na transição para 'em_preparacao' — tal como
-- o entregador é capturado ao entrar 'em_entrega'. É por pedido (um responsável), não por prato.
alter table pedidos add column preparado_por uuid references funcionarios(id);
alter table pedidos add column preparado_em  timestamptz;
create index pedidos_preparado_por_idx on pedidos (preparado_por);
comment on column pedidos.preparado_por is 'Funcionário que marcou o pedido em_preparacao. Só o servidor escreve.';

create or replace function pedidos_registar_preparador() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.estado = 'em_preparacao' and old.estado is distinct from 'em_preparacao' then
    new.preparado_por := coalesce(new.preparado_por, funcionario_actual());
    new.preparado_em  := coalesce(new.preparado_em, now());
  end if;
  return new;
end $$;
revoke execute on function pedidos_registar_preparador() from public, anon, authenticated;

create trigger trg_pedidos_4_preparador before update on pedidos
for each row execute function pedidos_registar_preparador();

-- Mostra "preparado_por" e "preparado_em" no cabeçalho do histórico do pedido (resto igual).
create or replace function historico_pedido_dados(p_pedido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  x pedidos;
  r jsonb;
begin
  select * into x from pedidos where id = p_pedido;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  select jsonb_build_object(
    'pedido_id', x.id, 'estado', x.estado, 'cliente', (select nome from clientes where id = x.cliente_id),
    'cozinha', (select trim(nome) from cozinhas where id = x.cozinha_id),
    'preparado_por', (select nome from funcionarios where id = x.preparado_por),
    'preparado_em', x.preparado_em,
    'entregador', (select nome from funcionarios where id = x.entregador_id),
    'caixa', (select posto from caixa where id = x.caixa_id),
    'valor', x.subtotal + x.taxa_entrega - x.desconto_indicacao, 'parcelas', x.parcelas,
    'eventos', coalesce((select jsonb_agg(ev order by (ev ->> 'em')::timestamptz) from (
        select jsonb_build_object('em', x.criado_em, 'acao', 'pedido_criado', 'quem',
                                  coalesce((select nome from clientes where id = x.cliente_id), 'cliente'), 'detalhe', null) ev
        union all
        select jsonb_build_object('em', a.data, 'acao', a.acao, 'quem', a.funcionario_nome,
                                  'detalhe', case when a.detalhe ~ '^\s*\{' then a.detalhe::jsonb end)
          from auditoria a
         where a.ref_id = x.id
            or a.ref_id in (select k.id from comprovativos_pagamento k where k.pedido_id = x.id)
        union all
        select jsonb_build_object('em', k.criado_em, 'acao', 'comprovativo_registado',
                                  'quem', (select nome from funcionarios where id = k.registado_por),
                                  'detalhe', jsonb_build_object('metodo', k.metodo, 'valor', k.valor, 'referencia', k.referencia,
                                                                'ia_estado', k.ia_estado, 'ia_valor', k.ia_valor, 'ia_referencia', k.ia_referencia))
          from comprovativos_pagamento k where k.pedido_id = x.id and k.deletado_em is null
        union all
        select jsonb_build_object('em', m.atualizado_em, 'acao', 'extrato_' || coalesce(m.ligacao, 'ligado'),
                                  'quem', coalesce((select nome from funcionarios where id = m.ligado_por), 'conferência automática'),
                                  'detalhe', jsonb_build_object('conta', e.conta, 'data', m.data, 'valor', m.valor, 'referencia', m.referencia))
          from extrato_movimentos m join extratos e on e.id = m.extrato_id
          join comprovativos_pagamento k on k.id = m.comprovativo_id
         where k.pedido_id = x.id and m.deletado_em is null
        union all
        select jsonb_build_object('em', (c.fechamento ->> 'fechado_em')::timestamptz, 'acao', 'caixa_fechada',
                                  'quem', c.fechamento ->> 'funcionario_nome',
                                  'detalhe', jsonb_build_object('posto', c.posto, 'diferenca', c.fechamento -> 'diferenca'))
          from caixa c where c.id = x.caixa_id and c.fechamento is not null) s), '[]'))
  into r;
  return r;
end $$;
revoke execute on function historico_pedido_dados(uuid) from public, anon, authenticated;
