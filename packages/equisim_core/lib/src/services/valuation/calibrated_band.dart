import '../../value_objects/money.dart';

/// Faixa do valor realizado em torno do preço justo, medida nas coortes da
/// validação (item C2, decisão 92).
///
/// **Não é a banda de cenários.** A banda de cenários é a sensibilidade do
/// preço justo às premissas — crescimento e desconto deslocados — e cobriu 8%
/// do que aconteceu, contra 90% nominais. Esta é empírica: em cada coorte de
/// 2018 em diante, o preço mais os proventos reinvestidos depois de [months]
/// meses, dividido pelo preço justo que o motor dava na data, e os quantis
/// centrais dessa razão. A cobertura declarada é a **fora da amostra**: cada
/// coorte medida só com as coortes cujo horizonte já tinha terminado.
class CalibratedBandTable {
  /// Horizonte, em meses.
  final int months;

  /// Frequência nominal da faixa central, em fração — `0.8` para 80%.
  final double nominal;

  /// Razão realizado ÷ justo na borda inferior.
  final double lowerFactor;

  /// Razão realizado ÷ justo na borda superior.
  final double upperFactor;

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

  /// Declara a faixa.
  const CalibratedBandTable({
    required this.months,
    required this.nominal,
    required this.lowerFactor,
    required this.upperFactor,
    required this.observations,
    required this.firstCohort,
    required this.lastCohort,
    required this.outOfSampleCoverage,
    required this.outOfSampleObservations,
  });

  /// `true` quando as bordas são utilizáveis: finitas, positivas e em ordem.
  bool get isUsable =>
      lowerFactor.isFinite &&
      upperFactor.isFinite &&
      lowerFactor > 0 &&
      upperFactor > lowerFactor;
}

/// A faixa calibrada aplicada a um preço justo.
abstract final class CalibratedBand {
  /// Bordas da faixa em torno de [fairValue], em centavos inteiros.
  ///
  /// Devolve `null` com preço justo não positivo ou faixa inutilizável: a razão
  /// foi medida sobre preço justo positivo, e não diz nada fora dele.
  static ({Money low, Money high})? around(
    Money fairValue,
    CalibratedBandTable table,
  ) {
    if (fairValue.cents <= 0 || !table.isUsable) return null;
    return (low: fairValue * table.lowerFactor, high: fairValue * table.upperFactor);
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
  /// Versão do formato.
  static const int versao = 1;

  /// Lê o pacote. Faixa malformada é descartada, e não inventada.
  static List<CalibratedBandTable> decode(Map<String, dynamic> pacote) {
    if (pacote['versao'] != versao) return const [];
    final faixas = pacote['faixas'];
    if (faixas is! List) return const [];
    final out = <CalibratedBandTable>[];
    for (final f in faixas) {
      if (f is! Map) continue;
      final meses = f['meses'];
      final nominal = f['nominal'];
      final inferior = f['fatorInferior'];
      final superior = f['fatorSuperior'];
      final observacoes = f['observacoes'];
      final primeira = f['primeiraCoorte'];
      final ultima = f['ultimaCoorte'];
      final fora = f['coberturaForaDaAmostra'];
      final nFora = f['observacoesForaDaAmostra'];
      if (meses is! int ||
          nominal is! num ||
          inferior is! num ||
          superior is! num ||
          observacoes is! int ||
          primeira is! int ||
          ultima is! int ||
          (fora != null && fora is! num) ||
          nFora is! int) {
        continue;
      }
      final t = CalibratedBandTable(
        months: meses,
        nominal: nominal.toDouble(),
        lowerFactor: inferior.toDouble(),
        upperFactor: superior.toDouble(),
        observations: observacoes,
        firstCohort: primeira,
        lastCohort: ultima,
        outOfSampleCoverage: (fora as num?)?.toDouble(),
        outOfSampleObservations: nFora,
      );
      if (t.isUsable) out.add(t);
    }
    return out;
  }
}
