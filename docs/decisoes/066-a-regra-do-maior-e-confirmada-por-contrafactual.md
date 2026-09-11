---
numero: 66
titulo: A regra do maior é confirmada por contrafactual, e o backtest não a vê
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - tool/backtest_valuation.dart
  - docs/validacao/unidade.md
substitui: []
---

## Contexto

`ValuationCascade.quotedShares` adota, quando as duas candidatas a divisor
divergem além da banda, a **maior** delas — porque divisor pequeno demais infla
o preço justo e produz sinal falso de desconto.

A [decisão 61](061-a-tolerancia-da-razao-de-unidade-e-relativa.md) registrou que
essa regra tem um viés estrutural contra **grupamento**: `reconciledShares` só
pode confirmar a contagem do exercício, e um grupamento a deixa maior que a
corrente sempre. O tamanho ficou medido — 29 ativos com grupamento aparente, 27
em que a contábil vence —, mas **o custo não**.

## Decisão

A regra fica, confirmada pelo contrafactual.

Dos 127 avaliados, 11 têm a contábil vencendo. Trocá-la pela implícita no valor
de mercado move **todos os onze para cima**, e o extremo mostra por quê:

| ticker | divisor/mercado | pot. adotado | pot. pelo mercado |
|---|---:|---:|---:|
| MILS3 | 4.852,07× | −85,8% | **+69.039,8%** |
| COGN3 | 11,49× | −41,0% | +578,4% |
| CPLE3 | 10,81× | −60,5% | +327,0% |
| ANIM3 | 4,91× | +219,1% | +1.466,0% |
| SAPR11 | 2,93× | +108,0% | +509,1% |

Um potencial de sessenta e nove mil por cento é exatamente o falso desconto que
a regra existe para barrar.

## Consequências aceitas

**Três dos onze ocupam o topo da lista sobre a qual se decide**: ANIM3 em 3º de
127, SAPR4 em 7º e SAPR11 em 8º. Neles a direção é robusta — barato pelas duas
contagens —, mas a magnitude depende de uma escolha que o dado não arbitra. Os
outros oito ficam do 69º ao 125º, onde a escolha não muda decisão.

**E a validação fora da amostra não pode julgar nada disto.**
`tool/backtest_valuation.dart` reconstrói o valor de mercado como
`contagem do exercício × preço da coorte`, o que é necessário para não injetar
a capitalização de hoje numa avaliação de 2018 — e faz as duas candidatas
colapsarem na mesma. Conferido, não suposto: **351 de 351 ativos** saem com
`u = 1` e sem divergência sob essa reescala.

Portanto a razão de unidade, a regra do maior e a escolha entre as duas
contagens **não têm evidência preditiva, e não são testáveis por este
instrumento**. O que sustenta a decisão 61 é a conferência entre unit e classe,
que é consistência interna. O que sustenta esta é o contrafactual acima, que é
argumento de assimetria de risco — não de acerto.

Consertar a cegueira exigiria preservar a contagem implícita no valor de
mercado ao longo das coortes, injetando a base societária de hoje em 2018:
trocar um viés declarado por outro. Fica inventariado em
[limitacoes.md §3.5](../validacao/limitacoes.md), não resolvido.
