# Plano — cor por estado nas entregas do estafeta

> Estado: **IMPLEMENTADO** em 2026-11-03 (`apps/estafeta/src/app/inicio.tsx`). Decidido com o Jesse em 2026-11-03.
> Motivo: no ecrã do estafeta está "tudo muito parecido" (todos os cartões no mesmo
> cinzento #F5F5F5). A cor deve destacar o que há **para fazer agora**.

## Decisão: tratamento **Híbrido** (fundo tingido + faixa de cor à esquerda)

Só muda os cartões das **entregas por fazer** (lista "Entregas de hoje").
A secção **"Feitas hoje"** fica **sempre cinzenta/apagada** (já estão feitas).

| Estado da entrega | Fundo do cartão | Faixa esquerda (6px) |
|---|---|---|
| **A caminho** (`em_entrega`) | `marcaClara` **#FBE9EA** (rosa da marca) | `marca` **#B5121B** |
| **Atrasado** (hora prometida já passou, qualquer estado ativo) | `erroFundo` **#FDECEA** (vermelho-claro) | `erro` **#B3261E** |
| **Em preparação / Confirmado** | `fundoSuave` **#F5F5F5** (cinzento) | `destaque` **#B07800** (dourado) |

- **"Atrasado" tem prioridade** sobre o estado (um `em_entrega` atrasado usa o visual de atrasado).
- Mantém-se sempre o **rótulo** ("A caminho"/"Em preparação") e o texto — a cor **nunca** é o único sinal (acessibilidade/daltonismo, legibilidade ao sol).

## Onde mexer (implementação futura)
- `apps/estafeta/src/app/inicio.tsx` — no `.map` das entregas, calcular o estilo do `Cartao`
  por estado (fundo) e acrescentar a faixa à esquerda (ex.: `borderLeftWidth: 6, borderLeftColor: …`,
  com `estilo` passado ao componente `Cartao`, que aceita `ViewStyle`).
- Reutilizar os tokens de `src/lib/tema.ts` (`marcaClara`, `erroFundo`, `fundoSuave`, `marca`, `erro`, `destaque`).
- Não mexer no backend. Implica **novo APK**.

## Comparação visual
Render de referência (antes vs Opção A faixa vs Opção B fundo) foi partilhado no chat em 2026-11-03.
O escolhido é o **híbrido** = Opção A + Opção B combinadas.
