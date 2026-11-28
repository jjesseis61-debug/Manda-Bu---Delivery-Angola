-- Encomendas de receitas: quando nenhuma cozinha tem o prato no cardápio, o cliente encomenda-o para
-- outro dia e o operador trata do resto.
--   cliente encomenda (dia/hora, pessoas, morada, nota)            -> 'pedida'
--   operador envia a uma cozinha (o sistema sugere)                -> 'na_cozinha'
--   a cozinha propõe o preço (ou recusa: volta a 'pedida')         -> 'proposta'
--   operador aprova (pode ajustar o preço)                         -> 'a_confirmar'
--   cliente aceita: nasce um pedido agendado normal                -> 'confirmada'
--   ... ou recusa                                                  -> 'recusada'
--   operador ou cliente cancelam antes de confirmar                -> 'cancelada'
-- O sinal (parametros.encomenda_sinal_pct, 50% por defeito) paga-se antes pelo «pagar antes» já existente
-- (Multicaixa Express / Unitel Money, confirmado pelas Finanças); o resto paga-se na entrega.

insert into funcionalidades (chave, activa, dispositivo_id) values ('encomendas', false, 'servidor')
on conflict (chave) do nothing;

alter table parametros
  add column if not exists encomenda_antecedencia_horas integer not null default 24 check (encomenda_antecedencia_horas between 1 and 336),
  add column if not exists encomenda_minimo_pessoas     integer not null default 4  check (encomenda_minimo_pessoas between 1 and 500),
  add column if not exists encomenda_sinal_pct          integer not null default 50 check (encomenda_sinal_pct between 0 and 100);

create table if not exists encomendas (
  id               uuid primary key default gen_random_uuid(),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  receita_id       uuid not null references receitas(id),
  cliente_id       uuid not null references clientes(id),
  ponto_entrega_id uuid not null references pontos_entrega(id),
  pessoas          integer not null check (pessoas between 1 and 500),
  para_quando      timestamptz not null,
  nota             text,
  estado           text not null default 'pedida'
                   check (estado in ('pedida', 'na_cozinha', 'proposta', 'a_confirmar', 'confirmada', 'recusada', 'cancelada')),
  cozinha_id       uuid references cozinhas(id),
  preco_cozinha    integer check (preco_cozinha > 0),
  nota_cozinha     text,
  preco            integer check (preco > 0),
  taxa_entrega     integer not null default 0 check (taxa_entrega >= 0),
  pedido_id        uuid references pedidos(id),
  motivo           text,
  decidido_por     uuid references funcionarios(id)
);
create index if not exists encomendas_receita_idx on encomendas (receita_id);
create index if not exists encomendas_cliente_idx on encomendas (cliente_id);
create index if not exists encomendas_ponto_idx on encomendas (ponto_entrega_id);
create index if not exists encomendas_cozinha_idx on encomendas (cozinha_id);
create index if not exists encomendas_pedido_idx on encomendas (pedido_id);
create index if not exists encomendas_decidido_por_idx on encomendas (decidido_por);
create index if not exists encomendas_estado_idx on encomendas (estado, para_quando);
alter table encomendas enable row level security;
revoke all on encomendas from public, anon, authenticated;

-- Sinal da encomenda (Kz), sobre o total (prato + entrega)
create or replace function encomenda_sinal(e encomendas) returns integer
language sql stable set search_path = public as $$
  select case when e.preco is null then 0
              else ceil((e.preco + e.taxa_entrega) * (select encomenda_sinal_pct from parametros where unico) / 100.0)::int end
$$;
revoke execute on function encomenda_sinal(encomendas) from public, anon, authenticated;

create or replace function encomenda_json(e encomendas) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'estado', e.estado, 'criado_em', e.criado_em, 'para_quando', e.para_quando, 'pessoas', e.pessoas,
    'nota', e.nota, 'motivo', e.motivo,
    'receita_id', e.receita_id, 'receita', (select titulo from receitas where id = e.receita_id),
    'cozinha_id', e.cozinha_id, 'cozinha_nome', (select nome from cozinhas where id = e.cozinha_id),
    'preco_cozinha', e.preco_cozinha, 'nota_cozinha', e.nota_cozinha,
    'preco', e.preco, 'taxa_entrega', e.taxa_entrega,
    'total', case when e.preco is not null then e.preco + e.taxa_entrega end,
    'sinal', encomenda_sinal(e),
    'pedido_id', e.pedido_id,
    'pago_antes', (select pago_antes from pedidos where id = e.pedido_id),
    'pagamento', (select jsonb_build_object('estado', a.estado, 'valor', a.valor, 'motivo', a.motivo)
                    from pagamentos_antecipados a where a.pedido_id = e.pedido_id order by a.criado_em desc limit 1),
    'local', (select coalesce(p.referencia, z.nome) from pontos_entrega p left join zonas z on z.id = p.zona_id
               where p.id = e.ponto_entrega_id))
$$;
revoke execute on function encomenda_json(encomendas) from public, anon, authenticated;

-- ------------------------------------------------------------------ cliente
create or replace function encomendar(p_receita uuid, p_pessoas integer, p_para_quando timestamptz,
                                      p_ponto uuid, p_nota text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  pr        parametros;
  v_id      uuid;
begin
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not funcionalidade_activa('encomendas') then raise exception 'encomendas_inactivas' using errcode = 'P0001'; end if;
  select * into pr from parametros where unico;
  if not exists (select 1 from receitas where id = p_receita and estado = 'publicada' and deletado_em is null) then
    raise exception 'receita_inexistente' using errcode = 'P0001';
  end if;
  if not exists (select 1 from enderecos_cliente where cliente_id = v_cliente and ponto_entrega_id = p_ponto and deletado_em is null) then
    raise exception 'ponto_invalido' using errcode = 'P0001';
  end if;
  if p_pessoas is null or p_pessoas < pr.encomenda_minimo_pessoas or p_pessoas > 500 then
    raise exception 'encomenda_pessoas' using errcode = 'P0001', detail = pr.encomenda_minimo_pessoas::text;
  end if;
  if p_para_quando is null or p_para_quando < now() + make_interval(hours => pr.encomenda_antecedencia_horas)
     or p_para_quando > now() + interval '30 days' then
    raise exception 'encomenda_data' using errcode = 'P0001', detail = pr.encomenda_antecedencia_horas::text;
  end if;
  if (select count(*) from encomendas where cliente_id = v_cliente and estado in ('pedida', 'na_cozinha', 'proposta', 'a_confirmar')) >= 3 then
    raise exception 'encomendas_a_mais' using errcode = 'P0001';
  end if;
  insert into encomendas (receita_id, cliente_id, ponto_entrega_id, pessoas, para_quando, nota)
  values (p_receita, v_cliente, p_ponto, p_pessoas, p_para_quando, nullif(trim(coalesce(p_nota, '')), ''))
  returning id into v_id;
  perform registar_auditoria('encomenda_pedida', 'encomendas', v_id, jsonb_build_object('pessoas', p_pessoas));
  return v_id;
end $$;
revoke execute on function encomendar(uuid, integer, timestamptz, uuid, text) from public, anon;
grant execute on function encomendar(uuid, integer, timestamptz, uuid, text) to authenticated;

create or replace function minhas_encomendas() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
begin
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(encomenda_json(e) order by e.criado_em desc)
                     from encomendas e where e.cliente_id = v_cliente and e.criado_em > now() - interval '60 days'), '[]'::jsonb);
end $$;
revoke execute on function minhas_encomendas() from public, anon;
grant execute on function minhas_encomendas() to authenticated;

-- O cliente aceita a proposta (nasce o pedido agendado) ou recusa
create or replace function encomenda_responder(p_id uuid, p_aceitar boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  e         encomendas;
  v_pedido  uuid;
  v_titulo  text;
begin
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  select * into e from encomendas where id = p_id and cliente_id = v_cliente for update;
  if not found or e.estado <> 'a_confirmar' then raise exception 'encomenda_nao_aguarda_resposta' using errcode = 'P0001'; end if;
  if not p_aceitar then
    update encomendas set estado = 'recusada', atualizado_em = now() where id = e.id;
    perform registar_auditoria('encomenda_recusada_cliente', 'encomendas', e.id, '{}'::jsonb);
    return null;
  end if;
  if e.para_quando < now() + interval '2 hours' then
    raise exception 'encomenda_data' using errcode = 'P0001', detail = 'já não há tempo para a preparar';
  end if;
  select titulo into v_titulo from receitas where id = e.receita_id;
  -- Pedido agendado normal (estafeta, caixa, venda e acertos como os outros); escrito pelo servidor
  insert into pedidos (cliente_id, cozinha_id, ponto_entrega_id, zona_id, itens, subtotal, taxa_entrega,
                       agendado_para, observacoes, estado, dispositivo_id)
  select e.cliente_id, e.cozinha_id, e.ponto_entrega_id, p.zona_id,
         jsonb_build_array(jsonb_build_object('nome', v_titulo || ' (encomenda, ' || e.pessoas || ' pessoas)',
                                              'qtd', 1, 'preco_unitario', e.preco)),
         e.preco, e.taxa_entrega, e.para_quando,
         concat_ws(' · ', 'Encomenda de receita', e.nota), 'confirmado', 'servidor'
    from pontos_entrega p where p.id = e.ponto_entrega_id
  returning id into v_pedido;
  update encomendas set estado = 'confirmada', pedido_id = v_pedido, atualizado_em = now() where id = e.id;
  perform registar_auditoria('encomenda_confirmada', 'encomendas', e.id, jsonb_build_object('pedido_id', v_pedido));
  return v_pedido;
end $$;
revoke execute on function encomenda_responder(uuid, boolean) from public, anon;
grant execute on function encomenda_responder(uuid, boolean) to authenticated;

-- Sinal pago antes (Multicaixa Express / Unitel Money): fica a confirmar pelas Finanças («Pagamentos antes»)
create or replace function encomenda_pagar_sinal(p_id uuid, p_metodo text, p_referencia text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  e         encomendas;
  p         pedidos;
  v_chave   text := upper(regexp_replace(coalesce(p_referencia, ''), '\s', '', 'g'));
  v_valor   integer;
  v_id      uuid;
begin
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if p_metodo is null or p_metodo not in ('multicaixa_express', 'unitel_money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if length(v_chave) < 4 then raise exception 'referencia_invalida' using errcode = 'P0001'; end if;
  select * into e from encomendas where id = p_id and cliente_id = v_cliente;
  if not found or e.estado <> 'confirmada' or e.pedido_id is null then
    raise exception 'encomenda_nao_confirmada' using errcode = 'P0001';
  end if;
  select * into p from pedidos where id = e.pedido_id for update;
  if p.estado not in ('pendente', 'confirmado', 'em_preparacao') then
    raise exception 'pedido_ja_nao_aceita_pagamento' using errcode = 'P0001';
  end if;
  v_valor := least(encomenda_sinal(e) - p.pago_antes, pedido_falta_pagar(p));
  if v_valor <= 0 then raise exception 'sinal_ja_pago' using errcode = 'P0001'; end if;
  if exists (select 1 from pagamentos_antecipados where pedido_id = p.id and estado = 'pendente') then
    raise exception 'pagamento_ja_enviado' using errcode = 'P0001';
  end if;
  if exists (select 1 from pagamentos_antecipados where referencia_chave = v_chave and estado <> 'rejeitado')
     or exists (select 1 from comprovativos_pagamento where referencia_chave = v_chave and deletado_em is null) then
    raise exception 'referencia_ja_usada' using errcode = 'P0001';
  end if;
  insert into pagamentos_antecipados (pedido_id, cliente_id, metodo, valor, referencia, referencia_chave)
  values (p.id, v_cliente, p_metodo, v_valor, trim(p_referencia), v_chave)
  returning id into v_id;
  perform registar_auditoria('encomenda_sinal_enviado', 'encomendas', e.id, jsonb_build_object('pagamento_id', v_id, 'valor', v_valor));
  return v_id;
end $$;
revoke execute on function encomenda_pagar_sinal(uuid, text, text) from public, anon;
grant execute on function encomenda_pagar_sinal(uuid, text, text) to authenticated;

create or replace function encomenda_cancelar_cliente(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update encomendas set estado = 'cancelada', motivo = 'Cancelada pelo cliente', atualizado_em = now()
   where id = p_id and cliente_id = cliente_actual() and estado in ('pedida', 'na_cozinha', 'proposta', 'a_confirmar');
  if not found then raise exception 'encomenda_nao_cancelavel' using errcode = 'P0001'; end if;
end $$;
revoke execute on function encomenda_cancelar_cliente(uuid) from public, anon;
grant execute on function encomenda_cancelar_cliente(uuid) to authenticated;

-- ------------------------------------------------------------------ operador e cozinha
-- Cozinhas sugeridas: primeiro as que já fazem o prato (receitas_pratos), depois as mais perto da morada
create or replace function encomenda_sugestoes(e encomendas) returns jsonb
language sql stable security definer set search_path = public as $$
  with pt as (select lat, lng from pontos_entrega where id = e.ponto_entrega_id)
  select coalesce(jsonb_agg(jsonb_build_object('cozinha_id', s.id, 'nome', s.nome, 'sabe_fazer', s.sabe, 'distancia_km', s.km)
                            order by s.sabe desc, s.km nulls last, s.nome), '[]'::jsonb)
    from (select c.id, c.nome,
                 exists (select 1 from receitas_pratos rp join cardapio m on m.id = rp.cardapio_id and m.deletado_em is null
                          where rp.receita_id = e.receita_id and m.cozinha_id = c.id) as sabe,
                 case when cl.lat is not null and pt.lat is not null then
                   round((6371 * acos(least(1, greatest(-1, cos(radians(pt.lat)) * cos(radians(cl.lat)) * cos(radians(cl.lng) - radians(pt.lng))
                                                         + sin(radians(pt.lat)) * sin(radians(cl.lat))))))::numeric, 1) end as km
            from cozinhas c
            left join cozinhas_localizacao cl on cl.cozinha_id = c.id and cl.deletado_em is null
            cross join pt
           where c.deletado_em is null and c.estado = 'activa' and condominio_da_cozinha(c.id) is null
           order by 3 desc, 4 nulls last
           limit 5) s
$$;
revoke execute on function encomenda_sugestoes(encomendas) from public, anon, authenticated;

-- Lista: o operador (pedidos.gerir) vê todas; a cozinha vê as que lhe foram enviadas
create or replace function encomendas_lista() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_gerir boolean := tem_permissao('pedidos.gerir');
begin
  if not (v_gerir or tem_permissao('cozinhas.gerir') or tem_permissao('vendas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir';
  end if;
  return coalesce((
    select jsonb_agg(encomenda_json(e)
                     || jsonb_build_object('cliente_nome', c.nome, 'cliente_telefone', c.telefone,
                                           'pode_gerir', v_gerir,
                                           'pode_propor', e.cozinha_id is not null and (v_gerir or pode_na_cozinha('cozinhas.gerir', e.cozinha_id)
                                                                                        or pode_na_cozinha('vendas.registar', e.cozinha_id)),
                                           'sugestoes', case when v_gerir and e.estado = 'pedida' then encomenda_sugestoes(e) end)
                     order by (e.estado in ('pedida', 'na_cozinha', 'proposta')) desc, e.para_quando)
      from encomendas e join clientes c on c.id = e.cliente_id
     where (v_gerir or (e.cozinha_id is not null and (pode_na_cozinha('cozinhas.gerir', e.cozinha_id) or pode_na_cozinha('vendas.registar', e.cozinha_id))))
       and (e.estado in ('pedida', 'na_cozinha', 'proposta', 'a_confirmar') or e.atualizado_em > now() - interval '14 days')), '[]'::jsonb);
end $$;
revoke execute on function encomendas_lista() from public, anon;
grant execute on function encomendas_lista() to authenticated;

create or replace function encomenda_enviar_cozinha(p_id uuid, p_cozinha uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('pedidos.gerir') then raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir'; end if;
  if not exists (select 1 from cozinhas where id = p_cozinha and deletado_em is null and estado = 'activa') then
    raise exception 'cozinha_invalida' using errcode = 'P0001';
  end if;
  update encomendas set estado = 'na_cozinha', cozinha_id = p_cozinha, preco_cozinha = null, nota_cozinha = null,
                        motivo = null, decidido_por = funcionario_actual(), atualizado_em = now()
   where id = p_id and estado in ('pedida', 'na_cozinha', 'proposta');
  if not found then raise exception 'encomenda_estado' using errcode = 'P0001'; end if;
  perform registar_auditoria('encomenda_enviada_cozinha', 'encomendas', p_id, jsonb_build_object('cozinha_id', p_cozinha));
end $$;
revoke execute on function encomenda_enviar_cozinha(uuid, uuid) from public, anon;
grant execute on function encomenda_enviar_cozinha(uuid, uuid) to authenticated;

-- A cozinha propõe o preço do prato (total para as pessoas pedidas) ou recusa (volta ao operador)
create or replace function encomenda_resposta_cozinha(p_id uuid, p_preco integer, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  e encomendas;
begin
  select * into e from encomendas where id = p_id for update;
  if not found or e.estado <> 'na_cozinha' then raise exception 'encomenda_estado' using errcode = 'P0001'; end if;
  if not (tem_permissao('pedidos.gerir') or pode_na_cozinha('cozinhas.gerir', e.cozinha_id) or pode_na_cozinha('vendas.registar', e.cozinha_id)) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'cozinha';
  end if;
  if p_preco is null then
    -- Recusa: volta para o operador escolher outra cozinha
    if coalesce(trim(p_nota), '') = '' then raise exception 'motivo_obrigatorio' using errcode = 'P0001'; end if;
    update encomendas set estado = 'pedida', motivo = (select nome from cozinhas where id = e.cozinha_id) || ' recusou: ' || trim(p_nota),
                          cozinha_id = null, atualizado_em = now()
     where id = e.id;
    perform registar_auditoria('encomenda_recusada_cozinha', 'encomendas', e.id, jsonb_build_object('motivo', trim(p_nota)));
    return;
  end if;
  if p_preco <= 0 then raise exception 'preco_invalido' using errcode = 'P0001'; end if;
  update encomendas set estado = 'proposta', preco_cozinha = p_preco, nota_cozinha = nullif(trim(coalesce(p_nota, '')), ''),
                        atualizado_em = now()
   where id = e.id;
  perform registar_auditoria('encomenda_proposta', 'encomendas', e.id, jsonb_build_object('preco', p_preco));
end $$;
revoke execute on function encomenda_resposta_cozinha(uuid, integer, text) from public, anon;
grant execute on function encomenda_resposta_cozinha(uuid, integer, text) to authenticated;

-- O operador aprova (pode ajustar o preço) e envia ao cliente, já com a taxa de entrega da zona
create or replace function encomenda_aprovar(p_id uuid, p_preco integer default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  e encomendas;
  v_preco integer;
begin
  if not tem_permissao('pedidos.gerir') then raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir'; end if;
  select * into e from encomendas where id = p_id for update;
  if not found or e.estado <> 'proposta' then raise exception 'encomenda_estado' using errcode = 'P0001'; end if;
  v_preco := coalesce(p_preco, e.preco_cozinha);
  if v_preco is null or v_preco <= 0 then raise exception 'preco_invalido' using errcode = 'P0001'; end if;
  update encomendas
     set estado = 'a_confirmar', preco = v_preco,
         taxa_entrega = coalesce((select round(z.taxa)::int from pontos_entrega p join zonas z on z.id = p.zona_id
                                   where p.id = e.ponto_entrega_id), 0),
         decidido_por = funcionario_actual(), atualizado_em = now()
   where id = e.id;
  perform registar_auditoria('encomenda_aprovada', 'encomendas', e.id, jsonb_build_object('preco', v_preco, 'preco_cozinha', e.preco_cozinha));
end $$;
revoke execute on function encomenda_aprovar(uuid, integer) from public, anon;
grant execute on function encomenda_aprovar(uuid, integer) to authenticated;

create or replace function encomenda_cancelar(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('pedidos.gerir') then raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'motivo_obrigatorio' using errcode = 'P0001'; end if;
  update encomendas set estado = 'cancelada', motivo = trim(p_motivo), decidido_por = funcionario_actual(), atualizado_em = now()
   where id = p_id and estado in ('pedida', 'na_cozinha', 'proposta', 'a_confirmar');
  if not found then raise exception 'encomenda_estado' using errcode = 'P0001'; end if;
  perform registar_auditoria('encomenda_cancelada', 'encomendas', p_id, jsonb_build_object('motivo', trim(p_motivo)));
end $$;
revoke execute on function encomenda_cancelar(uuid, text) from public, anon;
grant execute on function encomenda_cancelar(uuid, text) to authenticated;
