"""O negócio simulado: equipa, cozinhas, clientes e o que cada um faz ao longo do dia.

Tudo o que as apps fazem passa pelas mesmas tabelas e funções (com RLS), como o utilizador
da app; as tarefas do servidor correm como o pg_cron (superutilizador) ou como service_role.
"""
import json
import math
import random
import string
from datetime import date, timedelta

from motor import ErroNegocio, Jsonb, luanda, novo_id

R = random.Random(20261005)

ZONAS = [('Talatona', 1000), ('Kilamba', 800), ('Viana', 1200), ('Maianga', 600), ('Cazenga', 900),
         ('Benfica', 1000), ('Zango', 1500)]
# Centros aproximados de cada zona (os clientes moram à volta)
CENTROS = {'Talatona': (-8.92, 13.18), 'Kilamba': (-8.99, 13.27), 'Viana': (-8.90, 13.37),
           'Maianga': (-8.83, 13.23), 'Cazenga': (-8.82, 13.29), 'Benfica': (-9.00, 13.15),
           'Zango': (-9.05, 13.40)}

PRODUTOS = [  # nome, medida, unidade de compra, custo por unidade de compra, margem %, tamanho da compra
    ('Frango', 'Peso', 'kg', 2800, 20, 20), ('Peixe carapau', 'Peso', 'kg', 2500, 20, 15),
    ('Carne de vaca', 'Peso', 'kg', 4500, 20, 10), ('Arroz', 'Peso', 'kg', 900, 15, 25),
    ('Feijão', 'Peso', 'kg', 1200, 15, 10), ('Fuba de milho', 'Peso', 'kg', 700, 15, 25),
    ('Óleo de palma', 'Volume', 'l', 1800, 15, 10), ('Cebola', 'Peso', 'kg', 600, 10, 10),
    ('Tomate', 'Peso', 'kg', 800, 10, 10), ('Jindungo', 'Unidade', 'un', 25, 50, 200),
    ('Batata', 'Peso', 'kg', 700, 15, 20), ('Quiabo', 'Peso', 'kg', 1500, 15, 5),
    ('Sumo natural', 'Unidade', 'un', 250, 100, 60), ('Água 0,5 l', 'Unidade', 'un', 100, 100, 120),
]

PRATOS = [  # nome, categoria, preço, receita [(produto, quantidade, unidade)]
    ('Muamba de galinha', 'Composto', 4500, [('Frango', 250, 'g'), ('Óleo de palma', 50, 'ml'), ('Quiabo', 60, 'g'),
                                            ('Fuba de milho', 150, 'g'), ('Jindungo', 2, 'un')]),
    ('Calulu de peixe', 'Composto', 4000, [('Peixe carapau', 250, 'g'), ('Óleo de palma', 40, 'ml'), ('Tomate', 60, 'g'),
                                          ('Cebola', 40, 'g'), ('Fuba de milho', 150, 'g')]),
    ('Feijão de óleo de palma', 'Composto', 3500, [('Feijão', 150, 'g'), ('Óleo de palma', 40, 'ml'), ('Peixe carapau', 120, 'g'),
                                                  ('Arroz', 120, 'g')]),
    ('Carne guisada', 'Composto', 5000, [('Carne de vaca', 220, 'g'), ('Batata', 150, 'g'), ('Cebola', 40, 'g'),
                                        ('Tomate', 50, 'g'), ('Arroz', 120, 'g')]),
    ('Frango grelhado', 'Grelhados', 4200, [('Frango', 300, 'g'), ('Batata', 200, 'g'), ('Jindungo', 1, 'un')]),
    ('Sumo natural', 'Bebidas', 700, [('Sumo natural', 1, 'un')]),
    ('Água', 'Bebidas', 300, [('Água 0,5 l', 1, 'un')]),
]
PRINCIPAIS = [p[0] for p in PRATOS if p[1] != 'Bebidas']

MOTIVOS_CANCELAMENTO = ['Acabou um ingrediente', 'Avaria na cozinha (gás, luz ou equipamento)',
                        'A cozinha não conseguiria entregar a horas', 'Endereço fora da zona de entrega']
MOTIVOS_ATRASO = ['Muitos pedidos neste momento', 'Trânsito', 'Chuva', 'O estafeta está a terminar outra entrega']
NOMES = ('Ana Bia Carla Dina Eva Filipa Graça Helena Inês Joana Kátia Luísa Marta Neusa Olga Paula Rosa Sara Teresa '
         'Vânia Wilma Yara Zita António Bruno Carlos Daniel Edson Fernando Gil Hélder Ivo João Kiame Luís Mário '
         'Nelson Osvaldo Pedro Quintino Rui Sílvio Tomás Válter Wilson Yuri').split()
APELIDOS = ('Sousa Neto Mendes Costa Silva Lopes Santos Domingos Francisco Manuel João Pedro Bento Cassoma '
            'Tchissola Kiala Lukamba Mbala Ngola Paulo Quissanga Sebastião Tavares Vunge').split()


def nome_aleatorio():
    return f'{R.choice(NOMES)} {R.choice(APELIDOS)}'


class Mundo:
    def __init__(self, bd, inicio: date, dias: int):
        self.bd = bd
        self.inicio = inicio
        self.dias = dias
        self.dia = inicio
        self.cozinhas = {}        # id -> {'nome', 'gerente', 'estafetas', 'caixa', 'cardapio': {nome: id}, ...}
        self.funcionarios = {}    # id -> {'uid', 'nome', 'cozinha'}
        self.admin = None
        self.financeiro = None
        self.clientes = {}        # id -> dados do cliente simulado
        self.empresas = []        # pontos de entrega de empresas (para os grupos)
        self.zonas = {}
        self.produtos = {}
        self.pacotes = []
        self.telefones = iter(range(923100000, 999999999, 7))
        self.referencias = iter(range(10_000_000, 99_999_999, 13))
        self.eventos = []         # factos marcantes para o relatório
        self.injectados = {'diferencas_caixa': {}, 'estornos': [], 'fraude': []}
        self.pedidos_dia = 0

    # ------------------------------------------------------------------ utilidades
    def cli(self, c):
        return ('cliente', self.clientes[c]['uid'])

    def func(self, f):
        return ('func', self.funcionarios[f]['uid'])

    def servico(self):
        return ('servico', None)

    def facto(self, texto):
        self.eventos.append((self.bd.agora.date().isoformat(), texto))

    def ref(self, prefixo='MCX'):
        return f'{prefixo}{next(self.referencias)}'

    # ------------------------------------------------------------------ arranque
    def criar_funcionario(self, nome, permissoes, cozinha=None, telefone=None):
        """O administrador regista a pessoa e a direcção (no arranque, como superutilizador)."""
        uid = novo_id()
        tel = telefone or str(next(self.telefones))
        self.bd.executar('arranque', None, 'insert into auth.users (id, phone) values (%s, %s)', (uid, '+244' + tel))
        d = self.bd.executar('arranque', None,
                             'insert into direcoes (nome, permissoes) values (%s, %s) returning id',
                             (f'Direcção de {nome}', Jsonb({p: True for p in permissoes})), um=True)
        f = self.bd.executar('arranque', None,
                             'insert into funcionarios (nome, direcao_id, auth_user_id, telefone) values (%s, %s, %s, %s) returning id',
                             (nome, d, uid, tel), um=True)
        self.funcionarios[f] = {'uid': uid, 'nome': nome, 'cozinha': cozinha}
        self.bd.executar('registar_token_push', ('func', uid), 'select registar_token_push_funcionario(%s, %s)',
                         (f'ExponentPushToken[{uid[:22]}]', 'android'))
        return f

    def arranque(self):
        bd = self.bd
        bd.hora(luanda(self.inicio, 6, 0))
        todas = [r[0] for r in bd.linhas('select chave from permissoes')]
        self.admin = self.criar_funcionario('Jesse (administrador)', todas, telefone='923000001')
        self.financeiro = self.criar_funcionario('Rita Finanças', [
            'financas.conferir', 'financas.gerir', 'indicacoes.ver', 'indicacoes.verificar',
            'indicacoes.aprovar_pagamentos', 'pacotes.gerir', 'auditoria.ver', 'vendas.registar'])
        adm = self.func(self.admin)

        # Interruptores do lançamento (o resto é ligado ao longo do ano)
        for chave in ('indicacao', 'avaliacoes', 'destaques'):
            bd.executar('alterar_funcionalidade', adm, 'select alterar_funcionalidade(%s, true)', (chave,))
        bd.executar('alterar_parametros', adm, 'select alterar_parametros(%s)', (Jsonb({
            'contacto_telefone': '+244 923 000 000', 'contacto_whatsapp': '923000000',
            'contacto_email': 'ola@mandabue.ao', 'contacto_horario': 'Seg a Sáb, 10h às 21h'}),))

        for nome, taxa in ZONAS:
            self.zonas[nome] = bd.executar('zona', adm,
                                           "insert into zonas (nome, tipo, taxa) values (%s, 'Própria', %s) returning id",
                                           (nome, taxa), um=True)
        for nome, medida, unidade, custo, margem, compra in PRODUTOS:
            self.produtos[nome] = {'id': bd.executar('produto', adm, """
                insert into produtos (nome, tipo_estoque, categoria_medida, unidade_compra, custo, margem)
                values (%s, 'Longo Prazo', %s, %s, %s, %s) returning id""", (nome, medida, unidade, custo, margem), um=True),
                'compra': compra, 'custo': custo, 'unidade': unidade}

        coz = bd.valor('select cozinha_padrao()')
        self.abrir_cozinha(coz, 'Cozinha da Alexandra', existente=True)
        self.facto('Lançamento: 1 cozinha, Convida e Ganha, avaliações e destaques ligados')

    def abrir_cozinha(self, coz, nome, existente=False):
        bd, adm = self.bd, self.func(self.admin)
        if not existente:
            coz = bd.executar('cozinha', adm, """
                insert into cozinhas (nome, responsavel, consentimento_publico, telefone_publico, horario_publico)
                values (%s, %s, true, %s, 'Seg a Sáb, 10h às 21h') returning id""",
                              (nome, nome_aleatorio(), '9' + str(R.randint(21000000, 99999999))), um=True)
        gerente = self.criar_funcionario(f'Gerente {nome}', [
            'pedidos.gerir', 'vendas.registar', 'entregas.registar', 'equipa.gerir', 'stock.gerir',
            'equipa.reconhecer', 'clientes.gerir', 'avaliacoes.moderar'], cozinha=coz)
        estafetas = [self.criar_funcionario(f'Estafeta {i} {nome}', ['entregas.registar'], cozinha=coz) for i in (1, 2, 3)]
        self.cozinhas[coz] = {'nome': nome, 'gerente': gerente, 'estafetas': estafetas, 'caixa': None,
                              'cardapio': {}, 'base': {}, 'montavel': None, 'aberta_em': self.dia}
        # Turnos da primeira semana (depois o gerente marca os da semana seguinte ao domingo)
        self.marcar_turnos(coz, self.dia, 7, por=self.admin)   # o 1.º turno é o administrador que marca
        # Cardápio: pratos com receita (pratos_base) e preço
        g = self.func(gerente)
        for nome_p, categoria, preco, receita in PRATOS:
            comp = [{'produto_id': str(self.produtos[p]['id']), 'quantidade': q, 'unidade': u} for p, q, u in receita]
            # As receitas chegam pela sincronização do sistema de balcão (serviço), não pelas apps
            base = bd.executar('prato_base', self.servico(), 'insert into pratos_base (nome, componentes, cozinha_id) values (%s, %s, %s) returning id',
                               (nome_p, Jsonb(comp), coz), um=True)
            item = bd.executar('cardapio', adm, """
                insert into cardapio (nome, categoria, preco, prato_base_id, cozinha_id, do_dia)
                values (%s, %s, %s, %s, %s, %s) returning id""",
                               (nome_p, categoria, preco, base, coz, nome_p == 'Muamba de galinha'), um=True)
            self.cozinhas[coz]['cardapio'][nome_p] = item
            self.cozinhas[coz]['base'][nome_p] = base
        # Stock inicial
        for p in self.produtos:
            self.comprar(coz, p, 2)
        if not existente:
            self.facto(f'Nova cozinha: {nome}')
        return coz

    def marcar_turnos(self, coz, desde, dias, por=None):
        c = self.cozinhas[coz]
        g = self.func(por or c['gerente'])
        for d in range(dias):
            dia = desde + timedelta(days=d)
            if dia.weekday() == 6:   # domingo fechado
                continue
            for f in [c['gerente']] + c['estafetas']:
                self.bd.executar('turno', g, """
                    insert into turnos (funcionario_id, funcionario_nome, data, hora_inicio, hora_fim, cozinha_id, periodo)
                    values (%s, %s, %s, '09:00', '22:00', %s, 'manha')""",
                                 (f, self.funcionarios[f]['nome'], dia, coz))

    def comprar(self, coz, produto, lotes=1):
        """Entrada de stock registada pelo gerente (stock.gerir)."""
        p = self.produtos[produto]
        qtd = p['compra'] * lotes
        base = qtd * 1000 if p['unidade'] in ('kg', 'l') else qtd
        self.bd.executar('stock_entrada', self.func(self.cozinhas[coz]['gerente']), """
            insert into estoque_longo_prazo (dispositivo_id, produto_id, tipo, quantidade, custo_total, fornecedor, cozinha_id)
            values ('app-gerente', %s, 'Entrada', %s, %s, 'Mercado do Kikolo', %s)""",
                         (p['id'], base, p['custo'] * qtd * R.uniform(0.95, 1.08), coz))

    # ------------------------------------------------------------------ clientes
    def novo_cliente(self, indicador=None, zona=None, empresa=None, fraude_de=None):
        bd = self.bd
        uid = novo_id()
        tel = str(next(self.telefones))
        bd.executar('auth_otp', None, 'insert into auth.users (id, phone) values (%s, %s)', (uid, '+244 ' + tel))
        nome = nome_aleatorio()
        c = bd.executar('registar_cliente', ('cliente', uid), 'select registar_cliente(%s)', (nome,), um=True)
        zona = zona or R.choice(list(self.zonas))
        dados = {'uid': uid, 'nome': nome, 'zona': zona, 'activo': True, 'empresa': empresa,
                 'freq': R.choice([0.3, 0.5, 1, 1, 2, 3, 4]) / 7,   # pedidos por dia
                 'indicador': None, 'criado': self.dia, 'pedidos': 0, 'dispositivo': f'tel-{uid[:8]}',
                 'convida': R.random() < 0.35, 'fraude_de': fraude_de, 'ultimo_levantamento': None}
        self.clientes[c] = dados
        # A app regista o telemóvel para receber notificações
        bd.executar('registar_token_push', ('cliente', uid), 'select registar_token_push(%s, %s)',
                    (f'ExponentPushToken[{uid[:22]}]', R.choice(['android', 'android', 'ios'])))
        if indicador:
            codigo = bd.valor('select codigo from codigos_indicacao where cliente_id = %s', (indicador,))
            try:
                r = bd.executar('ligar_indicacao', self.cli(c), 'select ligar_indicacao(%s)', (codigo,), um=True)
                if r == 'ok':
                    dados['indicador'] = indicador
                else:
                    bd.esperados[f'ligar_indicacao: {r}'] += 1
            except ErroNegocio:
                pass
        # Endereço: a casa (ou o mesmo ponto de quem a "convidou" na fraude)
        if fraude_de:
            ponto = self.clientes[fraude_de]['ponto']
        else:
            lat0, lng0 = CENTROS[zona]
            ponto = bd.executar('ponto_entrega', self.cli(c), """
                insert into pontos_entrega (tipo, lat, lng, zona_id, referencia, dispositivo_id)
                values ('residencial', %s, %s, %s, %s, %s) returning id""",
                                (lat0 + R.uniform(-0.02, 0.02), lng0 + R.uniform(-0.02, 0.02), self.zonas[zona],
                                 'Perto da ' + R.choice(['escola', 'igreja', 'cantina', 'farmácia', 'paragem']), dados['dispositivo']),
                                um=True)
        bd.executar('endereco', self.cli(c), """
            insert into enderecos_cliente (cliente_id, ponto_entrega_id, nome, principal, dispositivo_id)
            values (%s, %s, 'Casa', true, %s)""", (c, ponto, dados['dispositivo']))
        dados['ponto'] = ponto
        if empresa:
            bd.executar('endereco', self.cli(c), """
                insert into enderecos_cliente (cliente_id, ponto_entrega_id, nome, principal, dispositivo_id)
                values (%s, %s, 'Trabalho', false, %s)""", (c, empresa, dados['dispositivo']))
        return c

    def nova_empresa(self, nome, zona):
        """O primeiro colega cria na app o ponto de entrega da empresa (tipo empresa)."""
        lat0, lng0 = CENTROS[zona]
        primeiro = self.novo_cliente(zona=zona)
        p = self.bd.executar('ponto_empresa', self.cli(primeiro), """
            insert into pontos_entrega (tipo, lat, lng, zona_id, referencia, dispositivo_id)
            values ('empresa', %s, %s, %s, %s, %s) returning id""",
                             (lat0 + R.uniform(-0.01, 0.01), lng0 + R.uniform(-0.01, 0.01), self.zonas[zona], nome,
                              self.clientes[primeiro]['dispositivo']), um=True)
        self.bd.executar('endereco', self.cli(primeiro), """
            insert into enderecos_cliente (cliente_id, ponto_entrega_id, nome, principal, dispositivo_id)
            values (%s, %s, 'Trabalho', false, %s)""", (primeiro, p, self.clientes[primeiro]['dispositivo']))
        self.clientes[primeiro]['empresa'] = p
        self.empresas.append({'ponto': p, 'nome': nome, 'zona': zona})
        return p
