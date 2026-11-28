# Teste fechado na Google Play — guia (Manda Bué)

Para publicar a app como **conta individual**, a Google exige um **teste fechado**:
**12 testadores inscritos de forma contínua durante 14 dias** antes de pedir o acesso a produção.

---

## Parte 1 — Mensagem para enviar aos 12 testadores

> Copia e cola (WhatsApp/SMS). Substitui `[LINK DO TESTE]` pelo link que o Play Console te dá.

```
Olá! 👋 Estamos a testar a app Manda Bué — Delivery Angola e preciso da tua ajuda.

É simples e grátis. Só preciso que:
1) Entres neste link com a tua conta Google (a mesma do teu telemóvel):
   [LINK DO TESTE]
2) Toques em "Tornar-me testador" / "Become a tester".
3) Instales a app pela Play Store (o link mostra o botão de instalar).

Depois, nos próximos 14 dias, abre a app algumas vezes e experimenta:
- criar a conta / entrar com o teu número;
- ver o cardápio e montar um pedido (não precisas de pagar nada);
- passear pelos ecrãs (Receitas, Convida e Ganha, Conta).

⚠️ MUITO IMPORTANTE: NÃO saias do teste nem desinstales durante os 14 dias.
Se faltares um dia ou dois, não faz mal — só não saias do programa de teste.

Qualquer coisa estranha que vejas, manda-me print. Obrigado! 🙏
```

---

## Parte 2 — O que é preciso do teu lado (administrador)

1. **Conta de programador** (individual) criada no Play Console (taxa única de **$25**, por cartão — sem cartões pré-pagos).
2. Cria uma faixa de **Teste fechado** (Closed testing) e sobe o **AAB** da app.
3. Adiciona os **12 testadores** por:
   - **lista de emails** (as contas Google deles), ou
   - um **Grupo Google** (adicionas o email do grupo).
4. Copia o **link de adesão** ("opt-in URL") e envia a mensagem da Parte 1.
5. Confirma que **12 ou mais** aceitaram (opt-in). O **relógio dos 14 dias** começa quando chegas aos 12.
6. Ao fim de **14 dias contínuos com ≥12 inscritos**, pede o **acesso a produção**.

### Regras de ouro
- Conta **apenas** estar **inscrito** (opted-in), não abrir todos os dias.
- **Não abrir 1–3 dias** não reinicia nada — desde que ninguém **saia** do teste.
- Se o número de inscritos **cair abaixo de 12** (alguém sai), o relógio **reinicia** quando voltares a 12.
- A Google quer ver **uso genuíno**: garante que **vários** testadores mexem mesmo na app (não 12 pessoas que só aceitaram e nunca abriram).
- **Pedidos reais pagos não são obrigatórios** — basta experimentar os fluxos.

### Antes de convidar os 12 — pensar no login
A app entra por **código SMS (OTP)**. Hoje o OTP é **manual** (o operador entrega o código).
Com 12 testadores a entrar ao mesmo tempo, isso pode ser um gargalo. Opções:
- ter alguém de prontidão a entregar os códigos no ecrã "Códigos de login" do operador; ou
- configurar um provedor de SMS real / números de teste no painel do Supabase antes do teste.

### Notas
- Para a **APK de teste direto** (link fixo que já usamos) **não é preciso** nada disto — instala-se
  diretamente. Os $25 + 12 testadores/14 dias são **só** para publicar na Play Store.
- As regras da Google mudam (já baixaram de 20 para 12 testadores). **Confirma sempre** na página
  oficial do Play Console antes de contar com datas.
