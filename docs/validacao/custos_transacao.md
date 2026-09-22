# Custos de transação — item C4

> **Medido em 22/09/2026.** Duas medições, porque «o backtest» do projeto são
> dois: a **simulação da carteira** que o aplicativo mostra, e as **coortes de
> validação** que respondem ao R3.
>
> ```bash
> python tool/b3_baixar.py --extremos --de 2017    # máxima e mínima diárias
> python tool/custos_spread.py                     # spread por observação
> dart run tool/regressao_condicional.dart --custos
> dart run tool/custos_simulacao.dart              # sobre a entrada congelada
> ```

## 0. O que era, e o que ficou

As [limitações](limitacoes.md) §2.5 diziam que o motor não modela corretagem,
emolumentos nem spread, e que os retornos simulados eram otimistas — «baixo por
não rebalancear, mas não medido». Agora:

- **a simulação cobra a tarifa da B3** em cada compra, em centavos inteiros
  (`TransactionCosts.b3`: negociação de 0,005% mais liquidação de 0,025%), e a
  tela mostra o total pago ao lado do aportado, do alocado e do caixa;
- **as coortes têm retorno líquido** de tarifa e spread nas duas pontas, e a
  habilidade foi remedida sobre ele.

## 1. O custo de cada ponta

**A tarifa** é a da B3 para ações à vista, pessoa física: 0,030% do valor
negociado. **A corretagem** fica em zero, que é o que as corretoras de varejo
cobram em ações desde 2019; a simulação aceita corretagem fixa por ordem, para
quem quiser outro número.

**O spread** não é publicado papel a papel na série histórica, e foi estimado da
máxima, da mínima e do fechamento diários do COTAHIST pelo método de **Abdi e
Ranaldo (2017)**: `s² = 4·E[(c_t − η_t)(c_t − η_{t+1})]`, com `c` o log do
fechamento e `η` o ponto médio dos logs da máxima e da mínima, em média nos 63
pregões até a data. Custo por ponta: `tarifa + s/2`.

**Por que não Corwin e Schultz (2012)**, que é o mais citado. Medido sobre as
mesmas observações, ele sai **invertido**:

| tercil de liquidez | Corwin e Schultz | Abdi e Ranaldo |
|---|---:|---:|
| baixa | 0,57% | **1,72%** |
| média | 1,06% | **0,87%** |
| alta | 0,90% | **0,42%** |

Pregão com um negócio só tem máxima igual à mínima e zera o par de Corwin e
Schultz, e a volatilidade do papel líquido entra como spread. O de Abdi e
Ranaldo ordena como deve. **Ele também superestima o papel muito líquido** — a
PETR4 sai com 0,72% em 30/06/2022, contra um spread cotado de centésimos —, e
por isso o custo daqui é **conservador**: pune mais do que o investidor pagaria.

Das 10.919 observações, 10.330 têm spread estimável na compra. Sem spread numa
ponta, vale o da outra (508 observações); sem nas duas, a mediana do tercil de
liquidez da coorte (649) ou a geral (21).

## 2. As coortes: o custo muda o nível, e não a ordem

Coortes trimestrais com as deslistadas, as mesmas observações nas duas leituras
([custos_transacao.json](custos_transacao.json)):

| 36 meses, n = 2.164 | bruto | líquido |
|---|---:|---:|
| retorno mediano | 14,00% | **13,14%** |
| custo de ida e volta mediano | — | 0,60% |
| potencial dado o B/M (critério do R3) | 0,028, `t` 0,15 | 0,028, `t` 0,16 |
| IC do potencial | 0,088 | 0,089 |
| IC do book-to-market | 0,160, `t` 2,07 | 0,159, `t` 2,08 |
| IC do composto | 0,146 | 0,146 |
| Q5 − Q1 pelo potencial | +0,75% | +0,75% (comprado e vendido: −0,49%) |
| Q5 − Q1 pelo B/M | 28,39% | 28,16% (comprado e vendido: 26,86%) |

| 12 meses, n = 2.935 | bruto | líquido |
|---|---:|---:|
| retorno mediano | 6,81% | **6,15%** |
| potencial dado o B/M | 0,042, `t` 0,63 | 0,042, `t` 0,63 |
| IC do book-to-market | 0,087, `t` 1,49 | 0,085, `t` 1,46 |
| Q5 − Q1 pelo potencial | 3,79% | 3,72% (comprado e vendido: 2,38%) |

> Sobre o backtest final da rodada — motor com as decisões 125 a 128 e as
> versões antigas dos documentos (item B8).

**Nenhum veredito muda.** O critério da decisão 96 dá o mesmo resultado nas
cinco ordenações, bruto e líquido — nenhuma passa. Os IC se movem na terceira
casa.

**E isto não é descoberta, é aritmética.** Custo uniforme preserva a ordem dos
retornos de uma coorte, e o IC é correlação de ordens: ele não muda. O que o
custo **poderia** mudar é a ordem quando ele varia com a liquidez — e varia,
de 0,4% a 1,7% de spread entre os tercis. A medição responde que, nesta amostra,
essa variação é pequena demais diante da dispersão dos retornos em 36 meses para
reordenar alguém que importe.

**O que o custo muda é o nível**: 0,86 p.p. a menos no retorno mediano de 36
meses, e 1,5 p.p. a menos na carteira comprada e vendida pelo book-to-market,
que paga as duas pernas. É o que se lê numa promessa de retorno, e não numa
promessa de ordenação.

## 3. A simulação: a tarifa é quase nada, e o spread seria o que pesa

Cinquenta carteiras sorteadas do universo congelado do gabarito — semente
20260922, oito ativos cada, R$ 10.000 iniciais e R$ 1.000 por mês, de 2019 a
agosto de 2026 ([custos_simulacao.json](custos_simulacao.json)):

| | patrimônio final | XIRR | custo sobre o aportado |
|---|---:|---:|---:|
| tarifa da B3 (o padrão) | −0,024% | −0,006 p.p. (pior: −0,019) | 0,031% |
| tarifa e 0,5% de meio spread | −0,53% | −0,12 p.p. (pior: −0,14) | 0,53% |

**A tarifa custa menos que o arredondamento de uma ação.** Num aporte que
fecharia exatamente cem ações, ela faz comprar 99 — e a ação que ficou vira
caixa, que entra no aporte seguinte. **O spread seria o que pesa**, e ele não
entra na simulação: ela compra ao fechamento, e quanto um investidor paga de
spread depende de como ele manda a ordem. Somar um número único a todas as
carteiras seria falsa precisão; a linha de 0,5% diz a ordem de grandeza.

## 4. O que fica

- **A simulação cobra a tarifa e declara o spread.** A limitação §2.5 passa a
  dizer isso, com os números acima.
- **As coortes medem os dois**, e a leitura da habilidade sobre o retorno
  líquido é a mesma da bruta.
- **O estimador de spread é conservador para o papel líquido.** Um custo
  menor só reforçaria que o custo não muda a ordem.
