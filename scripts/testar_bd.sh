#!/usr/bin/env bash
# Corre as migrações e os testes pgTAP num Postgres local, numa base de dados
# criada de raiz. No Supabase, o equivalente é `supabase test db`.
#
# Requisitos: psql, pg_prove e a extensão pgtap instalados.
# Variáveis: PGHOST, PGPORT, PGUSER (superutilizador) como no psql;
#            BD_TESTE (por defeito mandabue_teste).
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
BD="${BD_TESTE:-mandabue_teste}"

psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "drop database if exists ${BD}"
psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "create database ${BD}"
psql -X -q -v ON_ERROR_STOP=1 -d "${BD}" \
  -c "alter database ${BD} set search_path = \"\$user\", public, extensions"

psql -X -q -v ON_ERROR_STOP=1 -d "${BD}" -f "${RAIZ}/supabase/local/supabase_shim.sql"

for f in "${RAIZ}"/supabase/migrations/*.sql; do
  echo "migração: $(basename "$f")"
  psql -X -q -v ON_ERROR_STOP=1 -d "${BD}" -f "$f" > /dev/null
done

cd "${RAIZ}/supabase/tests"
pg_prove -d "${BD}" --ext .sql ./*.test.sql
