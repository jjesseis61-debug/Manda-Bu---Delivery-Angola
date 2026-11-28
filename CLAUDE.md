# Manda Bué — instruções do projecto

- Responder sempre em português de Angola.
- Apps Expo em `apps/cliente`, `apps/operador`, `apps/estafeta`; base de dados Supabase em `supabase/`
  (migrações novas, nunca editar as já aplicadas; testes pgTAP em `supabase/tests`).

## Painel de especialistas (obrigatório)

Todas as análises, propostas e funcionalidades passam pelas cinco lentes de `docs/especialistas.md`:
**Albert Bandura**, **Robert Cialdini**, **Everett Rogers**, **C.K. Prahalad** e **B. F. Skinner**.
Numa análise, dizer o que cada um veria (pontos fortes, riscos e propostas concretas); numa
funcionalidade, aplicar a checklist desse ficheiro antes de a dar por terminada.

## Regras de trabalho

- Não gerar APKs nem aplicar SQL em produção sem autorização explícita para essa acção.
- O SQL de produção é aplicado pelo utilizador no SQL Editor (entregar numa caixa de código, em partes se for grande).
- Web (Cloudflare Pages, www.mandabue.com.ao): só publica com `[publicar]` na mensagem do commit ou a pedido no workflow `web.yml`; não publicar sem autorização. O Netlify está desligado.
- Pedidos de "análise" são só análise, sem implementar.
- Sem segredos no repositório.
