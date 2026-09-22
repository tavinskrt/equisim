/// A volta entre o veredito de vantagem competitiva e a taxa de equilíbrio.
///
/// **Por que mora fora da cascata.** O veredito do moat usa a taxa terminal
/// para medir o excedente, e a taxa terminal sai de um ponto fixo que depende
/// do retorno terminal que o veredito concede. A cascata repõe a pergunta até
/// ela parar de mudar, com teto declarado (decisão 51) — e o caminho em que o
/// teto é alcançado, com o par ainda alternando, não tinha teste: fabricar um
/// ativo exatamente na fronteira do veredito é frágil, e a primeira mudança de
/// parâmetro o tiraria de lá sem aviso (lente `risco`, item D3).
///
/// Extraída como função pura de três funções, a volta é testável com um
/// veredito sintético que alterna para sempre, e a cascata continua fazendo a
/// mesma conta — o gabarito confere isso bit a bit.
library;

import 'growth_guards.dart';

/// O que a volta devolveu.
class MoatFixedPoint<V, R> {
  /// O último veredito adotado — consistente com [rates].
  final V verdict;

  /// O retorno terminal que [verdict] concede, ou `null` sem moat.
  final double? moat;

  /// As taxas resolvidas contra [moat].
  final R rates;

  /// Quantos passes a volta deu, contando o primeiro, que veio de fora.
  final int passes;

  /// `true` quando o veredito refeito deixou de mudar.
  final bool stable;

  /// `true` quando a volta parou porque o veredito seguinte pedia uma taxa que
  /// o ponto fixo não fechou.
  final bool solverFailed;

  const MoatFixedPoint._({
    required this.verdict,
    required this.moat,
    required this.rates,
    required this.passes,
    required this.stable,
    required this.solverFailed,
  });

  /// Repõe a pergunta até o veredito parar de mudar, ou até [maxPasses].
  ///
  /// - [verdict], [moat], [rates]: o par do primeiro passe, já consistente.
  /// - [reassess]: o veredito refeito contra as taxas do passe.
  /// - [moatOf]: o retorno terminal que um veredito concede — com a
  ///   imposição externa, quando houver.
  /// - [solve]: as taxas contra um retorno terminal; `null` quando o ponto
  ///   fixo não fecha.
  ///
  /// **O veredito só é adotado com a taxa dele.** Adotá-lo antes de saber se o
  /// solucionador fecha deixaria o retorno terminal de um passe casado com o
  /// caminho de taxas do anterior. Por isso, na parada, o par devolvido é
  /// sempre o último consistente entre si.
  static MoatFixedPoint<V, R> iterate<V, R>({
    required V verdict,
    required double? moat,
    required R rates,
    required V Function(R rates) reassess,
    required double? Function(V verdict) moatOf,
    required R? Function(double? moat) solve,
    int maxPasses = ValuationParameters.moatMaxPasses,
  }) {
    var passes = 1;
    var stable = false;
    var solverFailed = false;
    while (passes < maxPasses) {
      final refeito = reassess(rates);
      final novo = moatOf(refeito);
      final mudou = (novo == null) != (moat == null) ||
          (novo != null && moat != null && (novo - moat).abs() > 1e-9);
      if (!mudou) {
        stable = true;
        break;
      }
      final proximo = solve(novo);
      if (proximo == null) {
        solverFailed = true;
        break;
      }
      verdict = refeito;
      moat = novo;
      rates = proximo;
      passes++;
    }
    return MoatFixedPoint._(
      verdict: verdict,
      moat: moat,
      rates: rates,
      passes: passes,
      stable: stable,
      solverFailed: solverFailed,
    );
  }
}
