# A varredura do horizonte de projeção — item B6

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata.
>
> ```bash
> dart run tool/gabarito_cascata.dart   # congela a entrada
> dart run tool/horizonte.dart          # grava horizonte.json
> ```
>
> Montagem de dez anos conferida contra o gabarito ativo a ativo: **zero
> divergências**. As outras oito são, por construção, outra montagem — é o
> próprio objeto da medição.
>
> **Remedido depois da [decisão 119](../decisoes/119-a-rota-derivada-tambem-remunera-o-caixa-pela-taxa-livre-de-risco.md)**,
> que estendeu à rota derivada a separação do caixa que a decisão 113 fez no
> WACC. O preço justo caiu em 73 dos 97 e dois ativos saíram; os números abaixo
> são os de depois.

## 0. A pergunta

O horizonte explícito é fixo em **dez anos** para todo ativo, sem olhar ciclo,
setor ou maturidade, e nunca foi medido se dez é melhor que sete ou quinze.

O item pede a varredura «sobre o universo e sobre a habilidade». A perna da
habilidade exige reexecutar as coortes, que depende da base bruta (item C5); o
que se pode afirmar sem ela é a **correlação de postos** entre horizontes — e
ela responde pelo lado forte, porque uma ordenação que não se move não move um
`t`.

## 1. A varredura

| anos | avaliados | preço justo vs 10 anos (p25 / mediana / p75) | peso do terminal | postos vs 10 |
|---:|---:|---|---:|---:|
| 5 | **102** | −0,6% / **+0,8%** / +7,8% | **59,2%** | 0,9937 |
| 6 | 102 | −0,2% / +0,8% / +6,5% | 52,4% | 0,9968 |
| 7 | 101 | −0,2% / +0,6% / +4,6% | 44,8% | 0,9985 |
| 8 | 100 | 0,0% / +0,5% / +3,2% | 39,7% | 0,9994 |
| 9 | 97 | 0,0% / +0,2% / +1,7% | 34,6% | 0,9998 |
| **10** | **97** | — | **30,5%** | 1,0000 |
| 12 | 96 | −2,1% / −0,3% / 0,0% | 23,3% | 0,9988 |
| 15 | 95 | −4,5% / −0,9% / 0,0% | 15,9% | 0,9970 |
| 20 | 94 | −6,8% / −1,0% / 0,0% | **8,4%** | 0,9930 |

**Cinco anos contra vinte, nos 94 que os dois avaliam: postos de 0,9828.**

## 2. O achado: o nível não depende do horizonte, e a origem do valor depende

**A mediana do preço justo anda entre −1,0% e +0,8% de cinco a vinte anos.**
Quadruplicar a projeção explícita não move o ativo mediano.

**O peso do terminal vai de 59,2% a 8,4% no mesmo intervalo.** É a mesma
resposta, montada de maneiras muito diferentes.

**Isso não é acaso: é o terminal neutro funcionando.** `VT = lucro_{N+1} ÷ r`
afirma `RONIC_∞ = r`, de modo que o capital novo não cria valor e o crescimento
perpétuo sai da fórmula. Estender a projeção explícita transfere valor do
terminal para os fluxos **sem mudar o total** — que é exatamente o que um
terminal bem especificado tem de fazer. **A invariância ao horizonte é evidência
independente de que a construção do terminal está certa**, e ela não foi
buscada: saiu de uma varredura que perguntava outra coisa.

## 3. Onde o horizonte importa: nas caudas e na cobertura

A mediana não se move; as caudas sim.

| anos | p10 | p90 |
|---:|---:|---:|
| 5 | −3,3% | **+21,3%** |
| 10 | — | — |
| 20 | **−23,3%** | +3,0% |

**Horizonte curto empurra as caudas para cima; longo, para baixo.** Projeção
explícita mais longa acumula mais decaimento do crescimento, e quem cresce muito
no começo perde mais.

**E a cobertura anda contra o horizonte longo:**

| | |
|---|---|
| entram a 5 anos | ENEV3, ENGI11, GOAU4, MOTV3, PNVL3 |
| saem a 20 anos | AMER3, EMBJ3, MULT3 |

Projeção mais longa dá mais anos para o capital próprio desaparecer dentro da
projeção, e a via da firma recusa (decisões 45 e 110). **MOTV3, ENGI11 e GOAU4 — que as
decisões 113 e 119 tiraram — voltam a cinco anos**: não porque o ativo melhore,
mas porque a conta tem menos tempo para quebrar.

## 4. Sobre a habilidade: o que se pode afirmar, e o que não

**A ordenação é quase a mesma em todo o intervalo** — postos de 0,9828 entre os
extremos. Quanto isso limita a medição de habilidade tem forma fechada: com
`corr(x, y) = ρ` entre as duas ordenações,

```
| IC(y) − IC(x) |  ≤  (1 − ρ)·|IC(x)|  +  √(1 − ρ²)
```

A ρ = 0,9828 e `IC(x) = 0,078`, o teto é **+0,20**. **Não é decisivo**: o pior
caso matemático levaria o IC a 0,25, acima do book-to-market. Mas o pior caso
exige que a componente residual — 1,5% da variância dos postos — seja preditor
**perfeito** do retorno, o que nenhuma grandeza deste projeto é.

**O veredito continua sendo do backtest**, e depende do C5. O que esta medição
estabelece é que a aposta de que a habilidade esteja escondida no horizonte é
fraca, e que ela pode ser testada sem custo quando as coortes voltarem.

## 5. O que se decidiu

[Decisão 115](../decisoes/115-o-horizonte-fica-em-dez-anos-por-medicao.md):
**dez anos ficam**, agora por medição em vez de convenção.

- **Não é escolha de nível**: nenhum horizonte de 5 a 20 move a mediana mais que
  1,0%.
- **É escolha de onde o valor mora.** A 5 anos o terminal é 59% do preço justo, e
  o modelo vira majoritariamente a sua parte mais frágil; a 20 anos ele é 8%, mas
  a projeção explícita passa a extrapolar fundamento duas décadas à frente e
  três ativos deixam de ser avaliáveis.
- **Dez fica no meio dos dois males**, com 30,5% de terminal e 97 avaliados.

## 6. O que isto não diz

- **Não mede horizonte por ativo.** A varredura é do horizonte **comum**; um
  horizonte por setor, por ciclo ou por prazo de concessão é outra pergunta, e
  o motor já trata prazo de concessão por outro caminho (decisão 88).
- **Não é medição de habilidade.** É o limite superior do efeito que o horizonte
  poderia ter sobre ela, e o limite não é apertado.
- **A entrada é a de 14/09/2026.** Outra data move o nível de todo mundo; a
  invariância ao horizonte é propriedade da forma do terminal, e não da data.
