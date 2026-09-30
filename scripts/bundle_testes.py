#!/usr/bin/env python3
"""Gera, para cada teste pgTAP, um script SQL único que corre no SQL editor do
Supabase (ou pela API / MCP execute_sql), sem psql nem pg_prove.

- inclui _helpers.psql no lugar de \\ir;
- retira begin/rollback: o script corre numa transacção implícita;
- guarda cada linha TAP numa tabela temporária;
- termina com uma excepção que devolve o relatório TAP e desfaz TUDO
  (nenhum dado de teste fica na base de dados).

Uso: scripts/bundle_testes.py <pasta_saida>
"""
import pathlib, re, sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
TESTES = RAIZ / "supabase" / "tests"
PGTAP = re.compile(r"^select\s+(\*\s+from\s+finish\(\)|(plan|is|isnt|ok|matches|results_eq|throws_ok|lives_ok|"
                   r"col_not_null|col_type_is|has_table|hasnt_table|has_column)\()", re.I | re.S)


def instrucoes(sql):
    """Divide SQL em instruções, respeitando aspas, dollar-quotes e comentários."""
    out, atual, i, n = [], [], 0, len(sql)
    while i < n:
        c = sql[i]
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            j = n if j < 0 else j
            atual.append(sql[i:j]); i = j
        elif c == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'" and sql[j + 1:j + 2] == "'":
                    j += 2; continue
                if sql[j] == "'":
                    break
                j += 1
            atual.append(sql[i:j + 1]); i = j + 1
        elif c == "$" and (m := re.match(r"\$[A-Za-z_]*\$", sql[i:])):
            tag = m.group(0)
            j = sql.find(tag, i + len(tag))
            atual.append(sql[i:j + len(tag)]); i = j + len(tag)
        elif c == ";":
            out.append("".join(atual).strip()); atual = []; i += 1
        else:
            atual.append(c); i += 1
    if "".join(atual).strip():
        out.append("".join(atual).strip())
    return [s for s in out if re.sub(r"--[^\n]*", "", s).strip()]


def bundle(ficheiro):
    helpers = (TESTES / "_helpers.psql").read_text()
    corpo = ficheiro.read_text().replace("\\ir _helpers.psql", helpers)
    partes = ["create temp table tap_saida (n serial, linha text)",
              "grant all on tap_saida to public",
              "grant all on sequence tap_saida_n_seq to public"]
    for s in instrucoes(corpo):
        limpo = re.sub(r"^(--[^\n]*\n)+", "", s).strip()
        if limpo.lower() in ("begin", "rollback"):
            continue
        if PGTAP.match(limpo):
            limpo = "insert into tap_saida (linha) " + limpo
        partes.append(limpo)
    partes.append("do $fim$ begin raise exception 'TAP %%', E'\\n' || "
                  "(select string_agg(linha, E'\\n' order by n) from tap_saida); end $fim$".replace("%%", "%"))
    return ";\n".join(partes) + ";\n"


if __name__ == "__main__":
    destino = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    destino.mkdir(parents=True, exist_ok=True)
    for f in sorted(TESTES.glob("*.test.sql")):
        (destino / f.name).write_text(bundle(f))
        print(destino / f.name)
