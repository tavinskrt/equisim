---
numero: 130
titulo: Sem despesa financeira, o prêmio de crédito sai da alavancagem, e o rastro diz a regra que a conta usa
status: aceita
origem: voce
data: 2026-09-22
citacao: >
  Se precisar mexer no código, o faça, mas não esqueça de apurar com as lentes.
afeta:
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - packages/equisim_core/test/levered_rates_test.dart
substitui: []
---

## Contexto

Na rodada que fechou o C1, a lente `metodo` rodou duas vezes sobre o código do
custo de capital, e cada execução achou um defeito real.

**B25 — o rastro descrevia a regra antiga.** O Passo 3 do WACC no rastro de
auditoria escrevia «custo observado fora da banda; limitado a X» e «observado
dentro da banda → X», que é a regra anterior à decisão 31: limitar o custo
observado a uma banda. Desde ela o `K_d` é sempre `R_f` mais o prêmio sintético,
e o observado **só arbitra** se a cobertura de juros pode pesar. A primeira
execução da lente foi enganada pelo próprio rastro, e pediu para «descartar o
observado integralmente» — que é o que a conta já fazia.

**B26 — sem despesa financeira, o prêmio de crédito virava zero.** Quando a
despesa financeira de uma empresa com dívida contratada não estava publicada, o
WACC estático degenerava para o `Ke` — «não há `K_d` a ponderar». E o prêmio de
crédito que o ponto fixo recebe era derivado do custo que o WACC estático
devolvia, de modo que a degeneração o zerava: **o caminho resolvido tomava
dinheiro à taxa livre de risco**. No gabarito, a NATU3 trazia no mesmo rastro
«desconto feito ao custo do capital próprio» e «o WACC vai de 16,3% a 16,8%»,
com `Ke` de 21,0% e 56% de peso na dívida.

**A condição contradizia a decisão 31.** O prêmio sintético tem duas razões — a
alavancagem, que não passa pela despesa, e a cobertura, que passa. Sem a
despesa, a alavancagem continua medível.

## Decisão

1. **O Passo 3 do rastro diz a regra que a conta usa**: o prêmio pela
   alavancagem, se a cobertura fala e por quê, e que o observado não entra na
   taxa.
2. **O custo observado da dívida passa a ser opcional** em `CostOfCapital`:
   `null` quando a despesa financeira não está publicada.
3. **Sem a despesa, a cobertura sai da conta, e não entra no teto.** A tabela de
   cobertura devolve o prêmio máximo para cobertura não medível; deixá-la falar
   puniria com 10 p.p. um campo em branco na fonte. **Ausência não é cobertura
   ruim.**
4. **Só a falta de valor de mercado impede o WACC estático.** A despesa ausente
   deixa de degenerá-lo, e passa a ser declarada num aviso próprio.
5. **O prêmio do ponto fixo sai do `_wacc` em todos os casos**, e não mais do
   custo que ele devolvia: existe mesmo quando o WACC estático não existe, porque
   o ponto fixo pondera pelo capital próprio que a avaliação produz.

## A premissa que a mesma lente pediu para mudar, e não mudou

A segunda execução pediu também que o prêmio de crédito fosse **recalculado ano
a ano** no ponto fixo, supondo que a projeção desalavanca. **A premissa era
falsa**: a dívida projetada cresce a `g_t`, o mesmo ritmo do lucro, e a razão que
dá o prêmio — dívida líquida sobre EBITDA — fica parada por construção. O que
muda ano a ano é o `D/E` a mercado, que move o beta e não a classificação.
Recalcular devolveria o mesmo número. A premissa está documentada na origem, e
um teste a cobra.

## O que foi medido

No gabarito, sobre a entrada congelada: **o B25 não move preço algum** — fora
do rastro o gabarito é idêntico, e os 924 rastros que passam pelo WACC mudam no
texto. **O B26 move um ativo**: a NATU3, de −13,3% na montagem do aplicativo, e
nenhuma recusa muda. Para todo ativo que tinha WACC estático, o prêmio novo é o
mesmo número que o antigo.

**O backtest foi reexecutado**, porque as deslistadas das coortes são montadas
só com dado da CVM, sem despesa financeira, e podiam cair no B26 em massa. O
efeito sobre as coortes está no plano (item B26) e no veredito do C1.

## Consequências aceitas

**Um defeito conhecido fora da rodada em que o R1 foi marcado.** O R1 dizia
«nenhum defeito conhecido» sobre o que as lentes tinham apontado até ali; esta
rodada achou mais dois e os fechou. É assim que o critério tem de funcionar — o
«conhecido» se renova a cada leitura —, e não é razão para desmarcá-lo depois de
fechados.
