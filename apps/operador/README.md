# Manda Bué — app do operador

Expo (SDK 57) com Expo Router e TypeScript; corre em Android e na web. Backend: o projecto Supabase descrito em
`../../supabase/`.

## Preparar

```bash
cd apps/operador
npm install
cp .env.example .env   # preencher EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY
npx expo start         # w = web, a = Android
```

`.env` não vai para o repositório. Só valores públicos (URL e chave publicável); a chave secreta / `service_role`
nunca entra na app.

## Entrada

Telefone + SMS. O administrador principal regista o número do funcionário (`definir_telefone_funcionario`); no
primeiro login, `ligar_funcionario()` liga a conta ao funcionário com esse número. Um número que não é de nenhum
funcionário vê "sem acesso". As permissões vêm do organograma (`meu_funcionario()`) e são relidas sempre que a app
volta ao primeiro plano.

## Ecrãs

| Rota | Ecrã | Permissão |
|---|---|---|
| `entregas` | E1: pedidos por ponto de entrega, estados, caixa e formas de pagamento | `entregas.registar` ou `pedidos.gerir` |
| `painel` | O1: custo, vendas de indicação, clientes novos, retenção, anulados, top | `indicacoes.ver` |
| `verificacao` | O2: ganhos em verificação por indicador | `indicacoes.verificar` |
| `levantamentos` | O3: aprovar, rejeitar, marcar pago | `indicacoes.aprovar_pagamentos` |
| `embaixadores` | O4: elegíveis e actuais | `plataforma.parametros` |
| `parametros` | O5: parâmetros e interruptores (com confirmação) | `plataforma.parametros` |
| `cozinhas`, `cozinhas/[id]` | O6: perfil da cozinha e cardápio | `cozinhas.gerir` |
| `relatorios` | O9: relatório por cozinha, CSV e PDF | `relatorios.exportar` |

`src/components/Guarda.tsx` esconde os ecrãs sem permissão; o servidor verifica sempre de novo. Todas as escritas
ficam na auditoria (funções do servidor e, em `cozinhas`/`cardapio`, um trigger).

## Verificações

```bash
npm run typecheck
npm test
npx expo export --platform android --platform web
```

## I5

| Rota | Ecrã | Permissão |
|---|---|---|
| `moderacao` | O7: comentários recentes (Ocultar/Mostrar) e palavras filtradas | `avaliacoes.moderar` |
| `equipa` | O8: métricas da semana por turno, reconhecimentos | `equipa.reconhecer` ou membro da cozinha (tem turnos) |

Push (N12): `src/lib/push.ts` regista o telemóvel do funcionário depois de entrar. Precisa de
`extra.eas.projectId` em `app.json` e de uma *development build* no Android.

## I6

| Rota | Ecrã | Permissão |
|---|---|---|
| `grupos` | O10: grupos do dia, resumo dos pratos, todos os pedidos de um grupo de uma vez | `pedidos.gerir` ou `entregas.registar` |
