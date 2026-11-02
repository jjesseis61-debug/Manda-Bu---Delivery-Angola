-- Scoping das notificações por app/função.
-- Antes: todos os tokens de funcionário (operador + estafeta) recebiam TODAS as notificações de
-- funcionário. Uma pessoa com as duas apps via tudo em dobro e trocado (o estafeta recebia "novo
-- pedido" da cozinha; o operador recebia "nova entrega"). Agora cada token sabe de que app é, e
-- cada código de notificação só vai às apps a que diz respeito.
--
-- Mudança mínima: o operador e o cliente não precisam de mudar (o default trata deles). Só a app
-- do estafeta passa a registar o token com app='estafeta' (precisa de um APK novo para isso valer).

-- 1) De que app veio o token.
alter table dispositivos_push add column if not exists app text;

-- Backfill do que já existe: historicamente os tokens de funcionário eram todos do operador.
update dispositivos_push
   set app = case when funcionario_id is not null then 'operador'
                  when cliente_id   is not null then 'cliente' end
 where app is null;

alter table dispositivos_push drop constraint if exists dispositivos_push_app_chk;
alter table dispositivos_push add constraint dispositivos_push_app_chk
  check (app is null or app in ('cliente', 'operador', 'estafeta'));

-- 2) A que apps se destina cada código. Por omissão vai só ao operador (mantém todo o
--    comportamento actual da gestão/cozinha). Só as notificações de entrega chegam ao estafeta.
create or replace function apps_do_codigo(p_codigo text) returns text[]
language sql immutable set search_path = public as $$
  select case p_codigo
           when 'N32' then array['estafeta']              -- entrega atribuída ao estafeta
           when 'N19' then array['operador', 'estafeta']  -- pedido atrasado: gerente + estafeta que o leva
           else            array['operador']
         end;
$$;

-- 3) Registo de token do funcionário: passa a gravar a app. Default 'operador' (o operador não
--    muda); a app do estafeta passa 'estafeta'. (O cliente usa outra função; não precisa de mudar,
--    porque as notificações de cliente não são filtradas por app.)
drop function if exists registar_token_push_funcionario(text, text);
create or replace function registar_token_push_funcionario(p_token text, p_plataforma text, p_app text default 'operador')
returns void language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := funcionario_actual();
begin
  if v_func is null then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_token is null or p_token !~ '^(ExponentPushToken|ExpoPushToken)\[[^\]]+\]$' then
    raise exception 'token_invalido' using errcode = 'P0001';
  end if;
  if coalesce(p_app, 'operador') not in ('operador', 'estafeta') then
    raise exception 'app_invalida' using errcode = 'P0001';
  end if;
  insert into dispositivos_push (funcionario_id, token, plataforma, activo, dispositivo_id, app)
  values (v_func, p_token, p_plataforma, true, 'servidor', coalesce(p_app, 'operador'))
  on conflict (token) do update
    set funcionario_id = excluded.funcionario_id, cliente_id = null, plataforma = excluded.plataforma,
        activo = true, atualizado_em = now(), deletado_em = null, app = excluded.app;
end $$;

-- 4) Envio: igual ao anterior, mas para notificações de FUNCIONÁRIO só junta os tokens cuja app
--    corresponde ao código. As de cliente ficam exactamente como estavam.
create or replace function notificacoes_por_enviar(p_limite integer default 100)
 returns table(id uuid, cliente_id uuid, funcionario_id uuid, destino text, codigo text,
               titulo text, corpo text, dados jsonb, tokens text[])
 language sql stable security definer set search_path = public as $function$
  select n.id, n.cliente_id, n.funcionario_id,
         case when n.funcionario_id is not null then 'funcionario' else 'cliente' end,
         n.codigo, t.titulo, t.corpo, n.dados,
         coalesce((select array_agg(d.token order by d.atualizado_em desc) from dispositivos_push d
                    where d.activo and d.deletado_em is null
                      and (d.cliente_id = n.cliente_id or d.funcionario_id = n.funcionario_id)
                      and (n.funcionario_id is null
                           or coalesce(d.app, 'operador') = any(apps_do_codigo(n.codigo)))), '{}')
    from notificacoes_fila n
    cross join lateral texto_notificacao(n.codigo, n.dados) t
    left join preferencias_notificacao pn on pn.cliente_id = n.cliente_id and pn.deletado_em is null
   where n.enviada_em is null and n.deletado_em is null
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N10', 'N11', 'N12', 'N13',
                      'N14', 'N15', 'N16', 'N17', 'N18', 'N19', 'N20', 'N21', 'N22', 'N23', 'N24',
                      'N25', 'N26', 'N27', 'N28', 'N29', 'N30', 'N31', 'N32', 'N40')
     and notificacao_valida(n.codigo, n.criado_em)
     and (funcionalidade_da_notificacao(n.codigo) is null or funcionalidade_activa(funcionalidade_da_notificacao(n.codigo)))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
     and not (n.codigo = 'N9' and exists (select 1 from avaliacoes a where a.pedido_id::text = n.dados ->> 'pedido_id'))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$function$;
