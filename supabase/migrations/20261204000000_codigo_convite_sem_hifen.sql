-- =============================================================================
-- Código de convite sem hífen: MB-4812 → MB4812 (decisão do dono, 19/11/2026)
-- -----------------------------------------------------------------------------
-- Mais fácil de copiar no WhatsApp (dois toques seleccionam o código inteiro) e de escrever
-- (sem o teclado de símbolos). Feito antes da abertura ao público (só há contas de teste).
--   * normalizar_codigo_convite: aceita MB4812, mb4812, MB-4812, MB 4812 e só 4812 → MB4812
--   * converte os códigos existentes e o gerador passa a criar MB + dígitos
--   * ligar_indicacao, empresa_adicionar_membro e visitante_prato aceitam qualquer forma
-- Os links de teste já partilhados (?r=MB-4812) continuam a funcionar.
-- =============================================================================

create or replace function normalizar_codigo_convite(p text) returns text
language sql immutable set search_path = public as $$
  select case
           when x ~ '^[0-9]{4,5}$' then 'MB' || x
           when x ~ '^MB[0-9]{4,5}$' then x
         end
    from (select regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g') as x) s;
$$;

-- Códigos existentes (só contas de teste): sem hífen
update codigos_indicacao set codigo = replace(codigo, 'MB-', 'MB') where codigo like 'MB-%';

-- Gerador e funções que recebem o código: patch no corpo actual (idempotente)
do $$
declare
  v_def text; v_novo text;
begin
  -- gerar_codigo_indicacao: MB + dígitos
  v_def := pg_get_functiondef('gerar_codigo_indicacao'::regproc);
  v_novo := replace(replace(v_def, '''^MB-[0-9]{''', '''^MB[0-9]{'''), '''MB-'' ||', '''MB'' ||');
  if v_novo <> v_def then execute v_novo; end if;

  -- ligar_indicacao: compara com o código normalizado
  v_def := pg_get_functiondef('ligar_indicacao'::regproc);
  if position('normalizar_codigo_convite' in v_def) = 0 then
    v_novo := regexp_replace(v_def, 'codigo\s*=\s*upper\s*\(\s*trim\s*\(\s*p_codigo\s*\)\s*\)',
                             'codigo = normalizar_codigo_convite(p_codigo)');
    if v_novo = v_def then raise exception 'ligar_indicacao: padrão do código não encontrado'; end if;
    execute v_novo;
  end if;

  -- empresa_adicionar_membro: idem
  v_def := pg_get_functiondef('empresa_adicionar_membro'::regproc);
  if position('normalizar_codigo_convite' in v_def) = 0 then
    v_novo := regexp_replace(v_def, 'upper\s*\(\s*codigo\s*\)\s*=\s*upper\s*\(\s*btrim\s*\(\s*p_codigo\s*\)\s*\)',
                             'codigo = normalizar_codigo_convite(p_codigo)');
    if v_novo = v_def then raise exception 'empresa_adicionar_membro: padrão do código não encontrado'; end if;
    execute v_novo;
  end if;

  -- visitante_prato: o desconto do convite com qualquer forma do código
  v_def := pg_get_functiondef('visitante_prato'::regproc);
  if position('normalizar_codigo_convite' in v_def) = 0 then
    v_novo := regexp_replace(v_def, 'ci\.codigo\s*=\s*upper\s*\(\s*btrim\s*\(\s*p_codigo\s*\)\s*\)',
                             'ci.codigo = normalizar_codigo_convite(p_codigo)');
    if v_novo = v_def then raise exception 'visitante_prato: padrão do código não encontrado'; end if;
    execute v_novo;
  end if;
end $$;

-- Garantia: os códigos ficam sempre no formato novo
alter table codigos_indicacao drop constraint if exists codigos_indicacao_formato;
alter table codigos_indicacao add constraint codigos_indicacao_formato check (codigo ~ '^MB[0-9]{4,5}$');
