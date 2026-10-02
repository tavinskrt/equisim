# Caso ITUB4 — Itaú Unibanco, via do acionista (banco)

> **O que este caso mostra.** Um banco: a dívida é matéria-prima, então o motor
> pula a firma e desconta direto o lucro do acionista. Compare cada passo com o
> [caso WEGE3](wege3.md) — a tabela lado a lado está no
> [capítulo 5](../05-bancos.md), seção 5.3.
>
> **Data da avaliação:** 14/09/2026, entrada congelada
> ([dados/ITUB4.json](dados/ITUB4.json)).
>
> **Resultado:** preço justo **R$ 29,21**, contra R$ 42,35 de mercado — upside
> de **−31,0%**.

---

## 1. Os dados de partida

| Grandeza (exercício 2025) | Valor |
|---|---:|
| Lucro líquido | R$ 45,85 bi |
| Patrimônio líquido | R$ 215,08 bi |
| Minoritários | R$ 10,58 bi (já fora do lucro da controladora) |
| EBIT | **não publicado** — banco não tem |
| Preço de mercado | R$ 42,35 |
| Exercícios | 16 (2010–2025) |

---

## 2. Papéis e caminho

- **Unit:** 11.026.869.000 ações × R$ 42,35 ÷ R$ 458,6 bi = 1,02 → 1 ação por
  papel.
- **Contagem:** registro oficial da B3, líquido de tesouraria:
  **11.026.524.192** papéis.
- **Porta 1:** setor "financeiro", subsetor "Intermediários Financeiros /
  Bancos" → **via do acionista**. O aviso da tela explica: depósito e captação
  são insumo do negócio, e subtraí-los do valor trataria a matéria-prima como
  estrutura de capital.

> **O que não é feito, e por quê:** nada de NOPAT, capital investido, WACC,
> custo da dívida, desalavancagem do beta nem ponte da dívida. Todas essas
> contas separam operação de financiamento, e no banco as duas são a mesma
> coisa (capítulo 5, seção 5.1).

---

## 3. O custo do capital próprio

```
Ke de hoje = 14,09% + 0,9777 × 1,21% = 14,09% + 1,18% = 15,27%
```

O beta (0,98) sai de cinco anos de retornos diários com 81 proventos
reinvestidos, encolhido para o setor. **Não se desalavanca**: a alavancagem de
um banco é permanente e regulada, e o beta medido já a contém. Por isso também
não há ponto fixo: a taxa de cada ano é o forward daquele ano mais β × prêmio
(item B37, corrigido em 28/09/2026 — antes, sem a resolução, a taxa ia em linha
reta do CDI de hoje até a perpetuidade):

| Ano | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | ∞ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Forward | 13,62% | 14,13% | 14,46% | 14,51% | 14,63% | 14,53% | 14,42% | 14,40% | 14,32% | 14,29% | 14,29% |
| **Ke** | 14,8% | 15,3% | 15,7% | 15,7% | 15,8% | 15,7% | 15,6% | 15,6% | 15,5% | 15,5% | 15,47% |

Conferindo o ano 1: `13,62% + 0,9777 × 1,21% = 13,62% + 1,18% = 14,81%`. O
prêmio de 1,21% é a média de dez anos do prêmio implícito no preço da bolsa
(decisão 142; capítulo 3, seção 3.7).

---

## 4. O lucro de partida

```
LPA 2025 = 45.849 mi ÷ 11.026,5 mi papéis = R$ 4,158
ROE 2025 = lucro 2025 ÷ PL 2024 = 20,72%
ROE do ciclo = mediana dos oito exercícios anteriores = 18,43%
```

| Guarda | Resultado |
|---|---|
| 1 — tendência | −0,25 p.p./ano, `t` = −1,16: **não há tendência** |
| 2 — capital externo | Φ = 0,00: crescimento orgânico |
| 3 — desvio | o último ano **destoa** do ciclo |

Sem tendência que explique, o motor normaliza:

```
fator = ROE do ciclo ÷ ROE atual = 18,43% ÷ 20,72% = 0,889
LPA de partida = 4,158 × 0,889 = R$ 3,70
```

**Por quê:** o ROE de 2025 está acima do que o Itaú entregou na mediana de oito
anos, sem uma tendência estatística que diga que o patamar mudou. O motor supõe
que o ano bom não é o novo normal.

---

## 5. Quanto cresce

```
g pela mediana das variações do patrimônio   = 9,79%
g pela regressão do logaritmo do patrimônio  = 8,24%
erro-padrão = 0,5 p.p.;  discordância = 3,07 (crítico 1,76)
diferença = 1,55 p.p.  <  tolerância = máx(2 p.p.; 25% × 9,79%) = 2,45 p.p.
```

A discordância passa do crítico, mas a diferença absoluta é pequena: **crescimento
identificado, g = 9,79%** (capítulo 6, seção 6.6).

`g∞ = min(9,79%; 6,78%) = 6,78%`.

---

## 6. A perpetuidade: há vantagem competitiva?

```
excedente do ciclo = ROE do ciclo − Ke∞ = 18,43% − 15,47% = 2,96 p.p.
```

**Há excedente**: na mediana, o Itaú rende 18,43%, acima do custo de capital de
equilíbrio de 15,47%. A vantagem residual é concedida, mas a persistência medida
na própria série do banco é baixa (φ = 0,411, sobre 14 pares): em dez anos sobra
`λ = φ¹⁰ = 0,0001` do excedente. O retorno do capital novo na perpetuidade fica em
15,5%, o próprio custo — na prática, o **retorno neutro**: o capital novo rende o
custo, e o crescimento perpétuo não cria valor.

(Até 01/10/2026, com o prêmio de 5,5%, o custo de equilíbrio era 19,67% e o Itaú
não tinha excedente.)

---

## 7. Os dez anos

O ROE converge de 18,43% (o da base normalizada) ao Ke de cada ano; a retenção é
`g_t ÷ ROE_t`; o lucro distribuível é o LPA menos a retenção — o "dividendo
implícito" (capítulo 5, seção 5.4).

| Ano | g | Retenção | Ke | LPA (R$) | Distribuível (R$) | Fator acumulado | Meio de ano | Valor presente (R$) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 9,8% | 53,1% | 14,8% | 4,06 | 1,90 | 1,1481 | 1,0715 | 1,78 |
| 2 | 9,5% | 52,3% | 15,3% | 4,44 | 2,12 | 1,3238 | 1,0738 | 1,72 |
| 3 | 9,1% | 51,2% | 15,6% | 4,85 | 2,37 | 1,5309 | 1,0754 | 1,66 |
| 4 | 8,8% | 50,1% | 15,7% | 5,27 | 2,63 | 1,7712 | 1,0756 | 1,60 |
| 5 | 8,4% | 48,9% | 15,8% | 5,72 | 2,92 | 2,0513 | 1,0762 | 1,53 |
| 6 | 8,1% | 48,0% | 15,7% | 6,18 | 3,22 | 2,3737 | 1,0757 | 1,46 |
| 7 | 7,8% | 47,0% | 15,6% | 6,67 | 3,53 | 2,7441 | 1,0752 | 1,38 |
| 8 | 7,4% | 45,9% | 15,6% | 7,16 | 3,87 | 3,1719 | 1,0751 | 1,31 |
| 9 | 7,1% | 44,9% | 15,5% | 7,67 | 4,22 | 3,6635 | 1,0747 | 1,24 |
| 10 | 6,8% | 43,8% | 15,5% | 8,19 | 4,60 | 4,2304 | 1,0746 | 1,17 |
| **Soma** | | | | | | | | **14,85** |

(A soma das colunas arredondadas dá 14,85, que é também a exata.)

**Conferindo o ano 1:**

```
LPA₁ = 3,70 × 1,0979 = 4,06
retenção₁ = 9,79% ÷ 18,43% = 53,1%
distribuível₁ = 4,06 × (1 − 0,531) = 1,90
valor presente₁ = 1,90 × √1,1481 ÷ 1,1481 = 1,90 × 1,0716 ÷ 1,1481 = 1,78
```

---

## 8. O valor terminal

Retorno neutro — o crescimento sai da conta:

```
VT = LPA₁₁ ÷ Ke∞ = 8,19 × 1,0678 ÷ 15,47% = 8,745 ÷ 0,1547 = R$ 56,53
VP do terminal = 56,53 × 1,0746 ÷ 4,2304 = R$ 14,36
```

O terminal é 49,2% do preço justo.

**O que o retorno neutro não diz:** ele vale para o capital **novo**. O capital
que o banco já tem continua rendendo o que rende — o terminal implica 17,2% sobre
ele —, acima dos 15,5% de custo, e esse excedente do instalado já está dentro dos
R$ 14,36 (item B12).

---

## 9. O preço justo

```
preço justo = VP explícito + VP terminal = 14,85 + 14,36 = R$ 29,21
upside = (29,21 − 42,35) ÷ 42,35 = −31,0%
```

Não há dívida a subtrair nem minoritários a tirar: o lucro por papel já é do
acionista da controladora.

---

## 10. Os números em volta

**Cenários:** pessimista R$ 24,04; base R$ 29,21; otimista R$ 38,73. No Itaú o
otimista sai acima do pessimista, porque o retorno passa o custo e crescer cria
valor. No banco cujo retorno fica abaixo do custo, o crescimento +3 p.p.
**baixaria** o preço justo (item B38; capítulo 5, seção 5.7).

**Monte Carlo:** P5 = R$ 25,64; mediana = R$ 29,19; P95 = R$ 34,22.

**Faixa calibrada (80%):** 12 meses, R$ 33,80 a R$ 61,32; 36 meses, R$ 30,24 a
R$ 76,41.

**Múltiplos de pares** (16 bancos, cada um uma vez, sem o Itaú):

| Leitura | Mediana | Grandeza por papel | Preço |
|---|---:|---:|---:|
| P/L | 7,10 | lucro R$ 4,158 | R$ 29,54 |
| P/VP | 0,92 | patrimônio R$ 19,50 | R$ 18,00 |
| EV/EBITDA | — | **recusado**: instituição financeira | — |
| **Consolidada** | | | **R$ 23,77** |

Divergência de −18,6% em relação ao preço justo: dentro do limite de 50%. (Até
28/09/2026 a mediana contava cada classe de ação como um "par" e incluía o
próprio Itaú: eram 31; item B41.)

**Ressalvas:** nenhuma.

---

## 11. Por que o banco sai abaixo do mercado?

O mercado paga 10,2 vezes o lucro do Itaú (R$ 42,35 ÷ R$ 4,158). O motor chega a
7,0 vezes, e a um P/VP de 1,5, contra 2,2 no mercado. **O motor diz que o capital
do Itaú custa cerca de 15% ao ano e rende 18%**: crescer cria valor, mas menos do
que o mercado paga, por três motivos declarados:

1. **A base é normalizada**: o ROE de 2025 (20,7%) volta à mediana de oito anos
   (18,4%).
2. **O excedente some depressa**: a persistência medida na série do banco é
   baixa, e na perpetuidade o capital novo rende só o custo.
3. **O crescimento perpétuo tem teto** no crescimento nominal da economia
   (6,78%).

Duas leituras possíveis, e o motor não arbitra entre elas:

- o mercado exige menos que 15,3% do Itaú;
- o mercado espera ROE acima de 20% por muito tempo.

É o mesmo viés de nível da WEGE3, e das [limitações](../../validacao/limitacoes.md).
