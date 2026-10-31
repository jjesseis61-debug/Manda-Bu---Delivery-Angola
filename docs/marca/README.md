# Marca

Há duas assinaturas, uma por app, com a mesma linguagem gráfica (anel = tacho/prato visto de cima,
traço contínuo, dourado de realce) e as cores que lembram a bandeira de Angola sem a copiar
(vermelho, carvão e dourado).

- **Cliente — Cozinha da Alexandra:** anel com o monograma **A** (de Alexandra) ao centro e **vapor
  dourado** a subir — comida quente de casa. "Manda Bué" aparece só como endosso discreto
  ("entregue por Manda Bué"), nunca com símbolo próprio a competir.
- **Operador — Manda Bué:** anel com o monograma **MB** e três **linhas de velocidade** douradas à
  esquerda — a camada de logística/entrega.

| Ficheiro | Uso |
|---|---|
| `simbolo.svg` / `simbolo.png` | Símbolo da app do cliente — Cozinha da Alexandra (fundo vermelho) |
| `simbolo-operador.png` | Símbolo da app do operador — Manda Bué (fundo carvão, anel vermelho) |
| `logotipo.svg` / `logotipo.png` | Logótipo horizontal da Cozinha da Alexandra, fundo transparente |
| `logotipo-fundo-claro.png` | Logótipo horizontal sobre branco |
| `simbolo-icone.svg` | Fonte do ícone da app do cliente (1024 × 1024) |

Os desenhos são gerados por `gerar.py` (produz os SVG + `lista.json`) e rasterizados por `render.js`
com o Chromium/Playwright (`node render.js`, transparência correta). Os ícones, o ícone adaptativo do
Android (zona segura de 72 %) e o splash das apps estão em `apps/*/assets/`, gerados a partir destes
desenhos. Os assets do operador mantêm a marca MB e não são alterados aqui.

> Logótipo provisório desenhado em código. Quando houver a versão definitiva de um designer (ou um
> logótipo que a Alexandra já use), substituir mantendo os nomes dos ficheiros.

## Cores

| Papel | Cor | Notas |
|---|---|---|
| Marca | `#B5121B` | Botões principais, separador activo; branco por cima: 6,85:1 |
| Marca escura | `#8C0E15` | Estado carregado |
| Marca clara | `#FBE9EA` | Botões leves ("Adicionar"), texto vermelho por cima: 5,85:1 |
| Carvão | `#1F1A17` | Fundo da app do operador e do seu ícone |
| Dourado (gráfico) | `#B07800` | Estrelas e molduras sobre branco: 3,8:1 |
| Dourado (fundo) | `#F4B400` | Selos ("Prato do dia"), sempre com texto escuro: 9,4:1; vapor (cliente) e linhas de velocidade (operador) dos símbolos |
| Texto | `#1A1A1A` | 17,4:1 |
| Texto suave | `#5F6368` | 6,05:1 |
| Contorno de campos | `#8A8A8A` | 3,45:1 (visível ao sol) |
| Divisórias | `#E0E0E0` | Só decorativo |
| Erro | `#B3261E` | Sempre com ícone ⚠ e barra lateral; o texto do erro fica escuro |
| WhatsApp | `#075E54` | Texto branco: 7,7:1 |

## Regras

- Vermelho cheio só para a acção principal de cada ecrã; nas listas, botões leves.
- O símbolo precisa de espaço livre à volta de pelo menos a altura das linhas douradas.
- Não esticar, rodar nem mudar as cores do símbolo; sobre fotos, usar o símbolo dentro do quadrado vermelho.
- Logótipo provisório: substituir quando houver a versão definitiva de um designer, mantendo os nomes dos ficheiros.
