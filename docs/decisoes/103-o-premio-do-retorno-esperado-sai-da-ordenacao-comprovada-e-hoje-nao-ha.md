---
numero: 103
titulo: O preço justo é o produto, o prêmio do retorno esperado sai da ordenação comprovada — e hoje não há nenhuma
status: aceita
origem: voce
data: 2026-09-16
citacao: >
  Seus itens de escopo para esta rodada são B1 (siga sua recomendação), B10 e
  B13.
afeta:
  - packages/equisim_core/lib/src/services/portfolio/transversal_ordering.dart
  - packages/equisim_core/lib/src/services/portfolio/expected_return.dart
  - packages/equisim_core/lib/src/services/valuation/skill_reading.dart
  - packages/equisim_core/lib/src/usecases/portfolio_usecases.dart
  - lib/presentation/valuation/valuation_providers.dart
  - lib/presentation/goals/goal_page.dart
  - lib/presentation/goals/skill_copy.dart
  - lib/presentation/study/study_page.dart
  - lib/presentation/backtest/backtest_page.dart
  - tool/regressao_condicional.dart
  - assets/validacao/habilidade.json
  - docs/validacao/ordenacao_lado_a_lado.md
substitui: []
---

## Contexto

A §0 do [plano do motor de referência](../plano-motor-de-referencia.md) mediu que
o potencial do DCF ordena pior que o book-to-market e, condicionado a ele, não
acrescenta. O projeto usava essa ordenação: o retorno esperado da tela de metas e
do estudo é, desde a [decisão 58](058-a-carteira-de-acoes-nao-espera-a-renda-fixa.md),
o `Ke` de cada ativo mais `z · prêmio`, com `z` do potencial. A
[decisão 99](099-a-tela-de-metas-diz-que-o-premio-do-potencial-nao-esta-comprovado.md)
fez a tela dizer isso, e deixou para o B1 decidir o que o prêmio deve ser.

A §3 do plano oferecia três saídas: **(a)** o DCF é o produto, e a ordenação sai de
um modelo transversal declarado; **(b)** o DCF tem de ganhar; **(c)** os dois,
medidos lado a lado. A recomendação era (c) com (a) implantado enquanto (b) é
perseguido, e o usuário a autorizou em 16/09/2026.

O B1 também tinha de decidir **o que o retorno esperado é**. A
[decisão 62](062-o-esperado-e-retorno-total-e-nao-pede-yield.md) o fez retorno
total, pelo CAPM; a simulação da carteira é de preço
([decisão 23](023-remocao-de-proventos.md)); e a meta era comparada com os dois
sem dizer qual.

**A medição e a regra foram fixadas por escrito antes de medir**, em
[ordenacao_lado_a_lado.md](../validacao/ordenacao_lado_a_lado.md) §1: três
ordenações — o composto dos escores do potencial, do book-to-market e do lucro
sobre o preço, com pesos iguais; o book-to-market; o potencial —, sobre as mesmas
observações das coortes trimestrais de 36 meses com as deslistadas, julgadas pelo
critério da [decisão 96](096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md);
o prêmio sai da primeira que passar, nesta ordem, e de nenhuma se nenhuma passar.

## Decisão

1. **O preço justo é o produto da tela de avaliação, e o prêmio do retorno
   esperado sai da ordenação que a validação comprovou** — a saída (a), com a (c)
   como método. O modelo transversal declarado é o composto (`TransversalScore`),
   e a regra que escolhe a ordenação mora no núcleo
   (`SkillReading.premiumOrdering`), lendo o pacote que a medição grava.
2. **Sem ordenação comprovada, não há prêmio**: o retorno esperado de cada ativo é
   o `Ke` dele. Afirmar desconto relativo como retorno seria afirmar habilidade que
   a validação não mediu.
3. **O retorno esperado é total**: o `Ke` do CAPM inclui o provento, e a meta é um
   plano de patrimônio que o reinveste. A tela de metas diz "retorno total, com
   proventos reinvestidos"; a aba Análise diz, ao lado do XIRR, que a simulação é
   só de preço.

**Medido em 16/09/2026, sobre o motor da [decisão 102](102-nenhuma-avaliacao-muda-de-via-e-a-firma-avalia-pelo-fluxo-do-acionista-derivado.md):
nenhuma ordenação passa.** Em 36 meses, com as deslistadas, o composto tem IC de
0,173 e `t` corrigido de 1,57; o book-to-market, 0,186 e 2,52; o potencial, 0,078 e
0,61 — contra o crítico de 2,70. **O aplicativo, hoje, espera de cada ativo o
`Ke` dele.**

## Consequências aceitas

**A meta fica mais difícil de fechar para quem escolhia pelo desconto.** Uma
carteira de ativos baratos pelo potencial esperava mais que o `Ke`; agora espera o
`Ke`. É a consequência de não afirmar o que não se mediu, e a tela diz por quê.

**O book-to-market esteve na borda nas duas medições, e a regra não arredonda.**
Passava com 2,92 sobre o motor de antes e fica com 2,52 sobre este, porque a
amostra é a das observações que o motor avalia, e a decisão 102 tirou dela as
endividadas. Positivo em 22 de 22 coortes: é direção, e não prova, no nível que a
decisão 96 pede. O prêmio volta quando uma medição posterior mostrar uma ordenação
que passe — sem mudar código.

**A regra foi escolhida antes, e a ordem dela é uma preferência declarada.** O
composto vem primeiro porque é o modelo da saída (a); o book-to-market, porque é o
fator contra o qual a §0 mediu o motor. Os pesos iguais do composto não se ajustam
ao resultado.

**O potencial dado o book-to-market caiu** para 0,010, com `t` corrigido de 0,08. É
a leitura do R3 sobre o motor de hoje, e não o veredito: o C1 mede na Fase 4.

**A ressalva da decisão 99 continua, e mudou de assunto.** A tela de metas diz de
onde sai o prêmio — hoje, que não há — e continua dizendo que o potencial sozinho
não comprovou ordenar, com o número. Ela some só quando o prêmio sair do potencial
e o potencial estiver comprovado.

**O estimador do potencial sozinho continua no núcleo**
(`ExpectedReturn.forPortfolioCrossSectional`), para as ferramentas de validação que
o medem; o aplicativo usa `ExpectedReturn.forPortfolioOrdered`.

**O que fica de fora.** Os ativos recusados pelo motor não entram no retorno
esperado, embora tenham book-to-market: o `Ke` sai da avaliação, e um prêmio sem
âncora não tem leitura. A §0 mostrou que o book-to-market ordena mais nas recusadas
— é assunto para quando uma ordenação passar.
