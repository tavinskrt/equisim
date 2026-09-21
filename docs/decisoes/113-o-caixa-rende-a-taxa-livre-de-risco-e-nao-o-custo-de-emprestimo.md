---
numero: 113
titulo: O caixa rende a taxa livre de risco, e não o custo de empréstimo
status: aceita
origem: lente
data: 2026-09-21
citacao: >
  O WACC utiliza o custo da dívida (kd, que contém spread) na ponderação da
  dívida líquida de forma agnóstica, aplicando-o de maneira idêntica quando a
  firma dispõe de excesso de caixa (peso negativo). [...] subtraí-lo empregando
  o custo de empréstimo (Kd > Rf) comprime indevidamente o WACC e infla o valor
  presente descontado de balanços líquidos.
afeta:
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - packages/equisim_core/test/levered_rates_test.dart
  - docs/validacao/gabarito_cascata.json
substitui: []
---

## Contexto

A [decisão 104](104-a-divida-do-wacc-e-a-liquida.md) pôs a dívida **líquida**
nos pesos do WACC, e disse, no caso da companhia **sem dívida contratada**, o
que remunera o peso negativo: «sem dívida contratada não há prêmio de crédito a
cobrar, e o `K_d` é a taxa livre de risco — é o que caixa rende (decisão 58)».

**A regra valia só quando a dívida bruta era zero.** Com dívida contratada e
caixa maior que ela — `hasContractedDebt` verdadeiro, dívida líquida negativa —
o `K_d` aplicado continuava sendo `R_f + spread`, sobre um peso negativo. O
caixa era creditado ao acionista com **prêmio de crédito**, que caixa não rende.

O argumento que a decisão 104 usou para o caso extremo vale igual para o caso
intermediário, e a lente `metodo` apontou a diferença.

## Decisão

**A perna do financiamento se abre em duas, sobre o mesmo denominador.**

```
WACC = w_E·K_e  +  w_D,bruta·K_d·(1 − escudo)  −  w_caixa·R_f·(1 − τ)
```

com os três pesos sobre `E + D_líquida`, que é o mesmo capital total de antes.

1. **Os pesos não mudam.** `w_D,bruta − w_caixa` é exatamente `w_D,líquida`: o
   que a separação redistribui é a **taxa** de cada metade, e não o peso. A
   decisão 104 continua inteira.
2. **O rendimento do caixa é tributado, e não escudado.** O juro da dívida é
   despesa dedutível, e por isso leva `(1 − escudo)`; a receita financeira do
   caixa é receita tributável, e leva `(1 − τ)`. Os dois fatores são próximos, e
   não são a mesma coisa.
3. **A via alavancada faz o mesmo.** O caixa é projetado ao lado da dívida
   bruta, com o mesmo fator de crescimento — de modo que a série líquida da
   projeção **não muda** —, e o que muda é a composição da taxa de cada ano e a
   da perpetuidade. Sem isso as duas rotas discordariam no mesmo ativo, que é o
   defeito que a decisão 104 corrigiu.
4. **Com `D/E` imposto não há separação.** A dívida ali é arbitrada pela
   varredura do B15, e não observada: a forma colapsa na anterior.
5. **Sem caixa conhecido, a forma anterior vale**, e é a que quem monta o custo
   à mão obtém.
6. **O rastro mostra a forma que a conta usou.** Repetir a fórmula de uma perna
   só faria o passo da soma ponderada fechar num número diferente do resultado.

## O que foi medido

Sobre a entrada congelada do gabarito, em 21/09/2026. A via do acionista **não
muda em nenhum ativo** — ela não tem WACC. Na montagem do aplicativo, dos 102
avaliados:

| | |
|---|---:|
| preço justo idêntico | 38 |
| preço justo muda | 61 |
| deixam de ser avaliáveis | **3** |
| mediana da mudança | **+0,28%** |
| p5 / p95 | −2,2% / +11,5% |

O WACC **sobe** em todo ativo com caixa, exatamente por
`w_caixa·(1 − τ)·spread` — medido na ANIM3: de 17,7% para 19,6% no primeiro ano,
e o preço justo cai de R$ 3,70 para R$ 3,48.

**O preço justo sobe na maioria, e isso não contradiz a taxa maior.** O terminal
neutro do motor é deficitário na mediana — o capital instalado rende 0,71 vez o
custo de capital ([decisão 112](112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md)) —,
e descontar um déficit a taxa maior encolhe o déficit. Onde o terminal é
superavitário, o preço justo cai. A EMBJ3, com excedente terminal de −6,1 vezes
o preço justo, é o extremo: +41,7% sobre um potencial de −98,8%, que é ativo
degenerado nas duas versões.

## Consequências aceitas

**Três ativos deixam de ser avaliáveis: MOTV3, MYPK3 e QUAL3.** Com o WACC
maior, o valor da firma não cobre a dívida líquida já no ano zero, e o ponto
fixo recusa das duas partidas ([decisão 110](110-o-ponto-fixo-e-tentado-de-duas-partidas-e-a-recusa-deixa-de-ser-do-chute.md)).
A recusa é o comportamento declarado do motor quando a estrutura não sustenta a
via da firma, e o preço que eles tinham saía de uma taxa barata demais. **É
perda de cobertura, e está contada aqui**: 102 avaliados passam a 99 na montagem
do aplicativo.

**A medição das coortes envelhece de novo.** Habilidade, faixa calibrada,
recusas e ponte continuam descrevendo o motor anterior, e só a reexecução do
backtest as atualiza — que depende do item C5.

**O caixa é tratado como se rendesse `R_f` inteiro.** Parte do caixa de uma
companhia é operacional e não rende nada; parte está em aplicação que rende
perto do CDI. O motor não separa as duas, e adotar `R_f` para o todo **subestima
o WACC** de quem carrega caixa parado. É a direção conservadora entre as duas, e
é ressalva do método.

**Duas medições da mesma rodada envelheceram na hora.** A
[decisão 112](112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md)
e o [terminal_excedente.md](../validacao/terminal_excedente.md) foram escritos
horas antes, com custo de capital mediano de 18,6% e retorno implícito de 12,9%;
com a separação, são **18,9%** e **13,1%**, sobre 99 avaliados em vez de 103. Os
documentos de validação foram remedidos; a decisão 112 é imutável e fica com os
números da hora em que foi aceita. **A conclusão dela não se move**: o destino
medido da reversão continua sendo 9,5%, e o retorno do capital instalado
continua entre ele e o custo de capital.
