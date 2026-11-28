-- Interruptor próprio para as campanhas (promoções): deixam de depender dos condomínios.
-- As campanhas para todos, por zona ou por cozinha funcionam só com «campanhas»; as de um
-- condomínio precisam também de «condominios». Quem já tinha os condomínios ligados fica com
-- as campanhas ligadas (nada muda).
insert into funcionalidades (chave, activa, dispositivo_id)
values ('campanhas', coalesce((select activa from funcionalidades where chave = 'condominios'), false), 'servidor')
on conflict (chave) do nothing;

do $$
declare
  f    text;
  v_def text;
  v_novo text;
begin
  foreach f in array array['aplicar_campanha(jsonb,uuid,uuid,uuid,uuid)', 'campanhas_para_mim(uuid)'] loop
    v_def := pg_get_functiondef(f::regprocedure);
    v_novo := replace(v_def, 'funcionalidade_activa(''condominios'')', 'funcionalidade_activa(''campanhas'')');
    if v_novo = v_def and position('funcionalidade_activa(''campanhas'')' in v_def) = 0 then
      raise exception '% não tem o formato esperado', f;
    end if;
    execute v_novo;
  end loop;

  -- Campanha de um condomínio: só com os condomínios ligados
  v_def := pg_get_functiondef('campanha_vale(campanhas,uuid,uuid,uuid,uuid,integer,timestamptz)'::regprocedure);
  if position('funcionalidade_activa(''condominios'')' in v_def) = 0 then
    v_novo := regexp_replace(v_def, '(\n\s*if k\.condominio_id is not null then)',
      E'\n  if k.condominio_id is not null and not funcionalidade_activa(''condominios'') then return false; end if;\\1');
    if v_novo = v_def then raise exception 'campanha_vale não tem o formato esperado'; end if;
    execute v_novo;
  end if;
end $$;
