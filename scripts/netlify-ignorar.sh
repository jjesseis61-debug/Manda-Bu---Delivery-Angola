#!/usr/bin/env bash
# O Netlify deixou de ser usado (decisão do dono, 28/11/2026): a app web publica-se no Cloudflare Pages
# (.github/workflows/web.yml, domínio www.mandabue.com.ao). Este script diz sempre ao Netlify para NÃO
# compilar, nem pré-visualizações nem o site principal, mesmo com [publicar] no commit.
#   exit 0 → o Netlify cancela a build
echo "Netlify desligado: a app web publica-se no Cloudflare Pages. Não compila."
exit 0
