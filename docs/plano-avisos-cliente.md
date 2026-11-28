# Avisos do cliente: sino na app/PWA e notificações push na web

> Estado: **implementado (11/11/2026)** — migração `20261114000000_avisos_cliente_push_web.sql`,
> função `enviar-notificacoes` (Web Push), ecrã `avisos.tsx`, `lib/pushWeb.ts`, `public/sw.js`.

## A. Sino do cliente
- Ícone 🔔 no topo de todos os separadores, com contador de não lidos; abre **Avisos**.
- Mostra os mesmos avisos que saem por push (pedido, Convida, mensagens do apoio...), com o texto.
- Abrir o sino marca tudo como visto; tocar num aviso abre o ecrã certo.
- Funciona na app instalada e na PWA.

## B. Push na web (PWA)
- Em **Avisos**, a PWA mostra «Ligar avisos» (pede autorização ao navegador).
- Android/Chrome: no navegador e na PWA instalada. **iPhone: só com a PWA no ecrã principal**
  (iOS 16.4+); o ecrã explica como.
- O navegador regista uma assinatura Web Push (`dispositivos_push`, app = `web`); a função
  `enviar-notificacoes` envia-as por Web Push (chaves VAPID) e as da app pela Expo, como antes.
- Assinaturas que o navegador abandona (404/410) são desactivadas sozinhas. Sair da conta desliga.

## Chaves VAPID (sem intervenção humana)
- A função `enviar-notificacoes` **gera o par de chaves na 1.ª execução** e guarda-o em
  `segredos_servidor` (só o servidor lê). A chave privada **nunca passa por pessoas, pela
  conversa nem pelo repositório**.
- A app pede só a **chave pública** (`chave_publica_push_web`, com sessão).
- Os segredos `VAPID_PUBLICA` / `VAPID_PRIVADA` da função, se um dia forem definidos, têm prioridade.
