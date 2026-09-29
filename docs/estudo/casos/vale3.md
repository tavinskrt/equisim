# Caso VALE3 — Vale, via da firma com normalização pelo ciclo

> **O que este caso mostra.** Uma empresa de commodity no fundo do ciclo: o
> lucro de 2025 é uma fração do de 2022, e avaliar pelo último ano diria que a
> Vale encolheu para sempre. O caso mostra a **normalização pelo ciclo**, a
> **precedência do ciclo em commodity** e a **isenção da trava de saúde** —
> e o que muda na conta por causa disso.
>
> **Data:** 14/09/2026 ([dados/VALE3.json](dados/VALE3.json)).
>
> **Resultado:** preço justo **R$ 70,25**, contra R$ 75,48 de mercado — upside
> de **−6,9%**. Ressalva: **base normalizada forte**.

---

## 1. A história que os números contam

| Ano | Receita (R$ bi) | EBIT (R$ bi) | Lucro líquido (R$ bi) | Capital investido (R$ bi) |
|---:|---:|---:|---:|---:|
| 2019 | 148,6 | 2,2 | −8,7 | 187,4 |
| 2020 | 208,5 | 52,1 | 24,9 | 189,0 |
| 2021 | 293,5 | 141,3 | 121,3 | 207,5 |
| 2022 | 226,5 | 90,3 | 96,3 | 236,2 |
| 2023 | 208,1 | 65,3 | 40,6 | 248,0 |
| 2024 | 206,0 | 55,5 | 30,4 | 278,7 |
| 2025 | 213,6 | 32,0 | 11,8 | 250,8 |

O minério de ferro subiu muito em 2021 e caiu depois. O lucro de 2025 é 88%
menor que o de 2022, com receita parecida. Nada no negócio da Vale mudou nessa
proporção: mudou o preço do minério.

---

## 2. Papéis, caminho e custo do capital próprio

- **Contagem:** registro oficial da B3, **4.174.876.130** papéis (o valor de
  mercado implicava 4.652.060.943, e as demonstrações 4.439.160.000; o oficial
  desconta a tesouraria e arbitra a divergência).
- **Caminho:** setor "materiais básicos", NOPAT positivo em ≥ 60% dos anos →
  **via da firma**.
- **CAPM:** `Ke = 14,09% + 0,8655 × 5,5% = 18,85%` (beta com 19 proventos
  reinvestidos, encolhido; beta desalavancado 0,79).

---

## 3. O lucro de partida: normalização pelo ciclo

**Alíquota estrutural:** a mediana das efetivas é **18,6%** (a de 2025 foi 50%,
um ano atípico — por isso a mediana).

```
NOPAT 2025 = EBIT × (1 − 18,6%) = 31,97 × 0,814 = R$ 26,02 bi
ROIC 2025  = 26,02 ÷ capital investido 2024 (278,7) = 9,34%
ROIC do ciclo = mediana dos oito anos anteriores = 20,35%
```

| Guarda | Resultado | Leitura |
|---|---|---|
| 1 — tendência | +1,14 p.p./ano, `t` = 1,12 | não significante: **sem tendência** |
| 2 — capital externo | Φ = 0,00 | orgânico |
| 3 — desvio | 9,34% contra 20,35%: razão 0,46, fora de [0,75; 1,33] | **destoa** |
| Precedência do ciclo | subsetor "Mineração / Minerais Metálicos" | commodity: vale o ciclo mesmo que houvesse tendência |
| Trava de saúde | lucro caiu 87,7% em três anos (96,3 → 11,8) | acima de 50%, mas **commodity é isenta** (decisão 30) |

```
fator = ROIC do ciclo ÷ ROIC atual = 20,35% ÷ 9,34% = 2,18   (dentro de [1/3; 3])
NOPAT de partida = 26,02 × 2,18 = R$ 56,72 bi
```

**Por quê.** Em commodity, o lucro de um ano é função do preço do insumo, que
vai e volta. A mediana de oito anos pega um ciclo inteiro. Se a Vale estivesse
em outro setor, uma queda de 88% em três anos travaria o fator em 1,0 (a base
não sobe) — a trava existe para não "ressuscitar" empresa que quebrou o modelo
de negócio. Em commodity, a queda entre pico e vale é o ciclo, e a trava não se
aplica.

**O preço disso:** a base é 2,18 vezes o lucro publicado. Por isso a tela mostra
a ressalva **"base normalizada forte"** (fator acima de 2).

> **Uma correção feita durante esta documentação (item B39):** o aviso da tela
> dizia que "a vantagem competitiva residual segue barrada" pela trava de
> saúde. Desde a decisão 36 isso não é verdade — o veredito do passo 6 concede a
> vantagem (em tamanho quase nulo). O texto foi corrigido.

---

## 4. Quanto cresce

```
g pela mediana = 3,32%;  pela regressão = 2,18%;  erro = 0,63 p.p.
discordância = 1,82 (crítico 1,76), mas diferença 1,14 p.p. < 2 p.p.
→ crescimento identificado: g = 3,32%
```

O capital investido da Vale cresce devagar: é um negócio maduro. Como 3,32% é
menor que o teto (6,78%), `g∞ = g = 3,32%` e o crescimento **fica constante** em
todos os dez anos.

---

## 5. O custo de capital

**WACC de hoje:**

| Peça | Valor |
|---|---:|
| E | R$ 315,12 bi |
| Dívida bruta / caixa / dívida líquida | R$ 103,46 bi / R$ 41,63 bi / R$ 61,83 bi |
| Alavancagem (dívida líquida ÷ EBITDA) | 1,25× → prêmio de 1,8% |
| Kd | 14,09% + 1,8% = 15,89% |

```
WACC = 0,836 × 18,85% + 0,2745 × 15,89% × 0,66 − 0,1104 × 14,09% × 0,66
     = 15,76% + 2,88% − 1,03% = 17,61%
```

A despesa financeira publicada daria custo de dívida de 7,8% — abaixo da taxa
livre de risco, impossível para captação nova: é dívida antiga e em dólar. O
motor usa o custo de captar hoje.

**Resolvido ano a ano** (26 iterações): WACC de 17,27% no ano 1 a 17,88% no ano
10; **Ke de 18,57% a 19,24%**. O capital próprio fica em 83% do valor da firma.

---

## 6. A perpetuidade

```
excedente do ciclo = 20,35% − 17,88% = 2,47 p.p.
φ (AR(1), 14 pares) = 0,4105  →  λ = 0,4105¹⁰ = 0,0001
ROIC∞ = 17,88% + 0,0001 × 2,47% = 17,89%
```

Há excedente, mas ele **não persiste**: com φ = 0,41, de cada ponto de excedente
sobra menos de 0,01% em dez anos (o excedente "decai 59% ao ano", diz o aviso).
Na prática, é o retorno neutro — com a forma de Gordon, porque o veredito foi
concedido.

---

## 7. Os dez anos

| Ano | g | ROIC | Retenção | NOPAT (R$ mi) | Fluxo da firma (R$ mi) | Serviço da dívida (R$ mi) | Fluxo do acionista (R$ mi) | Ke | Fator acumulado | Meio de ano | Valor presente (R$ mi) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 3,3% | 20,4% | 16,3% | 58.607,6 | 49.042,1 | 4.734,8 | 44.307,3 | 18,6% | 1,1857 | 1,0889 | 40.690,0 |
| 2 | 3,3% | 20,1% | 16,6% | 60.554,3 | 50.527,9 | 5.103,6 | 45.424,3 | 19,1% | 1,4119 | 1,0912 | 35.107,5 |
| 3 | 3,3% | 19,8% | 16,7% | 62.565,6 | 52.090,5 | 5.418,4 | 46.672,2 | 19,4% | 1,6860 | 1,0928 | 30.250,3 |
| 4 | 3,3% | 19,6% | 16,9% | 64.643,7 | 53.688,1 | 5.621,7 | 48.066,5 | 19,5% | 2,0142 | 1,0930 | 26.083,4 |
| 5 | 3,3% | 19,4% | 17,1% | 66.790,8 | 55.354,2 | 5.864,2 | 49.490,0 | 19,6% | 2,4087 | 1,0936 | 22.468,6 |
| 6 | 3,3% | 19,1% | 17,4% | 69.009,3 | 57.013,5 | 6.011,2 | 51.002,2 | 19,5% | 2,8781 | 1,0931 | 19.370,7 |
| 7 | 3,3% | 18,8% | 17,7% | 71.301,4 | 58.698,7 | 6.157,4 | 52.541,3 | 19,4% | 3,4358 | 1,0926 | 16.708,3 |
| 8 | 3,3% | 18,5% | 17,9% | 73.669,7 | 60.455,1 | 6.351,6 | 54.103,5 | 19,4% | 4,1010 | 1,0925 | 14.413,3 |
| 9 | 3,3% | 18,2% | 18,3% | 76.116,6 | 62.212,3 | 6.516,9 | 55.695,4 | 19,3% | 4,8914 | 1,0921 | 12.435,3 |
| 10 | 3,3% | 17,9% | 18,6% | 78.644,8 | 64.039,2 | 6.717,7 | 57.321,5 | 19,2% | 5,8327 | 1,0920 | 10.731,6 |
| **Soma** | | | | | | | | | | | **228.258,9** |

Aqui o serviço da dívida é positivo e grande (R$ 4,7 a 6,7 bi por ano): a Vale
tem dívida líquida de verdade, e o acionista paga os juros dela depois do
imposto, menos a dívida nova que a manutenção da alavancagem permite tomar.

**Diferente da WEGE3:** com crescimento baixo, a retenção é pequena (16–19%) e
a maior parte do NOPAT vira fluxo livre. Por isso o valor está concentrado no
período explícito: o terminal é só 23,7% do capital próprio.

---

## 8. O terminal, convertido para o acionista

```
VT da firma = NOPAT₁₀ × (1 + 3,32%) × (1 − 3,32% ÷ 17,89%) ÷ (17,88% − 3,32%)
            = R$ 454.338,3 mi
fluxo da firma ano 11  = 454.338,3 × (17,88% − 3,32%) = 66.166,5
fluxo do acionista     = 66.166,5 − 6.940,8 (serviço da dívida) = 59.225,8
VT do acionista        = 59.225,8 ÷ (19,24% − 3,32%) = 371.943,8
VP do terminal         = 371.943,8 × 1,0920 ÷ 5,8327 = R$ 69.634,4 mi
```

---

## 9. O preço justo

```
capital próprio = 228.258,9 + 69.634,4 − 4.627,0 (minoritários) = R$ 293.266,3 mi
preço justo     = 293.266,3 mi ÷ 4.174.876.130 = R$ 70,25
upside          = (70,25 − 75,48) ÷ 75,48 = −6,9%
```

---

## 10. Os números em volta

**Cenários:** R$ 61,61 / R$ 70,25 / R$ 82,63. **Monte Carlo:** P5 R$ 64,95,
mediana R$ 70,21, P95 R$ 76,70.

**Faixa calibrada (80%):** 12 meses, R$ 60,23 a R$ 114,41; 36 meses, R$ 55,42 a
R$ 149,78. Larga: a Vale oscila 26,6% ao ano.

**Múltiplos de pares.** O subsetor de mineração não tem cinco **outras**
companhias (até 28/09/2026 a conta chegava a cinco contando classes de ação da
mesma empresa; item B41), e a mediana vem do setor de materiais básicos:

| Leitura | Mediana (companhias) | Preço |
|---|---:|---:|
| P/L | 12,60 (18) | R$ 35,65 |
| P/VP | 0,85 (21) | R$ 38,36 |
| EV/EBITDA | 6,44 (21) | R$ 61,23 |
| **Consolidada** | | **R$ 38,36** |

Divergência de −45,4%: grande, mas abaixo do limite de 50% que dispara o aviso.
Os pares do setor (siderúrgicas, papel e celulose, químicas) negociam a
múltiplos menores que os da Vale, e o lucro que o P/L e o P/VP multiplicam é o
de 2025, no fundo do ciclo — que é exatamente o que a normalização corrige no
fluxo descontado e os múltiplos não corrigem.

---

## 11. O que este caso ensina

- **A normalização é a peça que mais move o preço da Vale.** Sem ela, a base
  seria R$ 26,0 bi em vez de R$ 56,7 bi — menos da metade —, e como o serviço
  da dívida não encolhe junto com o lucro, o preço justo cairia ainda mais que
  a base. A ressalva "base normalizada forte" existe para isso ficar visível.
- **O motor não prevê o minério.** Ele supõe que o retorno volta à mediana de
  oito anos. Se o preço do minério ficar baixo por uma década, a base está alta
  demais; se voltar a 2021, baixa demais.
- **Commodity é o único setor em que o motor puxa a base para cima depois de uma
  queda forte** — e por isso a lista de setores cíclicos
  ([cyclical_sectors.dart](../../../packages/equisim_core/lib/src/services/valuation/cyclical_sectors.dart))
  decide muita coisa, e é mantida à mão (limitação declarada).
