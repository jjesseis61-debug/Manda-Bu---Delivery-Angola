#!/usr/bin/env python3
"""Simulação de 12 meses de funcionamento do Manda Bué numa base de dados local.

Uso: simular.py [dias] [dsn]
Requer o cluster de simulação com relógio controlado (ver README.md desta pasta).
"""
import json
import pickle
import sys
import time
from datetime import date, timedelta

from motor import BD, Agenda, ErroNegocio, Jsonb, luanda
from mundo import R
from operacao import Operacao

INICIO = date(2026, 10, 5)   # segunda-feira


class Simulacao(Operacao):
    def __init__(self, bd, dias):
        super().__init__(bd, INICIO, dias)
        self.agenda = Agenda()
        self.ligadas = {'indicacao', 'avaliacoes', 'destaques'}
        self.padrao = None
        self.mensal = []
        self.diario = []

    # ------------------------------------------------------------------ calendário do ano
    def marcos(self, n):
        """O que acontece no dia n da operação (lançamentos, mudanças de regras, incidentes)."""
        adm = self.func(self.admin)
        fin = self.func(self.financeiro)
        bd = self.bd

        def ligar(*chaves):
            for k in chaves:
                bd.executar('alterar_funcionalidade', adm, 'select alterar_funcionalidade(%s, true)', (k,))
                self.ligadas.add(k)
            self.facto('Ligado: ' + ', '.join(chaves))

        if n == 21:
            ligar('reconhecimento_equipa', 'contadores_zona', 'pessoas_como_tu')
        if n == 30:
            ligar('pacotes')
            for nome, ref, of, val, preco, val_d in (('Pacote Semana', 5, 0, 4000, 19000, 10),
                                                     ('Pacote Mês', 20, 2, 4000, 76000, 35)):
                self.pacotes.append(bd.executar('pacote', fin, """
                    insert into pacotes (nome, descricao, refeicoes, refeicoes_oferta, valor_refeicao, preco, validade_dias)
                    values (%s, %s, %s, %s, %s, %s, %s) returning id""",
                                                (nome, f'{ref} almoços', ref, of, val, preco, val_d), um=True))
        if n == 45:   # doses do dia na muamba, alguns dias
            self.facto('A cozinha passa a lançar doses do dia da muamba às sextas')
        if n == 60:
            ligar('multi_cozinha', 'pedidos_grupo', 'perfil_cozinha')
            self.abrir_cozinha(None, 'Cozinha Vida Pacífica')
            for nome, zona in (('Sonangol Talatona', 'Talatona'), ('BFA Maianga', 'Maianga'), ('Escola Kilamba', 'Kilamba')):
                emp = self.nova_empresa(nome, zona)
                for _ in range(R.randint(6, 12)):
                    self.novo_cliente(zona=zona, empresa=emp)
        if n == 90:
            ligar('pratos_montaveis', 'acompanhamento_entrega')
            self.criar_montavel()
        if n == 120:
            self.montar_fraude()
        if n == 150:
            self.abrir_cozinha(None, 'Cozinha Zango 8 Mil')
            emp = self.nova_empresa('Hospital do Zango', 'Zango')
            for _ in range(10):
                self.novo_cliente(zona='Zango', empresa=emp)
        if n == 180:   # preço da muamba sobe em todas as cozinhas
            for k in self.cozinhas.values():
                bd.executar('mudar_preco', adm, 'update cardapio set preco = 4800 where id = %s', (k['cardapio']['Muamba de galinha'],))
            self.facto('Preço da muamba: 4500 → 4800 Kz')
        if n == 210:
            bd.executar('alterar_parametros', adm, 'select alterar_parametros(%s)', (Jsonb({'ganho_por_pedido': 150}),))
            self.facto('Convida e Ganha: ganho por pedido 100 → 150 Kz (só para as novas ligações)')
        if n == 240:
            self.abrir_cozinha(None, 'Cozinha 1° de Maio')
        if n in (140, 230, 320):   # pedidos de apagar a conta
            c = R.choice([c for c, d in self.clientes.items() if d['activo'] and d['pedidos'] > 0])
            bd.executar('apagar_conta', self.cli(c), 'select apagar_conta()')
            self.clientes[c]['activo'] = False
            self.facto(f'Um cliente apagou a conta ({self.clientes[c]["pedidos"]} pedidos feitos)')
        if n == 300:   # uma cozinha fecha uma semana para obras
            coz = list(self.cozinhas)[1]
            bd.executar('pausar_cozinha', adm, "update cozinhas set estado = 'pausada' where id = %s", (coz,))
            self.cozinhas[coz]['pausada'] = True
            self.facto(f'{self.cozinhas[coz]["nome"]} em pausa por obras (1 semana)')
        if n == 307:
            coz = list(self.cozinhas)[1]
            bd.executar('pausar_cozinha', adm, "update cozinhas set estado = 'activa' where id = %s", (coz,))
            self.cozinhas[coz]['pausada'] = False
            self.facto(f'{self.cozinhas[coz]["nome"]} reabre')

    def criar_montavel(self):
        adm = self.func(self.admin)
        bd = self.bd
        for coz, k in self.cozinhas.items():
            mid = bd.executar('cardapio', adm, """insert into cardapio (nome, categoria, preco, cozinha_id)
                                                 values ('Monta o teu prato', 'Composto', 0, %s) returning id""", (coz,), um=True)
            m = {'id': mid, 'base': [], 'proteina': []}
            for grupo, minimo, opcoes in (('Base', 1, [('Arroz', 1500, 'Arroz', 150), ('Funge', 1200, 'Fuba de milho', 150)]),
                                          ('Proteína', 1, [('Frango', 2500, 'Frango', 250), ('Peixe', 2200, 'Peixe carapau', 250)]),
                                          ('Acompanhamento', 0, [('Feijão', 800, 'Feijão', 100)])):
                gid = bd.executar('opcoes_grupo', adm, """insert into opcoes_grupos (cardapio_id, nome, minimo, maximo)
                                                         values (%s, %s, %s, 1) returning id""", (mid, grupo, minimo), um=True)
                for nome, preco, prod, q in opcoes:
                    oid = bd.executar('opcao', adm, """insert into opcoes (grupo_id, nome, preco_extra, componentes)
                                                      values (%s, %s, %s, %s) returning id""",
                                      (gid, nome, preco, Jsonb([{'produto_id': str(self.produtos[prod]['id']), 'quantidade': q,
                                                                 'unidade': 'g'}])), um=True)
                    if grupo == 'Base':
                        m['base'].append(oid)
                    elif grupo == 'Proteína':
                        m['proteina'].append(oid)
                    else:
                        m['extra'] = oid
            k['montavel'] = m

    # ------------------------------------------------------------------ crescimento
    def novos_clientes(self, n):
        """Clientes que chegam por si (redes sociais, passa-palavra) e convidados com código."""
        organicos = R.randint(0, 2) + n // 60
        for _ in range(organicos):
            self.novo_cliente()
        for c, d in list(self.clientes.items()):
            if d['activo'] and d['convida'] and d['pedidos'] > 0 and R.random() < 0.025:
                self.novo_cliente(indicador=c, zona=d['zona'] if R.random() < 0.6 else None)
        for d in self.clientes.values():   # alguns deixam de pedir
            if d['activo'] and R.random() < 0.003:
                d['freq'] *= 0.2

    # ------------------------------------------------------------------ plano do dia
    def planear_dia(self, n, dia):
        a = self.agenda
        m = luanda
        semana = dia.weekday()
        # Tarefas do pg_cron (horas em Luanda = UTC+1; o cron do Supabase corre em UTC)
        a.marcar(m(dia, 4, 30), self.job, 'descartar_notificacoes_expiradas')
        a.marcar(m(dia, 6, 15), self.job, 'job_planos_compras')
        a.marcar(m(dia, 8, 0), self.job, 'job_n6_expiracao')
        a.marcar(m(dia, 9, 0), self.job, 'job_n14_pacotes')
        if semana == 0:
            a.marcar(m(dia, 6, 30), self.job, 'job_vigilancia')
            a.marcar(m(dia, 8, 0), self.job, 'job_n7_destaques')
        if semana < 5:
            a.marcar(m(dia, 11, 0), self.job, 'job_n5_lembrete')
        if dia.day == 1:
            a.marcar(m(dia, 7, 0), self.job, 'job_estimulos_mensais')
        if dia.day == 2:
            a.marcar(m(dia, 7, 0), self.job, 'job_relatorio_analista')
        if dia.day == 3:
            a.marcar(m(dia, 7, 0), self.job, 'job_investigacoes')
        for h in range(7, 24):
            a.marcar(m(dia, h, 1), self.job, 'job_contadores_zona')
            for mi in range(0, 60, 10):
                a.marcar(m(dia, h, mi, 30), self.enviar_notificacoes)
        for h in range(10, 23):
            for mi in range(0, 60, 5):
                a.marcar(m(dia, h, mi, 10), self.job, 'job_alertas_pedidos')
            for mi in range(0, 60, 15):
                a.marcar(m(dia, h, mi, 20), self.job, 'job_n9_avaliacao')
        for h in range(8, 14):
            for mi in range(0, 60, 5):
                a.marcar(m(dia, h, mi, 40), self.job, 'job_grupos')

        if semana == 6:   # domingo: fechado; o gerente marca os turnos da semana e repõe o stock
            for coz in self.cozinhas:
                a.marcar(m(dia, 18, 0), self.marcar_turnos, coz, dia + timedelta(days=1), 7)
                a.marcar(m(dia, 18, 30), self.repor_stock, coz)
            return

        self.novos_clientes(n)
        abertas = [coz for coz, k in self.cozinhas.items() if not k.get('pausada')]
        for coz in abertas:
            a.marcar(m(dia, 8, 45), self.abrir_caixa, coz)
            a.marcar(m(dia, 15, 0), self.sangria, coz)
            a.marcar(m(dia, 10, 0), self.tratar_reclamacoes, coz)
            a.marcar(m(dia, 22, 15), self.fechar_caixa, coz)
            if semana == 4 and n >= 45:
                a.marcar(m(dia, 9, 30), self.lancar_doses, coz)
        if semana == 0:
            a.marcar(m(dia, 9, 15), self.pedir_levantamentos)
        if semana == 1:
            a.marcar(m(dia, 10, 30), self.rever_ganhos)
            a.marcar(m(dia, 11, 0), self.pagar_levantamentos)
        if semana == 4:
            a.marcar(m(dia, 16, 0), self.pagar_levantamentos)

        # Pedidos dos clientes
        fator = 0.6 if semana == 5 else 1.0
        for c, d in self.clientes.items():
            if not d['activo'] or R.random() >= d['freq'] * fator:
                continue
            coz = self.cozinha_do(c)
            if coz not in abertas:
                if not self.ligada('multi_cozinha'):
                    continue
                coz = R.choice(abertas)
            if d['empresa'] and semana < 5 and self.ligada('pedidos_grupo'):
                continue   # quem trabalha numa empresa almoça pelo grupo nos dias úteis
            if R.random() < 0.8:
                hora = m(dia, 11, 0) + timedelta(minutes=R.randint(0, 170))
            else:
                hora = m(dia, 18, 0) + timedelta(minutes=R.randint(0, 120))
            a.marcar(hora, self.fazer_pedido, c, coz)
            if self.ligada('pacotes') and d['freq'] >= 3 / 7 and R.random() < 0.012:
                a.marcar(hora - timedelta(minutes=30), self.aderir_pacote, c)
        if self.ligada('pedidos_grupo') and semana < 5:
            for emp in self.empresas:
                if R.random() < 0.7:
                    a.marcar(m(dia, 9, 30) + timedelta(minutes=R.randint(0, 40)), self.criar_grupo, emp)

    def lancar_doses(self, coz):
        k = self.cozinhas[coz]
        self.bd.executar('lancar_doses', self.func(self.admin), 'update cardapio set doses_dia = %s where id = %s',
                         (R.randint(8, 20), k['cardapio']['Muamba de galinha']))

    # ------------------------------------------------------------------ ciclo
    def correr(self):
        self.arranque()
        self.padrao = list(self.cozinhas)[0]
        # Primeiros clientes (família, vizinhos e colegas)
        self.bd.hora(luanda(INICIO, 7, 0))
        for _ in range(25):
            c = self.novo_cliente()
            self.clientes[c]['convida'] = R.random() < 0.6
        t0 = time.time()
        for n in range(self.dias):
            dia = INICIO + timedelta(days=n)
            self.dia = dia
            self.pedidos_dia = 0
            self.bd.hora(luanda(dia, 6, 55))
            self.marcos(n)
            self.planear_dia(n, dia)
            self.agenda.correr(self.bd, luanda(dia, 23, 59, 59))
            self.diario.append({'dia': dia.isoformat(), 'pedidos': self.pedidos_dia,
                                'clientes': sum(1 for d in self.clientes.values() if d['activo']),
                                'falhas': len(self.bd.inesperados)})
            if (dia + timedelta(days=1)).day == 1 or n == self.dias - 1:
                self.fecho_do_mes(dia)
            print(f'{dia} | pedidos {self.pedidos_dia:4d} | clientes {len(self.clientes):5d} | '
                  f'falhas {len(self.bd.inesperados):4d} | {time.time() - t0:7.0f}s', flush=True)

    def fecho_do_mes(self, dia):
        """Último dia do mês: fecho mensal (financeiro) e relatório de cada cozinha (gerente)."""
        self.bd.hora(luanda(dia, 23, 30))
        fin = self.func(self.financeiro)
        t = time.perf_counter()
        fecho = self.bd.executar('fecho_mensal', fin, 'select fecho_mensal(%s, %s)', (dia.year, dia.month), um=True)
        self.mensal.append({'mes': f'{dia.year}-{dia.month:02d}', 'fecho': fecho, 'segundos': round(time.perf_counter() - t, 3)})


def main():
    dias = int(sys.argv[1]) if len(sys.argv) > 1 else 365
    dsn = sys.argv[2] if len(sys.argv) > 2 else 'dbname=sim port=5433 host=/var/run/postgresql user=root'
    s = Simulacao(BD(dsn), dias)
    try:
        s.correr()
    finally:
        estado = {'clientes': s.clientes, 'cozinhas': s.cozinhas, 'funcionarios': s.funcionarios, 'admin': s.admin,
                  'financeiro': s.financeiro, 'injectados': s.injectados, 'eventos': s.eventos, 'mensal': s.mensal,
                  'diario': s.diario, 'accoes': dict(s.bd.accoes), 'esperados': dict(s.bd.esperados),
                  'inesperados': s.bd.inesperados, 'ligadas': sorted(s.ligadas),
                  'tempos': {k: [len(v), sum(v) / len(v), max(v)] for k, v in s.bd.tempos.items() if v}}
        with open('/tmp/claude-0/sim/estado.pkl', 'wb') as f:
            pickle.dump(estado, f)


if __name__ == '__main__':
    main()
