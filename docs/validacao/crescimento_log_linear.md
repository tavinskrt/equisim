# Fórmula 4 do painel — como o crescimento é calculado

Medições feitas em 28/08/2026 sobre os 18 ativos das carteiras de teste,
exercícios de 2010 a 2025 (fonte: brapi.dev, `/v2/stocks/cash-flow`,
`mode=history`). Código:
[`growth_estimator.dart`](../../packages/equisim_core/lib/src/services/valuation/growth_estimator.dart).

---

## 1. Qual é a fórmula 4

No caminho do **DCF por FCFF** — o modelo mais exigente da cascata, e o que a
maioria dos ativos alcança — as fórmulas saem do motor nesta ordem, e é ela que
o painel numera:

| # | Fórmula |
|---|---|
| 1 | Razão da unidade negociada |
| 2 | Custo do capital próprio (CAPM) |
| 3 | Normalização do fluxo-base |
| **4** | **Crescimento explícito por regressão log-linear** |
| 5 | Custo médio ponderado de capital (WACC) |
| 6 | Crescimento na perpetuidade |
| 7 | Projeção e desconto do período explícito |
| 8 | Valor terminal (perpetuidade de Gordon) |
| 9 | Ponte do valor da firma ao preço justo por papel |
| 10 | Margem de segurança e potencial de valorização |

(Ordem confirmada executando a cascata com o coletor de auditoria acoplado. No
caminho alternativo por LPA a numeração muda, porque a razão da unidade e o
WACC não aparecem do mesmo jeito.)

```
ln(vₜ) = a + b·t     ⇒     g = e^b − 1     ⇒     g_aplicado = clamp(g, −5%, +20%)
```

`t` é o **ano fiscal em calendário** (2010, 2011, …), não a posição na série.

---

## 2. Como o cálculo é feito, passo a passo

1. Percorre todos os exercícios **já publicados** na data de referência.
2. **Descarta os exercícios com valor nulo ou não positivo** — logaritmo de
   número não positivo não existe.
3. Se sobrarem menos de 3 pontos, devolve `4% a.a.` (fallback conservador).
4. Ajusta uma reta por mínimos quadrados sobre `(ano, ln valor)`, fechada:
   `b = (n·Σxy − Σx·Σy) / (n·Σx² − (Σx)²)`.
5. Converte a inclinação em taxa anual por **composição**: `g = e^b − 1`.
6. Confina o resultado à banda de sanidade `[−5%, +20%]`.

A escolha da regressão sobre o CAGR ponta a ponta está certa e é defensável: o
CAGR depende de dois pontos, e um deles sendo atípico o número desanda. A
regressão usa todos os pontos.

---

## 3. O que o cálculo produz nas carteiras de teste

| Ativo | anos na base | pontos usados | descartados | g bruto | g aplicado | limitado? |
|---|---|---|---|---|---|---|
| BBAS3 | 16 | 9 | 7 | 10,7% | 10,7% | não |
| EGIE3 | 16 | 11 | 5 | 1,1% | 1,1% | não |
| PETR4 | 16 | 11 | 5 | 15,2% | 15,2% | não |
| VALE3 | 16 | 15 | 1 | 13,8% | 13,8% | não |
| SAPR11 | 16 | 15 | 1 | 21,3% | 20,0% | **sim** |
| BBSE3 | 14 | 13 | 1 | 11,0% | 11,0% | não |
| ABEV3 | 14 | 14 | 0 | 23,6% | 20,0% | **sim** |
| VIVT3 | 16 | 15 | 1 | 8,3% | 8,3% | não |
| KLBN11 | 16 | 12 | 4 | 26,7% | 20,0% | **sim** |
| WEGE3 | 16 | 14 | 2 | 19,0% | 19,0% | não |
| RADL3 | 16 | 12 | 4 | 22,6% | 20,0% | **sim** |
| AZZA3 | 15 | 10 | 5 | 25,1% | 20,0% | **sim** |
| BPAC11 | 16 | 5 | 11 | −13,5% | −5,0% | **sim** |
| SLCE3 | 16 | 10 | 6 | 34,7% | 20,0% | **sim** |
| TOTS3 | 16 | 13 | 3 | 4,0% | 4,0% | não |
| EQTL3 | 16 | 6 | 10 | 22,9% | 20,0% | **sim** |
| PRIO3 | 16 | 4 | 12 | 48,6% | 20,0% | **sim** |
| RENT3 | 16 | 6 | 10 | 12,5% | 12,5% | não |

---

## 4. Achados

Nenhum destes é erro de implementação — a fórmula faz o que diz que faz. São
propriedades do método que precisam estar declaradas na defesa, porque um
examinador atento chega a elas.

### 4.1 Em metade da amostra, quem determina o crescimento é a banda

**9 dos 18 ativos batem no teto de 20% ou no piso de −5%.** Para esses, o
número que entra no DCF não é o resultado da regressão: é o limite. A regressão
serviu apenas para decidir de que lado do limite o ativo cai.

Isso não invalida a banda — sem ela, PRIO3 entraria na projeção explícita com
48,6% a.a. —, mas muda o que se pode afirmar. O correto é dizer que **o modelo
projeta o teto de crescimento defensável**, não que "estimou 20% de
crescimento". O painel já registra o valor bruto ao lado do aplicado, o que
torna a distinção auditável.

### 4.2 Exercícios de prejuízo somem em silêncio, e o viés é para cima

O logaritmo exige `v > 0`, então todo exercício de fluxo negativo é removido da
regressão. O efeito é estrutural e sempre no mesmo sentido: **a reta é ajustada
só sobre os anos bons.**

- PRIO3 estima crescimento a partir de **4 dos 16 exercícios**;
- BPAC11, de 5; EQTL3 e RENT3, de 6; BBAS3, de 9.

Os 48,6% brutos da PRIO3 são a inclinação de quatro pontos escolhidos por serem
positivos. O painel publica `exercícios (n)` — os usados —, mas **não publica
quantos foram descartados**, e é o descarte que qualifica o número.

### 4.3 A janela do crescimento não é a mesma do fluxo-base

Dentro do mesmo modelo, sobre a mesma série:

- a **normalização do fluxo-base** olha os **5 últimos** exercícios;
- a **regressão de crescimento** olha **todos os 16**.

A diferença não é acadêmica. Refazendo a regressão sobre a mesma janela de 5:

| Ativo | g (16 anos) | g (5 anos) | diferença |
|---|---|---|---|
| SLCE3 | 20,0% | −5,0% | **−25,0 p.p.** |
| PETR4 | 15,2% | −5,0% | **−20,2 p.p.** |
| VALE3 | 13,8% | −5,0% | **−18,8 p.p.** |
| BBAS3 | 10,7% | −5,0% | −15,7 p.p. |
| ABEV3 | 20,0% | 8,1% | −11,9 p.p. |
| EGIE3 | 1,1% | 20,0% | **+18,9 p.p.** |
| BBSE3 | 11,0% | 20,0% | +9,0 p.p. |

**A escolha da janela é a premissa dominante da fórmula 4** — pesa mais que
qualquer refinamento do estimador. Hoje ela é implícita ("tudo que a fonte
entregar"), e deveria ser explícita e justificada como a janela de 5 do
fluxo-base é.

### 4.4 A winsorização não alcança a regressão

O exercício que a fórmula 3 apara continua entrando **cheio** na fórmula 4. Ou
seja: o mesmo ponto é considerado atípico demais para servir de base da
perpetuidade e confiável o bastante para definir a tendência.

Refazendo a regressão com o último ponto já winsorizado:

| Ativo | g bruto com `F_obs` | g bruto com `F₀` aparado |
|---|---|---|
| SAPR11 | 21,3% | **16,5%** |
| KLBN11 | 26,7% | 23,7% |
| AZZA3 | 25,1% | 22,6% |
| VALE3 | 13,8% | 15,1% |

No caso da SAPR11 a diferença **atravessa o teto**: com o outlier, o ativo é
limitado a 20%; sem ele, a regressão devolveria 16,5% e o teto nem seria
acionado. É a inconsistência mais concreta apontada aqui.

### 4.5 Peso igual para 2010 e 2025, com alavancagem nas pontas

A regressão é MQO simples, sem ponderação: o exercício de 2010 pesa tanto
quanto o de 2025 na inclinação. E, como `t` é o ano em calendário, os pontos
das **extremidades têm a maior alavancagem** — um valor pequeno no início da
série (que o log amplifica) inclina a reta inteira para cima.

### 4.6 O que está correto e não precisa mexer

- `t` é o ano em calendário, não o índice: **lacunas na série não distorcem a
  inclinação**. Um exercício faltando em 2019 não faz 2020 valer por 2019.
- A conversão de inclinação em taxa é por composição (`e^b − 1`), não por
  aproximação linear.
- `rawRate` e `slope` viajam até o painel, então o efeito da banda é visível
  para quem confere.
- Denominador degenerado e resultado não finito têm guarda explícita, com
  queda para o fallback de 4%.

---

## 5. O que não foi alterado

Nada do comportamento da fórmula 4 foi modificado nesta rodada. Os quatro
ajustes que os achados sugerem — declarar a janela, publicar os exercícios
descartados, alimentar a regressão com o fluxo já normalizado e ponderar os
anos recentes — **mudam preços justos publicados** e são decisão de orientação,
não correção de defeito.

Se a decisão for encaminhar algum deles, o de menor custo e maior efeito é o
**4.4** (usar `F₀` no último ponto da regressão): torna as fórmulas 3 e 4
coerentes entre si e não introduz premissa nova.
