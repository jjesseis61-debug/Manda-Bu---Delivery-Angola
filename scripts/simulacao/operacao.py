"""O dia a dia do negócio simulado: pedidos (do carrinho à entrega), caixa, pacotes, grupos,
Convida e Ganha, avaliações, reclamações e as tarefas agendadas do servidor."""
from datetime import timedelta

from motor import ErroNegocio, Jsonb, luanda, novo_id
from mundo import MOTIVOS_ATRASO, MOTIVOS_CANCELAMENTO, PRINCIPAIS, R, Mundo

# Erros que a app mostra ao utilizador (regras de negócio), por acção
ESPERADOS_PEDIDO = ('doses_esgotadas', 'prato_indisponivel', 'cozinha_indisponivel', 'cozinha_nao_aceita_pedidos',
                    'grupo_fechado', 'opcoes_em_falta')


class Operacao(Mundo):
    # ================================================================== pedidos
    def saldo(self, c):
        return self.bd.executar('ler_saldo', self.cli(c),
                                'select coalesce(saldo_disponivel, 0) from saldo_indicacao where indicador_id = %s',
                                (c,), um=True) or 0

    def tem_pacote(self, c):
        r = self.bd.executar('meu_pacote', self.cli(c), 'select meu_pacote()', um=True)
        return bool(r and r.get('em_vigor'))

    def itens_do_carrinho(self, coz):
        k = self.cozinhas[coz]
        prato = R.choice(PRINCIPAIS)
        itens = [{'cardapio_id': str(k['cardapio'][prato]), 'qtd': 2 if R.random() < 0.12 else 1}]
        # Pratos montáveis: às vezes tira um ingrediente da receita
        if self.ligada('pratos_montaveis') and R.random() < 0.1:
            comp = self.bd.valor("select componentes -> 0 ->> 'produto_id' from pratos_base where id = %s", (k['base'][prato],))
            if comp:
                itens[0]['componentes_excluidos'] = [comp]
        if k['montavel'] and R.random() < 0.08:
            m = k['montavel']
            itens = [{'cardapio_id': str(m['id']), 'qtd': 1,
                      'opcoes': [str(R.choice(m['base'])), str(R.choice(m['proteina']))]
                      + ([str(m['extra'])] if R.random() < 0.4 else [])}]
        if R.random() < 0.35:
            itens.append({'cardapio_id': str(k['cardapio'][R.choice(['Sumo natural', 'Água'])]), 'qtd': 1})
        return itens

    def fazer_pedido(self, c, coz, grupo=None):
        d = self.clientes[c]
        if not d['activo']:
            return
        bd = self.bd
        itens = self.itens_do_carrinho(coz)
        ponto = None if grupo else (d['empresa'] if d['empresa'] and R.random() < 0.3 else d['ponto'])
        try:
            orc = bd.executar('orcamento_pedido', self.cli(c), 'select orcamento_pedido(%s, %s, %s, %s)',
                              (Jsonb(itens), ponto, coz if self.ligada('multi_cozinha') and not grupo else None,
                               grupo['id'] if grupo else None),
                              esperados=ESPERADOS_PEDIDO, um=True)
        except ErroNegocio:
            return
        pid = novo_id()
        try:
            bd.executar('criar_pedido', self.cli(c), """
                insert into pedidos (id, cliente_id, ponto_entrega_id, grupo_id, cozinha_id, itens, observacoes, dispositivo_id)
                values (%s, %s, %s, %s, %s, %s, %s, %s)""",
                        (pid, c, ponto, grupo['id'] if grupo else None,
                         coz if self.ligada('multi_cozinha') and not grupo else None, Jsonb(itens),
                         R.choice([None, None, None, 'Sem jindungo, por favor', 'Ligar ao chegar']), d['dispositivo']),
                        esperados=ESPERADOS_PEDIDO)
        except ErroNegocio:
            return
        d['pedidos'] += 1
        self.pedidos_dia += 1
        total = orc['total']
        pago = 0
        # O pacote paga primeiro; o saldo cobre o que faltar (como o carrinho da app)
        if self.ligada('pacotes') and self.tem_pacote(c) and R.random() < 0.9:
            try:
                pago = bd.executar('usar_pacote', self.cli(c), 'select usar_pacote(%s)', (pid,),
                                   esperados=('sem_pacote',), um=True) or 0
            except ErroNegocio:
                pago = 0
        if self.ligada('indicacao') and R.random() < 0.7:
            s = self.saldo(c)
            usar = min(s, total - pago)
            if usar > 0:
                try:
                    bd.executar('usar_credito', self.cli(c), 'select usar_credito(%s, %s)', (pid, usar),
                                esperados=('saldo_insuficiente', 'acima_do_valor_do_pedido'), um=True)
                except ErroNegocio:
                    pass
        agora = bd.agora
        if grupo:
            return pid   # o grupo segue pelo gerente (mudar_estado_grupo) e pela entrega de cada pedido
        if R.random() < 0.02:
            self.agenda.marcar(agora + timedelta(minutes=R.randint(1, 3)), self.cliente_cancela, c, pid)
            return pid
        espera = R.randint(1, 6) if R.random() < 0.9 else R.randint(8, 14)   # às vezes passa dos 7 min
        self.agenda.marcar(agora + timedelta(minutes=espera), self.cozinha_confirma, coz, pid)
        return pid

    def cliente_cancela(self, c, pid):
        self.bd.executar('cancelar_pedido_cliente', self.cli(c), 'select cancelar_pedido(%s, %s)',
                         (pid, 'Cancelado pelo cliente na app'), esperados=('estado_invalido',))

    def estado(self, quem, pid, estado, **extra):
        self.bd.executar(f'estado_{estado}', quem, 'select mudar_estado_pedido(%s, %s, %s, %s, %s)',
                         (pid, estado, extra.get('motivo'), extra.get('caixa'),
                          Jsonb(extra['parcelas']) if 'parcelas' in extra else None),
                         esperados=('transicao_invalida',))

    def cozinha_confirma(self, coz, pid):
        g = self.func(self.cozinhas[coz]['gerente'])
        if self.bd.valor('select estado from pedidos where id = %s', (pid,)) != 'pendente':
            return
        if R.random() < 0.015:
            self.estado(g, pid, 'cancelado', motivo=R.choice(MOTIVOS_CANCELAMENTO + ['Sem gás.']))
            return
        self.estado(g, pid, 'confirmado')
        self.agenda.marcar(self.bd.agora + timedelta(minutes=R.randint(2, 8)), self.cozinha_prepara, coz, pid)

    def cozinha_prepara(self, coz, pid):
        self.estado(self.func(self.cozinhas[coz]['gerente']), pid, 'em_preparacao')
        self.agenda.marcar(self.bd.agora + timedelta(minutes=R.randint(12, 28)), self.sai_para_entrega, coz, pid)

    def sai_para_entrega(self, coz, pid):
        est = R.choice(self.cozinhas[coz]['estafetas'])
        self.estado(self.func(est), pid, 'em_entrega')
        viagem = R.randint(8, 30) if R.random() < 0.92 else R.randint(45, 70)
        if viagem > 40:   # atraso: o gerente avisa o cliente do motivo
            self.agenda.marcar(self.bd.agora + timedelta(minutes=25), self.avisar_atraso, coz, pid)
        if self.ligada('acompanhamento_entrega'):
            self.agenda.marcar(self.bd.agora + timedelta(minutes=3), self.posicao_estafeta, est)
        self.agenda.marcar(self.bd.agora + timedelta(minutes=viagem), self.entregar, coz, pid, est)

    def posicao_estafeta(self, est):
        self.bd.executar('registar_posicao_entrega', self.func(est), 'select registar_posicao_entrega(%s, %s, %s)',
                         (-8.9 + R.uniform(-0.05, 0.05), 13.2 + R.uniform(-0.05, 0.05), 12.0), um=True)

    def avisar_atraso(self, coz, pid):
        if self.bd.valor('select estado from pedidos where id = %s', (pid,)) != 'em_entrega':
            return
        self.bd.executar('informar_atraso', self.func(self.cozinhas[coz]['gerente']),
                         'select informar_atraso(%s, %s, %s)', (pid, R.choice(MOTIVOS_ATRASO), R.choice([10, 15, 20])))

    def entregar(self, coz, pid, est):
        bd = self.bd
        x = bd.linhas("""select subtotal + taxa_entrega - desconto_indicacao - credito_indicacao_usado - pago_pacote, estado
                           from pedidos where id = %s""", (pid,))[0]
        falta, estado = int(x[0]), x[1]
        if estado != 'em_entrega':
            return
        caixa = self.cozinhas[coz]['caixa']
        parcelas = []
        if falta > 0:
            sorte = R.random()
            if sorte < 0.7:
                parcelas = [{'metodo': 'Dinheiro', 'valor': falta}]
            else:
                metodo = 'Multicaixa Express' if sorte < 0.9 else 'TPA'
                caminho = f'{pid}/{bd.agora.strftime("%Y%m%d%H%M%S")}.jpg'
                # Foto do comprovativo enviada pelo estafeta (bucket privado)
                bd.executar('enviar_comprovativo', self.func(est),
                            "insert into storage.objects (bucket_id, name, owner) values ('comprovativos', %s, auth.uid())",
                            (caminho,))
                ref = self.ref('TPA' if metodo == 'TPA' else 'MCX')
                if R.random() < 0.3 and falta > 1000:   # parte em dinheiro, parte electrónico
                    dinheiro = (falta // 2000) * 1000
                    parcelas = [{'metodo': 'Dinheiro', 'valor': dinheiro},
                                {'metodo': metodo, 'valor': falta - dinheiro, 'referencia': ref, 'comprovativo': caminho}]
                else:
                    parcelas = [{'metodo': metodo, 'valor': falta, 'referencia': ref, 'comprovativo': caminho}]
        self.estado(self.func(est), pid, 'entregue_pago', caixa=caixa, parcelas=parcelas)
        c = bd.valor('select cliente_id from pedidos where id = %s', (pid,))
        if c in self.clientes and self.ligada('avaliacoes') and R.random() < 0.35:
            self.agenda.marcar(bd.agora + timedelta(minutes=R.randint(20, 240)), self.avaliar, c, pid, coz)
        elif c in self.clientes and R.random() < 0.01:
            self.agenda.marcar(bd.agora + timedelta(minutes=R.randint(30, 600)), self.reclamar, c, pid)
        if R.random() < 0.002:   # engano na entrega: o gerente estorna
            self.agenda.marcar(bd.agora + timedelta(minutes=40), self.estornar, coz, pid)

    def estornar(self, coz, pid):
        self.estado(self.func(self.cozinhas[coz]['gerente']), pid, 'estornado', motivo='Pedido trocado na entrega')
        self.injectados['estornos'].append(pid)

    def avaliar(self, c, pid, coz):
        if not self.clientes[c]['activo']:
            return
        # Como a app: só mostra "Avaliar" se o servidor deixar
        if not self.bd.executar('avaliacao_permitida', self.cli(c), 'select avaliacao_permitida(%s)', (pid,), um=True):
            return
        estrelas = R.choices([5, 4, 3, 2, 1], [50, 30, 12, 5, 3])[0]
        comentario = {5: 'Muito bom, chegou quente!', 4: 'Bom, mas podia vir mais molho.', 3: 'Razoável.',
                      2: 'Chegou frio e atrasado.', 1: 'Faltou a bebida e o prato veio errado.'}[estrelas]
        try:
            av = self.bd.executar('avaliar', self.cli(c), """
                insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario, usar_pseudonimo, dispositivo_id)
                values (%s, %s, %s, %s, %s, %s) returning id""",
                                  (pid, c, estrelas, comentario if R.random() < 0.6 else None, R.random() < 0.3,
                                   self.clientes[c]['dispositivo']), um=True)
        except ErroNegocio:
            return
        # A app avalia os pratos do pedido (receitas: prato_base_id de cada item)
        pratos = self.bd.linhas("""select distinct (i ->> 'prato_base_id')::uuid from pedidos, jsonb_array_elements(itens) i
                                    where id = %s and i ->> 'prato_base_id' is not null""", (pid,))
        for (prato,) in pratos[:2]:
            self.bd.executar('avaliar_prato', self.cli(c),
                             'insert into avaliacoes_pratos (avaliacao_id, prato_id, estrelas) values (%s, %s, %s)',
                             (av, prato, max(1, min(5, estrelas + R.choice([-1, 0, 0, 1])))))

    def reclamar(self, c, pid):
        if self.clientes[c]['activo']:
            self.bd.executar('fazer_reclamacao', self.cli(c), 'select fazer_reclamacao(%s, %s)',
                             (pid, 'O estafeta foi mal-educado e o troco veio errado.'),
                             esperados=('reclamacao_existente', 'prazo_terminado'), um=True)

    # ================================================================== caixa
    def abrir_caixa(self, coz):
        self.cozinhas[coz]['caixa'] = self.bd.executar(
            'abrir_caixa', self.func(self.cozinhas[coz]['gerente']), 'select abrir_caixa(%s, %s, %s)',
            (coz, 'Balcão', 5000), um=True)

    def sangria(self, coz):
        k = self.cozinhas[coz]
        g = self.func(k['gerente'])
        res = self.bd.executar('resumo_caixa', g, 'select resumo_caixa(%s)', (k['caixa'],), um=True)
        if res and res['esperado'] > 60000:
            self.bd.executar('registar_sangria', g, 'select registar_sangria(%s, %s, %s)',
                             (k['caixa'], int(res['esperado'] - 20000) // 1000 * 1000, 'Depósito no banco'), um=True)

    def fechar_caixa(self, coz):
        k = self.cozinhas[coz]
        g = self.func(k['gerente'])
        bd = self.bd
        # Pedidos que ainda estejam a caminho são entregues antes de fechar
        res = bd.executar('resumo_caixa', g, 'select resumo_caixa(%s)', (k['caixa'],), um=True)
        for comp in res['comprovativos']:
            if comp['estado'] == 'por_conferir':
                ok = R.random() > 0.01
                bd.executar('conferir_comprovativo', g, 'select conferir_comprovativo(%s, %s, %s)',
                            (comp['id'], ok, None if ok else 'Referência não aparece no extrato'))
        res = bd.executar('resumo_caixa', g, 'select resumo_caixa(%s)', (k['caixa'],), um=True)
        diferenca = R.choice([-500, -1000, 200]) if R.random() < 0.04 else 0
        contado = int(round(res['esperado'])) + diferenca
        f = bd.executar('fechar_caixa', g, 'select fechar_caixa(%s, %s, %s)',
                        (k['caixa'], contado, 'Faltou troco' if diferenca else None), um=True)
        if diferenca:
            self.injectados['diferencas_caixa'][str(k['caixa'])] = diferenca
        k['caixa'] = None
        return f

    # ================================================================== stock
    def repor_stock(self, coz):
        saldos = dict(self.bd.linhas("""
            select p.nome, coalesce(sum(case e.tipo when 'Entrada' then e.quantidade else -e.quantidade end), 0)
              from produtos p left join estoque_longo_prazo e on e.produto_id = p.id and e.cozinha_id = %s and e.deletado_em is null
             group by p.nome""", (coz,)))
        consumo = dict(self.bd.linhas("""
            select p.nome, coalesce(sum(e.quantidade), 0) from estoque_longo_prazo e join produtos p on p.id = e.produto_id
             where e.cozinha_id = %s and e.tipo = 'Consumo' and e.data > now() - interval '7 days' group by p.nome""", (coz,)))
        for nome, p in self.produtos.items():
            semana = float(consumo.get(nome, 0))
            base = p['compra'] * (1000 if p['unidade'] in ('kg', 'l') else 1)
            if float(saldos.get(nome, 0)) < semana * 1.3 + base * 0.5:
                self.comprar(coz, nome, max(1, round(semana * 1.2 / base)))

    # ================================================================== pacotes
    def aderir_pacote(self, c):
        metodo = R.choice(['multicaixa_express', 'multicaixa_express', 'unitel_money', 'loja'])
        pac = R.choice(self.pacotes)
        try:
            a = self.bd.executar('aderir_pacote', self.cli(c), 'select aderir_pacote(%s, %s)', (pac, metodo),
                                 esperados=('adesao_pendente',), um=True)
        except ErroNegocio:
            return
        self.agenda.marcar(self.bd.agora + timedelta(minutes=R.randint(15, 180)), self.confirmar_pacote, c, a, metodo)

    def confirmar_pacote(self, c, a, metodo):
        coz = self.cozinha_do(c)
        caixa = self.cozinhas[coz]['caixa'] if metodo == 'loja' else None
        if metodo == 'loja' and not caixa:
            return
        self.bd.executar('confirmar_pagamento_pacote', self.func(self.financeiro),
                         'select confirmar_pagamento_pacote(%s, %s, %s)',
                         (a, None if metodo == 'loja' else self.ref('PAC'), caixa), um=True)

    # ================================================================== grupos
    def criar_grupo(self, emp):
        membros = [c for c, d in self.clientes.items() if d['empresa'] == emp['ponto'] and d['activo']]
        if len(membros) < 3:
            return
        org = R.choice(membros)
        dia = self.bd.agora.date()
        coz = self.cozinha_do(org)
        try:
            gid = self.bd.executar('criar_grupo', self.cli(org), """
                insert into pedidos_grupo (ponto_entrega_id, cozinha_id, hora_entrega, prazo_adesao, modo_pagamento, dispositivo_id)
                values (%s, %s, %s, %s, 'individual', %s) returning id""",
                                   (emp['ponto'], coz, luanda(dia, 12, 30), luanda(dia, 11, 45), self.clientes[org]['dispositivo']),
                                   esperados=('grupo_existente', 'hora_invalida'), um=True)
        except ErroNegocio:
            return
        g = {'id': gid, 'cozinha': coz, 'membros': []}
        for c in membros:
            if c == org or R.random() < 0.6:
                self.agenda.marcar(self.bd.agora + timedelta(minutes=R.randint(1, 120)), self.entrar_no_grupo, c, g)
        self.agenda.marcar(luanda(dia, 11, 52), self.grupo_cozinha, g, 'confirmado')
        self.agenda.marcar(luanda(dia, 12, 0), self.grupo_cozinha, g, 'em_preparacao')
        self.agenda.marcar(luanda(dia, 12, 15), self.grupo_cozinha, g, 'em_entrega')
        self.agenda.marcar(luanda(dia, 12, 35), self.grupo_entregar, g)

    def entrar_no_grupo(self, c, g):
        pid = self.fazer_pedido(c, g['cozinha'], grupo=g)
        if pid:
            g['membros'].append(pid)

    def grupo_cozinha(self, g, estado):
        if self.bd.valor('select estado from pedidos_grupo where id = %s', (g['id'],)) in ('cancelado', None):
            return
        self.bd.executar('mudar_estado_grupo', self.func(self.cozinhas[g['cozinha']]['gerente']),
                         'select mudar_estado_grupo(%s, %s)', (g['id'], estado), um=True)

    def grupo_entregar(self, g):
        est = R.choice(self.cozinhas[g['cozinha']]['estafetas'])
        for pid in g['membros']:
            self.entregar(g['cozinha'], pid, est)

    # ================================================================== Convida e Ganha
    def pedir_levantamentos(self):
        for c, d in self.clientes.items():
            if not d['activo'] or not d['convida']:
                continue
            s = self.saldo(c)
            if s >= 2000 and R.random() < 0.3:
                valor = (s // 500) * 500
                self.bd.executar('pedir_levantamento', self.cli(c), 'select pedir_levantamento(%s, %s, %s)',
                                 (valor, R.choice(['multicaixa_express', 'unitel_money']), d.get('numero') or self.numero(c)),
                                 esperados=('sem_compra_propria', 'abaixo_minimo', 'saldo_insuficiente'), um=True)

    def numero(self, c):
        d = self.clientes[c]
        d['numero'] = d.get('numero') or ('9' + str(R.randint(21000000, 99999999)))
        if d.get('fraude_de'):   # a fraude usa o número de quem a montou
            d['numero'] = self.clientes[d['fraude_de']].get('numero') or self.numero(d['fraude_de'])
        return d['numero']

    def pagar_levantamentos(self):
        fin = self.func(self.financeiro)
        for (pid, ind) in self.bd.linhas("""select id, indicador_id from pagamentos_indicacao
                                             where tipo = 'levantamento' and estado = 'pedido' order by criado_em"""):
            if ind in self.injectados['fraude']:
                self.bd.executar('rejeitar_levantamento', fin, 'select rejeitar_levantamento(%s, %s)',
                                 (pid, 'Indicações por confirmar (mesma morada)'))
                continue
            self.bd.executar('aprovar_levantamento', fin, 'select aprovar_levantamento(%s)', (pid,))
            self.bd.executar('marcar_pago', fin, 'select marcar_pago(%s, %s)', (pid, self.ref('PAG')))

    def rever_ganhos(self):
        fin = self.func(self.financeiro)
        for (gid, ind) in self.bd.linhas("select id, indicador_id from ganhos_indicacao where estado = 'em_verificacao'"):
            if ind in self.injectados['fraude']:
                self.bd.executar('rever_ganho', fin, 'select rever_ganho(%s, %s, %s)', (gid, 'anular', 'Contas da mesma morada'), um=True)
            else:
                self.bd.executar('rever_ganho', fin, 'select rever_ganho(%s, %s, %s)', (gid, 'confirmar', None), um=True)

    def montar_fraude(self):
        """Um cliente cria contas falsas com o próprio código: 3 no mesmo telemóvel, 3 na mesma casa."""
        candidatos = [c for c, d in self.clientes.items() if d['activo'] and d['pedidos'] >= 2]
        f = R.choice(candidatos)
        self.injectados['fraude'].append(f)
        self.clientes[f]['convida'] = True
        for i in range(6):
            c = self.novo_cliente(indicador=f, zona=self.clientes[f]['zona'], fraude_de=f)
            if i < 3:
                self.clientes[c]['dispositivo'] = self.clientes[f]['dispositivo']
            self.clientes[c]['freq'] = 0.6
        self.facto(f'Fraude montada: 6 contas falsas ligadas ao código de {self.clientes[f]["nome"]}')

    # ================================================================== reclamações e moderação
    def tratar_reclamacoes(self, coz):
        g = self.func(self.cozinhas[coz]['gerente'])
        for (rid,) in self.bd.linhas("select id from reclamacoes where estado = 'aberta' and cozinha_id = %s", (coz,)):
            procedente = R.random() < 0.6
            self.bd.executar('decidir_reclamacao', g, 'select decidir_reclamacao(%s, %s, %s, %s, %s, %s)',
                             (rid, procedente, 'Pedimos desculpa. Falámos com a equipa para não voltar a acontecer.'
                              if procedente else 'Verificámos e o pedido saiu completo e a horas.',
                              R.choice(['atraso', 'qualidade', 'estafeta']), 'desconto' if procedente else 'nenhuma',
                              500 if procedente else None))

    # ================================================================== tarefas do servidor
    def job(self, nome):
        self.bd.executar(f'job:{nome}', None, f'select {nome}()')

    def enviar_notificacoes(self):
        ids = self.bd.executar('enviar_notificacoes', self.servico(),
                               'select coalesce(array_agg(id), array[]::uuid[]) from notificacoes_por_enviar(1000)', um=True)
        if ids:
            self.bd.executar('marcar_enviadas', self.servico(), 'select marcar_notificacoes_enviadas(%s)', (ids,), um=True)

    # ================================================================== apoio
    def ligada(self, chave):
        return chave in self.ligadas

    def cozinha_do(self, c):
        d = self.clientes[c]
        if 'cozinha' not in d or d['cozinha'] not in self.cozinhas:
            d['cozinha'] = R.choice(list(self.cozinhas)) if self.ligada('multi_cozinha') else self.padrao
        return d['cozinha']
