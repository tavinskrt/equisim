# Caso ITUB4 — Itaú Unibanco, via do acionista (banco)

> **O que este caso mostra.** Um banco: a dívida é matéria-prima, então o motor
> pula a firma e desconta direto o lucro do acionista. Compare cada passo com o
> [caso WEGE3](wege3.md) — a tabela lado a lado está no
> [capítulo 5](../05-bancos.md), seção 5.3.
>
> **Data da avaliação:** 14/09/2026, entrada congelada
> ([dados/ITUB4.json](dados/ITUB4.json)).
>
> **Resultado:** preço justo **R$ 21,76**, contra R$ 42,35 de mercado — upside
> de **−48,6%**.

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
Ke de hoje = 14,09% + 0,9777 × 5,5% = 14,09% + 5,38% = 19,46%
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
| **Ke** | 19,0% | 19,5% | 19,8% | 19,9% | 20,0% | 19,9% | 19,8% | 19,8% | 19,7% | 19,7% | 19,67% |

Conferindo o ano 1: `13,62% + 0,9777 × 5,5% = 13,62% + 5,38% = 19,00%`.

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
excedente do ciclo = ROE do ciclo − Ke∞ = 18,43% − 19,67% = −1,24 p.p.
```

**Não há excedente**: na mediana, o Itaú rende abaixo do custo que o motor
atribui ao capital dele. A vantagem residual é barrada ("sem excedente"), e vale
o **retorno neutro**: o capital novo rende o custo, e o crescimento perpétuo não
cria valor.

---

## 7. Os dez anos

O ROE converge de 18,43% (o da base normalizada) ao Ke de cada ano; a retenção é
`g_t ÷ ROE_t`; o lucro distribuível é o LPA menos a retenção — o "dividendo
implícito" (capítulo 5, seção 5.4).

| Ano | g | Retenção | Ke | LPA (R$) | Distribuível (R$) | Fator acumulado | Meio de ano | Valor presente (R$) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 9,8% | 53,1% | 19,0% | 4,06 | 1,90 | 1,1900 | 1,0909 | 1,75 |
| 2 | 9,5% | 51,0% | 19,5% | 4,44 | 2,18 | 1,4221 | 1,0932 | 1,68 |
| 3 | 9,1% | 48,7% | 19,8% | 4,85 | 2,49 | 1,7042 | 1,0947 | 1,60 |
| 4 | 8,8% | 46,4% | 19,9% | 5,27 | 2,83 | 2,0431 | 1,0949 | 1,51 |
| 5 | 8,4% | 44,2% | 20,0% | 5,72 | 3,19 | 2,4519 | 1,0955 | 1,43 |
| 6 | 8,1% | 42,2% | 19,9% | 6,18 | 3,58 | 2,9401 | 1,0950 | 1,33 |
| 7 | 7,8% | 40,2% | 19,8% | 6,67 | 3,98 | 3,5222 | 1,0945 | 1,24 |
| 8 | 7,4% | 38,2% | 19,8% | 7,16 | 4,42 | 4,2190 | 1,0944 | 1,15 |
| 9 | 7,1% | 36,4% | 19,7% | 7,67 | 4,88 | 5,0499 | 1,0941 | 1,06 |
| 10 | 6,8% | 34,5% | 19,7% | 8,19 | 5,37 | 6,0430 | 1,0939 | 0,97 |
| **Soma** | | | | | | | | **13,71** |

(A soma das colunas arredondadas dá 13,72; a exata é 13,71.)

**Conferindo o ano 1:**

```
LPA₁ = 3,70 × 1,0979 = 4,06
retenção₁ = 9,79% ÷ 18,43% = 53,1%
distribuível₁ = 4,06 × (1 − 0,531) = 1,90
valor presente₁ = 1,90 × √1,19 ÷ 1,19 = 1,90 × 1,0909 ÷ 1,1900 = 1,75
```

---

## 8. O valor terminal

Retorno neutro — o crescimento sai da conta:

```
VT = LPA₁₁ ÷ Ke∞ = 8,19 × 1,0678 ÷ 19,67% = 8,745 ÷ 0,1967 = R$ 44,47
VP do terminal = 44,47 × 1,0939 ÷ 6,0430 = R$ 8,05
```

O terminal é 37,0% do preço justo.

**O que o retorno neutro não diz:** ele vale para o capital **novo**. O capital
que o banco já tem continua rendendo 18,4% na perpetuidade, contra 19,7% de
custo. Esse déficit vale −R$ 0,53 por papel a valor presente, e já está dentro
dos R$ 8,05 (item B12).

---

## 9. O preço justo

```
preço justo = VP explícito + VP terminal = 13,71 + 8,05 = R$ 21,76
upside = (21,76 − 42,35) ÷ 42,35 = −48,6%
```

Não há dívida a subtrair nem minoritários a tirar: o lucro por papel já é do
acionista da controladora.

---

## 10. Os números em volta

**Cenários:** pessimista R$ 19,44; base R$ 21,76; otimista R$ 25,03. No Itaú o
otimista sai acima do pessimista. Em 10 dos 19 bancos e financeiras avaliados
em 14/09/2026, só o crescimento +3 p.p. **baixa** o preço justo, porque o
retorno fica abaixo do custo (item B38; capítulo 5, seção 5.7).

**Monte Carlo:** P5 = R$ 20,07; mediana = R$ 21,74; P95 = R$ 23,75.

**Faixa calibrada (80%):** 12 meses, R$ 33,97 a R$ 61,60; 36 meses, R$ 30,45 a
R$ 76,59.

**Múltiplos de pares** (16 bancos, cada um uma vez, sem o Itaú):

| Leitura | Mediana | Grandeza por papel | Preço |
|---|---:|---:|---:|
| P/L | 7,10 | lucro R$ 4,158 | R$ 29,54 |
| P/VP | 0,92 | patrimônio R$ 19,50 | R$ 18,00 |
| EV/EBITDA | — | **recusado**: instituição financeira | — |
| **Consolidada** | | | **R$ 23,77** |

Divergência de +9,2% em relação ao preço justo: dentro do limite de 50%. (Até
28/09/2026 a mediana contava cada classe de ação como um "par" e incluía o
próprio Itaú: eram 31; item B41.)

**Ressalvas:** nenhuma.

---

## 11. Por que o banco sai tão abaixo do mercado?

O mercado paga 10,2 vezes o lucro do Itaú (R$ 42,35 ÷ R$ 4,158). O motor chega a
5,2 vezes. A diferença vem de uma conta só: **o motor diz que o capital do Itaú
custa 19–20% ao ano e rende 18%**. Com retorno abaixo do custo, reter lucro para
crescer destrói valor, e o banco vale menos que o próprio patrimônio (P/VP de
1,1 pelo motor, contra 2,2 no mercado).

Duas leituras possíveis, e o motor não arbitra entre elas:

- o mercado exige menos que 19,5% do Itaú (um prêmio ou uma taxa livre de risco
  menores que os do motor);
- o mercado espera ROE acima de 20% por muito tempo.

É o mesmo viés de nível da WEGE3, e das [limitações](../../validacao/limitacoes.md).
