---
numero: 156
titulo: A curva de acumulação da Meta é o piloto dos gráficos da Bklit UI, e os outros gráficos continuam no Recharts até a comparação
status: aceita
origem: voce
data: 2026-10-28
citacao: >
  Conseguimos refinar os gráficos usando a Bklit UI?
afeta:
  - src/ui/charts/bklit/
  - src/features/goal/accumulation-chart.tsx
  - src/router.tsx
  - src/styles.css
  - package.json
  - THIRD_PARTY_NOTICES.md
  - test/ui/accumulation-chart.test.tsx
substitui: []
---

## Contexto

A decisão 155 deixou a Bklit UI para uma decisão própria. Ela não é pacote: é
um registro shadcn que copia o código dos gráficos para o repositório, sobre
visx 4 e d3. Hoje quatro gráficos usam Recharts: a evolução e o risco ×
retorno do Backtest, a curva de acumulação da Meta e a rosca de setores do
Estudo. Três caminhos foram postos: um piloto num gráfico, o estilo da Bklit
imitado nos Recharts, ou a troca dos quatro de uma vez. A escolha foi o piloto
na curva de acumulação.

## Decisão

**A curva de acumulação passa a ser desenhada pelo gráfico de linha da Bklit;
os outros três ficam no Recharts até a comparação dizer se vale migrá-los.**

1. Entram no repositório, em `src/ui/charts/bklit/`, os 64 arquivos que o
   gráfico de linha alcança (linha, grade, eixos e tooltip), e nada mais. São
   três mudanças mecânicas em relação ao original, descritas no `README.md`
   da pasta.
2. Entram cinco pacotes do visx 4 (`curve`, `event`, `grid`, `scale`, `shape`),
   `d3-array` e `d3-shape`. A Bklit também pede `@base-ui/react` (alpha) e
   `@number-flow/react`, mas só para peças que o piloto não usa, e eles ficam
   de fora.
3. O tema vem das variáveis `--chart-*` que a Bklit lê, apontadas para os
   tokens do Equisim na classe `.bklit-chart`. Nenhuma cor nova entra.
4. A moldura continua a nossa (`ChartFrame`), com legenda e alternância para
   tabela. A tabela segue sendo a via do valor exato e de quem não enxerga a
   cor.
5. O eixo da Bklit é de datas, e o da curva é de prazo. Cada ponto ganha uma
   data sintética, a 30 dias por mês, que só o posiciona: o eixo e o tooltip
   dizem o prazo ("5a", "2 anos e 6 meses"), e nenhuma data aparece.
6. O gráfico da Bklit prende o toque (`touch-action: none`) para arrastar. Aqui
   não há arrasto, e o toque volta a rolar a página (`pan-y`).
7. A Meta passa a ser carregada sob demanda, como o Backtest: o código da Bklit
   só desce para quem abre a Meta.

## Consequências aceitas

- **Peso**: o pedaço da Meta tem 41 kB (gzip), quase todo do código da Bklit.
  A primeira carga do aplicativo não cresce: com o Raio-X e a Meta fora do
  pacote do roteador, ela fica cerca de 3 kB menor que antes da decisão 155.
- **Dois motores de gráfico convivendo** até a comparação. É o preço de medir
  antes de trocar.
- **Código de terceiros para manter**: o que foi copiado não recebe correção
  sozinho. Atualizar é copiar de novo a mesma lista e reaplicar as três
  mudanças. O projeto de origem é de 2026 e tem um mantenedor.
- **Descartado o caminho do Next.js**: a diretiva `"use client"` sai, porque o
  Vite não a usa.
- Se o piloto for aprovado, a evolução do Backtest é a próxima candidata: o
  eixo dela já é de datas, o caso de uso para o qual o gráfico de linha da
  Bklit foi feito.
