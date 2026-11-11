# Agenda — Pedidos agendados (ecrã próprio) e prato montável padrão nas cozinhas novas

> Estado: **implementado (11/11/2026)** no código — migração `20261111000000_montavel_padrao_agendados.sql`,
> ecrã `agendados.tsx` do operador. **Falta aplicar a migração à produção e criar o montável nas 9 cozinhas
> existentes** (ambos só com autorização), e um APK novo do operador.
>
> **Fase 2 (11/11/2026, `20261121000000_agendados_fase2.sql`):** alertas por pedido (prato fora do horário,
> doses insuficientes para o dia, hora cheia — `parametros.agendados_por_hora_max`), **reagendar** com aviso
> ao cliente, **exportar CSV** e indicadores no relatório (nº, valor, cancelados, a horas, antecedência,
> horas mais pedidas). Fica para depois: mapa do dia (cada pedido já abre no Google Maps). "Atribuir estafeta antecipadamente" não se faz: a reserva expira;
> atribui-se quando o pedido entra na fila.

---

## Parte 1 — Ver todos os pedidos agendados

### 1.1 O que existe hoje
- Em **Pedidos e entregas** há um cartão **"Agendados (N)"** com uma linha por pedido:
  data/hora · cliente · pratos · zona. Filtra por cozinha.
- O servidor (`pedidos_agendados`) só devolve os que estão a **mais de 90 min** (os outros já
  entram na fila normal), estados pendente/confirmado.
- **Falta**: telefone, morada completa e mapa, opções dos pratos uma por linha, observações,
  valor a receber, estado, filtros por dia, e **acções** (confirmar, ligar, imprimir, cancelar).

### 1.2 Proposta
Um botão **"📅 Pedidos agendados"** em Pedidos que abre um **ecrã próprio**.

**Filtros:** Hoje · Amanhã · Esta semana · Escolher datas · cozinha · zona · estado.
Mostrar também os que **já entraram na fila** (menos de 90 min), marcados como "na fila".

**Organização:** agrupado **por dia → por hora** (ex.: "Amanhã · 11:00–12:00 · 4 pedidos ·
32.400 Kz"), com o total de pedidos e de valor por grupo.

**Cada pedido mostra:**
| Campo | Porquê |
|---|---|
| Hora agendada + "faltam 3 h 20 min" | Prioridade visual |
| Nº curto (#A1B2C3) e estado (pendente/confirmado) | Igual ao talão |
| Cliente · **Ligar** · **WhatsApp** | Confirmar ou avisar o cliente |
| Morada completa · zona · **Abrir no Google Maps** | Planear a entrega |
| Pratos com as **opções uma por linha** e "SEM ..." | A cozinha prepara sem dúvidas |
| Observações (destacadas) | Pedidos especiais |
| **A receber** (descontos, saldo usado), pacote/empresa | O estafeta leva troco certo |
| Grupo / empresa, se for o caso | Entrega conjunta |

**Acções por pedido:** confirmar antecipadamente · imprimir talão (cozinha/entrega) ·
atribuir estafeta antecipadamente · avisar o cliente (lembrete) · cancelar com motivo.

### 1.3 O que um especialista acrescentaria
1. **Lista de produção** (o mais útil para a cozinha): para o dia ou para uma faixa horária,
   o total a preparar por prato **e por opção** — ex.: *"Amanhã até às 13h: 12 Arroz,
   8 Frango, 5 Funge, 3 Salada"*. Serve para **compras, doses e mise en place**. Imprimível.
2. **Alertas**:
   - agendado ainda **pendente** perto da hora (ex.: 3 h antes) → ligar ao cliente;
   - agendado para um dia/hora em que a **cozinha está fechada** ou o prato fora de horário;
   - **doses** do dia insuficientes para o que está agendado;
   - **capacidade** da faixa horária ultrapassada (muitos pedidos à mesma hora).
3. **Mapa do dia**: os agendados no mapa, para agrupar entregas por zona/rota.
4. **Lembretes automáticos**: ao cliente no dia (push "o teu pedido chega às 11h") e à
   cozinha X min antes (já entram na fila 90 min antes — mantém-se).
5. **Exportar/imprimir** a lista do dia (PDF) e CSV.
6. **Indicadores** (para o relatório da cozinha): nº e valor de agendados, % cancelados,
   % entregues a horas, horas mais procuradas para agendar.
7. (Futuro) **Reagendar** a pedido do cliente, com registo no histórico.

### 1.4 Técnico
- Alargar `pedidos_agendados(p_inicio, p_fim, p_cozinha)`: telefone, morada (referência,
  zona, lat/lng), itens com `opcoes`/`componentes_excluidos`, observações, estado,
  descontos, empresa/grupo, e flag "já na fila". Mesmas permissões de `pedidos_operador`.
- Nova RPC `lista_producao(p_cozinha, p_inicio, p_fim)` → totais por prato e por opção.
- Reutilizar o gerador de talões (`talao.ts`) e a impressão já robusta.
- Testes pgTAP (filtros, permissões, totais da lista de produção) + jest do ecrã.

---

## Parte 2 — Prato montável padrão em cada cozinha nova

### 2.1 Situação
- Criar uma cozinha (operador) é um `insert` simples em `cozinhas`; **não cria cardápio**.
- Hoje (09/11): das 11 cozinhas, **só a Viana (2) e o Kilamba (1)** têm prato montável;
  9 não têm.

### 2.2 Proposta
**Sempre que se cria uma cozinha, o sistema clona automaticamente o prato montável modelo**
("Serve o teu próprio prato") para ela. O operador encontra-o pronto e só ajusta.

- **No servidor** (trigger `after insert on cozinhas`), para funcionar venha a cozinha
  de onde vier (app, painel, importação).
- **Prato modelo**: o montável marcado como modelo pelo admin (ex.: parâmetro
  `cardapio_modelo_montavel`); por defeito o "Serve o teu próprio prato" da **Viana**.
  Assim, melhorar o modelo melhora as cozinhas novas, sem depender de uma cozinha concreta.
- **O que se copia**: o prato (nome, descrição, foto, categoria, preço base, valor mínimo),
  os **grupos** (nome, mínimo, máximo, ordem) e as **opções** (nome, preço extra, ordem, foto).
  Não se copiam: vendas, avaliações, doses, horários.
- **Nasce desactivado** ("rascunho"), com aviso em Cardápio: *"Prato montável criado a partir
  do modelo — revê opções e preços e activa."* Assim uma cozinha nova **não vende opções que
  não faz** antes de as rever.
- **Fotos**: reutilizam o mesmo endereço público do modelo; se a cozinha trocar a foto,
  passa a ter a sua (caminho próprio `opcoes/<id>/…`).

### 2.3 O que um especialista acrescentaria
1. **Também para as cozinhas existentes sem montável** (as 9): um botão em Cardápio
   **"Criar prato montável a partir do modelo"** (e/ou uma acção única para todas, com autorização).
2. **Escolher o modelo**: "copiar de outra cozinha" (ex.: Kilamba em vez de Viana), útil
   quando há variantes regionais.
3. **Não duplicar**: se a cozinha já tiver um montável com o mesmo nome, não cria outro.
4. **Registo na auditoria** ("prato montável clonado do modelo X").
5. **Checklist de cozinha nova**: além do montável, lembrar foto da cozinha, horários,
   zonas, contactos — e só aparecer aos clientes quando estiver completa.

### 2.4 Técnico
- Migração nova: função `clonar_montavel(p_cozinha, p_modelo default null)` (SECURITY DEFINER,
  **não** chamável pelas apps directamente — só pelo trigger e por um wrapper com
  `exigir_permissao`), trigger `after insert on cozinhas`, parâmetro do modelo.
- Respeita `funcionalidade_activa('pratos_montaveis')`.
- Entra no teste `12_privilegios`; testes pgTAP: cozinha nova recebe o prato desactivado com
  os mesmos grupos/opções; não duplica; cozinha sem modelo definido não falha.
- Aplicar à produção **só com autorização**; o "preencher as 9 cozinhas existentes" é uma
  acção separada, também com autorização.

---

## Decisões (dono do produto, 09/11/2026)
1. **O montável clonado nasce desactivado** (rascunho) — a cozinha revê e activa.
2. **O administrador escolhe o prato modelo** (ecrã de parâmetros/cardápio do admin);
   enquanto não escolher, usa-se o "Serve o teu próprio prato" da Viana.
3. **Criar também nas 9 cozinhas existentes** sem montável (acção única, aplicada à
   produção com autorização no momento da implementação), além das cozinhas novas.
4. **Alerta de agendado por confirmar** (recomendação adoptada):
   - **3 h antes** da hora agendada, se o pedido ainda estiver **pendente**;
   - se as 3 h caírem **fora do turno** da cozinha (parâmetros `turno_hora_inicio`/`fim`,
     hoje 9h–23h), o alerta sai **no início do turno** (ex.: entrega às 10h → alerta às 9h);
   - agendado feito com **menos de 3 h** de antecedência → alerta **imediato**;
   - alerta **urgente** quando entra na fila (90 min antes) e continua pendente;
   - as 3 h ficam num **parâmetro editável** (`alerta_agendado_horas`, por defeito 3).
