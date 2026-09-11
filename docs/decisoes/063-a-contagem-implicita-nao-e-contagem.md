---
numero: 63
titulo: A contagem implícita no valor de mercado não é contagem, e fica em double
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - packages/equisim_core/lib/src/services/backtest/portfolio_backtest.dart
substitui: []
---

## Contexto

A lente `nucleo` propõe, de forma recorrente, que as contagens de papéis do
núcleo deixem de ser `double` e passem a `int` — nomeando
`FundamentalsSnapshot.sharesFromMarketCap` e pedindo "divisões exatas truncadas
de `int`". O argumento invoca a regra do
[CLAUDE.md](../../CLAUDE.md): *"Quantidade de ação e cota de FII é **inteira**"*
e *"fração de ação em caminho de cálculo é defeito"*.

A regra está certa e **já é cumprida onde ela fala**. O caminho que compra
papel é `PortfolioBacktest._allocate`, e ele opera em `Map<Ticker, int> shares`
com `available ~/ priceCents`: divisão inteira sobre centavos inteiros, com o
resto ficando em caixa por ativo para o aporte seguinte. Não há fração de ação
em lugar nenhum da simulação.

## Decisão

As contagens do **caminho de avaliação** ficam em `double`, e a razão é que não
são contagens.

`sharesFromMarketCap` devolve `VM ÷ preço`. Isso não enumera papéis: é o
**fator de escala** que põe o valor do capital próprio apurado pelo modelo na
mesma unidade do preço de tela. A ponte só precisa da razão `E ÷ VM − 1`, e a
contagem some dela por construção — está escrito no comentário do próprio
getter. Truncar esse fator para inteiro introduziria erro onde hoje não há
nenhum, e o erro seria maior justamente nas empresas de contagem pequena.

O mesmo vale para `sharesPerQuote`, que é inteiro por construção em `[1, 10]`
mas fica em `double` para que `conciliada / sharesPerQuote` continue sendo
divisão real. Trocá-lo por `int` convida `~/` num divisor que não deve truncar.

## Consequências aceitas

A leitura superficial do tipo continua sugerindo que o núcleo admite fração de
ação, e a lente continuará apontando. **O tipo não carrega a distinção entre
"papéis que se compram" e "escala que se aplica"**, e esta decisão é o lugar
onde ela fica registrada, já que nomear os campos de outro jeito custaria mais
clareza do que compra.

A alternativa descartada — um *value object* `ShareCount` inteiro para o
primeiro caso e um `Scale` real para o segundo — resolveria de verdade, e não
foi feita porque nenhum defeito numérico foi encontrado nos dois caminhos: o
que compra já é `int`, e o que escala já é exato. Fica disponível se algum dia
um defeito aparecer ali.
