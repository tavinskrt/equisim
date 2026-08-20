import '../../entities/financial_goal.dart';

/// Referências de mercado usadas para julgar se uma meta é plausível.
///
/// Os valores **não são constantes de código**: vêm das séries observadas, de
/// modo que os limiares se atualizam sozinhos conforme o mercado muda e a
/// mensagem ao usuário pode citar o número concreto em vez de um limite mágico.
class MarketAnchors {
  /// CAGR do CDI na janela de referência, em fração.
  final double riskFreeCagr;

  /// CAGR do índice de mercado na janela de referência, em fração.
  final double marketCagr;

  /// Janela observada, para exibição.
  final int observedYears;

  const MarketAnchors({
    required this.riskFreeCagr,
    required this.marketCagr,
    required this.observedYears,
  });

  /// Âncoras medidas em 19/08/2026 sobre janela de 10 anos:
  /// CDI 9,40% a.a. (BCB SGS 12) e Ibovespa 11,26% a.a. (^BVSP).
  ///
  /// Servem apenas de fallback quando as séries não puderem ser carregadas —
  /// o caminho normal é calcular a partir dos dados.
  static const MarketAnchors fallback2026 = MarketAnchors(
    riskFreeCagr: 0.0940,
    marketCagr: 0.1126,
    observedYears: 10,
  );
}

/// Classificação de viabilidade da meta.
enum FeasibilityLevel {
  /// Meta atingível sem risco: a renda fixa já entrega a taxa necessária.
  riskFreeSufficient,

  /// Dentro do retorno histórico do mercado.
  plausible,

  /// Acima do mercado: exige superá-lo de forma consistente.
  demanding,

  /// Fora de qualquer referência histórica: bloquear.
  unrealistic,
}

/// Veredito sobre a meta, com a mensagem já formulada.
class FeasibilityVerdict {
  final FeasibilityLevel level;
  final double requiredAnnualRate;
  final MarketAnchors anchors;
  final String message;

  const FeasibilityVerdict({
    required this.level,
    required this.requiredAnnualRate,
    required this.anchors,
    required this.message,
  });

  /// A interface deve impedir o prosseguimento.
  bool get blocks => level == FeasibilityLevel.unrealistic;

  /// A interface deve alertar, sem impedir.
  bool get warns => level == FeasibilityLevel.demanding;
}

abstract final class GoalFeasibility {
  /// Múltiplo do retorno de mercado acima do qual a meta é bloqueada.
  static const double blockingMultiple = 2.5;

  /// Múltiplo acima do qual a meta recebe alerta.
  static const double warningMultiple = 2.0;

  static FeasibilityVerdict assess({
    required RequiredReturn required,
    required MarketAnchors anchors,
    FinancialGoal? goal,
  }) {
    final annual = required.annual;
    final pct = (annual * 100).toStringAsFixed(2);
    final cdiPct = (anchors.riskFreeCagr * 100).toStringAsFixed(2);
    final marketPct = (anchors.marketCagr * 100).toStringAsFixed(2);

    if (goal != null && goal.reachableWithoutReturn) {
      return FeasibilityVerdict(
        level: FeasibilityLevel.riskFreeSufficient,
        requiredAnnualRate: annual,
        anchors: anchors,
        message: 'Os aportes sozinhos já superam a meta: não é necessária '
            'rentabilidade alguma.',
      );
    }

    if (annual < anchors.riskFreeCagr) {
      return FeasibilityVerdict(
        level: FeasibilityLevel.riskFreeSufficient,
        requiredAnnualRate: annual,
        anchors: anchors,
        message: 'A meta exige $pct% a.a., abaixo do CDI ($cdiPct% a.a. nos '
            'últimos ${anchors.observedYears} anos). Ela é atingível em renda '
            'fixa, sem correr risco de mercado.',
      );
    }

    if (annual <= anchors.marketCagr) {
      return FeasibilityVerdict(
        level: FeasibilityLevel.plausible,
        requiredAnnualRate: annual,
        anchors: anchors,
        message: 'A meta exige $pct% a.a., dentro do retorno histórico do '
            'Ibovespa ($marketPct% a.a.).',
      );
    }

    if (annual <= anchors.marketCagr * warningMultiple) {
      return FeasibilityVerdict(
        level: FeasibilityLevel.demanding,
        requiredAnnualRate: annual,
        anchors: anchors,
        message: 'A meta exige $pct% a.a., acima do retorno histórico do '
            'Ibovespa ($marketPct% a.a.). Depende de superar o mercado de '
            'forma consistente, o que é historicamente pouco frequente.',
      );
    }

    if (annual <= anchors.marketCagr * blockingMultiple) {
      return FeasibilityVerdict(
        level: FeasibilityLevel.demanding,
        requiredAnnualRate: annual,
        anchors: anchors,
        message: 'A meta exige $pct% a.a., mais que o dobro do retorno '
            'histórico do Ibovespa ($marketPct% a.a.). Revise prazo, aporte '
            'ou valor desejado.',
      );
    }

    final multiple = (annual / anchors.marketCagr).toStringAsFixed(1);
    return FeasibilityVerdict(
      level: FeasibilityLevel.unrealistic,
      requiredAnnualRate: annual,
      anchors: anchors,
      message: 'A meta exige $pct% a.a. — $multiple vezes o retorno histórico '
          'do Ibovespa ($marketPct% a.a.). Nenhuma carteira diversificada '
          'sustentou esse patamar na janela observada. Ajuste prazo, aporte '
          'mensal ou valor desejado.',
    );
  }
}
