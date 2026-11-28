# Plano — Cadeado opcional da conta (PIN + biometria)

> Reforço de segurança **opcional** na app do cliente. O login continua a ser por
> telemóvel + OTP (SMS); este cadeado protege a app **já aberta** neste aparelho.
> Decidido com o dono do produto. Estado: **implementado (11/11/2026)** na app cliente
> (`src/lib/cadeado.ts`, `cadeadoContexto.tsx`, `EcraCadeado.tsx`, `app/conta/cadeado.tsx`); falta APK.

## 1. Objetivo
Dar ao utilizador a hipótese de **proteger a app com um código (PIN) e/ou biometria**.
Se ativar, a app pede o código/biometria para abrir e antes de ações sensíveis.
Se **não** ativar, fica tudo aberto exatamente como hoje (sem fricção).

## 2. Problema que fecha (threat model)
- O OTP protege o **login** (precisa do telemóvel + SMS).
- Mas depois de entrar, a **sessão fica aberta muito tempo**. Quem apanhar o
  telemóvel **desbloqueado** pode abrir o Manda Bué e: ver moradas, ver o saldo
  do Convida, fazer pedidos, **pedir levantamento** e **apagar a conta**.
- Este cadeado fecha exatamente essa janela (telemóvel desbloqueado / partilhado).
- **Não** é uma password de login nem muda a autenticação no servidor — é um
  **cadeado deste aparelho** (local). Complementa o já existente
  *"Proteger a conta — sair em todos os dispositivos"*.

## 3. Decisões travadas
1. **Quando pede:**
   - **Ao abrir a app** (arranque a frio) — sempre, se o reforço estiver ligado.
   - **Ao voltar ao primeiro plano** após um período em segundo plano
     (grácia por defeito: **60 s**; configurável no código).
   - **Antes de ações sensíveis**, mesmo com a app já desbloqueada:
     - **Pedir levantamento** (Convida e Ganha).
     - **Apagar a conta**.
2. **Métodos:** **PIN (4–6 dígitos)** como base obrigatória do reforço +
   **biometria** (impressão digital / Face) **operacional** por cima:
   - Se o aparelho tem biometria registada e o utilizador a ativou, o desbloqueio
     tenta **biometria primeiro**, com o **PIN como alternativa** sempre disponível.
3. **Opcional e reversível:** desligado por defeito; liga/desliga em "Conta".
4. **Nunca tranca de fora (recuperação):** *"Esqueci o código"* → re-entrar por
   **OTP (SMS)** remove/repõe o cadeado. O número de telemóvel é a raiz de confiança.
5. **Âmbito:** **só app cliente**. **Zero** mudanças de backend/base de dados.

## 4. Fluxos (UX)
### 4.1 Ativar (em "Conta")
- Novo item: **"Proteger com código / biometria"** (interruptor, desligado por defeito).
- Ao ligar → ecrã *"Criar código"* (digitar + confirmar 4–6 dígitos).
- Se o aparelho suportar biometria → pergunta *"Usar também a impressão digital/Face?"*.
- Guardado → volta a "Conta" com o reforço ativo e um subtexto
  *"A app pede o código ao abrir e antes de levantamentos."*

### 4.2 Desbloquear (abrir a app / voltar ao 1.º plano)
- Ecrã de cadeado por cima de tudo (overlay), com a marca.
- Se biometria ativa → dispara o prompt biométrico automaticamente.
- Sempre com **teclado de PIN** como alternativa (*"Usar código"*).
- Sucesso → remove o overlay. A sessão Supabase **não** é tocada.

### 4.3 Ação sensível (levantamento / apagar conta)
- Antes de confirmar, pede **biometria ou PIN** (reutiliza o mesmo verificador).
- Cancelar → não executa a ação.

### 4.4 Esqueci o código
- Link no ecrã de cadeado → *"Sair e entrar por SMS"* → `signOut()` +
  limpa o cadeado local → fluxo normal de OTP. Ao reentrar, o reforço fica
  desligado (pode voltar a ativar).

## 5. Arquitetura técnica
### 5.1 Bibliotecas a adicionar (Expo managed)
- `expo-local-authentication` — biometria (hardware + enrolled + authenticate).
- `expo-secure-store` — guardar o **hash** do PIN e as definições no
  Keychain (iOS) / Keystore (Android), nunca em texto simples.
- `expo-crypto` — derivar o hash do PIN (SHA-512 com sal aleatório por instalação).
  (Já há `@react-native-async-storage/async-storage`, mas **o segredo não vai para
  AsyncStorage** — só SecureStore.)

### 5.2 Armazenamento (SecureStore)
- `cadeado.activo` = "1"/"0"
- `cadeado.sal` = sal aleatório (base64, gerado na criação do PIN)
- `cadeado.hash` = `SHA-512(sal + PIN)` (verificador; o PIN nunca é guardado)
- `cadeado.biometria` = "1"/"0"
- `cadeado.tentativas` = contador de falhas (para o atraso progressivo)
- Estado "desbloqueado nesta sessão de foreground": **só em memória** (nunca persiste).

### 5.3 Onde encaixa
- Novo módulo `src/lib/cadeado.ts`: `estaActivo()`, `definirPin()`, `removerPin()`,
  `verificarPin(pin)`, `biometriaDisponivel()`, `pedirBiometria()`,
  `tentarDesbloquear()`, `registarFalha()`/`limparFalhas()`.
- Novo componente `src/components/EcraCadeado.tsx` (overlay de desbloqueo).
- Encaixe no **`SessaoProvider`** (`src/lib/sessao.tsx`) — já ouve o
  `AppState` (foreground). Adicionar:
  - estado `bloqueado: boolean` e `desbloquear()`.
  - ao arrancar com sessão + reforço ativo → `bloqueado = true`.
  - no `AppState` → `active` após ≥ 60 s em background → `bloqueado = true`.
  - expor `bloqueado` no contexto; o `app/_layout` renderiza o `EcraCadeado`
    por cima quando `bloqueado`.
- Novo hook `confirmarComCadeado()` para ações sensíveis (chamado no botão de
  **levantamento** e no de **apagar conta**); se o reforço estiver desligado,
  resolve logo `true` (sem fricção).

### 5.4 Ecrãs/pontos a tocar
- `src/app/(tabs)/conta.tsx` — novo item + navegação para gerir o cadeado.
- Novo `src/app/conta/cadeado.tsx` — criar/remover PIN, alternar biometria.
- `src/lib/sessao.tsx` — estado de bloqueio + grácia de foreground.
- `src/app/_layout.tsx` — render do overlay quando bloqueado.
- Ecrã/ação de **levantamento** (Convida) — `confirmarComCadeado()` antes de pedir.
- Ação **apagar conta** — `confirmarComCadeado()` antes de confirmar.

## 6. Segurança do PIN
- PIN é curto (4–6 díg.) → **força bruta** é o risco. Mitigação:
  - **Atraso progressivo** por tentativas erradas (ex.: 5 erros → espera; 10 →
    força *"Esqueci o código"* / re-login OTP).
  - Verificador com **sal por instalação** + SHA-512 (sem PIN em claro).
- É cadeado **local** (de aparelho): não protege contra extração do token por um
  atacante com acesso root ao telemóvel — protege o caso realista (telemóvel
  desbloqueado nas mãos de outra pessoa). Para ações financeiras, o passo extra
  antes do **levantamento** acrescenta uma barreira mesmo nesse caso.

## 7. Casos-limite
- **Sem biometria no aparelho** → só PIN (a opção de biometria nem aparece).
- **Biometria removida/alterada no SO** → cai para PIN automaticamente.
- **Esquecer o PIN** → recuperação por OTP (secção 4.4). Nunca há *lockout* total.
- **Vários aparelhos** → cada aparelho tem o seu cadeado (local). O
  *"sair em todos os dispositivos"* continua a ser a reposição ao nível da conta.
- **Trocar de utilizador no mesmo telemóvel** → ao sair, limpar o cadeado local.

## 8. Testes
- Unitários: `verificarPin` (certo/errado, sal, atraso por tentativas),
  `estaActivo`, transição de bloqueio no `SessaoProvider`.
- Manuais no APK: ligar reforço → fechar/abrir app pede código; background >60 s
  pede código; levantamento e apagar conta pedem código/biometria; "esqueci" faz
  re-login por SMS; aparelho sem biometria mostra só PIN.

## 9. Fora de âmbito (não-objetivos)
- **Password Supabase / login por email+password** (não acrescenta sobre o OTP).
- Sincronizar o cadeado entre aparelhos (é propositadamente local).
- Alterações de backend, RLS ou migrações (**nenhuma**).

## 10. Entrega
- Implementação **só na app cliente**; sem tocar na produção/DB.
- Opcional: esconder atrás de uma funcionalidade (`funcionalidades`) para rollout
  gradual — não é obrigatório, já que vem desligado por defeito.
- Gerar APK do cliente **só com autorização explícita**, como habitual.
