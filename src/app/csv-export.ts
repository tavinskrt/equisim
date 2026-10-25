import { type BacktestOutcome, type DateTime, toStringAsFixed } from '../core';
import { Fmt } from '../copy';
import type { PortfolioComparison } from './backtest';

/**
 * Exportação dos resultados em CSV.
 *
 * O separador é ponto e vírgula e o decimal é vírgula: é o que o Excel em
 * português brasileiro abre sem pedir configuração de importação. Um CSV que
 * exige diálogo de importação não serve para anexar a uma monografia.
 */
export const CsvExport = {
  separator: ';',

  /** Série temporal das duas carteiras. */
  comparisonSeries(result: PortfolioComparison): string {
    const reference = result.principal ?? result.reserve;
    if (reference === null) return '';
    const lines = [
      ['data', 'principal_base100', 'principal_patrimonio', 'reserva_base100', 'reserva_patrimonio'].join(
        CsvExport.separator,
      ),
    ];
    for (let i = 0; i < reference.dates.length; i++) {
      lines.push(
        [
          Fmt.date(reference.dates[i]!),
          valueAt(result.principal?.base100, i),
          valueAt(result.principal?.wealth, i),
          valueAt(result.reserve?.base100, i),
          valueAt(result.reserve?.wealth, i),
        ].join(CsvExport.separator),
      );
    }
    return lines.join('\n') + '\n';
  },

  /** Métricas consolidadas, para conferência cruzada em Python ou planilha. */
  metrics(result: PortfolioComparison): string {
    const lines = [['metrica', 'principal', 'reserva'].join(CsvExport.separator)];
    const row = (label: string, a: number | null | undefined, b: number | null | undefined, decimals = 6) => {
      lines.push(
        [label, a == null ? '' : n(a, decimals), b == null ? '' : n(b, decimals)].join(CsvExport.separator),
      );
    };
    const p = result.principal?.metrics;
    const r = result.reserve?.metrics;
    row('retorno_ponderado_tempo_twr', p?.timeWeightedReturn, r?.timeWeightedReturn);
    row('retorno_ponderado_dinheiro_xirr', p?.moneyWeightedReturn, r?.moneyWeightedReturn);
    row('cagr', p?.cagr, r?.cagr);
    row('volatilidade_anualizada', p?.volatility, r?.volatility);
    row('max_drawdown', p?.maxDrawdown, r?.maxDrawdown);
    row('sharpe', p?.sharpe, r?.sharpe);
    row('sortino', p?.sortino, r?.sortino);
    row('calmar', p?.calmar, r?.calmar);
    row('patrimonio_final', result.principal?.finalValue.reais, result.reserve?.finalValue.reais, 2);
    row('capital_aportado', result.principal?.totalContributed.reais, result.reserve?.totalContributed.reais, 2);
    row('capital_alocado', result.principal?.totalAllocated.reais, result.reserve?.totalAllocated.reais, 2);
    row('custos_de_transacao', result.principal?.transactionCosts.reais, result.reserve?.transactionCosts.reais, 2);
    row('caixa_residual', result.principal?.residualCash.reais, result.reserve?.residualCash.reais, 2);
    return lines.join('\n') + '\n';
  },

  /** Desempenho individual dos ativos de uma carteira. */
  perAsset(outcome: BacktestOutcome): string {
    const lines = [
      [
        'ticker',
        'peso_alvo',
        'peso_atual',
        'deriva_pp',
        'retorno',
        'cotas',
        'capital_destinado',
        'valor_final',
        'caixa',
      ].join(CsvExport.separator),
    ];
    for (const a of outcome.perAsset.values()) {
      lines.push(
        [
          a.ticker.value,
          n(a.targetWeight.value),
          n(a.currentWeight),
          n(a.drift, 2),
          n(a.totalReturn),
          // Sem casa decimal: a quantidade é inteira.
          String(a.shares),
          n(a.invested.reais, 2),
          n(a.finalValue.reais, 2),
          n(a.cash.reais, 2),
        ].join(CsvExport.separator),
      );
    }
    return lines.join('\n') + '\n';
  },

  /**
   * O arquivo inteiro: cabeçalho, métricas, desempenho por ativo das duas
   * carteiras — o CSV é a via para conferir a troca fora do aplicativo — e a
   * série temporal.
   */
  document(args: { studyName: string; result: PortfolioComparison; generatedAt: DateTime }): string {
    const { studyName, result, generatedAt } = args;
    const parts = [
      `# Equisim — ${studyName}`,
      `# Período: ${result.window.toString()}`,
      `# Gerado em ${Fmt.date(generatedAt)}`,
      '',
      '## Métricas',
      CsvExport.metrics(result),
    ];
    if (result.principal !== null) {
      parts.push('## Desempenho por ativo (Principal)', CsvExport.perAsset(result.principal), '');
    }
    if (result.reserve !== null) {
      parts.push('## Desempenho por ativo (Reserva)', CsvExport.perAsset(result.reserve), '');
    }
    parts.push('## Série temporal', CsvExport.comparisonSeries(result));
    return parts.join('\n') + '\n';
  },
};

function n(value: number, decimals = 4): string {
  return toStringAsFixed(value, decimals).replace('.', ',');
}

function valueAt(values: readonly number[] | undefined, index: number): string {
  if (values === undefined || index >= values.length) return '';
  return n(values[index]!, 2);
}
