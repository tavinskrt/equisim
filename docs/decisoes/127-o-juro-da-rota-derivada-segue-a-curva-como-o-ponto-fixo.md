---
numero: 127
titulo: O juro e o rendimento do caixa da rota derivada seguem a curva, como o ponto fixo que fecha o Ke
status: aceita
origem: voce
data: 2026-09-22
citacao: >
  Reforce a validação da implementação realizada com a execução das lentes e
  correção dos problemas apontados por elas. Caso haja necessidade da inserção
  de outro item na lista, não hesite em fazer.
afeta:
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/equity_from_firm_test.dart
substitui: []
---

## Contexto

Desde a [decisão 102](102-nenhuma-avaliacao-muda-de-via-e-a-firma-avalia-pelo-fluxo-do-acionista-derivado.md),
a via da firma desconta o **fluxo do acionista derivado** ao `Ke`, e o `Ke` de
cada ano sai do ponto fixo de `LeveredCostOfCapital.solve`. O ponto fixo fecha
o WACC com `K_d,t = Rf_t + spread` e o caixa rendendo `Rf_t`, ano a ano, sobre
os forwards da curva do Tesouro (decisão 74).

**A rota derivada não fazia o mesmo.** Ela projetava o serviço da dívida com um
`K_d` só — o do primeiro ano, `Rf + spread` — e o caixa a uma taxa só, e
descontava pelo `Ke` que se move. O comentário no código dizia isso: «a rota
derivada não recebe caminho de custo da dívida». Era limitação declarada, e a
lente `metodo` a apontou em 22/09/2026 como o que é: a identidade entre as duas
rotas pede que as duas leiam a mesma dívida, e aqui uma lia a curva e a outra
não. É o item **B24**, aberto e fechado nesta rodada.

## Decisão

**Com o caminho de taxas resolvido, o juro e o rendimento do caixa de cada ano
são os do ano** — `K_d,t = Rf_t + spread` e `Rf_t` —, e o terminal usa a taxa
livre de risco de equilíbrio. `DcfCalculator.equityFromFirm` ganhou
`costOfDebtPath`, `cashYieldPath` e as duas taxas terminais; sem eles, vale a
taxa única, que é a forma de quem monta a projeção à mão. Sem o caminho
resolvido — o recuo para o WACC estático —, nada muda: ali o `Ke` também é
único.

## O que foi medido

No gabarito da cascata, sobre a entrada congelada, montagem do aplicativo:

| | |
|---|---:|
| preço justo que muda | **64 de 97** |
| mediana do movimento, com sinal | **−0,65%** |
| p90 do movimento em módulo | 2,9% |
| maior | YDUQ3, −13,1% |
| recusa que muda | nenhuma |

**O sinal é o esperado.** Os forwards dos primeiros anos da curva de 10/09/2026
ficam acima da taxa à vista, e o juro projetado sobe; o movimento pesa mais
onde a dívida líquida é grande diante do capital próprio.

**O gabarito foi regravado** com a mudança medida e registrada aqui, e voltou a
conferir idêntico.

## Consequências aceitas

**Uma limitação declarada virou defeito corrigido, e isso é critério, não
reescrita da história.** A declaração estava certa sobre o que o código fazia;
o que ela não dizia é que o `Ke` do desconto já vinha do caminho — e com isso a
limitação deixava de ser simplificação e passava a ser inconsistência.

**O backtest e as medições de coorte sobre a Fase 3 foram reexecutados depois
desta decisão**, junto com o item B8. As leituras anteriores a ela descrevem o
motor de antes.
