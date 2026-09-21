# O beta e a estrutura de capital da perpetuidade — item B15

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata.
>
> ```bash
> dart run tool/gabarito_cascata.dart     # congela a entrada
> dart run tool/perpetuidade.dart         # grava perpetuidade.json
> ```
>
> Montagem conferida contra o gabarito ativo a ativo: zero divergências.

## 0. O apontamento, e o que dele sobrou

A lente `metodo` disse em 15/09/2026 que a taxa de equilíbrio troca **só** a taxa
livre de risco: o mesmo beta e, na via da firma, o WACC com o peso e a dívida de
hoje. Um estado estacionário com o beta e a alavancagem do ano da avaliação é
premissa não declarada, e ela pesa onde metade do valor mora.

**Metade disso caiu com a
[decisão 105](../decisoes/105-o-aplicativo-resolve-o-prior-do-beta-e-o-custo-de-capital.md).**
O aplicativo passou a resolver o caminho de taxas: a alavancagem de equilíbrio é
a que a projeção alcança no **ano N**, e não a de hoje. Sobra o beta, que
continua sendo o de hoje — janela de cinco anos, encolhido em direção ao prior
transversal — e vai à perpetuidade sem convergir.

## 1. A alavancagem do ano N é praticamente a de hoje

| `D/E` | p25 | mediana | p75 | n |
|---|---:|---:|---:|---:|
| hoje | 0,00 | 0,29 | 1,25 | 99 |
| no ano N, o do modelo | 0,09 | 0,64 | 1,37 | 83 |
| mediana do setor da B3, hoje | 0,04 | 0,34 | 0,56 | 99 |

As duas primeiras linhas são de conjuntos diferentes — só 83 dos 102 resolvem as
taxas —, e comparar medianas de conjuntos diferentes engana. **Ativo a ativo**,
nos 80 em que as duas existem, a diferença mediana é de **−0,01**, e a
alavancagem sobe em 24 deles.

O modelo não produz uma alavancagem fugindo para o infinito ao longo da
projeção: ele chega a um ponto perto de onde partiu. A mediana setorial da B3,
para comparação:

| setor | `D/E` mediano |
|---|---:|
| bens-industriais | 0,04 |
| consumo-cíclico | 0,56 |
| consumo-não-cíclico | 0,74 |
| financeiro | 0,00 |
| materiais-básicos | 0,22 |
| petróleo, gás e biocombustíveis | 0,83 |
| saúde | 0,34 |
| utilidade pública | 0,95 |

## 2. Convergir o beta não move nada, e a razão é que ele já convergiu

Blume leva o beta em direção a 1: `β_∞ = 0,67·β + 0,33`. Aplicado **só** à taxa
de equilíbrio — a corrente continua sendo o beta observado, que é o que o dado
mede:

| | mediana | p10 | p90 |
|---|---:|---:|---:|
| efeito na taxa de equilíbrio | **−0,0%** | −0,9% | +0,5% |
| efeito no preço justo | **+0,1%** | −1,5% | +2,8% |

Sobe em 56 de 102.

**O que a perpetuidade usa não é o `beta` do CAPM.** Com o caminho de taxas
resolvido, o beta de equilíbrio é o **desalavancado realavancado na estrutura do
ano N** — `β_U · fator(D_N/E_N)`. Ele coincide com o beta de hoje só porque a
§1 mostrou que `D_N/E_N` é praticamente `D_0/E_0`: as duas medições se sustentam
uma na outra.

**E o encolhimento já faz o trabalho.** A [decisão 40](../decisoes/040-beta-encolhido-por-precisao.md)
puxa o beta de cada ativo em direção ao prior transversal por precisão, e o prior
realavancado fica perto de 1: o beta mediano que chega ao preço é **0,955**, e
`0,67 × 0,955 + 0,33` dá 0,97. Blume por cima de um beta já encolhido é um ajuste
sobre um ajuste, e ele encontra pouco a fazer.

Onde há efeito é nas caudas — p90 de +2,8% —, e ali são os poucos ativos cujo
beta ficou longe de 1 mesmo depois do encolhimento.

## 3. Impor a mediana do setor move menos, e custa avaliação

| | mediana | p10 | p90 |
|---|---:|---:|---:|
| efeito na taxa de equilíbrio | **0,0%** | −2,0% | +1,1% |
| efeito no preço justo | **0,0%** | −3,7% | +5,9% |

E **5 dos 102 deixam de ser avaliados**: a alavancagem imposta quebra o ponto
fixo do custo de capital em ativos cuja estrutura real está longe da mediana do
setor.

## 4. O que se decidiu

[Decisão 109](../decisoes/109-a-perpetuidade-declara-de-onde-vem-o-beta-e-a-estrutura-e-nao-os-converge.md):
**declarar a origem das duas pontas, e não adotar nenhuma das alternativas.**

- `ValuationDiagnostics.terminalEquityShare` passa a carregar a estrutura de
  capital com que a perpetuidade é descontada — a do ano N, quando as taxas são
  resolvidas.
- As duas alternativas ficam como imposição de diagnóstico
  (`terminalBetaWeightOverride`, `terminalLeverageOverride`), para que a próxima
  leitura não refaça a pergunta sem instrumento.

## 5. O que isto não diz

- **Não diz que o beta de cinco anos é o certo para a perpetuidade.** Diz que a
  correção clássica não muda o número **neste universo**, porque o encolhimento
  já aproxima o beta do mercado por outro caminho — e por um que tem erro-padrão
  a justificá-lo. Num universo em que o prior desalavancado se afaste de 1, a
  conclusão muda, e o instrumento fica pronto.
- **Não mede a alavancagem de equilíbrio contra o que as companhias fazem.** A
  mediana setorial de hoje é a única referência usada, e ela é a de um instante.
- **A imposição de `D/E` não move o prêmio de crédito.** Ele sai da alavancagem
  observada sobre o EBITDA, que é fato do exercício, e não da estrutura que se
  está supondo — de modo que a varredura mede o efeito pela taxa, e não pelo
  custo da dívida.
