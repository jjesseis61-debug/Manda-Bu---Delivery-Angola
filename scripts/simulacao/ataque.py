#!/usr/bin/env python3
"""Teste de segurança: um atacante tenta furar a aplicação, contra a base LOCAL de simulação.

Corre cada tentativa com o papel e a sessão que o atacante teria (anónimo, cliente ou
funcionário), exactamente como passaria pela API da Supabase (PostgREST + RLS). Para cada uma
diz se foi TRAVADA (como deve) ou se PASSOU (falha de segurança).

Nunca toca na produção. Cada tentativa corre numa transacção que é sempre desfeita, por isso
nada fica alterado nem na base local.
"""
import json
import sys

import psycopg

DSN = 'dbname=sim port=5433 host=/var/run/postgresql user=root'


class Alvo:
    def __init__(self):
        self.bd = psycopg.connect(DSN, autocommit=False)
        self.r = []
        # Duas vítimas reais da base, e um funcionário sem permissões fortes
        self.vitima, self.vitima_uid = self.um("""
            select c.id, c.auth_user_id from clientes c where c.auth_user_id is not null and c.deletado_em is null
             and exists (select 1 from pedidos p where p.cliente_id = c.id)
             and exists (select 1 from ganhos_indicacao g where g.indicador_id = c.id) order by c.id limit 1""")
        self.atacante, self.atacante_uid = self.um("""
            select c.id, c.auth_user_id from clientes c where c.auth_user_id is not null and c.deletado_em is null
             and c.id <> %s order by c.id limit 1""", (self.vitima,))
        self.estafeta_uid = self.um("""
            select f.auth_user_id from funcionarios f join direcoes d on d.id = f.direcao_id
             where d.permissoes ? 'entregas.registar' and not (d.permissoes ? 'pedidos.gerir') limit 1""")[0]
        # Um pedido da vítima que valha a pena espreitar: cancelado (tem justificação para ler)
        pv = self.um("select id from pedidos where cliente_id = %s and estado = 'cancelado' limit 1", (self.vitima,))
        self.pedido_vitima = pv[0] if pv else self.um("select id from pedidos where cliente_id = %s limit 1", (self.vitima,))[0]
        self.pedido_atacante = self.um("select id from pedidos where cliente_id = %s and estado = 'pendente' limit 1",
                                       (self.atacante,))
        self.pedido_atacante = self.pedido_atacante[0] if self.pedido_atacante else None

    def um(self, sql, p=None):
        with self.bd.transaction():
            return self.bd.execute(sql, p).fetchone()

    def sessao(self, cur, quem):
        if quem == 'anon':
            cur.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({'role': 'anon'}),))
            cur.execute('set local role anon')
        elif quem == 'servidor_nao':   # alguém com a chave anónima a fingir-se de serviço
            cur.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({'role': 'anon'}),))
            cur.execute('set local role anon')
        else:
            # quem pode vir como id de cliente, id de funcionário ou já como auth_user_id:
            # resolve-se sempre para o auth_user_id certo (é o que auth.uid() vê), antes de trocar de papel.
            uid = cur.execute(
                "select coalesce((select auth_user_id from clientes where id = %s),"
                "                (select auth_user_id from funcionarios where id = %s), %s)",
                (str(quem), str(quem), str(quem))).fetchone()[0]
            cur.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({'sub': str(uid), 'role': 'authenticated'}),))
            cur.execute('set local role authenticated')

    def tenta(self, categoria, nome, quem, sql, params=None, passou_se_linhas=False, espero_bloqueio=True,
              funcao_vaza_se_nao_nulo=False):
        """Corre a tentativa e decide se ficou SEGURA.

        - passou_se_linhas: leitura de tabela — vaza (inseguro) se devolver linhas.
        - funcao_vaza_se_nao_nulo: chamada a função — vaza se o resultado não for nulo/vazio
          (um select a uma função devolve sempre 1 linha, mesmo quando o valor é NULL).
        - caso contrário é escrita — só "passa" se mexer mesmo em linhas (rowcount > 0);
          as regras de acesso que filtram para zero linhas não dão erro mas não alteram nada.
        - espero_bloqueio=False: a tentativa deve correr sem efeito mau (ex.: injeção que é só texto).
        """
        bloqueada, detalhe = False, None
        try:
            with self.bd.transaction():
                cur = self.bd.cursor()
                self.sessao(cur, quem)
                cur.execute(sql, params)
                if passou_se_linhas:
                    linhas = cur.fetchall()
                    bloqueada = (len(linhas) == 0)
                    detalhe = f'devolveu {len(linhas)} linhas'
                elif funcao_vaza_se_nao_nulo:
                    v = cur.fetchone()[0]
                    bloqueada = (v is None or v == [] or v == {})
                    detalhe = 'devolveu NULL' if bloqueada else f'devolveu dados: {str(v)[:60]}'
                elif cur.rowcount >= 0 and cur.statusmessage and cur.statusmessage.split()[0] in ('UPDATE', 'DELETE', 'INSERT'):
                    bloqueada = (cur.rowcount == 0)   # 0 linhas mexidas = as regras travaram
                    detalhe = f'{cur.statusmessage} ({cur.rowcount} linhas)'
                else:
                    bloqueada = False
                    detalhe = 'executou sem erro'
        except psycopg.Error as e:
            bloqueada = True
            detalhe = (e.diag.message_primary or str(e)).strip()[:150]
        ok = bloqueada if espero_bloqueio else (not bloqueada)
        self.r.append({'categoria': categoria, 'ataque': nome, 'travado': bloqueada,
                       'esperado_travar': espero_bloqueio, 'seguro': ok, 'detalhe': detalhe})

    def correr(self):
        v, a = self.vitima, self.atacante
        vp, ap = self.pedido_vitima, self.pedido_atacante
        ANON = 'anon'

        # 1. Sem sessão (chave anónima): ler tudo o que for de dados pessoais ou de negócio
        for tab in ('clientes', 'pedidos', 'ganhos_indicacao', 'pagamentos_indicacao', 'comprovativos_pagamento',
                    'vendas', 'caixa', 'auditoria', 'notificacoes_fila', 'enderecos_cliente', 'avaliacoes',
                    'conversas_atendimento', 'mensagens_atendimento', 'extratos', 'custos', 'funcionarios',
                    'codigos_indicacao', 'adesoes_pacote', 'turnos', 'reclamacoes'):
            self.tenta('1. Anónimo lê tabelas', f'select * from {tab}', ANON,
                       f'select * from {tab} limit 5', passou_se_linhas=True)
        self.tenta('1. Anónimo lê tabelas', 'ler segredos do servidor', ANON,
                   'select * from segredos_servidor limit 5', passou_se_linhas=True)

        # 2. Sem sessão: chamar funções do servidor (SECURITY DEFINER) e de serviço
        self.tenta('2. Anónimo chama funções', 'registar_cliente', ANON, "select registar_cliente('Hacker')")
        self.tenta('2. Anónimo chama funções', 'contactos', ANON, 'select contactos()')
        self.tenta('2. Anónimo chama funções', 'meu_perfil', ANON, 'select meu_perfil()')
        self.tenta('2. Anónimo chama funções', 'notificacoes_por_enviar (serviço)', ANON,
                   'select * from notificacoes_por_enviar(100)', passou_se_linhas=True)
        self.tenta('2. Anónimo chama funções', 'marcar_notificacoes_enviadas (serviço)', ANON,
                   'select marcar_notificacoes_enviadas(array[gen_random_uuid()])')
        self.tenta('2. Anónimo chama funções', 'limpar_dados (serviço)', ANON, 'select limpar_dados()')
        self.tenta('2. Anónimo chama funções', 'segredo_envio_valido (serviço)', ANON,
                   "select segredo_envio_valido('x')")
        self.tenta('2. Anónimo chama funções', 'job_estimulos_mensais (cron)', ANON, 'select job_estimulos_mensais()')
        self.tenta('2. Anónimo chama funções', 'agendar_jobs', ANON, 'select agendar_jobs()')
        self.tenta('2. Anónimo chama funções', 'registar_auditoria', ANON,
                   "select registar_auditoria('falso', null, null, '{}'::jsonb)")

        # 3. Cliente autenticado a ler dados de OUTRO cliente
        self.tenta('3. Cliente lê dados de outro', 'pedidos da vítima', a,
                   'select * from pedidos where cliente_id = %s', (v,), passou_se_linhas=True)
        self.tenta('3. Cliente lê dados de outro', 'ganhos da vítima', a,
                   'select * from ganhos_indicacao where indicador_id = %s', (v,), passou_se_linhas=True)
        self.tenta('3. Cliente lê dados de outro', 'endereços da vítima', a,
                   'select * from enderecos_cliente where cliente_id = %s', (v,), passou_se_linhas=True)
        self.tenta('3. Cliente lê dados de outro', 'saldo da vítima', a,
                   'select * from saldo_indicacao where indicador_id = %s', (v,), passou_se_linhas=True)
        self.tenta('3. Cliente lê dados de outro', 'avaliações com nome da vítima', a,
                   'select * from avaliacoes where cliente_id = %s', (v,), passou_se_linhas=True)
        self.tenta('3. Cliente lê dados de outro', 'conversas de atendimento da vítima', a,
                   'select * from conversas_atendimento where cliente_id = %s', (v,), passou_se_linhas=True)
        self.tenta('3. Cliente lê dados de outro', 'todos os clientes', a,
                   'select * from clientes limit 5', passou_se_linhas=True)
        self.tenta('3. Cliente lê dados de outro', 'justificação de cancelamento da vítima', a,
                   'select justificacao_cancelamento(%s)', (vp,), funcao_vaza_se_nao_nulo=True)
        self.tenta('3. Cliente lê dados de outro', 'justificação de cancelamento (sessão autenticada SEM cliente)', self.estafeta_uid,
                   'select justificacao_cancelamento(%s)', (vp,), funcao_vaza_se_nao_nulo=True)

        # 4. Cliente a escrever/alterar o que não é dele ou campos protegidos
        self.tenta('4. Cliente escreve indevidamente', 'cancelar pedido da vítima', a,
                   'select cancelar_pedido(%s)', (vp,))
        self.tenta('4. Cliente escreve indevidamente', 'usar o saldo da vítima num pedido meu', a,
                   'select usar_credito(%s, 1000)', (ap,) if ap else (vp,))
        if ap:
            self.tenta('4. Cliente escreve indevidamente', 'dar-me desconto no meu pedido', a,
                       'update pedidos set desconto_indicacao = 9999 where id = %s', (ap,))
            self.tenta('4. Cliente escreve indevidamente', 'marcar o meu pedido como entregue e pago', a,
                       "update pedidos set estado = 'entregue_pago' where id = %s", (ap,))
            self.tenta('4. Cliente escreve indevidamente', 'baixar o subtotal do meu pedido', a,
                       'update pedidos set subtotal = 1 where id = %s', (ap,))
        self.tenta('4. Cliente escreve indevidamente', 'inventar um ganho para mim', a,
                   "insert into ganhos_indicacao (pedido_id, indicador_id, indicado_id, valor, estado) values (%s, %s, %s, 999999, 'confirmado')",
                   (vp, a, v))
        self.tenta('4. Cliente escreve indevidamente', 'marcar um levantamento meu como pago', a,
                   "insert into pagamentos_indicacao (indicador_id, valor, tipo, estado) values (%s, 999999, 'levantamento', 'pago')", (a,))
        self.tenta('4. Cliente escreve indevidamente', 'subir o meu limite de crédito', a,
                   'update clientes set limite_credito = 9999999 where id = %s', (a,))
        self.tenta('4. Cliente escreve indevidamente', 'pôr-me como embaixador', a,
                   "update codigos_indicacao set nivel = 'embaixador' where cliente_id = %s", (a,))
        self.tenta('4. Cliente escreve indevidamente', 'tornar-me funcionário', a,
                   "insert into funcionarios (nome, auth_user_id) values ('Hacker', %s)", (self.atacante_uid,))
        self.tenta('4. Cliente escreve indevidamente', 'mudar parâmetros da plataforma', a,
                   'update parametros set ganho_por_pedido = 999999')
        self.tenta('4. Cliente escreve indevidamente', 'ligar interruptores', a,
                   "update funcionalidades set activa = true where chave = 'multi_cozinha'")
        self.tenta('4. Cliente escreve indevidamente', 'ler a fila de notificações', a,
                   'select * from notificacoes_fila limit 5', passou_se_linhas=True)

        # 5. Funcionário (só entregas) a exceder as permissões
        f = self.estafeta_uid
        self.tenta('5. Funcionário excede permissões', 'mudar preços do cardápio', f,
                   'update cardapio set preco = 1')
        self.tenta('5. Funcionário excede permissões', 'mudar parâmetros', f,
                   'update parametros set ganho_por_pedido = 999999')
        self.tenta('5. Funcionário excede permissões', 'ligar interruptores', f,
                   "update funcionalidades set activa = false where chave = 'avaliacoes'")
        self.tenta('5. Funcionário excede permissões', 'promover-se a administrador', f,
                   'update funcionarios set administrador_principal = true where auth_user_id = %s', (f,))
        self.tenta('5. Funcionário excede permissões', 'aprovar um levantamento', f,
                   'select aprovar_levantamento(gen_random_uuid())')
        self.tenta('5. Funcionário excede permissões', 'ler os custos do negócio', f,
                   'select * from custos limit 5', passou_se_linhas=True)
        self.tenta('5. Funcionário excede permissões', 'abrir casos de investigação', f,
                   "select abrir_investigacoes(current_date - 30, current_date)")
        self.tenta('5. Funcionário excede permissões', 'apagar vendas', f, 'delete from vendas where true')

        # 6. Fraude de dinheiro e integridade
        self.tenta('6. Fraude e integridade', 'forjar uma venda App cliente', f,
                   "insert into vendas (produto, qtd, valor_total, origem, cozinha_id) select 'x', 1, 1, 'App cliente', cozinha_padrao()")
        self.tenta('6. Fraude e integridade', 'apagar um registo de auditoria', ANON,
                   'delete from auditoria where true')
        self.tenta('6. Fraude e integridade', 'alterar um registo de auditoria (como funcionário)', f,
                   "update auditoria set detalhe = '{}'::jsonb where true")
        self.tenta('6. Fraude e integridade', 'apagar auditoria (como serviço falso = anon)', ANON,
                   "select set_config('mb.limpeza','auditoria',true); delete from auditoria where true")

        # 7. Injeção de SQL e abuso de entrada, pela API (parâmetros de RPC)
        self.tenta('7. Injeção e abuso', 'SQL no código de indicação', a,
                   "select ligar_indicacao(%s)", ("'; drop table pedidos; --",), espero_bloqueio=False)  # deve correr e não encontrar código
        self.tenta('7. Injeção e abuso', 'tabela pedidos continua a existir', ANON,
                   "select to_regclass('public.pedidos') is not null", espero_bloqueio=False)
        self.tenta('7. Injeção e abuso', 'valor negativo no levantamento', a,
                   'select pedir_levantamento(-500000, %s, %s)', ('multicaixa_express', '923000000'))
        self.tenta('7. Injeção e abuso', 'orçamento com cardapio_id inexistente', a,
                   "select orcamento_pedido(%s, null)", (json.dumps([{'cardapio_id': '00000000-0000-0000-0000-000000000000', 'qtd': 1}]),))

        self.resumo()

    def resumo(self):
        n = len(self.r)
        seguros = sum(x['seguro'] for x in self.r)
        print(f'\n=== Teste de segurança: {seguros}/{n} tentativas tratadas como deviam ===\n')
        cat = None
        for x in self.r:
            if x['categoria'] != cat:
                cat = x['categoria']
                print(f'\n{cat}')
            marca = 'OK  ' if x['seguro'] else '>>> FALHA'
            estado = 'travado' if x['travado'] else 'passou'
            print(f'  {marca} [{estado}] {x["ataque"]} — {x["detalhe"]}')
        falhas = [x for x in self.r if not x['seguro']]
        print(f'\n{"="*60}')
        if falhas:
            print(f'FALHAS DE SEGURANÇA: {len(falhas)}')
            for x in falhas:
                print(f'  - {x["categoria"]} / {x["ataque"]}: {x["detalhe"]}')
        else:
            print('Nenhuma falha: todas as tentativas foram tratadas como deviam.')
        json.dump(self.r, open('/tmp/claude-0/sim/ataque.json', 'w'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    Alvo().correr()
