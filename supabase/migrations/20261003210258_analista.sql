-- Analista do administrador (Claude com ferramentas). Quem tem analista.usar pergunta em linguagem normal
-- ("que cozinha perdeu clientes este mês e porquê?") e a Edge Function analista responde: o Claude escolhe
-- as ferramentas (vendas, pratos, clientes, operação, satisfação, equipa, finanças; todas agregadas, só de
-- leitura, sem nomes nem contactos de clientes), cruza os números e escreve a resposta com os números-chave,
-- as limitações e sugestões. No dia 2 de cada mês faz o relatório do mês anterior (N25).
-- Interruptor: funcionalidade agente_analista (desligada até ser testada).

insert into funcionalidades (chave, activa, dispositivo_id) values ('agente_analista', false, 'servidor')
on conflict (chave) do nothing;
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'analista.usar', 'Relatórios',
   'Fazer perguntas ao analista (Claude) sobre todo o negócio e ler o relatório mensal')
on conflict (chave) do nothing;

alter table parametros
  add column analista_perguntas_dia integer not null default 30 check (analista_perguntas_dia between 1 and 500);
comment on column parametros.analista_perguntas_dia is 'Perguntas ao analista por pessoa e por dia (controla o custo)';

create table perguntas_analista (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  funcionario_id   uuid references funcionarios(id),          -- null: relatório mensal automático
  tipo             text not null default 'pergunta' check (tipo in ('pergunta', 'relatorio_mensal')),
  pergunta         text not null check (char_length(pergunta) between 5 and 600),
  inicio           date,                                       -- relatório: o mês
  fim              date,
  estado           text not null default 'pendente'
                     check (estado in ('pendente', 'a_responder', 'respondida', 'indisponivel')),
  ia_tentativas    integer not null default 0,
  ia_nota          text,
  resposta         text,
  numeros          jsonb not null default '[]',
  sugestoes        jsonb not null default '[]',
  limitacoes       text,
  passos           jsonb not null default '[]',
  respondida_em    timestamptz
);
create index perguntas_analista_funcionario_idx on perguntas_analista (funcionario_id, criado_em);
create index perguntas_analista_pendente_idx on perguntas_analista (criado_em) where estado = 'pendente';
create unique index perguntas_analista_relatorio_key on perguntas_analista (inicio) where tipo = 'relatorio_mensal' and deletado_em is null;
create trigger trg_0_so_servidor before insert or update or delete on perguntas_analista
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on perguntas_analista
for each row execute function sync_receber();
alter table perguntas_analista enable row level security;
revoke all on perguntas_analista from anon;
revoke insert, update, delete, truncate on perguntas_analista from authenticated;
grant select on perguntas_analista to authenticated;
create policy ler on perguntas_analista for select to authenticated
  using (deletado_em is null and tem_permissao('analista.usar')
         and (funcionario_id is null or funcionario_id = funcionario_actual() or e_administrador()));
comment on table perguntas_analista is 'Sincronização: só servidor (perguntas ao analista e relatórios mensais). Telemóvel só lê.';

-- ---------------------------------------------------------------- pela app
create or replace function perguntar_analista(p_pergunta text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := funcionario_actual();
  v_id uuid;
begin
  if not tem_permissao('analista.usar') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not funcionalidade_activa('agente_analista') then raise exception 'funcionalidade_inactiva' using errcode = 'P0001'; end if;
  if char_length(trim(coalesce(p_pergunta, ''))) < 5 then raise exception 'texto_curto' using errcode = 'P0001'; end if;
  if char_length(p_pergunta) > 600 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  if (select count(*) from perguntas_analista
       where funcionario_id = v_func and criado_em > now() - interval '24 hours')
     >= (select analista_perguntas_dia from parametros where unico) then
    raise exception 'limite_diario' using errcode = 'P0001';
  end if;
  insert into perguntas_analista (dispositivo_id, sincronizado_em, funcionario_id, pergunta)
  values ('servidor', now(), v_func, trim(p_pergunta)) returning id into v_id;
  return v_id;
end $$;
revoke execute on function perguntar_analista(text) from public, anon;
grant execute on function perguntar_analista(text) to authenticated;

-- Relatório de um mês (pela app ou pelo job do dia 2); um por mês
create or replace function criar_relatorio_analista(p_ano int, p_mes int) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_ini date := make_date(p_ano, p_mes, 1);
  v_id uuid;
begin
  insert into perguntas_analista (dispositivo_id, sincronizado_em, tipo, pergunta, inicio, fim)
  values ('servidor', now(), 'relatorio_mensal',
          format('Relatório do mês de %s de %s: como correu o negócio, comparado com o mês anterior?', lower(nome_mes(p_mes)), p_ano),
          v_ini, (v_ini + interval '1 month - 1 day')::date)
  on conflict (inicio) where tipo = 'relatorio_mensal' and deletado_em is null do nothing
  returning id into v_id;
  return coalesce(v_id, (select id from perguntas_analista where tipo = 'relatorio_mensal' and inicio = v_ini and deletado_em is null));
end $$;
revoke execute on function criar_relatorio_analista(int, int) from public, anon, authenticated;

create or replace function pedir_relatorio_analista(p_ano int, p_mes int) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('analista.usar') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not funcionalidade_activa('agente_analista') then raise exception 'funcionalidade_inactiva' using errcode = 'P0001'; end if;
  if p_ano is null or p_mes is null or p_mes not between 1 and 12 or p_ano not between 2020 and 2100
     or make_date(p_ano, p_mes, 1) > (now() at time zone 'Africa/Luanda')::date then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  return criar_relatorio_analista(p_ano, p_mes);
end $$;
revoke execute on function pedir_relatorio_analista(int, int) from public, anon;
grant execute on function pedir_relatorio_analista(int, int) to authenticated;

create or replace function job_relatorio_analista() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_ant date := (date_trunc('month', now() at time zone 'Africa/Luanda') - interval '1 month')::date;
begin
  if not funcionalidade_activa('agente_analista') then return null; end if;
  return criar_relatorio_analista(extract(year from v_ant)::int, extract(month from v_ant)::int);
end $$;
revoke execute on function job_relatorio_analista() from public, anon, authenticated;

create or replace function perguntas_analista_lista() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_func uuid := funcionario_actual();
begin
  if not tem_permissao('analista.usar') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'tipo', p.tipo, 'pergunta', p.pergunta, 'inicio', p.inicio, 'fim', p.fim, 'estado', p.estado,
             'resposta', p.resposta, 'numeros', p.numeros, 'sugestoes', p.sugestoes, 'limitacoes', p.limitacoes,
             'ia_nota', p.ia_nota, 'passos', jsonb_array_length(p.passos), 'criado_em', p.criado_em,
             'respondida_em', p.respondida_em, 'quem', f.nome)
           order by p.criado_em desc)
      from (select * from perguntas_analista
             where deletado_em is null and (funcionario_id is null or funcionario_id = v_func or e_administrador())
             order by criado_em desc limit 40) p
      left join funcionarios f on f.id = p.funcionario_id), '[]');
end $$;
revoke execute on function perguntas_analista_lista() from public, anon;
grant execute on function perguntas_analista_lista() to authenticated;

-- ---------------------------------------------------------------- números da equipa em qualquer período
create or replace function metricas_funcionario_periodo(p_func uuid, p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with p as (select alerta_atraso_min from parametros where unico),
  ent as (select x.* from pedidos x
           where x.entregador_id = p_func and x.deletado_em is null and x.estado = 'entregue_pago'
             and (x.entregue_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  hor as (select count(*) filter (where e.hora_prometida is not null) com_hora,
                 count(*) filter (where e.hora_prometida is not null
                                    and e.entregue_em <= e.hora_prometida + make_interval(mins => p.alerta_atraso_min)) a_horas
            from ent e, p),
  av as (select count(*) n, round(avg(a.estrelas)::numeric, 1) media
           from avaliacoes a join ent e on e.id = a.pedido_id where a.deletado_em is null),
  ven as (select count(*) n, coalesce(sum(v.valor_total), 0) valor from vendas v
           where v.registado_por = p_func and v.pedido_id is null and v.deletado_em is null
             and (v.data at time zone 'Africa/Luanda')::date between p_inicio and p_fim)
  select jsonb_build_object(
    'entregas', (select count(*) from ent),
    'com_hora', hor.com_hora,
    'a_horas', hor.a_horas,
    'pct_a_horas', case when hor.com_hora > 0 then round(100.0 * hor.a_horas / hor.com_hora)::int end,
    'avaliacoes', av.n,
    'estrelas', av.media,
    'vendas_balcao', ven.n,
    'valor_balcao', ven.valor,
    'confirmados', (select count(*) from auditoria a
                     where a.funcionario_id = p_func and a.acao = 'pedido_estado' and a.deletado_em is null
                       and (a.detalhe::jsonb) ->> 'para' = 'confirmado'
                       and (a.data at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
    'reclamacoes_procedentes', (select count(*) from reclamacoes r
                                 where r.entregador_id = p_func and r.procedente and r.deletado_em is null
                                   and (r.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
    'comprovativos_rejeitados', (select count(*) from comprovativos_pagamento k
                                  where k.registado_por = p_func and k.estado = 'rejeitado' and k.deletado_em is null
                                    and (k.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim))
  from hor, av, ven;
$$;
revoke execute on function metricas_funcionario_periodo(uuid, date, date) from public, anon, authenticated;

-- Os estímulos mensais passam a usar a mesma conta (mesmos números)
create or replace function metricas_funcionario(p_func uuid, p_ini date) returns jsonb
language sql stable security definer set search_path = public as $$
  select metricas_funcionario_periodo(p_func, p_ini, (p_ini + interval '1 month - 1 day')::date);
$$;

-- ---------------------------------------------------------------- ferramentas do analista (só leitura, só o serviço)
create or replace function analista_vendas(p_inicio date, p_fim date, p_agrupar text default 'total') returns jsonb
language sql stable security definer set search_path = public as $$
  with x as (
    select p.cozinha_id, p.zona_id, p.cliente_id, (p.entregue_em at time zone 'Africa/Luanda') as quando,
           p.subtotal + p.taxa_entrega - p.desconto_indicacao as valor
      from pedidos p
     where p.deletado_em is null and p.estado = 'entregue_pago'
       and (p.entregue_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  g as (
    select case p_agrupar
             when 'dia' then to_char(quando, 'YYYY-MM-DD')
             when 'semana' then 'semana de ' || to_char(date_trunc('week', quando), 'YYYY-MM-DD')
             when 'mes' then to_char(quando, 'YYYY-MM')
             when 'cozinha' then coalesce((select trim(nome) from cozinhas where id = x.cozinha_id), '—')
             when 'zona' then coalesce((select nome from zonas where id = x.zona_id), 'sem zona')
             when 'hora' then to_char(quando, 'HH24') || 'h'
             when 'dia_semana' then extract(isodow from quando)::int || ' ' ||
                                    (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])[extract(isodow from quando)::int]
             else 'total' end as grupo, x.*
      from x)
  select jsonb_build_object(
    'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim), 'agrupado_por', coalesce(p_agrupar, 'total'),
    'pedidos_entregues', coalesce((select jsonb_agg(l order by l ->> 'grupo') from (
        select jsonb_build_object('grupo', grupo, 'pedidos', count(*), 'valor_kz', sum(valor),
                                  'ticket_medio_kz', round(avg(valor)), 'clientes', count(distinct cliente_id)) l
          from g group by grupo) s), '[]'),
    'pedidos_cancelados', (select count(*) from pedidos where deletado_em is null and estado = 'cancelado'
                             and (criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
    'vendas_ao_balcao', (select jsonb_build_object('vendas', count(*), 'valor_kz', coalesce(sum(valor_total), 0)) from vendas
                           where deletado_em is null and pedido_id is null
                             and (data at time zone 'Africa/Luanda')::date between p_inicio and p_fim));
$$;

create or replace function analista_pratos(p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with x as (select p.itens from pedidos p where p.deletado_em is null and p.estado = 'entregue_pago'
              and (p.entregue_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  it as (select trim(coalesce(i ->> 'nome', 'Prato')) as nome, coalesce((i ->> 'qtd')::numeric, 1) as qtd,
                coalesce((i ->> 'preco_unitario')::numeric, 0) as preco
           from x, jsonb_array_elements(x.itens) i)
  select jsonb_build_object(
    'mais_vendidos', coalesce((select jsonb_agg(l) from (
        select jsonb_build_object('prato', nome, 'quantidade', sum(qtd), 'valor_kz', sum(qtd * preco)) l
          from it group by nome order by sum(qtd) desc limit 30) s), '[]'),
    'avaliacoes_dos_pratos', coalesce((select jsonb_agg(l) from (
        select jsonb_build_object('prato', pb.nome, 'estrelas_media', round(avg(ap.estrelas)::numeric, 1), 'avaliacoes', count(*)) l
          from avaliacoes_pratos ap join pratos_base pb on pb.id = ap.prato_id join avaliacoes a on a.id = ap.avaliacao_id
         where a.deletado_em is null and (a.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim
         group by pb.nome order by count(*) desc limit 30) s), '[]'));
$$;

create or replace function analista_clientes(p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with x as (select p.* from pedidos p where p.deletado_em is null and p.estado = 'entregue_pago'
              and (p.entregue_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  ant as (select p.cliente_id from pedidos p where p.deletado_em is null and p.estado = 'entregue_pago'
           and (p.entregue_em at time zone 'Africa/Luanda')::date between p_inicio - (p_fim - p_inicio + 1) and p_inicio - 1),
  c as (select cliente_id, count(*) n, sum(subtotal + taxa_entrega - desconto_indicacao) v from x group by cliente_id)
  select jsonb_build_object(
    'clientes_registados_no_periodo', (select count(*) from clientes where deletado_em is null
                                         and (criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
    'clientes_que_compraram', (select count(*) from c),
    'clientes_com_2_ou_mais_pedidos', (select count(*) from c where n >= 2),
    'pedidos_por_cliente', (select round(avg(n), 1) from c),
    'gasto_medio_por_cliente_kz', (select round(avg(v)) from c),
    'periodo_anterior_compraram', (select count(distinct cliente_id) from ant),
    'periodo_anterior_voltaram', (select count(distinct cliente_id) from ant where cliente_id in (select cliente_id from c)),
    'por_zona', coalesce((select jsonb_agg(l) from (
        select jsonb_build_object('zona', coalesce(z.nome, 'sem zona'), 'clientes', count(distinct x.cliente_id), 'pedidos', count(*),
                                  'valor_kz', sum(x.subtotal + x.taxa_entrega - x.desconto_indicacao)) l
          from x left join zonas z on z.id = x.zona_id group by z.nome order by count(*) desc limit 15) s), '[]'),
    'por_tipo_de_local', coalesce((select jsonb_object_agg(coalesce(tipo, 'sem local'), n) from (
        select pe.tipo, count(*) n from x left join pontos_entrega pe on pe.id = x.ponto_entrega_id group by pe.tipo) s), '{}'),
    'vieram_pelo_convida_e_ganha', (select count(distinct g.indicado_id) from ganhos_indicacao g join x on x.id = g.pedido_id),
    'pacotes_por_estado', coalesce((select jsonb_object_agg(estado, n) from (
        select estado, count(*) n from adesoes_pacote where deletado_em is null group by estado) s), '{}'));
$$;

create or replace function analista_operacao(p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with par as (select alerta_atraso_min from parametros where unico),
  x as (select p.* from pedidos p where p.deletado_em is null and p.grupo_id is null
         and (p.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  conf as (select a.ref_id, min(a.data) as em from auditoria a
            where a.acao = 'pedido_estado' and a.deletado_em is null and a.ref_id in (select id from x)
              and (a.detalhe::jsonb) ->> 'para' = 'confirmado' group by a.ref_id)
  select jsonb_build_object(
    'por_cozinha', coalesce((select jsonb_agg(l) from (
        select jsonb_build_object(
                 'cozinha', coalesce(trim(cz.nome), '—'), 'pedidos', count(*),
                 'entregues', count(*) filter (where x.estado = 'entregue_pago'),
                 'cancelados', count(*) filter (where x.estado = 'cancelado'),
                 'minutos_ate_confirmar', round(avg(extract(epoch from conf.em - x.criado_em) / 60)),
                 'minutos_ate_entregar', round(avg(extract(epoch from x.entregue_em - x.criado_em) / 60) filter (where x.estado = 'entregue_pago')),
                 'pct_entregues_a_horas', round(100.0 * count(*) filter (where x.estado = 'entregue_pago' and x.hora_prometida is not null
                                                  and x.entregue_em <= x.hora_prometida + make_interval(mins => (select alerta_atraso_min from par)))
                                          / nullif(count(*) filter (where x.estado = 'entregue_pago' and x.hora_prometida is not null), 0)),
                 'alertas_atraso', (select count(*) from alertas_pedido a where a.tipo = 'atraso' and a.pedido_id in
                                      (select id from x x2 where x2.cozinha_id is not distinct from x.cozinha_id)),
                 'alertas_sem_confirmacao', (select count(*) from alertas_pedido a where a.tipo = 'sem_confirmacao' and a.pedido_id in
                                      (select id from x x2 where x2.cozinha_id is not distinct from x.cozinha_id))) l
          from x left join conf on conf.ref_id = x.id left join cozinhas cz on cz.id = x.cozinha_id
         group by x.cozinha_id, cz.nome) s), '[]'),
    'motivos_de_cancelamento', coalesce((select jsonb_agg(l) from (
        select jsonb_build_object('motivo', coalesce(nullif(trim(motivo_cancelamento), ''), 'sem motivo'), 'pedidos', count(*)) l
          from x where estado = 'cancelado' group by coalesce(nullif(trim(motivo_cancelamento), ''), 'sem motivo')
         order by count(*) desc limit 10) s), '[]'),
    'pedidos_por_hora', coalesce((select jsonb_object_agg(h, n) from (
        select to_char(criado_em at time zone 'Africa/Luanda', 'HH24') || 'h' h, count(*) n from x group by 1) s), '{}'));
$$;

create or replace function analista_satisfacao(p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with a as (select av.* from avaliacoes av where av.deletado_em is null
              and (av.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  r as (select * from reclamacoes where deletado_em is null
         and (criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim)
  select jsonb_build_object(
    'avaliacoes', (select count(*) from a),
    'estrelas_media', (select round(avg(estrelas)::numeric, 2) from a),
    'por_estrelas', coalesce((select jsonb_object_agg(estrelas, n) from (select estrelas, count(*) n from a group by 1) s), '{}'),
    'por_cozinha', coalesce((select jsonb_agg(l) from (
        select jsonb_build_object('cozinha', coalesce(trim(cz.nome), '—'), 'avaliacoes', count(*),
                                  'estrelas_media', round(avg(a.estrelas)::numeric, 2)) l
          from a left join cozinhas cz on cz.id = a.cozinha_id group by cz.nome) s), '[]'),
    'comentarios_negativos_recentes', coalesce((select jsonb_agg(l) from (
        select jsonb_build_object('estrelas', estrelas, 'comentario', left(comentario, 200)) l from a
         where estrelas <= 3 and not oculta and nullif(trim(comentario), '') is not null
         order by criado_em desc limit 15) s), '[]'),
    'reclamacoes', (select count(*) from r),
    'reclamacoes_com_razao', (select count(*) from r where procedente),
    'reclamacoes_por_motivo', coalesce((select jsonb_object_agg(k, n) from (
        select coalesce(categoria, ia_categoria, 'por_classificar') k, count(*) n from r group by 1) s), '{}'),
    'compensacoes_kz', (select coalesce(sum(compensacao_valor), 0) from r));
$$;

create or replace function analista_equipa(p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('nome', s.nome, 'cargo', s.cargo, 'numeros', s.m)
                            order by (s.m ->> 'entregas')::int desc, (s.m ->> 'vendas_balcao')::int desc), '[]')
    from (select f.nome, f.cargo, metricas_funcionario_periodo(f.id, p_inicio, p_fim) as m
            from funcionarios f where f.deletado_em is null) s
   where (s.m ->> 'entregas')::int + (s.m ->> 'vendas_balcao')::int + (s.m ->> 'confirmados')::int > 0;
$$;

create or replace function analista_financas(p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public as $$
  with x as (select p.* from pedidos p where p.deletado_em is null and p.estado = 'entregue_pago'
              and (p.entregue_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  k as (select c.*, exists (select 1 from extratos e where e.deletado_em is null and e.estado in ('lido', 'manual')
                              and (c.criado_em at time zone 'Africa/Luanda')::date between e.periodo_inicio and e.periodo_fim) as coberto,
               exists (select 1 from extrato_movimentos m where m.comprovativo_id = c.id and m.deletado_em is null) as no_extrato
          from comprovativos_pagamento c where c.deletado_em is null
           and (c.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  cx as (select (fechamento ->> 'diferenca')::numeric as diferenca from caixa
          where deletado_em is null and fechamento is not null and data between p_inicio and p_fim)
  select jsonb_build_object(
    'receita_entregue_kz', (select coalesce(sum(subtotal + taxa_entrega - desconto_indicacao), 0) from x),
    'taxas_de_entrega_kz', (select coalesce(sum(taxa_entrega), 0) from x),
    'recebido_por_metodo_kz', coalesce((select jsonb_object_agg(metodo, v) from (
        select p ->> 'metodo' metodo, sum((p ->> 'valor')::numeric) v from x, jsonb_array_elements(x.parcelas) p group by 1) s), '{}'),
    'pago_com_pacotes_kz', (select coalesce(sum(pago_pacote), 0) from x),
    'descontos_convida_e_ganha_kz', (select coalesce(sum(desconto_indicacao), 0) from x),
    'saldo_convida_usado_kz', (select coalesce(sum(credito_indicacao_usado), 0) from x),
    'ganhos_convida_e_ganha_kz', coalesce((select jsonb_object_agg(estado, v) from (
        select estado, sum(valor) v from ganhos_indicacao where deletado_em is null
           and (criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim group by estado) s), '{}'),
    'pacotes_vendidos', (select jsonb_build_object('adesoes', count(*), 'valor_kz', coalesce(sum(preco), 0)) from adesoes_pacote
                          where deletado_em is null and pago_em is not null
                            and (pago_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
    'vendas_ao_balcao_kz', (select coalesce(sum(valor_total), 0) from vendas where deletado_em is null and pedido_id is null
                              and (data at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
    'comprovativos', (select jsonb_build_object('total', count(*), 'valor_kz', coalesce(sum(valor), 0),
                                                'por_conferir', count(*) filter (where estado = 'por_conferir'),
                                                'rejeitados', count(*) filter (where estado = 'rejeitado'),
                                                'sem_entrada_no_extrato', count(*) filter (where coberto and not no_extrato and estado <> 'rejeitado'),
                                                'sem_extrato_carregado', count(*) filter (where not coberto)) from k),
    'caixas', (select jsonb_build_object('fechadas', count(*), 'com_diferenca', count(*) filter (where diferenca <> 0),
                                         'soma_diferencas_kz', coalesce(sum(diferenca), 0)) from cx),
    'custos_por_categoria_kz', coalesce((select jsonb_object_agg(coalesce(categoria, 'outros'), v) from (
        select categoria, sum(valor) v from custos where deletado_em is null and data between p_inicio and p_fim group by 1) s), '{}'),
    'compensacoes_a_clientes_kz', (select coalesce(sum(compensacao_valor), 0) from reclamacoes
                                    where deletado_em is null and decidido_em is not null
                                      and (decidido_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim));
$$;

-- ---------------------------------------------------------------- Edge Function analista
-- Reserva uma pergunta: a indicada (a app pede logo a resposta) ou a mais antiga por responder
create or replace function reservar_pergunta(p_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  q perguntas_analista;
begin
  if not funcionalidade_activa('agente_analista') then return null; end if;
  select * into q from perguntas_analista
   where deletado_em is null and (p_id is null or id = p_id)
     and (estado = 'pendente' or (estado = 'a_responder' and atualizado_em < now() - interval '5 minutes'))
   order by criado_em limit 1 for update skip locked;
  if not found then return null; end if;
  update perguntas_analista set estado = 'a_responder', atualizado_em = now() where id = q.id;
  return jsonb_build_object('id', q.id, 'tipo', q.tipo, 'pergunta', q.pergunta, 'inicio', q.inicio, 'fim', q.fim,
                            'hoje', (now() at time zone 'Africa/Luanda')::date,
                            'cozinhas', (select coalesce(jsonb_agg(trim(nome)), '[]') from cozinhas where deletado_em is null),
                            'primeiro_pedido', (select (min(criado_em) at time zone 'Africa/Luanda')::date from pedidos where deletado_em is null));
end $$;

create or replace function registar_resposta_analista(p_id uuid, p_resultado text, p_resposta jsonb default null,
                                                      p_passos jsonb default '[]', p_nota text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  q perguntas_analista;
  v_estado text;
begin
  select * into q from perguntas_analista where id = p_id for update;
  if not found then raise exception 'pergunta_inexistente' using errcode = 'P0001'; end if;
  if p_resultado = 'erro' then
    update perguntas_analista
       set ia_tentativas = ia_tentativas + 1,
           estado = case when ia_tentativas + 1 >= 3 then 'indisponivel' else 'pendente' end,
           ia_nota = left(p_nota, 300), atualizado_em = now()
     where id = q.id returning estado into v_estado;
    return v_estado;
  end if;
  if p_resultado = 'indisponivel' then
    update perguntas_analista set estado = 'indisponivel', ia_nota = left(p_nota, 300), atualizado_em = now() where id = q.id;
    return 'indisponivel';
  end if;
  if p_resultado <> 'respondida' or nullif(trim(p_resposta ->> 'resposta'), '') is null then
    raise exception 'resultado_invalido' using errcode = 'P0001';
  end if;
  update perguntas_analista
     set estado = 'respondida', resposta = left(p_resposta ->> 'resposta', 6000),
         numeros = coalesce(p_resposta -> 'numeros_chave', '[]'), sugestoes = coalesce(p_resposta -> 'sugestoes', '[]'),
         limitacoes = left(p_resposta ->> 'limitacoes', 1000), passos = coalesce(p_passos, '[]'),
         ia_nota = left(p_nota, 300), respondida_em = now(), atualizado_em = now()
   where id = q.id;
  if q.tipo = 'relatorio_mensal' then
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select f, 'N25', jsonb_build_object('pergunta_id', q.id, 'mes', lower(nome_mes(extract(month from q.inicio)::int)),
                                        'ano', extract(year from q.inicio)::int)
      from funcionarios_com_permissao('analista.usar') f;
  end if;
  return 'respondida';
end $$;

-- Agenda o analista de minuto a minuto (a app também o chama logo depois de cada pergunta)
create or replace function agendar_analista(p_url text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format($f$select cron.schedule('analista', '* * * * *', %L)$f$,
    format('select net.http_post(url := %L, body := ''{}''::jsonb, timeout_milliseconds := 150000, headers := jsonb_build_object('
           '''Content-Type'', ''application/json'', ''x-envio-segredo'', '
           '(select valor from public.segredos_servidor where chave = ''envio_notificacoes'')))', p_url));
  return 'agendado';
end $$;

do $$
declare f text;
begin
  foreach f in array array['analista_vendas(date, date, text)', 'analista_pratos(date, date)', 'analista_clientes(date, date)',
                           'analista_operacao(date, date)', 'analista_satisfacao(date, date)', 'analista_equipa(date, date)',
                           'analista_financas(date, date)', 'reservar_pergunta(uuid)',
                           'registar_resposta_analista(uuid, text, jsonb, jsonb, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
revoke execute on function agendar_analista(text) from public, anon, authenticated;
