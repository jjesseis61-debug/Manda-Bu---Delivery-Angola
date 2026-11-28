-- Vigilante do Convida e Ganha (Claude com ferramentas). Para cada indicador com sinais num período abre-se um
-- caso; a Edge Function vigiar dá ao Claude ferramentas SÓ DE LEITURA (os indicados e os seus pedidos, os
-- levantamentos, a rede de indicações, a comparação com os outros indicadores) e o Claude entrega um dossiê.
-- Sinais: indicados no mesmo local (fraco: vizinhos do mesmo prédio são legítimos), o mesmo telemóvel em várias
-- contas, levantamentos para o número de um indicado, indicados que só fazem o pedido do desconto, muitos
-- indicados no mesmo dia, ganhos anulados. Não anula ganhos nem bloqueia: quem tem indicacoes.verificar decide
-- e usa as ferramentas de sempre (verificação dos ganhos, levantamentos). Sem nomes nem telefones para o Claude.
-- Interruptor: funcionalidade agente_vigilante (desligada até ser testada).

insert into funcionalidades (chave, activa, dispositivo_id) values ('agente_vigilante', false, 'servidor')
on conflict (chave) do nothing;

alter table parametros
  add column vigilancia_pontuacao_min integer not null default 4 check (vigilancia_pontuacao_min between 1 and 100);
comment on column parametros.vigilancia_pontuacao_min is
  'Pontos para abrir um caso no Convida e Ganha (telemóvel partilhado 4, levantamento para um indicado 4, só o pedido do desconto 3, muitos no mesmo dia 2, mesmo local 1, ganho anulado 1)';

-- Histórico de que contas usaram cada telemóvel (o token de avisos passa de conta quando alguém entra noutra).
-- Guarda só o hash do token; serve para o sinal "o mesmo telemóvel em várias contas".
create table aparelhos_contas (
  token_hash  text not null,
  cliente_id  uuid not null references clientes(id) on delete cascade,
  primeiro_em timestamptz not null default now(),
  ultimo_em   timestamptz not null default now(),
  primary key (token_hash, cliente_id)
);
create index aparelhos_contas_cliente_idx on aparelhos_contas (cliente_id);
alter table aparelhos_contas enable row level security;
revoke all on aparelhos_contas from anon, authenticated;
comment on table aparelhos_contas is 'Só servidor: que contas de clientes usaram cada telemóvel (hash do token de avisos). Sem acesso pelas apps.';
insert into aparelhos_contas (token_hash, cliente_id, primeiro_em, ultimo_em)
select md5(token), cliente_id, criado_em, atualizado_em from dispositivos_push where cliente_id is not null
on conflict do nothing;

create or replace function registar_aparelho_conta() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.cliente_id is not null then
    insert into aparelhos_contas (token_hash, cliente_id) values (md5(new.token), new.cliente_id)
    on conflict (token_hash, cliente_id) do update set ultimo_em = now();
  end if;
  return new;
end $$;
revoke execute on function registar_aparelho_conta() from public, anon, authenticated;
create trigger trg_aparelhos_contas after insert or update of cliente_id, token on dispositivos_push
for each row execute function registar_aparelho_conta();

create table casos_convida (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  indicador_id     uuid not null references clientes(id),
  inicio           date not null,
  fim              date not null check (fim >= inicio),
  sinais           jsonb not null,
  pontuacao        integer not null default 0,
  aberto_por       uuid references funcionarios(id),
  estado           text not null default 'por_investigar'
                     check (estado in ('por_investigar', 'a_investigar', 'investigado', 'indisponivel')),
  ia_tentativas    integer not null default 0,
  ia_nota          text,
  risco            text check (risco in ('baixo', 'medio', 'alto')),
  resumo           text,
  conclusao        jsonb,
  passos           jsonb not null default '[]',
  investigado_em   timestamptz,
  decisao          text check (decisao in ('sem_problema', 'erro_operacional', 'suspeita_confirmada')),
  decisao_nota     text check (char_length(decisao_nota) <= 500),
  decidido_por     uuid references funcionarios(id),
  decidido_em      timestamptz,
  unique (indicador_id, inicio, fim)
);
create index casos_convida_pendente_idx on casos_convida (criado_em) where estado = 'por_investigar';
create index casos_convida_aberto_por_idx on casos_convida (aberto_por);
create index casos_convida_decidido_por_idx on casos_convida (decidido_por);
create trigger trg_0_so_servidor before insert or update or delete on casos_convida
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on casos_convida
for each row execute function sync_receber();
alter table casos_convida enable row level security;
revoke all on casos_convida from anon;
revoke insert, update, delete, truncate on casos_convida from authenticated;
grant select on casos_convida to authenticated;
create policy ler on casos_convida for select to authenticated
  using (deletado_em is null and tem_permissao('indicacoes.verificar'));
comment on table casos_convida is 'Sincronização: só servidor (casos do vigilante do Convida e Ganha). Telemóvel só lê.';

-- Indicados de um indicador ligados no período, com o local do primeiro pedido
create or replace function vig_indicados_base(p_indicador uuid, p_inicio date, p_fim date)
returns table (indicado_id uuid, ligado_em timestamptz, primeiro_pedido_id uuid, ponto uuid)
language sql stable security definer set search_path = public as $$
  select l.indicado_id, l.ligado_em, l.primeiro_pedido_id,
         (select x.ponto_entrega_id from pedidos x where x.id = l.primeiro_pedido_id)
    from ligacoes_indicacao l
   where l.indicador_id = p_indicador and l.deletado_em is null
     and (l.ligado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim;
$$;
revoke execute on function vig_indicados_base(uuid, date, date) from public, anon, authenticated;

-- Sinais de um indicador num período
create or replace function sinais_convida(p_indicador uuid, p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with ind as (select * from vig_indicados_base(p_indicador, p_inicio, p_fim)),
  locais as (select ponto_entrega_id from enderecos_cliente where cliente_id = p_indicador and deletado_em is null),
  contas as (select p_indicador as cliente_id union select indicado_id from ind),
  s as (
    select
      (select count(*) from ind) as indicados,
      (select count(*) from ind i where i.ponto is not null
          and (exists (select 1 from locais lo where i.ponto in (select pontos_entrega_proximos(lo.ponto_entrega_id)))
               or exists (select 1 from ind j where j.indicado_id <> i.indicado_id and j.ponto is not null
                            and i.ponto in (select pontos_entrega_proximos(j.ponto))))) as mesmo_local,
      (select count(*) from ind i where exists (
          select 1 from aparelhos_contas a join aparelhos_contas b on b.token_hash = a.token_hash and b.cliente_id <> a.cliente_id
           where a.cliente_id = i.indicado_id and b.cliente_id in (select cliente_id from contas))) as telemovel_partilhado,
      (select count(*) from pagamentos_indicacao pg
        where pg.indicador_id = p_indicador and pg.tipo = 'levantamento' and pg.deletado_em is null
          and exists (select 1 from ligacoes_indicacao l join clientes c on c.id = l.indicado_id
                       where l.indicador_id = p_indicador and c.telefone is not null
                         and normalizar_telefone(c.telefone) = normalizar_telefone(pg.numero_destino))) as levantamento_para_indicado,
      (select count(*) from ind i where i.ligado_em < (p_fim + 1)::timestamptz - interval '14 days'
          and (select count(*) from pedidos x where x.cliente_id = i.indicado_id and x.estado = 'entregue_pago'
                 and x.deletado_em is null) = 1) as so_um_pedido,
      (select count(*) from ind i where i.ligado_em < (p_fim + 1)::timestamptz - interval '14 days') as indicados_com_14_dias,
      (select coalesce(max(n), 0) from (select count(*) n from ind group by (ligado_em at time zone 'Africa/Luanda')::date) d) as maximo_num_dia,
      (select count(*) from ganhos_indicacao g where g.indicador_id = p_indicador and g.estado = 'anulado' and g.deletado_em is null
          and (g.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim) as ganhos_anulados,
      (select coalesce(sum(valor), 0) from ganhos_indicacao g where g.indicador_id = p_indicador and g.deletado_em is null
          and g.estado in ('confirmado', 'pago', 'em_verificacao')
          and (g.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim) as ganhos_kz)
  select jsonb_build_object(
    'indicados', indicados, 'mesmo_local', mesmo_local, 'telemovel_partilhado', telemovel_partilhado,
    'levantamento_para_indicado', levantamento_para_indicado, 'so_um_pedido', so_um_pedido,
    'indicados_com_14_dias', indicados_com_14_dias, 'maximo_num_dia', maximo_num_dia,
    'ganhos_anulados', ganhos_anulados, 'ganhos_kz', ganhos_kz,
    'pontuacao', mesmo_local + telemovel_partilhado * 4 + levantamento_para_indicado * 4
                 + case when indicados_com_14_dias >= 3 and so_um_pedido * 10 >= indicados_com_14_dias * 6 then 3 else 0 end
                 + case when maximo_num_dia >= 4 then 2 else 0 end + least(ganhos_anulados, 3))
  from s;
$$;
revoke execute on function sinais_convida(uuid, date, date) from public, anon, authenticated;

create or replace function abrir_vigilancia_periodo(p_inicio date, p_fim date, p_por uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_min int := (select vigilancia_pontuacao_min from parametros where unico);
  n int;
begin
  with s as (
    select i.indicador_id, sinais_convida(i.indicador_id, p_inicio, p_fim) as sinais
      from (select distinct indicador_id from ligacoes_indicacao
             where deletado_em is null and (ligado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim
            union
            select distinct indicador_id from pagamentos_indicacao
             where deletado_em is null and tipo = 'levantamento'
               and (criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim) i
  ), novos as (
    insert into casos_convida (dispositivo_id, sincronizado_em, indicador_id, inicio, fim, sinais, pontuacao, aberto_por)
    select 'servidor', now(), s.indicador_id, p_inicio, p_fim, s.sinais, (s.sinais ->> 'pontuacao')::int, p_por
      from s where (s.sinais ->> 'pontuacao')::int >= v_min
    on conflict (indicador_id, inicio, fim) do nothing
    returning 1)
  select count(*) into n from novos;
  return n;
end $$;
revoke execute on function abrir_vigilancia_periodo(date, date, uuid) from public, anon, authenticated;

create or replace function abrir_vigilancia(p_inicio date, p_fim date) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('indicacoes.verificar');
  n int;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 92 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  if not funcionalidade_activa('agente_vigilante') then raise exception 'funcionalidade_inactiva' using errcode = 'P0001'; end if;
  n := abrir_vigilancia_periodo(p_inicio, p_fim, v_func);
  perform registar_auditoria('vigilancia_aberta', 'casos_convida', null, jsonb_build_object('inicio', p_inicio, 'fim', p_fim, 'casos', n));
  return n;
end $$;
revoke execute on function abrir_vigilancia(date, date) from public, anon;
grant execute on function abrir_vigilancia(date, date) to authenticated;

-- Todas as segundas-feiras: casos das últimas 4 semanas (não repete o mesmo período)
create or replace function job_vigilancia() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_fim date := (now() at time zone 'Africa/Luanda')::date - 1;
begin
  if not funcionalidade_activa('agente_vigilante') then return 0; end if;
  return abrir_vigilancia_periodo(v_fim - 27, v_fim, null);
end $$;
revoke execute on function job_vigilancia() from public, anon, authenticated;

create or replace function casos_convida_lista() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('indicacoes.verificar');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id, 'indicador', cl.nome, 'codigo', (select codigo from codigos_indicacao where cliente_id = c.indicador_id),
             'inicio', c.inicio, 'fim', c.fim, 'sinais', c.sinais, 'pontuacao', c.pontuacao, 'estado', c.estado,
             'ia_nota', c.ia_nota, 'risco', c.risco, 'resumo', c.resumo, 'conclusao', c.conclusao, 'passos', c.passos,
             'investigado_em', c.investigado_em, 'decisao', c.decisao, 'decisao_nota', c.decisao_nota,
             'decidido_por', d.nome, 'decidido_em', c.decidido_em, 'criado_em', c.criado_em)
           order by (c.decisao is null) desc, case c.risco when 'alto' then 0 when 'medio' then 1 when 'baixo' then 2 else 3 end,
                    c.pontuacao desc, c.criado_em desc)
      from casos_convida c join clientes cl on cl.id = c.indicador_id
      left join funcionarios d on d.id = c.decidido_por
     where c.deletado_em is null and c.criado_em > now() - interval '180 days'), '[]');
end $$;
revoke execute on function casos_convida_lista() from public, anon;
grant execute on function casos_convida_lista() to authenticated;

create or replace function decidir_caso_convida(p_id uuid, p_decisao text, p_nota text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('indicacoes.verificar');
  c casos_convida;
begin
  select * into c from casos_convida where id = p_id and deletado_em is null for update;
  if not found then raise exception 'caso_inexistente' using errcode = 'P0001'; end if;
  if c.decisao is not null then raise exception 'caso_decidido' using errcode = 'P0001'; end if;
  if p_decisao is null or p_decisao not in ('sem_problema', 'erro_operacional', 'suspeita_confirmada') then
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
  if char_length(trim(coalesce(p_nota, ''))) < 5 then raise exception 'nota_obrigatoria' using errcode = 'P0001'; end if;
  if char_length(p_nota) > 500 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  update casos_convida
     set decisao = p_decisao, decisao_nota = trim(p_nota), decidido_por = v_func, decidido_em = now(), atualizado_em = now()
   where id = c.id;
  perform registar_auditoria('caso_convida_decidido', 'casos_convida', c.id,
    jsonb_build_object('decisao', p_decisao, 'risco_agente', c.risco, 'indicador_id', c.indicador_id));
end $$;
revoke execute on function decidir_caso_convida(uuid, text, text) from public, anon;
grant execute on function decidir_caso_convida(uuid, text, text) to authenticated;

create or replace function vigiar_de_novo(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  c casos_convida;
begin
  perform exigir_permissao('indicacoes.verificar');
  select * into c from casos_convida where id = p_id and deletado_em is null for update;
  if not found then raise exception 'caso_inexistente' using errcode = 'P0001'; end if;
  if c.decisao is not null then raise exception 'caso_decidido' using errcode = 'P0001'; end if;
  update casos_convida
     set estado = 'por_investigar', ia_tentativas = 0, ia_nota = null,
         sinais = sinais_convida(c.indicador_id, c.inicio, c.fim),
         pontuacao = (sinais_convida(c.indicador_id, c.inicio, c.fim) ->> 'pontuacao')::int, atualizado_em = now()
   where id = c.id;
end $$;
revoke execute on function vigiar_de_novo(uuid) from public, anon;
grant execute on function vigiar_de_novo(uuid) to authenticated;

-- ---------------------------------------------------------------- ferramentas do vigilante (só leitura, só o serviço)
create or replace function vig_caso(p_caso uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'caso_id', c.id, 'indicador_id', c.indicador_id, 'inicio', c.inicio, 'fim', c.fim,
    'nivel', (select nivel from codigos_indicacao where cliente_id = c.indicador_id),
    'conta_criada_em', (select (criado_em at time zone 'Africa/Luanda')::date from clientes where id = c.indicador_id),
    'pedidos_proprios_entregues', (select count(*) from pedidos where cliente_id = c.indicador_id and estado = 'entregue_pago' and deletado_em is null),
    'indicados_desde_sempre', (select count(*) from ligacoes_indicacao where indicador_id = c.indicador_id and deletado_em is null),
    'sinais', sinais_convida(c.indicador_id, c.inicio, c.fim),
    'casos_anteriores', (select coalesce(jsonb_agg(jsonb_build_object('inicio', a.inicio, 'fim', a.fim, 'risco', a.risco, 'decisao', a.decisao)), '[]')
                           from casos_convida a where a.indicador_id = c.indicador_id and a.id <> c.id and a.deletado_em is null))
  from casos_convida c where c.id = p_caso;
$$;

create or replace function reservar_caso_convida() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c casos_convida;
begin
  if not funcionalidade_activa('agente_vigilante') then return null; end if;
  select * into c from casos_convida
   where deletado_em is null and decisao is null
     and (estado = 'por_investigar' or (estado = 'a_investigar' and atualizado_em < now() - interval '5 minutes'))
   order by pontuacao desc, criado_em limit 1 for update skip locked;
  if not found then return null; end if;
  update casos_convida set estado = 'a_investigar', atualizado_em = now() where id = c.id;
  return vig_caso(c.id);
end $$;

-- Os indicados no período (sem nomes nem telefones)
create or replace function vig_indicados(p_indicador uuid, p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with ind as (select * from vig_indicados_base(p_indicador, p_inicio, p_fim)),
  locais as (select ponto_entrega_id from enderecos_cliente where cliente_id = p_indicador and deletado_em is null),
  contas as (select p_indicador as cliente_id union select indicado_id from ind)
  select coalesce(jsonb_agg(jsonb_build_object(
           'indicado_id', i.indicado_id,
           'conta_criada', to_char(c.criado_em at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'),
           'ligado', to_char(i.ligado_em at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'),
           'pedidos_entregues', (select count(*) from pedidos x where x.cliente_id = i.indicado_id and x.estado = 'entregue_pago' and x.deletado_em is null),
           'valor_entregue_kz', (select coalesce(sum(subtotal + taxa_entrega - desconto_indicacao), 0) from pedidos x
                                  where x.cliente_id = i.indicado_id and x.estado = 'entregue_pago' and x.deletado_em is null),
           'ultimo_pedido', (select to_char(max(criado_em) at time zone 'Africa/Luanda', 'YYYY-MM-DD') from pedidos x
                              where x.cliente_id = i.indicado_id and x.deletado_em is null),
           'tipo_local', (select tipo from pontos_entrega where id = i.ponto),
           'zona', (select z.nome from pontos_entrega pe join zonas z on z.id = pe.zona_id where pe.id = i.ponto),
           'mesmo_local_que_o_indicador', exists (select 1 from locais lo where i.ponto in (select pontos_entrega_proximos(lo.ponto_entrega_id))),
           'mesmo_local_que_outros_indicados', (select count(*) from ind j where j.indicado_id <> i.indicado_id and j.ponto is not null
                                                   and i.ponto in (select pontos_entrega_proximos(j.ponto))),
           'telemovel_partilhado', exists (select 1 from aparelhos_contas a join aparelhos_contas b on b.token_hash = a.token_hash and b.cliente_id <> a.cliente_id
                                            where a.cliente_id = i.indicado_id and b.cliente_id in (select cliente_id from contas)),
           'ganhos_gerados_kz', (select coalesce(sum(valor), 0) from ganhos_indicacao g where g.indicado_id = i.indicado_id and g.indicador_id = p_indicador
                                   and g.estado <> 'anulado' and g.deletado_em is null))
         order by i.ligado_em), '[]')
    from ind i join clientes c on c.id = i.indicado_id;
$$;

-- Pedidos de um indicado
create or replace function vig_pedidos_indicado(p_indicado uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'pedido_id', x.id, 'feito', to_char(x.criado_em at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'), 'estado', x.estado,
           'subtotal_kz', x.subtotal, 'desconto_convida_kz', x.desconto_indicacao, 'saldo_convida_usado_kz', x.credito_indicacao_usado,
           'pagamento', (select string_agg(distinct p ->> 'metodo', ', ') from jsonb_array_elements(x.parcelas) p),
           'cozinha', (select trim(nome) from cozinhas where id = x.cozinha_id),
           'itens', (select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || coalesce(i ->> 'nome', 'Prato'), ', ') from jsonb_array_elements(x.itens) i))
         order by x.criado_em), '[]')
    from (select * from pedidos where cliente_id = p_indicado and deletado_em is null order by criado_em limit 30) x;
$$;

-- Levantamentos do indicador (número mascarado; diz se é o número de um indicado)
create or replace function vig_levantamentos(p_indicador uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'quando', to_char(pg.criado_em at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'), 'valor_kz', pg.valor, 'metodo', pg.metodo,
           'estado', pg.estado, 'numero_final', right(regexp_replace(coalesce(pg.numero_destino, ''), '\D', '', 'g'), 3),
           'e_o_numero_do_indicador', exists (select 1 from clientes c where c.id = p_indicador and c.telefone is not null
                                                and normalizar_telefone(c.telefone) = normalizar_telefone(pg.numero_destino)),
           'e_o_numero_de_um_indicado', exists (select 1 from ligacoes_indicacao l join clientes c on c.id = l.indicado_id
                                                  where l.indicador_id = p_indicador and c.telefone is not null
                                                    and normalizar_telefone(c.telefone) = normalizar_telefone(pg.numero_destino)))
         order by pg.criado_em), '[]')
    from pagamentos_indicacao pg
   where pg.indicador_id = p_indicador and pg.tipo = 'levantamento' and pg.deletado_em is null;
$$;

-- Rede: indicados que também indicam, e se o indicador foi indicado por um dos seus indicados (ciclo)
create or replace function vig_rede(p_indicador uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'quem_o_indicou', (select l.indicador_id from ligacoes_indicacao l where l.indicado_id = p_indicador and l.deletado_em is null limit 1),
    'ciclo', exists (select 1 from ligacoes_indicacao a join ligacoes_indicacao b on b.indicador_id = a.indicado_id
                      where a.indicador_id = p_indicador and b.indicado_id = p_indicador and a.deletado_em is null and b.deletado_em is null),
    'indicados_que_tambem_indicam', coalesce((select jsonb_agg(jsonb_build_object('indicado_id', l.indicado_id, 'indicados_dele', n))
                                                from (select l.indicado_id, (select count(*) from ligacoes_indicacao l2
                                                                              where l2.indicador_id = l.indicado_id and l2.deletado_em is null) n
                                                        from ligacoes_indicacao l where l.indicador_id = p_indicador and l.deletado_em is null) l
                                               where n > 0), '[]'));
$$;

-- Como se comparam os indicadores no período (sem nomes)
create or replace function vig_comparar(p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with i as (select indicador_id, count(*) n from ligacoes_indicacao
              where deletado_em is null and (ligado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim group by 1)
  select jsonb_build_object(
    'indicadores_activos', (select count(*) from i),
    'indicados_no_periodo', (select coalesce(sum(n), 0) from i),
    'mediana_de_indicados', (select percentile_cont(0.5) within group (order by n) from i),
    'maximo_de_indicados', (select max(n) from i),
    'indicados_com_um_so_pedido_pct', (select round(100.0 * count(*) filter (where (select count(*) from pedidos x where x.cliente_id = l.indicado_id
                                                                                 and x.estado = 'entregue_pago' and x.deletado_em is null) = 1)
                                                   / nullif(count(*), 0))
                                         from ligacoes_indicacao l where l.deletado_em is null
                                          and (l.ligado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim));
$$;

create or replace function registar_vigilancia(p_caso uuid, p_resultado text, p_conclusao jsonb default null,
                                               p_passos jsonb default '[]', p_nota text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  c casos_convida;
  v_estado text;
  v_risco text;
begin
  select * into c from casos_convida where id = p_caso for update;
  if not found then raise exception 'caso_inexistente' using errcode = 'P0001'; end if;
  if p_resultado = 'erro' then
    update casos_convida
       set ia_tentativas = ia_tentativas + 1,
           estado = case when ia_tentativas + 1 >= 3 then 'indisponivel' else 'por_investigar' end,
           ia_nota = left(p_nota, 300), atualizado_em = now()
     where id = c.id returning estado into v_estado;
    return v_estado;
  end if;
  if p_resultado = 'indisponivel' then
    update casos_convida set estado = 'indisponivel', ia_nota = left(p_nota, 300), atualizado_em = now() where id = c.id;
    return 'indisponivel';
  end if;
  if p_resultado <> 'investigado' or p_conclusao is null then raise exception 'resultado_invalido' using errcode = 'P0001'; end if;
  v_risco := case when p_conclusao ->> 'risco' in ('baixo', 'medio', 'alto') then p_conclusao ->> 'risco' else 'medio' end;
  update casos_convida
     set estado = 'investigado', risco = v_risco, resumo = left(p_conclusao ->> 'resumo', 600),
         conclusao = p_conclusao - 'risco' - 'resumo', passos = coalesce(p_passos, '[]'),
         ia_nota = left(p_nota, 300), investigado_em = now(), atualizado_em = now()
   where id = c.id;
  insert into auditoria (dispositivo_id, funcionario_id, funcionario_nome, acao, detalhe, ref_id, ref_tipo, sincronizado_em)
  values ('servidor', null, 'Agente Claude', 'caso_convida_investigado',
          jsonb_build_object('risco', v_risco, 'indicador_id', c.indicador_id)::text, c.id, 'casos_convida', now());
  if v_risco = 'alto' then
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select f, 'N26', jsonb_build_object('caso_id', c.id, 'codigo', (select codigo from codigos_indicacao where cliente_id = c.indicador_id),
                                        'resumo', left(p_conclusao ->> 'resumo', 140))
      from funcionarios_com_permissao('indicacoes.verificar') f;
  end if;
  return 'investigado';
end $$;

create or replace function agendar_vigilancia(p_url text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format($f$select cron.schedule('vigiar', '*/5 * * * *', %L)$f$,
    format('select net.http_post(url := %L, body := ''{}''::jsonb, timeout_milliseconds := 150000, headers := jsonb_build_object('
           '''Content-Type'', ''application/json'', ''x-envio-segredo'', '
           '(select valor from public.segredos_servidor where chave = ''envio_notificacoes'')))', p_url));
  return 'agendado';
end $$;

do $$
declare f text;
begin
  foreach f in array array['vig_caso(uuid)', 'reservar_caso_convida()', 'vig_indicados(uuid, date, date)',
                           'vig_pedidos_indicado(uuid)', 'vig_levantamentos(uuid)', 'vig_rede(uuid)', 'vig_comparar(date, date)',
                           'registar_vigilancia(uuid, text, jsonb, jsonb, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
revoke execute on function agendar_vigilancia(text) from public, anon, authenticated;
