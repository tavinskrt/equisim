import 'dart:math' as math;

import '../../entities/portfolio.dart';
import '../../entities/valuation.dart';
import '../../value_objects/ticker.dart';
import '../valuation/cost_of_capital.dart';
import '../valuation/inference.dart';

/// Retorno anual esperado de um ativo, decomposto.
class ExpectedAssetReturn {
  final Ticker ticker;

  /// Valorização total até o preço justo, sem prazo, em fração.
  final double upside;

  /// Parcela anualizada da convergência de preço.
  final double priceConvergence;

  const ExpectedAssetReturn({
    required this.ticker,
    required this.upside,
    required this.priceConvergence,
  });

  /// Retorno esperado ao ano.
  ///
  /// É a convergência de preço e nada mais: o modelo não distribui provento
  /// (ver `docs/decisoes/023-remocao-de-proventos.md`), então somar um *yield*
  /// aqui embutiria um retorno que nenhuma outra tela do trabalho apura.
  double get annual => priceConvergence;
}

/// Converte *upside* de valuation em taxa anual comparável à meta.
///
/// **Problema de unidade que isto resolve**: o upside do DCF é uma valorização
/// *total* (ex.: +40%) sem prazo definido, enquanto a rentabilidade requerida é
/// uma taxa *por período* (ex.: 12% a.a.). Comparar os dois diretamente não
/// significa nada — é preciso declarar em quanto tempo o preço converge para o
/// valor justo.
///
///     r_esperado = (1 + upside)^(1/H) − 1
///
/// **O retorno é só de preço.** O trabalho não modela provento, e a estimativa
/// é portanto conservadora: um acionista que receba dividendo obtém mais que
/// isto. Ver `docs/decisoes/023-remocao-de-proventos.md`.
abstract final class ExpectedReturn {
  /// Horizonte de convergência padrão, em meses.
  ///
  /// **36 meses, por decisão 25.** Os 12 meses anteriores acompanhavam a
  /// convenção de mercado para preço-alvo, mas tornavam a anualização a
  /// identidade — `(1 + u)^(1/1) − 1 = u` —, de modo que o *upside* bruto virava
  /// retorno esperado sem nenhuma transformação. A PETR4, com +209,2% de
  /// *upside*, entrava na média ponderada da carteira como 209,2% ao ano.
  ///
  /// É parâmetro declarado, não constante escondida: deve aparecer junto do
  /// resultado.
  static const int defaultHorizonMonths = 36;

  /// Anualiza um upside total sobre o horizonte [horizonMonths].
  static double annualizedFromUpside(
    double upside, {
    int horizonMonths = defaultHorizonMonths,
  }) {
    if (horizonMonths <= 0) return 0.0;
    final growth = 1.0 + upside;
    if (growth <= 0) return -1.0;
    final years = horizonMonths / 12.0;
    return math.pow(growth, 1.0 / years).toDouble() - 1.0;
  }

  /// Retorno esperado de um ativo.
  static ExpectedAssetReturn forAsset({
    required Ticker ticker,
    required double upside,
    int horizonMonths = defaultHorizonMonths,
  }) =>
      ExpectedAssetReturn(
        ticker: ticker,
        upside: upside,
        priceConvergence:
            annualizedFromUpside(upside, horizonMonths: horizonMonths),
      );

  /// Retorno esperado da carteira: média dos ativos ponderada pelos pesos.
  ///
  /// Ativos sem valuation disponível são ignorados, e os pesos remanescentes
  /// reescalados — reportar o peso faltante é responsabilidade da interface.
  static double forPortfolio({
    required Portfolio portfolio,
    required Map<Ticker, ValuationResult> valuations,
    int horizonMonths = defaultHorizonMonths,
  }) {
    var weighted = 0.0;
    var covered = 0.0;

    for (final entry in portfolio.entries.values) {
      final valuation = valuations[entry.ticker];
      if (valuation == null) continue;
      final expected = forAsset(
        ticker: entry.ticker,
        upside: valuation.upside,
        horizonMonths: horizonMonths,
      );
      weighted += entry.weight.value * expected.annual;
      covered += entry.weight.value;
    }

    if (covered <= 0) return 0.0;
    return weighted / covered;
  }

  // ------------------------------------------ Retorno esperado transversal --

  /// Teto do escore, em desvios robustos.
  ///
  /// **Confina a cauda, não a ordenação.** A distribuição de potencial dos 120
  /// avaliados vai de −95,5% a +477,3%: sem teto, um único ativo de cauda
  /// direita levaria o escore a mais de dez desvios e sozinho definiria o
  /// retorno esperado da carteira inteira. Com dois desvios e prêmio de 5,5%, a
  /// banda de retorno esperado é de CDI ± 11 p.p. — o suficiente para separar o
  /// muito descontado do muito esticado sem que a ponta decida a conta.
  static const double defaultZCap = 2.0;

  /// Retorno esperado transversal de um conjunto de ativos avaliados.
  ///
  /// **Por que não é a anualização do potencial.** `(1 + u)^(1/H) − 1` é uma
  /// afirmação de nível: com potencial mediano de −39,4% no universo elegível,
  /// ela devolve −15,4% ao ano para o ativo *mediano* — e num otimizador de
  /// média-variância isso não ordena mal, ele simplesmente não aloca. O nível do
  /// potencial carrega tudo o que a estrutura a termo e o terminal neutro
  /// impõem de conservadorismo ao custo de capital brasileiro; a **ordenação**
  /// entre ativos, não.
  ///
  /// Este estimador usa só a ordenação, **em torno do custo de capital próprio
  /// de cada ativo**:
  ///
  ///     E[R_i] = Ke_i + z_i · prêmio,    z_i = (u_i − mediana(u)) / MAD*(u)
  ///
  /// O ativo mediano da seção recebe o **próprio `Ke`** — `Rf + β_i·prêmio`,
  /// que é o retorno esperado incondicional dele —; quem está descontado em
  /// relação aos pares recebe mais, e quem está esticado recebe menos. **O
  /// preço justo do ativo individual não é tocado** — ele continua saindo do
  /// DCF, e é ele que a tela de avaliação mostra. Esta é a projeção de
  /// otimização, e só ela.
  ///
  /// **A âncora era o CDI, e isso subtraía o prêmio de risco inteiro**
  /// (decisão 58). Com ela, uma carteira de ações centrada na seção esperava
  /// exatamente a renda fixa: o prêmio de mercado aparecia só como dispersão em
  /// torno do CDI, nunca como nível. É afirmação que nenhuma teoria de
  /// precificação sustenta, e a lente `metodo` a apontou em oito rodadas.
  ///
  /// Sem `Ke` disponível para um ativo, a âncora dele recua para [spotRiskFree]
  /// — o comportamento anterior, e o resultado declara em
  /// [CrossSectionalReturn.anchoredOnCostOfEquity].
  ///
  /// Escala robusta e não desvio-padrão pelo mesmo motivo da Guarda 3: com
  /// ponto de ruptura de 50%, a cauda de potencial não infla o denominador e
  /// achata todo mundo no centro.
  ///
  /// - [upsides]: potenciais dos ativos a estimar.
  /// - [costOfEquity]: custo do capital próprio de cada ativo. É a âncora.
  /// - [spotRiskFree]: CDI corrente, em fração ao ano. Âncora de recuo, para
  ///   o ativo cujo `Ke` não veio.
  /// - [riskPremium]: prêmio de risco de mercado. O padrão é o mesmo parâmetro
  ///   do CAPM que desconta o fluxo, para que as duas pontas do trabalho não
  ///   adotem prêmios diferentes.
  /// - [reference]: seção transversal que define mediana e escala. **Quanto mais
  ///   larga, mais significativo o escore** — medir uma carteira de cinco ativos
  ///   contra ela mesma centra a carteira no CDI por construção. Omitida, cai
  ///   para os próprios [upsides], e o resultado declara isso em
  ///   [CrossSectionalReturn.referenceSize].
  /// - [zCap]: teto do escore em desvios robustos.
  static Map<Ticker, CrossSectionalReturn> crossSection({
    required Map<Ticker, double> upsides,
    required double spotRiskFree,
    Map<Ticker, double>? costOfEquity,
    double riskPremium = CapmInputs.defaultMarketPremium,
    Iterable<double>? reference,
    double zCap = defaultZCap,
  }) {
    final secao = [...(reference ?? upsides.values)];
    final centro = Inference.median(secao);
    final escala = Inference.scaledMad(secao);

    final saida = <Ticker, CrossSectionalReturn>{};
    for (final e in upsides.entries) {
      // Sem escala estimável — seção curta demais ou colapsada num ponto — não
      // há distância a medir, e todo mundo recebe a âncora. É a leitura neutra:
      // afirmar ordenação onde a seção não a sustenta seria inventar prêmio.
      final z = (centro == null || escala == null)
          ? 0.0
          : ((e.value - centro) / escala).clamp(-zCap, zCap);
      // **A bandeira sai de haver `Ke`, e não de comparar as duas âncoras.**
      // Um `Ke` numericamente igual ao CDI é possível — beta zero, ou
      // coincidência de arredondamento — e compará-los declararia recuo onde
      // não houve.
      final ke = costOfEquity?[e.key];
      final temKe = ke != null && ke.isFinite && ke > 0;
      final ancora = temKe ? ke : spotRiskFree;
      final bruto = ancora + z * riskPremium;
      saida[e.key] = CrossSectionalReturn(
        ticker: e.key,
        upside: e.value,
        z: z,
        expected: bruto < 0 ? 0.0 : bruto,
        floored: bruto < 0,
        referenceSize: secao.length,
        anchoredOnCostOfEquity: temKe,
      );
    }
    return saida;
  }

  /// Retorno esperado da carteira pelo estimador transversal.
  ///
  /// Média dos ativos ponderada pelos pesos, com os pesos sem avaliação
  /// descartados e os remanescentes reescalados — a mesma convenção de
  /// [forPortfolio], para que a cobertura continue significando o mesmo.
  ///
  /// - [reference]: seção transversal de referência. Ver [crossSection].
  static double forPortfolioCrossSectional({
    required Portfolio portfolio,
    required Map<Ticker, ValuationResult> valuations,
    required double spotRiskFree,
    double riskPremium = CapmInputs.defaultMarketPremium,
    Iterable<double>? reference,
    double zCap = defaultZCap,
  }) {
    final upsides = <Ticker, double>{};
    for (final entry in portfolio.entries.values) {
      final v = valuations[entry.ticker];
      if (v != null) upsides[entry.ticker] = v.upside;
    }
    if (upsides.isEmpty) return 0.0;

    final estimado = crossSection(
      upsides: upsides,
      spotRiskFree: spotRiskFree,
      costOfEquity: {
        for (final e in valuations.entries)
          if (e.value.diagnostics != null)
            e.key: e.value.diagnostics!.costOfEquity,
      },
      riskPremium: riskPremium,
      reference: reference ?? [for (final v in valuations.values) v.upside],
      zCap: zCap,
    );

    var weighted = 0.0;
    var covered = 0.0;
    for (final entry in portfolio.entries.values) {
      final r = estimado[entry.ticker];
      if (r == null) continue;
      weighted += entry.weight.value * r.expected;
      covered += entry.weight.value;
    }
    return covered <= 0 ? 0.0 : weighted / covered;
  }

  /// Fração do peso da carteira que possui valuation disponível.
  static double coverage({
    required Portfolio portfolio,
    required Map<Ticker, ValuationResult> valuations,
  }) {
    var covered = 0.0;
    for (final entry in portfolio.entries.values) {
      if (valuations.containsKey(entry.ticker)) {
        covered += entry.weight.value;
      }
    }
    return covered;
  }
}

/// Retorno esperado de um ativo pelo estimador transversal.
class CrossSectionalReturn {
  final Ticker ticker;

  /// Potencial de valorização que entrou na conta, em fração.
  final double upside;

  /// Escore robusto do potencial contra a seção, já confinado ao teto.
  final double z;

  /// Retorno esperado ao ano, em fração.
  final double expected;

  /// `true` quando o piso de zero foi aplicado.
  ///
  /// Só acontece se `z_cap · prêmio > CDI` — com o CDI brasileiro na casa de
  /// dois dígitos e prêmio de 5,5%, não acontece. Fica declarado porque, se
  /// acontecer, a ordenação entre os ativos do piso se perde, e quem lê o
  /// resultado precisa saber disso em vez de deduzir de empates suspeitos.
  final bool floored;

  /// Tamanho da seção transversal que definiu mediana e escala.
  ///
  /// Faz parte do resultado: um escore medido contra cinco ativos e outro
  /// contra cento e vinte não sustentam a mesma conclusão.
  final int referenceSize;

  /// `true` quando a âncora foi o custo de capital próprio do ativo, e não o
  /// CDI de recuo.
  ///
  /// Sai porque a diferença entre as duas é o prêmio de risco inteiro, e o
  /// leitor precisa poder distinguir um número do outro (decisão 58).
  final bool anchoredOnCostOfEquity;

  const CrossSectionalReturn({
    required this.ticker,
    required this.upside,
    required this.z,
    required this.expected,
    required this.floored,
    required this.referenceSize,
    this.anchoredOnCostOfEquity = false,
  });
}
