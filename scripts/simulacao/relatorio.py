#!/usr/bin/env python3
"""Relatório da simulação: verificações, números do ano, fecho de cada mês, fraude, privacidade,
desempenho com o volume de um ano e filas dos agentes. Escreve JSON e Markdown."""
import json
import pickle
import statistics
import sys
import time
from collections import Counter

import psycopg

from verificar import DSN, correr

ESTADO = '/tmp/claude-0/sim/estado.pkl'


def q(bd, sql, params=None):
    with bd.transaction():
        return bd.execute(sql, params).fetchall()


def como(bd, uid, sql, params=None, papel='authenticated'):
    """Corre uma leitura como o utilizador da app (para privacidade e tempos reais)."""
    with bd.transaction():
        bd.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({'sub': str(uid), 'role': papel}),))
        bd.execute(f'set local role {papel}')
        t = time.perf_counter()
        r = bd.execute(sql, params).fetchall()
        return r, time.perf_counter() - t


def main():
    e = pickle.load(open(ESTADO, 'rb'))
    bd = psycopg.connect(DSN)
    rel = {'verificacoes': correr(bd)}

    # ------------------------------------------------------------------ números do ano
    n = lambda sql, p=None: q(bd, sql, p)[0][0]
    rel['numeros'] = {
        'dias_simulados': len(e['diario']),
        'clientes_registados': n('select count(*) from clientes'),
        'contas_apagadas': n('select count(*) from clientes where deletado_em is not null'),
        'cozinhas': n('select count(*) from cozinhas'),
        'pedidos': n('select count(*) from pedidos'),
        'pedidos_por_estado': dict(q(bd, 'select estado, count(*) from pedidos group by 1 order by 2 desc')),
        'cancelados_por': dict(q(bd, "select coalesce(cancelado_por, '?'), count(*) from pedidos where estado = 'cancelado' group by 1")),
        'faturado_kz': n("select coalesce(sum(valor_total), 0) from vendas where origem like 'App cliente%%'"),
        'pagamentos_por_metodo': {k: int(v) for k, v in q(bd, """select x ->> 'metodo', sum((x ->> 'valor')::numeric) from vendas v, jsonb_array_elements(v.parcelas) x
                                                                where v.origem like 'App cliente%%' group by 1 order by 2 desc""")},
        'pedidos_de_grupo': n('select count(*) from pedidos where grupo_id is not null'),
        'grupos': dict(q(bd, 'select estado, count(*) from pedidos_grupo group by 1')),
        'adesoes_pacote': dict(q(bd, 'select estado, count(*) from adesoes_pacote group by 1')),
        'refeicoes_pacote_usadas': n('select coalesce(sum(refeicoes_pacote), 0) from pedidos where estado <> %s', ('cancelado',)),
        'ligacoes_convida': n('select count(*) from ligacoes_indicacao'),
        'ganhos_por_estado': {f'{k} ({m or "-"})': int(v) for k, m, v in q(bd, """select estado, motivo, count(*) from ganhos_indicacao
                                                                                  group by 1, 2 order by 3 desc""")},
        'ganhos_kz': dict((k, int(v)) for k, v in q(bd, 'select estado, sum(valor) from ganhos_indicacao group by 1')),
        'levantamentos': {f'{k}': [int(c), int(v)] for k, c, v in q(bd, """select estado, count(*), sum(valor) from pagamentos_indicacao
                                                                           where tipo = 'levantamento' group by 1""")},
        'saldo_usado_em_pedidos_kz': n("select coalesce(sum(valor), 0) from pagamentos_indicacao where tipo = 'credito'"),
        'avaliacoes': dict(q(bd, 'select estrelas, count(*) from avaliacoes group by 1 order by 1')),
        'reclamacoes': dict(q(bd, "select case when procedente then 'procedente' when procedente is false then 'nao_procedente' else estado end, count(*) from reclamacoes group by 1")),
        'alertas': dict(q(bd, 'select tipo, count(*) from alertas_pedido group by 1')),
        'caixas_fechadas': n('select count(*) from caixa where fechamento is not null'),
        'diferencas_caixa': [[str(d), float(v)] for d, v in q(bd, """select data, (fechamento ->> 'diferenca')::numeric from caixa
                                                                       where (fechamento ->> 'diferenca')::numeric <> 0 order by data""")],
        'comprovativos': dict(q(bd, 'select estado, count(*) from comprovativos_pagamento group by 1')),
        'notificacoes': {k: [int(t), int(s), int(d)] for k, t, s, d in q(bd, """
            select codigo, count(*), count(enviada_em), count(*) filter (where deletado_em is not null and enviada_em is null)
              from notificacoes_fila group by 1 order by 1""")},
        'stock_movimentos': dict(q(bd, 'select tipo, count(*) from estoque_longo_prazo group by 1')),
        'linhas_auditoria': n('select count(*) from auditoria'),
        'tamanho_bd_mb': n("select round(pg_database_size('sim') / 1048576.0)"),
    }

    # ------------------------------------------------------------------ fecho de cada mês = vendas do mês
    meses = []
    for m in e['mensal']:
        f = m['fecho']
        ano, mes = f['ano'], f['mes']
        vendas = n("""select coalesce(sum(valor_total), 0) from vendas
                       where origem like 'App cliente%%' and (data at time zone 'Africa/Luanda')::date between %s and %s""",
                   (f['inicio'], f['fim']))
        pedidos = n("""select count(*) from pedidos where estado in ('entregue_pago', 'estornado')
                        and (entregue_em at time zone 'Africa/Luanda')::date between %s and %s""", (f['inicio'], f['fim']))
        injectado = sum(v for k, v in e['injectados']['diferencas_caixa'].items()
                        if q(bd, 'select data between %s and %s from caixa where id = %s', (f['inicio'], f['fim'], k))[0][0])
        meses.append({'mes': m['mes'], 'pedidos_fecho': f['totais']['pedidos'], 'pedidos_bd': pedidos,
                      'vendido_fecho': f['totais']['vendido'], 'vendas_bd': int(vendas),
                      'diferenca_caixas_fecho': f['totais']['diferenca_caixas'], 'diferenca_injectada': injectado,
                      'caixas_por_fechar': f['totais']['caixas_por_fechar'], 'segundos': m['segundos'],
                      'ok': abs(f['totais']['vendido'] - vendas) < 1 and abs(f['totais']['diferenca_caixas'] - injectado) < 1})
    rel['meses'] = meses

    # ------------------------------------------------------------------ fraude montada
    fr = e['injectados']['fraude']
    if fr:
        f = fr[0]
        rel['fraude'] = {
            'ganhos_das_contas_falsas': dict(q(bd, """select estado || ' (' || coalesce(motivo, '-') || ')', count(*) from ganhos_indicacao
                                                        where indicador_id = %s and indicado_id in (select indicado_id from ligacoes_indicacao
                                                          where indicador_id = %s and criado_em::date = (select min(criado_em)::date from ligacoes_indicacao l2
                                                            where l2.indicador_id = %s and l2.criado_em > now() - interval '400 days'
                                                              and l2.indicado_id in (select id from clientes where criado_em >= %s::date)))
                                                        group by 1""", (f, f, f, '2027-02-02'))),
            'levantamentos_do_fraudador': dict(q(bd, "select estado, count(*) from pagamentos_indicacao where indicador_id = %s and tipo = 'levantamento' group by 1", (f,))),
            'casos_vigilancia': n('select count(*) from casos_convida where indicador_id = %s', (f,)),
            'saldo_final': n('select saldo_disponivel_de(%s)', (f,)),
        }

    # ------------------------------------------------------------------ privacidade (como a app)
    clientes = q(bd, 'select id, auth_user_id from clientes where deletado_em is null and auth_user_id is not null order by random() limit 30')
    falhas = 0
    for cid, uid in clientes:
        r, _ = como(bd, uid, 'select count(*) filter (where cliente_id <> %s), count(*) from pedidos', (cid,))
        r2, _ = como(bd, uid, 'select count(*) from ganhos_indicacao where indicador_id <> %s and indicado_id <> %s', (cid, cid))
        r3, _ = como(bd, uid, 'select count(*) from avaliacoes where cliente_id <> %s', (cid,))
        r4, _ = como(bd, uid, 'select count(*) from comprovativos_pagamento')
        if r[0][0] or r2[0][0] or r3[0][0] or r4[0][0]:
            falhas += 1
    rel['privacidade'] = {'clientes_testados': len(clientes), 'viram_dados_de_outros': falhas}

    # ------------------------------------------------------------------ desempenho com o volume de um ano
    adm_uid = q(bd, 'select f.auth_user_id from funcionarios f join direcoes d on d.id = f.direcao_id order by jsonb_object_length(d.permissoes) desc limit 1')[0][0]
    ger = q(bd, "select f.auth_user_id, t.cozinha_id from funcionarios f join turnos t on t.funcionario_id = f.id where f.nome like 'Gerente%%' limit 1")[0]
    cli = q(bd, 'select auth_user_id from clientes c where deletado_em is null order by (select count(*) from pedidos p where p.cliente_id = c.id) desc limit 1')[0][0]
    testes = [
        ('pedidos_operador (gerente)', ger[0], 'select count(*) from pedidos_operador()', None),
        ('relatorio_cozinha do ano (gerente)', ger[0], "select relatorio_cozinha(%s, (now() - interval '365 days')::date, now()::date)", (ger[1],)),
        ('relatorio_comparativo do ano', adm_uid, "select count(*) from relatorio_comparativo((now() - interval '365 days')::date, now()::date)", None),
        ('painel_programa do ano', adm_uid, "select painel_programa((now() - interval '365 days')::date, now()::date)", None),
        ('fecho_mensal', adm_uid, 'select fecho_mensal(extract(year from now())::int, extract(month from now())::int)', None),
        ('fecho_diario', adm_uid, 'select fecho_diario((now() - interval \'1 day\')::date, null)', None),
        ('destaques_mes (cliente)', cli, 'select count(*) from destaques_mes()', None),
        ('meus pedidos (cliente com mais pedidos)', cli, 'select count(*) from pedidos', None),
        ('orcamento_pedido (cliente)', cli, """select orcamento_pedido((select jsonb_build_array(jsonb_build_object('cardapio_id', id, 'qtd', 1)) from cardapio
                                              where nome = 'Muamba de galinha' and cozinha_id = cozinha_padrao()),
                                             (select ponto_entrega_id from enderecos_cliente where cliente_id = cliente_actual() limit 1))""", None),
        ('analista_vendas do ano', adm_uid, "select analista_vendas((now() - interval '365 days')::date, now()::date, 'mes')", None),
        ('alertas_abertos (gerente)', ger[0], 'select count(*) from alertas_abertos()', None),
    ]
    desempenho = []
    for nome, uid, sql, params in testes:
        try:
            tempos = []
            for _ in range(3):
                _, t = como(bd, uid, sql, params)
                tempos.append(t)
            desempenho.append({'consulta': nome, 'ms': round(statistics.median(tempos) * 1000, 1)})
        except psycopg.Error as ex:
            desempenho.append({'consulta': nome, 'erro': str(ex).strip()[:200]})
    rel['desempenho'] = desempenho
    rel['tempos_accoes'] = {k: {'vezes': v[0], 'media_ms': round(v[1] * 1000, 1), 'max_ms': round(v[2] * 1000, 1)}
                            for k, v in sorted(e['tempos'].items(), key=lambda kv: -kv[1][1])[:20]}

    # ------------------------------------------------------------------ agentes (Claude não é chamado na simulação)
    rel['agentes'] = {
        'estimulos_mensais': n('select count(*) from estimulos_mensais'),
        'casos_investigacao': n('select count(*) from casos_investigacao'),
        'casos_convida': n('select count(*) from casos_convida'),
        'planos_compras': n('select count(*) from planos_compras'),
        'relatorios_analista': n('select count(*) from perguntas_analista'),
        'reclamacoes_por_analisar_ia': n("select count(*) from reclamacoes where ia_estado = 'pendente'"),
    }
    rel['falhas'] = e['inesperados']
    rel['erros_de_negocio'] = e['esperados']
    rel['accoes'] = e['accoes']
    rel['eventos'] = e['eventos']
    rel['diario'] = e['diario']
    json.dump(rel, open('/tmp/claude-0/sim/relatorio.json', 'w'), ensure_ascii=False, indent=1, default=str)
    print(json.dumps({k: rel[k] for k in ('numeros', 'meses', 'privacidade', 'desempenho', 'agentes')}, ensure_ascii=False, indent=1, default=str)[:12000])
    print('VERIFICACOES:', sum(r['ok'] for r in rel['verificacoes']), '/', len(rel['verificacoes']))
    for r in rel['verificacoes']:
        if not r['ok']:
            print('  FALHA', r['nome'], r['problemas'], r['exemplos'][:3])
    print('FALHAS INESPERADAS:', len(e['inesperados']))
    for k, v in Counter((x['accao'], x['mensagem'][:160]) for x in e['inesperados']).most_common(20):
        print(' ', v, k)


if __name__ == '__main__':
    main()
