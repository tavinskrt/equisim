# 2. A empresa em números

> **Para que serve este capítulo.** O motor não lê notícias nem opiniões: lê os
> números que a empresa publica todo ano. Este capítulo explica quais são esses
> números, o que cada um quer dizer, e quais contas o motor faz com eles.
>
> Tempo de leitura: 50 minutos. Pré-requisito: capítulo 1.

---

## 2.1 As duas fotografias da empresa

Toda companhia aberta publica, a cada exercício (ano fiscal), um conjunto de
demonstrações. O Equisim usa duas:

- **Balanço patrimonial** — uma *foto* num dia (31 de dezembro): o que a empresa
  tem (ativos), o que ela deve (passivos) e o que sobra para os sócios
  (patrimônio líquido).
- **Demonstração do resultado (DRE)** — um *filme* do ano: quanto ela vendeu,
  quanto gastou e quanto lucrou.

Os números chegam de duas fontes: a CVM (a "Receita Federal" das companhias
abertas, que recebe os balanços oficiais) e a brapi (uma API que também
publica cotações). Onde as duas têm o mesmo número, vale o da CVM.

---

## 2.2 A DRE, linha por linha

Uma DRE simplificada, com números redondos (R$ milhões):

| Linha | Valor | O que é |
|---|---:|---|
| Receita líquida | 10.000 | tudo o que foi vendido, sem os impostos sobre a venda |
| (−) custos e despesas operacionais | −8.100 | matéria-prima, salários, aluguel… |
| **EBITDA** | **1.900** | resultado da operação antes de depreciação |
| (−) depreciação e amortização | −500 | o desgaste das máquinas, contabilizado aos poucos |
| **EBIT** (resultado operacional) | **1.400** | quanto a *operação* rendeu, antes de juros e imposto |
| (−) despesa financeira líquida | −400 | juros da dívida menos o que o caixa rendeu |
| **Lucro antes do imposto** | **1.000** | |
| (−) imposto de renda e CSLL | −300 | |
| **Lucro líquido** | **700** | o que sobrou para os sócios |

Duas medidas de lucro importam para o motor:

- **EBIT** mede a operação sem olhar para como ela foi financiada. Uma empresa
  sem dívida e outra cheia de dívida podem ter o mesmo EBIT.
- **Lucro líquido** é o que sobra para o acionista depois de pagar os
  credores e o governo.

A **alíquota efetiva** é o imposto dividido pelo lucro antes do imposto: aqui,
300 ÷ 1.000 = 30%.

---

## 2.3 O balanço: dívida, caixa e patrimônio

| Grandeza | Exemplo | Como o motor calcula |
|---|---:|---|
| **Dívida bruta** | 2.000 | empréstimos de curto prazo + de longo prazo |
| **Caixa** | 700 | caixa + aplicações financeiras de curto prazo |
| **Dívida líquida** | 1.300 | dívida bruta − caixa |
| **Patrimônio líquido (PL)** | 6.000 | valor patrimonial por ação × número de ações do exercício |
| **Capital investido** | 7.300 | PL + dívida líquida |

A dívida líquida pode ser **negativa**: é a empresa que tem mais caixa do que
deve (a WEG é um exemplo).

O **capital investido** é todo o dinheiro que sócios e credores colocaram para a
operação funcionar: fábricas, estoques, clientes a receber. É sobre ele que se
mede se a empresa é boa em gerar retorno.

**No código:** [fundamentals.dart](../../packages/equisim_core/lib/src/entities/fundamentals.dart)
(`totalDebt`, `totalCash`, `netDebt`, `equityBookValue`, `investedCapital`).

---

## 2.4 NOPAT: o lucro da operação, como se não houvesse dívida

O **NOPAT** (*net operating profit after taxes*, lucro operacional depois do
imposto) é o EBIT menos o imposto que a empresa pagaria se não tivesse dívida:

```
NOPAT = EBIT × (1 − alíquota)
```

No exemplo, com 30%: 1.400 × 0,70 = **980**.

Por que tirar a dívida da conta? Porque o motor separa duas perguntas:

1. *A operação é boa?* — responde-se com NOPAT e capital investido;
2. *Como ela é financiada?* — responde-se com a dívida, mais adiante, no custo
   de capital (capítulo 3) e na passagem da firma para o acionista (capítulo 4).

**Qual alíquota o motor usa.** A **mediana** das alíquotas efetivas publicadas
(pelo menos cinco exercícios), limitada a 34% — a alíquota cheia de IRPJ (15% +
10% de adicional) mais CSLL (9%). A mediana é usada porque um único ano com
crédito tributário ou multa distorceria a média (capítulo 6, seção 6.1).

**Um detalhe honesto.** Resultado de coligadas (a "equivalência patrimonial")
já chega depois do imposto da coligada; o motor não o tributa de novo.

**No código:** [fundamentals.dart, `nopatAtRate`](../../packages/equisim_core/lib/src/entities/fundamentals.dart)
e [capital_base.dart, `structuralTaxRate`](../../packages/equisim_core/lib/src/services/valuation/capital_base.dart).

---

## 2.5 Retorno sobre o capital: a empresa é boa em quê?

```
ROIC = NOPAT ÷ capital investido        (retorno sobre o capital investido)
ROE  = lucro líquido ÷ patrimônio líquido  (retorno sobre o patrimônio)
```

No exemplo: ROIC = 980 ÷ 7.300 = 13,4%; ROE = 700 ÷ 6.000 = 11,7%.

O ROIC responde: *para cada R$ 100 colocados na operação, quanto volta por ano?*
Uma empresa com ROIC de 25% (como a WEG) transforma capital em lucro muito
melhor que uma com ROIC de 8%.

**Um cuidado do motor.** O lucro de um ano é gerado pelo capital que existia
**no começo** daquele ano. Por isso o motor divide o lucro do ano pelo capital
do ano **anterior** (a "base de abertura")
([capital_base.dart](../../packages/equisim_core/lib/src/services/valuation/capital_base.dart)).

---

## 2.6 Crescer custa dinheiro

Para vender mais no ano que vem, a empresa precisa de mais fábrica, mais
estoque, mais clientes a prazo. Esse dinheiro sai do lucro. A parte do lucro
que fica na empresa para financiar o crescimento é a **taxa de retenção** (ou
de reinvestimento), `b`.

A ligação entre as três grandezas é uma das fórmulas mais importantes do
projeto:

```
crescimento = retenção × retorno sobre o capital
g = b × ROIC        ⇔        b = g ÷ ROIC
```

Exemplo: uma empresa com ROIC de 20% que quer crescer 5% ao ano precisa
reinvestir 5% ÷ 20% = **25%** do lucro. Os outros 75% podem ser distribuídos —
são o **fluxo de caixa livre**:

```
fluxo livre = lucro × (1 − b)
```

Outra empresa, com ROIC de 8%, para crescer os mesmos 5% precisa reinvestir
5 ÷ 8 = **62,5%** do lucro. Sobra muito menos.

> **Crescer só cria valor quando o retorno sobre o capital supera o custo desse
> capital.** Se a empresa reinveste a 8% um dinheiro que custa 13%, cada real
> reinvestido destrói valor. O capítulo 4 mostra como o motor trata isso.

**No motor**, a retenção é limitada a 95% (reter 100% para sempre significaria
nunca distribuir nada) e a zero (sem crescimento não há reinvestimento)
([dcf.dart, `retentionAt`](../../packages/equisim_core/lib/src/services/valuation/dcf.dart)).

---

## 2.7 Um ano não conta a história: normalização

O lucro de um único ano pode enganar:

- **Empresas cíclicas** (mineração, petróleo, siderurgia, celulose) vivem de
  preço de commodity. No auge do minério, a Vale lucra muito; no fundo, pouco.
  Avaliar pelo lucro do auge supõe que o auge dura para sempre.
- **Anos atípicos**: uma venda de ativo, uma multa, uma greve.

Por isso o motor compara o retorno do último ano com o **retorno típico do
ciclo** — a mediana dos oito exercícios anteriores. Se o último ano destoa muito
(e não há uma tendência clara que explique a mudança), o lucro-base é ajustado:

```
lucro-base = lucro do último ano × (retorno do ciclo ÷ retorno atual)
```

limitado a um fator entre 1/3 e 3. O capítulo 4 e o [caso VALE3](casos/vale3.md)
mostram essa conta em detalhe.

---

## 2.8 Quantas ações existem? (e o caso das units)

Para chegar ao preço **por ação**, o motor divide o valor da empresa pelo número
de papéis. Parece trivial, e não é:

- a empresa tem ações em tesouraria (recompradas), que não recebem nada;
- a contagem muda com bonificações, desdobramentos e grupamentos;
- algumas empresas negociam **units** — um "pacote" de ações. Uma unit da
  Sanepar (SAPR11) é 1 ação ordinária + 4 preferenciais. O preço de tela é o da
  unit, então o valor precisa ser dividido pelo número de units, e não de ações.

O motor usa, nesta ordem: a contagem oficial da B3 (líquida de tesouraria)
quando recente; senão, valor de mercado ÷ preço. Quando as fontes divergem além
de 1,5×, vale a maior contagem — o lado conservador, que dá o menor preço por
papel ([compute_valuation.dart, `quotedShares`](../../packages/equisim_core/lib/src/usecases/compute_valuation.dart)).

---

## 2.9 O dado só existe depois de publicado

Uma empresa fecha o ano em 31 de dezembro, mas só publica o balanço semanas
depois. Se o motor avaliasse em janeiro usando o balanço de dezembro, estaria
"vendo o futuro" — e numa validação histórica isso infla o resultado
artificialmente.

Por isso toda avaliação tem uma **data** (`asOf`), e o motor só enxerga os
exercícios que já tinham sido entregues à CVM naquela data (quando a data de
entrega é conhecida; senão, supõe 90 dias de atraso). Isso se chama visão
*point-in-time*
([point_in_time_view.dart](../../packages/equisim_core/lib/src/time/point_in_time_view.dart)).

---

## Resumo do capítulo

| Grandeza | Conta | Para que o motor usa |
|---|---|---|
| Dívida líquida | dívida bruta − caixa | passar da firma ao acionista; custo de capital |
| Capital investido | PL + dívida líquida | base sobre a qual o retorno é medido |
| NOPAT | EBIT × (1 − alíquota) | lucro da operação (via da firma) |
| ROIC | NOPAT ÷ capital de abertura | a empresa é boa em gerar retorno? |
| ROE | lucro ÷ PL de abertura | idem, para bancos (capítulo 5) |
| Retenção | `b = g ÷ ROIC` | quanto do lucro financia o crescimento |
| Fluxo livre | lucro × (1 − b) | o que pode ser distribuído |
| Normalização | lucro × ciclo ÷ atual | não avaliar pelo auge nem pelo fundo |

## Para estudar mais

- **Alexandre Póvoa, *Valuation: como precificar ações*** (Elsevier) —
  capítulos sobre demonstrações e sobre o fluxo de caixa da firma. Escrito para
  o mercado brasileiro.
- **Tim Koller, Marc Goedhart e David Wessels (McKinsey), *Valuation: Measuring
  and Managing the Value of Companies*** — capítulos 6 a 10 ("Reorganizing the
  financial statements", ROIC, crescimento). É a principal referência do motor
  para a relação `g = b × ROIC`.
- **CVM, "Caderno de Educação Financeira — Mercado de Valores Mobiliários"**
  (gratuito, no portal do investidor da CVM) — explica balanço e DRE para
  iniciantes.
