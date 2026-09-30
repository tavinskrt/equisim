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
const arquivoSgs7 = 'data/indices/ibovespa_sgs7.json';

/// Distância máxima entre a razão mediana da sobreposição e 1.
const toleranciaDaEmenda = 0.002;

/// Série do Ibovespa que emenda o SGS 7 à fonte de mercado.
class IbovespaLongo implements BenchmarkRepository {
  IbovespaLongo._(this._pontos, this.inicioDaFonte, this.razaoNaSobreposicao);

  final List<PricePoint> _pontos;

  /// Primeiro pregão da fonte de mercado: antes dele, os pontos são do SGS.
  final DateTime inicioDaFonte;

  /// Razão mediana `fonte ÷ SGS` nos pregões comuns.
  final double razaoNaSobreposicao;

  /// Primeiro pregão da série emendada.
  DateTime get inicio => _pontos.first.date;

  /// Monta a série com a fonte de mercado [mercado].
  ///
  /// [janelaDaFonte] é a janela pedida a ela: por padrão tudo o que ela tiver;
  /// a entrada congelada só serve as janelas que gravou, e aí vai a gravada.
  static Future<IbovespaLongo> montar(
    BenchmarkRepository mercado, {
    DateRange? janelaDaFonte,
  }) async {
    final arquivo = File(arquivoSgs7);
    if (!arquivo.existsSync()) {
      throw StateError('Falta $arquivoSgs7. Rode antes: '
          'python tool/ibovespa_sgs_baixar.py');
    }
    final json = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
    final sgs = <DateTime, double>{
      for (final p in json['pontos'] as List)
        DateTime.parse((p as List)[0] as String): (p[1] as num).toDouble(),
    };
    final r = await mercado.ibovespa(
      janelaDaFonte ?? DateRange(DateTime(2000, 1, 1), DateTime(2100, 1, 1)),
    );
    if (r.isErr) {
      throw StateError('Ibovespa da fonte de mercado: ${r.failureOrNull?.message}');
    }
    final fonte = r.unwrap().points;
    if (fonte.isEmpty) throw StateError('Ibovespa da fonte de mercado vazio.');
    final inicioDaFonte = fonte.first.date;

    final razoes = <double>[
      for (final p in fonte)
        if (sgs[p.date] case final s? when s > 0 && p.close > 0) p.close / s,
    ];
    if (razoes.isEmpty) {
      throw StateError('SGS 7 e fonte de mercado sem pregão em comum: a emenda '
          'não pode ser conferida.');
    }
    final razao = Inference.median(razoes)!;
    if ((razao - 1).abs() > toleranciaDaEmenda) {
      throw StateError('A razão mediana entre a fonte de mercado e o SGS 7 é '
          '${razao.toStringAsFixed(6)}: uma das duas mudou de escala.');
    }

    final pontos = <PricePoint>[
      for (final e in sgs.entries)
        if (e.key.isBefore(inicioDaFonte))
          PricePoint(date: e.key, close: e.value),
      ...fonte,
    ]..sort((a, b) => a.date.compareTo(b.date));
    return IbovespaLongo._(pontos, inicioDaFonte, razao);
  }

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async => Ok(PriceSeries(
        ticker: Ticker.parse('IBOV11'),
        points: [
          for (final p in _pontos)
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
double premioDasAncoras(MarketAnchors a) =>
    (1 + a.marketCagr) / (1 + a.riskFreeCagr) - 1;
