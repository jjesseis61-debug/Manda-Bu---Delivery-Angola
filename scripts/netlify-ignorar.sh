#!/usr/bin/env bash
# Decide se o Netlify compila o site (PWA do cliente). Poupa créditos.
#   exit 0 → NÃO compila (o Netlify cancela a build)
#   exit 1 → compila
# Regras (decisão do dono, 17/11/2026):
#   1. Pré-visualizações dos PRs (deploy-preview): nunca compila.
#   2. Site principal: só compila quando o último commit traz [publicar] na mensagem
#      (publicação em lote, a pedido, em vez de a cada envio).
if [ "${CONTEXT:-}" = "deploy-preview" ] || [ "${PULL_REQUEST:-}" = "true" ]; then
  echo "Pré-visualização de PR desligada (poupar créditos): não compila."
  exit 0
fi
if git log -1 --pretty=%B | grep -q '\[publicar\]'; then
  echo "Commit com [publicar]: compila e publica o site."
  exit 1
fi
echo "Sem [publicar] no commit: não compila (o site só se publica a pedido)."
exit 0
