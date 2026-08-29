import '../../entities/financial_goal.dart';
import '../valuation/growth_estimator.dart';

/// Referências de mercado usadas para julgar se uma meta é plausível.
///
/// Os valores **não são constantes de código**: vêm das séries observadas, de
/// modo que os limiares se atualizam sozinhos conforme o mercado muda e a
/// mensagem ao usuário pode citar o número concreto em vez de um limite mágico.
class MarketAnchors {
  /// CAGR do CDI na janela de referência, em fração.
  ///
  /// É uma média **histórica**, e serve para julgar a meta: "a rentabilidade
  /// exigida está acima ou abaixo do que a renda fixa entregou na década?".
  /// Não serve como taxa de desconto — para isso existe [currentRiskFreeRate].
  final double riskFreeCagr;

  /// CDI **corrente** anualizado, em fração.
  ///
  /// Esta é a taxa livre de risco do CAPM. Desconto olha para frente: o custo
  /// de oportunidade de hoje é o juro de hoje, não a média da década. Medido
  /// em 21/08/2026 a distância era de 4,7 p.p. — CDI corrente a 14,15% a.a.
  /// contra 9,40% de média decenal —, e usar a média no desconto inflava toda
  /// perpetuidade, com efeito violento nos ativos de valor terminal alto.
  final double currentRiskFreeRate;

  /// CAGR do índice de mercado na janela de referência, em fração.
  final double marketCagr;

  /// Inflação anual observada na janela (IPCA, BCB SGS 433), em fração.
  ///
  /// Existe para manter **real e nominal na mesma unidade**. A taxa de
  /// desconto do valuation é nominal — sai do CDI —, então o crescimento na
  /// perpetuidade também precisa ser nominal. Descontar fluxo a 16% a.a. e
  /// fazê-lo crescer a 3% *reais* infla o spread da perpetuidade e subavalia
  /// toda empresa, de forma silenciosa.
  final double inflationCagr;

  /// Janela observada, para exibição.
  final int observedYears;

  /// Declara as âncoras.
  ///
  /// - [riskFreeCagr]: CAGR histórico do CDI na janela.
  /// - [marketCagr]: CAGR histórico do índice na janela.
  /// - [observedYears]: extensão da janela, para exibição.
  /// - [inflationCagr]: IPCA anualizado. Padrão 4,5%.
  /// - [currentRiskFreeRate]: CDI corrente. **Omiti-lo faz cair para
  ///   [riskFreeCagr]**, ou seja, o desconto passa a usar a média da década —
  ///   o comportamento antigo, preservado para não quebrar quem constrói as
  ///   âncoras à mão. A aplicação informa o valor corrente.
  const MarketAnchors({
    required this.riskFreeCagr,
    required this.marketCagr,
    required this.observedYears,
    this.inflationCagr = 0.045,
    double? currentRiskFreeRate,
  }) : currentRiskFreeRate = currentRiskFreeRate ?? riskFreeCagr;

  /// Âncoras medidas em 19/08/2026 sobre janela de 10 anos:
  /// CDI 9,40% a.a. (BCB SGS 12), Ibovespa 11,26% a.a. (^BVSP) e IPCA
  /// 4,50% a.a. (BCB SGS 433).
  ///
  /// Servem apenas de fallback quando as séries não puderem ser carregadas —
  /// o caminho normal é calcular a partir dos dados.
  static const MarketAnchors fallback2026 = MarketAnchors(
    riskFreeCagr: 0.0940,
    marketCagr: 0.1126,
    inflationCagr: 0.0450,
    currentRiskFreeRate: 0.1415,
    observedYears: 10,
  );

  /// Crescimento nominal de longo prazo da economia.
  ///
  /// `(1 + real) × (1 + inflação) − 1` — o teto correto para a perpetuidade
  /// num fluxo descontado a taxa nominal.
  double get nominalEconomyGrowth =>
      (1 + GrowthEstimator.realEconomyGrowth) * (1 + inflationCagr) - 1;
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
  /// Classificação da meta. É o que [blocks] e [warns] traduzem para a
  /// interface.
  final FeasibilityLevel level;

  /// Taxa anual exigida pela meta, em fração.
  final double requiredAnnualRate;

  /// Âncoras contra as quais a meta foi julgada. Viajam junto do veredito para
  /// que a interface cite os números concretos sem consultá-los de novo.
  final MarketAnchors anchors;

  /// Mensagem pronta para exibição, em português, já citando os percentuais.
  final String message;

  /// Agrupa o veredito já formulado.
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

/// Julga se uma meta patrimonial é plausível diante do que o mercado entregou.
///
/// Os limiares são **múltiplos do CAGR observado do Ibovespa**, não constantes
/// absolutas: uma exigência de 15% a.a. é modesta numa década de juro alto e
/// agressiva numa de juro baixo, e um limite fixo trataria as duas igual.
abstract final class GoalFeasibility {
  /// Múltiplo do retorno de mercado acima do qual a meta é bloqueada.
  static const double blockingMultiple = 2.5;

  /// Múltiplo acima do qual a meta recebe alerta.
  static const double warningMultiple = 2.0;

  /// Classifica a meta e formula a mensagem correspondente.
  ///
  /// - [required]: taxa já resolvida por `RequiredReturnSolver`.
  /// - [anchors]: referências de mercado da janela observada.
  /// - [goal]: plano original. Opcional — quando informado, permite detectar o
  ///   caso em que os aportes sozinhos já superam a meta, que antecede
  ///   qualquer comparação com o mercado.
  ///
  /// A escala é: abaixo do CDI é [FeasibilityLevel.riskFreeSufficient]; até o
  /// CAGR do mercado é [FeasibilityLevel.plausible]; até
  /// [blockingMultiple] vezes esse CAGR é [FeasibilityLevel.demanding], em duas
  /// faixas com mensagens distintas; acima disso é
  /// [FeasibilityLevel.unrealistic].
  ///
  /// Nunca falha e nunca lança — toda meta recebe um veredito.
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
