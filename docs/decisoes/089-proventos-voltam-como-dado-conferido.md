---
numero: 89
titulo: Proventos voltam como dado conferido da B3, no retorno total das coortes e no beta, e não como crédito da simulação
status: aceita
origem: orientador
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/services/b3/cash_dividends.dart
  - packages/equisim_core/lib/src/services/b3/b3_registry.dart
  - packages/equisim_core/lib/src/time/brazilian_calendar.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/usecases/resolve_beta_prior.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/equisim_core.dart
  - packages/equisim_core/test/cash_dividends_test.dart
  - packages/equisim_core/test/beta_total_return_test.dart
  - packages/equisim_core/test/brazilian_calendar_test.dart
  - lib/data/repositories/cash_dividends_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - assets/b3/proventos.json
  - assets/b3/emissores.json
  - tool/b3_complemento_baixar.py
  - tool/b3/proventos.dart
  - tool/b3_proventos_empacotar.dart
  - tool/proventos_conferir.dart
  - tool/backtest_valuation.dart
  - tool/regressao_condicional.dart
  - tool/padrao_ligar.dart
  - test/data/b3_tesouro_package_asset_test.dart
  - docs/validacao/proventos.md
  - CLAUDE.md
  - scripts/qa/rules.ts
substitui: []
---

## Contexto

A [decisão 23](023-remocao-de-proventos.md) tirou provento do projeto inteiro. O
motivo que a sustentava era de dado: a premissa de que o valor da fonte era
bruto nunca foi conferida contra documento, e todo número de provento dependia
dela. O item A4 do plano deixava a reabertura com o orientador.

**O orientador reabriu a decisão 23**, conforme informado pelo usuário em
14/09/2026, na escolha que pedia o retorno total nas coortes e na regressão do
beta.

A conferência passou a ser possível: o portal de empresas listadas da B3 dá o
histórico inteiro de proventos em dinheiro por emissor — 18.651 eventos dos 297
do universo — com o fechamento com direito ao lado. Ver
[proventos.md](../validacao/proventos.md).

## Decisão

**Substitui a decisão 23 em parte**: provento volta como **dado conferido**, em
dois lugares, e só neles.

1. **A fonte é a B3, e a conferência vem antes do uso.** O fechamento com direito
   que a B3 publica bate com o COTAHIST em 9.241 de 9.243 proventos, a 1%. O
   `adjustedClose` da fonte de preços continua fora de cálculo: desvia 3,3% na
   mediana de dez anos contra a B3, e mais de 5% em 101 de 278 ativos.
2. **Retorno total nas coortes de validação.** `backtest_valuation.dart` grava
   `ret12tot` e `ret36tot` ao lado do retorno de preço; a regressão condicional lê
   os dois. O provento é reinvestido no fechamento da data ex, e o fator
   `Π(1 + D/P_ex)` não depende de a série estar ajustada por desdobramento.
   Sem pregão da data ex no COTAHIST — papel que trocou de código —, vale o preço
   com direito da B3 menos o provento.
3. **O beta sai do retorno total dos dois lados.** O Ibovespa é índice de retorno
   total, e o ativo pelo fechamento não era: a queda da data ex entrava como
   risco. `TotalReturnIndex` soma `D/P_com` ao retorno do pregão da data ex, e o
   aplicativo o lê do pacote `assets/b3/proventos.json`, com os proventos desde
   2015 que têm preço com direito. `ResolveBetaPrior` aceita os mesmos proventos,
   para o prior e o beta que ele encolhe usarem a mesma régua. A auditoria diz
   quantos proventos entraram no beta.
4. **A convenção é a do acionista pessoa física:** dividendo e rendimento
   inteiros, juros sobre capital próprio líquidos dos 15% retidos.
5. **A data ex é o primeiro pregão depois da data-com.** A B3 não abre em 24/12 nem
   em 31/12, que são dias úteis bancários; `BrazilianCalendar.nextTradingSession`
   passa a valer também para a data ex dos eventos de ações do registro (A3.1),
   que usava o próximo dia útil e punha em 31/12 o evento com data-com em 30/12.

**O que da decisão 23 continua valendo:** a simulação da carteira é de preço, com
ação inteira e caixa residual; a cascata de avaliação não lê provento — o fluxo
descontado sai do lucro e da retenção, e o degrau de Gordon não volta; o retorno
esperado da carteira é a convergência de preço. Levar provento a qualquer um
deles exige decisão nova.

## Consequências aceitas

**O retorno total não muda a conclusão sobre a habilidade.** Nas coortes do motor
de 11/09/2026, o IC do potencial sozinho em 36 meses sobe de 0,161 para 0,199,
e o coeficiente condicionado a P/B e L/P fica sem significância nos dois — t de
0,43 para 0,22. A penalidade do retorno de preço existia, e não era ela que
escondia habilidade.

**O beta muda em todo ativo que paga provento**, e com ele o custo de capital e o
preço justo. O efeito, na mesma execução, está em
[fase1_padrao.md](../validacao/fase1_padrao.md).

**O pacote tem 1,1 MB**, e envelhece: provento anunciado depois de 14/09/2026 não
entra no beta até o pacote ser regerado, e a janela de cinco anos continua
coberta por ele.

**A citação literal do orientador não consta**: a reabertura chegou relatada pelo
usuário.
