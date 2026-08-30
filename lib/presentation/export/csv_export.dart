import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backtest/backtest_providers.dart';
import '../shared/ui_kit.dart';

/// Exportação dos resultados em CSV.
///
/// O separador é ponto e vírgula e o decimal é vírgula: é o que o Excel em
/// português brasileiro abre sem pedir configuração de importação. Um CSV que
/// exige diálogo de importação não serve para anexar a uma monografia.
abstract final class CsvExport {
  static const String separator = ';';

  static String _n(double value, {int decimals = 4}) =>
      value.toStringAsFixed(decimals).replaceAll('.', ',');

  /// Série temporal das duas carteiras.
  static String comparisonSeries(PortfolioComparison result) {
    final reference = result.principal ?? result.reserva;
    if (reference == null) return '';

    final buffer = StringBuffer()
      ..writeln(
        [
          'data',
          'principal_base100',
          'principal_patrimonio',
          'reserva_base100',
          'reserva_patrimonio',
        ].join(separator),
      );

    for (var i = 0; i < reference.dates.length; i++) {
      final principal = result.principal;
      final reserva = result.reserva;
      buffer.writeln(
        [
          Fmt.date.format(reference.dates[i]),
          _valueAt(principal?.base100, i),
          _valueAt(principal?.wealth, i),
          _valueAt(reserva?.base100, i),
          _valueAt(reserva?.wealth, i),
        ].join(separator),
      );
    }
    return buffer.toString();
  }

  /// Métricas consolidadas, para conferência cruzada em Python ou planilha.
  static String metrics(PortfolioComparison result) {
    final buffer = StringBuffer()
      ..writeln(['metrica', 'principal', 'reserva'].join(separator));

    void row(String label, double? a, double? b, {int decimals = 6}) {
      buffer.writeln(
        [
          label,
          a == null ? '' : _n(a, decimals: decimals),
          b == null ? '' : _n(b, decimals: decimals),
        ].join(separator),
      );
    }

    final p = result.principal?.metrics;
    final r = result.reserva?.metrics;

    row(
      'retorno_ponderado_tempo_twr',
      p?.timeWeightedReturn,
      r?.timeWeightedReturn,
    );
    row(
      'retorno_ponderado_dinheiro_xirr',
      p?.moneyWeightedReturn,
      r?.moneyWeightedReturn,
    );
    row('cagr', p?.cagr, r?.cagr);
    row('volatilidade_anualizada', p?.volatility, r?.volatility);
    row('max_drawdown', p?.maxDrawdown, r?.maxDrawdown);
    row('sharpe', p?.sharpe, r?.sharpe);
    row('sortino', p?.sortino, r?.sortino);
    row('calmar', p?.calmar, r?.calmar);
    row('dividend_yield_liquido', p?.netDividendYield, r?.netDividendYield);
    row(
      'patrimonio_final',
      result.principal?.finalValue.reais,
      result.reserva?.finalValue.reais,
      decimals: 2,
    );
    row(
      'capital_aportado',
      result.principal?.totalContributed.reais,
      result.reserva?.totalContributed.reais,
      decimals: 2,
    );
    row(
      'proventos_brutos',
      result.principal?.grossDividends.reais,
      result.reserva?.grossDividends.reais,
      decimals: 2,
    );
    row(
      'imposto_retido',
      result.principal?.withheldTax.reais,
      result.reserva?.withheldTax.reais,
      decimals: 2,
    );

    return buffer.toString();
  }

  /// Desempenho individual dos ativos de uma carteira.
  static String perAsset(BacktestOutcome outcome) {
    final buffer = StringBuffer()
      ..writeln(
        [
          'ticker',
          'peso_alvo',
          'peso_atual',
          'deriva_pp',
          'retorno_total',
          'capital_alocado',
          'valor_final',
          'proventos_brutos',
          'imposto_retido',
        ].join(separator),
      );

    for (final asset in outcome.perAsset.values) {
      buffer.writeln(
        [
          asset.ticker.value,
          _n(asset.targetWeight.value),
          _n(asset.currentWeight),
          _n(asset.drift, decimals: 2),
          _n(asset.totalReturn),
          _n(asset.invested.reais, decimals: 2),
          _n(asset.finalValue.reais, decimals: 2),
          _n(asset.grossDividends.reais, decimals: 2),
          _n(asset.withheldTax.reais, decimals: 2),
        ].join(separator),
      );
    }
    return buffer.toString();
  }

  static String _valueAt(List<double>? values, int index) {
    if (values == null || index >= values.length) return '';
    return _n(values[index], decimals: 2);
  }
}

/// Copia o resultado em CSV para a área de transferência.
///
/// A área de transferência é a via portátil: funciona em todas as plataformas
/// do projeto — incluindo web, onde salvar arquivo exigiria intermediação do
/// navegador — e cola direto na planilha.
Future<void> exportComparisonCsv({
  required BuildContext context,
  required String studyName,
  required PortfolioComparison result,
}) async {
  final buffer = StringBuffer()
    ..writeln('# Equisim — $studyName')
    ..writeln('# Período: ${result.window}')
    ..writeln('# Gerado em ${Fmt.date.format(DateTime.now())}')
    ..writeln()
    ..writeln('## Métricas')
    ..writeln(CsvExport.metrics(result));

  // As duas carteiras exportam por ativo: o CSV é a via para conferir a
  // decisão de troca fora do aplicativo, e ela compara os dois lados.
  if (result.principal != null) {
    buffer
      ..writeln('## Desempenho por ativo (Principal)')
      ..writeln(CsvExport.perAsset(result.principal!))
      ..writeln();
  }

  if (result.reserva != null) {
    buffer
      ..writeln('## Desempenho por ativo (Reserva)')
      ..writeln(CsvExport.perAsset(result.reserva!))
      ..writeln();
  }

  buffer
    ..writeln('## Série temporal')
    ..writeln(CsvExport.comparisonSeries(result));

  await Clipboard.setData(ClipboardData(text: buffer.toString()));

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV copiado — cole numa planilha ou num arquivo .csv'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
