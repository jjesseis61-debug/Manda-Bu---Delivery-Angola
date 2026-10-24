-- Hora de entrega estimada: cada pedido fica com hora_prometida, para o cliente saber quando chega
-- ("Entrega prevista" no ecrã do pedido) e para medir as entregas a horas (relatórios e métricas
-- da equipa, que até aqui não tinham hora com que comparar).
--  * Pedido normal: hora do pedido + parametros.tempo_entrega_min (45 min por defeito).
--  * Pedido de grupo: a hora de entrega do grupo.
-- É sempre o servidor que a define (o valor que o telemóvel mandar é ignorado).

alter table parametros add column tempo_entrega_min integer not null default 45
  check (tempo_entrega_min between 10 and 240);
comment on column parametros.tempo_entrega_min is 'Minutos entre o pedido e a hora de entrega prometida ao cliente';

create or replace function pedidos_hora_prometida() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.grupo_id is not null then
    new.hora_prometida := (select hora_entrega from pedidos_grupo where id = new.grupo_id);
  else
    new.hora_prometida := coalesce(new.criado_em, now())
                          + make_interval(mins => (select tempo_entrega_min from parametros where unico));
  end if;
  return new;
end $$;
revoke execute on function pedidos_hora_prometida() from public, anon, authenticated;

create trigger trg_pedidos_4_hora_prometida before insert on pedidos
for each row execute function pedidos_hora_prometida();
