-- =============================================================================
-- Convida e Ganha: sem comissão no 1.º pedido do convidado + aparelhos por conta
-- -----------------------------------------------------------------------------
-- Decisão do dono do produto (11/11/2026):
--  1. O 1.º pedido do convidado já leva o desconto de boas-vindas (1.000 Kz em pedidos de
--     5.000 Kz ou mais). Para proteger a margem desse pedido, NÃO gera comissão a quem
--     convidou; as comissões começam no 2.º pedido. Fica num parâmetro
--     (parametros.comissao_primeiro_pedido, desligado) para se poder voltar atrás.
--  2. Limite de contas por telemóvel, versão leve: NÃO se bloqueia nem se corta nada a
--     ninguém (famílias partilham telemóveis). Regista-se em que aparelhos cada conta entra
--     e a vigilância vê os aparelhos com muitas contas (parametros.alerta_contas_por_aparelho).
--     Todos os benefícios do Convida exigem pedidos reais e pagos, por isso o risco é de
--     margem, não de dinheiro perdido.
-- =============================================================================

alter table parametros
  add column if not exists comissao_primeiro_pedido boolean not null default false,
  add column if not exists alerta_contas_por_aparelho int not null default 3
    check (alerta_contas_por_aparelho between 2 and 50);
comment on column parametros.comissao_primeiro_pedido is
  'Gera comissão no 1.º pedido do convidado (o do desconto de boas-vindas)? Por defeito não.';
comment on column parametros.alerta_contas_por_aparelho is
  'A partir de quantas contas no mesmo aparelho a vigilância o mostra (sem bloquear ninguém)';

-- -----------------------------------------------------------------------------
-- 1. Sem comissão no 1.º pedido (acrescenta-se a regra à função actual, sem a copiar)
-- -----------------------------------------------------------------------------
do $$
declare
  v_def  text := pg_get_functiondef('processar_ganho_indicacao()'::regprocedure);
  v_novo text;
begin
  if position('comissao_primeiro_pedido' in v_def) > 0 then return; end if; -- já aplicado
  -- Procura-se o bloco sem depender de espaços/quebras de linha (o texto colado no SQL Editor
  -- pelo telemóvel pode alterá-los); insere-se a regra numa só linha logo a seguir.
  v_novo := regexp_replace(v_def,
    '(if exists \(select 1 from ganhos_indicacao where pedido_id = new\.id\) then\s+return new;\s+end if;)',
    E'\\1\n  if lig.primeiro_pedido_id = new.id and not p.comissao_primeiro_pedido then return new; end if; -- 1.º pedido: sem comissão');
  if v_novo = v_def then
    raise exception 'processar_ganho_indicacao não tem o formato esperado';
  end if;
  execute v_novo;

  -- Aviso N2 ("entrou com o teu código"): diz que as comissões começam no 2.º pedido
  v_def := pg_get_functiondef('texto_notificacao(text, jsonb)'::regprocedure);
  v_novo := replace(v_def,
    $s$'%s entrou com o teu código! Ganhas %s em cada pedido durante %s dias.'$s$,
    $s$'%s entrou com o teu código! Ganhas %s em cada pedido a partir do 2.º, durante %s dias.'$s$);
  if v_novo = v_def and position('a partir do 2.º' in v_def) = 0 then
    raise exception 'texto_notificacao (N2) não tem o formato esperado';
  end if;
  if v_novo <> v_def then execute v_novo; end if;
end $$;

-- -----------------------------------------------------------------------------
-- 2. Aparelhos em que cada conta entra
-- -----------------------------------------------------------------------------
create table if not exists aparelhos_conta (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references clientes(id) on delete cascade,
  -- Id da instalação da app (ou do navegador, na versão web): muda ao reinstalar
  instalacao_id text not null check (length(instalacao_id) between 8 and 100),
  -- Id do aparelho (Android ID / iOS identifierForVendor): sobrevive a reinstalar. null na web
  aparelho_id   text check (aparelho_id is null or length(aparelho_id) between 4 and 100),
  plataforma    text not null check (plataforma in ('android', 'ios', 'web')),
  modelo        text check (modelo is null or length(modelo) <= 80),
  primeiro_em   timestamptz not null default now(),
  ultimo_em     timestamptz not null default now(),
  unique (cliente_id, instalacao_id)
);
create index if not exists aparelhos_conta_aparelho_idx on aparelhos_conta (aparelho_id) where aparelho_id is not null;
create index if not exists aparelhos_conta_instalacao_idx on aparelhos_conta (instalacao_id);
alter table aparelhos_conta enable row level security;
-- Sem políticas: só se lê e escreve pelas funções abaixo
comment on table aparelhos_conta is 'Aparelhos em que cada conta de cliente entrou (só antifraude do Convida)';

-- A app chama ao entrar e ao abrir: regista ou actualiza o aparelho desta conta
create or replace function registar_aparelho(p_instalacao text, p_aparelho text, p_plataforma text,
                                             p_modelo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
begin
  if v_cliente is null then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_instalacao is null or length(p_instalacao) not between 8 and 100
     or p_plataforma not in ('android', 'ios', 'web')
     or (p_aparelho is not null and length(p_aparelho) not between 4 and 100) then
    raise exception 'parametro_invalido' using errcode = 'P0001';
  end if;
  insert into aparelhos_conta (cliente_id, instalacao_id, aparelho_id, plataforma, modelo)
  values (v_cliente, p_instalacao, nullif(trim(p_aparelho), ''), p_plataforma, left(nullif(trim(p_modelo), ''), 80))
  on conflict (cliente_id, instalacao_id) do update
    set ultimo_em = now(),
        aparelho_id = coalesce(excluded.aparelho_id, aparelhos_conta.aparelho_id),
        modelo = coalesce(excluded.modelo, aparelhos_conta.modelo);
end $$;
revoke execute on function registar_aparelho(text, text, text, text) from public, anon;
grant  execute on function registar_aparelho(text, text, text, text) to authenticated;

-- Vigilância: aparelhos com N ou mais contas (pelo id do aparelho; na web, pelo do navegador)
create or replace function aparelhos_partilhados()
returns table(chave text, plataforma text, modelo text, contas int, ultimo_em timestamptz, clientes jsonb)
language plpgsql stable security definer set search_path = public as $$
declare
  v_min int := (select alerta_contas_por_aparelho from parametros where unico);
begin
  perform exigir_permissao('indicacoes.verificar');
  return query
  with a as (
    select coalesce(ac.aparelho_id, 'web:' || ac.instalacao_id) as k, ac.*
      from aparelhos_conta ac)
  select a.k, max(a.plataforma), max(a.modelo), count(distinct a.cliente_id)::int, max(a.ultimo_em),
         jsonb_agg(distinct jsonb_build_object(
           'cliente_id', c.id, 'nome', c.nome, 'telefone', c.telefone,
           'convidado_por', (select ci.nome from ligacoes_indicacao l join clientes ci on ci.id = l.indicador_id
                              where l.indicado_id = c.id and l.deletado_em is null limit 1),
           'pedidos', (select count(*) from pedidos p where p.cliente_id = c.id and p.estado = 'entregue_pago'
                        and p.deletado_em is null)))
    from a join clientes c on c.id = a.cliente_id
   group by a.k
  having count(distinct a.cliente_id) >= v_min
   order by count(distinct a.cliente_id) desc, max(a.ultimo_em) desc
   limit 200;
end $$;
revoke execute on function aparelhos_partilhados() from public, anon;
grant  execute on function aparelhos_partilhados() to authenticated;
