---
numero: 42
titulo: A cascata passa a descontar pelo caminho de taxas resolvido, e a taxa de equilíbrio deixa de ser a mesma para todo ativo
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga com D1b até onde conseguir. Forneça a mesma lista ao final, rode as
  lentes e faça da melhor forma
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/fluxo_explicito.dart
  - docs/validacao/identidade_das_vias.md
substitui: []
---

## Contexto

A [decisão 41](041-custo-de-capital-realavancado-ano-a-ano.md) construiu
`LeveredCostOfCapital` e provou que a identidade entre as duas rotas do capital
próprio fecha — de 4,2% para menos de 1e-6 — quando o custo de capital é
resolvido ano a ano contra a alavancagem. Nada disso estava ligado à produção:
`PrepareValuationInputs` calculava o `β_U` e o descartava, e a cascata seguia
descontando por interpolação de dois pontos.

## Decisão

**`ValuationInputs.unleveredBeta` passa a existir e a ser preenchido**, com o
`ShrunkBeta.unlevered` que a [decisão 40](040-beta-encolhido-por-precisao.md)
produz.

**A via da firma passa a descontar pelo caminho resolvido.** A cascata chama
`LeveredCostOfCapital.solve` depois de ter o fluxo-base e usa `wacc` como
`discountRatePath` e `terminalWacc` como taxa da perpetuidade.

**O recuo é declarado, não silencioso.** Sem `β_U`, sem convergência do ponto
fixo, ou com falha do solucionador, vale a interpolação de dois pontos — e o
resultado diz qual dos dois caminhos valeu e por quê.

**O aviso traz a curva, não só o número.** Ele declara o WACC do primeiro ano,
o do último, o da perpetuidade, e **quanto a participação do capital próprio se
moveu** no intervalo — que é exatamente o que a taxa única não enxergava.

## Consequências aceitas

**Cobertura de 117 dos 122 avaliados.** Cinco caem na interpolação.

**O efeito é redistribuição, e não deslocamento de nível.** Oitenta e um preços
justos se movem além de 0,5% e a **variação mediana é +0,0%**. O potencial
mediano vai de −38,6% para −37,3%, e os positivos de 30 para 27. O motor deixou
de tratar todo ativo como se a alavancagem fosse constante, e cada um foi para
o lado que a própria estrutura de capital manda: MOTV3 +268,0%, SBSP3 +147,7%,
PGMN3 −78,1%, MGLU3 −76,1%.

**A taxa de equilíbrio deixou de ser a mesma para todo mundo.** O delta do
desconto terminal tem mediana nula e p90 de +2,94 p.p., subindo em 56 dos 117
e caindo nos outros 61 — porque a alavancagem cresce ao longo da projeção em
uns e encolhe em outros.

**A equity ainda vem de `EV − D`.** `DcfCalculator.equityFromFirm` continua sem
chamador em produção, e com ele continuam a amplificação por `1/participação`,
a pós-condição dos 20% e a mescla da
[decisão 38](038-transicao-continua-entre-as-vias.md). Trocar a ponte pela rota
derivada é o que os torna desnecessários, e é o que falta.

**O veredito de vantagem competitiva é medido contra a taxa interpolada**, não
contra a resolvida: ele é decidido antes do ponto fixo. O efeito é de segunda
ordem — o `λ` mediano é 0,0015 — mas é aproximação declarada, não exatidão.
Fechá-la exige dois passes do solucionador, e é trabalho à parte.

**A via do acionista sobre LPA continua** como modelo independente para quem
não é banco, e a discordância que a
[decisão 39](039-as-duas-vias-sao-modelos-independentes.md) mediu continua com
ela.

**Todo preço justo da via da firma muda.** Números publicados ficam defasados
de novo.

**A alternativa descartada** era ligar o solucionador **e** a rota derivada de
uma vez. Recusada por risco: são duas mudanças de efeito grande, e juntas
esconderiam qual delas produziu qual movimento — que é exatamente o erro que a
decisão 37 e a 38 ensinaram a evitar.
