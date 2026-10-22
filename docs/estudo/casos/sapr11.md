# Caso SAPR11 — Sanepar: unit, concessão e a leitura por pares

> **O que este caso mostra.** Três coisas que não aparecem nos outros casos: a
> **unit** (um papel que é um pacote de 5 ações), a **concessão** (um negócio
> que opera sob contrato) e uma **divergência grande entre o fluxo descontado e
> os múltiplos dos pares** — que o motor declara, sem mudar o preço justo.
>
> **Data:** 14/09/2026 ([dados/SAPR11.json](dados/SAPR11.json)).
>
> **Resultado:** preço justo **R$ 46,05 por unit** (R$ 9,21 por ação), contra
> R$ 34,74 de mercado — upside de **+32,6%**. Ressalvas: **prazo determinado** e
> **controle estatal**.

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
- `Ke = 14,09% + 0,6562 × 1,21% = 14,88%` (beta baixo: saneamento oscila pouco
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

**WACC de hoje:** `0,8547 × 14,88% + 0,6018 × 15,39% × (1 − 25,8%) − 0,4565 ×
14,09% × (1 − 34%) = 15,34%`. Resolvido ano a ano (30 iterações): WACC de
14,21% a 14,86%, **Ke de 14,43% a 15,09%**.

---

## 6. A perpetuidade de uma concessão

A vantagem residual é barrada por dois motivos:

1. **concessão**: a tarifa remunera o capital ao custo dele, e um negócio que
   será relicitado não preserva excedente sobre capital novo (decisão 50);
2. **sem excedente**: o ROIC do ciclo (13,47%) está abaixo do custo de
   equilíbrio (14,86%).

**E o prazo do contrato?** Quando o motor consegue ler o prazo da concessão no
Formulário de Referência, o terminal passa a ser "capital devolvido + excedente
até o fim do contrato" (decisão 88). Para a Sanepar, o prazo **não foi lido**:
o terminal fica perpétuo, com retorno neutro, e a tela mostra a ressalva
**"prazo determinado"** e um aviso explicando o que isso muda.

---

## 7. Os dez anos

Aqui o ROIC **sobe** do de partida (13,5%) para o WACC do ano (14,9%): a
convergência ao custo de capital funciona nos dois sentidos. Com o retorno
subindo e o crescimento caindo, a retenção cai de 74% para 39%, e o fluxo livre
cresce muito ao longo da projeção.

| Ano | g | ROIC | Retenção | NOPAT (R$ mi) | Fluxo da firma (R$ mi) | Serviço da dívida (R$ mi) | Fluxo do acionista (R$ mi) | Ke | Fator acumulado | Meio de ano | Valor presente (R$ mi) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 10,0% | 13,5% | 74,4% | 2.321,1 | 593,5 | 44,9 | 548,5 | 14,4% | 1,1443 | 1,0697 | 512,8 |
| 2 | 9,7% | 13,6% | 71,0% | 2.545,4 | 737,3 | 63,0 | 674,3 | 14,9% | 1,3151 | 1,0720 | 549,6 |
| 3 | 9,3% | 13,8% | 67,4% | 2.782,3 | 908,3 | 81,6 | 826,7 | 15,3% | 1,5158 | 1,0736 | 585,5 |
| 4 | 8,9% | 14,0% | 63,9% | 3.031,2 | 1.095,2 | 98,5 | 996,7 | 15,3% | 1,7480 | 1,0738 | 612,3 |
| 5 | 8,6% | 14,2% | 60,3% | 3.291,3 | 1.306,5 | 118,6 | 1.187,9 | 15,4% | 2,0177 | 1,0744 | 632,5 |
| 6 | 8,2% | 14,4% | 57,2% | 3.562,0 | 1.524,0 | 137,1 | 1.387,0 | 15,3% | 2,3271 | 1,0739 | 640,1 |
| 7 | 7,9% | 14,5% | 54,3% | 3.842,0 | 1.756,5 | 157,1 | 1.599,4 | 15,2% | 2,6814 | 1,0734 | 640,3 |
| 8 | 7,5% | 14,6% | 51,2% | 4.130,2 | 2.013,6 | 180,7 | 1.832,9 | 15,2% | 3,0892 | 1,0733 | 636,9 |
| 9 | 7,1% | 14,7% | 48,5% | 4.425,1 | 2.280,1 | 204,9 | 2.075,2 | 15,1% | 3,5562 | 1,0729 | 626,1 |
| 10 | 6,8% | 14,9% | 45,6% | 4.725,0 | 2.569,5 | 232,3 | 2.337,1 | 15,1% | 4,0929 | 1,0728 | 612,6 |
| **Soma** | | | | | | | | | | | **6.048,6** |

---

## 8. O terminal, convertido para o acionista

Retorno neutro (o crescimento sai da conta da firma):

```
VT da firma            = NOPAT₁₀ × 1,0678 ÷ 14,86% = 4.725,0 × 1,0678 ÷ 0,1486 = R$ 33.954,1 mi
fluxo da firma ano 11  = 33.954,1 × (14,86% − 6,78%)  = 2.743,6
fluxo do acionista     = 2.743,6 − 248,1 (serviço da dívida) = 2.495,6
VT do acionista        = 2.495,6 ÷ (15,09% − 6,78%) = 30.024,8
VP do terminal         = 30.024,8 × 1,0728 ÷ 4,0929 = R$ 7.869,9 mi
```

O terminal é 56,5% do capital próprio. O capital que já existe rende 13,6% na
perpetuidade, contra 14,9% de custo: esse déficit vale −R$ 0,80 bi a valor
presente, e já está dentro do terminal (item B12).

---

## 9. O preço justo

```
capital próprio = 6.048,6 + 7.869,9 − 0 (minoritários) = R$ 13.918,6 mi
preço justo     = 13.918,6 mi ÷ 302.241.104 units = R$ 46,05 por unit
                  (÷ 5 = R$ 9,21 por ação)
upside          = (46,05 − 34,74) ÷ 34,74 = +32,6%
```

---

## 10. Os números em volta

**Cenários:** R$ 39,10 / R$ 46,05 / R$ 57,25. **Monte Carlo:** P5 R$ 40,34,
mediana R$ 46,02, P95 R$ 52,93.

**Faixa calibrada (80%):** 12 meses, R$ 26,21 a R$ 55,49; 36 meses, R$ 23,10 a
R$ 75,33.

**Múltiplos de pares.** O subsetor "água e saneamento" não tem cinco outras
companhias, e a mediana vem do setor de utilidade pública (energia elétrica,
gás, saneamento):

| Leitura | Mediana (companhias) | Grandeza por unit | Preço |
|---|---:|---:|---:|
| P/L | 9,86 (27) | lucro R$ 6,88 | R$ 67,83 |
| P/VP | 1,87 (32) | patrimônio R$ 40,85 | R$ 76,49 |
| EV/EBITDA | 7,27 (32) | EBITDA R$ 2,96 bi, dívida líq. R$ 1,78 bi | R$ 65,38 |
| **Consolidada** | | | **R$ 67,83** |

**Divergência de +47,3%** — abaixo do limite de 50%, e a tela não avisa (com o
prêmio de 5,5%, até 01/10/2026, o preço justo era R$ 36,74 e a divergência,
+84,6%, avisava). O preço justo **não muda**: a leitura por pares é teste de sanidade, e a divergência fica
declarada (decisão 118).

**Por que tanta diferença.** O setor de utilidade pública, dominado por energia
elétrica, negocia a múltiplos maiores que a Sanepar (o próprio mercado paga só
0,85 vez o patrimônio dela, contra 1,87 da mediana do setor). O fluxo descontado
diz que a Sanepar rende 13,5% sobre o capital, abaixo dos 15% que o motor
exige — e o preço justo fica entre o mercado e os
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
- **Estatal não paga taxa maior no motor, e a tela diz isso.** A Sanepar é
  controlada pelo governo do Paraná, e a avaliação leva a ressalva **controle
  estatal**. O motor não soma prêmio ao custo de capital: medido, o beta das
  estatais é menor que o das privadas, e a exposição delas ao risco do país não
  é maior; o risco de o controlador decidir por outros objetivos que o lucro
  fica no fluxo do minoritário ([estatais.md](../../validacao/estatais.md)).
