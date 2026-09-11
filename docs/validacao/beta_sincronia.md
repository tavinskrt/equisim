# O beta diário, a negociação não síncrona e a cotação suja

Medido em 11/09/2026.

```bash
dart run tool/beta_sincronia.dart   # grava beta_sincronia.json
```

---

## 0. O apontamento, repetido sete vezes

A lente `metodo` voltou em sete rodadas seguidas ao mesmo ponto: o beta sai de
regressão de retorno **diário** sobre cotação **não ajustada por provento**, e
as duas coisas enviesam.

São dois apontamentos distintos, e só um é acionável.

## 1. A cotação suja está bloqueada por dado

Corrigir o retorno por provento exige a série de retorno total da fonte, e a
[limitação 1.2](limitacoes.md) já a mediu: **desvio mediano de 9,1%** entre o
fator implícito no fluxo de proventos publicado e a razão `adjustedClose/close`
observada, com máximo de 38,5% na BBAS3 e seis dos onze ativos acima de 5%.

A série existe no domínio — `PricePoint.adjustedClose` — e está declarada como
**conferência, nunca cálculo**. Trocar um viés conhecido de tamanho
desconhecido por um erro medido de 9,1% não é correção.

Isto é item da Fase B: segunda fonte para o fluxo de proventos, ou nada.

## 2. A não sincronia: medida, e não existe aqui

Ativo que não negocia todo dia responde ao mercado com atraso, e a covariância
contemporânea perde a parte atrasada. O viés é conhecido, tem direção — **para
baixo** — e tem correção clássica: a de Dimson, que soma as inclinações contra
o mercado defasado, contemporâneo e adiantado.

Três estimadores, mesma janela de cinco anos, **nos 127 ativos que o motor
avalia**:

| | p10 | mediana | p90 | acima do diário |
|---|---:|---:|---:|---:|
| semanal ÷ diário | 0,834 | **0,991** | 1,112 | 61 de 127 |
| **Dimson ÷ diário** | 0,907 | **0,978** | 1,100 | 54 de 127 |

**A correção não eleva o beta — ela o reduz, em 2,2% na mediana.** É o
contrário do que a teoria prevê, e a razão está na liquidez.

### Porque não existe: a Porta 0 já tirou quem sofreria

| | pregões por ano (mediana) | Dimson ÷ diário |
|---|---:|---:|
| metade que menos negocia | **250** | 0,972 |
| metade que mais negocia | **250** | 0,985 |

**As duas metades negociam todos os pregões do ano.** O corte de liquidez da
[decisão 25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md) removeu 162
ativos do universo por liquidez insuficiente, e com eles foi embora a condição
que produz o viés.

No universo **cru** — 365 ativos, antes da Porta 0 — o quadro é outro: a razão
Dimson ÷ diário vai a 1,411 no p90, e aparecem casos como a USIM6 com 20
pregões por ano e beta diário de −0,001 contra −0,562 de Dimson. Lá o viés é
real. Aqui ele não chega.

### E a correção custaria caro

| erro-padrão do beta | mediana |
|---|---:|
| diário | **0,0490** |
| Dimson | 0,0853 |
| semanal | 0,1073 |

**Dimson custa 74% mais erro-padrão; o semanal, 119%.** Como o encolhimento da
[decisão 40](../decisoes/040-beta-encolhido-por-precisao.md) pondera por
`1/SE²`, adotar qualquer um dos dois transferiria peso do ativo para o prior
setorial — trocaria precisão por viés numa direção em que **não há viés a
trocar**.

## 3. O que fica

**Nada muda no motor**, e a razão é medida. O apontamento estava certo em
teoria e é inaplicável neste universo, porque a Porta 0 opera antes dele.

Fica registrado para que a próxima leitura não refaça a pergunta: se o corte de
liquidez for afrouxado, **este item volta**, e volta com o tamanho que o
universo cru mostra.
