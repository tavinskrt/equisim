import 'dart:math' as math;

import '../../entities/price_series.dart';
import '../../value_objects/money.dart';
import '../metrics/returns.dart' show tradingDaysPerYear;
import '../metrics/risk_metrics.dart';

/// Faixa do valor realizado medida nas coortes da validação (itens C2 e C2b).
///
/// **Não é a banda de cenários.** A banda de cenários é a sensibilidade do
/// preço justo às premissas — crescimento e desconto deslocados — e cobriu 8%
/// do que aconteceu, contra 90% nominais. Esta é empírica: em cada coorte de
/// 2018 em diante, o preço mais os proventos reinvestidos depois de [months]
/// meses, e os quantis centrais dele. A cobertura declarada é a **fora da
/// amostra**: cada coorte medida só com as coortes cujo horizonte já tinha
/// terminado.
///
/// **Duas formas, e a segunda é a que cobre.** A primeira, da
/// [decisão 92](../../../../../docs/decisoes/092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md),
/// é a razão entre o realizado e o preço justo — [FairValueBandTable]. Na
/// montagem das coortes na base da data ela deixou de cobrir, e a forma fixada
/// antes de medir no C2b — [VolatilityBandTable] — cobre a até 2 p.p. nos dois
/// horizontes: o centro é o quanto o preço de fato converge ao justo, e a
/// largura é a volatilidade do papel.
sealed class CalibratedBandTable {
  /// Horizonte, em meses.
  final int months;

  /// Frequência nominal da faixa central, em fração — `0.8` para 80%.
  final double nominal;

  /// Observações que formam a faixa.
  final int observations;

  /// Primeira e última coorte medidas.
  final int firstCohort;
  final int lastCohort;

  /// Fração das observações de teste que caíram na faixa calibrada só com o
  /// passado delas. `null` sem coorte de teste.
  final double? outOfSampleCoverage;

  /// Observações de teste da cobertura fora da amostra.
  final int outOfSampleObservations;

  /// Declara o que as duas formas têm em comum.
  const CalibratedBandTable({
    required this.months,
    required this.nominal,
    required this.observations,
    required this.firstCohort,
    required this.lastCohort,
    required this.outOfSampleCoverage,
    required this.outOfSampleObservations,
  });

  /// `true` quando as bordas são utilizáveis.
  bool get isUsable;
}

/// A faixa em torno do preço justo: o realizado dividido por ele (decisão 92).
class FairValueBandTable extends CalibratedBandTable {
  /// Razão realizado ÷ justo na borda inferior.
  final double lowerFactor;

  /// Razão realizado ÷ justo na borda superior.
  final double upperFactor;

  /// Declara a faixa.
  const FairValueBandTable({
    required super.months,
    required super.nominal,
    required this.lowerFactor,
    required this.upperFactor,
    required super.observations,
    required super.firstCohort,
    required super.lastCohort,
    required super.outOfSampleCoverage,
    required super.outOfSampleObservations,
  });

  @override
  bool get isUsable =>
      lowerFactor.isFinite &&
      upperFactor.isFinite &&
      lowerFactor > 0 &&
      upperFactor > lowerFactor;
}

/// A faixa da convergência parcial na escala da volatilidade do papel (C2b).
///
/// Sobre o preço de hoje `P₀`, o preço justo `V` e a volatilidade `σ` do papel:
///
///     [P₀·exp(a + b·ln(V/P₀) + σ·zInferior), P₀·exp(a + b·ln(V/P₀) + σ·zSuperior)]
///
/// O `b` medido é pequeno — 0,03 em 12 meses e 0,08 em 36 —, e é isso mesmo que
/// a medição diz: o preço converge ao preço justo menos de um décimo do caminho
/// em 36 meses. A faixa é, sobretudo, o preço de hoje mais a volatilidade do
/// papel; o preço justo entra com o peso que a validação mediu, e não com o
/// peso que a decisão 26 supõe.
class VolatilityBandTable extends CalibratedBandTable {
  /// Intercepto de `log(W/P₀) = a + b·log(V/P₀)` na calibragem.
  final double a;

  /// Coeficiente do potencial no centro — o tanto que o preço convergiu.
  final double b;

  /// Quantil inferior do resíduo padronizado pela volatilidade.
  final double zLower;

  /// Quantil superior do resíduo padronizado pela volatilidade.
  final double zUpper;

  /// Declara a faixa.
  const VolatilityBandTable({
    required super.months,
    required super.nominal,
    required this.a,
    required this.b,
    required this.zLower,
    required this.zUpper,
    required super.observations,
    required super.firstCohort,
    required super.lastCohort,
    required super.outOfSampleCoverage,
    required super.outOfSampleObservations,
  });

  @override
  bool get isUsable =>
      a.isFinite && b.isFinite && zLower.isFinite && zUpper.isFinite && zUpper > zLower;
}

/// A faixa calibrada aplicada a uma avaliação.
abstract final class CalibratedBand {
  /// Pregões da volatilidade do papel (item C2b, `cobertura_banda.md` §9).
  static const int volatilityWindow = tradingDaysPerYear;

  /// Retornos abaixo dos quais o papel fica sem volatilidade.
  static const int volatilityMinimumReturns = 120;

  /// Volatilidade anualizada do papel nos últimos [volatilityWindow] pregões de
  /// [prices], ou `null` com menos de [volatilityMinimumReturns] retornos.
  ///
  /// Desvio-padrão amostral dos retornos logarítmicos diários, vezes √252 — a
  /// escala da faixa na forma fixada antes de medir, no C2b. A série é a da
  /// avaliação, que termina na data dela: a validação e o aplicativo leem a
  /// mesma janela. Par com fechamento não positivo não forma retorno.
  static double? trailingVolatility(PriceSeries prices) {
    final pts = prices.points;
    final inicio = math.max(1, pts.length - volatilityWindow);
    final retornos = <double>[
      for (var i = inicio; i < pts.length; i++)
        if (pts[i - 1].close > 0 && pts[i].close > 0)
          math.log(pts[i].close / pts[i - 1].close),
    ];
    if (retornos.length < volatilityMinimumReturns) return null;
    final v = RiskMetrics.annualizedVolatility(retornos);
    return v.isFinite ? v : null;
  }

  /// Bordas da faixa de [table], em centavos inteiros, ou `null`.
  ///
  /// Devolve `null` quando falta o que a forma precisa: preço justo não
  /// positivo, faixa inutilizável, ou — na faixa da volatilidade — preço de
  /// mercado não positivo ou papel sem volatilidade. Faixa que não se pode
  /// formar não se inventa.
  ///
  /// - [fairValue]: o preço justo da avaliação.
  /// - [table]: a faixa do pacote.
  /// - [marketPrice] e [volatility]: exigidos por [VolatilityBandTable].
  static ({Money low, Money high})? of(
    Money fairValue,
    CalibratedBandTable table, {
    Money? marketPrice,
    double? volatility,
  }) {
    if (fairValue.cents <= 0 || !table.isUsable) return null;
    switch (table) {
      case FairValueBandTable(:final lowerFactor, :final upperFactor):
        return (low: fairValue * lowerFactor, high: fairValue * upperFactor);
      case VolatilityBandTable(:final a, :final b, :final zLower, :final zUpper):
        final p0 = marketPrice?.reais;
        if (p0 == null || p0 <= 0 || volatility == null || !volatility.isFinite) {
          return null;
        }
        if (volatility <= 0) return null;
        final centro = a + b * math.log(fairValue.reais / p0);
        final low = p0 * math.exp(centro + volatility * zLower);
        final high = p0 * math.exp(centro + volatility * zUpper);
        if (!low.isFinite || !high.isFinite || low <= 0) return null;
        return (low: Money.fromReais(low), high: Money.fromReais(high));
    }
  }

  /// A faixa de [months] meses e frequência [nominal], ou `null`.
  ///
  /// A frequência é comparada a um centésimo: vem de pacote JSON, e `double`
  /// não se compara por igualdade.
  static CalibratedBandTable? select(
    List<CalibratedBandTable> tables, {
    required int months,
    required double nominal,
  }) {
    for (final t in tables) {
      if (t.months == months && (t.nominal - nominal).abs() < 0.005) return t;
    }
    return null;
  }
}

/// Formato do pacote da faixa calibrada, gravado por
/// `tool/cobertura_banda.py` e lido pelo aplicativo.
abstract final class CalibratedBandCodec {
  /// Versão do pacote da faixa em torno do justo (decisão 92).
  static const int versaoJusto = 1;

  /// Versão do pacote da faixa na escala da volatilidade (C2b).
  static const int versaoVolatilidade = 2;

  /// Lê o pacote. Faixa malformada é descartada, e não inventada.
  static List<CalibratedBandTable> decode(Map<String, dynamic> pacote) {
    final versao = pacote['versao'];
    if (versao != versaoJusto && versao != versaoVolatilidade) return const [];
    final faixas = pacote['faixas'];
    if (faixas is! List) return const [];
    final out = <CalibratedBandTable>[];
    for (final f in faixas) {
      if (f is! Map) continue;
      final meses = f['meses'];
      final nominal = f['nominal'];
      final observacoes = f['observacoes'];
      final primeira = f['primeiraCoorte'];
      final ultima = f['ultimaCoorte'];
      final fora = f['coberturaForaDaAmostra'];
      final nFora = f['observacoesForaDaAmostra'];
      if (meses is! int ||
          nominal is! num ||
          observacoes is! int ||
          primeira is! int ||
          ultima is! int ||
          (fora != null && fora is! num) ||
          nFora is! int) {
        continue;
      }
      final comum = (
        months: meses,
        nominal: nominal.toDouble(),
        observations: observacoes,
        firstCohort: primeira,
        lastCohort: ultima,
        outOfSampleCoverage: (fora as num?)?.toDouble(),
        outOfSampleObservations: nFora,
      );
      final CalibratedBandTable t;
      if (versao == versaoJusto) {
        final inferior = f['fatorInferior'];
        final superior = f['fatorSuperior'];
        if (inferior is! num || superior is! num) continue;
        t = FairValueBandTable(
          months: comum.months,
          nominal: comum.nominal,
          lowerFactor: inferior.toDouble(),
          upperFactor: superior.toDouble(),
          observations: comum.observations,
          firstCohort: comum.firstCohort,
          lastCohort: comum.lastCohort,
          outOfSampleCoverage: comum.outOfSampleCoverage,
          outOfSampleObservations: comum.outOfSampleObservations,
        );
      } else {
        final a = f['a'];
        final b = f['b'];
        final zi = f['zInferior'];
        final zs = f['zSuperior'];
        if (a is! num || b is! num || zi is! num || zs is! num) continue;
        t = VolatilityBandTable(
          months: comum.months,
          nominal: comum.nominal,
          a: a.toDouble(),
          b: b.toDouble(),
          zLower: zi.toDouble(),
          zUpper: zs.toDouble(),
          observations: comum.observations,
          firstCohort: comum.firstCohort,
          lastCohort: comum.lastCohort,
          outOfSampleCoverage: comum.outOfSampleCoverage,
          outOfSampleObservations: comum.outOfSampleObservations,
        );
      }
      if (t.isUsable) out.add(t);
    }
    return out;
  }
}
