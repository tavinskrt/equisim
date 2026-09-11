---
numero: 62
titulo: O retorno esperado já é total; a lacuna não pede dividend yield
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/usecases/portfolio_usecases.dart
  - lib/presentation/goals/goal_page.dart
  - packages/equisim_core/test/usecases_test.dart
substitui: []
---

## Contexto

`GoalAlignment.yieldToCloseGap` devolvia o *dividend yield* que fecharia a
distância entre o retorno esperado da carteira e o exigido pela meta, e a tela
de metas o exibia em prosa: *"O esperado conta apenas valorização: a simulação
não distribui provento. Um dividend yield de X% ao ano fecharia esta lacuna."*

A justificativa estava escrita e era boa: o trabalho não modela provento desde
a [decisão 23](023-remocao-de-proventos.md), de modo que o retorno apurado era
de **preço**. Uma carteira que paga bem e valoriza pouco apareceria em déficit
que não existe, e o usuário seria empurrado para risco desnecessário.

Ela deixou de valer com a [decisão 58](058-a-carteira-de-acoes-nao-espera-a-renda-fixa.md).
O retorno esperado passou de `CDI + z·prêmio` para `Ke + z·prêmio`, com
`Ke = Rf + β·prêmio` — que é, por definição do CAPM, o retorno **total**
esperado do ativo. Dividendo incluído.

Somar um yield a um retorno total conta o provento **duas vezes**, e no sentido
que faz a carteira parecer melhor do que é.

## Decisão

`yieldToCloseGap` é removido, e com ele o parágrafo da tela. A lacuna passa a
ser lida por `gap` e nada mais.

Os dois rótulos da mesma tela que ainda diziam "CDI" — o subtítulo *"CDI à
vista mais prêmio pelo desconto relativo"* e a dica *"CDI + prêmio pelo desconto
relativo"* — passam a nomear o `Ke`.

## Consequências aceitas

A carteira que paga dividendo alto e valoriza pouco volta a poder aparecer em
déficit. **A diferença é que agora isso está certo**: o `Ke` dela já embute o
provento que ela distribui, e se ainda assim o esperado não alcança o exigido,
a lacuna é real.

O que se perde é o amparo explícito ao investidor de renda. Ele era um remendo
correto para um número que mudou de significado, e manter o remendo depois da
mudança é pior do que não ter tido nenhum.

**O defeito é de costura, e é o terceiro do mesmo cartão.** A decisão 58 mudou
o número e três rótulos a três funções de distância continuaram descrevendo o
anterior — um deles com um comentário ao lado gabando-se de ter corrigido o
rótulo *anterior*. Nada no gate pega isso: o teste do `yieldToCloseGap` afirmava
a identidade `yield == −gap`, que continuou verdadeira e vazia enquanto a
premissa morria embaixo dela.
