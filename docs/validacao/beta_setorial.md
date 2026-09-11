# O beta desalavancado, e a proposta que a medição descartou

Medido em 10/09/2026 sobre os 363 papéis com série de preço utilizável.

```bash
dart run tool/beta_setorial.dart   # grava beta_setorial.json
```

---

## 0. Por que

O teste A1 ([decisão 39](../decisoes/039-as-duas-vias-sao-modelos-independentes.md))
mostrou que `Ke` e `WACC` não estão ligados pela alavancagem: o beta é
regressão crua contra o Ibovespa, sem versão desalavancada. Sem essa ligação a
identidade `FCFF/WACC ≡ FCFE/Ke` não fecha por construção.

A proposta era o beta *bottom-up* clássico: desalavancar, tomar a **mediana
setorial** como risco de negócio, e realavancar para a estrutura do próprio
ativo. A premissa dupla era que a regressão individual é ruidosa e que o setor
explica o risco do negócio.

**As duas metades falharam.**

---

## 1. A regressão individual não é ruidosa

| | valor |
|---|---:|
| `β` mediano | 0,84 |
| erro-padrão mediano | **0,07** |
| erro-padrão p90 | 0,15 |
| erro-padrão acima de 0,30 | **6 de 363** |

Cinco anos de pregão diário dão cerca de 1.250 observações pareadas. O
estimador é preciso. O que se pode dizer é mais modesto: em **71 dos 363** o
intervalo de 95% cobre 1,0, ou seja, o beta não distingue o ativo do mercado —
o que é diferente de ser ruidoso.

## 2. E o setor explica pouco

| | dispersão robusta |
|---|---:|
| `β` desalavancado do universo | 0,40 |
| mediana **dentro** dos setores | 0,35 |
| **redução ao agrupar** | **13,1%** |

Os setores grandes são os piores: construção 0,48, serviços financeiros 0,47,
consumo cíclico 0,41. Só telecomunicações (0,09), infraestrutura (0,09) e saúde
(0,19) são apertados, e têm 6, 3 e 8 ativos.

E **95 dos 363 não têm setor com três pares** — um quarto do universo não
receberia beta *bottom-up* de jeito nenhum.

## 3. Substituir moveria muito, sem ganho

| | valor |
|---|---:|
| \|Δβ\| mediano | 0,39 |
| **\|ΔKe\| mediano** | **2,13 p.p.** |
| \|ΔKe\| p90 | 11,89 p.p. |
| Δβ mediano **com sinal** | 0,00 |

Trocar um estimador com erro-padrão de 0,07 por uma mediana cuja dispersão
interna é 0,35 aumentaria o erro. **A proposta fica descartada.**

---

## 4. O que sobra, e é o que foi implementado

### 4.1 Encolhimento por precisão

O peso do estimador individual é a razão entre a precisão dele e a soma das
duas:

```
w = (1/SE²) / (1/SE² + 1/σ_prior²)
β = w · β_regressão + (1 − w) · β_prior
```

Nenhum limiar decide — a precisão decide, e é contínua.

| | valor |
|---|---:|
| peso mediano do individual | **0,98** |
| peso p10 | 0,93 |
| abaixo de 0,90 | **23 de 363** |
| \|Δβ\| mediano | 0,01 |
| \|ΔKe\| mediano | **0,03 p.p.** |

**O ativo típico não se move.** É o oposto da substituição setorial, e é o
comportamento correto quando o estimador individual é bom.

### 4.2 Onde ele age, e por que precisava agir

A **AZUL3** devolve `β = 109.108,81` com `ρ = 0,110` sobre **142** pregões —
contra ~1.250 dos demais. O erro-padrão é **83.228**: a estimativa não carrega
informação nenhuma.

**E o motor a aceitava.** `BetaCalculator.estimate` não devolvia erro-padrão, e
`PrepareValuationInputs` usava o número como qualquer outro beta. Com o
encolhimento, o peso vai a `4·10⁻¹¹` e o ativo recebe o prior do setor.

### 4.3 O teto de Hamada

`D/E` tem mediana de 0,28 e p75 de 1,96, mas chega a **94,5** na AZUL3, onde o
valor de mercado do capital próprio praticamente sumiu. Realavancar um prior
por 94,5 inventaria um beta de dezenas, e Hamada — que supõe dívida sem risco —
já não descreve ali. `D/E` é confinado em **3,0**, onde a dívida responde por
75% do capital.

### 4.4 O efeito em produção é pequeno, e isso é a leitura certa

| | valor |
|---|---:|
| avaliados nos dois modos | 122 |
| \|Δ preço justo\| mediano | **0,09%** |
| p90 | 0,74% |
| máximo | 4,57% |
| alterados além de 0,5% | 21 de 122 |

Os betas degenerados pertencem a ativos que a Porta 0 já filtra. **O ganho não
é de nível — é de não deixar entrar no CAPM um número sem informação.**

---

## 5. O que isto entrega para A2

O `β` desalavancado do próprio ativo passa a ser grandeza de primeira classe,
com `ShrunkBeta.unlevered`. **É ela que liga `Ke` a `WACC`**, e sem ela a
conciliação das vias não tem como acontecer.

O prior é resolvido por `ResolveBetaPrior`, fora da cascata, no mesmo arranjo
que `ResolveMarketAnchors` já usa: a cascata avalia um ativo por vez e é pura,
e estatística transversal não cabe ali.

## 6. Medianas desalavancadas por setor

| Setor | `β_U` | n | dispersão |
|---|---:|---:|---:|
| energia | 0,30 | 39 | 0,31 |
| bens industriais | 0,33 | 20 | 0,39 |
| infraestrutura | 0,40 | 3 | 0,09 |
| consumo não cíclico | 0,45 | 29 | 0,23 |
| educação | 0,45 | 8 | 0,46 |
| materiais básicos | 0,51 | 26 | 0,38 |
| saúde | 0,53 | 8 | 0,19 |
| consumo cíclico | 0,53 | 43 | 0,41 |
| construção e imobiliário | 0,55 | 37 | 0,48 |
| telecomunicações | 0,55 | 6 | 0,09 |
| serviços | 0,58 | 6 | 0,22 |
| saneamento | 0,63 | 5 | 0,30 |
| serviços financeiros | 0,77 | 28 | 0,47 |
| tecnologia | 1,10 | 10 | 0,47 |

A ordenação é economicamente plausível — energia e bens industriais embaixo,
tecnologia em cima. **O que a medição nega não é que o setor signifique algo, e
sim que ele signifique o bastante para substituir uma regressão de 1.250
pontos.**

## 7. O que fica em aberto

1. **A taxonomia setorial é da fonte**, não GICS nem B3 — a §1.5 das
   [limitações](limitacoes.md). Agrupar por outra taxonomia daria outras
   medianas.
2. **O prior é resolvido sobre o universo do dia**, e a §1.8 registra que ele
   varia entre execuções.
3. **O erro-padrão supõe regressão simples e resíduo bem comportado.** Não há
   correção para autocorrelação nem para heterocedasticidade, que o
   `inference.dart` já sabe fazer em outro contexto.
