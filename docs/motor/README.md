# O motor do Equisim, peça por peça

Esta documentação descreve **o que o código faz**, regra por regra, e mostra
para cada uma de onde ela vem: o arquivo e a função que a executam, a fórmula,
a base teórica e a evidência que o próprio projeto produziu (decisão registrada,
medição, teste). O objetivo é que qualquer número do preço justo possa ser
seguido até a linha que o produziu e até o livro ou artigo que o justifica.

> **Escrita do zero em 28/09/2026, conferindo o código linha a linha**
> ([decisão 141](../decisoes/141-a-documentacao-do-motor-e-refeita-do-zero-contra-o-codigo.md)).
> Ao conferir, sete defeitos foram achados e registrados no
> [plano](../plano-motor-de-referencia.md) (itens B35 a B41); seis foram
> corrigidos, e o B38 aguarda decisão. O texto abaixo descreve o código **depois**
> das correções.
>
> Para aprender o assunto do zero, use o [guia de estudo](../estudo/README.md).
> Esta documentação supõe o vocabulário dele.

---

## Os capítulos

| # | Capítulo | O que cobre |
|---:|---|---|
| 1 | [Insumos e dados](01-insumos-e-dados.md) | fontes, visão *point-in-time*, grandezas do exercício, contagem de papéis, unit, curva, CDI, IPCA, beta |
| 2 | [Cascata e portas](02-cascata-e-portas.md) | elegibilidade, roteamento, as duas vias, recusas |
| 3 | [Base e crescimento](03-base-e-crescimento.md) | alíquota estrutural, série de capital, as três guardas, normalização, crescimento, perpetuidade |
| 4 | [Custo de capital](04-custo-de-capital.md) | CAPM, beta encolhido, Hamada, custo da dívida, WACC, curva, ponto fixo |
| 5 | [Projeção, desconto e terminal](05-projecao-desconto-e-terminal.md) | as fórmulas do DCF, as três formas de terminal, a passagem da firma ao acionista |
| 6 | [Resultado e tela de avaliação](06-resultado.md) | cenários, Monte Carlo, faixa calibrada, múltiplos, ressalvas, avisos, rastro |
| 7 | [O resto do aplicativo](07-aplicativo.md) | carteiras, meta, retorno esperado, simulação com aportes |
| 8 | [Como o motor é verificado e validado](08-verificacao-e-validacao.md) | gate de QA, lentes, gabarito, testes, R1–R3, réplica selada |
| — | [Referências](referencias.md) | bibliografia citada |

## Onde está o código

| Pasta | Conteúdo |
|---|---|
| [`packages/equisim_core/lib/src/usecases/compute_valuation.dart`](../../packages/equisim_core/lib/src/usecases/compute_valuation.dart) | a cascata inteira (`ValuationCascade`), os avisos e o rastro de auditoria |
| [`packages/equisim_core/lib/src/services/valuation/`](../../packages/equisim_core/lib/src/services/valuation/) | as peças: DCF, custo de capital, guardas, curva, cenários, faixa, múltiplos |
| [`packages/equisim_core/lib/src/services/metrics/`](../../packages/equisim_core/lib/src/services/metrics/) | beta, encolhimento, retornos, métricas de risco |
| [`packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart`](../../packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart) | a montagem dos insumos de uma avaliação |
| [`lib/`](../../lib/) | o aplicativo Flutter: dados (fontes, cache), telas |
| [`tool/`](../../tool/) | medições, backtest, gabarito, empacotadores de dados |

O núcleo (`packages/equisim_core`) é **Dart puro, sem nenhuma dependência de
execução**, sem rede, sem arquivo, sem relógio: a mesma entrada dá a mesma saída
hoje e daqui a um ano. Isso é travado por teste
([purity_test.dart](../../packages/equisim_core/test/purity_test.dart)) e é o que
torna o gabarito possível.

## Como ler as tabelas

Cada regra aparece numa linha com as colunas:

- **Regra** — o que o motor faz, em uma frase;
- **Código** — arquivo e função (não número de linha: a função sobrevive a
  edições, a linha não);
- **Fundamento** — a teoria ou referência (detalhes em [referências](referencias.md));
- **Evidência** — a decisão que a registrou e, quando houver, a medição.

As decisões estão em [`docs/decisoes/`](../decisoes/); as medições, em
[`docs/validacao/`](../validacao/).
