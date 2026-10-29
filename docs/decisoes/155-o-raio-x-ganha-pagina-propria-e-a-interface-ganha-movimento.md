---
numero: 155
titulo: O Raio-X ganha página própria com Voltar, e a interface ganha movimento curto pelo Motion, com peças da Kokonut UI e profundidade em CSS
status: aceita
origem: voce
data: 2026-10-28
citacao: >
  Conseguimos adicionar umas animações do motion.dev pra deixar mais clean?
  [...] O que podemos usar da Kokonut UI? Eu acessei um site que chama
  linear.app e achei ele lindo, pois tem uns componentes visuais em 3D [...]
  Quem sabe a gente não consegue retirar esse "raio-x" da mesma aba e separar
  ele em uma nova guia ou tomar a página com o voltar
afeta:
  - src/router.tsx
  - src/main.tsx
  - src/styles.css
  - src/ui/motion.tsx
  - src/ui/segmented.tsx
  - src/ui/engine-loading.tsx
  - src/ui/tilt.tsx
  - src/ui/ticker-logo.tsx
  - src/ui/sheet.tsx
  - src/features/asset/asset-page.tsx
  - src/features/asset/asset-xray.tsx
  - src/features/asset/section-index.tsx
  - src/features/shell/app-shell.tsx
  - src/features/shell/use-open-asset.ts
  - src/features/shell/command-palette.tsx
  - src/features/study/portfolio-column.tsx
  - src/features/study/asset-picker-sheet.tsx
  - src/features/backtest/per-asset-card.tsx
  - src/features/valuations/valuations-page.tsx
  - src/features/manual/manual-page.tsx
  - scripts/capture-screens.ts
  - docs/motor/07-aplicativo.md
  - THIRD_PARTY_NOTICES.md
  - test/ui/motion.test.tsx
substitui: []
---

## Contexto

O Raio-X abria numa folha lateral por cima da área corrente, pelo parâmetro
`?ativo=PETR4`, com no máximo 820 px de largura. A avaliação inteira (leitura,
régua, faixa, modelo, sensibilidade, pares, projeção, ressalvas) se empilhava
nessa coluna estreita. O pedido foi tirá-lo dali para uma página com Voltar, e
dar à interface o acabamento visual de produtos como o Linear, antes do
trabalho de linguagem para iniciantes.

Quatro bibliotecas foram avaliadas no código-fonte, em 28/10/2026:

- **Motion** (`motion`, MIT) já estava no `package.json` desde a decisão 152 e
  nenhum arquivo o importava.
- **Kokonut UI** (MIT) é um registro shadcn de componentes que dependem de
  `motion` e `lucide-react`, que o projeto já tem.
- **Linear**: a profundidade vem de superfícies em degraus, degradê desfocado e
  brilho, que o CSS faz com `perspective` e `rotateX/rotateY`.
- **Bklit UI** (MIT) troca o desenho dos gráficos por visx e d3. Um gráfico de
  linha arrasta 64 arquivos e 12 mil linhas, com sete pacotes novos. Fica para
  uma decisão própria.

## Decisão

**O Raio-X passa a ser a página `/ativo/:ticker`, e a interface ganha movimento
curto, sempre subordinado à preferência de movimento reduzido.**

1. A página tem cabeçalho com Voltar, logo, nome, setor e a entrada no estudo.
   O Voltar devolve pelo histórico a quem chegou navegando, e leva ao Estudo
   quem abriu o link direto, o mesmo critério de Simular minhas premissas, cujo
   Voltar, sem histórico, agora leva à página do ativo.
2. Todo lugar que abria a folha navega para a página. Um `?ativo=` antigo, em
   qualquer área, redireciona para ela, sem ficar no histórico.
3. No computador, um índice lateral lista as seções que a página mostra e marca
   a que está à vista. O clique rola sem mexer na URL, para o Voltar continuar
   devolvendo de onde a pessoa veio.
4. O movimento é o do Motion, em `LazyMotion` estrito: só o componente `m`, com
   os recursos `domAnimation` no pacote principal. `MotionConfig
   reducedMotion="user"` corta transformação e layout para quem pediu menos
   movimento.
5. **Conteúdo nunca depende de JavaScript para aparecer.** A área que esmaece
   ao trocar de endereço e os cartões do Raio-X em cascata são animação CSS.
   Uma animação do Motion só avança a cada quadro de tela, e numa aba em
   segundo plano não há quadro: com `opacity: 0` de partida, a página ficava
   invisível. As capturas mostraram isso nas telas abertas por endereço.
6. Entram pelo Motion: os números da leitura contando até o valor (só na tela:
   o leitor de tela lê o valor final, uma vez), a placa do controle segmentado
   que desliza e, enquanto o motor avalia, as etapas da cascata em texto,
   adaptadas do AI Text Loading da Kokonut UI.
7. A profundidade à moda do Linear é CSS. O cartão da leitura inclina até 3°
   seguindo o mouse, com brilho no tom do veredito. Há também uma aura da marca
   atrás do cabeçalho do ativo, e a logo grande ganha volume. Nada disso
   responde ao toque nem ao movimento reduzido.

## Consequências aceitas

- **O Raio-X deixa de abrir por cima da área.** Quem estava no Estudo sai dele
  para ver o ativo, e o Voltar é o caminho de volta. O ganho é a largura da
  tela inteira, o índice das seções e o endereço próprio.
- **Peso no build**: o pacote principal cresce cerca de 30 kB (gzip) com o
  Motion e os recursos de animação. Baixar os recursos à parte foi descartado:
  um pedaço que falha (rede, ou a aba aberta antes de uma publicação pedindo o
  pedaço velho) deixaria parado no estado inicial tudo o que é `m.*`. Em
  troca, o Raio-X e a Meta saem do pacote do roteador para pedaços próprios,
  e a primeira carga fica do tamanho que era antes (ver a decisão 156).
- **Código adaptado de terceiros**: o carregamento do motor vem do AI Text
  Loading da Kokonut UI, sob MIT, e a licença está em `THIRD_PARTY_NOTICES.md`.
  O índice de seções e a placa deslizante seguem ideias da Kokonut, mas foram
  escritos aqui.
- **Descartados**: three.js e React Three Fiber, por centenas de kB e GPU para
  algo decorativo, sem dado que fique mais claro em três dimensões. Também o
  catálogo de efeitos da Kokonut (fundos animados, textos-espetáculo, botões
  lúdicos), porque movimento que não explica compete com o número. E o
  `domMax` do Motion: a placa deslizante mede e anima `x` e `width` em vez de
  usar animação de layout.
- **As capturas da lente `tela`** pedem movimento reduzido ao navegador, para a
  foto pegar o estado final, e não um quadro no meio da animação.
- **Nenhum número muda.** O motor em `src/core` não é tocado. A linguagem para
  iniciantes fica para depois, e a página nova tem lugar para ela: uma frase de
  abertura por seção e um glossário no trilho lateral.
