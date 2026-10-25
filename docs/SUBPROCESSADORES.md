# Subprocessadores e fornecedores de dados (registo interno)

> **Documento interno.** Não é mostrado aos clientes nem vai para as lojas.
> A política de privacidade pública descreve estes serviços **por categoria**
> (fornecedor de alojamento, serviços de notificações, fornecedor de SMS);
> este registo nomeia os fornecedores reais, para responder a um pedido formal
> (p. ex. da **APD — Agência de Proteção de Dados** de Angola) ou de um utilizador.
>
> **Nunca** pôr aqui chaves, segredos ou tokens — só nomes e papéis. Os segredos
> ficam fora do repositório (variáveis de ambiente / painel do fornecedor).

**Responsável pelo tratamento:** Cozinha da Alexandra (marca; entregue por Manda Bué).
**Última atualização:** 25 de Outubro de 2026.

## Fornecedores

| Papel | Fornecedor | O que trata | Observações |
|---|---|---|---|
| Alojamento + base de dados | **Supabase** (projeto `laruvuambdovnkojwrzp`) | Conta, pedidos, pagamentos, endereços, avaliações, auditoria | Acesso restrito por RLS (cada utilizador só vê os seus dados) e por permissões da equipa |
| Notificações push | **Expo** (serviço de envio) → **Google FCM** (Android) e **Apple APNs** (iOS) | Token do dispositivo e conteúdo da notificação | A Expo é o intermediário; a entrega final é da Google/Apple. O push não leva o código OTP |
| SMS / código de login (OTP) | **Nenhum fornecedor externo** no momento | Código de uso único | O OTP é **manual** (o operador entrega o código ao cliente). Atualizar esta linha se ligarem um provedor (ex.: Twilio, Africell) no painel do Supabase |
| Distribuição da app | **Google Play** (e Apple App Store, se publicarem no iOS) | Instalação e atualizações | Dados de conta de programador/loja geridos pelas próprias plataformas |

## Dados e retenção

- **Dados recolhidos:** nome, telefone, NIF (opcional), endereços/ponto de entrega,
  pedidos e pagamentos, avaliações e fotos que o cliente envia, token de push.
- **Não guardamos** dados de cartão de pagamento.
- **Apagar conta** (app → Conta → Apagar a conta): saem nome, telefone, NIF,
  endereços e o registo do telemóvel; pedidos e pagamentos ficam **sem o nome**,
  por obrigação contabilística da empresa.
- **Localização do estafeta:** só durante a entrega; o percurso não é guardado.

## Contacto de privacidade

Definido na app em `EXPO_PUBLIC_CONTACTO_PRIVACIDADE` (ver `apps/cliente/src/lib/empresa.ts`).

## Como manter isto verdadeiro

Sempre que mudar um fornecedor (trocar de alojamento, ligar um provedor de SMS,
publicar no iOS), **atualizar a tabela acima e a data**. A política pública fica
por categorias e normalmente não precisa de mudar; este registo é que acompanha
os fornecedores reais.
