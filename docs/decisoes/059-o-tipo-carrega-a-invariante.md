---
numero: 59
titulo: O tipo carrega a invariante — ponto de taxa, base de tempo, valor medido na falha, e os verbos de interface saem do domínio
status: aceita
origem: conselheiro
data: 2026-09-11
citacao: >
  Criar um objeto de valor simples que consolide um único ponto no tempo (data)
  com o seu valor em taxa. Modificar RateSeries para consumir internamente e
  exigir no construtor uma lista do novo objeto de valor.
afeta:
  - packages/equisim_core/lib/src/repositories/repositories.dart
  - packages/equisim_core/lib/src/failures/failure.dart
  - packages/equisim_core/lib/src/entities/portfolio.dart
  - packages/equisim_core/lib/src/services/goal/feasibility.dart
  - packages/equisim_core/lib/src/usecases/portfolio_usecases.dart
  - packages/equisim_core/test/result_and_rates_test.dart
  - packages/equisim_core/test/portfolio_test.dart
  - lib/data/datasources/remote/bcb_datasource.dart
  - lib/data/repositories/market_repositories.dart
substitui: []
---

## Contexto

A [decisão 58](058-a-carteira-de-acoes-nao-espera-a-renda-fixa.md) fez
`RateSeries` **verificar** que as duas listas paralelas tinham o mesmo tamanho.
A lente `nucleo` respondeu que verificar é tratar o sintoma: duas listas que se
prometem alinhadas ou viram uma lista de pares, ou a promessa continua sendo
responsabilidade de quem constrói.

Ela tinha razão, e o caminho da falha existia no código: `market_repositories`
iterava `series.rates` **indexando `series.dates[i]`**.

## Decisão

### 1. `RatePoint`, e o construtor por listas paralelas deixa de existir

`RateSeries` guarda `List<RatePoint>`. `dates` e `rates` continuam disponíveis
como **vistas derivadas**, e `tail(n)` substitui o recorte manual que
`_currentRateOf` fazia com dois `sublist` coordenados.

**Não há mais estado em que a data e a taxa discordem em quantidade** — a
verificação da decisão 58 vira desnecessária por construção.

### 2. A série carrega a própria frequência

`annualized({periodsPerYear})` deixava a série muda sobre a própria base e o
chamador responsável por acertá-la — com a documentação avisando que *"errar
esta base desloca o resultado em ordens de grandeza"*. Uma série mensal
anualizada em base 252 devolve número plausível e errado por vinte vezes.

`TimeBasis` entra como propriedade da série, e `annualized()` deixa de aceitar
parâmetro. O mapeamento de código do SGS para base mora no `BcbDatasource`,
que é onde se sabe qual série foi pedida: 12 é CDI diário em dias úteis, 433 e
24364 são mensais.

### 3. `InvalidInput` carrega o valor medido

`actual` entra pela mesma razão que `DataQualityFailure.deviation` já existia: a
soma dos pesos entrava na mensagem já formatada, e quem quisesse arredondar de
outro jeito teria de reextraí-la do texto. **O domínio diz quanto; a
apresentação decide como escrever.**

### 4. `FeasibilityVerdict.blocks` e `warns` saem

Diziam "a interface deve impedir" e "a interface deve alertar" — verbos de
apresentação num tipo de domínio. **A interface não os usava**: só os testes,
que passam a afirmar sobre `level`, que é o fato.

### 5. `Portfolio.maxAssets` fica, e a justificativa é reescrita

A lente a apontou como limite de interface vazado. **A conferência mostrou o
contrário**: a apresentação só exibe o contador, e quem recusa o décimo sexto
ativo são as fábricas do domínio. Um teto que a tela apenas mostra e o domínio
impõe é regra de domínio — o que estava errado era a justificativa, que citava
a degradação do arrastar e soltar.

A razão real é de produto: acima de quinze ativos o alerta de concentração
setorial deixa de discriminar e a comparação entre Principal e Reserva perde o
sentido de "duas teses".

## Consequências aceitas

**Nenhum número muda.** Esta decisão é de tipos: nada aqui toca cálculo.

**`dates` e `rates` passam a alocar a cada acesso**, por serem vistas. Os
consumidores que os liam em laço passaram a iterar `points`; os que restam
chamam uma vez.

**Uma verificação de tempo de execução foi substituída por impossibilidade de
tempo de compilação**, que é a troca certa: o `ArgumentError` da decisão 58
protegia contra um estado que agora não existe.

**O gate reprovou uma vez e aprovou na seguinte, sobre o mesmo diff.** O
parecer que reprovou citou divisão por zero propagando NaN até a tela, sem
apontar a linha. A conferência do caminho implicado — `z = (u − mediana) ÷
escala`, no estimador transversal — mostra que ele não existe:
`Inference.scaledMad` devolve **nulo**, e não zero, quando a dispersão some, e
o nulo já era tratado. Ficou travado por teste, para que a afirmação não
dependa de leitura de código: seção colapsada num ponto e seção de um ponto só
devolvem retorno esperado finito.

**A alternativa descartada** no item 5 era mover o teto para a apresentação,
como a lente pediu. Recusada porque removeria a **única** barreira: a tela
exibe `15` e não impede nada, de modo que a mudança silenciosamente permitiria
carteiras de vinte ativos.
