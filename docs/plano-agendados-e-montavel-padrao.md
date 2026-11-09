# Agenda — Pedidos agendados (ecrã próprio) e prato montável padrão nas cozinhas novas

> Estado: **planeado / na agenda** (análise; ainda não implementado). App do operador + backend.

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

## Perguntas em aberto
1. O montável clonado nasce **desactivado** (recomendado) ou já activo?
2. O modelo é **sempre o da Viana**, ou o admin escolhe qual é o modelo?
3. Criar já o montável nas **9 cozinhas existentes** sem ele, ou só nas novas?
4. Nos agendados: a partir de quantas horas antes um pendente deve gerar alerta?
