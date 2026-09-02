---
numero: 24
titulo: Lucro retido sai do fluxo descontado; a lacuna da meta é lida como yield
status: aceita
origem: parecer
data: 2026-09-02
citacao: >
  o modelo distribui os proventos integralmente no fluxo do avaliador atual e
  ao mesmo tempo capitaliza o crescimento da empresa, gerando distorção técnica
  que precifica o mesmo dinheiro duas vezes
afeta:
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/portfolio_usecases.dart
  - lib/presentation/goals
substitui: []
---

## Contexto

Duas tensões da lente `metodo` do conselheiro, rodada em 02/09/2026 sobre o
estado posterior à [decisão 23](023-remocao-de-proventos.md).

**Dupla contagem no DCF simplificado.** `DcfCalculator.earningsPerShare`
descontava o **lucro por ação inteiro** como se todo ele chegasse ao acionista
e, ao mesmo tempo, o fazia crescer a `g` ano após ano. Crescimento exige
reinvestimento: parte do lucro precisa ficar na empresa para financiar capital
de giro e imobilizado. Descontar o lucro cheio *e* capitalizar o crescimento
precifica o mesmo dinheiro duas vezes, e infla o preço justo de toda empresa em
crescimento — justamente as que o modelo por LPA costuma pegar, porque é o
degrau da cascata para quem não tem fluxo de caixa publicado.

**Déficit crônico na meta.** Desde a decisão 23 o retorno esperado é
convergência de preço e nada mais. Confrontá-lo com a rentabilidade exigida faz
uma carteira sadia de pagadoras aparecer em déficit permanente. O risco não é
teórico: lendo um abismo que não existe, o investidor é empurrado a trocar
ativos por outros mais agressivos do que precisaria.

## Decisão

**O fluxo descontado passa a ser `LPA × (1 − b)`.** A retenção `b` sai da
relação de crescimento sustentável `g = ROE × b`, com o ROE medido no exercício
mais recente publicado (`LPA ÷ VPA`, ambos na unidade negociada). Há duas
retenções, uma para o período explícito e outra para a perpetuidade, cada uma
derivada do seu próprio crescimento.

**Sem ROE utilizável, o crescimento é zerado.** Patrimônio por papel ausente ou
não positivo, ou um crescimento que exigiria reter todo o lucro (`b ≥ 1`),
levam o modelo ao *earnings power value*: lucro estacionário, valor `LPA / Ke`.
A conta vira uma identidade exata, verificada em teste.

**A lacuna da meta ganha leitura própria.** `GoalAlignment.yieldToCloseGap`
devolve o *dividend yield* que fecharia o déficit — que é a própria lacuna com
o sinal invertido, `exigido − esperado`. A tela de meta o exibe junto da folga,
dizendo que o esperado conta apenas valorização.

## Consequências aceitas

**Preço justo menor no modelo por LPA.** Uma empresa com ROE de 20% crescendo
5% retém um quarto do lucro; o valor cai proporcionalmente. É correção de
defeito, não conservadorismo — mas muda números já apresentados.

**O ROE entra como insumo novo, com a fragilidade do `bookValuePerShare`.** A
fonte publica valor patrimonial por ação, e ele carrega as limitações
contábeis de sempre: patrimônio negativo, reavaliação de ativo, empresa de
capital leve com VPA irrisório inflando o ROE. O caso ruim degrada para o
*earnings power value*, que é conservador, em vez de produzir número errado.

**O `yieldToCloseGap` não é estimativa de provento.** É aritmética da lacuna, e
a decisão 23 continua valendo integralmente: nada é somado ao retorno esperado,
nenhum yield é adotado como premissa. Quem sabe quanto a carteira paga é o
investidor, e a tela entrega o número contra o qual ele compara. A alternativa
descartada era adotar um yield histórico padrão e somá-lo ao esperado no
cálculo da meta — recusada por contradizer a decisão 23 num trecho de código,
o pior lugar para uma exceção morar.

**O `earnings power value` é declarado, não silencioso.** Quando o modelo cai
para lucro estacionário, o aviso vai no resultado e o passo aparece na
auditoria — sem isso o usuário veria um preço justo mais baixo sem saber que o
crescimento foi descartado por falta de insumo.
