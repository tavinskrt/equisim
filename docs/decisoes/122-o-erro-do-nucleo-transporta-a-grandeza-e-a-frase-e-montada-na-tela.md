---
numero: 122
titulo: O erro do núcleo transporta a grandeza que a regra violou, e a frase é montada na tela
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B20, B22, B23, B21 e C5.
afeta:
  - packages/equisim_core/lib/src/failures/failure.dart
  - packages/equisim_core/lib/src/entities/portfolio.dart
  - lib/presentation/shared/failure_copy.dart
  - test/presentation/failure_copy_test.dart
substitui: []
---

## Contexto

O item B21 saiu de três execuções de lente em duas rodadas — `nucleo` duas
vezes, `registro` uma —, todas apontando a mesma coisa: **o núcleo monta frase
de tela**. A evidência canônica era

```dart
'Os pesos devem somar 100%; somam ${(total * 100).toStringAsFixed(2)}%.'
```

**Metade do arranjo já existia.** `Failure.message` é declarado como diagnóstico
técnico, `InvalidInput` já carregava `field` e `actual`, e `FailureCopy` já
compunha a frase a partir do tipo selado — usando `observedDeviation` de
`DataQualityFailure`. O que faltava era a outra metade.

## O que faltava, exatamente

1. **O limite não viajava.** «Limite de $maxAssets ativos por carteira
   excedido.» interpolava a constante na frase: a tela ou exibia o texto pronto,
   ou repetia a constante do lado dela — duas fontes para o mesmo número.
2. **A unidade não viajava.** Com só `actual`, a tela teria de deduzir se
   `0.7` é 70%, sete décimos de real ou sete ativos — na prática, pelo nome do
   campo, que é acoplamento por convenção de string.
3. **`actual` não era usado.** O campo existia desde a decisão 59 e nenhuma tela
   o lia; o percentual que o usuário via vinha do `toStringAsFixed` do núcleo.

## Decisão

**O núcleo diz a regra e a grandeza; a tela escreve o número.**

1. **`InvalidInput` ganha `limit` e `unit`.** `limit` é o patamar que a regra
   impõe, na mesma unidade de `actual`; `unit` é `QuantityUnit.fraction`,
   `count` ou `currency`.
2. **A mensagem do núcleo diz a regra, não o medido.** «Os pesos devem somar
   100%.» e «Limite de ativos por carteira excedido.» — a regra faz parte do
   diagnóstico técnico, e o número medido sai pelos campos.
3. **`FailureCopy` escreve «Informado: X. Limite: Y.»**, formatando pela `Fmt`
   das outras telas: percentual com uma casa para fração, **inteiro** para
   contagem — meio ativo não existe —, e moeda para reais.
4. **Sem `unit`, a tela não inventa número.** As validações que só nomeiam uma
   regra — prazo, aporte negativo, valor desejado — continuam como estão, e
   forçá-las a ter grandeza seria inventar campo para satisfazer forma.
5. **`Failure.message` continua sendo diagnóstico técnico**, e continua em
   português e específico: ele é o que a auditoria e o log leem. O que sai dele
   é a **formatação de apresentação**, não a informação.

## O que isto não resolve, e é deliberado

**A dívida do B21 tinha três metades, e esta decisão fecha uma.** As outras
duas continuam inventariadas:

- **`double` onde o domínio pede inteiro e centavo.** `FundamentalsSnapshot`
  declara `netIncome`, `ebitda` e a **contagem de ações** como `double`, e o
  caminho de avaliação corre em `double` do começo ao fim. Trocar isso é
  reescrever o motor, não ajustar a fronteira do erro.
- **Enums do núcleo carregam `label` pronto para a tela** — `ValuationCaveat`,
  `ScenarioBand`, `MultipleKind`. **Esta metade cresceu na rodada anterior**,
  com os enums do B5 seguindo a convenção existente: desviar num enum novo seria
  incoerência, não melhoria.

**As duas exigem decisão própria, com escopo declarado**, e não cabem dentro de
um item cujo critério de pronto nomeia a fronteira do `Failure`. Ficam no
registro, e é isso que o item B21 passa a significar daqui em diante.

## Consequências aceitas

**A frase que o usuário lê muda.** Antes: «Entrada inválida — Os pesos devem
somar 100%; somam 70,00%.» Agora: «Entrada inválida — Os pesos devem somar 100%.
Informado: 70,0%. Limite: 100,0%.» Uma casa decimal em vez de duas, e o limite
explícito. **É a tela decidindo**, que é o ponto.

**`QuantityUnit` é do núcleo, e é vocabulário de apresentação por fora.** Ela
não diz como escrever — diz **o que a grandeza é**. A alternativa seria a tela
adivinhar, e adivinhar por nome de campo quebra calado.

**Nada garante que as próximas falhas usem os campos.** O `switch` exaustivo
sobre o tipo selado quebra a compilação quando uma **variante** nova aparece,
mas não quando uma chamada nova esquece de preencher `unit`. O teste cobre os
dois casos que existem hoje; o terceiro depende de quem escrever o próximo.
