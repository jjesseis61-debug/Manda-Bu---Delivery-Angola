# Auditoria — App do cliente para web (PWA) + decisão PWA vs Nativo

> Análise/auditoria técnica, não é plano de implementação. Feita com o Jesse em 2026-11-07.
> Contexto: fazer o link do embaixador converter no iPhone (e em quem não tem app) sem App Store.

## Parte A — Decisão: PWA vs App tradicional (nativa/híbrida)

**Recomendação: estratégia híbrida, por função.**

| App | Trabalho dela | Recomendação |
|---|---|---|
| **Cliente** | Alcance, converter links do WhatsApp, iPhone, zero-install | **PWA (web-first)** + manter APK Android |
| **Operador** | Caixa, câmara, uso intensivo em loja | **Nativo** (mantém) |
| **Estafeta** | Localização em background, offline, fiabilidade | **Nativo** (mantém) — PWA iOS não dá background location |

Porquê PWA para o cliente: zero instalação, abre do WhatsApp, **funciona no iPhone sem App Store**,
deep-links são só URLs, e o Expo exporta web a partir do mesmo código. Porquê nativo para
operador/estafeta: precisam de capacidades de dispositivo (localização em background, câmara, offline
fiável) que a web — sobretudo iOS — ainda não dá bem.

Notas atuais (2026): iOS web push só desde 16.4 e **só com a PWA "adicionada ao ecrã inicial"**; execução
em background ainda é limitada no iOS. Sem compras in-app (dinheiro/Multicaixa/Unitel) → **sem taxa de 30%
da App Store**. Fontes consultadas: Progressier (PWA vs Native 2026), Ecomize (PWA no iPhone 2026),
MagicBell, YSMP.

## Parte B — Auditoria técnica (com build real)

**Veredito: ~80% pronta. Compila e exporta para web HOJE.**
`npx expo export --platform web` → sucesso (`dist/` gerado, bundle ~1,8 MB). A app já foi construída a
pensar na web.

### Já reaproveita (sem trabalho)
- **Navegação/rotas:** `expo-router` corre na web.
- **Mapas:** já têm variantes **`MapaPin.web.tsx` / `MapaPontos.web.tsx`** (mostram texto) + flag
  `HA_MAPA = Platform.OS !== 'web'` em `lib/mapaNativo.ts`. Todas as telas usam estes componentes
  (cozinha, enderecos/novo, AcompanharEntrega, ComoChegar) — nenhuma importa `maplibre` direto.
- **Push:** `lib/push.ts` já tem `if (Platform.OS === 'web') return` → não rebenta (sem push na web).
- **Comprovativo PDF:** `lib/comprovativo.ts` já tem ramo web (`Print.printAsync`).
- **Resto:** Supabase, AsyncStorage (→ localStorage), expo-image-picker (→ file input), clipboard.
- `react-native-web` e a secção `web` (output "single") já estão no projeto.

### Gaps (o que falta)
1. **Empacotamento PWA** (pequeno): o export é um SPA, não PWA. Falta `manifest.webmanifest`
   (nome, ícones, `display: standalone`, cor) + **service worker** (instalável + offline).
2. **Escolher morada sem mapa** (médio — único gap funcional): na web, `enderecos/novo` depende do
   **geolocation do browser**. Sem permissão/GPS não há como marcar o ponto (não há mapa para tocar nem
   pesquisa de morada). Precisa de **fallback**: pesquisa de endereço/geocoding ou reutilizar ponto conhecido.
3. **Deep-link `/p/{id}?r=`** (pequeno): ligar à captura de indicação (`ligarIndicacao`). A rota
   `convite/[codigo]` já existe; falta a rota do prato com código (ou reusar convite + redirecionar).
4. **Open Graph por prato** (pequeno, separado): o SPA não dá OG por prato; precisa de prerender/função
   edge que sirva meta-tags por `/p/{id}` (para o cartão do WhatsApp).
5. **Hospedagem:** `mandabue.ao` + HTTPS (Netlify/Vercel/Cloudflare Pages servem SPA + função edge p/ OG).
6. **Opcional:** otimizar bundle (1,8 MB → code-splitting/gzip) para dados caros; push web real (hoje
   no-op; fallback SMS/WhatsApp).

### Ordem sugerida
1. Resolver a **morada na web** (pesquisa/fallback) — o único gap funcional.
2. **Empacotar PWA** (manifest + service worker).
3. **Hospedar** em `mandabue.ao` + **OG do prato** + **deep-link `?r=`**.
4. iPhone e quem não tem app passam a pedir no **Safari/PWA**, com o código do embaixador a aplicar-se.

> Não é reescrita — é integração + 1 ajuste de UX. Liga a `docs/plano-embaixador.md` (deep-link/mensagem).
