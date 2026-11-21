-- Recursos Humanos, fases 1 e 2:
--  * ficha do trabalhador (dados pessoais e bancários, contacto de emergência, admissão);
--  * documentos com validade (BI, carta, seguro e livrete da mota, declaração de saúde...);
--  * contratos com os tipos da Lei Geral do Trabalho (Lei n.º 12/23) e período experimental;
--  * equipamento entregue (mota da empresa, capacete, caixa térmica...) e devolução;
--  * folha de salários mensal com Segurança Social (INSS) e IRT, recibos e pagamento;
--  * custo do pessoal nos Resultados do mês.
-- Taxas e tabela do IRT ficam editáveis (rh_parametros / rh_irt_escaloes): os valores iniciais são
-- os da Lei n.º 14/25 (OGE 2026, Grupo A) e do Decreto Presidencial n.º 227/18 (INSS 3% + 8%), a
-- confirmar com o contabilista. Dados pessoais só com a permissão rh.gerir.

insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'rh.gerir',          'Recursos humanos', 'Fichas, documentos, contratos e equipamento da equipa (dados pessoais)'),
  ('servidor', 'rh.salarios',       'Recursos humanos', 'Folha de salários: calcular, ajustar e fechar o mês; taxas do INSS e tabela do IRT'),
  ('servidor', 'financas.salarios', 'Finanças',         'Pagar os salários da folha fechada')
on conflict (chave) do update set grupo = excluded.grupo, descricao = excluded.descricao, deletado_em = null, atualizado_em = now();

-- ------------------------------------------------------------------ fichas e documentos
create table if not exists rh_fichas (
  funcionario_id        uuid primary key references funcionarios(id),
  atualizado_em         timestamptz not null default now(),
  bi                    text check (bi is null or length(bi) <= 30),
  nif                   text check (nif is null or length(nif) <= 30),
  inss_numero           text check (inss_numero is null or length(inss_numero) <= 30),
  data_nascimento       date,
  morada                text check (morada is null or length(morada) <= 200),
  banco                 text check (banco is null or length(banco) <= 60),
  iban                  text check (iban is null or length(iban) <= 40),
  emergencia_nome       text check (emergencia_nome is null or length(emergencia_nome) <= 120),
  emergencia_telefone   text check (emergencia_telefone is null or length(emergencia_telefone) <= 30),
  data_admissao         date,
  notas                 text check (notas is null or length(notas) <= 500),
  atualizado_por        uuid references funcionarios(id)
);
create index if not exists rh_fichas_atualizado_por_idx on rh_fichas (atualizado_por);

create table if not exists rh_documentos (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  deletado_em     timestamptz,
  funcionario_id  uuid not null references funcionarios(id),
  tipo            text not null check (tipo in ('bi', 'nif', 'cartao_inss', 'carta_conducao', 'livrete_mota', 'seguro_mota',
                                                'declaracao_saude', 'registo_criminal', 'contrato_assinado', 'outro')),
  numero          text check (numero is null or length(numero) <= 60),
  validade        date,
  notas           text check (notas is null or length(notas) <= 200),
  criado_por      uuid references funcionarios(id)
);
create index if not exists rh_documentos_funcionario_idx on rh_documentos (funcionario_id);
create index if not exists rh_documentos_criado_por_idx on rh_documentos (criado_por);

-- ------------------------------------------------------------------ contratos
create table if not exists rh_contratos (
  id                          uuid primary key default gen_random_uuid(),
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  funcionario_id              uuid not null references funcionarios(id),
  tipo                        text not null check (tipo in ('indeterminado', 'termo_certo', 'termo_incerto', 'tempo_parcial',
                                                            'temporario', 'estagio', 'teletrabalho', 'prestacao_servicos')),
  funcao                      text check (funcao is null or length(funcao) <= 80),
  inicio                      date not null,
  fim                         date,
  periodo_experimental_dias   integer not null default 0 check (periodo_experimental_dias between 0 and 180),
  horas_semana                integer check (horas_semana is null or horas_semana between 1 and 60),
  salario_base                integer not null default 0 check (salario_base between 0 and 100000000),
  subsidio_alimentacao        integer not null default 0 check (subsidio_alimentacao between 0 and 10000000),
  subsidio_transporte         integer not null default 0 check (subsidio_transporte between 0 and 10000000),
  outros_subsidios            integer not null default 0 check (outros_subsidios between 0 and 10000000),
  activo                      boolean not null default true,
  terminado_em                date,
  motivo_fim                  text check (motivo_fim is null or length(motivo_fim) <= 200),
  notas                       text check (notas is null or length(notas) <= 500),
  criado_por                  uuid references funcionarios(id),
  check (fim is null or fim >= inicio)
);
create index if not exists rh_contratos_funcionario_idx on rh_contratos (funcionario_id);
create index if not exists rh_contratos_criado_por_idx on rh_contratos (criado_por);
create unique index if not exists rh_contratos_um_activo on rh_contratos (funcionario_id) where activo;

-- ------------------------------------------------------------------ equipamento
create table if not exists rh_equipamentos (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  funcionario_id  uuid not null references funcionarios(id),
  tipo            text not null check (tipo in ('mota', 'capacete', 'colete', 'caixa_termica', 'uniforme', 'telemovel', 'outro')),
  descricao       text check (descricao is null or length(descricao) <= 120),
  matricula       text check (matricula is null or length(matricula) <= 20),
  propriedade     text not null default 'empresa' check (propriedade in ('empresa', 'trabalhador', 'servico_contratado')),
  entregue_em     date not null default current_date,
  devolvido_em    date,
  estado_devolucao text check (estado_devolucao is null or length(estado_devolucao) <= 120),
  criado_por      uuid references funcionarios(id)
);
create index if not exists rh_equipamentos_funcionario_idx on rh_equipamentos (funcionario_id);
create index if not exists rh_equipamentos_criado_por_idx on rh_equipamentos (criado_por);

-- ------------------------------------------------------------------ taxas e tabela do IRT
create table if not exists rh_parametros (
  unico                   boolean primary key default true check (unico),
  atualizado_em           timestamptz not null default now(),
  inss_trabalhador        numeric(5,2) not null default 3 check (inss_trabalhador between 0 and 50),
  inss_empresa            numeric(5,2) not null default 8 check (inss_empresa between 0 and 50),
  isencao_alimentacao     integer not null default 30000 check (isencao_alimentacao >= 0),
  isencao_transporte      integer not null default 30000 check (isencao_transporte >= 0),
  subsidio_ferias_pct     numeric(5,2) not null default 50 check (subsidio_ferias_pct between 0 and 200),
  subsidio_natal_pct      numeric(5,2) not null default 50 check (subsidio_natal_pct between 0 and 200),
  referencia_legal        text not null default 'IRT: Lei n.º 14/25 (OGE 2026), Grupo A. INSS: Decreto Presidencial n.º 227/18. Confirmar com o contabilista.',
  atualizado_por          uuid references funcionarios(id)
);
create index if not exists rh_parametros_atualizado_por_idx on rh_parametros (atualizado_por);
insert into rh_parametros (unico) values (true) on conflict do nothing;

create table if not exists rh_irt_escaloes (
  ordem             integer primary key check (ordem between 1 and 30),
  limite_inferior   integer not null check (limite_inferior >= 0),
  limite_superior   integer check (limite_superior is null or limite_superior >= limite_inferior),
  parcela_fixa      integer not null default 0 check (parcela_fixa >= 0),
  taxa              numeric(5,2) not null default 0 check (taxa between 0 and 100),
  excesso           integer not null default 0 check (excesso >= 0)
);
insert into rh_irt_escaloes (ordem, limite_inferior, limite_superior, parcela_fixa, taxa, excesso) values
  ( 1,        0,   150000,        0,  0,          0),
  ( 2,   150001,   200000,    12500, 16,     150000),
  ( 3,   200001,   300000,    31250, 18,     200000),
  ( 4,   300001,   500000,    49250, 19,     300000),
  ( 5,   500001,  1000000,    87250, 20,     500000),
  ( 6,  1000001,  1500000,   187250, 21,    1000000),
  ( 7,  1500001,  2000000,   292250, 22,    1500000),
  ( 8,  2000001,  2500000,   402250, 23,    2000000),
  ( 9,  2500001,  5000000,   517250, 24,    2500000),
  (10,  5000001, 10000000,  1117250, 24.5,  5000000),
  (11, 10000001,     null,  2342250, 25,   10000000)
on conflict (ordem) do nothing;

-- ------------------------------------------------------------------ folha de salários
create table if not exists rh_folhas (
  mes           date primary key check (extract(day from mes) = 1),
  estado        text not null default 'fechada' check (estado in ('fechada')),
  fechada_em    timestamptz not null default now(),
  fechada_por   uuid references funcionarios(id)
);
create index if not exists rh_folhas_fechada_por_idx on rh_folhas (fechada_por);

-- Ajustes do mês antes de fechar (horas extra/bónus, faltas, subsídios de férias e de Natal)
create table if not exists rh_folha_ajustes (
  mes             date not null check (extract(day from mes) = 1),
  funcionario_id  uuid not null references funcionarios(id),
  extras          integer not null default 0 check (extras between 0 and 100000000),
  descontos       integer not null default 0 check (descontos between 0 and 100000000),
  sub_ferias      boolean not null default false,
  sub_natal       boolean not null default false,
  nota            text check (nota is null or length(nota) <= 200),
  atualizado_em   timestamptz not null default now(),
  primary key (mes, funcionario_id)
);
create index if not exists rh_folha_ajustes_funcionario_idx on rh_folha_ajustes (funcionario_id);

create table if not exists rh_folha_linhas (
  id                  uuid primary key default gen_random_uuid(),
  mes                 date not null references rh_folhas(mes),
  funcionario_id      uuid not null references funcionarios(id),
  contrato_id         uuid references rh_contratos(id),
  dias                integer not null,
  salario_base        integer not null,
  sub_alimentacao     integer not null,
  sub_transporte      integer not null,
  outros_subsidios    integer not null,
  extras              integer not null,
  sub_ferias          integer not null,
  sub_natal           integer not null,
  descontos           integer not null,
  bruto               integer not null,
  inss_trabalhador    integer not null,
  inss_empresa        integer not null,
  materia_colectavel  integer not null,
  irt                 integer not null,
  liquido             integer not null,
  nota                text,
  pago_em             timestamptz,
  metodo              text check (metodo is null or metodo in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money')),
  referencia          text check (referencia is null or length(referencia) between 1 and 60),
  pago_por            uuid references funcionarios(id),
  unique (mes, funcionario_id)
);
create index if not exists rh_folha_linhas_funcionario_idx on rh_folha_linhas (funcionario_id);
create index if not exists rh_folha_linhas_contrato_idx on rh_folha_linhas (contrato_id);
create index if not exists rh_folha_linhas_pago_por_idx on rh_folha_linhas (pago_por);

alter table rh_fichas enable row level security;
alter table rh_documentos enable row level security;
alter table rh_contratos enable row level security;
alter table rh_equipamentos enable row level security;
alter table rh_parametros enable row level security;
alter table rh_irt_escaloes enable row level security;
alter table rh_folhas enable row level security;
alter table rh_folha_ajustes enable row level security;
alter table rh_folha_linhas enable row level security;
revoke all on rh_fichas, rh_documentos, rh_contratos, rh_equipamentos, rh_parametros, rh_irt_escaloes,
              rh_folhas, rh_folha_ajustes, rh_folha_linhas from anon, authenticated;

-- ------------------------------------------------------------------ cálculos
create or replace function irt_calcular(p_materia integer) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce((select e.parcela_fixa + round(greatest(p_materia - e.excesso, 0) * e.taxa / 100.0)::int
                     from rh_irt_escaloes e
                    where p_materia >= e.limite_inferior and (e.limite_superior is null or p_materia <= e.limite_superior)
                    order by e.ordem limit 1), 0);
$$;
revoke execute on function irt_calcular(integer) from public, anon, authenticated;

-- Um salário: bruto, INSS (trabalhador e empresa), matéria colectável, IRT e líquido
create or replace function rh_calcular(p_base integer, p_alim integer, p_transp integer, p_outros integer,
                                       p_extras integer default 0, p_descontos integer default 0,
                                       p_sub_ferias integer default 0, p_sub_natal integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  k rh_parametros;
  v_bruto int; v_inss_t int; v_inss_e int; v_isento int; v_mat int; v_irt int;
begin
  select * into k from rh_parametros where unico;
  v_bruto := greatest(coalesce(p_base, 0) + coalesce(p_alim, 0) + coalesce(p_transp, 0) + coalesce(p_outros, 0)
                      + coalesce(p_extras, 0) + coalesce(p_sub_ferias, 0) + coalesce(p_sub_natal, 0) - coalesce(p_descontos, 0), 0);
  v_inss_t := round(v_bruto * k.inss_trabalhador / 100.0)::int;
  v_inss_e := round(v_bruto * k.inss_empresa / 100.0)::int;
  v_isento := least(coalesce(p_alim, 0), k.isencao_alimentacao) + least(coalesce(p_transp, 0), k.isencao_transporte);
  v_mat := greatest(v_bruto - v_isento - v_inss_t, 0);
  v_irt := irt_calcular(v_mat);
  return jsonb_build_object('bruto', v_bruto, 'inss_trabalhador', v_inss_t, 'inss_empresa', v_inss_e,
                            'isento', v_isento, 'materia_colectavel', v_mat, 'irt', v_irt,
                            'liquido', v_bruto - v_inss_t - v_irt, 'custo_empresa', v_bruto + v_inss_e);
end $$;
revoke execute on function rh_calcular(integer, integer, integer, integer, integer, integer, integer, integer) from public, anon, authenticated;

-- Linhas da folha de um mês (calculadas; se o mês estiver fechado, as gravadas)
create or replace function rh_folha_calcular(p_mes date)
returns table(funcionario_id uuid, nome text, contrato_id uuid, tipo text, dias integer, salario_base integer,
              sub_alimentacao integer, sub_transporte integer, outros_subsidios integer, extras integer,
              sub_ferias integer, sub_natal integer, descontos integer, bruto integer, inss_trabalhador integer,
              inss_empresa integer, materia_colectavel integer, irt integer, liquido integer, nota text,
              pago_em timestamptz, metodo text, referencia text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini date := mes_inicio(p_mes);
  v_fim date := (mes_inicio(p_mes) + interval '1 month - 1 day')::date;
  v_dias_mes int := extract(day from (mes_inicio(p_mes) + interval '1 month - 1 day'))::int;
  k rh_parametros;
begin
  select * into k from rh_parametros where unico;
  if exists (select 1 from rh_folhas where mes = v_ini) then
    return query
      select l.funcionario_id, f.nome, l.contrato_id, c.tipo, l.dias, l.salario_base, l.sub_alimentacao, l.sub_transporte,
             l.outros_subsidios, l.extras, l.sub_ferias, l.sub_natal, l.descontos, l.bruto, l.inss_trabalhador, l.inss_empresa,
             l.materia_colectavel, l.irt, l.liquido, l.nota, l.pago_em, l.metodo, l.referencia
        from rh_folha_linhas l join funcionarios f on f.id = l.funcionario_id
        left join rh_contratos c on c.id = l.contrato_id
       where l.mes = v_ini order by f.nome;
    return;
  end if;
  return query
  with c as (
    select distinct on (ct.funcionario_id) ct.*,
           (least(coalesce(ct.fim, v_fim), coalesce(ct.terminado_em, v_fim), v_fim) - greatest(ct.inicio, v_ini) + 1) as d
      from rh_contratos ct join funcionarios f on f.id = ct.funcionario_id and f.deletado_em is null
     where ct.tipo <> 'prestacao_servicos'
       and ct.inicio <= v_fim and coalesce(ct.fim, v_fim) >= v_ini and coalesce(ct.terminado_em, v_fim) >= v_ini
     order by ct.funcionario_id, ct.inicio desc),
  b as (
    select c.*, f.nome,
           round(c.salario_base * least(c.d, v_dias_mes)::numeric / v_dias_mes)::int as base,
           round(c.subsidio_alimentacao * least(c.d, v_dias_mes)::numeric / v_dias_mes)::int as alim,
           round(c.subsidio_transporte * least(c.d, v_dias_mes)::numeric / v_dias_mes)::int as transp,
           round(c.outros_subsidios * least(c.d, v_dias_mes)::numeric / v_dias_mes)::int as outros,
           coalesce(a.extras, 0) as ex, coalesce(a.descontos, 0) as de,
           case when a.sub_ferias then round(c.salario_base * k.subsidio_ferias_pct / 100.0)::int else 0 end as sf,
           case when a.sub_natal then round(c.salario_base * k.subsidio_natal_pct / 100.0)::int else 0 end as sn,
           a.nota as nt
      from c join funcionarios f on f.id = c.funcionario_id
      left join rh_folha_ajustes a on a.mes = v_ini and a.funcionario_id = c.funcionario_id
     where c.d > 0),
  r as (select b.*, rh_calcular(b.base, b.alim, b.transp, b.outros, b.ex, b.de, b.sf, b.sn) as x from b)
  select r.funcionario_id, r.nome, r.id, r.tipo, least(r.d, v_dias_mes)::int, r.base, r.alim, r.transp, r.outros, r.ex,
         r.sf, r.sn, r.de, (r.x ->> 'bruto')::int, (r.x ->> 'inss_trabalhador')::int, (r.x ->> 'inss_empresa')::int,
         (r.x ->> 'materia_colectavel')::int, (r.x ->> 'irt')::int, (r.x ->> 'liquido')::int, r.nt,
         null::timestamptz, null::text, null::text
    from r order by r.nome;
end $$;
revoke execute on function rh_folha_calcular(date) from public, anon, authenticated;

-- Custo do pessoal de um mês (folha: bruto + INSS da empresa)
create or replace function custo_pessoal_mes(p_mes date) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce(sum(bruto + inss_empresa), 0)::int from rh_folha_calcular(p_mes);
$$;
revoke execute on function custo_pessoal_mes(date) from public, anon, authenticated;

-- ------------------------------------------------------------------ RPCs: equipa e fichas (rh.gerir)
create or replace function rh_exigir(p text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao(p) then raise exception 'sem_permissao' using errcode = '42501', detail = p; end if;
end $$;
revoke execute on function rh_exigir(text) from public, anon, authenticated;

create or replace function rh_alertas(p_func uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(a order by a), '[]'::jsonb) from (
    select 'Sem contrato registado' as a
     where not exists (select 1 from rh_contratos c where c.funcionario_id = p_func and c.activo)
    union all
    select 'Falta o NIF ou o n.º da Segurança Social'
     where not exists (select 1 from rh_fichas r where r.funcionario_id = p_func and r.nif is not null and r.inss_numero is not null)
    union all
    select case when d.validade < current_date then 'Caducado: ' else 'Caduca em breve: ' end
           || replace(d.tipo, '_', ' ') || ' (' || to_char(d.validade, 'DD/MM/YYYY') || ')'
      from rh_documentos d
     where d.funcionario_id = p_func and d.deletado_em is null and d.validade is not null
       and d.validade <= current_date + 30
    union all
    select 'Contrato termina a ' || to_char(c.fim, 'DD/MM/YYYY')
      from rh_contratos c where c.funcionario_id = p_func and c.activo and c.fim is not null and c.fim <= current_date + 30
    union all
    select 'Período experimental termina a ' || to_char(c.inicio + c.periodo_experimental_dias, 'DD/MM/YYYY')
      from rh_contratos c where c.funcionario_id = p_func and c.activo and c.periodo_experimental_dias > 0
       and c.inicio + c.periodo_experimental_dias between current_date and current_date + 15
    union all
    select 'Salário em duplicado: tem salário no contrato e no pagamento dos estafetas'
     where exists (select 1 from rh_contratos c where c.funcionario_id = p_func and c.activo and c.salario_base > 0)
       and exists (select 1 from estafetas_remuneracao e where e.funcionario_id = p_func and e.salario_mensal > 0)
  ) s;
$$;
revoke execute on function rh_alertas(uuid) from public, anon, authenticated;

create or replace function rh_lista() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform rh_exigir('rh.gerir');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'funcionario_id', f.id, 'nome', f.nome, 'cargo', f.cargo, 'telefone', f.telefone,
             'admissao', coalesce(r.data_admissao, (f.criado_em at time zone 'Africa/Luanda')::date),
             'contrato', (select jsonb_build_object('tipo', c.tipo, 'inicio', c.inicio, 'fim', c.fim, 'salario_base', c.salario_base)
                            from rh_contratos c where c.funcionario_id = f.id and c.activo),
             'equipamentos', (select count(*) from rh_equipamentos e where e.funcionario_id = f.id and e.devolvido_em is null),
             'alertas', rh_alertas(f.id)) order by f.nome)
      from funcionarios f left join rh_fichas r on r.funcionario_id = f.id
     where f.deletado_em is null), '[]'::jsonb);
end $$;
revoke execute on function rh_lista() from public, anon;
grant execute on function rh_lista() to authenticated;

create or replace function rh_ficha(p_func uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f funcionarios;
begin
  perform rh_exigir('rh.gerir');
  select * into f from funcionarios where id = p_func and deletado_em is null;
  if not found then raise exception 'funcionario_inexistente' using errcode = 'P0001'; end if;
  return jsonb_build_object(
    'funcionario_id', f.id, 'nome', f.nome, 'cargo', f.cargo, 'telefone', f.telefone,
    'ficha', (select to_jsonb(r) - 'funcionario_id' - 'atualizado_por' from rh_fichas r where r.funcionario_id = f.id),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'numero', d.numero,
                                    'validade', d.validade, 'notas', d.notas) order by d.tipo, d.validade)
                              from rh_documentos d where d.funcionario_id = f.id and d.deletado_em is null), '[]'::jsonb),
    'contratos', coalesce((select jsonb_agg(to_jsonb(c) - 'criado_por' - 'funcionario_id' order by c.activo desc, c.inicio desc)
                             from rh_contratos c where c.funcionario_id = f.id), '[]'::jsonb),
    'equipamentos', coalesce((select jsonb_agg(to_jsonb(e) - 'criado_por' - 'funcionario_id' order by e.devolvido_em nulls first, e.entregue_em desc)
                                from rh_equipamentos e where e.funcionario_id = f.id), '[]'::jsonb),
    'alertas', rh_alertas(f.id));
end $$;
revoke execute on function rh_ficha(uuid) from public, anon;
grant execute on function rh_ficha(uuid) to authenticated;

create or replace function rh_guardar_ficha(p_func uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rh_exigir('rh.gerir');
  if not exists (select 1 from funcionarios where id = p_func and deletado_em is null) then
    raise exception 'funcionario_inexistente' using errcode = 'P0001';
  end if;
  insert into rh_fichas (funcionario_id, bi, nif, inss_numero, data_nascimento, morada, banco, iban,
                         emergencia_nome, emergencia_telefone, data_admissao, notas, atualizado_por)
  values (p_func, nullif(btrim(p ->> 'bi'), ''), nullif(btrim(p ->> 'nif'), ''), nullif(btrim(p ->> 'inss_numero'), ''),
          nullif(p ->> 'data_nascimento', '')::date, nullif(btrim(p ->> 'morada'), ''), nullif(btrim(p ->> 'banco'), ''),
          nullif(upper(replace(p ->> 'iban', ' ', '')), ''), nullif(btrim(p ->> 'emergencia_nome'), ''),
          nullif(btrim(p ->> 'emergencia_telefone'), ''), nullif(p ->> 'data_admissao', '')::date,
          nullif(btrim(p ->> 'notas'), ''), funcionario_actual())
  on conflict (funcionario_id) do update set
    bi = excluded.bi, nif = excluded.nif, inss_numero = excluded.inss_numero, data_nascimento = excluded.data_nascimento,
    morada = excluded.morada, banco = excluded.banco, iban = excluded.iban, emergencia_nome = excluded.emergencia_nome,
    emergencia_telefone = excluded.emergencia_telefone, data_admissao = excluded.data_admissao, notas = excluded.notas,
    atualizado_por = excluded.atualizado_por, atualizado_em = now();
  -- Na auditoria fica só que a ficha mudou (os dados pessoais não se copiam para lá)
  perform registar_auditoria('rh_ficha', 'funcionarios', p_func, '{}'::jsonb);
end $$;
revoke execute on function rh_guardar_ficha(uuid, jsonb) from public, anon;
grant execute on function rh_guardar_ficha(uuid, jsonb) to authenticated;

create or replace function rh_guardar_documento(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_func uuid := nullif(p ->> 'funcionario_id', '')::uuid;
begin
  perform rh_exigir('rh.gerir');
  if v_id is null then
    if not exists (select 1 from funcionarios where id = v_func and deletado_em is null) then
      raise exception 'funcionario_inexistente' using errcode = 'P0001';
    end if;
    insert into rh_documentos (funcionario_id, tipo, numero, validade, notas, criado_por)
    values (v_func, p ->> 'tipo', nullif(btrim(p ->> 'numero'), ''), nullif(p ->> 'validade', '')::date,
            nullif(btrim(p ->> 'notas'), ''), funcionario_actual())
    returning id into v_id;
  else
    update rh_documentos set tipo = p ->> 'tipo', numero = nullif(btrim(p ->> 'numero'), ''),
           validade = nullif(p ->> 'validade', '')::date, notas = nullif(btrim(p ->> 'notas'), '')
     where id = v_id and deletado_em is null;
    if not found then raise exception 'documento_inexistente' using errcode = 'P0001'; end if;
  end if;
  return v_id;
end $$;
revoke execute on function rh_guardar_documento(jsonb) from public, anon;
grant execute on function rh_guardar_documento(jsonb) to authenticated;

create or replace function rh_apagar_documento(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rh_exigir('rh.gerir');
  update rh_documentos set deletado_em = now() where id = p_id and deletado_em is null;
end $$;
revoke execute on function rh_apagar_documento(uuid) from public, anon;
grant execute on function rh_apagar_documento(uuid) to authenticated;

-- Novo contrato (fecha o activo anterior) ou alteração de um contrato
create or replace function rh_guardar_contrato(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_func uuid := nullif(p ->> 'funcionario_id', '')::uuid;
  v_tipo text := p ->> 'tipo';
  v_ini date := nullif(p ->> 'inicio', '')::date;
  v_fim date := nullif(p ->> 'fim', '')::date;
  v_pe int := coalesce(nullif(p ->> 'periodo_experimental_dias', '')::int,
                       case when p ->> 'tipo' in ('termo_certo', 'termo_incerto', 'temporario') then 30
                            when p ->> 'tipo' = 'prestacao_servicos' then 0 else 60 end);
begin
  perform rh_exigir('rh.gerir');
  if v_ini is null then raise exception 'inicio_obrigatorio' using errcode = 'P0001'; end if;
  if v_tipo = 'termo_certo' and v_fim is null then raise exception 'fim_obrigatorio' using errcode = 'P0001'; end if;
  if v_tipo in ('termo_certo', 'termo_incerto', 'temporario') and v_pe > 30 then
    raise exception 'periodo_experimental_maximo_30' using errcode = 'P0001';
  end if;
  if v_id is null then
    if not exists (select 1 from funcionarios where id = v_func and deletado_em is null) then
      raise exception 'funcionario_inexistente' using errcode = 'P0001';
    end if;
    update rh_contratos set activo = false, terminado_em = coalesce(terminado_em, v_ini - 1),
           motivo_fim = coalesce(motivo_fim, 'Substituído por novo contrato'), atualizado_em = now()
     where funcionario_id = v_func and activo;
    insert into rh_contratos (funcionario_id, tipo, funcao, inicio, fim, periodo_experimental_dias, horas_semana, salario_base,
                              subsidio_alimentacao, subsidio_transporte, outros_subsidios, notas, criado_por)
    values (v_func, v_tipo, nullif(btrim(p ->> 'funcao'), ''), v_ini, v_fim, v_pe, nullif(p ->> 'horas_semana', '')::int,
            coalesce((p ->> 'salario_base')::int, 0), coalesce((p ->> 'subsidio_alimentacao')::int, 0),
            coalesce((p ->> 'subsidio_transporte')::int, 0), coalesce((p ->> 'outros_subsidios')::int, 0),
            nullif(btrim(p ->> 'notas'), ''), funcionario_actual())
    returning id into v_id;
  else
    update rh_contratos set tipo = v_tipo, funcao = nullif(btrim(p ->> 'funcao'), ''), inicio = v_ini, fim = v_fim,
           periodo_experimental_dias = v_pe, horas_semana = nullif(p ->> 'horas_semana', '')::int,
           salario_base = coalesce((p ->> 'salario_base')::int, 0), subsidio_alimentacao = coalesce((p ->> 'subsidio_alimentacao')::int, 0),
           subsidio_transporte = coalesce((p ->> 'subsidio_transporte')::int, 0), outros_subsidios = coalesce((p ->> 'outros_subsidios')::int, 0),
           notas = nullif(btrim(p ->> 'notas'), ''), atualizado_em = now()
     where id = v_id and activo;
    if not found then raise exception 'contrato_inexistente' using errcode = 'P0001'; end if;
    select funcionario_id into v_func from rh_contratos where id = v_id;
  end if;
  perform registar_auditoria('rh_contrato', 'funcionarios', v_func,
    jsonb_build_object('tipo', v_tipo, 'inicio', v_ini, 'fim', v_fim, 'salario_base', (p ->> 'salario_base')::int));
  return v_id;
end $$;
revoke execute on function rh_guardar_contrato(jsonb) from public, anon;
grant execute on function rh_guardar_contrato(jsonb) to authenticated;

create or replace function rh_terminar_contrato(p_id uuid, p_data date, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rh_exigir('rh.gerir');
  if p_data is null then raise exception 'data_obrigatoria' using errcode = 'P0001'; end if;
  update rh_contratos set activo = false, terminado_em = p_data, motivo_fim = nullif(btrim(p_motivo), ''), atualizado_em = now()
   where id = p_id and activo;
  if not found then raise exception 'contrato_inexistente' using errcode = 'P0001'; end if;
  perform registar_auditoria('rh_contrato_terminado', 'rh_contratos', p_id, jsonb_build_object('data', p_data, 'motivo', p_motivo));
end $$;
revoke execute on function rh_terminar_contrato(uuid, date, text) from public, anon;
grant execute on function rh_terminar_contrato(uuid, date, text) to authenticated;

create or replace function rh_guardar_equipamento(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_func uuid := nullif(p ->> 'funcionario_id', '')::uuid;
begin
  perform rh_exigir('rh.gerir');
  if not exists (select 1 from funcionarios where id = v_func and deletado_em is null) then
    raise exception 'funcionario_inexistente' using errcode = 'P0001';
  end if;
  insert into rh_equipamentos (funcionario_id, tipo, descricao, matricula, propriedade, entregue_em, criado_por)
  values (v_func, p ->> 'tipo', nullif(btrim(p ->> 'descricao'), ''), nullif(upper(btrim(p ->> 'matricula')), ''),
          coalesce(nullif(p ->> 'propriedade', ''), 'empresa'), coalesce(nullif(p ->> 'entregue_em', '')::date, current_date),
          funcionario_actual())
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function rh_guardar_equipamento(jsonb) from public, anon;
grant execute on function rh_guardar_equipamento(jsonb) to authenticated;

create or replace function rh_devolver_equipamento(p_id uuid, p_estado text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rh_exigir('rh.gerir');
  update rh_equipamentos set devolvido_em = current_date, estado_devolucao = nullif(btrim(p_estado), '')
   where id = p_id and devolvido_em is null;
  if not found then raise exception 'equipamento_inexistente' using errcode = 'P0001'; end if;
end $$;
revoke execute on function rh_devolver_equipamento(uuid, text) from public, anon;
grant execute on function rh_devolver_equipamento(uuid, text) to authenticated;

-- ------------------------------------------------------------------ RPCs: salários (rh.salarios / financas.salarios)
create or replace function rh_parametros_ler() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (tem_permissao('rh.salarios') or tem_permissao('financas.salarios')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'rh.salarios';
  end if;
  return jsonb_build_object(
    'parametros', (select to_jsonb(k) - 'unico' - 'atualizado_por' from rh_parametros k where unico),
    'escaloes', (select jsonb_agg(to_jsonb(e) order by e.ordem) from rh_irt_escaloes e));
end $$;
revoke execute on function rh_parametros_ler() from public, anon;
grant execute on function rh_parametros_ler() to authenticated;

-- Guarda as taxas e, se vier, a tabela do IRT inteira (substitui)
create or replace function rh_parametros_guardar(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  e jsonb;
  n int := 0;
begin
  perform rh_exigir('rh.salarios');
  update rh_parametros set
    inss_trabalhador = coalesce((p ->> 'inss_trabalhador')::numeric, inss_trabalhador),
    inss_empresa = coalesce((p ->> 'inss_empresa')::numeric, inss_empresa),
    isencao_alimentacao = coalesce((p ->> 'isencao_alimentacao')::int, isencao_alimentacao),
    isencao_transporte = coalesce((p ->> 'isencao_transporte')::int, isencao_transporte),
    subsidio_ferias_pct = coalesce((p ->> 'subsidio_ferias_pct')::numeric, subsidio_ferias_pct),
    subsidio_natal_pct = coalesce((p ->> 'subsidio_natal_pct')::numeric, subsidio_natal_pct),
    referencia_legal = coalesce(nullif(btrim(p ->> 'referencia_legal'), ''), referencia_legal),
    atualizado_por = funcionario_actual(), atualizado_em = now()
   where unico;
  if jsonb_typeof(p -> 'escaloes') = 'array' then
    if jsonb_array_length(p -> 'escaloes') = 0 then raise exception 'tabela_vazia' using errcode = 'P0001'; end if;
    delete from rh_irt_escaloes;
    for e in select * from jsonb_array_elements(p -> 'escaloes') loop
      n := n + 1;
      insert into rh_irt_escaloes (ordem, limite_inferior, limite_superior, parcela_fixa, taxa, excesso)
      values (n, (e ->> 'limite_inferior')::int, nullif(e ->> 'limite_superior', '')::int,
              coalesce((e ->> 'parcela_fixa')::int, 0), coalesce((e ->> 'taxa')::numeric, 0), coalesce((e ->> 'excesso')::int, 0));
    end loop;
  end if;
  perform registar_auditoria('rh_parametros', 'rh_parametros', null, p);
end $$;
revoke execute on function rh_parametros_guardar(jsonb) from public, anon;
grant execute on function rh_parametros_guardar(jsonb) to authenticated;

-- Simulação de um salário (para o contrato e para conferir)
create or replace function rh_simular_salario(p_base integer, p_alim integer, p_transp integer, p_outros integer) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (tem_permissao('rh.salarios') or tem_permissao('rh.gerir')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'rh.salarios';
  end if;
  return rh_calcular(p_base, p_alim, p_transp, p_outros);
end $$;
revoke execute on function rh_simular_salario(integer, integer, integer, integer) from public, anon;
grant execute on function rh_simular_salario(integer, integer, integer, integer) to authenticated;

create or replace function rh_folha(p_mes date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_mes date := mes_inicio(coalesce(p_mes, (now() at time zone 'Africa/Luanda')::date));
  v_linhas jsonb;
begin
  if not (tem_permissao('rh.salarios') or tem_permissao('financas.salarios')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'rh.salarios';
  end if;
  v_linhas := coalesce((select jsonb_agg(to_jsonb(l)) from rh_folha_calcular(v_mes) l), '[]'::jsonb);
  return jsonb_build_object(
    'mes', v_mes,
    'fechada', exists (select 1 from rh_folhas where mes = v_mes),
    'pode_fechar', (v_mes + interval '1 month')::date <= (now() at time zone 'Africa/Luanda')::date + 5,
    'linhas', v_linhas,
    'totais', (select jsonb_build_object(
                 'bruto', coalesce(sum((l ->> 'bruto')::int), 0), 'inss_trabalhador', coalesce(sum((l ->> 'inss_trabalhador')::int), 0),
                 'inss_empresa', coalesce(sum((l ->> 'inss_empresa')::int), 0), 'irt', coalesce(sum((l ->> 'irt')::int), 0),
                 'liquido', coalesce(sum((l ->> 'liquido')::int), 0),
                 'custo_empresa', coalesce(sum((l ->> 'bruto')::int + (l ->> 'inss_empresa')::int), 0),
                 'por_pagar', coalesce(sum((l ->> 'liquido')::int) filter (where l ->> 'pago_em' is null), 0))
                 from jsonb_array_elements(v_linhas) l),
    'prestadores', coalesce((select jsonb_agg(jsonb_build_object('nome', f.nome, 'funcao', c.funcao) order by f.nome)
                               from rh_contratos c join funcionarios f on f.id = c.funcionario_id and f.deletado_em is null
                              where c.activo and c.tipo = 'prestacao_servicos'), '[]'::jsonb));
end $$;
revoke execute on function rh_folha(date) from public, anon;
grant execute on function rh_folha(date) to authenticated;

create or replace function rh_folha_ajustar(p_mes date, p_func uuid, p_extras integer, p_descontos integer,
                                            p_sub_ferias boolean, p_sub_natal boolean, p_nota text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_mes date := mes_inicio(p_mes);
begin
  perform rh_exigir('rh.salarios');
  if exists (select 1 from rh_folhas where mes = v_mes) then raise exception 'folha_fechada' using errcode = 'P0001'; end if;
  if coalesce(p_extras, 0) < 0 or coalesce(p_descontos, 0) < 0 then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  insert into rh_folha_ajustes (mes, funcionario_id, extras, descontos, sub_ferias, sub_natal, nota)
  values (v_mes, p_func, coalesce(p_extras, 0), coalesce(p_descontos, 0), coalesce(p_sub_ferias, false),
          coalesce(p_sub_natal, false), nullif(btrim(p_nota), ''))
  on conflict (mes, funcionario_id) do update set extras = excluded.extras, descontos = excluded.descontos,
     sub_ferias = excluded.sub_ferias, sub_natal = excluded.sub_natal, nota = excluded.nota, atualizado_em = now();
end $$;
revoke execute on function rh_folha_ajustar(date, uuid, integer, integer, boolean, boolean, text) from public, anon;
grant execute on function rh_folha_ajustar(date, uuid, integer, integer, boolean, boolean, text) to authenticated;

-- Fecha a folha do mês: grava as linhas (deixam de mudar com contratos ou taxas)
create or replace function rh_folha_fechar(p_mes date) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_mes date := mes_inicio(p_mes);
  v_calc jsonb;
  n int;
begin
  perform rh_exigir('rh.salarios');
  if (v_mes + interval '1 month')::date > (now() at time zone 'Africa/Luanda')::date + 5 then
    raise exception 'mes_em_curso' using errcode = 'P0001';
  end if;
  if exists (select 1 from rh_folhas where mes = v_mes) then raise exception 'folha_fechada' using errcode = 'P0001'; end if;
  -- Calcula antes de marcar o mês como fechado (depois disso a função lê as linhas gravadas)
  v_calc := coalesce((select jsonb_agg(to_jsonb(t)) from rh_folha_calcular(v_mes) t), '[]'::jsonb);
  insert into rh_folhas (mes, fechada_por) values (v_mes, funcionario_actual());
  insert into rh_folha_linhas (mes, funcionario_id, contrato_id, dias, salario_base, sub_alimentacao, sub_transporte,
                               outros_subsidios, extras, sub_ferias, sub_natal, descontos, bruto, inss_trabalhador,
                               inss_empresa, materia_colectavel, irt, liquido, nota)
  select v_mes, t.funcionario_id, t.contrato_id, t.dias, t.salario_base, t.sub_alimentacao, t.sub_transporte,
         t.outros_subsidios, t.extras, t.sub_ferias, t.sub_natal, t.descontos, t.bruto, t.inss_trabalhador,
         t.inss_empresa, t.materia_colectavel, t.irt, t.liquido, t.nota
    from jsonb_to_recordset(v_calc) as t(funcionario_id uuid, contrato_id uuid, dias int, salario_base int, sub_alimentacao int,
                                         sub_transporte int, outros_subsidios int, extras int, sub_ferias int, sub_natal int,
                                         descontos int, bruto int, inss_trabalhador int, inss_empresa int,
                                         materia_colectavel int, irt int, liquido int, nota text);
  get diagnostics n = row_count;
  perform registar_auditoria('rh_folha_fechada', 'rh_folhas', null, jsonb_build_object('mes', v_mes, 'linhas', n));
  return n;
end $$;
revoke execute on function rh_folha_fechar(date) from public, anon;
grant execute on function rh_folha_fechar(date) to authenticated;

-- Paga o salário líquido de uma linha da folha fechada
create or replace function rh_folha_pagar(p_mes date, p_func uuid, p_metodo text, p_referencia text default null) returns integer
language plpgsql security definer set search_path = public as $$
declare
  l rh_folha_linhas;
begin
  perform rh_exigir('financas.salarios');
  if p_metodo is null or p_metodo not in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if p_metodo <> 'Dinheiro' and length(coalesce(btrim(p_referencia), '')) < 4 then
    raise exception 'referencia_obrigatoria' using errcode = 'P0001';
  end if;
  select * into l from rh_folha_linhas where mes = mes_inicio(p_mes) and funcionario_id = p_func for update;
  if not found then raise exception 'folha_nao_fechada' using errcode = 'P0001'; end if;
  if l.pago_em is not null then raise exception 'ja_pago' using errcode = 'P0001'; end if;
  update rh_folha_linhas set pago_em = now(), metodo = p_metodo, referencia = nullif(btrim(p_referencia), ''),
         pago_por = funcionario_actual()
   where id = l.id;
  perform registar_auditoria('rh_salario_pago', 'funcionarios', p_func,
    jsonb_build_object('mes', l.mes, 'liquido', l.liquido, 'metodo', p_metodo, 'referencia', p_referencia));
  return l.liquido;
end $$;
revoke execute on function rh_folha_pagar(date, uuid, text, text) from public, anon;
grant execute on function rh_folha_pagar(date, uuid, text, text) to authenticated;

-- ------------------------------------------------------------------ custo do pessoal nos resultados
do $$
declare
  v_def  text := pg_get_functiondef('resultados_mes(date)'::regprocedure);
  v_novo text;
begin
  if position('custo_pessoal_mes' in v_def) > 0 then return; end if;
  v_novo := replace(v_def, '''despesas_gerais'', (select coalesce(sum(valor), 0)::int from custos',
                    '''pessoal'', custo_pessoal_mes(v_mes),' || E'\n    ' || '''despesas_gerais'', (select coalesce(sum(valor), 0)::int from custos');
  v_novo := replace(v_novo, '(c ->> ''despesas_gerais'')::int;', '(c ->> ''despesas_gerais'')::int + (c ->> ''pessoal'')::int;');
  if position('custo_pessoal_mes' in v_novo) = 0 or position('(c ->> ''pessoal'')::int;' in v_novo) = 0 then
    raise exception 'resultados_mes não tem o formato esperado';
  end if;
  execute v_novo;
end $$;
