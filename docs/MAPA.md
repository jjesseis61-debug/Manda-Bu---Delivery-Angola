# Mapa — OpenStreetMap grátis + interruptor do Google

## Como funciona agora

A app do cliente mostra sempre um mapa (acompanhar a entrega e marcar o ponto de entrega),
**sem precisar de chave, faturação nem cartão**:

- **Por defeito:** mapa **OpenStreetMap** (grátis), através da biblioteca MapLibre. Funciona no
  Android e no iOS.
- **Interruptor `mapa_google`** (no painel do operador, em *Parâmetros e interruptores*),
  **desligado** de origem. Só quando o ligas — e **se** o build tiver a chave do Google Maps
  (Android) ou no iOS (Apple Maps) — a app troca para o Google/Apple Maps. Sem chave, mesmo com o
  interruptor ligado, continua no OpenStreetMap (nunca fica em branco).

Assim deixaste de depender do cartão e do Google Cloud para o mapa funcionar. A chave do Google
passou a ser **opcional** — um "upgrade" estético, não um requisito.

## O que é preciso para entrar na app

O MapLibre tem código nativo, por isso só entra na app **no próximo build (APK)**. Até lá, o
código está pronto e testado, mas o APK atual ainda mostra o mapa antigo.

## Fornecedor de tiles

Por defeito a app usa o **OpenFreeMap** (`https://tiles.openfreemap.org/styles/bright`): tiles
vetoriais de dados OpenStreetMap, **sem API key, sem limites e com uso comercial permitido**, feito
para apps. (O servidor público de tiles do próprio OpenStreetMap **bloqueia o uso por apps**, por
isso não se usa diretamente — daria mapa em branco.)

Se um dia quiseres garantir disponibilidade contratual, podes apontar para um fornecedor próprio
(ex.: MapTiler ou Stadia Maps, com plano gratuito e **sem cartão**) definindo, no build, a variável
`EXPO_PUBLIC_MAPA_TILES_URL` no formato raster `https://.../{z}/{x}/{y}.png`. A app passa a usá-la
sem mudar código.

## Dois "gates" independentes (OSM por base, Google cirúrgico)

A app está pronta para os dois mapas, com **fallback total**: faltando qualquer chave, corre 100% em
OpenStreetMap/MapLibre.

- **Gate A — mapa visível.** Por defeito OSM/MapLibre. Com a chave `GOOGLE_MAPS_ANDROID_API_KEY` no
  build e o interruptor `mapa_google` ligado, troca para Google (Android) / Apple Maps (iOS). Sem
  chave, continua em OSM mesmo com o interruptor ligado. (Já configurado no `app.config.js`.)
- **Gate B — rota/ETA.** Por defeito o tempo é estimado pela distância em linha recta. Com o
  interruptor `rota_google` ligado **e** a chave `GOOGLE_ROTAS_API_KEY` no servidor (secret), a
  edge function `rota-estafeta` calcula a rota por estrada com trânsito (Google Directions), guarda-a
  em `rotas_estafeta` (cache) e o `posicao_entrega` usa-a enquanto recente (< 2 min); a app mostra a
  **linha da rota** no mapa e "Rota por estrada, com trânsito". Sem a chave ou com o interruptor
  desligado, volta tudo à estimativa.

O Gate B vive no servidor (edge function + secret), por isso **liga-se/desliga-se sem APK novo**; só o
Gate A (mapa visível em Google) é que precisa de build com a chave nativa. Para controlar o custo, o
Gate B só corre com o pedido a caminho e pede a rota ao Google no máximo 1×/minuto por pedido.

## Detalhe técnico

- `apps/cliente/src/lib/mapaEstilo.ts` — estilo raster do OpenStreetMap (atribuição "© OpenStreetMap").
- `apps/cliente/src/lib/mapaNativo.ts` — `GOOGLE_DISPONIVEL` (há chave/plataforma?) e `HA_MAPA`.
- `apps/cliente/src/components/MapaPontos.tsx` e `MapaPin.tsx` — escolhem OSM ou Google conforme o interruptor.
- `supabase/migrations/20261006090000_mapa_osm.sql` — cria o interruptor `mapa_google` (desligado).
  Nota: a app usa OSM mesmo sem esta linha; a linha serve só para o operador poder **ligar** o Google.
