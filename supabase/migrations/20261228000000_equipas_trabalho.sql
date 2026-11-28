-- Junta Bué no trabalho: equipas fixas de colegas com uma responsável (docs/projecto-balcao-e-equipas.md, secção 3).
--
--  * Equipa fixa: local, hora da entrega, prazo e dias da semana. Todos os dias úteis o grupo do dia abre
--    sozinho (modo «conta_mes») e cada colega recebe «Vais almoçar hoje?».
--  * Autorizações do colega (retiráveis): a responsável pode pedir o meu almoço / ver a minha conta do mês.
--  * Uma refeição por colega por dia; mais refeições só com pedido extra aprovado pela cozinha.
--  * Conta do mês de cada colega: o almoço vai para a conta (como a conta de empresa, uma parcela que não é
--    dinheiro na entrega) até ao limite mensal; o que passa do limite paga-se no dia. Paga-se por referência
--    (confirmada pelas Finanças) ou em dinheiro registado pela cozinha. Em atraso: passa a pagar no dia.
--  * Acordo por equipa (proposto pelas Finanças, aceite pela cozinha): benefício da responsável em % de cada
--    prato, por escalão (média de refeições por dia do mês anterior), desbloqueado colega a colega quando
--    cada um paga. «Só a cozinha»: comissão 0, entrega 0, só para equipas trazidas pela cozinha.
--  * Cada pedido conta só num programa: com acordo, benefício da equipa; sem acordo, ganha-ganha (Kambas).
-- Tudo atrás do interruptor «equipas_trabalho» (desligado).

insert into funcionalidades (chave, activa, dispositivo_id)
values ('equipas_trabalho', false, 'servidor')
on conflict (chave) do nothing;

-- ------------------------------------------------------------------ 1. tabelas
create table if not exists equipas (
  id               uuid primary key default gen_random_uuid(),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  deletado_em      timestamptz,
  nome             text not null check (length(trim(nome)) between 2 and 60),
  responsavel_id   uuid not null references clientes(id),
  cozinha_id       uuid not null references cozinhas(id),
  ponto_entrega_id uuid not null references pontos_entrega(id),
  hora_entrega     time not null default '12:30',
  prazo_minutos    integer not null default 90 check (prazo_minutos between 30 and 300),
  dias             smallint[] not null default '{1,2,3,4,5}'
                   check (dias <@ '{1,2,3,4,5,6,7}'::smallint[] and cardinality(dias) between 1 and 7),
  limite_mensal    integer not null default 40000 check (limite_mensal between 0 and 1000000),
  activa           boolean not null default true,
  empresa_id       uuid references empresas(id),   -- conta onde vão os almoços (parcela «Conta do mês»)
  origem           text not null default 'plataforma' check (origem in ('plataforma', 'cozinha'))
);
create index if not exists equipas_responsavel_idx on equipas (responsavel_id);
create index if not exists equipas_cozinha_idx on equipas (cozinha_id);
create index if not exists equipas_ponto_idx on equipas (ponto_entrega_id);
create index if not exists equipas_empresa_idx on equipas (empresa_id);

create table if not exists equipa_membros (
  id             uuid primary key default gen_random_uuid(),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  equipa_id      uuid not null references equipas(id),
  cliente_id     uuid not null references clientes(id),
  estado         text not null default 'convidado' check (estado in ('convidado', 'activo', 'saiu')),
  pode_pedir     boolean not null default false,   -- «a responsável pode pedir o meu almoço»
  pode_ver_conta boolean not null default false,   -- «a responsável pode ver a minha conta do mês»
  em_atraso      boolean not null default false,
  aceite_em      timestamptz,
  unique (equipa_id, cliente_id)
);
create index if not exists equipa_membros_cliente_idx on equipa_membros (cliente_id);
-- Um colega está activo numa só equipa de cada vez
create unique index if not exists equipa_membros_activo_idx on equipa_membros (cliente_id) where estado = 'activo';

alter table pedidos_grupo add column if not exists equipa_id uuid references equipas(id);
alter table pedidos_grupo add column if not exists dia_equipa date;
create unique index if not exists pedidos_grupo_equipa_dia_idx on pedidos_grupo (equipa_id, dia_equipa)
  where equipa_id is not null and deletado_em is null;
alter table pedidos_grupo drop constraint if exists pedidos_grupo_modo_pagamento_check;
alter table pedidos_grupo add constraint pedidos_grupo_modo_pagamento_check
  check (modo_pagamento in ('individual', 'empresa', 'quem_recebe', 'conta_mes'));

alter table pedidos add column if not exists pedido_por uuid references clientes(id);
alter table pedidos add column if not exists sem_comissao boolean not null default false;
comment on column pedidos.sem_comissao is 'Pedido de uma equipa com acordo «só a cozinha»: sem comissão da plataforma nem taxa de entrega';
comment on column pedidos.pedido_por is 'Responsável da equipa que pediu este almoço em nome do colega (com autorização dele)';
create index if not exists pedidos_pedido_por_idx on pedidos (pedido_por) where pedido_por is not null;

create table if not exists equipa_extras (
  id           uuid primary key default gen_random_uuid(),
  criado_em    timestamptz not null default now(),
  equipa_id    uuid not null references equipas(id),
  cliente_id   uuid not null references clientes(id),
  dia          date not null,
  quantidade   integer not null check (quantidade between 1 and 10),
  motivo       text not null check (length(trim(motivo)) between 2 and 200),
  aprovadas    integer check (aprovadas >= 0),
  estado       text not null default 'pendente' check (estado in ('pendente', 'aprovado', 'recusado')),
  decidido_por uuid references funcionarios(id),
  decidido_em  timestamptz
);
create index if not exists equipa_extras_equipa_idx on equipa_extras (equipa_id, dia);
create index if not exists equipa_extras_cliente_idx on equipa_extras (cliente_id);
create index if not exists equipa_extras_decidido_por_idx on equipa_extras (decidido_por);
create unique index if not exists equipa_extras_pendente_idx on equipa_extras (equipa_id, cliente_id, dia) where estado = 'pendente';

create table if not exists contas_mes_pagamentos (
  id               uuid primary key default gen_random_uuid(),
  criado_em        timestamptz not null default now(),
  equipa_id        uuid not null references equipas(id),
  cliente_id       uuid not null references clientes(id),   -- de quem é a conta
  mes              date not null check (extract(day from mes) = 1),
  valor            integer not null check (valor > 0),
  metodo           text not null check (metodo in ('multicaixa_express', 'unitel_money', 'dinheiro')),
  referencia       text,
  referencia_chave text,
  pago_por         uuid references clientes(id),             -- o próprio ou a responsável em nome dele
  estado           text not null default 'pendente' check (estado in ('pendente', 'confirmado', 'rejeitado')),
  motivo           text,
  registado_por    uuid references funcionarios(id),         -- dinheiro recebido pela cozinha
  decidido_por     uuid references funcionarios(id),
  decidido_em      timestamptz,
  check (metodo = 'dinheiro' or referencia_chave is not null)
);
create index if not exists contas_mes_pagamentos_conta_idx on contas_mes_pagamentos (equipa_id, cliente_id, mes);
create index if not exists contas_mes_pagamentos_cliente_idx on contas_mes_pagamentos (cliente_id);
create index if not exists contas_mes_pagamentos_pago_por_idx on contas_mes_pagamentos (pago_por);
create index if not exists contas_mes_pagamentos_registado_idx on contas_mes_pagamentos (registado_por);
create index if not exists contas_mes_pagamentos_decidido_idx on contas_mes_pagamentos (decidido_por);
-- A mesma referência não serve duas vezes (nem aqui nem no «pagar antes»)
create unique index if not exists contas_mes_pagamentos_ref_idx on contas_mes_pagamentos (referencia_chave)
  where estado <> 'rejeitado' and referencia_chave is not null;

create table if not exists equipa_acordos (
  id                 uuid primary key default gen_random_uuid(),
  criado_em          timestamptz not null default now(),
  equipa_id          uuid not null references equipas(id),
  quem_paga          text not null check (quem_paga in ('plataforma', 'plataforma_cozinha', 'cozinha')),
  parte_cozinha_pct  numeric(5,2) not null default 50 check (parte_cozinha_pct between 0 and 100),
  pct_1              numeric(5,2) not null default 3 check (pct_1 between 0 and 20),
  pct_2              numeric(5,2) not null default 5 check (pct_2 between 0 and 20),
  pct_3              numeric(5,2) not null default 10 check (pct_3 between 0 and 20),
  limite_2           integer not null default 10 check (limite_2 >= 1),
  limite_3           integer not null default 15 check (limite_3 >= 1),
  conta_bebidas      boolean not null default false,
  tecto_refeicao     integer not null default 1000 check (tecto_refeicao between 0 and 10000),
  estado             text not null default 'proposto' check (estado in ('proposto', 'activo', 'terminado')),
  criado_por         uuid references funcionarios(id),
  aceite_por         uuid references funcionarios(id),
  aceite_em          timestamptz,
  terminado_em       timestamptz,
  check (pct_1 <= pct_2 and pct_2 <= pct_3 and limite_2 < limite_3)
);
create index if not exists equipa_acordos_equipa_idx on equipa_acordos (equipa_id);
create index if not exists equipa_acordos_criado_por_idx on equipa_acordos (criado_por);
create index if not exists equipa_acordos_aceite_por_idx on equipa_acordos (aceite_por);
create unique index if not exists equipa_acordos_vigente_idx on equipa_acordos (equipa_id) where estado in ('proposto', 'activo');

create table if not exists equipa_beneficios (
  id             uuid primary key default gen_random_uuid(),
  criado_em      timestamptz not null default now(),
  equipa_id      uuid not null references equipas(id),
  acordo_id      uuid not null references equipa_acordos(id),
  pedido_id      uuid not null unique references pedidos(id),
  cliente_id     uuid not null references clientes(id),      -- o colega que comeu
  responsavel_id uuid not null references clientes(id),      -- quem recebe o benefício
  mes            date not null,
  base           integer not null,
  pct            numeric(5,2) not null,
  valor          integer not null check (valor >= 0),
  parte_cozinha  integer not null default 0 check (parte_cozinha >= 0),
  estado         text not null default 'pendente' check (estado in ('pendente', 'desbloqueado', 'pago', 'anulado')),
  pago_em        timestamptz,
  pago_por       uuid references funcionarios(id),
  metodo_pagamento text
);
create index if not exists equipa_beneficios_equipa_idx on equipa_beneficios (equipa_id, mes);
create index if not exists equipa_beneficios_cliente_idx on equipa_beneficios (cliente_id);
create index if not exists equipa_beneficios_responsavel_idx on equipa_beneficios (responsavel_id);
create index if not exists equipa_beneficios_acordo_idx on equipa_beneficios (acordo_id);
create index if not exists equipa_beneficios_pago_por_idx on equipa_beneficios (pago_por);

-- Só as funções leem e escrevem
alter table equipas enable row level security;
alter table equipa_membros enable row level security;
alter table equipa_extras enable row level security;
alter table contas_mes_pagamentos enable row level security;
alter table equipa_acordos enable row level security;
alter table equipa_beneficios enable row level security;
revoke all on equipas, equipa_membros, equipa_extras, contas_mes_pagamentos, equipa_acordos, equipa_beneficios
  from public, anon, authenticated;

-- ------------------------------------------------------------------ 2. ajudas
create or replace function hoje_luanda() returns date
language sql stable set search_path = public as $$ select (now() at time zone 'Africa/Luanda')::date $$;

create or replace function funcionario_tem_permissao(p_func uuid, p_permissao text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_func in (select funcionarios_com_permissao(p_permissao));
$$;
revoke execute on function funcionario_tem_permissao(uuid, text) from public, anon, authenticated;

-- O funcionário trabalha nesta cozinha (ou é da sede: sem cozinhas atribuídas, vê todas)
create or replace function funcionario_ve_cozinha(p_func uuid, p_cozinha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select administrador_principal from funcionarios where id = p_func), false)
      or pertence_a_cozinha(p_func, p_cozinha)
      or (p_func is not null
          and not exists (select 1 from equipa_cozinha where funcionario_id = p_func)
          and not exists (select 1 from turnos where funcionario_id = p_func and deletado_em is null));
$$;
revoke execute on function funcionario_ve_cozinha(uuid, uuid) from public, anon, authenticated;

-- Refeições de um pedido: tudo menos as bebidas (categoria «Bebidas»)
create or replace function refeicoes_dos_itens(p_itens jsonb) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce(sum(coalesce((i ->> 'qtd')::int, 1)), 0)::int
    from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) i
    left join cardapio c on c.id = nullif(i ->> 'cardapio_id', '')::uuid
   where coalesce(c.categoria, '') not ilike 'bebida%';
$$;
revoke execute on function refeicoes_dos_itens(jsonb) from public, anon, authenticated;

create or replace function valor_bebidas_dos_itens(p_itens jsonb) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce(sum(coalesce((i ->> 'qtd')::int, 1) * coalesce((i ->> 'preco_unitario')::int, 0)), 0)::int
    from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) i
    join cardapio c on c.id = nullif(i ->> 'cardapio_id', '')::uuid
   where c.categoria ilike 'bebida%';
$$;
revoke execute on function valor_bebidas_dos_itens(jsonb) from public, anon, authenticated;

create or replace function equipa_do_grupo(p_grupo uuid) returns equipas
language sql stable security definer set search_path = public as $$
  select e.* from pedidos_grupo g join equipas e on e.id = g.equipa_id where g.id = p_grupo;
$$;
revoke execute on function equipa_do_grupo(uuid) from public, anon, authenticated;

create or replace function acordo_activo(p_equipa uuid) returns equipa_acordos
language sql stable security definer set search_path = public as $$
  select * from equipa_acordos where equipa_id = p_equipa and estado = 'activo' limit 1;
$$;
revoke execute on function acordo_activo(uuid) from public, anon, authenticated;

-- O pedido é de uma equipa com acordo activo (conta para o benefício, não para o ganha-ganha)
create or replace function pedido_com_beneficio_equipa(p_pedido uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from pedidos p
                   join pedidos_grupo g on g.id = p.grupo_id
                   join equipa_acordos a on a.equipa_id = g.equipa_id and a.estado = 'activo'
                  where p.id = p_pedido);
$$;
revoke execute on function pedido_com_beneficio_equipa(uuid) from public, anon, authenticated;


-- Quanto deste pedido vai para a conta do mês: o que se paga, até ao que resta do limite mensal
create or replace function conta_mes_valor(p pedidos, e equipas) returns integer
language sql stable security definer set search_path = public as $$
  select least(
           greatest(p.subtotal + p.taxa_entrega - coalesce(p.desconto_indicacao, 0)
                    - coalesce(p.credito_indicacao_usado, 0) - coalesce(p.pago_antes, 0), 0),
           greatest(e.limite_mensal - coalesce((
             select sum(x.valor_empresa) from pedidos x
              where x.empresa_id = e.empresa_id and x.cliente_id = p.cliente_id and x.id <> p.id
                and x.deletado_em is null and x.estado not in ('cancelado', 'estornado')
                and date_trunc('month', x.criado_em at time zone 'Africa/Luanda')
                    = date_trunc('month', coalesce(p.criado_em, now()) at time zone 'Africa/Luanda')), 0), 0))::int;
$$;
revoke execute on function conta_mes_valor(pedidos, equipas) from public, anon, authenticated;

-- Escalão do benefício num mês: pela média de refeições por dia (com almoços) do mês anterior
create or replace function equipa_escalao(p_equipa uuid, p_mes date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a equipa_acordos := acordo_activo(p_equipa);
  v_ini date := (date_trunc('month', p_mes) - interval '1 month')::date;
  v_ref int;
  v_dias int;
  v_media numeric;
  v_pct numeric;
  v_prox int;
begin
  select coalesce(sum(refeicoes_dos_itens(p.itens)), 0), count(distinct (p.entregue_em at time zone 'Africa/Luanda')::date)
    into v_ref, v_dias
    from pedidos p join pedidos_grupo g on g.id = p.grupo_id
   where g.equipa_id = p_equipa and p.estado = 'entregue_pago' and p.deletado_em is null
     and (p.entregue_em at time zone 'Africa/Luanda')::date >= v_ini
     and (p.entregue_em at time zone 'Africa/Luanda')::date < (v_ini + interval '1 month')::date;
  v_media := case when v_dias > 0 then round(v_ref::numeric / v_dias, 1) else 0 end;
  if a.id is null then
    return jsonb_build_object('media', v_media, 'pct', 0);
  end if;
  v_pct := case when v_media >= a.limite_3 then a.pct_3 when v_media >= a.limite_2 then a.pct_2 else a.pct_1 end;
  v_prox := case when v_media >= a.limite_3 then null when v_media >= a.limite_2 then a.limite_3 else a.limite_2 end;
  return jsonb_build_object('media', v_media, 'pct', v_pct, 'proximo_limite', v_prox,
                            'proximo_pct', case when v_prox = a.limite_3 then a.pct_3 when v_prox = a.limite_2 then a.pct_2 end,
                            'faltam', case when v_prox is not null then greatest(v_prox - v_media, 0) end);
end $$;
revoke execute on function equipa_escalao(uuid, date) from public, anon, authenticated;

create or replace function aviso_cliente(p_cliente uuid, p_titulo text, p_corpo text, p_link text default '/equipa')
returns void language sql security definer set search_path = public as $$
  insert into notificacoes_fila (cliente_id, codigo, dados)
  values (p_cliente, 'N31', jsonb_build_object('titulo', p_titulo, 'corpo', p_corpo, 'link', p_link));
$$;
revoke execute on function aviso_cliente(uuid, text, text, text) from public, anon, authenticated;

create or replace function nome_curto(p_cliente uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(split_part(trim(nome), ' ', 1), ''), 'Um colega') from clientes where id = p_cliente;
$$;
revoke execute on function nome_curto(uuid) from public, anon, authenticated;

-- Conta do mês de um colega: almoços na conta (entregues e a caminho), pagamentos e o que falta
create or replace function conta_mes_resumo(p_equipa uuid, p_cliente uuid, p_mes date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e equipas;
  v_ini date := date_trunc('month', p_mes)::date;
  v_fim date := (date_trunc('month', p_mes) + interval '1 month')::date;
  v_linhas jsonb;
  v_total int;
  v_pago int;
  v_pendente int;
  m equipa_membros;
begin
  select * into e from equipas where id = p_equipa;
  select * into m from equipa_membros where equipa_id = p_equipa and cliente_id = p_cliente;
  select coalesce(jsonb_agg(jsonb_build_object(
           'pedido_id', p.id, 'dia', (p.criado_em at time zone 'Africa/Luanda')::date, 'valor', p.valor_empresa,
           'entregue', p.estado = 'entregue_pago', 'pedido_por', case when p.pedido_por is not null then nome_curto(p.pedido_por) end,
           'itens', (select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || coalesce(i ->> 'nome', 'prato'), ', ')
                       from jsonb_array_elements(p.itens) i))
           order by p.criado_em), '[]'::jsonb),
         coalesce(sum(p.valor_empresa) filter (where p.estado = 'entregue_pago'), 0)
    into v_linhas, v_total
    from pedidos p
   where p.empresa_id = e.empresa_id and p.cliente_id = p_cliente and p.valor_empresa > 0 and p.deletado_em is null
     and p.estado not in ('cancelado', 'estornado')
     and (p.criado_em at time zone 'Africa/Luanda')::date >= v_ini and (p.criado_em at time zone 'Africa/Luanda')::date < v_fim;
  select coalesce(sum(valor) filter (where estado = 'confirmado'), 0), coalesce(sum(valor) filter (where estado = 'pendente'), 0)
    into v_pago, v_pendente
    from contas_mes_pagamentos where equipa_id = p_equipa and cliente_id = p_cliente and mes = v_ini;
  return jsonb_build_object(
    'equipa_id', p_equipa, 'cliente_id', p_cliente, 'nome', (select nome from clientes where id = p_cliente),
    'mes', v_ini, 'limite', e.limite_mensal, 'linhas', v_linhas, 'total', v_total,
    'pago', v_pago, 'a_confirmar', v_pendente, 'em_falta', greatest(v_total - v_pago, 0),
    'em_atraso', coalesce(m.em_atraso, false),
    'pagamentos', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'valor', valor, 'metodo', metodo, 'estado', estado,
                                                                'criado_em', criado_em, 'motivo', motivo,
                                                                'pago_por', case when pago_por is distinct from p_cliente then nome_curto(pago_por) end)
                                             order by criado_em), '[]'::jsonb)
                     from contas_mes_pagamentos where equipa_id = p_equipa and cliente_id = p_cliente and mes = v_ini));
end $$;
revoke execute on function conta_mes_resumo(uuid, uuid, date) from public, anon, authenticated;

-- Depois de um pagamento: desbloqueia o benefício dos almoços do mês pago e acerta o atraso
create or replace function equipa_recalcular_conta(p_equipa uuid, p_cliente uuid, p_mes date) returns void
language plpgsql security definer set search_path = public as $$
declare
  r jsonb := conta_mes_resumo(p_equipa, p_cliente, p_mes);
  v_ini date := date_trunc('month', p_mes)::date;
begin
  if (r ->> 'em_falta')::int <= 0 then
    update equipa_beneficios b set estado = 'desbloqueado'
      from pedidos p
     where b.pedido_id = p.id and b.equipa_id = p_equipa and b.cliente_id = p_cliente and b.estado = 'pendente'
       and (p.criado_em at time zone 'Africa/Luanda')::date >= v_ini
       and (p.criado_em at time zone 'Africa/Luanda')::date < (v_ini + interval '1 month')::date;
  end if;
  perform equipa_actualizar_atraso(p_equipa, p_cliente);
end $$;
revoke execute on function equipa_recalcular_conta(uuid, uuid, date) from public, anon, authenticated;

-- Em atraso: um mês anterior por pagar depois do dia 10 do mês seguinte
create or replace function equipa_actualizar_atraso(p_equipa uuid, p_cliente uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_atraso boolean := false;
  v_mes date;
  v_hoje date := hoje_luanda();
begin
  for v_mes in select distinct date_trunc('month', p.criado_em at time zone 'Africa/Luanda')::date
                 from pedidos p join equipas e on e.empresa_id = p.empresa_id
                where e.id = p_equipa and p.cliente_id = p_cliente and p.valor_empresa > 0 and p.estado = 'entregue_pago'
                  and p.criado_em >= now() - interval '13 months' loop
    if v_hoje >= (v_mes + interval '1 month' + interval '9 days')::date
       and (conta_mes_resumo(p_equipa, p_cliente, v_mes) ->> 'em_falta')::int > 0 then
      v_atraso := true;
      exit;
    end if;
  end loop;
  update equipa_membros set em_atraso = v_atraso, atualizado_em = now()
   where equipa_id = p_equipa and cliente_id = p_cliente and em_atraso is distinct from v_atraso;
  return v_atraso;
end $$;
revoke execute on function equipa_actualizar_atraso(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------------------------------ 3. regras ao criar o pedido
create or replace function pedidos_equipa() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e equipas;
  m equipa_membros;
  a equipa_acordos;
  v_dia date;
  v_ja int;
  v_extra int;
begin
  if e_escrita_cliente() then
    new.pedido_por := null;   -- só a função pedir_por_colega o preenche
    new.sem_comissao := false;
  end if;
  if new.grupo_id is null then return new; end if;
  e := equipa_do_grupo(new.grupo_id);
  if e.id is null then return new; end if;

  select * into m from equipa_membros where equipa_id = e.id and cliente_id = new.cliente_id and estado = 'activo';
  if not found then
    raise exception 'nao_e_da_equipa' using errcode = 'P0001';
  end if;

  -- Uma refeição por colega por dia (mais só com pedido extra aprovado pela cozinha)
  v_dia := (coalesce(new.criado_em, now()) at time zone 'Africa/Luanda')::date;
  select coalesce(sum(refeicoes_dos_itens(p.itens)), 0) into v_ja
    from pedidos p join pedidos_grupo g on g.id = p.grupo_id
   where g.equipa_id = e.id and p.cliente_id = new.cliente_id and p.deletado_em is null
     and p.estado not in ('cancelado', 'estornado') and (p.criado_em at time zone 'Africa/Luanda')::date = v_dia;
  select coalesce(sum(aprovadas), 0) into v_extra
    from equipa_extras where equipa_id = e.id and cliente_id = new.cliente_id and dia = v_dia and estado = 'aprovado';
  if v_ja + refeicoes_dos_itens(new.itens) > 1 + v_extra then
    raise exception 'limite_refeicoes_dia' using errcode = 'P0001', detail = (1 + v_extra)::text;
  end if;

  -- «Só a cozinha»: sem taxa de entrega (a cozinha leva ou os colegas levantam)
  a := acordo_activo(e.id);
  -- (fica marcado no pedido: vale o acordo em vigor quando se pediu)
  if a.quem_paga = 'cozinha' then
    new.taxa_entrega := 0;
    new.sem_comissao := true;
  end if;

  -- Conta do mês (em atraso: paga no dia)
  if not m.em_atraso and e.empresa_id is not null then
    new.empresa_id := e.empresa_id;
    new.valor_empresa := conta_mes_valor(new, e);
    if new.valor_empresa = 0 then new.empresa_id := null; end if;
  end if;
  return new;
end $$;
revoke execute on function pedidos_equipa() from public, anon, authenticated;
-- Depois dos preços, do desconto e do selo (ordem alfabética dos triggers)
drop trigger if exists trg_pedidos_51_equipa on pedidos;
create trigger trg_pedidos_51_equipa before insert on pedidos for each row execute function pedidos_equipa();

-- Ao fechar o grupo do dia, a taxa é repartida: «só a cozinha» volta a 0 e a conta do mês acompanha
create or replace function equipa_ajustar_fecho(p_grupo uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  e equipas := equipa_do_grupo(p_grupo);
  p pedidos;
begin
  if e.id is null then return; end if;
  update pedidos set taxa_entrega = 0, atualizado_em = now()
   where grupo_id = p_grupo and sem_comissao and deletado_em is null and estado not in ('cancelado', 'entregue_pago', 'estornado');
  for p in select * from pedidos where grupo_id = p_grupo and empresa_id = e.empresa_id and deletado_em is null
                                   and estado not in ('cancelado', 'entregue_pago', 'estornado') loop
    update pedidos set valor_empresa = conta_mes_valor(p, e), atualizado_em = now() where id = p.id;
  end loop;
end $$;
revoke execute on function equipa_ajustar_fecho(uuid) from public, anon, authenticated;

do $$
declare
  v_def  text := pg_get_functiondef('fechar_grupo_interno(uuid)'::regprocedure);
  v_novo text;
begin
  if position('equipa_ajustar_fecho' in v_def) > 0 then return; end if;
  v_novo := replace(v_def, 'update pedidos_grupo set estado = ''fechado'', atualizado_em = now() where id = g.id;',
                    'perform equipa_ajustar_fecho(g.id);
  update pedidos_grupo set estado = ''fechado'', atualizado_em = now() where id = g.id;');
  if v_novo = v_def then raise exception 'fechar_grupo_interno não tem o formato esperado'; end if;
  execute v_novo;
end $$;

-- Na entrega, a parte que vai para a conta (do mês ou da empresa) não é cobrada: as parcelas somam o resto
do $$
declare
  v_def  text := pg_get_functiondef('pedidos_antes_actualizar()'::regprocedure);
  v_novo text;
begin
  if position('new.pago_antes + coalesce(new.valor_empresa, 0)' in v_def) > 0 then return; end if;
  v_novo := replace(v_def, 'v_soma + new.credito_indicacao_usado + new.pago_pacote + new.pago_antes',
                    'v_soma + new.credito_indicacao_usado + new.pago_pacote + new.pago_antes + coalesce(new.valor_empresa, 0)');
  if v_novo = v_def then raise exception 'pedidos_antes_actualizar não tem o formato esperado'; end if;
  execute v_novo;
end $$;

-- A parcela da venda chama-se «Conta do mês» quando é de uma equipa
do $$
declare
  v_def  text := pg_get_functiondef('gerar_venda_pedido()'::regprocedure);
  v_novo text;
begin
  if position('Conta do mês' in v_def) > 0 then return; end if;
  v_novo := replace(v_def, '''metodo'', ''Conta da empresa''',
                    '''metodo'', case when exists (select 1 from equipas q where q.empresa_id = new.empresa_id) then ''Conta do mês'' else ''Conta da empresa'' end');
  if v_novo = v_def then raise exception 'gerar_venda_pedido não tem o formato esperado'; end if;
  execute v_novo;
end $$;

-- Cada pedido conta só num programa: com acordo de equipa não há ganha-ganha
do $$
declare
  v_def  text := pg_get_functiondef('processar_ganho_indicacao()'::regprocedure);
  v_novo text;
begin
  if position('pedido_com_beneficio_equipa' in v_def) > 0 then return; end if;
  v_novo := replace(v_def, 'if not funcionalidade_activa(''indicacao'') then return new; end if;',
                    'if not funcionalidade_activa(''indicacao'') then return new; end if;
  if pedido_com_beneficio_equipa(new.id) then return new; end if;');
  if v_novo = v_def then raise exception 'processar_ganho_indicacao não tem o formato esperado'; end if;
  execute v_novo;
end $$;

-- As contas das equipas não aparecem na lista das empresas
do $$
declare
  v_def  text := pg_get_functiondef('listar_empresas()'::regprocedure);
  v_novo text;
begin
  if position('equipas' in v_def) > 0 then return; end if;
  v_novo := replace(v_def, 'from empresas e where e.deletado_em is null',
                    'from empresas e where e.deletado_em is null and not exists (select 1 from equipas q where q.empresa_id = e.id)');
  if v_novo = v_def then raise exception 'listar_empresas não tem o formato esperado'; end if;
  execute v_novo;
end $$;

-- «Só a cozinha»: sem comissão da plataforma nesses pedidos
create or replace function acerto_valores_pedido(p pedidos, p_sinal int) returns jsonb
language sql stable security definer set search_path = public as $$
  with k as (select case when p.sem_comissao then 0 else coalesce(comissao_percent, 0) end as pct,
                    coalesce(convida_cozinha_percent, 0) as cv
               from cozinhas where id = p.cozinha_id),
  v as (
    select p.subtotal::int as vendas, p.taxa_entrega::int as taxas,
           round(p.subtotal * k.pct / 100)::int as comissao,
           round((p.desconto_indicacao + p.credito_indicacao_usado) * (100 - k.cv) / 100)::int as convida,
           coalesce(p.pago_pacote, 0)::int as pacote,
           coalesce(p.valor_empresa, 0)::int as empresa
      from k)
  select jsonb_build_object(
    'vendas', p_sinal * vendas, 'taxas_entrega', p_sinal * taxas, 'comissao', p_sinal * comissao,
    'convida_plataforma', p_sinal * convida, 'pago_pacote', p_sinal * pacote, 'valor_empresa', p_sinal * empresa,
    'saldo', p_sinal * ((taxas + comissao) - (convida + pacote + empresa)))
  from v;
$$;
revoke execute on function acerto_valores_pedido(pedidos, int) from public, anon, authenticated;

-- ------------------------------------------------------------------ 4. benefício ao entregar
create or replace function pedidos_beneficio_equipa() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e equipas;
  a equipa_acordos;
  v_mes date;
  v_pct numeric;
  v_base int;
  v_valor int;
begin
  if new.grupo_id is null or new.estado is not distinct from old.estado then return new; end if;
  if old.estado = 'entregue_pago' and new.estado <> 'entregue_pago' then
    update equipa_beneficios set estado = 'anulado' where pedido_id = new.id and estado <> 'pago';
    return new;
  end if;
  if new.estado <> 'entregue_pago' then return new; end if;
  e := equipa_do_grupo(new.grupo_id);
  if e.id is null then return new; end if;
  a := acordo_activo(e.id);
  if a.id is null then return new; end if;
  v_mes := date_trunc('month', new.criado_em at time zone 'Africa/Luanda')::date;
  v_pct := (equipa_escalao(e.id, v_mes) ->> 'pct')::numeric;
  -- Base: o prato com as opções, pelo valor pago; sem a taxa de entrega; bebidas só se o acordo disser
  v_base := greatest(new.subtotal - case when a.conta_bebidas then 0 else valor_bebidas_dos_itens(new.itens) end
                     - coalesce(new.desconto_indicacao, 0), 0);
  v_valor := least(round(v_base * v_pct / 100)::int, a.tecto_refeicao * greatest(refeicoes_dos_itens(new.itens), 1));
  insert into equipa_beneficios (equipa_id, acordo_id, pedido_id, cliente_id, responsavel_id, mes, base, pct, valor,
                                 parte_cozinha, estado)
  values (e.id, a.id, new.id, new.cliente_id, e.responsavel_id, v_mes, v_base, v_pct, v_valor,
          case a.quem_paga when 'cozinha' then v_valor
                           when 'plataforma_cozinha' then round(v_valor * a.parte_cozinha_pct / 100)::int else 0 end,
          -- Pago no dia (fora da conta): desbloqueado logo
          case when coalesce(new.valor_empresa, 0) = 0 then 'desbloqueado' else 'pendente' end)
  on conflict (pedido_id) do nothing;
  return new;
end $$;
revoke execute on function pedidos_beneficio_equipa() from public, anon, authenticated;
drop trigger if exists trg_pedidos_beneficio_equipa on pedidos;
create trigger trg_pedidos_beneficio_equipa after update of estado on pedidos
  for each row execute function pedidos_beneficio_equipa();

-- ------------------------------------------------------------------ 5. cliente: equipa e colegas
create or replace function exigir_equipas() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v uuid := cliente_actual();
begin
  if not funcionalidade_activa('equipas_trabalho') then raise exception 'funcionalidade_desligada' using errcode = 'P0001'; end if;
  if v is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  return v;
end $$;
revoke execute on function exigir_equipas() from public, anon, authenticated;

create or replace function criar_equipa(p_nome text, p_ponto uuid, p_cozinha uuid, p_hora time,
                                        p_prazo_minutos integer default 90, p_dias smallint[] default '{1,2,3,4,5}')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
  v_emp uuid;
  v_id uuid;
begin
  if not exists (select 1 from enderecos_cliente where cliente_id = v_cli and ponto_entrega_id = p_ponto and deletado_em is null) then
    raise exception 'grupo_ponto_invalido' using errcode = 'P0001';
  end if;
  if not cozinha_aceita_pedidos(p_cozinha) then raise exception 'cozinha_indisponivel' using errcode = 'P0001'; end if;
  if exists (select 1 from equipa_membros where cliente_id = v_cli and estado = 'activo') then
    raise exception 'ja_tem_equipa' using errcode = 'P0001';
  end if;
  insert into empresas (dispositivo_id, nome, limite_refeicao, activa)
  values ('servidor', 'Equipa · ' || trim(p_nome), 0, true) returning id into v_emp;
  insert into equipas (nome, responsavel_id, cozinha_id, ponto_entrega_id, hora_entrega, prazo_minutos, dias, empresa_id)
  values (trim(p_nome), v_cli, p_cozinha, p_ponto, p_hora, p_prazo_minutos, p_dias, v_emp) returning id into v_id;
  insert into equipa_membros (equipa_id, cliente_id, estado, aceite_em) values (v_id, v_cli, 'activo', now());
  perform registar_auditoria('equipa_criada', 'equipas', v_id, jsonb_build_object('nome', trim(p_nome)));
  return v_id;
end $$;

create or replace function editar_equipa(p_equipa uuid, p_nome text, p_hora time, p_prazo_minutos integer, p_dias smallint[], p_activa boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_cli uuid := exigir_equipas();
begin
  update equipas set nome = trim(p_nome), hora_entrega = p_hora, prazo_minutos = p_prazo_minutos, dias = p_dias,
                     activa = p_activa, atualizado_em = now()
   where id = p_equipa and responsavel_id = v_cli and deletado_em is null;
  if not found then raise exception 'sem_permissao' using errcode = '42501'; end if;
end $$;

-- A responsável junta um colega pelo código dele (MB4812 ou MB-4812); o colega aceita ou recusa
create or replace function equipa_convidar(p_equipa uuid, p_codigo text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
  e equipas;
  v_alvo uuid;
  v_cod text := upper(replace(replace(trim(coalesce(p_codigo, '')), '-', ''), ' ', ''));
begin
  select * into e from equipas where id = p_equipa and responsavel_id = v_cli and deletado_em is null;
  if not found then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select cliente_id into v_alvo from codigos_indicacao where upper(replace(codigo, '-', '')) = v_cod and deletado_em is null;
  if v_alvo is null then raise exception 'codigo_invalido' using errcode = 'P0001'; end if;
  if v_alvo = v_cli then raise exception 'codigo_proprio' using errcode = 'P0001'; end if;
  insert into equipa_membros (equipa_id, cliente_id, estado) values (e.id, v_alvo, 'convidado')
  on conflict (equipa_id, cliente_id) do update set estado = 'convidado', atualizado_em = now()
    where equipa_membros.estado = 'saiu';
  perform aviso_cliente(v_alvo, 'Convite para a equipa ' || e.nome,
    nome_curto(v_cli) || ' convidou-te para almoçar com a equipa «' || e.nome || '». Abre para aceitar.');
  return (select nome from clientes where id = v_alvo);
end $$;

create or replace function equipa_responder(p_equipa uuid, p_aceitar boolean, p_pode_pedir boolean default false,
                                            p_pode_ver_conta boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
  e equipas;
begin
  select * into e from equipas where id = p_equipa and deletado_em is null;
  if not exists (select 1 from equipa_membros where equipa_id = p_equipa and cliente_id = v_cli and estado = 'convidado') then
    raise exception 'sem_convite' using errcode = 'P0001';
  end if;
  if p_aceitar and exists (select 1 from equipa_membros where cliente_id = v_cli and estado = 'activo') then
    raise exception 'ja_tem_equipa' using errcode = 'P0001';
  end if;
  update equipa_membros
     set estado = case when p_aceitar then 'activo' else 'saiu' end,
         pode_pedir = p_aceitar and coalesce(p_pode_pedir, false),
         pode_ver_conta = p_aceitar and coalesce(p_pode_ver_conta, false),
         aceite_em = case when p_aceitar then now() end, atualizado_em = now()
   where equipa_id = p_equipa and cliente_id = v_cli;
  perform aviso_cliente(e.responsavel_id, case when p_aceitar then 'Mais um na equipa' else 'Convite recusado' end,
    nome_curto(v_cli) || case when p_aceitar then ' entrou na equipa «' || e.nome || '».' else ' não aceitou o convite para «' || e.nome || '».' end);
end $$;

-- O colega muda as autorizações quando quiser (Cialdini: ele decide e pode retirar)
create or replace function equipa_autorizacoes(p_equipa uuid, p_pode_pedir boolean, p_pode_ver_conta boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_cli uuid := exigir_equipas();
begin
  update equipa_membros set pode_pedir = coalesce(p_pode_pedir, false), pode_ver_conta = coalesce(p_pode_ver_conta, false),
                            atualizado_em = now()
   where equipa_id = p_equipa and cliente_id = v_cli and estado = 'activo';
  if not found then raise exception 'sem_permissao' using errcode = '42501'; end if;
end $$;

-- Sair (o próprio) ou tirar um colega (a responsável). A responsável não sai: desactiva a equipa.
create or replace function equipa_sair(p_equipa uuid, p_cliente uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
  e equipas;
  v_alvo uuid := coalesce(p_cliente, v_cli);
begin
  select * into e from equipas where id = p_equipa;
  if v_alvo <> v_cli and e.responsavel_id <> v_cli then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if v_alvo = e.responsavel_id then raise exception 'responsavel_nao_sai' using errcode = 'P0001'; end if;
  update equipa_membros set estado = 'saiu', pode_pedir = false, pode_ver_conta = false, atualizado_em = now()
   where equipa_id = p_equipa and cliente_id = v_alvo and estado <> 'saiu';
end $$;

-- Grupo do dia da equipa: o de hoje (ou o próximo já aberto); null se não há
create or replace function equipa_grupo_hoje(p_equipa uuid) returns pedidos_grupo
language sql stable security definer set search_path = public as $$
  select * from pedidos_grupo where equipa_id = p_equipa and dia_equipa >= hoje_luanda() and deletado_em is null
   order by dia_equipa limit 1;
$$;
revoke execute on function equipa_grupo_hoje(uuid) from public, anon, authenticated;

-- Tudo o que a app mostra: as minhas equipas, convites, hoje, colegas e (responsável) benefício
create or replace function minhas_equipas() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
  r jsonb := '[]';
  e equipas;
  m equipa_membros;
  g pedidos_grupo;
  a equipa_acordos;
  v_resp boolean;
  rec record;
  v_mes date := date_trunc('month', hoje_luanda())::date;
begin
  for rec in select q.id as eid, x.id as mid from equipas q join equipa_membros x on x.equipa_id = q.id
               where x.cliente_id = v_cli and x.estado in ('convidado', 'activo') and q.deletado_em is null
               order by x.estado, q.nome loop
    select * into e from equipas where id = rec.eid;
    select * into m from equipa_membros where id = rec.mid;
    v_resp := e.responsavel_id = v_cli;
    g := equipa_grupo_hoje(e.id);
    a := acordo_activo(e.id);
    r := r || jsonb_build_object(
      'id', e.id, 'nome', e.nome, 'sou_responsavel', v_resp, 'estado', m.estado, 'cozinha_id', e.cozinha_id,
      'responsavel', nome_curto(e.responsavel_id),
      'cozinha', (select nome from cozinhas where id = e.cozinha_id),
      'local', (select ec.nome from enderecos_cliente ec where ec.ponto_entrega_id = e.ponto_entrega_id and ec.cliente_id = e.responsavel_id and ec.deletado_em is null limit 1),
      'hora_entrega', to_char(e.hora_entrega, 'HH24:MI'), 'prazo_minutos', e.prazo_minutos, 'dias', to_jsonb(e.dias),
      'limite_mensal', e.limite_mensal, 'activa', e.activa,
      'pode_pedir', m.pode_pedir, 'pode_ver_conta', m.pode_ver_conta, 'em_atraso', m.em_atraso,
      'hoje', case when g.id is not null then jsonb_build_object(
                'grupo_id', g.id, 'codigo', g.codigo_convite, 'estado', g.estado, 'prazo', g.prazo_adesao, 'hora', g.hora_entrega,
                'meu_pedido', (select jsonb_build_object('id', p.id, 'estado', p.estado, 'pedido_por',
                                                         case when p.pedido_por is not null then nome_curto(p.pedido_por) end,
                                                         'itens', (select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || coalesce(i ->> 'nome', 'prato'), ', ')
                                                                     from jsonb_array_elements(p.itens) i))
                                 from pedidos p where p.grupo_id = g.id and p.cliente_id = v_cli and p.deletado_em is null
                                  and p.estado not in ('cancelado', 'estornado') order by p.criado_em desc limit 1),
                'pedidos', (select count(*) from pedidos p where p.grupo_id = g.id and p.deletado_em is null
                                                               and p.estado not in ('cancelado', 'estornado')))
              end,
      'extras_hoje', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'quantidade', x.quantidade, 'aprovadas', x.aprovadas,
                                                                   'estado', x.estado, 'motivo', x.motivo)), '[]'::jsonb)
                        from equipa_extras x where x.equipa_id = e.id and x.cliente_id = v_cli and x.dia = hoje_luanda()),
      'acordo', case when a.id is not null then jsonb_build_object('quem_paga', a.quem_paga) end,
      -- Colegas: a responsável vê quem já pediu hoje e as autorizações; os outros só os nomes
      'colegas', (select coalesce(jsonb_agg(jsonb_build_object(
                    'cliente_id', x.cliente_id, 'nome', c.nome, 'estado', x.estado,
                    'pode_pedir', case when v_resp then x.pode_pedir end,
                    'pode_ver_conta', case when v_resp then x.pode_ver_conta end,
                    'em_atraso', case when v_resp and x.pode_ver_conta then x.em_atraso end,
                    'pediu_hoje', case when v_resp and g.id is not null then exists (
                                    select 1 from pedidos p where p.grupo_id = g.id and p.cliente_id = x.cliente_id
                                       and p.deletado_em is null and p.estado not in ('cancelado', 'estornado')) end)
                    order by (x.cliente_id = e.responsavel_id) desc, c.nome), '[]'::jsonb)
                    from equipa_membros x join clientes c on c.id = x.cliente_id
                   where x.equipa_id = e.id and x.estado in ('convidado', 'activo')
                     and (m.estado = 'activo')),
      'beneficio', case when v_resp and a.id is not null then jsonb_build_object(
                     'escalao', equipa_escalao(e.id, v_mes),
                     'mes_pendente', (select coalesce(sum(valor), 0) from equipa_beneficios where equipa_id = e.id and mes = v_mes and estado = 'pendente'),
                     'desbloqueado', (select coalesce(sum(valor), 0) from equipa_beneficios where equipa_id = e.id and estado = 'desbloqueado'),
                     'pago', (select coalesce(sum(valor), 0) from equipa_beneficios where equipa_id = e.id and estado = 'pago'),
                     'colegas_por_pagar', (select count(distinct cliente_id) from equipa_beneficios where equipa_id = e.id and estado = 'pendente'))
                   end);
  end loop;
  return r;
end $$;

-- Pedir o almoço em nome do colega (só com a autorização dele e antes do prazo); ele é avisado e pode recusar
create or replace function pedir_por_colega(p_equipa uuid, p_cliente uuid, p_itens jsonb, p_id uuid default gen_random_uuid())
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
  e equipas;
  g pedidos_grupo;
  o jsonb;
begin
  select * into e from equipas where id = p_equipa and responsavel_id = v_cli and activa and deletado_em is null;
  if not found then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not exists (select 1 from equipa_membros where equipa_id = e.id and cliente_id = p_cliente and estado = 'activo' and pode_pedir) then
    raise exception 'sem_autorizacao_do_colega' using errcode = 'P0001';
  end if;
  g := equipa_grupo_hoje(e.id);
  if g.id is null or g.estado <> 'aberto' or g.prazo_adesao <= now() then
    raise exception 'grupo_fechado' using errcode = 'P0001';
  end if;
  if exists (select 1 from pedidos where grupo_id = g.id and cliente_id = p_cliente and deletado_em is null
                                     and estado not in ('cancelado', 'estornado')) then
    raise exception 'colega_ja_pediu' using errcode = 'P0001';
  end if;
  o := orcamento_pedido(p_itens, g.ponto_entrega_id, g.cozinha_id, g.id);
  insert into pedidos (id, dispositivo_id, cliente_id, ponto_entrega_id, grupo_id, cozinha_id, itens, subtotal, taxa_entrega,
                       zona_id, campanha_id, pedido_por, estado, observacoes)
  values (p_id, 'servidor', p_cliente, g.ponto_entrega_id, g.id, g.cozinha_id, o -> 'itens', (o ->> 'subtotal')::int,
          (o ->> 'taxa_entrega')::int, (o ->> 'zona_id')::uuid, nullif(o ->> 'campanha_id', '')::uuid, v_cli, 'pendente',
          'Pedido por ' || nome_curto(v_cli));
  perform aviso_cliente(p_cliente, nome_curto(v_cli) || ' pediu o teu almoço',
    (select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || coalesce(i ->> 'nome', 'prato'), ', ') from jsonb_array_elements(o -> 'itens') i)
    || '. Podes trocar ou recusar até às ' || to_char(g.prazo_adesao at time zone 'Africa/Luanda', 'HH24"h"MI') || '.');
  perform registar_auditoria('pedido_por_colega', 'pedidos', p_id, jsonb_build_object('responsavel', v_cli, 'colega', p_cliente));
  return p_id;
end $$;

-- O prato habitual do colega (o último almoço dele na equipa) para a responsável repetir
create or replace function prato_habitual_colega(p_equipa uuid, p_cliente uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
begin
  if not exists (select 1 from equipas where id = p_equipa and responsavel_id = v_cli)
     or not exists (select 1 from equipa_membros where equipa_id = p_equipa and cliente_id = p_cliente and estado = 'activo' and pode_pedir) then
    raise exception 'sem_autorizacao_do_colega' using errcode = 'P0001';
  end if;
  return (select jsonb_build_object('itens', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                                                'cardapio_id', i -> 'cardapio_id', 'qtd', i -> 'qtd',
                                                'opcoes', (select jsonb_agg(o -> 'id') from jsonb_array_elements(coalesce(i -> 'opcoes', '[]')) o),
                                                'componentes_excluidos', i -> 'componentes_excluidos')))
                                              from jsonb_array_elements(p.itens) i),
                                    'texto', (select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || coalesce(i ->> 'nome', 'prato'), ', ')
                                                from jsonb_array_elements(p.itens) i))
            from pedidos p join pedidos_grupo g on g.id = p.grupo_id
           where g.equipa_id = p_equipa and p.cliente_id = p_cliente and p.estado = 'entregue_pago' and p.deletado_em is null
           order by p.criado_em desc limit 1);
end $$;

-- O colega recusa o almoço pedido por ele (até ao prazo)
create or replace function recusar_pedido_colega(p_pedido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
  p pedidos;
  g pedidos_grupo;
begin
  select * into p from pedidos where id = p_pedido and cliente_id = v_cli and pedido_por is not null and deletado_em is null for update;
  if not found then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into g from pedidos_grupo where id = p.grupo_id;
  if p.estado <> 'pendente' or g.prazo_adesao <= now() then raise exception 'ja_nao_se_pode_recusar' using errcode = 'P0001'; end if;
  update pedidos set estado = 'cancelado', motivo_cancelamento = 'Recusado pelo colega', atualizado_em = now() where id = p.id;
  perform aviso_cliente(p.pedido_por, nome_curto(v_cli) || ' recusou o almoço',
    nome_curto(v_cli) || ' não quer o almoço que pediste hoje. Já não vai na entrega.');
end $$;

-- Pedir mais refeições hoje (quantas e porquê); a cozinha aprova tudo, parte ou recusa até ao prazo
create or replace function pedir_refeicoes_extra(p_equipa uuid, p_quantidade integer, p_motivo text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
  e equipas;
  g pedidos_grupo;
  v_id uuid;
begin
  select * into e from equipas where id = p_equipa and deletado_em is null;
  if not exists (select 1 from equipa_membros where equipa_id = p_equipa and cliente_id = v_cli and estado = 'activo') then
    raise exception 'nao_e_da_equipa' using errcode = 'P0001';
  end if;
  g := equipa_grupo_hoje(e.id);
  if g.id is null or g.prazo_adesao <= now() then raise exception 'grupo_fechado' using errcode = 'P0001'; end if;
  insert into equipa_extras (equipa_id, cliente_id, dia, quantidade, motivo)
  values (e.id, v_cli, hoje_luanda(), p_quantidade, trim(p_motivo)) returning id into v_id;
  -- Aviso a quem gere os pedidos dessa cozinha
  insert into notificacoes_fila (funcionario_id, codigo, dados)
  select f.id, 'N32', jsonb_build_object('titulo', 'Pedido de refeições extra',
           'corpo', format('%s (equipa %s) pede mais %s refeição(ões) hoje: %s. Decide até às %s.', nome_curto(v_cli), e.nome,
                           p_quantidade, trim(p_motivo), to_char(g.prazo_adesao at time zone 'Africa/Luanda', 'HH24"h"MI')),
           'link', '/equipas')
    from funcionarios f
   where f.deletado_em is null and funcionario_tem_permissao(f.id, 'pedidos.gerir')
     and funcionario_ve_cozinha(f.id, e.cozinha_id);
  return v_id;
end $$;

-- ------------------------------------------------------------------ 6. conta do mês
create or replace function conta_mes(p_equipa uuid, p_cliente uuid default null, p_mes date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cli uuid := cliente_actual();
  v_alvo uuid := coalesce(p_cliente, v_cli);
begin
  if v_cli is null and not tem_permissao('financas.acertos') and not tem_permissao('pedidos.gerir') then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if v_cli is not null and v_alvo <> v_cli and not exists (
       select 1 from equipas e join equipa_membros m on m.equipa_id = e.id
        where e.id = p_equipa and e.responsavel_id = v_cli and m.cliente_id = v_alvo and m.pode_ver_conta) then
    raise exception 'sem_autorizacao_do_colega' using errcode = '42501';
  end if;
  if not exists (select 1 from equipa_membros where equipa_id = p_equipa and cliente_id = v_alvo) then
    raise exception 'nao_e_da_equipa' using errcode = 'P0001';
  end if;
  return conta_mes_resumo(p_equipa, v_alvo, coalesce(p_mes, hoje_luanda()));
end $$;

-- Pagar a conta (o próprio, ou a responsável autorizada em nome dele) por referência; as Finanças confirmam
create or replace function pagar_conta_mes(p_equipa uuid, p_cliente uuid, p_mes date, p_metodo text, p_referencia text, p_valor integer)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := exigir_equipas();
  v_ref text := upper(regexp_replace(coalesce(p_referencia, ''), '\s', '', 'g'));
  v_id uuid;
  r jsonb;
begin
  if p_metodo not in ('multicaixa_express', 'unitel_money') then raise exception 'metodo_invalido' using errcode = 'P0001'; end if;
  if length(v_ref) < 4 then raise exception 'referencia_invalida' using errcode = 'P0001'; end if;
  r := conta_mes(p_equipa, p_cliente, p_mes);   -- valida quem pode
  if p_valor is null or p_valor <= 0 or p_valor > (r ->> 'em_falta')::int - (r ->> 'a_confirmar')::int then
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
  if exists (select 1 from pagamentos_antecipados where referencia_chave = v_ref and estado <> 'rejeitado') then
    raise exception 'referencia_repetida' using errcode = 'P0001';
  end if;
  insert into contas_mes_pagamentos (equipa_id, cliente_id, mes, valor, metodo, referencia, referencia_chave, pago_por)
  values (p_equipa, p_cliente, date_trunc('month', p_mes)::date, p_valor, p_metodo, trim(p_referencia), v_ref, v_cli)
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'referencia_repetida' using errcode = 'P0001';
end $$;

-- ------------------------------------------------------------------ 7. operador
create or replace function equipas_operador() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (tem_permissao('pedidos.gerir') or tem_permissao('financas.acertos') or tem_permissao('clientes.gerir')) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', e.id, 'nome', e.nome, 'responsavel', (select nome from clientes where id = e.responsavel_id),
            'cozinha_id', e.cozinha_id, 'cozinha', k.nome, 'activa', e.activa, 'origem', e.origem, 'limite_mensal', e.limite_mensal,
            'hora_entrega', to_char(e.hora_entrega, 'HH24:MI'),
            'membros', (select count(*) from equipa_membros m where m.equipa_id = e.id and m.estado = 'activo'),
            'extras_pendentes', (select count(*) from equipa_extras x where x.equipa_id = e.id and x.estado = 'pendente' and x.dia = hoje_luanda()),
            'pagamentos_por_confirmar', (select count(*) from contas_mes_pagamentos p where p.equipa_id = e.id and p.estado = 'pendente'),
            'em_atraso', (select count(*) from equipa_membros m where m.equipa_id = e.id and m.em_atraso),
            'acordo', (select jsonb_build_object('id', a.id, 'estado', a.estado, 'quem_paga', a.quem_paga)
                         from equipa_acordos a where a.equipa_id = e.id and a.estado in ('proposto', 'activo')))
            order by e.nome), '[]'::jsonb)
            from equipas e join cozinhas k on k.id = e.cozinha_id
           where e.deletado_em is null and (funcionario_ve_cozinha(funcionario_actual(), e.cozinha_id) or tem_permissao('financas.acertos')));
end $$;

create or replace function equipa_operador(p_equipa uuid, p_mes date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e equipas;
  v_mes date := date_trunc('month', coalesce(p_mes, hoje_luanda()))::date;
begin
  if not (tem_permissao('pedidos.gerir') or tem_permissao('financas.acertos') or tem_permissao('clientes.gerir')) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  select * into e from equipas where id = p_equipa;
  return jsonb_build_object(
    'id', e.id, 'nome', e.nome, 'origem', e.origem, 'limite_mensal', e.limite_mensal, 'activa', e.activa,
    'responsavel', (select nome from clientes where id = e.responsavel_id), 'responsavel_id', e.responsavel_id,
    'cozinha', (select nome from cozinhas where id = e.cozinha_id), 'mes', v_mes,
    'hora_entrega', to_char(e.hora_entrega, 'HH24:MI'), 'prazo_minutos', e.prazo_minutos, 'dias', to_jsonb(e.dias),
    'grupo_hoje', (select jsonb_build_object('id', g.id, 'estado', g.estado, 'prazo', g.prazo_adesao,
                                             'pedidos', (select count(*) from pedidos p where p.grupo_id = g.id and p.estado not in ('cancelado', 'estornado')))
                     from pedidos_grupo g where g.id = (equipa_grupo_hoje(e.id)).id),
    'extras', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'cliente', c.nome, 'quantidade', x.quantidade, 'motivo', x.motivo,
                                                            'estado', x.estado, 'aprovadas', x.aprovadas, 'dia', x.dia) order by x.criado_em desc), '[]'::jsonb)
                 from equipa_extras x join clientes c on c.id = x.cliente_id where x.equipa_id = e.id and x.dia >= hoje_luanda() - 7),
    'contas', (select coalesce(jsonb_agg(conta_mes_resumo(e.id, m.cliente_id, v_mes) - 'linhas' order by c.nome), '[]'::jsonb)
                 from equipa_membros m join clientes c on c.id = m.cliente_id where m.equipa_id = e.id and m.estado <> 'convidado'),
    'pagamentos_pendentes', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'cliente', c.nome, 'valor', p.valor, 'metodo', p.metodo,
                                                                          'referencia', p.referencia, 'mes', p.mes, 'criado_em', p.criado_em)
                                                       order by p.criado_em), '[]'::jsonb)
                               from contas_mes_pagamentos p join clientes c on c.id = p.cliente_id
                              where p.equipa_id = e.id and p.estado = 'pendente'),
    'acordo', (select to_jsonb(a) from equipa_acordos a where a.equipa_id = e.id and a.estado in ('proposto', 'activo')),
    'escalao', equipa_escalao(e.id, v_mes),
    'beneficios', jsonb_build_object(
      'pendente', (select coalesce(sum(valor), 0) from equipa_beneficios where equipa_id = e.id and estado = 'pendente'),
      'desbloqueado', (select coalesce(sum(valor), 0) from equipa_beneficios where equipa_id = e.id and estado = 'desbloqueado'),
      'parte_cozinha_desbloqueada', (select coalesce(sum(parte_cozinha), 0) from equipa_beneficios where equipa_id = e.id and estado = 'desbloqueado'),
      'pago', (select coalesce(sum(valor), 0) from equipa_beneficios where equipa_id = e.id and estado = 'pago'),
      'mes', (select coalesce(sum(valor), 0) from equipa_beneficios where equipa_id = e.id and mes = v_mes and estado <> 'anulado'),
      'parte_cozinha_mes', (select coalesce(sum(parte_cozinha), 0) from equipa_beneficios where equipa_id = e.id and mes = v_mes and estado <> 'anulado')));
end $$;

-- Limite mensal, origem (quem trouxe a equipa) e estado: quem gere clientes
create or replace function definir_equipa(p_equipa uuid, p_limite integer, p_origem text, p_activa boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('clientes.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  update equipas set limite_mensal = p_limite, origem = p_origem, activa = p_activa, atualizado_em = now() where id = p_equipa;
  perform registar_auditoria('equipa_definida', 'equipas', p_equipa,
                             jsonb_build_object('limite', p_limite, 'origem', p_origem, 'activa', p_activa));
end $$;

-- A cozinha decide o pedido extra: aprova tudo (= quantidade), parte, ou recusa (0)
create or replace function decidir_extra(p_extra uuid, p_aprovadas integer) returns void
language plpgsql security definer set search_path = public as $$
declare
  x equipa_extras;
  e equipas;
begin
  if not tem_permissao('pedidos.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into x from equipa_extras where id = p_extra and estado = 'pendente' for update;
  if not found then raise exception 'ja_decidido' using errcode = 'P0001'; end if;
  select * into e from equipas where id = x.equipa_id;
  if not funcionario_ve_cozinha(funcionario_actual(), e.cozinha_id) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_aprovadas is null or p_aprovadas < 0 or p_aprovadas > x.quantidade then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  update equipa_extras set aprovadas = p_aprovadas, estado = case when p_aprovadas > 0 then 'aprovado' else 'recusado' end,
                           decidido_por = funcionario_actual(), decidido_em = now()
   where id = x.id;
  perform aviso_cliente(x.cliente_id,
    case when p_aprovadas = 0 then 'Refeições extra recusadas' else 'Refeições extra aprovadas' end,
    case when p_aprovadas = 0 then 'A cozinha não consegue fazer mais refeições hoje.'
         when p_aprovadas < x.quantidade then format('A cozinha aprovou %s das %s refeições que pediste. Já podes pedir.', p_aprovadas, x.quantidade)
         else format('A cozinha aprovou as %s refeições. Já podes pedir.', p_aprovadas) end);
end $$;

-- Dinheiro recebido pela cozinha («Recebi em dinheiro…»): fica logo confirmado
create or replace function registar_dinheiro_conta_mes(p_equipa uuid, p_cliente uuid, p_mes date, p_valor integer, p_pago_por uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  e equipas;
  r jsonb;
  v_id uuid;
begin
  if not tem_permissao('pedidos.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into e from equipas where id = p_equipa;
  if not funcionario_ve_cozinha(funcionario_actual(), e.cozinha_id) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  r := conta_mes_resumo(p_equipa, p_cliente, p_mes);
  if p_valor is null or p_valor <= 0 or p_valor > (r ->> 'em_falta')::int then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  insert into contas_mes_pagamentos (equipa_id, cliente_id, mes, valor, metodo, pago_por, estado, registado_por, decidido_por, decidido_em)
  values (p_equipa, p_cliente, date_trunc('month', p_mes)::date, p_valor, 'dinheiro', coalesce(p_pago_por, p_cliente), 'confirmado',
          funcionario_actual(), funcionario_actual(), now())
  returning id into v_id;
  perform registar_auditoria('conta_mes_dinheiro', 'contas_mes_pagamentos', v_id,
                             jsonb_build_object('valor', p_valor, 'cliente', p_cliente, 'mes', p_mes));
  perform equipa_recalcular_conta(p_equipa, p_cliente, p_mes);
  perform aviso_cliente(p_cliente, 'Pagamento recebido',
    format('A cozinha recebeu %s em dinheiro para a tua conta de %s. Obrigado!', formatar_kz(p_valor), to_char(p_mes, 'MM/YYYY')));
  return v_id;
end $$;

-- As Finanças confirmam (ou rejeitam, com motivo) o pagamento por referência
create or replace function decidir_pagamento_conta_mes(p_id uuid, p_confirmar boolean, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare x contas_mes_pagamentos;
begin
  if not tem_permissao('financas.acertos') then raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.acertos'; end if;
  select * into x from contas_mes_pagamentos where id = p_id for update;
  if not found or x.estado <> 'pendente' then raise exception 'pagamento_ja_decidido' using errcode = 'P0001'; end if;
  if not p_confirmar and coalesce(trim(p_motivo), '') = '' then raise exception 'motivo_obrigatorio' using errcode = 'P0001'; end if;
  update contas_mes_pagamentos set estado = case when p_confirmar then 'confirmado' else 'rejeitado' end,
                                   motivo = case when p_confirmar then null else trim(p_motivo) end,
                                   decidido_por = funcionario_actual(), decidido_em = now()
   where id = x.id;
  if p_confirmar then perform equipa_recalcular_conta(x.equipa_id, x.cliente_id, x.mes); end if;
  perform aviso_cliente(coalesce(x.pago_por, x.cliente_id),
    case when p_confirmar then 'Pagamento confirmado' else 'Pagamento não confirmado' end,
    case when p_confirmar then format('Recebemos %s da conta de %s.', formatar_kz(x.valor), to_char(x.mes, 'MM/YYYY'))
         else 'Não encontrámos o pagamento: ' || trim(p_motivo) end);
end $$;

-- Acordo: proposto pelas Finanças/comercial, aceite pela cozinha; «só a cozinha» só para equipas que ela trouxe
create or replace function propor_acordo_equipa(p_equipa uuid, p_quem_paga text, p_parte_cozinha_pct numeric default 50,
                                                p_pct_1 numeric default 3, p_pct_2 numeric default 5, p_pct_3 numeric default 10,
                                                p_limite_2 integer default 10, p_limite_3 integer default 15,
                                                p_conta_bebidas boolean default false, p_tecto integer default 1000)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  e equipas;
  v_id uuid;
begin
  if not tem_permissao('financas.acertos') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into e from equipas where id = p_equipa and deletado_em is null;
  if not found then raise exception 'equipa_inexistente' using errcode = 'P0001'; end if;
  if p_quem_paga = 'cozinha' and e.origem <> 'cozinha' then raise exception 'so_cozinha_exige_origem_cozinha' using errcode = 'P0001'; end if;
  update equipa_acordos set estado = 'terminado', terminado_em = now() where equipa_id = p_equipa and estado = 'proposto';
  insert into equipa_acordos (equipa_id, quem_paga, parte_cozinha_pct, pct_1, pct_2, pct_3, limite_2, limite_3,
                              conta_bebidas, tecto_refeicao, criado_por)
  values (p_equipa, p_quem_paga, p_parte_cozinha_pct, p_pct_1, p_pct_2, p_pct_3, p_limite_2, p_limite_3,
          p_conta_bebidas, p_tecto, funcionario_actual())
  returning id into v_id;
  perform registar_auditoria('acordo_equipa_proposto', 'equipa_acordos', v_id, jsonb_build_object('quem_paga', p_quem_paga));
  return v_id;
end $$;

create or replace function aceitar_acordo_equipa(p_acordo uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  a equipa_acordos;
  e equipas;
begin
  if not tem_permissao('pedidos.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into a from equipa_acordos where id = p_acordo and estado = 'proposto' for update;
  if not found then raise exception 'acordo_inexistente' using errcode = 'P0001'; end if;
  select * into e from equipas where id = a.equipa_id;
  if not funcionario_ve_cozinha(funcionario_actual(), e.cozinha_id) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  update equipa_acordos set estado = 'terminado', terminado_em = now() where equipa_id = a.equipa_id and estado = 'activo';
  update equipa_acordos set estado = 'activo', aceite_por = funcionario_actual(), aceite_em = now() where id = a.id;
  perform registar_auditoria('acordo_equipa_aceite', 'equipa_acordos', a.id, '{}'::jsonb);
  perform aviso_cliente(e.responsavel_id, 'O teu benefício começou',
    'A partir de hoje ganhas uma parte de cada almoço da equipa «' || e.nome || '». Vê quanto na tua equipa.');
end $$;

create or replace function terminar_acordo_equipa(p_acordo uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (tem_permissao('financas.acertos') or tem_permissao('pedidos.gerir')) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  update equipa_acordos set estado = 'terminado', terminado_em = now() where id = p_acordo and estado in ('proposto', 'activo');
  perform registar_auditoria('acordo_equipa_terminado', 'equipa_acordos', p_acordo, '{}'::jsonb);
end $$;

-- Pagar à responsável o benefício já desbloqueado (Finanças; ou a cozinha, quando é ela quem paga tudo)
create or replace function pagar_beneficio_equipa(p_equipa uuid, p_metodo text) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v int;
  e equipas;
begin
  select * into e from equipas where id = p_equipa;
  if not (tem_permissao('financas.acertos')
          or (tem_permissao('pedidos.gerir') and (acordo_activo(p_equipa)).quem_paga = 'cozinha'
              and funcionario_ve_cozinha(funcionario_actual(), e.cozinha_id))) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  with u as (update equipa_beneficios set estado = 'pago', pago_em = now(), pago_por = funcionario_actual(), metodo_pagamento = p_metodo
              where equipa_id = p_equipa and estado = 'desbloqueado' returning valor)
  select coalesce(sum(valor), 0) into v from u;
  if v > 0 then
    perform registar_auditoria('beneficio_equipa_pago', 'equipas', p_equipa, jsonb_build_object('valor', v, 'metodo', p_metodo));
    perform aviso_cliente(e.responsavel_id, 'Benefício pago', format('Recebeste %s do benefício da equipa «%s».', formatar_kz(v), e.nome));
  end if;
  return v;
end $$;

-- ------------------------------------------------------------------ 8. job: grupo do dia, «Vais almoçar hoje?», prazos, atrasos
-- Abre o grupo do dia de uma equipa e pergunta a cada colega «Vais almoçar hoje?»
create or replace function abrir_grupo_equipa(p_equipa uuid, p_dia date) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e equipas;
  v_hora timestamptz;
  v_prazo timestamptz;
  v_grupo uuid;
  m record;
begin
  select * into e from equipas where id = p_equipa and activa and deletado_em is null;
  if not found then return null; end if;
  v_hora := (p_dia + e.hora_entrega) at time zone 'Africa/Luanda';
  v_prazo := v_hora - make_interval(mins => e.prazo_minutos);
  if v_prazo <= now() + interval '10 minutes'
     or exists (select 1 from pedidos_grupo where equipa_id = e.id and dia_equipa = p_dia and deletado_em is null)
     or not cozinha_aceita_pedidos(e.cozinha_id) then
    return null;
  end if;
  insert into pedidos_grupo (dispositivo_id, organizador_id, ponto_entrega_id, cozinha_id, hora_entrega, prazo_adesao,
                             modo_pagamento, tipo, equipa_id, dia_equipa, estado)
  values ('servidor', e.responsavel_id, e.ponto_entrega_id, e.cozinha_id, v_hora, v_prazo, 'conta_mes', 'trabalho',
          e.id, p_dia, 'aberto')
  returning id into v_grupo;
  for m in select cliente_id from equipa_membros where equipa_id = e.id and estado = 'activo' loop
    perform aviso_cliente(m.cliente_id, 'Vais almoçar hoje?',
      format('O almoço da equipa «%s» chega às %s. Pede até às %s.', e.nome, to_char(e.hora_entrega, 'HH24"h"MI'),
             to_char(v_prazo at time zone 'Africa/Luanda', 'HH24"h"MI')));
  end loop;
  return v_grupo;
end $$;
revoke execute on function abrir_grupo_equipa(uuid, date) from public, anon, authenticated;

create or replace function job_equipas() returns void
language plpgsql security definer set search_path = public as $$
declare
  e equipas;
  v_hoje date := hoje_luanda();
  m record;
begin
  if not funcionalidade_activa('equipas_trabalho') then return; end if;
  -- Abre o grupo de hoje das equipas activas (a partir das 6h, até ao prazo)
  if extract(hour from now() at time zone 'Africa/Luanda') >= 6 then
    for e in select * from equipas
              where activa and deletado_em is null and extract(isodow from v_hoje)::smallint = any (dias) loop
      perform abrir_grupo_equipa(e.id, v_hoje);
    end loop;
  end if;
  -- Pedidos extra sem resposta até ao prazo ficam recusados
  update equipa_extras x set estado = 'recusado', aprovadas = 0, decidido_em = now()
    from pedidos_grupo g
   where x.estado = 'pendente' and g.equipa_id = x.equipa_id and g.dia_equipa = x.dia and g.prazo_adesao <= now();
  update equipa_extras set estado = 'recusado', aprovadas = 0, decidido_em = now() where estado = 'pendente' and dia < v_hoje;
  -- Atrasos (uma vez por dia, de manhã)
  if extract(hour from now() at time zone 'Africa/Luanda') = 6 then
    for m in select equipa_id, cliente_id from equipa_membros where estado = 'activo' loop
      perform equipa_actualizar_atraso(m.equipa_id, m.cliente_id);
    end loop;
  end if;
end $$;
revoke execute on function job_equipas() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_equipas', '*/10 * * * *', 'select public.job_equipas()');
  end if;
end $$;

-- ------------------------------------------------------------------ 9. permissões das funções da app
revoke execute on function criar_equipa(text, uuid, uuid, time, integer, smallint[]), editar_equipa(uuid, text, time, integer, smallint[], boolean),
  equipa_convidar(uuid, text), equipa_responder(uuid, boolean, boolean, boolean), equipa_autorizacoes(uuid, boolean, boolean),
  equipa_sair(uuid, uuid), minhas_equipas(), pedir_por_colega(uuid, uuid, jsonb, uuid), prato_habitual_colega(uuid, uuid),
  recusar_pedido_colega(uuid), pedir_refeicoes_extra(uuid, integer, text), conta_mes(uuid, uuid, date),
  pagar_conta_mes(uuid, uuid, date, text, text, integer), equipas_operador(), equipa_operador(uuid, date),
  definir_equipa(uuid, integer, text, boolean), decidir_extra(uuid, integer), registar_dinheiro_conta_mes(uuid, uuid, date, integer, uuid),
  decidir_pagamento_conta_mes(uuid, boolean, text),
  propor_acordo_equipa(uuid, text, numeric, numeric, numeric, numeric, integer, integer, boolean, integer),
  aceitar_acordo_equipa(uuid), terminar_acordo_equipa(uuid), pagar_beneficio_equipa(uuid, text)
  from public, anon;
grant execute on function criar_equipa(text, uuid, uuid, time, integer, smallint[]), editar_equipa(uuid, text, time, integer, smallint[], boolean),
  equipa_convidar(uuid, text), equipa_responder(uuid, boolean, boolean, boolean), equipa_autorizacoes(uuid, boolean, boolean),
  equipa_sair(uuid, uuid), minhas_equipas(), pedir_por_colega(uuid, uuid, jsonb, uuid), prato_habitual_colega(uuid, uuid),
  recusar_pedido_colega(uuid), pedir_refeicoes_extra(uuid, integer, text), conta_mes(uuid, uuid, date),
  pagar_conta_mes(uuid, uuid, date, text, text, integer), equipas_operador(), equipa_operador(uuid, date),
  definir_equipa(uuid, integer, text, boolean), decidir_extra(uuid, integer), registar_dinheiro_conta_mes(uuid, uuid, date, integer, uuid),
  decidir_pagamento_conta_mes(uuid, boolean, text),
  propor_acordo_equipa(uuid, text, numeric, numeric, numeric, numeric, integer, integer, boolean, integer),
  aceitar_acordo_equipa(uuid), terminar_acordo_equipa(uuid), pagar_beneficio_equipa(uuid, text)
  to authenticated;
revoke execute on function hoje_luanda() from public, anon;
grant execute on function hoje_luanda() to authenticated;
