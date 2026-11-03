# Caso SAPR11 — Sanepar: unit, concessão e a leitura por pares

> **O que este caso mostra.** Quatro coisas que não aparecem juntas nos outros
> casos: a **unit** (um papel que é um pacote de 5 ações), a **concessão** (um
> negócio que opera sob contrato), a **trava de saúde** segurando uma
> normalização para cima e uma **divergência grande entre o fluxo descontado e
> os múltiplos dos pares** — que o motor declara, sem mudar o preço justo.
>
> **Data:** 14/09/2026, entrada congelada, com o motor de 03/11/2026
> ([dados/SAPR11.json](dados/SAPR11.json)).
>
> **Resultado:** preço justo **R$ 27,76 por unit** (R$ 5,55 por ação), contra
> R$ 34,74 de mercado — upside de **−20,1%**. Ressalvas: **prazo determinado** e
> **controle estatal**.
>
> **Por que mudou tanto.** Até a contagem de 14/09 feita com o motor de outubro,
> o resultado era R$ 46,05 e +32,6%. Com a decisão 153, o último ponto passou a
> ser o primeiro semestre de 2026 vezes 2, e esse semestre traz prejuízo. A
> seção 3 mostra o caminho.

---

## 1. A unit: por quantas ações dividir

A Sanepar tem 1.511.205.500 ações (ordinárias e preferenciais). Na bolsa, a
SAPR11 é uma **unit**: 1 ação ordinária + 4 preferenciais = 5 ações.

| Passo | Conta | Resultado |
|---|---|---|
| Composição declarada pela companhia (formulário cadastral da CVM) | — | **5 ações por unit** |
| Conferência pela medida: `ações da fonte × preço ÷ valor de mercado` | 302.241.100 × 34,74 ÷ 9,32 bi | 1,13 → 1 (não confere) |
| Contagem oficial da B3, líquida de tesouraria, em units | — | **302.241.104 units** |
| Contagem implícita no valor de mercado da fonte | 9,32 bi ÷ 34,74 | 268.397.753 |
| Contagem das demonstrações, convertida em units | 302.241.100 ÷ 5 | 60.448.220 |

A conferência não fecha porque a fonte já entrega as ações contadas em units
(302,2 milhões, e não 1,5 bilhão). Quando a medida e a composição declarada
divergem, vale a declarada (item B16), e a tela diz por quê: a razão medida só
devolve o número de ações da unit quando as espécies valem o mesmo.

As duas contagens da fonte divergem 4,4 vezes, acima da banda de 1,5×. O
registro oficial da B3 arbitra (decisão 83): 302,2 milhões de units × R$ 34,74
dão R$ 10,50 bi, que é o valor de mercado real da Sanepar.

> **Uma correção feita durante esta documentação (item B40):** um aviso nomeava
> a contagem implícita no valor de mercado como a da ponte por papel, enquanto a
> conta usava a oficial. O aviso agora nomeia a contagem que a conta usa.

**Por que importa:** dividir o capital próprio pelas 60,4 milhões das
demonstrações em vez das 302,2 milhões oficiais daria R$ 138,79 por unit, e um
"upside" falso de +300%.

---

## 2. Caminho e custo do capital próprio

- Setor "utilidade pública", subsetor "água e saneamento"; NOPAT positivo em
  ≥ 60% dos anos → **via da firma**.
- `Ke = 14,05% + 0,6567 × 1,21% = 14,05% + 0,79% = 14,84%` (beta baixo:
  saneamento oscila pouco com o mercado; desalavancado, 0,4857).

---

## 3. O lucro de partida e a trava de saúde

**O último ponto.** O primeiro semestre de 2026 da Sanepar tem lucro antes do
imposto de R$ 314,6 mi e imposto de R$ 467,1 mi: o imposto passa o lucro, e o
semestre fecha com prejuízo. Vezes 2, o ano anualizado tem lucro antes do
imposto de R$ 629,3 mi, imposto de R$ 934,2 mi e **prejuízo de R$ 305,0 mi**,
contra lucro de R$ 2,08 bi em 2025. O EBIT, que vem antes dos juros e do
imposto, cai bem menos: de R$ 2,34 bi para R$ 2,07 bi. A tela avisa que a
anualização "multiplica junto o que for não recorrente", e o motor não tem como
saber se esse imposto se repete.

```
alíquota estrutural = 25,5%   (mediana dos 17 pontos; a de 2025 foi 9,7%)
NOPAT 2026 = 2.072,9 × (1 − 25,5%) = R$ 1.544,5 mi
ROIC 2026  = 1.544,5 ÷ capital investido 2025 (14.132,3) = 10,93%
ROIC do ciclo = mediana de 2018–2025 = 13,42%
```

Os oito retornos do ciclo, em ordem: 11,1%, 12,2%, 12,4%, 13,0%, 13,8%, 13,9%,
14,4% e 14,9%; a mediana é `(13,03% + 13,81%) ÷ 2 = 13,42%`.

Sem tendência (−0,01 p.p. ao ano, `t` = −0,07) e com o último ponto fora da
banda (razão 0,814, a 1,71 desvio robusto), a normalização **pediria** levar a
base ao típico:

```
fator bruto = 13,42% ÷ 10,93% = 1,228
```

**Mas a trava de saúde segura o fator em 1,00.** O lucro líquido caiu 120,3% no
triênio — de R$ 1,50 bi em 2023 para o prejuízo de R$ 305,0 mi —, acima do
máximo de 50%. A regra (capítulo 4, seção 4.4) diz que uma empresa que perdeu
mais da metade do resultado pode ter mudado de patamar, e trazer a base de volta
à mediana atribuiria a ela um retorno que talvez não volte. A Sanepar não é de
setor cíclico, então não há isenção. Base de partida: **R$ 1.544,5 mi**, o
NOPAT anualizado sem mudança.

Compare com a [Unipar](unip6.md), em que a trava não age porque o setor é de
commodity, e com a [Randon](rapt4.md), em que ela age e a conta acaba recusada.

---

## 4. Crescimento

```
mediana = 10,03%;  regressão = 11,92%;  erro = 0,66 p.p.
discordância 2,88 (crítico 1,76), diferença 1,89 p.p. < máx(2; 2,5) p.p.
→ identificado: g = 10,03%;  g∞ = 6,83% (teto)
```

A retenção observada no passado foi de 80%: a Sanepar reinveste quase tudo,
como toda empresa de saneamento em expansão de rede.

---

## 5. O custo de capital

| Peça | Valor |
|---|---:|
| E (units × preço) | R$ 10,50 bi |
| Dívida bruta / caixa / dívida líquida | R$ 7,25 bi / R$ 4,66 bi / R$ 2,59 bi |
| Alavancagem 0,94× → prêmio | 1,3% |
| Kd | 15,35% |
| Escudo fiscal | 34% |

No ponto anualizado a despesa financeira não está publicada: a cobertura de
juros não é medível, o prêmio de crédito sai só da alavancagem, e o escudo
fiscal fica na alíquota estatutária. (Na contagem de outubro, com 2025 como
último ponto, a despesa de R$ 3,08 bi passava o EBIT — cobertura de 0,76 —, e o
motor reduzia o escudo na mesma proporção, para 25,8%.)

**WACC de hoje:**

```
pesos: 10,50 ÷ 13,09 = 0,8023;  7,25 ÷ 13,09 = 0,5540;  4,66 ÷ 13,09 = 0,3563
WACC = 0,8023 × 14,84% + 0,5540 × 15,35% × (1 − 34%) − 0,3563 × 14,05% × (1 − 34%)
     = 11,91% + 5,61% − 3,30% = 14,22%
```

Resolvido ano a ano (27 iterações): WACC de 13,69% a 14,40%, **Ke de 14,38% a
15,07%**; a participação do capital próprio vai de 76,6% a 78,9% do valor da
firma.

---

## 6. A perpetuidade de uma concessão

A vantagem residual é barrada por dois motivos:

1. **concessão**: a tarifa remunera o capital ao custo dele, e um negócio que
   será relicitado não preserva excedente sobre capital novo (decisão 50);
2. **sem excedente**: o ROIC do ciclo (13,42%) está abaixo do custo de
   equilíbrio (14,5%).

**E o prazo do contrato?** Quando o motor consegue ler o prazo da concessão no
Formulário de Referência, o terminal passa a ser "capital devolvido + excedente
até o fim do contrato" (decisão 88). Para a Sanepar, o prazo **não foi lido**:
o terminal fica perpétuo, com retorno neutro, e a tela mostra a ressalva
**"prazo determinado"** e um aviso explicando o que isso muda.

---

## 7. Os dez anos

Aqui o ROIC **sobe** do de partida (10,9%) para o WACC do ano (14,4%): a
convergência ao custo de capital funciona nos dois sentidos. Com o retorno
subindo e o crescimento caindo, a retenção cai de 91,8% para 47,4%, e o fluxo
livre cresce muito ao longo da projeção — no ano 1 a empresa reinveste quase
tudo o que gera.

O serviço da dívida tem o sinal oposto ao da [WEG](wege3.md), porque a Sanepar
tem dívida líquida: para a alavancagem acompanhar o crescimento, ela toma
dívida nova, e esse dinheiro entra para o acionista. Conferindo o ano 1:

```
juro da dívida      = 7.250,0 × (13,67% + 1,3%) × (1 − 34%) = 716,4
rendimento do caixa = 4.662,5 × 13,67% × (1 − 34%)          = 420,7
dívida nova         = 2.587,6 × 10,03%                       = 259,5
serviço da dívida   = 716,4 − 420,7 − 259,5                  = 36,2
```

| Ano | g | ROIC | Retenção | NOPAT (R$ mi) | Fluxo da firma (R$ mi) | Serviço da dívida (R$ mi) | Fluxo do acionista (R$ mi) | Ke | Fator acumulado | Meio de ano | Valor presente (R$ mi) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 10,0% | 10,9% | 91,8% | 1.699,3 | 140,2 | 36,2 | 103,9 | 14,4% | 1,1438 | 1,0695 | 97,2 |
| 2 | 9,7% | 11,3% | 85,7% | 1.863,7 | 266,7 | 59,2 | 207,5 | 14,9% | 1,3138 | 1,0718 | 169,3 |
| 3 | 9,3% | 11,7% | 79,5% | 2.037,3 | 416,9 | 82,6 | 334,3 | 15,2% | 1,5133 | 1,0732 | 237,1 |
| 4 | 9,0% | 12,1% | 73,9% | 2.219,8 | 579,2 | 103,5 | 475,7 | 15,2% | 1,7437 | 1,0734 | 292,8 |
| 5 | 8,6% | 12,6% | 68,3% | 2.410,8 | 763,9 | 130,2 | 633,7 | 15,4% | 2,0121 | 1,0742 | 338,3 |
| 6 | 8,2% | 13,0% | 63,7% | 2.609,6 | 948,1 | 152,6 | 795,5 | 15,3% | 2,3195 | 1,0737 | 368,2 |
| 7 | 7,9% | 13,3% | 59,4% | 2.815,6 | 1.143,6 | 177,4 | 966,2 | 15,2% | 2,6710 | 1,0731 | 388,2 |
| 8 | 7,5% | 13,7% | 55,1% | 3.027,8 | 1.358,8 | 207,6 | 1.151,3 | 15,1% | 3,0753 | 1,0730 | 401,7 |
| 9 | 7,2% | 14,0% | 51,2% | 3.245,2 | 1.583,9 | 239,6 | 1.344,3 | 15,1% | 3,5393 | 1,0728 | 407,5 |
| 10 | 6,8% | 14,4% | 47,4% | 3.466,7 | 1.823,8 | 275,6 | 1.548,1 | 15,1% | 4,0727 | 1,0727 | 407,8 |
| **Soma** | | | | | | | | | | | **3.108,0** |

---

## 8. O terminal, convertido para o acionista

Retorno neutro (o crescimento sai da conta da firma):

```
VT da firma            = NOPAT₁₀ × 1,0683 ÷ 14,40% = 3.466,7 × 1,0683 ÷ 0,1440 = R$ 25.715,6 mi
fluxo da firma ano 11  = 25.715,6 × (14,40% − 6,83%)  = 1.948,2
fluxo do acionista     = 1.948,2 − 294,5 (serviço da dívida) = 1.653,8
VT do acionista        = 1.653,8 ÷ (15,07% − 6,83%) = 20.053,0
VP do terminal         = 20.053,0 × 1,072716 ÷ 4,072738 = R$ 5.281,8 mi
```

O terminal é 63,0% do capital próprio. O capital que já existe rende 11,6% na
perpetuidade, contra 14,4% de custo: esse déficit vale −R$ 1,50 bi a valor
presente, e já está dentro do terminal (item B12).

---

## 9. O preço justo

```
capital próprio = 3.108,0 + 5.281,8 − 0 (minoritários) = R$ 8.389,8 mi
preço justo     = 8.389,8 mi ÷ 302.241.104 units = R$ 27,76 por unit
                  (÷ 5 = R$ 5,55 por ação)
upside          = (27,76 − 34,74) ÷ 34,74 = −20,1%
```

---

## 10. Os números em volta

**Cenários:** R$ 24,26 / R$ 27,76 / R$ 33,76. **Monte Carlo:** P5 R$ 24,23,
mediana R$ 27,83, P95 R$ 32,04.

**Faixa calibrada (80%):** 12 meses, R$ 25,75 a R$ 54,75; 36 meses, R$ 22,83 a
R$ 74,43 (a conta está no [caso WEGE3](wege3.md), seção 13; a volatilidade da
Sanepar no último ano foi de 31,0%).

**Múltiplos de pares.** O subsetor "água e saneamento" não tem cinco outras
companhias, e a mediana vem do setor de utilidade pública (energia elétrica,
gás, saneamento):

| Leitura | Mediana (companhias) | Grandeza por unit | Preço |
|---|---:|---:|---:|
| P/L | 9,86 (27) | lucro anualizado **negativo** | **recusada** |
| P/VP | 1,87 (32) | patrimônio R$ 40,05 | R$ 74,98 |
| EV/EBITDA | 7,27 (32) | EBITDA R$ 2,77 bi, dívida líq. R$ 2,59 bi | R$ 58,00 |
| **Consolidada (mediana das duas)** | | | **R$ 66,49** |

A leitura por P/L é recusada porque um múltiplo de lucro sobre prejuízo não tem
sentido.

**Divergência de +139,5%** — acima do limite de 50%, e a tela avisa. O preço
justo **não muda**: a leitura por pares é teste de sanidade, e a divergência
fica declarada (decisão 118).

**Por que tanta diferença.** O setor de utilidade pública, dominado por energia
elétrica, negocia a múltiplos maiores que a Sanepar (o próprio mercado paga só
0,87 vez o patrimônio dela, contra 1,87 da mediana do setor). O fluxo descontado
diz que a Sanepar rende 10,9% sobre o capital hoje, abaixo dos 14% a 15% que o
motor exige — e, com a base presa pela trava, o preço justo fica abaixo do
mercado e bem abaixo dos pares.

> **Uma correção feita durante esta documentação (item B41):** até 28/09/2026 a
> mediana dos "pares" de saneamento tinha sete entradas, três delas da própria
> Sanepar (SAPR3, SAPR4 e SAPR11). A mediana caía na Sanepar, e as leituras de
> P/VP e EV/EBITDA devolviam, as duas, R$ 38,15 — o preço da própria Sanepar na
> data do pacote. Agora cada companhia entra uma vez, e a avaliada não entra.

---

## 11. O que este caso ensina

- **Contar papéis é parte da avaliação.** O erro da fonte aqui seria de cinco
  vezes, e só a contagem oficial o evita.
- **Concessão muda a perpetuidade**, e o prazo lido do contrato muda mais ainda;
  sem ele, a ressalva avisa.
- **Um semestre pode mudar o preço.** A anualização da decisão 153 levou o
  prejuízo do primeiro semestre para o ano inteiro, e a trava de saúde, lendo
  esse prejuízo, impediu a normalização para cima. Com 2025 como último ponto, a
  base era normalizada (fator 1,207) e o preço justo era R$ 46,05. As duas
  contas seguem a regra; a diferença é o dado, e a tela declara as duas coisas
  nos avisos.
- **Duas leituras independentes podem discordar muito**, e o motor não escolhe
  uma: mostra as duas e mantém o preço do fluxo descontado.
- **Estatal não paga taxa maior no motor, e a tela diz isso.** A Sanepar é
  controlada pelo governo do Paraná, e a avaliação leva a ressalva **controle
  estatal**. O motor não soma prêmio ao custo de capital: medido, o beta das
  estatais é menor que o das privadas, e a exposição delas ao risco do país não
  é maior; o risco de o controlador decidir por outros objetivos que o lucro
  fica no fluxo do minoritário ([estatais.md](../../validacao/estatais.md)).
