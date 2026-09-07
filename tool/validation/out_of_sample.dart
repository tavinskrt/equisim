import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'context.dart';

/// Validação fora da amostra da arquitetura de portas.
///
/// **Por que existe.** Os treze parâmetros da decisão 25 foram calibrados sobre
/// dezoito ativos cujo volume financeiro diário mediano vai de R$ 36,6 mi a
/// R$ 1.541,9 mi — a amostra inteira está no decil superior de liquidez do
/// mercado, cuja mediana é de R$ 9,2 mi. Aplicar essas regras ao universo sem
/// medir o que acontece seria extrapolar a calibragem em silêncio.
///
/// O que este relatório responde: qual a **distribuição de saídas por porta** no
/// universo elegível, e se as proporções fazem sentido setorialmente. Um
/// parâmetro que separa bem dezoito ativos e classifica 90% do universo na mesma
/// gaveta não está separando nada.
abstract final class OutOfSampleValidation {
  /// Executa a validação e escreve o relatório.
  ///
  /// - [ctx]: contexto com os repositórios de produção.
  /// - [limit]: teto de ativos a avaliar, para execução parcial.
  /// - [outputDir]: destino do relatório.
  static Future<void> run(
    ValidationContext ctx, {
    required String outputDir,
    int limit = 200,
  }) async {
    final today = DateTime(2026, 9, 4);

    stdout.writeln('Levantando o universo negociável...');
    final universo = await ctx.fundamentals.universe();
    if (universo.isErr) {
      stderr.writeln('Universo indisponível: ${universo.failureOrNull!.message}');
      return;
    }
    final tickers = universo.unwrap().take(limit).toList();
    stdout.writeln('  ${tickers.length} ativos a avaliar\n');

    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: today,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    stdout.writeln('Âncoras: CDI corrente ${pct(anchors.currentRiskFreeRate)} · '
        'IPCA ${pct(anchors.inflationCagr)} · '
        'PIB real ${pct(anchors.realEconomyGrowth)} · '
        'teto nominal ${pct(anchors.nominalEconomyGrowth)}\n');

    final linhas = <_Row>[];
    var i = 0;
    for (final ticker in tickers) {
      i++;
      if (i % 10 == 0) stdout.write('  $i/${tickers.length}\r');

      final prepared = await PrepareValuationInputs.call(
        ticker: ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
      );
      if (prepared.isErr) {
        linhas.add(_Row(
          ticker: ticker.value,
          outcome: 'insumos indisponíveis',
          detail: prepared.failureOrNull!.message,
        ));
        continue;
      }

      final inputs = prepared.unwrap();
      final result = ValuationCascade.evaluate(inputs);
      if (result.isErr) {
        linhas.add(_Row(
          ticker: ticker.value,
          outcome: _classifyRefusal(result.failureOrNull!.message),
          detail: result.failureOrNull!.message,
          sector: inputs.sectorKey,
        ));
        continue;
      }

      final v = result.unwrap();
      linhas.add(_Row(
        ticker: ticker.value,
        outcome: 'avaliado',
        lane: v.model.label,
        sector: inputs.sectorKey,
        fairValue: v.fairValue.reais,
        price: v.marketPrice.reais,
        upside: v.upside,
        warnings: v.warnings.length,
        growthOrigin: _growthOriginOf(v.warnings),
        moat: _hasMoat(v.warnings),
      ));
    }
    stdout.writeln('\n');

    _report(linhas, outputDir);
  }

  /// Classifica a recusa pela mensagem, para agrupar no relatório.
  static String _classifyRefusal(String message) {
    if (message.contains('liquidez insuficiente')) return 'Porta 0 · liquidez';
    if (message.contains('histórico curto')) return 'Porta 0 · histórico';
    if (message.contains('patrimônio líquido não positivo')) {
      return 'Porta 0 · solvência';
    }
    if (message.contains('recuperação judicial')) return 'Porta 0 · continuidade';
    if (message.contains('não havia sido divulgado')) return 'sem exercício';
    if (message.contains('não sustentam nenhuma')) return 'sem via aplicável';
    return 'outra recusa';
  }

  /// `true` quando a cascata declarou vantagem competitiva residual.
  static bool _hasMoat(List<String> warnings) =>
      warnings.any((w) => w.contains('Vantagem competitiva comprovada'));

  /// Lê a origem do crescimento nos avisos, que é onde a cascata a declara.
  static String _growthOriginOf(List<String> warnings) {
    for (final w in warnings) {
      if (w.contains('Adotada a inflação')) return 'âncora';
      if (w.contains('sem crescimento')) return 'g = 0';
    }
    return 'fundamental';
  }

  static void _report(List<_Row> linhas, String outputDir) {
    final buf = StringBuffer()
      ..writeln('# Validação fora da amostra — arquitetura de portas')
      ..writeln()
      ..writeln('Executada em ${DateTime.now().toIso8601String().split("T").first} '
          'sobre ${linhas.length} ativos do universo negociável.')
      ..writeln();

    final porSaida = <String, int>{};
    for (final l in linhas) {
      porSaida[l.outcome] = (porSaida[l.outcome] ?? 0) + 1;
    }
    buf
      ..writeln('## Distribuição de saídas')
      ..writeln()
      ..writeln('| Saída | Ativos | Fração |')
      ..writeln('|---|---:|---:|');
    final ordenado = porSaida.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in ordenado) {
      buf.writeln('| ${e.key} | ${e.value} | '
          '${pct(e.value / linhas.length, decimals: 1)} |');
    }

    final avaliados = linhas.where((l) => l.outcome == 'avaliado').toList();
    if (avaliados.isNotEmpty) {
      final porVia = <String, int>{};
      final porOrigem = <String, int>{};
      for (final l in avaliados) {
        porVia[l.lane ?? '?'] = (porVia[l.lane ?? '?'] ?? 0) + 1;
        porOrigem[l.growthOrigin ?? '?'] =
            (porOrigem[l.growthOrigin ?? '?'] ?? 0) + 1;
      }
      buf
        ..writeln()
        ..writeln('## Entre os avaliados')
        ..writeln()
        ..writeln('| Via | Ativos |')
        ..writeln('|---|---:|');
      for (final e in porVia.entries) {
        buf.writeln('| ${e.key} | ${e.value} |');
      }
      buf
        ..writeln()
        ..writeln('| Origem do crescimento | Ativos |')
        ..writeln('|---|---:|');
      for (final e in porOrigem.entries) {
        buf.writeln('| ${e.key} | ${e.value} |');
      }

      final comMoat = avaliados.where((l) => l.moat).toList();
      buf
        ..writeln()
        ..writeln('| Terminal | Ativos |')
        ..writeln('|---|---:|')
        ..writeln('| estado estacionário (ROIC_inf = WACC_inf) | '
            '${avaliados.length - comMoat.length} |')
        ..writeln('| vantagem competitiva residual | ${comMoat.length} |');
      if (comMoat.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('Com vantagem residual: '
              '${(comMoat.map((l) => l.ticker).toList()..sort()).join(", ")}.');
      }

      final upsides = [for (final l in avaliados) l.upside!]..sort();
      double q(double p) => upsides[(p * (upsides.length - 1)).round()];
      buf
        ..writeln()
        ..writeln('## Dispersão do potencial de valorização')
        ..writeln()
        ..writeln('| Percentil | Potencial |')
        ..writeln('|---|---:|')
        ..writeln('| mínimo | ${pct(upsides.first, decimals: 1)} |')
        ..writeln('| p10 | ${pct(q(0.10), decimals: 1)} |')
        ..writeln('| p25 | ${pct(q(0.25), decimals: 1)} |')
        ..writeln('| mediana | ${pct(q(0.50), decimals: 1)} |')
        ..writeln('| p75 | ${pct(q(0.75), decimals: 1)} |')
        ..writeln('| p90 | ${pct(q(0.90), decimals: 1)} |')
        ..writeln('| máximo | ${pct(upsides.last, decimals: 1)} |');
    }

    buf
      ..writeln()
      ..writeln('## Ativo a ativo')
      ..writeln()
      ..writeln('| Ativo | Setor | Saída | Via | Crescimento | Justo | Preço | Potencial |')
      ..writeln('|---|---|---|---|---|---:|---:|---:|');
    final ordenados = [...linhas]..sort((a, b) => a.ticker.compareTo(b.ticker));
    for (final l in ordenados) {
      buf.writeln('| ${l.ticker} | ${l.sector ?? "—"} | ${l.outcome} | '
          '${l.lane ?? "—"} | ${l.growthOrigin ?? "—"} | '
          '${l.fairValue == null ? "—" : num2(l.fairValue!, decimals: 2)} | '
          '${l.price == null ? "—" : num2(l.price!, decimals: 2)} | '
          '${l.upside == null ? "—" : pct(l.upside!, decimals: 1)} |');
    }

    writeReport('$outputDir/validacao_fora_da_amostra.md', buf.toString());
    writeReport(
      '$outputDir/validacao_fora_da_amostra.json',
      const JsonEncoder.withIndent('  ')
          .convert([for (final l in linhas) l.toJson()]),
    );
  }
}

class _Row {
  final String ticker;
  final String outcome;
  final String? lane;
  final String? sector;
  final String? detail;
  final String? growthOrigin;
  final double? fairValue;
  final double? price;
  final double? upside;
  final int warnings;

  /// Vantagem competitiva residual preservada na perpetuidade.
  final bool moat;

  const _Row({
    required this.ticker,
    required this.outcome,
    this.lane,
    this.sector,
    this.detail,
    this.growthOrigin,
    this.fairValue,
    this.price,
    this.upside,
    this.warnings = 0,
    this.moat = false,
  });

  Map<String, dynamic> toJson() => {
        'ticker': ticker,
        'saida': outcome,
        if (lane != null) 'via': lane,
        if (sector != null) 'setor': sector,
        if (growthOrigin != null) 'crescimento': growthOrigin,
        if (fairValue != null) 'justo': fairValue,
        if (price != null) 'preco': price,
        if (upside != null) 'potencial': upside,
        'avisos': warnings,
        'moat': moat,
        if (detail != null) 'detalhe': detail,
      };
}
