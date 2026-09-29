# Caso SAPR11 — Sanepar: unit, concessão e a leitura por pares

> **O que este caso mostra.** Três coisas que não aparecem nos outros casos: a
> **unit** (um papel que é um pacote de 5 ações), a **concessão** (um negócio
> que opera sob contrato) e uma **divergência grande entre o fluxo descontado e
> os múltiplos dos pares** — que o motor declara, sem mudar o preço justo.
>
> **Data:** 14/09/2026 ([dados/SAPR11.json](dados/SAPR11.json)).
>
> **Resultado:** preço justo **R$ 36,74 por unit** (R$ 7,35 por ação), contra
> R$ 34,74 de mercado — upside de **+5,8%**. Ressalva: **prazo determinado**.

---

## 1. A unit: por quantas ações dividir

A Sanepar tem 1.511.205.500 ações (ordinárias e preferenciais). Na bolsa, a
SAPR11 é uma **unit**: 1 ação ordinária + 4 preferenciais = 5 ações.

| Passo | Conta | Resultado |
|---|---|---|
| Composição declarada pela companhia (formulário cadastral da CVM) | — | **5 ações por unit** |
| Conferência pela medida: `ações correntes × preço ÷ valor de mercado` | 503.735.170 × 34,74 ÷ 3,61 bi | 4,85 → 5 (confere) |
| Contagem oficial da B3, líquida de tesouraria, em units | — | **302.241.104 units** |
| Contagem implícita no valor de mercado da fonte | 3,61 bi ÷ 34,74 | 103.850.066 |

As duas contagens divergem quase 3 vezes. O valor de mercado da fonte está
errado (ele parece contar só as ordinárias): 302,2 milhões de units × R$ 34,74
dão R$ 10,5 bi, que é o valor de mercado real da Sanepar. O registro oficial da
B3 arbitra (decisão 83).

> **Uma correção feita durante esta documentação (item B40):** um aviso dizia
> que "a ponte por papel usa a [contagem] implícita no valor de mercado" — as
> 103,9 milhões —, enquanto a conta usava as 302,2 milhões oficiais. O aviso
> agora nomeia a contagem que a conta usa.

**Por que importa:** dividir o capital próprio por 103,9 milhões em vez de 302,2
milhões daria um preço justo quase três vezes maior, e um "upside" falso de
+200%.

---

## 2. Caminho e custo do capital próprio

- Setor "utilidade pública", subsetor "água e saneamento"; NOPAT positivo em
  ≥ 60% dos anos → **via da firma**.
- `Ke = 14,09% + 0,6562 × 5,5% = 17,70%` (beta baixo: saneamento oscila pouco
  com o mercado).

---

## 3. O lucro de partida

```
alíquota estrutural = 25,2%   (a de 2025 foi 9,7%)
NOPAT 2025 = 2.337,5 × (1 − 25,2%) = R$ 1.748,5 mi
ROIC 2025  = 1.748,5 ÷ capital investido 2024 (15.659,3) = 11,16%
ROIC do ciclo = 13,47%
```

Sem tendência (`t` = 0,41) e com o último ano fora da banda (razão 0,83,
desvio robusto grande): **normaliza**.

```
fator = 13,47% ÷ 11,16% = 1,207
NOPAT de partida = 1.748,5 × 1,207 = R$ 2.109,6 mi
```

---

## 4. Crescimento

```
mediana = 10,03%;  regressão = 11,92%;  erro = 0,66 p.p.
discordância 2,88 (crítico 1,76), diferença 1,89 p.p. < máx(2; 2,5) p.p.
→ identificado: g = 10,03%;  g∞ = 6,78% (teto)
```

A retenção observada no passado foi de 80%: a Sanepar reinveste quase tudo,
como toda empresa de saneamento em expansão de rede.

---

## 5. O custo de capital

| Peça | Valor |
|---|---:|
| E (units × preço) | R$ 10,50 bi |
| Dívida bruta / caixa / dívida líquida | R$ 7,39 bi / R$ 5,61 bi / R$ 1,78 bi |
| Alavancagem 0,6× → prêmio | 1,3% |
| Kd | 15,39% |
| Escudo fiscal | **25,8%** (e não 34%) |

**Por que o escudo é menor:** a despesa financeira de 2025 (R$ 3,08 bi) foi
maior que o EBIT (cobertura de 0,76). Quando o lucro operacional não cobre os
juros, não há imposto suficiente para abater, e o motor reduz o escudo na
proporção: 34% × 0,76 = 25,8%.

**WACC de hoje:** `0,8547 × 17,70% + 0,6018 × 15,39% × (1 − 25,8%) − 0,4565 ×
14,09% × (1 − 34%) = 17,75%`. Resolvido ano a ano (30 iterações): WACC de
16,69% a 17,35%, **Ke de 17,35% a 17,98%**.

---

## 6. A perpetuidade de uma concessão

A vantagem residual é barrada por dois motivos:

1. **concessão**: a tarifa remunera o capital ao custo dele, e um negócio que
   será relicitado não preserva excedente sobre capital novo (decisão 50);
2. **sem excedente**: o ROIC do ciclo (13,47%) está abaixo do custo de
   equilíbrio (17,95%).

**E o prazo do contrato?** Quando o motor consegue ler o prazo da concessão no
Formulário de Referência, o terminal passa a ser "capital devolvido + excedente
até o fim do contrato" (decisão 88). Para a Sanepar, o prazo **não foi lido**:
o terminal fica perpétuo, com retorno neutro, e a tela mostra a ressalva
**"prazo determinado"** e um aviso explicando o que isso muda.

---

## 7. Os dez anos

Aqui o ROIC **sobe** do de partida (13,5%) para o WACC do ano (17,3%): a
convergência ao custo de capital funciona nos dois sentidos. Com o retorno
subindo e o crescimento caindo, a retenção cai de 74% para 39%, e o fluxo livre
cresce muito ao longo da projeção.

| Ano | g | ROIC | Retenção | NOPAT (R$ mi) | Fluxo da firma (R$ mi) | Serviço da dívida (R$ mi) | Fluxo do acionista (R$ mi) | Ke | Fator acumulado | Meio de ano | Valor presente (R$ mi) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 10,0% | 13,5% | 74,4% | 2.321,1 | 593,5 | 44,9 | 548,5 | 17,3% | 1,1735 | 1,0833 | 506,3 |
| 2 | 9,7% | 13,9% | 69,6% | 2.545,4 | 773,1 | 63,0 | 710,0 | 17,8% | 1,3829 | 1,0856 | 557,4 |
| 3 | 9,3% | 14,4% | 64,8% | 2.782,3 | 980,0 | 81,6 | 898,3 | 18,2% | 1,6341 | 1,0871 | 597,6 |
| 4 | 8,9% | 14,8% | 60,3% | 3.031,2 | 1.203,0 | 98,5 | 1.104,4 | 18,2% | 1,9318 | 1,0873 | 621,6 |
| 5 | 8,6% | 15,3% | 56,0% | 3.291,3 | 1.449,1 | 118,6 | 1.330,5 | 18,3% | 2,2860 | 1,0878 | 633,1 |
| 6 | 8,2% | 15,8% | 52,2% | 3.562,0 | 1.702,4 | 137,1 | 1.565,4 | 18,2% | 2,7027 | 1,0873 | 629,8 |
| 7 | 7,9% | 16,1% | 48,7% | 3.842,0 | 1.970,5 | 157,1 | 1.813,4 | 18,1% | 3,1924 | 1,0868 | 617,4 |
| 8 | 7,5% | 16,6% | 45,3% | 4.130,2 | 2.260,5 | 180,7 | 2.079,8 | 18,1% | 3,7701 | 1,0867 | 599,5 |
| 9 | 7,1% | 16,9% | 42,1% | 4.425,1 | 2.560,0 | 204,9 | 2.355,1 | 18,0% | 4,4491 | 1,0863 | 575,0 |
| 10 | 6,8% | 17,3% | 39,1% | 4.725,0 | 2.878,5 | 232,3 | 2.646,2 | 18,0% | 5,2491 | 1,0862 | 547,6 |
| **Soma** | | | | | | | | | | | **5.885,3** |

---

## 8. O terminal, convertido para o acionista

Retorno neutro (o crescimento sai da conta da firma):

```
VT da firma            = NOPAT₁₀ × 1,0678 ÷ 17,35% = 4.725,0 × 1,0678 ÷ 0,1735 = R$ 29.085,6 mi
fluxo da firma ano 11  = 29.085,6 × (17,35% − 6,78%)  = 3.073,7
fluxo do acionista     = 3.073,7 − 248,1 (serviço da dívida) = 2.825,6
VT do acionista        = 2.825,6 ÷ (17,98% − 6,78%) = 25.225,5
VP do terminal         = 25.225,5 × 1,0862 ÷ 5,2491 = R$ 5.219,9 mi
```

O terminal é 47% do capital próprio. O capital que já existe rende 14,2% na
perpetuidade, contra 17,3% de custo: esse déficit vale −R$ 1,26 bi a valor
presente, e já está dentro do terminal (item B12).

---

## 9. O preço justo

```
capital próprio = 5.885,3 + 5.219,9 − 0 (minoritários) = R$ 11.105,2 mi
preço justo     = 11.105,2 mi ÷ 302.241.104 units = R$ 36,74 por unit
                  (÷ 5 = R$ 7,35 por ação)
upside          = (36,74 − 34,74) ÷ 34,74 = +5,8%
```

---

## 10. Os números em volta

**Cenários:** R$ 32,63 / R$ 36,74 / R$ 43,30. **Monte Carlo:** P5 R$ 32,75,
mediana R$ 36,72, P95 R$ 41,40.

**Faixa calibrada (80%):** 12 meses, R$ 26,42 a R$ 55,89; 36 meses, R$ 23,88 a
R$ 76,24.

**Múltiplos de pares.** O subsetor "água e saneamento" não tem cinco outras
companhias, e a mediana vem do setor de utilidade pública (energia elétrica,
gás, saneamento):

| Leitura | Mediana (companhias) | Grandeza por unit | Preço |
|---|---:|---:|---:|
| P/L | 9,86 (27) | lucro R$ 6,88 | R$ 67,83 |
| P/VP | 1,87 (32) | patrimônio R$ 40,85 | R$ 76,49 |
| EV/EBITDA | 7,27 (32) | EBITDA R$ 2,96 bi, dívida líq. R$ 1,78 bi | R$ 65,38 |
| **Consolidada** | | | **R$ 67,83** |

**Divergência de +84,6%** — acima do limite de 50%, e a tela avisa. O preço justo
**não muda**: a leitura por pares é teste de sanidade, e a divergência fica
declarada (decisão 118).

**Por que tanta diferença.** O setor de utilidade pública, dominado por energia
elétrica, negocia a múltiplos maiores que a Sanepar (o próprio mercado paga só
0,85 vez o patrimônio dela, contra 1,87 da mediana do setor). O fluxo descontado
diz que a Sanepar rende 13,5% sobre o capital, abaixo dos 17–18% que o motor
exige — e o mercado parece concordar mais com o fluxo descontado do que com os
pares.

> **Uma correção feita durante esta documentação (item B41):** até 28/09/2026 a
> mediana dos "pares" de saneamento tinha sete entradas, três delas da própria
> Sanepar (SAPR3, SAPR4 e SAPR11). A mediana caía na Sanepar, e as leituras de
> P/VP e EV/EBITDA devolviam, as duas, R$ 38,15 — o preço da própria Sanepar na
> data do pacote. Agora cada companhia entra uma vez, e a avaliada não entra.

---

## 11. O que este caso ensina

- **Contar papéis é parte da avaliação.** O erro da fonte aqui seria de quase
  três vezes, e só a contagem oficial o evita.
- **Concessão muda a perpetuidade**, e o prazo lido do contrato muda mais ainda;
  sem ele, a ressalva avisa.
- **Duas leituras independentes podem discordar muito**, e o motor não escolhe
  uma: mostra as duas e mantém o preço do fluxo descontado.
