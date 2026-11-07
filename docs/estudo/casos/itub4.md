# Caso ITUB4 — Itaú Unibanco, via do acionista (banco)

> **O que este caso mostra.** Um banco: a dívida é matéria-prima, então o motor
> pula a firma e desconta direto o lucro do acionista. Compare cada passo com o
> [caso WEGE3](wege3.md) — a tabela lado a lado está no
> [capítulo 5](../05-bancos.md), seção 5.3.
>
> **Data da avaliação:** 14/09/2026, entrada congelada, com o motor de
> 03/11/2026 ([dados/ITUB4.json](dados/ITUB4.json)).
>
> **Resultado:** preço justo **R$ 28,53**, contra R$ 42,35 de mercado — upside
> de **−32,6%**.

---

## 1. Os dados de partida

| Grandeza (2026 anualizado) | Valor |
|---|---:|
| Lucro líquido | R$ 48,40 bi |
| Patrimônio líquido | R$ 228,03 bi |
| Minoritários | R$ 10,25 bi (já fora do lucro da controladora) |
| EBIT | **não publicado** — banco não tem |
| Preço de mercado | R$ 42,35 |
| Exercícios | 17 (2010–2026) |

**O último ponto é 2026 anualizado**: o lucro acumulado do
primeiro semestre, no ITR de 30/06/2026, vezes 2, com o balanço da mesma data. A
anualização supõe que o segundo semestre repete o primeiro, sem correção de
sazonalidade, e multiplica junto o que for não recorrente; a tela declara isso
num aviso.

---

## 2. Papéis e caminho

- **Unit:** 11.026.869.000 ações × R$ 42,35 ÷ R$ 426,6 bi = 1,09 → 1 ação por
  papel.
- **Contagem:** registro oficial da B3, líquido de tesouraria:
  **11.021.872.192** papéis.
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
Ke de hoje = 14,05% + 1,0020 × 1,21% = 14,05% + 1,21% = 15,26%
```

O beta (1,00) sai de cinco anos de retornos diários com 81 proventos
reinvestidos, encolhido para o setor. **Não se desalavanca**: a alavancagem de
um banco é permanente e regulada, e o beta medido já a contém. Por isso também
não há ponto fixo: a taxa de cada ano é o forward daquele ano mais β × prêmio
(a taxa segue a curva ano a ano, e não uma reta do CDI de hoje até a
perpetuidade):

| Ano | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | ∞ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Forward | 13,67% | 14,16% | 14,48% | 14,53% | 14,70% | 14,58% | 14,46% | 14,44% | 14,40% | 14,38% | 14,38% |
| **Ke** | 14,89% | 15,38% | 15,69% | 15,74% | 15,91% | 15,79% | 15,68% | 15,66% | 15,61% | 15,59% | 15,59% |

Conferindo o ano 1: `13,67% + 1,0020 × 1,21% = 13,67% + 1,21% = 14,89%` (com o
forward sem arredondar, 13,672%). O prêmio de 1,21% é a média de dez anos do
prêmio implícito no preço da bolsa (capítulo 3, seção 3.7).

---

## 4. O lucro de partida

```
LPA 2026 (anualizado) = 48.398 mi ÷ 11.021,9 mi papéis = R$ 4,391
ROE 2026 = lucro 2026 anualizado ÷ PL 2025 = 48.398 ÷ 215.076 = 22,50%
ROE do ciclo = mediana dos oito exercícios anteriores (2018–2025) = 18,59%
```

| Guarda | Resultado |
|---|---|
| 1 — tendência | −0,14 p.p./ano, `t` = −0,72: **não há tendência** |
| 2 — capital externo | Φ = 0,00: crescimento orgânico |
| 3 — desvio | o último ano **destoa** do ciclo: está a 2,97 desvios típicos dele |

A razão entre os dois retornos (22,50% ÷ 18,59% = 1,21) fica dentro da faixa de
0,75 a 1,33, mas a distância passa de 1,5 desvios, e isso basta para destoar
([normalizacoes.md](../../validacao/normalizacoes.md)). Sem tendência que
explique, o motor normaliza:

```
fator = ROE do ciclo ÷ ROE atual = 18,59% ÷ 22,50% = 0,826
LPA de partida = 4,391 × 0,826 = R$ 3,63
```

**Por quê:** o ROE de 2026 está acima do que o Itaú entregou na mediana de oito
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

`g∞ = min(9,79%; 6,83%) = 6,83%`.

---

## 6. A perpetuidade: há vantagem competitiva?

```
excedente do ciclo = ROE do ciclo − Ke∞ = 18,59% − 15,59% = 2,99 p.p.  (sem arredondar)
```

**Há excedente**: na mediana, o Itaú rende 18,59%, acima do custo de capital de
equilíbrio de 15,59%. A vantagem residual é concedida, mas a persistência medida
na própria série do banco é baixa (φ = 0,424, sobre 15 pares: o excedente perde
57,6% por ano), e em dez anos sobra `λ = φ¹⁰ = 0,0002` dele. O retorno do capital
novo na perpetuidade fica em 15,59%, o próprio custo — na prática, o **retorno
neutro**: o capital novo rende o custo, e o crescimento perpétuo não cria valor.

(Até 01/10/2026, com o prêmio de 5,5%, o custo de equilíbrio era 19,67% e o Itaú
não tinha excedente.)

---

## 7. Os dez anos

O ROE converge de 18,59% (o da base normalizada) ao Ke de cada ano; a retenção é
`g_t ÷ ROE_t`; o lucro distribuível é o LPA menos a retenção — o "dividendo
implícito" (capítulo 5, seção 5.4).

| Ano | g | Retenção | Ke | LPA (R$) | Distribuível (R$) | Fator acumulado | Meio de ano | Valor presente (R$) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 9,8% | 52,6% | 14,9% | 3,98 | 1,89 | 1,1489 | 1,0718 | 1,76 |
| 2 | 9,5% | 51,9% | 15,4% | 4,36 | 2,10 | 1,3255 | 1,0741 | 1,70 |
| 3 | 9,1% | 50,9% | 15,7% | 4,76 | 2,34 | 1,5335 | 1,0756 | 1,64 |
| 4 | 8,8% | 49,9% | 15,7% | 5,17 | 2,59 | 1,7749 | 1,0758 | 1,57 |
| 5 | 8,5% | 48,7% | 15,9% | 5,61 | 2,88 | 2,0573 | 1,0766 | 1,51 |
| 6 | 8,1% | 47,8% | 15,8% | 6,07 | 3,17 | 2,3822 | 1,0761 | 1,43 |
| 7 | 7,8% | 46,9% | 15,7% | 6,54 | 3,47 | 2,7557 | 1,0755 | 1,36 |
| 8 | 7,5% | 45,9% | 15,7% | 7,03 | 3,81 | 3,1871 | 1,0754 | 1,28 |
| 9 | 7,2% | 44,9% | 15,6% | 7,54 | 4,15 | 3,6846 | 1,0752 | 1,21 |
| 10 | 6,8% | 43,8% | 15,6% | 8,05 | 4,53 | 4,2591 | 1,0751 | 1,14 |
| **Soma** | | | | | | | | **14,60** |

(A soma das colunas arredondadas dá 14,60; a exata é 14,603.)

**Conferindo o ano 1:**

```
LPA₁ = 3,63 × 1,0979 = 3,98
retenção₁ = 9,79% ÷ 18,59% ≈ 52,6%
distribuível₁ = 3,98 × (1 − 0,526) = 1,89
valor presente₁ = 1,89 × √1,1489 ÷ 1,1489 = 1,89 × 1,0718 ÷ 1,1489 = 1,76
```

O motor divide `g` e o ROE sem arredondar e chega a 52,6%; com os dois
arredondados a duas casas, a divisão dá 52,66%, e o distribuível, R$ 1,88. A
diferença é de arredondamento, e não de regra.

---

## 8. O valor terminal

Retorno neutro — o crescimento sai da conta:

```
VT = LPA₁₁ ÷ Ke∞ = 8,05 × 1,0683 ÷ 15,59% = 8,600 ÷ 0,1559 = R$ 55,16
VP do terminal = 55,16 × 1,0751 ÷ 4,2591 = R$ 13,92
```

O terminal é 48,8% do preço justo.

**O que o retorno neutro não diz:** ele vale para o capital **novo**. O capital
que o banco já tem continua rendendo o que rende — o terminal implica 17,3% sobre
ele —, acima dos 15,6% de custo, e esse excedente do instalado já está dentro dos
R$ 13,92.

---

## 9. O preço justo

```
preço justo = VP explícito + VP terminal = 14,603 + 13,924 = R$ 28,53
upside = (28,53 − 42,35) ÷ 42,35 = −32,6%
```

Não há dívida a subtrair nem minoritários a tirar: o lucro por papel já é do
acionista da controladora.

---

## 10. Os números em volta

**Sensibilidade:** premissas mais duras R$ 23,51; as do motor R$ 28,53; premissas
mais brandas R$ 37,72. No Itaú as mais brandas saem acima das mais duras,
porque o retorno passa o custo e crescer cria valor. No banco cujo retorno fica
abaixo do custo, o crescimento +3 p.p. **baixaria** o preço justo (capítulo 5, seção 5.7).

**Monte Carlo:** P5 = R$ 25,06; mediana = R$ 28,51; P95 = R$ 33,37.

**Faixa calibrada (80%):** 12 meses, R$ 33,74 a R$ 61,44; 36 meses, R$ 30,87 a
R$ 78,93. A conta é a mesma do [caso WEGE3](wege3.md), seção 13, com a
volatilidade do Itaú no último ano (24,6%).

**Múltiplos de pares** (16 bancos, cada um uma vez, sem o Itaú):

| Leitura | Mediana | Grandeza por papel | Preço |
|---|---:|---:|---:|
| P/L | 7,10 | lucro R$ 4,391 | R$ 31,19 |
| P/VP | 0,92 | patrimônio R$ 20,69 | R$ 19,09 |
| EV/EBITDA | — | **recusado**: instituição financeira | — |
| **Consolidada** | | | **R$ 25,14** |

Divergência de −11,9% em relação ao preço justo: dentro do limite de 50%.

**Ressalvas:** nenhuma.

---

## 11. Por que o banco sai abaixo do mercado?

O mercado paga 9,6 vezes o lucro anualizado do Itaú (R$ 42,35 ÷ R$ 4,391). O
motor chega a 6,5 vezes, e a um P/VP de 1,4, contra 2,0 no mercado. **O motor diz
que o capital do Itaú custa cerca de 15% ao ano e rende 18,6%**: crescer cria
valor, mas menos do que o mercado paga, por três motivos declarados:

1. **A base é normalizada**: o ROE de 2026 anualizado (22,5%) volta à mediana de
   oito anos (18,6%).
2. **O excedente some depressa**: a persistência medida na série do banco é
   baixa, e na perpetuidade o capital novo rende só o custo.
3. **O crescimento perpétuo tem teto** no crescimento nominal da economia
   (6,83%).

Duas leituras possíveis, e o motor não arbitra entre elas:

- o mercado exige menos que 15,3% do Itaú;
- o mercado espera ROE acima de 20% por muito tempo.

É o mesmo viés de nível da WEGE3, e das [limitações](../../validacao/limitacoes.md).
