"""Motor da simulação: relógio do Postgres (faketime), sessões como as apps e agenda de eventos.

Cada acção corre numa transacção própria, com o papel e o utilizador que a app usaria
(authenticated + claims do JWT, service_role para as funções do servidor, superutilizador
para o pg_cron). O relógio do cluster de simulação avança para a hora de cada evento.
"""
import calendar
import collections
import heapq
import itertools
import json
import os
import random
import time
import traceback
import uuid
from datetime import datetime, timedelta, timezone

import psycopg
from psycopg.types.json import Jsonb

FICHEIRO_RELOGIO = '/var/lib/sim_relogio/relogio'
LUANDA = timezone(timedelta(hours=1))


def relogio(momento: datetime):
    """O Postgres do cluster de simulação passa a ver `momento` (com fuso)."""
    alvo = calendar.timegm(momento.astimezone(timezone.utc).timetuple())
    tmp = FICHEIRO_RELOGIO + '.tmp'
    with open(tmp, 'w') as f:
        f.write('+%ds\n' % (alvo - int(time.time())))
    os.replace(tmp, FICHEIRO_RELOGIO)


class ErroNegocio(Exception):
    """Erro devolvido pelo servidor (SQLSTATE e mensagem), como a app o veria."""

    def __init__(self, sqlstate, mensagem):
        super().__init__(f'{sqlstate}:{mensagem}')
        self.sqlstate = sqlstate
        self.mensagem = mensagem


class BD:
    def __init__(self, dsn):
        self.conn = psycopg.connect(dsn, autocommit=False)
        self.conn.execute("set application_name = 'simulacao'")
        self.conn.commit()
        self.agora = None
        # Contagens: acções feitas, erros esperados (regras de negócio) e inesperados (falhas)
        self.accoes = collections.Counter()
        self.esperados = collections.Counter()
        self.inesperados = []
        self.tempos = collections.defaultdict(list)

    def hora(self, momento):
        self.agora = momento
        relogio(momento)

    def _sessao(self, cur, quem):
        if quem is None:
            return
        tipo, uid = quem
        if tipo == 'servico':
            cur.execute("select set_config('request.jwt.claims', %s, true)", ('{"role": "service_role"}',))
            cur.execute('set local role service_role')
        else:
            cur.execute("select set_config('request.jwt.claims', %s, true)",
                        (json.dumps({'sub': str(uid), 'role': 'authenticated'}),))
            cur.execute('set local role authenticated')

    def executar(self, nome, quem, sql, params=None, esperados=(), um=False, todos=False):
        """Corre `sql` numa transacção como `quem`. Erros listados em `esperados` (mensagem ou
        SQLSTATE) contam como regras de negócio; os outros ficam registados como falhas."""
        self.accoes[nome] += 1
        t0 = time.perf_counter()
        try:
            with self.conn.transaction():
                cur = self.conn.cursor()
                self._sessao(cur, quem)
                cur.execute(sql, params)
                if um:
                    linha = cur.fetchone()
                    res = linha[0] if linha else None
                elif todos:
                    res = cur.fetchall()
                else:
                    res = None
            self.tempos[nome].append(time.perf_counter() - t0)
            return res
        except psycopg.Error as e:
            diag = e.diag
            estado, msg = diag.sqlstate or '?', (diag.message_primary or str(e)).strip()
            if msg in esperados or estado in esperados:
                self.esperados[f'{nome}: {msg}'] += 1
                raise ErroNegocio(estado, msg) from None
            self.inesperados.append({
                'accao': nome, 'quando': self.agora.isoformat() if self.agora else None,
                'sqlstate': estado, 'mensagem': msg, 'detalhe': diag.message_detail,
                'contexto': (diag.context or '')[:400], 'sql': sql[:300],
                'params': repr(params)[:300]})
            raise ErroNegocio(estado, msg) from None

    def valor(self, sql, params=None):
        """Leitura como superutilizador (para o guião decidir e para as verificações)."""
        with self.conn.transaction():
            cur = self.conn.cursor()
            cur.execute(sql, params)
            linha = cur.fetchone()
            return linha[0] if linha else None

    def linhas(self, sql, params=None):
        with self.conn.transaction():
            cur = self.conn.cursor()
            cur.execute(sql, params)
            return cur.fetchall()


class Agenda:
    """Eventos do dia por ordem de hora; um evento pode marcar outros."""

    def __init__(self):
        self.fila = []
        self.seq = itertools.count()

    def marcar(self, momento, accao, *args):
        heapq.heappush(self.fila, (momento, next(self.seq), accao, args))

    def correr(self, bd, ate):
        while self.fila and self.fila[0][0] <= ate:
            momento, _, accao, args = heapq.heappop(self.fila)
            bd.hora(momento)
            try:
                accao(*args)
            except ErroNegocio:
                pass
            except Exception:  # erro do próprio guião: registar e seguir
                bd.inesperados.append({'accao': getattr(accao, '__name__', str(accao)),
                                       'quando': momento.isoformat(), 'sqlstate': 'guiao',
                                       'mensagem': traceback.format_exc()[-1500:]})


def luanda(dia, hora, minuto=0, segundo=0):
    return datetime(dia.year, dia.month, dia.day, hora, minuto, segundo, tzinfo=LUANDA)


def novo_id():
    return str(uuid.uuid4())


__all__ = ['BD', 'Agenda', 'ErroNegocio', 'Jsonb', 'luanda', 'novo_id', 'relogio', 'LUANDA', 'random']
