# Manda Bué — app do cliente

Expo (SDK 57) com Expo Router e TypeScript. Backend: o projecto Supabase descrito em `../../supabase/`.

## Preparar

```bash
cd apps/cliente
npm install
cp .env.example .env   # preencher EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY
npx expo start
```

`.env` não vai para o repositório. Só valores públicos da app (URL e chave publicável); a chave secreta /
`service_role` nunca entra na app.

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `src/app/` | Rotas do Expo Router: cada ficheiro é um ecrã; `_layout.tsx` define a navegação |
| `src/lib/supabase.ts` | Cliente Supabase (sessão guardada no AsyncStorage, renovação só em primeiro plano) |

Código que não é ecrã (componentes, hooks, utilitários) fica fora de `src/app/`, com o atalho `@/` para `src/`.

## Ligações (deep link)

Esquema `mandabue://` (em `app.json`), para os convites do programa de indicação da I2.

## Verificações

```bash
npm run typecheck                       # TypeScript
npx expo export --platform android      # empacota o JavaScript sem compilar a app nativa
```

## Regras (secção 15 do `PROJECTO_CRESCIMENTO_MANDA_BUE.md`)

- O servidor calcula todos os valores; a app só mostra o que o servidor devolve.
- Nenhum valor fixo no código: tudo vem de `parametros` e `funcionalidades`.
- Nenhum dado fictício na interface.
