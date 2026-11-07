# Caso UNIP6 — Unipar, via da firma com normalização pelo ciclo

> **O que este caso mostra.** Uma empresa de commodity no fundo do ciclo: o
> retorno de 2026 é uma fração do de 2021 e 2022, e avaliar pelo último ano
> diria que a Unipar encolheu para sempre. O caso mostra a **normalização pelo
> ciclo**, a **precedência do ciclo em commodity** e a **isenção da trava de
> saúde** — e o que muda na conta por causa disso. Compare com a
> [Sanepar](sapr11.md) e a [Randon](rapt4.md), em que a mesma trava age.
>
> **Data:** 14/09/2026, entrada congelada, com o motor de 03/11/2026
> ([dados/UNIP6.json](dados/UNIP6.json)).
>
> **Resultado:** preço justo **R$ 75,38**, contra R$ 57,04 de mercado — upside
> de **+32,2%**. Ressalvas: **base normalizada forte** e **crescimento não
> identificado**.

---

## 1. A história que os números contam

A Unipar produz cloro, soda cáustica e PVC, produtos de preço internacional.

| Ano | Receita (R$ mi) | EBIT (R$ mi) | Lucro líquido (R$ mi) | Capital investido (R$ mi) |
|---:|---:|---:|---:|---:|
| 2021 | 6.289 | 2.944,5 | 2.003,8 | 2.173,8 |
| 2022 | 7.270 | 2.380,3 | 1.334,3 | 2.333,1 |
| 2023 | 4.897 | 979,6 | 791,3 | 2.371,2 |
| 2024 | 5.432 | 625,0 | 557,1 | 3.547,1 |
| 2025 | 5.143 | 793,5 | 481,7 | 4.269,0 |
| 2026 anualizado | 5.468 | 770,9 | 321,1 | 4.342,1 |

O EBIT de 2026 anualizado é um quarto do de 2021, com receita só 13% menor, e
o capital investido quase dobrou desde 2023. O negócio não encolheu nessa
proporção: caiu o preço do que ele vende.

**O último ponto é 2026 anualizado**: o primeiro semestre vezes
2, com o balanço de 30/06/2026.

---

## 2. Papéis, caminho e custo do capital próprio

- **Unit:** `113.173.264 ações × R$ 57,04 ÷ R$ 5,77 bi = 1,118` → 1 ação por
  papel.
- **Contagem:** registro oficial da B3, **111.622.153** papéis (o valor de
  mercado implicava 101.189.279, e as demonstrações 113.173.264; o oficial
  desconta a tesouraria e arbitra a divergência).
- **Caminho:** setor "materiais básicos", NOPAT positivo em ≥ 60% dos anos →
  **via da firma**.
- **CAPM:** `Ke = 14,05% + 0,8203 × 1,21% = 14,05% + 0,99% = 15,04%` (beta com
  19 proventos reinvestidos, encolhido; beta desalavancado 0,79).

---

## 3. O lucro de partida: normalização pelo ciclo

**Alíquota estrutural:** a mediana das efetivas dos 17 pontos é **31,6%** (a de
2026 anualizado foi 39,7%).

```
NOPAT 2026 = EBIT × (1 − 31,6%) = 770,9 × 0,684 = R$ 527,6 mi
ROIC 2026  = 527,6 ÷ capital investido 2025 (4.269,0) = 12,36%
ROIC do ciclo = mediana de 2018–2025 = 30,02%
```

Os oito retornos do ciclo, em ordem: 15,3%, 16,9%, 18,0%, 28,9%, 31,1%, 37,6%,
75,2% e 150,5%. A mediana é `(28,92% + 31,12%) ÷ 2 = 30,02%`. A **média** dos
oito daria 46,7%: os dois anos de pico (2021 e 2022) puxariam tudo para cima. É
por isso que o motor usa a mediana (capítulo 6, seção 6.1).

| Guarda | Resultado | Leitura |
|---|---|---|
| 1 — tendência | +1,35 p.p./ano, `t` = 0,70 | não significante: **sem tendência** |
| 2 — capital externo | Φ = 0,57 | abaixo de 1,0: base comparável |
| 3 — desvio | 12,36% contra 30,02%: razão 0,41, fora de [0,75; 1,33] | **destoa** |
| Precedência do ciclo | setor "materiais básicos" | commodity: vale o ciclo mesmo que houvesse tendência |
| Trava de saúde | lucro caiu 59,4% em três anos (791,3 → 321,1) | acima de 50%, mas **commodity é isenta** |

```
fator = ROIC do ciclo ÷ ROIC atual = 30,02% ÷ 12,36% = 2,43   (dentro de [1/3; 3])
NOPAT de partida = 527,6 × 2,429 = R$ 1.281,5 mi
```

**Por quê.** Em commodity, o lucro de um ano é função do preço do produto, que
vai e volta. A mediana de oito anos pega um ciclo inteiro. Se a Unipar estivesse
em outro setor, uma queda de 59% em três anos travaria o fator em 1,0 (a base
não sobe), como acontece com a Sanepar e a Randon — a trava existe para não
"ressuscitar" empresa que quebrou o modelo de negócio. Em commodity, a queda
entre pico e vale é o ciclo, e a trava não se aplica.

**O preço disso:** a base é 2,43 vezes o lucro publicado. Por isso a tela mostra
a ressalva **"base normalizada forte"** (fator acima de 2).

---

## 4. Quanto cresce

```
g pela mediana = 7,33%;  pela regressão = 14,87%;  erro = 1,86 p.p.
discordância = 4,05 (crítico 1,76), e a diferença de 7,5 p.p. passa de máx(2; 25% de g)
→ crescimento não identificado
```

Os dois estimadores discordam demais: o capital investido da Unipar cresceu aos
saltos (2024 sozinho somou R$ 1,2 bi), e a série não sustenta um número. O motor
cai na **âncora da inflação**, de 4,96%, depois de conferir que ela é
financiável: crescer 4,96% com o retorno típico de 30,02% exige reter
`4,96% ÷ 30,02% = 16,5%` do NOPAT, e a empresa reteve 17,7% no passado. Como
4,96% é menor que o teto (6,83%), `g∞ = g = 4,96%`, e o crescimento **fica
constante** nos dez anos. A tela mostra a ressalva **"crescimento não
identificado"**.

---

## 5. O custo de capital

**WACC de hoje:**

| Peça | Valor |
|---|---:|
| E (papéis × preço) | R$ 6,37 bi |
| Dívida bruta / caixa / dívida líquida | R$ 3,70 bi / R$ 1,37 bi / R$ 2,33 bi |
| Alavancagem (dívida líquida ÷ EBITDA) | 2,16× → prêmio de 2,4% |
| Kd | 14,05% + 2,4% = 16,45% |

```
pesos: 6,37 ÷ 8,70 = 0,7320;  3,70 ÷ 8,70 = 0,4257;  1,37 ÷ 8,70 = 0,1577
WACC = 0,7320 × 15,04% + 0,4257 × 16,45% × 0,66 − 0,1577 × 14,05% × 0,66
     = 11,01% + 4,62% − 1,46% = 14,17%
```

A despesa financeira não está publicada no ponto anualizado, e o prêmio de
crédito sai só da alavancagem; a tela declara isso num aviso.

**Resolvido ano a ano** (28 iterações): WACC de 14,10% no ano 1 a 14,69% no ano
10; **Ke de 14,80% a 15,53%**. O capital próprio vai de 78,5% a 76,2% do valor da
firma projetado (hoje, a preço de mercado, é 73,2%).

---

## 6. A perpetuidade

```
excedente do ciclo = 30,02% − 14,69% = 15,33 p.p.
φ (AR(1), 15 pares) = 0,2347  →  λ = 0,2347¹⁰ ≈ 0,0000005
ROIC∞ = 14,69% + 0,0000005 × 15,33% = 14,69%
```

O crescimento passa como orgânico por pouco (Φ = 0,57, contra o teto de 0,60), e
há excedente, mas ele **não persiste**: com φ = 0,23, de cada ponto de excedente
não sobra quase nada em dez anos (o excedente "decai 76,5% ao ano", diz o aviso).
Na prática, é o retorno neutro — com a forma de Gordon, porque o veredito foi
concedido. Compare com a [WEG](wege3.md), em que φ = 0,87 deixa 24% do
excedente depois de dez anos.

---

## 7. Os dez anos

O ROIC parte do típico (30,0%), porque a base foi normalizada até ele, e converge
ao WACC do ano (14,7% no ano 10). Com o crescimento constante e o retorno caindo,
a retenção sobe de 16,5% para 33,8%.

O serviço da dívida é positivo: a Unipar tem dívida líquida, e o acionista paga
os juros dela depois do imposto, menos o que o caixa rende e menos a dívida nova
que a manutenção da alavancagem permite tomar. Conferindo o ano 1:

```
juro da dívida      = 3.702,5 × (13,67% + 2,4%) × (1 − 34%) = 392,8
rendimento do caixa = 1.371,3 × 13,67% × (1 − 34%)          = 123,7
dívida nova         = 2.331,3 × 4,96%                        = 115,7
serviço da dívida   = 392,8 − 123,7 − 115,7                  = 153,3
```

| Ano | g | ROIC | Retenção | NOPAT (R$ mi) | Fluxo da firma (R$ mi) | Serviço da dívida (R$ mi) | Fluxo do acionista (R$ mi) | Ke | Fator acumulado | Meio de ano | Valor presente (R$ mi) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 5,0% | 30,0% | 16,5% | 1.345,1 | 1.122,7 | 153,3 | 969,4 | 14,8% | 1,1480 | 1,0714 | 904,8 |
| 2 | 5,0% | 28,3% | 17,5% | 1.411,9 | 1.164,2 | 168,8 | 995,4 | 15,3% | 1,3235 | 1,0737 | 807,5 |
| 3 | 5,0% | 26,6% | 18,6% | 1.482,0 | 1.205,8 | 182,6 | 1.023,3 | 15,6% | 1,5301 | 1,0752 | 719,1 |
| 4 | 5,0% | 25,0% | 19,9% | 1.555,6 | 1.246,2 | 192,5 | 1.053,8 | 15,7% | 1,7698 | 1,0755 | 640,4 |
| 5 | 5,0% | 23,3% | 21,3% | 1.632,8 | 1.285,6 | 205,2 | 1.080,4 | 15,8% | 2,0500 | 1,0763 | 567,2 |
| 6 | 5,0% | 21,6% | 23,0% | 1.713,9 | 1.320,2 | 213,1 | 1.107,1 | 15,7% | 2,3722 | 1,0757 | 502,1 |
| 7 | 5,0% | 19,9% | 25,0% | 1.798,9 | 1.349,2 | 221,3 | 1.128,0 | 15,6% | 2,7424 | 1,0752 | 442,2 |
| 8 | 5,0% | 18,1% | 27,4% | 1.888,3 | 1.371,7 | 231,8 | 1.139,9 | 15,6% | 3,1699 | 1,0751 | 386,6 |
| 9 | 5,0% | 16,4% | 30,3% | 1.982,0 | 1.382,3 | 242,2 | 1.140,1 | 15,5% | 3,6626 | 1,0749 | 334,6 |
| 10 | 5,0% | 14,7% | 33,8% | 2.080,4 | 1.377,3 | 253,9 | 1.123,4 | 15,5% | 4,2313 | 1,0748 | 285,4 |
| **Soma** | | | | | | | | | | | **5.589,8** |

**Diferente da WEGE3:** com crescimento baixo, a retenção é pequena (16% a 34%)
e a maior parte do NOPAT vira fluxo livre. Por isso o valor está concentrado no
período explícito: o terminal é só 33,7% do capital próprio, contra 49,1% na
WEG.

---

## 8. O terminal, convertido para o acionista

```
VT da firma = NOPAT₁₀ × (1 + 4,96%) × (1 − 4,96% ÷ 14,69%) ÷ (14,69% − 4,96%)
            ≈ R$ 14,86 bi (14.864,7 sem arredondar)
fluxo da firma ano 11  = 14.864,7 × (14,69% − 4,96%) = 1.445,7
fluxo do acionista     = 1.445,7 − 266,5 (serviço da dívida) = 1.179,2
VT do acionista        = 1.179,2 ÷ (15,53% − 4,96%) = 11.163,7
VP do terminal         = 11.163,7 × 1,074836 ÷ 4,231254 = R$ 2.835,8 mi
```

---

## 9. O preço justo

```
capital próprio = 5.589,8 + 2.835,8 − 12,0 (minoritários) = R$ 8.413,6 mi
preço justo     = 8.413,6 mi ÷ 111.622.153 = R$ 75,38
upside          = (75,38 − 57,04) ÷ 57,04 = +32,2%
```

A Unipar é um dos 28 ativos, entre os 121 avaliados, com upside positivo.

---

## 10. Os números em volta

**Cenários:** R$ 60,70 / R$ 75,38 / R$ 98,32 (crescimento de 1,96% e 7,96%,
desconto 2 pontos acima e abaixo). **Monte Carlo:** P5 R$ 66,86, mediana
R$ 75,40, P95 R$ 86,56.

**Faixa calibrada (80%):** 12 meses, R$ 41,73 a R$ 93,50; 36 meses, R$ 37,13 a
R$ 131,42. Larga: a Unipar oscilou 33,2% no último ano. A conta está no
[caso WEGE3](wege3.md), seção 13.

**Múltiplos de pares** (setor de materiais básicos):

| Leitura | Mediana (companhias) | Grandeza por papel | Preço |
|---|---:|---:|---:|
| P/L | 13,02 (18) | lucro R$ 2,877 | R$ 37,46 |
| P/VP | 0,85 (21) | patrimônio R$ 18,01 | R$ 15,27 |
| EV/EBITDA | 6,44 (21) | EBITDA R$ 1,08 bi, dívida líq. R$ 2,33 bi | R$ 41,47 |
| **Consolidada** | | | **R$ 37,46** |

Divergência de −50,3%: acima do limite de 50%, e o aviso aparece na avaliação.
O lucro e o EBITDA que os múltiplos multiplicam são os de 2026 anualizado, no
fundo do ciclo — que é exatamente o que a normalização corrige no fluxo
descontado e os múltiplos não corrigem. O mercado, que paga 19,8 vezes esse
lucro, fica entre as duas leituras.

---

## 11. O que este caso ensina

- **A normalização é a peça que mais move o preço da Unipar.** Sem ela, a base
  seria R$ 527,6 mi em vez de R$ 1.281,5 mi — menos da metade —, e como o
  serviço da dívida não encolhe junto com o lucro, o preço justo cairia mais
  que a base. A ressalva "base normalizada forte" existe para isso ficar
  visível.
- **O motor não prevê o preço da soda e do PVC.** Ele supõe que o retorno volta
  à mediana de oito anos, e essa mediana inclui o pico de 2021 e 2022 só pelo
  meio: a média, que os incluiria inteiros, daria 46,7%. Se o preço ficar baixo
  por uma década, a base está alta demais; se voltar a 2021, baixa demais.
- **Commodity é o único setor em que o motor puxa a base para cima depois de uma
  queda forte** — e por isso a lista de setores cíclicos
  ([cyclical-sectors.ts](../../../src/core/services/valuation/cyclical-sectors.ts))
  decide muita coisa, e é mantida à mão (limitação declarada).
- **Duas ressalvas no mesmo preço.** A base foi multiplicada por 2,43 e o
  crescimento é uma âncora, não uma medida. O preço justo de R$ 75,38 é a conta
  do motor com essas duas escolhas declaradas, e a faixa calibrada, de R$ 41,73
  a R$ 93,50 em doze meses, é o tamanho medido da incerteza.
