/// O cálculo do usuário: a conta do motor refeita com os números de quem
/// discorda dele (decisão 147).
library;

import '../../failures/failure.dart';
import '../../failures/result.dart';
import 'capital_base.dart';
import 'dcf.dart';

/// Uma premissa que o usuário pode digitar.
///
/// O nome de cada valor é o que vai em [InvalidInput.field] quando a conta
/// recusa a premissa, para a tela destacar o campo certo.
enum ManualField {
  /// Lucro do ano de partida, em reais: `NOPAT` na via da firma, lucro
  /// líquido na do acionista.
  baseProfit,

  /// Crescimento do lucro no primeiro ano projetado.
  growth,

  /// Taxa que desconta o fluxo do acionista no primeiro ano — o custo do
  /// capital próprio, nas duas vias.
  discountRate,

  /// Crescimento na perpetuidade.
  perpetualGrowth,

  /// Retorno sobre o capital no primeiro ano: `ROIC` na via da firma, `ROE` na
  /// do acionista.
  returnOnCapital,

  /// Parcela do lucro reinvestida, quando ela é fixa.
  retention,

  /// Retorno do capital novo na perpetuidade.
  terminalReturn,
}

/// Como a taxa de desconto se espalha pelos anos.
enum ManualRatePath {
  /// O caminho do motor — a curva de juros, e na via da firma a estrutura de
  /// capital de cada ano —, deslocado em paralelo pela diferença entre a taxa
  /// digitada e a do primeiro ano do motor.
  engine,

  /// Uma taxa só, do primeiro ano à perpetuidade.
  constant,
}

/// Como o crescimento evolui nos anos explícitos.
enum ManualGrowthPath {
  /// Do crescimento digitado ao da perpetuidade, em linha reta até o último
  /// ano explícito. É o que o motor faz.
  decays,

  /// O mesmo crescimento em todos os anos explícitos.
  constant,
}

/// De onde sai a parcela do lucro reinvestida.
enum ManualReinvestment {
  /// `b_t = g_t ÷ retorno_t`, com o retorno convergindo à taxa de desconto até
  /// o último ano explícito. É o que o motor faz.
  byReturn,

  /// Uma parcela fixa do lucro, em todos os anos e na perpetuidade.
  fixedFraction,
}

/// As premissas de um cálculo do usuário (decisão 147).
///
/// Taxas em fração ao ano. **O lucro de partida é em reais nas duas vias**: a
/// via do acionista desconta lucro por papel, e é [ManualValuation] quem
/// converte, porque "lucro líquido do ano" é o número que se lê no balanço.
class ManualPremises {
  /// Lucro do ano de partida, em reais. Ver [ManualField.baseProfit].
  final double baseProfit;

  /// Crescimento do primeiro ano projetado.
  final double growth;

  /// Como o crescimento evolui depois do primeiro ano.
  final ManualGrowthPath growthPath;

  /// Taxa de desconto do primeiro ano.
  final double discountRate;

  /// Como a taxa se espalha pelos anos.
  final ManualRatePath ratePath;

  /// Crescimento na perpetuidade.
  final double perpetualGrowth;

  /// De onde sai o reinvestimento.
  final ManualReinvestment reinvestment;

  /// Retorno sobre o capital do primeiro ano, usado sob
  /// [ManualReinvestment.byReturn].
  final double returnOnCapital;

  /// Parcela reinvestida, usada sob [ManualReinvestment.fixedFraction].
  final double retention;

  /// Retorno do capital novo na perpetuidade, ou `null` para igual à taxa de
  /// desconto — o estado estacionário, em que crescer não cria valor.
  final double? terminalReturn;

  /// Declara as premissas. Não valida: quem recusa é
  /// [ManualValuation.evaluate], com o campo nomeado.
  const ManualPremises({
    required this.baseProfit,
    required this.growth,
    this.growthPath = ManualGrowthPath.decays,
    required this.discountRate,
    this.ratePath = ManualRatePath.engine,
    required this.perpetualGrowth,
    this.reinvestment = ManualReinvestment.byReturn,
    required this.returnOnCapital,
    required this.retention,
    this.terminalReturn,
  });

  static const Object _keep = Object();

  /// Cópia com os campos informados trocados. [terminalReturn] aceita `null`
  /// explícito — é como se volta ao estado estacionário.
  ManualPremises copyWith({
    double? baseProfit,
    double? growth,
    ManualGrowthPath? growthPath,
    double? discountRate,
    ManualRatePath? ratePath,
    double? perpetualGrowth,
    ManualReinvestment? reinvestment,
    double? returnOnCapital,
    double? retention,
    Object? terminalReturn = _keep,
  }) => ManualPremises(
    baseProfit: baseProfit ?? this.baseProfit,
    growth: growth ?? this.growth,
    growthPath: growthPath ?? this.growthPath,
    discountRate: discountRate ?? this.discountRate,
    ratePath: ratePath ?? this.ratePath,
    perpetualGrowth: perpetualGrowth ?? this.perpetualGrowth,
    reinvestment: reinvestment ?? this.reinvestment,
    returnOnCapital: returnOnCapital ?? this.returnOnCapital,
    retention: retention ?? this.retention,
    terminalReturn: identical(terminalReturn, _keep)
        ? this.terminalReturn
        : terminalReturn as double?,
  );

  /// O valor de um campo, ou `null` para o retorno terminal no estado
  /// estacionário.
  double? valueOf(ManualField field) => switch (field) {
    ManualField.baseProfit => baseProfit,
    ManualField.growth => growth,
    ManualField.discountRate => discountRate,
    ManualField.perpetualGrowth => perpetualGrowth,
    ManualField.returnOnCapital => returnOnCapital,
    ManualField.retention => retention,
    ManualField.terminalReturn => terminalReturn,
  };

  /// Cópia com um campo trocado.
  ManualPremises withValue(ManualField field, double value) => switch (field) {
    ManualField.baseProfit => copyWith(baseProfit: value),
    ManualField.growth => copyWith(growth: value),
    ManualField.discountRate => copyWith(discountRate: value),
    ManualField.perpetualGrowth => copyWith(perpetualGrowth: value),
    ManualField.returnOnCapital => copyWith(returnOnCapital: value),
    ManualField.retention => copyWith(retention: value),
    ManualField.terminalReturn => copyWith(terminalReturn: value),
  };
}

/// Os grupos de premissas, na ordem em que [ManualValuation.attribution]
/// os aplica.
enum ManualGroup {
  /// O lucro de partida.
  profit,

  /// O crescimento e o caminho dele.
  growth,

  /// O modo de reinvestir, o retorno e a parcela.
  reinvestment,

  /// A taxa de desconto e o caminho dela.
  rate,

  /// O crescimento na perpetuidade.
  perpetuity,

  /// O retorno do capital novo na perpetuidade.
  newCapital,
}

/// Como o valor terminal foi formado.
enum ManualTerminal {
  /// Capital novo rendendo a própria taxa: `lucro_{N+1} ÷ taxa`, e o
  /// crescimento perpétuo quase não pesa.
  neutral,

  /// Retorno do capital novo acima (ou abaixo) da taxa: Gordon com
  /// reinvestimento, `lucro_{N+1}·(1 − g/retorno) ÷ (taxa − g)`.
  advantage,

  /// Gordon com a parcela fixa: `lucro_{N+1}·(1 − b) ÷ (taxa − g)`.
  fixedFraction,

  /// Concessão: o capital volta no fim do contrato, e o excedente sobre ele só
  /// dura até lá (decisão 88).
  contract,
}

/// Algo que a conta fez e que o usuário precisa saber para ler o número.
enum ManualNoticeKind {
  /// O crescimento digitado não coube no que o retorno financia: com
  /// reinvestimento acima de 95% do lucro, o motor o confina.
  confinedGrowth,

  /// O fluxo de algum ano ficou negativo: a empresa reinveste mais do que
  /// lucra.
  negativeFlow,

  /// A empresa é concessão, e a perpetuidade deixou de acabar no contrato.
  perpetualConcession,

  /// Crescimento perpétuo trocado com o capital novo rendendo a própria taxa:
  /// ele quase não muda a perpetuidade.
  neutralPerpetuity,
}

/// Um aviso do cálculo do usuário, com os anos a que se refere.
class ManualNotice {
  /// Qual aviso.
  final ManualNoticeKind kind;

  /// Anos explícitos afetados, contados a partir de 1. Vazio quando o aviso
  /// não é de ano.
  final List<int> years;

  /// Declara o aviso.
  const ManualNotice(this.kind, {this.years = const []});
}

/// Um ano do cálculo do usuário, em reais.
class ManualYear {
  /// Ano projetado, a partir de 1.
  final int year;

  /// Crescimento aplicado, já confinado ao que o retorno financia.
  final double growth;

  /// Crescimento pedido, antes do confinamento.
  final double plannedGrowth;

  /// Lucro do ano antes do reinvestimento: `NOPAT` na via da firma, lucro
  /// líquido na do acionista.
  final double profit;

  /// Parcela do lucro reinvestida.
  final double retention;

  /// Fluxo da firma, antes da dívida — só na via da firma.
  final double? firmFlow;

  /// Serviço líquido da dívida — só na via da firma.
  final double? debtService;

  /// Fluxo do acionista do ano, o que se desconta.
  final double flow;

  /// Taxa que descontou o ano.
  final double rate;

  /// `fluxo ÷ fator = valor presente`.
  final double discountFactor;

  /// Valor presente do fluxo.
  final double presentValue;

  /// Declara o ano.
  const ManualYear({
    required this.year,
    required this.growth,
    required this.plannedGrowth,
    required this.profit,
    required this.retention,
    this.firmFlow,
    this.debtService,
    required this.flow,
    required this.rate,
    required this.discountFactor,
    required this.presentValue,
  });
}

/// O resultado de um cálculo do usuário. Valores agregados em reais.
class ManualOutcome {
  /// Preço justo por papel, sob as premissas do usuário.
  final double fairValuePerShare;

  /// Valor do patrimônio da controladora — o valor presente líquido do que o
  /// acionista recebe.
  final double equityValue;

  /// Soma do valor presente dos anos explícitos.
  final double explicitPresentValue;

  /// Valor terminal no último ano explícito, antes de descontar.
  final double terminalValue;

  /// Valor terminal trazido a presente.
  final double terminalPresentValue;

  /// Participação dos não controladores, que sai antes da divisão por papel.
  final double minorityInterest;

  /// Capital das emissões depois do balanço, somado pelo valor de emissão.
  final double postStatementCapital;

  /// Taxa que descontou a perpetuidade.
  final double terminalRate;

  /// Custo médio do capital de cada ano e o da perpetuidade — só na via da
  /// firma, onde ele guia o retorno e a perpetuidade da firma.
  final List<double>? capitalCostRates;
  final double? terminalCapitalCost;

  /// Como o terminal foi formado.
  final ManualTerminal terminalKind;

  /// Os anos explícitos.
  final List<ManualYear> years;

  /// O que a conta fez e o usuário precisa saber.
  final List<ManualNotice> notices;

  /// Declara o resultado.
  const ManualOutcome({
    required this.fairValuePerShare,
    required this.equityValue,
    required this.explicitPresentValue,
    required this.terminalValue,
    required this.terminalPresentValue,
    required this.minorityInterest,
    required this.postStatementCapital,
    required this.terminalRate,
    this.capitalCostRates,
    this.terminalCapitalCost,
    required this.terminalKind,
    required this.years,
    required this.notices,
  });
}

/// Um degrau de "onde você discorda do motor".
class ManualStep {
  /// Os grupos aplicados neste degrau. Mais de um quando aplicar o primeiro
  /// sozinho deixava a conta sem valor finito — a taxa digitada abaixo do
  /// crescimento perpétuo do motor, por exemplo.
  final List<ManualGroup> groups;

  /// Preço justo antes do degrau.
  final double from;

  /// Preço justo depois do degrau, ou `null` quando a conta não fecha.
  final double? to;

  /// Declara o degrau.
  const ManualStep({required this.groups, required this.from, this.to});

  /// Quanto o degrau moveu o preço, ou `null` quando a conta não fecha.
  double? get delta => to == null ? null : to! - from;
}

/// A resposta de "o que o preço de hoje supõe".
class ManualSolution {
  /// O campo resolvido.
  final ManualField field;

  /// O preço que se queria alcançar.
  final double target;

  /// O valor do campo que leva o preço justo a [target], ou `null` quando
  /// nenhum valor na faixa examinada leva.
  final double? value;

  /// Sem solução: o valor do campo que chega mais perto de [target], e o preço
  /// que ele dá.
  final double? closestValue;
  final double? closestPrice;

  /// Declara a resposta.
  const ManualSolution({
    required this.field,
    required this.target,
    this.value,
    this.closestValue,
    this.closestPrice,
  });
}

/// **A conta do motor congelada**, para o usuário refazê-la com os números
/// dele (decisão 147).
///
/// A cascata decide a via, normaliza a base, mede o crescimento, resolve o
/// custo de capital pelo ponto fixo e desconta. Este objeto guarda o que saiu
/// dela — o fluxo-base, as premissas finais, o caminho de taxas, a ponte da
/// dívida — e desconta de novo **pela mesma calculadora**, trocando só o que o
/// usuário digitou. Duas consequências, e as duas são o ponto:
///
/// - **sem nenhuma troca, o resultado é o preço justo do motor**, ao centavo e
///   além — travado por teste;
/// - **cada troca muda só a premissa trocada.** Quem baixa a taxa de desconto
///   mantém o lucro normalizado, a ponte da dívida e o caixa da emissão
///   posterior; quem troca o lucro mantém a taxa.
///
/// **O que ele não faz é revalidar.** A faixa calibrada, a habilidade medida e
/// as ressalvas são do preço do motor, porque foi ele que as coortes mediram.
/// O preço do usuário é a conta do usuário.
class ManualValuation {
  /// Via da avaliação do motor. O usuário refaz a conta na mesma via.
  final ValuationLane lane;

  /// Papéis da ponte — a contagem que forma a cotação.
  final double shares;

  /// Preço de mercado da avaliação.
  final double marketPrice;

  /// Preço justo do motor por papel, antes do arredondamento ao centavo.
  final double engineFairValue;

  /// Fluxo-base do motor, na unidade da via: `NOPAT` em reais na da firma,
  /// lucro por papel na do acionista.
  final double engineBase;

  /// Lucro do último exercício publicado, em reais e sem a normalização pelo
  /// ciclo, ou `null` quando ele não é medível.
  final double? publishedBase;

  /// Fator de normalização que o motor aplicou ao último exercício.
  final double baseFactor;

  /// `true` quando o fluxo-base foi reconstruído do ciclo (decisão 53).
  final bool rebuiltBase;

  /// Premissas finais do motor — as que produziram o preço justo.
  final DcfAssumptions engineAssumptions;

  /// Taxa que descontou o fluxo do acionista em cada ano, e a da
  /// perpetuidade: o custo do capital próprio, nas duas vias.
  final List<double> engineRates;
  final double engineTerminalRate;

  /// A rota derivada da firma e o `Ke` do centro que a desconta — só na via da
  /// firma.
  final FirmDiscountRoute? firmRoute;
  final double? engineEquityRate;
  final double? engineTerminalEquityRate;
  final List<double>? engineEquityRatePath;

  /// Capital das emissões depois do balanço, em reais (item B28).
  final double postStatementCapital;

  /// Declara a conta congelada. Quem a monta é a cascata, ao concluir a via.
  const ManualValuation({
    required this.lane,
    required this.shares,
    required this.marketPrice,
    required this.engineFairValue,
    required this.engineBase,
    this.publishedBase,
    this.baseFactor = 1.0,
    this.rebuiltBase = false,
    required this.engineAssumptions,
    required this.engineRates,
    required this.engineTerminalRate,
    this.firmRoute,
    this.engineEquityRate,
    this.engineTerminalEquityRate,
    this.engineEquityRatePath,
    this.postStatementCapital = 0.0,
  });

  /// Anos de projeção explícita.
  int get projectionYears => engineAssumptions.projectionYears;

  /// `true` quando a empresa é concessão com prazo.
  bool get isConcession => engineAssumptions.contractYearsAfterHorizon != null;

  /// Quanto um real de lucro por papel vale em reais agregados.
  double get _scale => lane == ValuationLane.shareholder ? shares : 1.0;

  /// As premissas do motor, no vocabulário do usuário: é de onde os campos
  /// partem.
  ManualPremises get enginePremises => ManualPremises(
    baseProfit: engineBase * _scale,
    growth: engineAssumptions.growthRate,
    discountRate: engineRates.first,
    perpetualGrowth: engineAssumptions.perpetualGrowth,
    returnOnCapital: engineAssumptions.returnOnCapital,
    // A parcela do primeiro ano do motor é o ponto de partida de quem troca
    // o reinvestimento pelo retorno pela parcela fixa.
    retention: engineAssumptions.retentionAt(1),
    terminalReturn: engineAssumptions.terminalReturnOnCapital,
  );

  /// `true` quando a taxa das premissas é exatamente a do motor.
  bool _isEngineRate(ManualPremises p) =>
      p.ratePath == ManualRatePath.engine && p.discountRate == engineRates.first;

  /// A taxa de cada ano e a da perpetuidade, sob as premissas.
  ({List<double> years, double terminal}) _rates(ManualPremises p) {
    switch (p.ratePath) {
      case ManualRatePath.engine:
        final d = p.discountRate - engineRates.first;
        return (
          years: [for (final r in engineRates) r + d],
          terminal: engineTerminalRate + d,
        );
      case ManualRatePath.constant:
        return (
          years: List.filled(projectionYears, p.discountRate),
          terminal: p.discountRate,
        );
    }
  }

  /// As premissas do motor com as do usuário no lugar.
  ///
  /// Cada troca só acontece quando o campo difere do motor, de modo que a
  /// conta sem troca use **as mesmas** premissas da cascata, e não uma cópia
  /// delas.
  DcfAssumptions _assumptions(
    ManualPremises p,
    ({List<double> years, double terminal}) rates,
  ) {
    final m = enginePremises;
    var a = engineAssumptions;
    // **Na via do acionista a taxa das premissas é o `Ke`**, e a do usuário
    // entra nela. **Na da firma, não**: as premissas carregam o `WACC`, que lá
    // não desconta nada — é o alvo para onde o retorno sobre o capital
    // converge e a taxa que fixa o reinvestimento da perpetuidade da firma —,
    // e a taxa do usuário entra só no `Ke` que desconta o fluxo do acionista.
    //
    // Mover o `WACC` junto, pela tradução dos cenários do motor (decisão 121),
    // foi medido e recusado em 11/10/2026: com o retorno convergindo a um custo
    // de capital maior, a empresa passa a precisar reinvestir menos para
    // crescer, e na companhia endividada isso supera o desconto — em 12 dos 90
    // ativos da via da firma, **subir a taxa subia o preço**. Quem digita a
    // taxa de desconto está dizendo quanto exige, e não quanto a empresa rende:
    // o retorno tem campo próprio.
    if (!_isEngineRate(p) && lane == ValuationLane.shareholder) {
      a = a.copyWith(
        discountRatePath: rates.years,
        discountRate: rates.years.first,
        terminalDiscountRate: rates.terminal,
      );
    }
    if (p.growth != m.growth) a = a.copyWith(growthRate: p.growth);
    if (p.growthPath == ManualGrowthPath.constant) {
      a = a.copyWith(growthPath: List.filled(projectionYears, p.growth));
    }
    if (p.perpetualGrowth != m.perpetualGrowth) {
      a = a.copyWith(perpetualGrowth: p.perpetualGrowth);
    }
    if (p.returnOnCapital != m.returnOnCapital) {
      a = a.copyWith(returnOnCapital: p.returnOnCapital);
    }
    if (p.reinvestment == ManualReinvestment.fixedFraction) {
      // O terminal neutro sai: com a parcela fixa, é Gordon com ela, e a
      // concessão deixa de cortar o excedente — ver [ManualNoticeKind].
      a = a.copyWith(
        reinvestmentPolicy: ReinvestmentPolicy.fixedFraction,
        fixedRetention: p.retention,
        neutralTerminalReturn: false,
      );
    }
    if (p.terminalReturn != m.terminalReturn) {
      a = a.withTerminalReturnOnCapital(p.terminalReturn);
    }
    return a;
  }

  /// Refaz a conta do motor com as premissas [p].
  ///
  /// Recusa com [InvalidInput] e o campo nomeado em [InvalidInput.field]
  /// quando a premissa não tem conta: lucro de partida não positivo, taxa não
  /// positiva, parcela reinvestida fora de `[0, 100%)`, retorno do capital
  /// novo não positivo, ou taxa da perpetuidade a menos de
  /// [DcfCalculator.minimumSpread] do crescimento perpétuo onde a perpetuidade
  /// é de Gordon — aí ela não tem valor finito.
  Result<ManualOutcome> evaluate(ManualPremises p) {
    if (!p.baseProfit.isFinite || p.baseProfit <= 0) {
      return Err(
        InvalidInput(
          'Lucro de partida não positivo: o fluxo descontado parte dele.',
          field: ManualField.baseProfit.name,
          actual: p.baseProfit,
          limit: 0,
          unit: QuantityUnit.currency,
        ),
      );
    }
    if (p.reinvestment == ManualReinvestment.fixedFraction &&
        (!p.retention.isFinite || p.retention < 0 || p.retention >= 1)) {
      return Err(
        InvalidInput(
          'Parcela reinvestida fora de [0, 100%): reinvestir tudo para sempre '
          'não deixa nada ao acionista.',
          field: ManualField.retention.name,
          actual: p.retention,
          limit: 1,
          unit: QuantityUnit.fraction,
        ),
      );
    }
    final tr = p.terminalReturn;
    if (tr != null && (!tr.isFinite || tr <= 0)) {
      return Err(
        InvalidInput(
          'Retorno do capital novo na perpetuidade não positivo.',
          field: ManualField.terminalReturn.name,
          actual: tr,
          limit: 0,
          unit: QuantityUnit.fraction,
        ),
      );
    }
    if (!p.growth.isFinite || p.growth <= -1) {
      return Err(
        InvalidInput(
          'Crescimento que zera o lucro.',
          field: ManualField.growth.name,
          actual: p.growth,
          limit: -1,
          unit: QuantityUnit.fraction,
        ),
      );
    }
    if (!p.perpetualGrowth.isFinite || p.perpetualGrowth <= -1) {
      return Err(
        InvalidInput(
          'Crescimento perpétuo que zera o lucro.',
          field: ManualField.perpetualGrowth.name,
          actual: p.perpetualGrowth,
          limit: -1,
          unit: QuantityUnit.fraction,
        ),
      );
    }
    if (!p.returnOnCapital.isFinite) {
      return Err(
        InvalidInput(
          'Retorno sobre o capital não finito.',
          field: ManualField.returnOnCapital.name,
        ),
      );
    }
    final rates = _rates(p);
    final lowestRate = [
      ...rates.years,
      rates.terminal,
    ].reduce((x, y) => x < y ? x : y);
    if (!lowestRate.isFinite || lowestRate <= 0) {
      return Err(
        InvalidInput(
          'Taxa de desconto não positiva em algum ano.',
          field: ManualField.discountRate.name,
          actual: lowestRate,
          limit: 0,
          unit: QuantityUnit.fraction,
        ),
      );
    }

    final a = _assumptions(p, rates);
    final base = p.baseProfit == enginePremises.baseProfit
        ? engineBase
        : p.baseProfit / _scale;
    final Result<DcfOutcome> discountedOutcome;
    if (lane == ValuationLane.shareholder) {
      discountedOutcome = DcfCalculator.shareholder(baseProfit: base, assumptions: a);
    } else {
      final route = firmRoute;
      if (route == null) {
        return const Err(
          ComputationFailure(
            'Avaliação da via da firma sem a rota da dívida congelada.',
          ),
        );
      }
      final fromEngine = _isEngineRate(p);
      discountedOutcome = route.discount(
        baseProfit: base,
        assumptions: a,
        equityDiscountRate: fromEngine
            ? (engineEquityRate ?? rates.years.first)
            : rates.years.first,
        terminalEquityDiscountRate: fromEngine
            ? (engineTerminalEquityRate ?? rates.terminal)
            : rates.terminal,
        equityDiscountRatePath: fromEngine ? engineEquityRatePath : rates.years,
      );
    }

    return discountedOutcome.fold(
      (o) => Ok(_result(p, a, o, rates)),
      (failure) => Err(_translate(failure, p, a, rates)),
    );
  }

  /// A recusa da calculadora, nomeando o campo quando é a margem da
  /// perpetuidade — o único caso em que ela recusa premissa que passou pelas
  /// conferências de [evaluate].
  Failure _translate(
    Failure failure,
    ManualPremises p,
    DcfAssumptions a,
    ({List<double> years, double terminal}) rates,
  ) {
    final margins = [
      rates.terminal - p.perpetualGrowth,
      if (lane == ValuationLane.firm)
        a.terminalDiscountRate - p.perpetualGrowth,
    ];
    final smaller = margins.reduce((x, y) => x < y ? x : y);
    if (smaller < DcfCalculator.minimumSpread) {
      return InvalidInput(
        'A taxa de desconto da perpetuidade não supera o crescimento perpétuo '
        'pela margem mínima: a perpetuidade não tem valor finito.',
        field: ManualField.perpetualGrowth.name,
        actual: smaller,
        limit: DcfCalculator.minimumSpread,
        unit: QuantityUnit.fraction,
      );
    }
    return failure;
  }

  ManualOutcome _result(
    ManualPremises p,
    DcfAssumptions a,
    DcfOutcome o,
    ({List<double> years, double terminal}) rates,
  ) {
    final e = _scale;
    final n = o.projectedFlows.length;
    final profits = o.projectedProfits;
    final retentions = o.retentions;
    final growthRates = o.growthRates;
    final factors = o.discountFactors;
    final years = <ManualYear>[
      for (var i = 0; i < n; i++)
        ManualYear(
          year: i + 1,
          growth: growthRates?[i] ?? a.growthAt(i + 1),
          plannedGrowth: a.plannedGrowthAt(i + 1),
          profit: (profits?[i] ?? double.nan) * e,
          retention: retentions?[i] ?? a.retentionAt(i + 1),
          firmFlow: o.firmFlows?[i],
          debtService: o.debtService?[i],
          flow: o.projectedFlows[i] * e,
          rate: o.discountRates?[i] ?? rates.years[i],
          discountFactor: factors?[i] ?? double.nan,
          presentValue: o.discountedFlows[i] * e,
        ),
    ];
    final explicitValue = o.discountedFlows.fold(0.0, (s, v) => s + v) * e;
    final terminalPv = o.discountedTerminalValue * e;
    final route = firmRoute;
    final minorityValue = lane == ValuationLane.firm && route != null
        ? _nonNegative(route.minorityInterest)
        : 0.0;
    final capital = postStatementCapital > 0 && shares > 0
        ? postStatementCapital
        : 0.0;
    final perShare = o.fairValuePerShare + (shares > 0 ? capital / shares : 0);

    final ManualTerminal kind;
    if (a.reinvestmentPolicy == ReinvestmentPolicy.fixedFraction) {
      kind = ManualTerminal.fixedFraction;
    } else if (a.terminalReturnOnCapital != null) {
      kind = ManualTerminal.advantage;
    } else if (a.contractYearsAfterHorizon != null && a.returnOnCapital > 0) {
      kind = ManualTerminal.contract;
    } else {
      kind = ManualTerminal.neutral;
    }

    final warnings = <ManualNotice>[];
    final confinedValues = [
      for (final y in years)
        if (y.plannedGrowth - y.growth > 1e-9) y.year,
    ];
    if (confinedValues.isNotEmpty) {
      warnings.add(
        ManualNotice(ManualNoticeKind.confinedGrowth, years: confinedValues),
      );
    }
    final negatives = [
      for (final y in years)
        if (y.flow < 0) y.year,
    ];
    if (negatives.isNotEmpty) {
      warnings.add(
        ManualNotice(ManualNoticeKind.negativeFlow, years: negatives),
      );
    }
    if (isConcession && kind != ManualTerminal.contract) {
      warnings.add(const ManualNotice(ManualNoticeKind.perpetualConcession));
    }
    if (kind == ManualTerminal.neutral &&
        p.perpetualGrowth != enginePremises.perpetualGrowth) {
      warnings.add(const ManualNotice(ManualNoticeKind.neutralPerpetuity));
    }

    return ManualOutcome(
      fairValuePerShare: perShare,
      equityValue: explicitValue + terminalPv - minorityValue + capital,
      explicitPresentValue: explicitValue,
      terminalValue: o.terminalValue * e,
      terminalPresentValue: terminalPv,
      minorityInterest: minorityValue,
      postStatementCapital: capital,
      terminalRate: o.terminalDiscountRateUsed ?? rates.terminal,
      capitalCostRates: lane == ValuationLane.firm
          ? List.unmodifiable([
              for (var t = 1; t <= n; t++) a.discountRateAt(t),
            ])
          : null,
      terminalCapitalCost: lane == ValuationLane.firm
          ? a.terminalDiscountRate
          : null,
      terminalKind: kind,
      years: List.unmodifiable(years),
      notices: List.unmodifiable(warnings),
    );
  }

  /// O mesmo tratamento que a rota derivada dá aos minoritários: negativo não
  /// soma valor ao controlador.
  static double _nonNegative(double v) => v.isFinite && v > 0 ? v : 0.0;

  /// `true` quando o grupo [g] difere entre [a] e [b].
  static bool _differs(ManualGroup g, ManualPremises a, ManualPremises b) =>
      switch (g) {
        ManualGroup.profit => a.baseProfit != b.baseProfit,
        ManualGroup.growth =>
          a.growth != b.growth || a.growthPath != b.growthPath,
        ManualGroup.reinvestment =>
          a.reinvestment != b.reinvestment ||
              a.returnOnCapital != b.returnOnCapital ||
              (b.reinvestment == ManualReinvestment.fixedFraction &&
                  a.retention != b.retention),
        ManualGroup.rate =>
          a.discountRate != b.discountRate || a.ratePath != b.ratePath,
        ManualGroup.perpetuity => a.perpetualGrowth != b.perpetualGrowth,
        ManualGroup.newCapital => a.terminalReturn != b.terminalReturn,
      };

  /// [current] com os campos do grupo [g] trocados pelos de [target].
  static ManualPremises _apply(
    ManualGroup g,
    ManualPremises current,
    ManualPremises target,
  ) => switch (g) {
    ManualGroup.profit => current.copyWith(baseProfit: target.baseProfit),
    ManualGroup.growth => current.copyWith(
      growth: target.growth,
      growthPath: target.growthPath,
    ),
    ManualGroup.reinvestment => current.copyWith(
      reinvestment: target.reinvestment,
      returnOnCapital: target.returnOnCapital,
      retention: target.retention,
    ),
    ManualGroup.rate => current.copyWith(
      discountRate: target.discountRate,
      ratePath: target.ratePath,
    ),
    ManualGroup.perpetuity => current.copyWith(
      perpetualGrowth: target.perpetualGrowth,
    ),
    ManualGroup.newCapital => current.copyWith(
      terminalReturn: target.terminalReturn,
    ),
  };

  /// **Onde o usuário discorda do motor**: do preço do motor ao dele, um grupo
  /// de premissas de cada vez, na ordem de [ManualGroup].
  ///
  /// A ordem importa — o efeito de baixar a taxa depende do crescimento que já
  /// está na conta —, e por isso é fixa: a mesma troca dá sempre os mesmos
  /// degraus. Um grupo que, aplicado sozinho, deixa a conta sem valor finito é
  /// somado ao seguinte, e o degrau diz os dois.
  List<ManualStep> attribution(ManualPremises p) {
    final m = enginePremises;
    final start = evaluate(m).valueOrNull?.fairValuePerShare ?? engineFairValue;
    var current = m;
    var previous = start;
    final pending = <ManualGroup>[];
    final steps = <ManualStep>[];
    for (final g in ManualGroup.values) {
      if (!_differs(g, m, p)) continue;
      current = _apply(g, current, p);
      pending.add(g);
      final r = evaluate(current).valueOrNull;
      if (r == null) continue;
      steps.add(
        ManualStep(
          groups: List.unmodifiable(pending),
          from: previous,
          to: r.fairValuePerShare,
        ),
      );
      previous = r.fairValuePerShare;
      pending.clear();
    }
    if (pending.isNotEmpty) {
      steps.add(
        ManualStep(groups: List.unmodifiable(pending), from: previous),
      );
    }
    return List.unmodifiable(steps);
  }

  /// Faixa examinada por [solve] para cada campo.
  (double, double) _band(ManualField f) => switch (f) {
    ManualField.baseProfit => (
      enginePremises.baseProfit * 0.001,
      enginePremises.baseProfit * 50,
    ),
    ManualField.growth => (-0.5, 1.0),
    ManualField.discountRate => (0.001, 0.6),
    ManualField.perpetualGrowth => (-0.2, 0.3),
    ManualField.returnOnCapital => (0.001, 1.5),
    ManualField.retention => (0.0, 0.999),
    ManualField.terminalReturn => (0.001, 1.0),
  };

  /// **O que o preço de hoje supõe**: o valor de [field] que leva o preço
  /// justo, com as outras premissas de [from], a [target] — o preço de
  /// mercado, quando omitido.
  ///
  /// Varre a faixa do campo numa grade de 400 pontos, acha a primeira troca de
  /// sinal e a refina por bisseção. Sem troca, devolve o valor que chega mais
  /// perto e o preço que ele dá. Determinístico: a mesma pergunta dá sempre a
  /// mesma resposta.
  ManualSolution solve(
    ManualField field,
    ManualPremises from, {
    double? target,
  }) {
    final targetValue = target ?? marketPrice;
    double? deviation(double v) {
      final r = evaluate(from.withValue(field, v)).valueOrNull;
      if (r == null || !r.fairValuePerShare.isFinite) return null;
      return r.fairValuePerShare - targetValue;
    }

    final (lo, hi) = _band(field);
    const points = 400;
    double? a;
    double? fa;
    double? b;
    double? best;
    double? bestDeviation;
    for (var i = 0; i <= points; i++) {
      final v = lo + (hi - lo) * i / points;
      final fv = deviation(v);
      if (fv == null) continue;
      if (bestDeviation == null || fv.abs() < bestDeviation.abs()) {
        best = v;
        bestDeviation = fv;
      }
      if (fa != null && (fa <= 0) != (fv <= 0)) {
        b = v;
        break;
      }
      a = v;
      fa = fv;
    }
    if (a == null || fa == null || b == null) {
      return ManualSolution(
        field: field,
        target: targetValue,
        closestValue: best,
        closestPrice: bestDeviation == null ? null : bestDeviation + targetValue,
      );
    }
    var left = a;
    var dir = b;
    var fLeft = fa;
    for (var i = 0; i < 80; i++) {
      final mid = (left + dir) / 2;
      final fm = deviation(mid);
      if (fm == null) break;
      if ((fLeft <= 0) == (fm <= 0)) {
        left = mid;
        fLeft = fm;
      } else {
        dir = mid;
      }
    }
    return ManualSolution(field: field, target: targetValue, value: (left + dir) / 2);
  }
}
