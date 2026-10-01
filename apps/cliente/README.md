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
| `src/app/` | Rotas (Expo Router). `index` decide entre entrar, registo e início |
| `src/app/entrar.tsx`, `registo.tsx` | Entrada por SMS e registo (com o campo do código de convite, C2) |
| `src/app/(tabs)/` | Início (cardápio, C7, linha "Hoje na…" do C8), Pedidos, Convida e Ganha (C1), Conta |
| `src/app/carrinho.tsx` | Checkout: endereço, orçamento do servidor, C2, saldo do programa |
| `src/app/pedido/[id].tsx` | Estado do pedido; com `fim=1` é o fim de pedido (C6) |
| `src/app/levantar.tsx`, `como-funciona.tsx`, `cozinha.tsx` | C4, regras (4.13), C8 |
| `src/app/enderecos/` | C11: lista e novo endereço (pin no mapa, Casa/Trabalho, bairro, referência) |
| `src/app/convite/[codigo].tsx` | Link de convite: guarda o código para pré-preencher C2 |
| `src/lib/` | Cliente Supabase, chamadas ao servidor (`api.ts`), sessão e interruptores, carrinho, push, formatação |
| `src/components/` | Componentes de interface |

O servidor calcula todos os valores: preços, taxa de entrega, desconto, saldo e ganhos vêm do Supabase. Os
interruptores são lidos ao arrancar e sempre que a app volta ao primeiro plano; uma funcionalidade desligada não
mostra ecrãs nem botões.

## Push

`src/lib/push.ts` regista o token Expo no servidor depois do registo. Precisa de `extra.eas.projectId` em
`app.json` (criado com `npx eas-cli init`) e de uma *development build* no Android. Sem `projectId` não faz nada.

## Ligações (deep link)

Esquema `mandabue://` (em `app.json`), para os convites do programa de indicação da I2.

## Verificações

```bash
npm run typecheck                       # TypeScript
npm test                                # testes unitários (formatação, regras, mensagens)
npx expo export --platform android      # empacota o JavaScript sem compilar a app nativa
```

## Regras (secção 15 do `PROJECTO_CRESCIMENTO_MANDA_BUE.md`)

- O servidor calcula todos os valores; a app só mostra o que o servidor devolve.
- Nenhum valor fixo no código: tudo vem de `parametros` e `funcionalidades`.
- Nenhum dado fictício na interface.
