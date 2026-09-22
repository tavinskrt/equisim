import '../../entities/fundamentals.dart';
import '../../time/point_in_time_view.dart';
import '../valuation/inference.dart';

/// A ordenação que decide o prêmio do retorno esperado (item B1).
///
/// O plano do motor de referência mediu, na §0, que o potencial do DCF não
/// ordena melhor que o book-to-market e, condicionado a ele, não acrescenta. A
/// saída escolhida para o B1 é medir lado a lado e implantar um modelo
/// transversal declarado enquanto o DCF é perseguido: **o preço justo continua
/// sendo a entrega da tela de avaliação, e o prêmio do retorno esperado sai de
/// uma ordenação medida** — ver `docs/validacao/ordenacao_lado_a_lado.md`.
enum TransversalOrdering {
  /// Média dos escores robustos do potencial, do book-to-market e do lucro
  /// sobre o preço — o modelo transversal declarado, com o potencial como um
  /// insumo entre outros.
  composite,

  /// O valor patrimonial sobre o valor de mercado.
  bookToMarket,

  /// O potencial do valuation.
  potential;
}

/// Os sinais de um ativo que a ordenação transversal lê.
class TransversalSignals {
  /// Potencial do valuation, `justo ÷ preço − 1`.
  final double? potential;

  /// Patrimônio líquido do último exercício publicado sobre o valor de mercado.
  final double? bookToMarket;

  /// Lucro líquido do último exercício publicado sobre o valor de mercado.
  final double? earningsYield;

  /// Declara os sinais; o ausente é `null`.
  const TransversalSignals({
    this.potential,
    this.bookToMarket,
    this.earningsYield,
  });

  /// Os sinais do último exercício publicado até [asOf] em [history], e o
  /// [potential] da avaliação.
  ///
  /// A data entra por parâmetro, e só na falta dela vale a de hoje: o núcleo é
  /// determinístico, e a mesma série tem de dar os mesmos sinais amanhã.
  factory TransversalSignals.fromHistory(
    List<FundamentalsSnapshot> history, {
    DateTime? asOf,
    double? potential,
  }) {
    final hoje = asOf ?? DateTime.now();
    final publicados = PointInTimeView(hoje).published(history);
    return TransversalSignals.of(
      publicados.isEmpty ? null : publicados.last,
      potential: potential,
    );
  }

  /// Os sinais do último exercício publicado, e o [potential] da avaliação.
  ///
  /// `PL ÷ VM` e `lucro ÷ VM` do exercício, sem valor de mercado positivo não há
  /// nenhum dos dois — a mesma conta que as coortes da validação fazem, para que
  /// o aplicativo ordene pelo que foi medido.
  factory TransversalSignals.of(FundamentalsSnapshot? latest, {double? potential}) {
    final vm = latest?.marketCap;
    final temVm = vm != null && vm.isFinite && vm > 0;
    final pl = latest?.equityBookValue;
    final lucro = latest?.netIncome;
    return TransversalSignals(
      potential: potential,
      bookToMarket: temVm && pl != null && pl.isFinite ? pl / vm : null,
      earningsYield: temVm && lucro != null && lucro.isFinite ? lucro / vm : null,
    );
  }
}

/// Escores da ordenação transversal, em desvios robustos confinados.
///
/// **A escala é a do retorno esperado desde a decisão 58**: `(x − mediana) ÷
/// MAD`, confinado a ±[cap], para que a cauda de um sinal — o potencial chega a
/// +477% — não decida sozinha. O composto é a média dos escores dos sinais que o
/// ativo tem, com pesos iguais: não há fundamento a priori para outros, e pesos
/// medidos no mesmo backtest que os julga seriam ajuste ao teste.
abstract final class TransversalScore {
  /// Teto do escore, em desvios robustos.
  static const double cap = 2.0;

  /// Escore robusto de cada valor contra a seção formada pelos próprios
  /// valores. Seção sem escala estimável — curta ou colapsada — dá zero a todos,
  /// que é a leitura neutra.
  static Map<K, double> robustZ<K>(Map<K, double> values) {
    final finitos = {
      for (final e in values.entries)
        if (e.value.isFinite) e.key: e.value,
    };
    final secao = finitos.values.toList();
    final centro = Inference.median(secao);
    final escala = Inference.scaledMad(secao);
    // `Inference.scaledMad` já devolve `null` com MAD zero; a guarda repete a
    // condição aqui para que a divisão abaixo seja segura por inspeção local.
    final semEscala = centro == null || escala == null || escala <= 0;
    return {
      for (final e in finitos.entries)
        e.key: semEscala
            ? 0.0
            : ((e.value - centro) / escala).clamp(-cap, cap).toDouble(),
    };
  }

  /// O escore de cada ativo pela [ordering], contra a seção dos próprios
  /// [signals].
  ///
  /// Ativo sem o sinal que a ordenação pede fica fora do mapa; no composto, o
  /// sinal ausente sai da média, e o ativo sem nenhum dos três fica fora.
  static Map<K, double> scores<K>(
    Map<K, TransversalSignals> signals,
    TransversalOrdering ordering,
  ) {
    Map<K, double> de(double? Function(TransversalSignals) campo) => {
          for (final e in signals.entries)
            if (campo(e.value) case final v?) e.key: v,
        };
    final zPotencial = robustZ(de((s) => s.potential));
    final zBm = robustZ(de((s) => s.bookToMarket));
    switch (ordering) {
      case TransversalOrdering.potential:
        return zPotencial;
      case TransversalOrdering.bookToMarket:
        return zBm;
      case TransversalOrdering.composite:
        final zEy = robustZ(de((s) => s.earningsYield));
        final out = <K, double>{};
        for (final k in signals.keys) {
          final zs = [zPotencial[k], zBm[k], zEy[k]].nonNulls.toList();
          if (zs.isEmpty) continue;
          out[k] = zs.reduce((a, b) => a + b) / zs.length;
        }
        return out;
    }
  }
}
