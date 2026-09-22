---
numero: 125
titulo: A fronteira do dinheiro arredonda o decimal escrito, o caminho de estimação é real, e o rótulo de tela sai do núcleo
status: aceita
origem: voce
data: 2026-09-22
citacao: >
  Seus itens de escopo para esta rodada são B8, B21 (pode finalizar a
  reescrita das outras duas metades), C4 e D3.
afeta:
  - packages/equisim_core/lib/src/value_objects/money.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/entities/portfolio.dart
  - packages/equisim_core/lib/src/services/valuation/eligibility.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - lib/presentation/shared/domain_copy.dart
  - test/presentation/domain_copy_test.dart
substitui: []
---

## Contexto

A [decisão 122](122-o-erro-do-nucleo-transporta-a-grandeza-e-a-frase-e-montada-na-tela.md)
fechou uma das três metades do item B21 — o `Failure` passou a transportar a
grandeza, e a frase passou a ser montada na tela — e inventariou as outras duas,
dizendo que exigiam decisão própria com escopo declarado:

- **(b)** o `Money` em centavos inteiros vale na carteira e no aporte, e o
  caminho de avaliação corre em `double` do começo ao fim — inclusive o lucro, o
  EBITDA e a contagem de ações, que é grandeza inteira;
- **(c)** os enums do núcleo carregam `label` pronto para a tela.

Esta é a decisão. Antes de reescrever, **medi o que cada uma das duas acusações
significava no código**, e a (b) se revelou três coisas diferentes, das quais só
uma era defeito.

## (b) O que o `double` do caminho de avaliação era, parte por parte

### 1. A fronteira do `double` para o dinheiro tinha defeito — e foi consertada

O caminho de avaliação **já devolvia `Money`**: preço justo, preço de mercado e
os três cenários saem por `Money.fromReais`. E essa fronteira fazia
`(reais * 100).round()` — o padrão exato que
`test/qa_fixtures/financial_edge_cases.json` registra como quebrado
(`tostringasfixed-nao-e-half-up`): `1.005 * 100` resulta em `100.49999999999999`,
e R$ 1,005 virava R$ 1,00. O próprio comentário do método documentava a falha
como limitação.

**Agora `Money.fromReais` arredonda o decimal escrito**: a menor representação
decimal do `double` — a que `toString` devolve —, meio afastado de zero. `1.005`
dá 101 centavos, `2.675` dá 268, `-1.005` dá −101, e `0.1 + 0.2` dá 30, porque
um valor que já chega com erro de conta é arredondado pelo que ele é. Por ela
passam também a cotação da simulação e o que o usuário digita na aba Meta.

**O gabarito da cascata continua idêntico** nos 376 ativos, nas nove montagens e
no rastro bit a bit: nenhum preço justo do universo caía num meio centavo
perdido. O defeito era real e não tinha vítima registrada — que é a melhor hora
de consertar.

### 2. Os insumos contábeis em `double` não perdem centavo — e isso está provado

A ingestão da CVM já lê **em centavos exatos**, do texto ao inteiro, sem ponto
flutuante no caminho (`CvmAccountLine.doTexto`, com `BigInt` contra estouro). O
`FundamentalsSnapshot` guarda o valor em reais `double`, e a pergunta é se a
conversão perde algo.

**Não perde, na faixa em que um balanço vive.** O `double` tem 53 bits de
mantissa: representa todo inteiro até 9·10¹⁵ e tem casa de centavo até R$ 90
trilhões. O maior ativo total do universo passa pouco de R$ 1,5 trilhão. O
teste `o double do balanço não perde centavo` confere a ida e volta centavo →
`double` → `Money` em 20 mil valores sorteados até R$ 45 trilhões, e em todos
ela é exata.

O que acontece **depois** — multiplicar por taxa, compor por prazo, descontar —
é estimação, e estimação é conta real por natureza: `(1 + k)^t`, `ln`, a média
de uma distribuição. Arredondar cada passo para o centavo **introduziria** erro
sem proteger nada, porque o que sai da conta é uma estimativa com faixa de
incerteza de dezenas de por cento. A regra do projeto — «aritmética inteira em
centavos, `double` só na fronteira de apresentação» — é a regra do **dinheiro
que se move**: aporte, caixa, posição, custo. O preço justo não se move; ele se
estima, e cruza para `Money` na saída, que é a fronteira.

### 3. A contagem de ações não é inteira no motor — e não deve ser

A acusação dizia que a contagem é «grandeza inteira por convenção de domínio».
**No registro, é**: a B3 e a CVM publicam inteiros, e o `double` os guarda
exatos (todo inteiro abaixo de 9·10¹⁵). **No motor, não é**, e por boa razão: o
divisor do preço justo é a contagem **na unidade negociada**. Uma *unit* de uma
ordinária e duas preferenciais divide o total por três, e a contagem implícita
no valor de mercado é valor sobre preço — as duas são estimativas legítimas, e
fracionárias. Forçar `int` ali seria arredondar uma razão, e o preço justo
herdaria o arredondamento.

A convenção que importa — **ação inteira onde se compra** — já é cumprida onde
ela vale: a simulação compra quantidade `int` e guarda a sobra em caixa
(decisão 23).

## (c) O rótulo de tela sai dos enums do núcleo

**Catorze enums** carregavam `label`: `PortfolioKind`, `ValuationModel`,
`ScenarioBand`, `ValuationCaveat`, `CvmLayout`, `FieldSource`,
`TransversalOrdering`, `ValuationLane`, `IneligibilityReason`, `GrowthOrigin`,
`MoatBlock`, `MultipleKind`, `MultipleRefusal` e `QuotedSharesSource`. Um
décimo quinto, `TerminalValueMethod`, **não tinha uso nenhum** no repositório, e
foi removido.

1. **O que a tela mostra mora em `lib/presentation/shared/domain_copy.dart`**,
   em extensões `rotulo` com `switch` exaustivo — um valor novo quebra a
   compilação ali, e não sai na tela como `name` cru. O arquivo não importa
   Flutter, e as ferramentas que escrevem relatório usam os mesmos rótulos.
2. **O que o núcleo escreve para si continua no núcleo.** O rastro de cálculo e
   a mensagem de falha são diagnóstico técnico, e a decisão 122 os mantém em
   português e específicos. Os seis enums que só o rastro nomeia — a origem do
   divisor, a via, o múltiplo, o modelo, a origem do crescimento e o bloqueio
   do moat — ganharam uma extensão **privada** `diagnostico` em
   `compute_valuation.dart`, com o mesmo texto de antes: **o rastro não mudou
   uma letra**, e o gabarito confere isso bit a bit.
3. **`EligibilityVerdict.message` dizia «Frase única para a interface»**, e não
   era: ela só vai para a falha e para o rastro. A documentação passou a dizer
   o que ela é — diagnóstico —, e a tela lê `reasons`.
4. **`CvmLayout` e `FieldSource` não eram texto de tela**: o rótulo de um só era
   lido por uma ferramenta de conferência, que passou a usar `name`, e o do
   outro não era lido por ninguém.

## O que isto fecha

**O item B21 fecha inteiro.** As três metades: (a) pela decisão 122; (b) com a
fronteira do dinheiro consertada e o resto medido e declarado; (c) com o
rótulo na apresentação.

## Consequências aceitas

**Há dois textos para seis enums** — o diagnóstico no núcleo e, quando a tela os
mostrar, o rótulo na apresentação. É a mesma duplicação que a decisão 122
aceitou para o `Failure`, pela mesma razão: o rastro é lido pela auditoria e o
rótulo pelo usuário, e amarrar um ao outro devolveria à tela a redação do
núcleo. Hoje os dois coincidem porque os rótulos foram movidos, e não
reescritos; podem divergir quando a tela quiser.

**A troca de `Money.fromReais` muda o arredondamento em casos de meio centavo**
que antes caíam para baixo. Na simulação, uma cotação com três casas que caía
no meio passa a subir; na aba Meta, um valor digitado com três casas também.
São exatamente os casos em que a regra do BRL manda subir.

**O caminho de estimação continua em `double`**, e esta decisão é o registro de
que isso é escolha e não descuido. Quem quiser mudar precisa mostrar um preço
justo que se move por arredondamento — o que o gabarito, até aqui, nunca
mostrou.
