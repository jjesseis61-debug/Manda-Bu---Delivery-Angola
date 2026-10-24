# Marca

- **Cliente — Cozinha da Alexandra:** no espírito do KFC (marca de comida à volta de uma pessoa real),
  na paleta **vermelho + branco + preto** (apetite, limpeza, herança). Um só símbolo em todo o lado —
  **quadrado vermelho + prato branco + retrato a traço (preto) da fundadora** — usado no ícone, no
  logótipo e no letreiro. Há uma **versão abstrata** (anel + monograma **A**) para o ícone
  monocromático/temático do Android, onde um retrato a uma só cor não funciona. "Manda Bué" aparece
  só como endosso discreto ("entregue por Manda Bué"), nunca com símbolo próprio.
- **Operador — Manda Bué:** anel com o monograma **MB** e três **linhas de velocidade** douradas à
  esquerda — a camada de logística/entrega (carvão).

O **dourado não entra na marca do cliente** — fica reservado a **realce funcional** na app (selos,
"Prato do dia", estrelas): paleta-base curta + uma cor de ação, como nas grandes marcas.

| Ficheiro | Uso |
|---|---|
| `simbolo.svg` / `simbolo.png` | Símbolo da marca — retrato da Alexandra (quadrado vermelho + prato) |
| `simbolo-abstrato.png` | Versão abstrata (anel + A), p/ monocromático/usos a uma cor |
| `simbolo-operador.png` | Símbolo da app do operador — Manda Bué (fundo carvão, anel vermelho) |
| `logotipo.svg` / `logotipo.png` | Logótipo horizontal da Cozinha da Alexandra, fundo transparente |
| `logotipo-fundo-claro.png` | Logótipo horizontal sobre branco |
| `letreiro.png` | Letreiro vertical (montra, menus, marketing, Play Store, redes) |

> Uso da imagem da fundadora mediante a sua autorização. As fotos-base foram fornecidas pelo negócio.

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
| Dourado (fundo) | `#F4B400` | Selos ("Prato do dia"), sempre com texto escuro: 9,4:1; realce funcional (não entra na marca do cliente); linhas de velocidade do símbolo do operador |
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
