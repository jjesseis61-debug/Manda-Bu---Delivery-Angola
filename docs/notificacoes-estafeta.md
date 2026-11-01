# Notificações push no estafeta — passo-a-passo (Expo + Firebase)

As notificações do estafeta usam a mesma base que o operador: o telemóvel regista um
**token Expo** (via `registar_token_push_funcionario`) e o servidor envia pela função
`enviar-notificacoes`. Para o APK do estafeta **receber** push faltam 3 coisas de
configuração que só se fazem fora do repositório. Este guia é esses passos.

> O código do repositório já está pronto (`app.config.js`, `push.ts` e o workflow do APK).
> As notificações passam a chegar assim que existirem os dois segredos no fim deste guia.

Package da app: **`ao.mandabue.estafeta`** (tem de ser exactamente este em todo o lado).

### Links rápidos

| Passo | Link direto |
|---|---|
| Firebase Console | https://console.firebase.google.com/ |
| Firebase → Cloud Messaging (depois de escolher o projecto) | https://console.firebase.google.com/project/_/settings/cloudmessaging |
| Firebase → Contas de serviço (gerar a chave FCM) | https://console.firebase.google.com/project/_/settings/serviceaccounts/adminsdk |
| Expo (entrar / projectos) | https://expo.dev/ |
| GitHub → lista de segredos deste repositório | https://github.com/jjesseis61-debug/Manda-Bu---Delivery-Angola/settings/secrets/actions |
| GitHub → **criar** um segredo novo (atalho) | https://github.com/jjesseis61-debug/Manda-Bu---Delivery-Angola/settings/secrets/actions/new |

> Nos links do Firebase, o `_` escolhe automaticamente o projecto onde já estás. Se tiveres
> vários projectos, abre primeiro o Console e escolhe o projecto certo.

---

## Parte A — Firebase (ficheiro `google-services.json` + chave FCM)

Podes **reutilizar o mesmo projecto Firebase** que já usas para o cliente/operador — só
acrescentas lá uma app Android nova. (Se não tens nenhum, cria um projecto primeiro.)

1. Abre o [Firebase Console](https://console.firebase.google.com/) e entra no projecto.
2. **Engrenagem (⚙) → Definições do projeto → separador "Os teus apps" → Adicionar app → Android.**
3. Preenche:
   - **Nome do pacote Android:** `ao.mandabue.estafeta`
   - **Alcunha (opcional):** `Manda Bué Estafeta`
   - *(A "impressão digital SHA-1" não é precisa para notificações — podes deixar em branco.)*
4. Carrega em **Registar app** e depois em **Descarregar google-services.json**.
   Guarda esse ficheiro — vais precisar dele na Parte C.
   - ⚠️ Não precisas de mexer no Gradle nem seguir os passos "Adicionar SDK" que o Firebase
     mostra a seguir — o nosso build trata disso. Carrega só em "Seguinte / Continuar para a consola".
5. Confirma que o **Cloud Messaging** está ligado:
   **Definições do projeto → separador "Cloud Messaging"**
   (link direto: https://console.firebase.google.com/project/_/settings/cloudmessaging).
   Se aparecer *"Firebase Cloud Messaging API (V1)"* com estado **Ativado**, está bom.
6. Gera a **chave da conta de serviço** (é o que o Expo usa para entregar ao Google):
   **Definições do projeto → separador "Contas de serviço" → Gerar nova chave privada → Gerar chave**
   (link direto: https://console.firebase.google.com/project/_/settings/serviceaccounts/adminsdk).
   Descarrega esse JSON (nome parecido com `nome-do-projeto-firebase-adminsdk-xxxx.json`).
   - ⚠️ **Não é o mesmo** que o `google-services.json`. Este (`firebase-adminsdk…`) vai **para o
     Expo** (Parte B). O `google-services.json` vai para o GitHub (Parte C). Não troques os dois.

---

## Parte B — Expo (criar o projecto, obter o Project ID, ligar o FCM)

1. Entra em [expo.dev](https://expo.dev/) com a tua conta Expo (a mesma do operador serve).
2. **Projects → Create a Project.**
   - **Name:** `manda-bue-estafeta`
   - Cria. Vais parar à página do projecto.
3. Copia o **Project ID** (um código tipo `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`).
   Está no topo da página do projecto, ou em **Project settings**. Guarda-o para a Parte C.
4. Liga a chave FCM ao projecto Expo:
   **(no projecto) Credentials → Android → Service Account → FCM V1 service account key → Upload**
   e escolhe o ficheiro `…firebase-adminsdk….json` da Parte A, ponto 6.
   - Se te pedir um "Application identifier", usa `ao.mandabue.estafeta`.

---

## Parte C — Segredos no GitHub

No repositório: **Settings → Secrets and variables → Actions → New repository secret**
(atalho direto: https://github.com/jjesseis61-debug/Manda-Bu---Delivery-Angola/settings/secrets/actions/new).
Cria estes **dois**:

| Nome do segredo | Valor |
|---|---|
| `EXPO_PROJECT_ID_ESTAFETA` | o **Project ID** da Parte B, ponto 3 |
| `GOOGLE_SERVICES_JSON_ESTAFETA` | o conteúdo **inteiro** do `google-services.json` da Parte A, ponto 4 (do `{` inicial ao `}` final) |

⚠️ No `GOOGLE_SERVICES_JSON_ESTAFETA` cola o ficheiro **completo**. O workflow verifica que é
um JSON válido, que tem `project_info` e que contém o package `ao.mandabue.estafeta` — se
estiver cortado ou for o ficheiro errado, o build pára com uma mensagem a dizer o que falta.

---

## Parte D — Gerar o APK e testar

1. Pede-me para **gerar o APK do estafeta** (só o faço com a tua autorização). O workflow passa
   a usar os dois segredos automaticamente.
2. Instala o APK num telemóvel **real** (o push não funciona em emulador).
3. Abre a app, entra como um **funcionário com a permissão de entregas**, e **aceita** o pedido
   de notificações quando aparecer.
4. Confirmar que o token ficou registado (opcional) — posso correr esta verificação por ti, ou
   fazes no SQL Editor do Supabase:
   ```sql
   -- tokens de push de funcionários (o teu deve aparecer depois de entrares na app)
   select plataforma, left(token, 18) || '…' as token, activo, atualizado_em
   from dispositivos_push
   where funcionario_id is not null
   order by atualizado_em desc
   limit 5;
   ```
5. Dispara uma notificação de teste (um pedido novo atribuído, ou peço eu à função
   `enviar-notificacoes`) e confirma que chega ao telemóvel.

---

## Resumo do que faz o quê

| Peça | Onde | Serve para |
|---|---|---|
| `google-services.json` | segredo `GOOGLE_SERVICES_JSON_ESTAFETA` → APK | o Android reconhece o remetente FCM |
| Project ID do Expo | segredo `EXPO_PROJECT_ID_ESTAFETA` → APK | a app pede um token Expo válido |
| Chave FCM (adminsdk) | carregada no Expo | o Expo entrega as mensagens ao Google/FCM |

Se faltar uma destas, a app **compila na mesma** mas sai sem push — por isso é importante ter
as três antes de distribuir o APK a estafetas a sério.
