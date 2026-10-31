-- Agendamento do cardápio por data/hora: preparar hoje o prato de amanhã.
-- Cada item do cardápio pode ter uma JANELA de disponibilidade:
--   disponivel_de  — a partir de quando fica visível/pedível (null = já)
--   disponivel_ate — quando expira (null = sem fim)
-- A visibilidade é calculada na leitura (comparação com now()), por isso NÃO precisa de agendador:
-- o prato aparece e desaparece sozinho na hora certa. O interruptor manual `disponivel` continua a
-- ser a chave-mestra (pode sempre forçar esconder); a janela é um acréscimo.

alter table cardapio
  add column disponivel_de  timestamptz,
  add column disponivel_ate timestamptz;

comment on column cardapio.disponivel_de  is 'Agendamento: fica disponível a partir desta data/hora (null = já)';
comment on column cardapio.disponivel_ate is 'Agendamento: expira nesta data/hora (null = sem fim)';

-- Predicado da janela (por linha; usa now(), logo STABLE). Sem gates de sessão: pode ir na política RLS.
create or replace function janela_aberta(p_de timestamptz, p_ate timestamptz)
returns boolean language sql stable set search_path = public as $$
  select (p_de  is null or now() >= p_de)
     and (p_ate is null or now() <  p_ate);
$$;
grant execute on function janela_aberta(timestamptz, timestamptz) to authenticated;

-- Leitura do cardápio: os gestores (cozinhas.gerir) veem tudo, para poderem agendar e gerir;
-- os clientes só veem o que está dentro da janela. (O cliente já filtra `disponivel`/`visivel_online`
-- na sua query; a janela passa a ser imposta pelo servidor, aqui.)
drop policy ler on cardapio;
create policy ler on cardapio for select to authenticated using (
  deletado_em is null
  and ( (select tem_permissao('cozinhas.gerir'))
        or janela_aberta(disponivel_de, disponivel_ate) )
);

-- Leitura "fora da janela?" que fura a RLS (o item fora da janela está escondido ao cliente).
-- SECURITY DEFINER; devolve só um booleano, não expõe dados do prato.
create or replace function cardapio_fora_da_janela(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from cardapio
                  where id = p_id and not janela_aberta(disponivel_de, disponivel_ate));
$$;
revoke execute on function cardapio_fora_da_janela(uuid) from public, anon;
grant  execute on function cardapio_fora_da_janela(uuid) to authenticated;

-- Guarda do pedido: no commit, rejeita qualquer item fora da janela. INVOKER (precisa de ver o
-- cliente em e_escrita_cliente — num DEFINER o current_user seria o dono); a leitura que fura a RLS
-- vai no helper acima. Só se aplica às escritas do cliente, como as outras validações do pedido.
create or replace function pedidos_validar_janela() returns trigger
language plpgsql set search_path = public as $$
declare
  it jsonb;
begin
  if e_escrita_cliente() then
    for it in select * from jsonb_array_elements(coalesce(new.itens, '[]'::jsonb)) loop
      if cardapio_fora_da_janela((it ->> 'cardapio_id')::uuid) then
        raise exception 'item_indisponivel' using errcode = 'P0001', detail = it ->> 'cardapio_id';
      end if;
    end loop;
  end if;
  return new;
end $$;
revoke execute on function pedidos_validar_janela() from public, anon, authenticated;

-- Corre depois do _00_cardapio (que normaliza os itens) e do _01_doses; antes do _05_agendado.
create trigger trg_pedidos_02_janela before insert on pedidos
for each row execute function pedidos_validar_janela();
