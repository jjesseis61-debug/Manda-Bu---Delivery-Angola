# Simulação de 12 meses

Põe o Manda Bué a funcionar durante um ano inteiro numa base de dados **local**, nunca na
produção. Corre com o relógio do Postgres a avançar dia a dia. Cada pessoa usa as mesmas tabelas e
funções que as apps usam, com o seu papel e as regras de acesso (RLS):

- os clientes registam-se, convidam amigos, pedem, pagam com pacote ou saldo, avaliam e reclamam;
- as cozinhas confirmam, preparam, cancelam e avisam atrasos;
- os estafetas entregam e enviam os comprovativos;
- o gerente abre e fecha a caixa, regista sangrias, repõe o stock, marca turnos e responde a reclamações;
- as finanças confirmam pacotes, revêem ganhos e pagam levantamentos;
- o administrador liga as funcionalidades e muda preços e parâmetros.

As tarefas do pg_cron correm à hora marcada e as notificações são "enviadas" pelo serviço.

O que acontece ao longo do ano (`simular.py`, `marcos`):

| Dia | Acontecimento |
|---|---|
| 0 | Lançamento: 1 cozinha, 25 primeiros clientes; Convida e Ganha, avaliações e destaques |
| 21 | Reconhecimento da equipa, contadores de zona, "pessoas como tu" |
| 30 | Pacotes pré-pagos (Semana e Mês) |
| 45 | Doses do dia da muamba às sextas |
| 60 | Várias cozinhas (2.ª cozinha), pedidos de grupo em 3 empresas, perfil da cozinha |
| 90 | Pratos montáveis ("Monta o teu prato") e acompanhamento da entrega |
| 120 | Fraude: 6 contas falsas com o código de um cliente (3 no mesmo telemóvel, 3 na mesma casa) |
| 140, 230, 320 | Clientes apagam a conta |
| 150 | 3.ª cozinha e uma empresa nova |
| 180 | Preço da muamba sobe |
| 210 | Ganho por pedido do Convida e Ganha 100 → 150 Kz (só nas novas ligações) |
| 240 | 4.ª cozinha |
| 300–307 | Uma cozinha em pausa por obras |

Ao longo do ano há também clientes que cancelam, cozinhas que cancelam com motivo, atrasos,
estornos, diferenças de caixa, comprovativos rejeitados, doses esgotadas, grupos sem pedidos e
clientes que deixam de pedir.

Os agentes com Claude não são chamados: as tarefas criam os casos e os planos, que ficam à espera.

## Correr

```bash
apt-get install -y faketime && pip install "psycopg[binary]"
# Cluster de simulação na porta 5433, com o relógio controlado por um ficheiro
pg_createcluster 16 sim -p 5433
cat >> /etc/postgresql/16/sim/environment <<'E'
LD_PRELOAD='/usr/lib/x86_64-linux-gnu/faketime/libfaketimeMT.so.1'
FAKETIME_TIMESTAMP_FILE='/var/lib/sim_relogio/relogio'
FAKETIME_NO_CACHE='1'
FAKETIME_DONT_FAKE_MONOTONIC='1'
E
mkdir -p /var/lib/sim_relogio && echo '+0s' > /var/lib/sim_relogio/relogio
pg_ctlcluster 16 sim start
su postgres -c "psql -p 5433 -c 'create role root superuser login'"

# Base "sim" com todas as migrações (UTF-8), depois o ano, as verificações e o relatório
createdb -p 5433 -E UTF8 -T template0 sim   # e aplicar supabase/local/supabase_shim.sql + migrações
python3 simular.py 365
python3 verificar.py
python3 relatorio.py
```

- `motor.py`: o relógio, as sessões (como a app, o serviço ou o pg_cron) e a agenda de eventos.
- `mundo.py`: a equipa, as cozinhas, o cardápio com receitas, o stock e os clientes.
- `operacao.py`: o dia a dia (pedidos, caixa, pacotes, grupos, Convida e Ganha, avaliações, reclamações, fraude).
- `simular.py`: o calendário do ano e o plano de cada dia.
- `verificar.py`: as verificações (dinheiro, stock, pacotes, ganhos, notificações, grupos, doses, cancelamentos).
- `relatorio.py`: os números, o fecho de cada mês, a fraude, a privacidade, o desempenho e as filas dos agentes.
