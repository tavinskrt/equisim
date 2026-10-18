// O Ibovespa diário longo: o SGS 7 do Banco Central antes da fonte de mercado,
// e a fonte de mercado dali em diante.
//
// **Por que existe.** A brapi entrega o índice dos últimos dez anos (desde
// 23/09/2016 na consulta de 28/09/2026). Um prêmio de risco histórico medido
// numa coorte de 2018 com janela de dez anos pede o índice desde 2008, e o
// SGS 7 tem o fechamento diário até 30/09/2019, quando foi descontinuado.
//
// **A emenda.** Vale a fonte de mercado a partir do primeiro pregão dela, e o
// SGS antes. Nos 744 pregões comuns de 2016 a 2019 a razão mediana entre as
// duas é 1,000000; três dias diferem mais de 0,2%, um deles um erro de dígito
// no SGS (61.108 contra 64.108 em 21/10/2016). A emenda confere a razão na
// sobreposição e recusa se ela se afastar de 1 — sinal de que uma das duas
// mudou de escala.
//
// Só serve a medições: o aplicativo não tem o SGS 7, e o beta das coortes
// continua lendo a série da fonte de mercado.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

/// O arquivo gravado por `tool/ibovespa_sgs_baixar.py`.
const sgs7File = 'data/indices/ibovespa_sgs7.json';

/// Distância máxima entre a razão mediana da sobreposição e 1.
const spliceTolerance = 0.002;

/// Série do Ibovespa que emenda o SGS 7 à fonte de mercado.
class LongIbovespa implements BenchmarkRepository {
  LongIbovespa._(this._points, this.sourceStart, this.overlapRatio);

  final List<PricePoint> _points;

  /// Primeiro pregão da fonte de mercado: antes dele, os pontos são do SGS.
  final DateTime sourceStart;

  /// Razão mediana `fonte ÷ SGS` nos pregões comuns.
  final double overlapRatio;

  /// Monta a série com a fonte de mercado [market].
  ///
  /// [sourceWindow] é a janela pedida a ela: por padrão tudo o que ela tiver;
  /// a entrada congelada só serve as janelas que gravou, e aí vai a gravada.
  static Future<LongIbovespa> build(
    BenchmarkRepository market, {
    DateRange? sourceWindow,
  }) async {
    final file = File(sgs7File);
    if (!file.existsSync()) {
      throw StateError('Falta $sgs7File. Rode antes: '
          'python tool/ibovespa_sgs_baixar.py');
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final sgs = <DateTime, double>{
      for (final p in json['pontos'] as List)
        DateTime.parse((p as List)[0] as String): (p[1] as num).toDouble(),
    };
    final r = await market.ibovespa(
      sourceWindow ?? DateRange(DateTime(2000, 1, 1), DateTime(2100, 1, 1)),
    );
    if (r.isErr) {
      throw StateError('Ibovespa da fonte de mercado: ${r.failureOrNull?.message}');
    }
    final source = r.unwrap().points;
    if (source.isEmpty) throw StateError('Ibovespa da fonte de mercado vazio.');
    final sourceStart = source.first.date;

    final ratios = <double>[
      for (final p in source)
        if (sgs[p.date] case final s? when s > 0 && p.close > 0) p.close / s,
    ];
    if (ratios.isEmpty) {
      throw StateError('SGS 7 e fonte de mercado sem pregão em comum: a emenda '
          'não pode ser conferida.');
    }
    final ratio = Inference.median(ratios)!;
    if ((ratio - 1).abs() > spliceTolerance) {
      throw StateError('A razão mediana entre a fonte de mercado e o SGS 7 é '
          '${ratio.toStringAsFixed(6)}: uma das duas mudou de escala.');
    }

    final points = <PricePoint>[
      for (final e in sgs.entries)
        if (e.key.isBefore(sourceStart))
          PricePoint(date: e.key, close: e.value),
      ...source,
    ]..sort((a, b) => a.date.compareTo(b.date));
    return LongIbovespa._(points, sourceStart, ratio);
  }

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async => Ok(PriceSeries(
        ticker: Ticker.parse('IBOV11'),
        points: [
          for (final p in _points)
            if (range.contains(p.date)) p,
        ],
      ));
}

/// O prêmio de risco histórico que as âncoras de mercado implicam.
///
/// `(1 + CAGR do Ibovespa) ÷ (1 + CAGR do CDI) − 1`, os dois sobre a mesma
/// janela de [ResolveMarketAnchors] — o índice entre as médias de 63 pregões
/// das pontas, e o CDI composto. É Fisher, e não subtração: o prêmio é razão de
/// fatores brutos, como na medição da decisão 116.
double premiumOfAnchors(MarketAnchors a) =>
    (1 + a.marketCagr) / (1 + a.riskFreeCagr) - 1;
