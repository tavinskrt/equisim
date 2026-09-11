---
numero: 54
titulo: O beta é desalavancado pela mesma dívida com que é realavancado, e o desalavancado passa a sair do beta encolhido
status: aceita
origem: conselheiro
data: 2026-09-11
citacao: >
  Substituir no cálculo de prior as referências de dívida bruta pela dívida
  líquida, padronizando a engrenagem de encolhimento e isolamento.
afeta:
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - packages/equisim_core/lib/src/services/metrics/beta_shrinkage.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/usecases/resolve_beta_prior.dart
  - packages/equisim_core/test/beta_shrinkage_test.dart
  - tool/beta_ida_volta.dart
  - docs/validacao/beta_ida_volta.md
substitui: []
---

## Contexto

A lente `metodo` apontou que o prior de beta usa dívida bruta enquanto a
realavancagem usa líquida. A conferência confirmou, e encontrou um segundo
defeito na mesma volta.

O beta é desalavancado numa ponta e realavancado na outra; para a operação
significar alguma coisa, a volta tem de desfazer a ida.

**Não desfazia, por duas razões independentes:**

1. **A ida usava dívida bruta e a volta, líquida.** Medido: o fator da ida é
   1,092× o da volta na mediana e 1,396× no p90, e **o beta que voltava era
   menor que o medido em 100 dos 127 avaliados**. Em 32 empresas de caixa
   líquido, a ida divide e a volta não multiplica de volta.
2. **A ida partia do beta cru, não do encolhido.** `ShrunkBeta.unlevered`
   desalavancava `leveredBeta`, enquanto `ShrunkBeta.beta` era o encolhido — e
   o caminho resolvido relavanca `unlevered` e **nunca toca em `beta`**. O
   encolhimento da [decisão 40](040-beta-encolhido-por-precisao.md) não chegava
   ao preço da maioria do universo.

Ver [beta_ida_volta.md](../validacao/beta_ida_volta.md).

## Decisão

**A régua é a dívida líquida sobre o valor de mercado, nas duas pontas da
desalavancagem**, e mora num lugar só:
`FundamentalsSnapshot.debtToMarketEquity`.

A escolha não é de gosto: a líquida é a dívida que a ponte `EV − D`, os pesos
do WACC e o capital investido já usam. Trocar a régua da realavancagem exigiria
trocar as três e contradiria a definição de capital investido. E é a correta —
caixa é ativo de beta baixo, e o beta do negócio operacional é maior que o da
ação de uma empresa cheia de caixa.

**O desalavancado passa a sair do beta encolhido**, de modo que
`unlevered × fator == beta` vale por construção. Encolher em espaço alavancado e
desalavancar o resultado é idêntico a encolher em espaço desalavancado, porque
o fator é o mesmo dos dois lados.

## Consequências aceitas

**Noventa e seis dos 127 preços justos caem, e nenhum sobe.** Variação mediana
de **−7,2%**; o potencial mediano vai de −31,8% para −37,5%, o p75 de +11,4%
para +4,5% e os positivos de 40 para 35. EVEN3 −39,0%, KLBN3 −25,1%, GOAU4
−22,2%, USIM3 −22,2%.

A direção não podia ser outra: corrigir a ida eleva o beta desalavancado, a
volta o realavanca sobre um número maior, o custo do capital próprio sobe e o
valor cai. **Isto desfaz parte do que rodadas anteriores somaram** — e o que
somava era um beta subestimado.

**O encolhimento move pouco, e agora se sabe quanto.** O peso do próprio ativo
tem mediana de 0,985 e só 1 dos 127 fica abaixo de 0,90: a precisão da
regressão individual domina a do prior setorial em praticamente todo ativo,
porque a dispersão setorial dos betas é grande. A diferença entre desalavancar
o cru e o encolhido é de 0,5% na mediana. **A decisão 40 é quase inerte neste
universo**, e isso fica registrado — uma identidade que vale por acidente de
calibragem não vale, mas o tamanho dela é honesto declarar.

**O confinamento de `D/E` em `[0; 3]` continua.** Com caixa líquido o fator vai
ao piso e `β_U = β_L`, enquanto a Hamada com dívida negativa daria `β_U > β_L`.
O piso é a leitura conservadora, e a ida e a volta se cancelam de qualquer
forma porque ele vale nos dois lados.

**O beta continua medido sobre retorno diário de cotação não ajustada.** É
outro defeito, independente deste, e segue aberto.

**A alternativa descartada** era realavancar pela bruta em vez de desalavancar
pela líquida. Recusada porque exigiria trocar a dívida da ponte, do WACC e do
capital investido junto — três lugares onde a líquida está certa — para
consertar um lugar onde ela também está.
