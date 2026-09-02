---
numero: 23
titulo: Backtest sem proventos, com ação inteira e caixa residual
status: aceita
origem: voce
data: 2026-09-02
citacao: >
  remover os proventos da jogada do backtest. Isso implica que devemos tratar
  shares como inteiro. A intenção do backtest é apenas fazer com que o usuário
  consiga ver como a carteira montada desempenhou no passado
afeta:
  - packages/equisim_core/lib/src/services/backtest
  - packages/equisim_core/lib/src/services/portfolio
  - packages/equisim_core/lib/src/usecases
  - packages/equisim_core/lib/src/repositories
  - lib/data
  - lib/presentation/backtest
  - lib/presentation/valuation
  - tool/validation
substitui: []
---

## Contexto

O motor de backtest creditava provento pela posição vigente na data-ex,
descontava IRRF conforme uma `TaxPolicy` declarada e reinvestia o líquido no
próprio ativo pagador na data de pagamento. Isso forçava três coisas que se
sustentavam umas às outras:

1. **Quantidade fracionária de ações.** O reinvestimento de R$ 37,42 num papel
   de R$ 66,90 só fecha com 0,559 ação. A tela exibia "12,47 cotas", número que
   não existe em extrato de corretora nenhuma.
2. **Uma cadeia inteira de dados.** `DividendEvent`, `DividendKind`,
   `TaxPolicy`, `DividendBasis`, `TotalReturnEngine`, `DividendRepository`, a
   tabela `cached_dividends`, o endpoint `/v2/stocks/dividends` e um portão de
   qualidade que conferia o fluxo contra o *dividend yield* publicado.
3. **Uma premissa não conferida.** `DividendBasis.gross` — que o valor
   publicado pela fonte é bruto — estava declarada como "sujeita a conferência
   documental" contra os avisos aos acionistas, e a conferência nunca
   aconteceu. Todo número de provento do trabalho dependia dela.

Duas superfícies fora do backtest também dependiam de provento: o modelo de
Gordon, terceiro degrau da cascata de avaliação, e a soma do *dividend yield*
líquido ao retorno esperado da carteira na tela de estudo.

A pergunta que a simulação existe para responder é uma só: **como a carteira
montada teria se comportado no passado**. Ela é respondida pelo preço.

## Decisão

Provento sai do projeto inteiro.

- O backtest opera sobre `close`, com **quantidade inteira de ações**: cada
  fatia de aporte compra o maior número de lotes de uma ação que couber no
  preço do dia.
- A sobra vira **caixa do ativo**, acumula e participa dos aportes seguintes.
  Entra no patrimônio dia a dia, de modo que nenhum centavo aportado
  desaparece da curva. A fatia de um ativo sem cotação no dia, que antes era
  descartada, também fica no caixa.
- A divisão de cada aporte pelos pesos **distribui o resto** em centavos
  inteiros, então `Σ invested` reconstitui o aportado exatamente. O defeito
  conhecido de arredondamento por fatia deixa de existir.
- A cascata de avaliação passa a ter três degraus: FCFF → LPA → múltiplos, com
  o valor patrimonial por ação como piso do último.
- O retorno esperado da carteira é a convergência de preço até o valor justo, e
  nada mais.
- Beta e correlação passam a ser apurados sobre séries de `close`.
- Somem do código: `DividendEvent`, `DividendKind`, `TaxPolicy`,
  `DividendBasis`, `TotalReturnEngine`, `DividendRepository` e a implementação
  dele, `DividendQualityGate`, `BrapiDividendDto`, `DcfCalculator.gordonGrowth`
  e `ValuationModel.gordonGrowth`. O cache sobe para a versão 2, que apaga a
  tabela `cached_dividends` e a coluna `published_dividend_yield`.

## Decisões do plano congelado que esta derruba

Quatro decisões numeradas do [`PLANO_ARQUITETURA.md`](../../PLANO_ARQUITETURA.md)
deixam de valer aqui. Elas **não** entram no campo `substitui` porque não têm
arquivo próprio em `docs/decisoes/` — o campo cita decisões desta pasta, e o
gate local recusa referência a arquivo inexistente. Ficam registradas no corpo,
que é onde a cadeia se reconstrói:

| # | O que dizia | Situação |
|---|---|---|
| 12 | IR sobre JCP: modelar, 15% retido na fonte | Sem objeto — não há JCP no modelo |
| 16 | `RENDIMENTO` é isento, como dividendo | Sem objeto — não há rótulo fiscal |
| 17 | Usar `label` e `statistics.dividendYield` como portão de qualidade | Revogada — o portão saiu junto com o fluxo |
| 18 | `rate` é base bruta, premissa declarada | Revogada — a premissa não é mais usada por cálculo nenhum |

A decisão 9 (**sem rebalanceamento**) e a 15 (**TWR e XIRR juntos**) continuam
valendo integralmente: nenhuma delas depende de provento.

## Consequências aceitas

**O retorno do trabalho passa a ser de preço, e é menor que o do acionista
real.** Quem detém ação brasileira recebe dividendo isento e JCP líquido de
15%; nada disso aparece mais nos números. A estimativa fica conservadora por
construção — e isso precisa estar dito onde o número aparece, não só aqui.

**Comparar a carteira com o Ibovespa passa a misturar duas convenções.** O
índice é de retorno total por construção e continua sendo; o `close` dos ativos
não. O efeito sobre o beta é de segunda ordem, porque ele mede covariância de
variações e não nível, mas a assimetria existe e fica declarada em
`PrepareValuationInputs._estimateBeta`.

**Ativos que só tinham Gordon caem um degrau.** Um papel sem fluxo de caixa e
sem lucro por ação utilizáveis era avaliado pela perpetuidade de dividendos;
agora recebe o valor patrimonial por ação, rotulado como piso contábil e não
como valor intrínseco. É uma estimativa pior, e o resultado diz isso.

**O caixa residual é ruído novo na tela.** Uma carteira de papel caro diante de
um aporte pequeno pode terminar com dezenas de reais parados. O número é
verdadeiro e informativo — diz que o aporte não comporta a composição —, mas é
uma linha a mais para o leitor entender.

**A alternativa descartada** era manter provento só no valuation, preservando o
modelo de Gordon e o *yield* no retorno esperado. Ela foi recusada porque
manteria viva a cadeia inteira de dados — repositório, cache, DTO, política
fiscal — para alimentar um degrau de cascata que raramente é alcançado, e
manteria em produção a premissa de base bruta que nunca foi conferida.
