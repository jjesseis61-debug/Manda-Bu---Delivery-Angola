#!/usr/bin/env python3
"""Verificações no fim da simulação: o dinheiro, o stock, os pacotes, o Convida e Ganha e as
notificações batem certo depois de 12 meses? Cada verificação devolve (ok, detalhe)."""
import json
import pickle
import sys
import time

import psycopg

DSN = 'dbname=sim port=5433 host=/var/run/postgresql user=root'

# Cada verificação: nome, SQL que devolve as linhas com PROBLEMAS (vazio = certo), explicação
VERIFICACOES = [
    ('Cada pedido entregue tem as vendas certas',
     """select p.id, p.subtotal + p.taxa_entrega - p.desconto_indicacao as final, coalesce(sum(v.valor_total), 0) as vendas
          from pedidos p left join vendas v on v.pedido_id = p.id and v.origem = 'App cliente' and v.deletado_em is null
         where p.estado in ('entregue_pago', 'estornado') and p.deletado_em is null
         group by p.id having p.subtotal + p.taxa_entrega - p.desconto_indicacao <> coalesce(sum(v.valor_total), 0)""",
     'Soma das linhas de venda = valor final do pedido (subtotal + taxa − desconto).'),
    ('Pagamentos de cada pedido somam o valor final',
     """select id from pedidos p
         where estado in ('entregue_pago', 'estornado')
           and (select coalesce(sum((x ->> 'valor')::numeric), 0) from jsonb_array_elements(p.parcelas) x)
               + credito_indicacao_usado + pago_pacote <> subtotal + taxa_entrega - desconto_indicacao""",
     'Dinheiro/electrónico + saldo + pacote = valor final.'),
    ('Estornos compensam as vendas',
     """select p.id from pedidos p where p.estado = 'estornado'
           and (select coalesce(sum(valor_total), 0) from vendas v where v.pedido_id = p.id) <> 0""",
     'Venda original + estorno = 0.'),
    ('Pedidos não entregues não geram vendas',
     """select p.id from pedidos p join vendas v on v.pedido_id = p.id where p.estado in ('cancelado', 'pendente', 'confirmado', 'em_preparacao', 'em_entrega')""",
     'Só há venda depois de entregue e pago.'),
    ('Nenhum pedido ficou a meio',
     """select id, estado, criado_em from pedidos where estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
          and criado_em < now() - interval '1 day'""",
     'Todos os pedidos de dias anteriores acabaram entregues, cancelados ou estornados.'),
    ('Todas as caixas fechadas e com o esperado certo',
     """select c.id, c.data, c.fechamento ->> 'esperado' as esperado,
               coalesce(c.troco_inicial, 0)
               + (select coalesce(sum((x ->> 'valor')::numeric), 0) from vendas v, jsonb_array_elements(v.parcelas) x
                   where v.caixa_id = c.id and v.deletado_em is null and x ->> 'metodo' = 'Dinheiro')
               + (select coalesce(sum(preco), 0) from adesoes_pacote a where a.caixa_id = c.id and a.metodo = 'loja'
                   and a.estado in ('activa', 'reembolsada', 'terminada', 'esgotada'))
               - (select coalesce(sum((s ->> 'valor')::numeric), 0) from jsonb_array_elements(c.sangrias) s) as recalculado
          from caixa c
         where c.deletado_em is null and c.posto = 'Balcão'
           and (c.fechamento is null and c.data < (now() at time zone 'Africa/Luanda')::date
                or (c.fechamento ->> 'esperado')::numeric <> coalesce(c.troco_inicial, 0)
               + (select coalesce(sum((x ->> 'valor')::numeric), 0) from vendas v, jsonb_array_elements(v.parcelas) x
                   where v.caixa_id = c.id and v.deletado_em is null and x ->> 'metodo' = 'Dinheiro')
               + (select coalesce(sum(preco), 0) from adesoes_pacote a where a.caixa_id = c.id and a.metodo = 'loja'
                   and a.estado in ('activa', 'reembolsada', 'terminada', 'esgotada'))
               - (select coalesce(sum((s ->> 'valor')::numeric), 0) from jsonb_array_elements(c.sangrias) s))""",
     'Esperado = troco + dinheiro das vendas (incluindo estornos) + pacotes pagos na loja − sangrias.'),
    ('Comprovativos: um por pagamento electrónico, todos conferidos',
     """select p.id from pedidos p, jsonb_array_elements(p.parcelas) x
         where p.estado in ('entregue_pago', 'estornado') and x ->> 'metodo' <> 'Dinheiro'
           and not exists (select 1 from comprovativos_pagamento k where k.pedido_id = p.id
                             and k.referencia = x ->> 'referencia' and k.estado in ('conferido', 'rejeitado'))""",
     'Cada parcela electrónica tem o seu comprovativo, conferido (ou rejeitado) antes do fecho.'),
    ('Saldo do Convida e Ganha nunca negativo',
     """select c.id, saldo_disponivel_de(c.id) from clientes c where saldo_disponivel_de(c.id) < 0""",
     'Ganhos confirmados − levantamentos − saldo usado ≥ 0 para todos.'),
    ('Ganhos só dentro do período garantido e com o valor garantido',
     """select g.id from ganhos_indicacao g join ligacoes_indicacao l on l.indicado_id = g.indicado_id
          join pedidos p on p.id = g.pedido_id
         where g.valor <> l.ganho_por_pedido_garantido or p.entregue_em > l.expira_em
            or l.indicador_id <> g.indicador_id""",
     'Valor = o garantido na ligação (mesmo depois de mudar o parâmetro); nada depois do fim do período.'),
    ('Pedidos de indicados no período têm ganho',
     """select p.id from pedidos p join ligacoes_indicacao l on l.indicado_id = p.cliente_id
         where p.estado = 'entregue_pago' and p.entregue_em <= l.expira_em
           and not exists (select 1 from ganhos_indicacao g where g.pedido_id = p.id)""",
     'Cada pedido pago de um amigo, dentro do período, gera um ganho (confirmado, em verificação ou anulado).'),
    ('Estornos anulam o ganho do pedido',
     """select g.id from ganhos_indicacao g join pedidos p on p.id = g.pedido_id
         where p.estado = 'estornado' and g.estado in ('confirmado', 'em_verificacao')""",
     'Um pedido estornado não deixa ganho por pagar.'),
    ('Desconto do amigo só no primeiro pedido',
     """select l.indicado_id, count(*) from pedidos p join ligacoes_indicacao l on l.indicado_id = p.cliente_id
         where p.desconto_indicacao > 0 and p.estado <> 'cancelado' group by l.indicado_id having count(*) > 1""",
     'Cada amigo convidado recebe o desconto uma só vez.'),
    ('Levantamentos pagos não excedem os ganhos',
     """select indicador_id from pagamentos_indicacao where estado in ('pedido', 'aprovado', 'pago')
         group by indicador_id
        having sum(valor) > (select coalesce(sum(valor), 0) from ganhos_indicacao g
                              where g.indicador_id = pagamentos_indicacao.indicador_id and g.estado in ('confirmado', 'pago'))""",
     'Ninguém levantou ou gastou mais do que ganhou.'),
    ('Refeições do pacote batem com os pedidos',
     """select a.id, a.refeicoes_usadas,
               (select coalesce(sum(refeicoes_pacote), 0) from pedidos p where p.adesao_pacote_id = a.id and p.estado <> 'cancelado') as nos_pedidos
          from adesoes_pacote a
         where a.refeicoes_usadas <> (select coalesce(sum(refeicoes_pacote), 0) from pedidos p
                                        where p.adesao_pacote_id = a.id and p.estado <> 'cancelado')
            or a.refeicoes_usadas > a.refeicoes + a.refeicoes_oferta""",
     'Usadas = soma das refeições nos pedidos não cancelados (os cancelados devolvem); nunca acima do total.'),
    ('Stock: cada venda com receita descontou os ingredientes uma vez',
     """select v.id from vendas v
         where v.origem = 'App cliente' and v.prato_base_id is not null and v.qtd > 0
           and not exists (select 1 from estoque_longo_prazo e where e.venda_id = v.id and e.tipo = 'Consumo')""",
     'Consumo registado para cada venda de prato com receita.'),
    ('Stock: ingredientes tirados não foram descontados',
     """select v.id from vendas v, jsonb_array_elements_text(v.componentes_excluidos) x
          join estoque_longo_prazo e on e.produto_id = x::uuid
         where e.venda_id = v.id""",
     'O que o cliente tirou do prato não sai do stock.'),
    ('Stock: nenhum consumo repetido',
     """select venda_id, produto_id from estoque_longo_prazo where venda_id is not null group by 1, 2 having count(*) > 1""",
     'Nunca desconta duas vezes o mesmo produto da mesma venda.'),
    ('Notificações: todas têm texto',
     """select codigo, count(*) from notificacoes_fila n
         where (texto_notificacao(n.codigo, n.dados)).corpo is null group by codigo""",
     'Cada notificação gerada tem título e corpo.'),
    ('Notificações: nenhuma pendente esquecida',
     """select codigo, count(*) from notificacoes_fila where enviada_em is null and deletado_em is null
           and criado_em < now() - interval '2 days' group by codigo""",
     'As antigas foram enviadas ou descartadas por validade.'),
    ('Grupos: a taxa dividida soma a taxa da zona',
     """select g.id from pedidos_grupo g join pontos_entrega pe on pe.id = g.ponto_entrega_id join zonas z on z.id = pe.zona_id
         where g.estado <> 'cancelado' and g.estado <> 'aberto'
           and (select coalesce(sum(taxa_entrega), 0) from pedidos p where p.grupo_id = g.id and p.estado <> 'cancelado') <> round(z.taxa)
           and exists (select 1 from pedidos p where p.grupo_id = g.id and p.estado <> 'cancelado')""",
     'Os colegas dividem a taxa de entrega e a soma é a taxa da zona.'),
    ('Grupos: nenhum ficou aberto',
     """select id from pedidos_grupo where estado = 'aberto' and prazo_adesao < now()""",
     'Todos os grupos fecham no prazo (tarefa job_grupos).'),
    ('Doses do dia nunca abaixo de zero',
     """select c.id, c.nome, c.doses_dia, (select coalesce(sum((i ->> 'qtd')::int), 0) from pedidos p, jsonb_array_elements(p.itens) i
             where i ->> 'cardapio_id' = c.id::text and p.estado <> 'cancelado' and p.criado_em >= c.doses_definidas_em
               and (p.criado_em at time zone 'Africa/Luanda')::date = (c.doses_definidas_em at time zone 'Africa/Luanda')::date) as pedidas
          from cardapio c where c.doses_dia is not null
           and c.doses_dia < (select coalesce(sum((i ->> 'qtd')::int), 0) from pedidos p, jsonb_array_elements(p.itens) i
             where i ->> 'cardapio_id' = c.id::text and p.estado <> 'cancelado' and p.criado_em >= c.doses_definidas_em
               and (p.criado_em at time zone 'Africa/Luanda')::date = (c.doses_definidas_em at time zone 'Africa/Luanda')::date)""",
     'Nunca se vendeu mais do que as doses lançadas no dia.'),
    ('Cancelamentos com justificação certa',
     """select id from pedidos where estado = 'cancelado' and (cancelado_por is null or justificacao_cancelamento(id) is null)""",
     'Cada cancelamento regista quem cancelou e tem a justificação para o cliente.'),
    ('Contas apagadas ficaram anónimas',
     """select id from clientes where deletado_em is not null and (nome !~ '^Cliente removido' and nome is not null and telefone is not null)""",
     'Sem nome nem telefone depois de apagar a conta (os pedidos e as vendas ficam).'),
    ('Reclamações das avaliações baixas',
     """select a.id from avaliacoes a where a.estrelas <= 2 and not exists (select 1 from reclamacoes r where r.pedido_id = a.pedido_id)""",
     'Cada avaliação de 1 ou 2 estrelas abre uma reclamação.'),
    ('Todas as reclamações decididas',
     """select id from reclamacoes where estado = 'aberta' and criado_em < now() - interval '2 days'""",
     'O gerente respondeu a todas.'),
]


def correr(bd):
    resultados = []
    for nome, sql, explicacao in VERIFICACOES:
        t = time.perf_counter()
        try:
            with bd.transaction():
                linhas = bd.execute(sql).fetchall()
            ok = not linhas
            resultados.append({'nome': nome, 'ok': ok, 'problemas': len(linhas), 'exemplos': [list(map(str, l)) for l in linhas[:5]],
                               'explicacao': explicacao, 'segundos': round(time.perf_counter() - t, 2)})
        except psycopg.Error as e:
            resultados.append({'nome': nome, 'ok': False, 'problemas': -1, 'exemplos': [str(e).strip()[:300]],
                               'explicacao': explicacao, 'segundos': round(time.perf_counter() - t, 2)})
    return resultados


if __name__ == '__main__':
    with psycopg.connect(DSN) as bd:
        for r in correr(bd):
            print(('OK   ' if r['ok'] else 'FALHA'), r['nome'], '' if r['ok'] else r['problemas'], r['exemplos'][:2] if not r['ok'] else '')
