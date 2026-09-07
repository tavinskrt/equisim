import '../value_objects/ticker.dart';

/// Fotografia dos fundamentos de um exercício social.
///
/// A fonte fornece **apenas granularidade anual** (16 exercícios, 2010–2025).
/// Não existe recorte trimestral — limitação a declarar na metodologia.
///
/// Campos derivados relevantes que a fonte não entrega prontos:
/// - D&A       = `cleanEbitda − cleanEbit`
/// - alíquota  = `incomeTaxExpense / incomeBeforeTax`
/// - dív. líq. = `(curto + longo prazo) − (caixa + aplicações)`
class FundamentalsSnapshot {
  /// Ativo a que o exercício pertence.
  final Ticker ticker;

  /// Encerramento do exercício a que os números se referem.
  ///
  /// É a data que [PointInTimeView] compara com o corte de publicação para
  /// decidir se o exercício já era público numa data de análise.
  final DateTime fiscalPeriodEnd;

  // --- Demonstração de resultado ---
  // Todos os campos abaixo são `null` quando a fonte não os informa para o
  // exercício. Valores monetários vêm em reais, na escala publicada pela
  // fonte (unidades, não milhares), e por ação onde o nome indica.
  final double? totalRevenue;
  final double? ebit;
  final double? ebitda;
  final double? netIncome;
  final double? incomeBeforeTax;
  final double? incomeTaxExpense;
  final double? interestExpense;
  final double? earningsPerShare;

  // --- Balanço patrimonial ---
  final double? cash;
  final double? shortTermInvestments;
  final double? shortTermDebt;
  final double? longTermDebt;
  final double? totalStockholderEquity;
  final double? bookValuePerShare;

  /// Lucro operacional líquido de imposto, quando a fonte o publica.
  ///
  /// Derivado por `ebit × (1 − alíquota efetiva)` quando ausente — ver [nopatOf].
  /// Não existe para instituição financeira, que não tem EBIT publicado; é uma
  /// das confirmações numéricas da Porta 1 (decisão 25).
  final double? nopat;

  // --- Balanço, lado operacional ---
  // Existem para reconstituir o capital investido pelo lado das operações e
  // conferi-lo contra o lado do financiamento. A concordância entre as duas
  // rotas é teste de qualidade do exercício.
  final double? propertyPlantEquipment;
  final double? intangibleAssets;
  final double? totalCurrentAssets;
  final double? currentLiabilities;

  /// Capital social realizado. Sobe por emissão **e** por incorporação de
  /// reservas, então não serve sozinho para medir capital externo — ver
  /// [externalCapitalAgainst].
  final double? realizedShareCapital;

  /// Reservas de lucro. Serve para distinguir emissão de incorporação.
  final double? profitReserves;

  // --- Fluxo de caixa ---
  final double? operatingCashFlow;
  final double? investmentCashFlow;
  final double? freeCashFlow;

  // --- Mercado ---
  final double? sharesOutstanding;

  /// Contagem de ações **do exercício**, preservada antes da sobrescrita pelo
  /// valor corrente.
  ///
  /// [sharesOutstanding] descreve o hoje, e é o que o preço por papel exige.
  /// Este descreve o ano, e é o que o patrimônio exige: [bookValuePerShare] é
  /// publicado por ação daquele exercício, e multiplicá-lo pela contagem
  /// corrente mistura escalas em toda empresa que desdobrou ou bonificou.
  final double? sharesOutstandingAsOf;

  final double? marketCap;
  final double? enterpriseToEbitda;

  const FundamentalsSnapshot({
    required this.ticker,
    required this.fiscalPeriodEnd,
    this.totalRevenue,
    this.ebit,
    this.ebitda,
    this.netIncome,
    this.incomeBeforeTax,
    this.incomeTaxExpense,
    this.interestExpense,
    this.earningsPerShare,
    this.nopat,
    this.cash,
    this.shortTermInvestments,
    this.shortTermDebt,
    this.longTermDebt,
    this.totalStockholderEquity,
    this.bookValuePerShare,
    this.propertyPlantEquipment,
    this.intangibleAssets,
    this.totalCurrentAssets,
    this.currentLiabilities,
    this.realizedShareCapital,
    this.profitReserves,
    this.operatingCashFlow,
    this.investmentCashFlow,
    this.freeCashFlow,
    this.sharesOutstanding,
    this.sharesOutstandingAsOf,
    this.marketCap,
    this.enterpriseToEbitda,
  });

  /// Depreciação e amortização, derivada de EBITDA − EBIT.
  double? get depreciationAndAmortization {
    if (ebitda == null || ebit == null) return null;
    final da = ebitda! - ebit!;
    return da >= 0 ? da : null;
  }

  /// Alíquota efetiva de imposto, limitada a [0, 0.5] para conter distorções
  /// de exercícios com prejuízo ou créditos fiscais extraordinários.
  double? get effectiveTaxRate {
    if (incomeBeforeTax == null || incomeTaxExpense == null) return null;
    if (incomeBeforeTax! <= 0) return null;
    final rate = incomeTaxExpense!.abs() / incomeBeforeTax!;
    if (rate.isNaN || rate.isInfinite) return null;
    return rate.clamp(0.0, 0.5);
  }

  /// Dívida bruta: curto mais longo prazo.
  ///
  /// **Trata ausência como zero.** Uma parcela não informada pela fonte é
  /// indistinguível aqui de uma parcela realmente nula, e o efeito não é
  /// neutro: dívida subestimada infla o equity no *bridge* do DCF
  /// (`Equity = EV − dívida líquida`). Quem precisa distinguir "sem dívida" de
  /// "sem dado" deve inspecionar [shortTermDebt] e [longTermDebt] diretamente.
  double get totalDebt => (shortTermDebt ?? 0) + (longTermDebt ?? 0);

  /// Caixa e equivalentes: disponibilidades mais aplicações de curto prazo.
  ///
  /// Trata ausência como zero, com a ressalva simétrica à de [totalDebt] — aqui
  /// o viés é conservador, porque caixa subestimado **reduz** o equity.
  double get totalCash => (cash ?? 0) + (shortTermInvestments ?? 0);

  /// Dívida líquida: [totalDebt] menos [totalCash]. Negativa em empresa com
  /// caixa maior que a dívida, e é assim que entra no *bridge* do DCF.
  double get netDebt => totalDebt - totalCash;

  /// Custo da dívida implícito: despesa financeira sobre dívida bruta.
  double? get costOfDebt {
    if (interestExpense == null || totalDebt <= 0) return null;
    final kd = interestExpense!.abs() / totalDebt;
    if (kd.isNaN || kd.isInfinite) return null;
    return kd.clamp(0.0, 1.0);
  }

  /// CapEx aproximado pelo fluxo de investimento.
  ///
  /// Aproximação imperfeita: `investmentCashFlow` inclui M&A e aplicações
  /// financeiras, não só imobilizado. Medido contra `Δ(imobilizado) + D&A`, erra
  /// por fatores de 0,25× a 2,42× e para os dois lados — **não use em conta de
  /// reinvestimento**. A variação do capital investido mede a mesma grandeza sem
  /// passar por aqui; ver [investedCapital].
  double? get approximateCapex => investmentCashFlow?.abs();

  // --------------------------------------------------- Bases de capital --

  /// Patrimônio líquido reconstituído: `VPA × ações do exercício`.
  ///
  /// **Não** usa [totalStockholderEquity], que a fonte deixa nulo em todos os 16
  /// exercícios do BBAS3 e só preenche a partir de 2020 no campo do controlador.
  /// E **não** usa [sharesOutstanding], que é a contagem de hoje: o produto teria
  /// escalas misturadas em qualquer empresa que tenha desdobrado.
  ///
  /// Base da via B e imune a desdobramento e bonificação por construção, ao
  /// contrário de qualquer série por ação.
  double? get equityBookValue {
    final vpa = bookValuePerShare;
    final n = sharesOutstandingAsOf;
    if (vpa == null || n == null || vpa <= 0 || n <= 0) return null;
    final pl = vpa * n;
    return pl.isFinite ? pl : null;
  }

  /// Capital investido pelo lado do financiamento: `PL + dívida bruta − caixa`.
  ///
  /// Base da via A. Equivale, por identidade de balanço, a
  /// `imobilizado + intangível + capital de giro` — ver [investedCapitalOperating],
  /// cuja concordância com este serve de teste de qualidade.
  ///
  /// A soma que a taxa de reinvestimento pede — `CapEx − Depreciação + ΔNKG` — é
  /// exatamente a variação desta grandeza, o que dispensa o CapEx que a fonte não
  /// publica.
  double? get investedCapital {
    final pl = equityBookValue;
    if (pl == null) return null;
    final ci = pl + totalDebt - totalCash;
    return (ci.isFinite && ci > 0) ? ci : null;
  }

  /// Capital investido pelo lado operacional, quando as linhas existem.
  ///
  /// Devolve `null` sem imobilizado ou sem capital de giro. O capital de giro é
  /// **operacional**: exclui caixa do ativo e dívida de curto prazo do passivo.
  double? get investedCapitalOperating {
    final imob = propertyPlantEquipment;
    final ac = totalCurrentAssets;
    final pc = currentLiabilities;
    if (imob == null || ac == null || pc == null) return null;
    final nkg = (ac - totalCash) - (pc - (shortTermDebt ?? 0));
    final ci = imob + (intangibleAssets ?? 0) + nkg;
    return ci.isFinite ? ci : null;
  }

  // ------------------------------------------------ Contagem de papéis --

  /// Contagem de ações conciliada entre as duas que a fonte publica.
  ///
  /// **Por que não basta [sharesOutstanding].** A fonte publica duas contagens:
  /// a corrente, que acompanha o preço, e a do exercício, que acompanha as
  /// demonstrações. Elas divergem em **47 dos 334** ativos com as duas
  /// preenchidas (medido em 07/09/2026 sobre o cache de produção), e a
  /// divergência chega a **4.868×** — o MILS3 vem com 48.172 ações correntes
  /// contra 234.178.210 do exercício. Dividir o valor da firma pela contagem
  /// errada produziu preço justo de R$ 37.708,72 contra R$ 15,79 de mercado na
  /// validação fora da amostra.
  ///
  /// **O árbitro é o próprio lucro por ação publicado.** `N = lucro ÷ LPA` é
  /// identidade contábil, não estimativa, e usa dois campos que já existem. Nos
  /// 38 casos divergentes com LPA utilizável ele confirmou a contagem do
  /// exercício em **34** — com razão de 1,0000 na maioria — e a contagem
  /// corrente em **nenhum**.
  ///
  /// Sem árbitro, prefere-se a contagem do exercício: é a que reconstrói o
  /// patrimônio publicado (`VPA × N = PL`, verificado em todos os divergentes),
  /// e o numerador de qualquer ponte vem dessas mesmas demonstrações.
  ///
  /// **Limitação declarada.** A contagem do exercício tem a idade do último
  /// encerramento. Grupamento ou desdobramento posterior a ele não aparece
  /// aqui, e o preço de hoje já o reflete. O erro daí é o da ação societária;
  /// o erro que ela substitui era de três ordens de grandeza.
  double? get reconciledShares {
    final doExercicio = _positive(sharesOutstandingAsOf);
    final corrente = _positive(sharesOutstanding);
    if (doExercicio == null) return corrente;
    if (corrente == null) return doExercicio;

    final arbitro = _sharesFromEarnings;
    if (arbitro != null) {
      final peloExercicio = _logDistance(doExercicio, arbitro);
      final pelaCorrente = _logDistance(corrente, arbitro);
      final melhor = peloExercicio <= pelaCorrente ? doExercicio : corrente;
      final distancia = peloExercicio <= pelaCorrente ? peloExercicio : pelaCorrente;
      if (distancia <= _reconciliationBand) return melhor;
    }
    return doExercicio;
  }

  /// `true` quando as duas contagens discordam além de uma ação societária
  /// plausível — o que a cascata registra como aviso.
  bool get sharesDisagree {
    final a = _positive(sharesOutstandingAsOf);
    final b = _positive(sharesOutstanding);
    if (a == null || b == null) return false;
    return _logDistance(a, b) > _reconciliationBand;
  }

  /// Contagem implícita no lucro por ação publicado: `N = lucro ÷ LPA`.
  double? get _sharesFromEarnings {
    final lucro = netIncome;
    final lpa = earningsPerShare;
    if (lucro == null || lpa == null) return null;
    if (lpa.abs() < 1e-9) return null;
    final n = lucro / lpa;
    return (n.isFinite && n > 0) ? n : null;
  }

  /// Tolerância da conciliação, em razão: aceita de 1/1,5 a 1,5.
  static const double _reconciliationBand = 1.5;

  /// Distância multiplicativa entre duas contagens, sempre `>= 1`.
  ///
  /// Simétrica por construção — `d(a,b) == d(b,a)` —, o que é o que se quer de
  /// uma comparação entre duas medidas da mesma grandeza.
  static double _logDistance(double a, double b) => a >= b ? a / b : b / a;

  /// O valor quando é positivo e finito; `null` caso contrário.
  static double? _positive(double? v) =>
      (v != null && v.isFinite && v > 0) ? v : null;

  /// Magnitude abaixo da qual um valor publicado é resíduo, não número.
  ///
  /// A fonte devolve zero para linha que não se aplica — banco não tem NOPAT —,
  /// mas o zero chega às vezes como resíduo de ponto flutuante. Comparar com
  /// `!= 0` trataria `1e-16` como lucro operacional legítimo, e o fluxo
  /// projetado sairia esvaziado sem que nada avisasse.
  static const double _residuo = 1.0;

  /// NOPAT publicado, ou derivado por `EBIT × (1 − alíquota efetiva)`.
  ///
  /// O teste é de **magnitude**, nunca de igualdade: dinheiro em ponto flutuante
  /// não se compara com `==`.
  double? get nopatOrDerived {
    final publicado = nopat;
    if (publicado != null && publicado.abs() > _residuo) return publicado;
    final op = ebit;
    final t = effectiveTaxRate;
    if (op == null || t == null) return null;
    final v = op * (1 - t);
    return v.isFinite ? v : null;
  }

  /// Capital externo que entrou no exercício, contra o lucro de [anterior].
  ///
  /// Da relação de excedente limpo `ΔPL = lucro − dividendos + emissão + OCI`:
  /// se o patrimônio cresceu mais do que a empresa lucrou, o excesso não pode ter
  /// vindo de lucro retido.
  ///
  /// **Por que não `Δ capital social`.** Ele sobe também por incorporação de
  /// reservas, que não traz dinheiro novo: a WEGE3 acusaria R$ 9,0 bi de emissão
  /// sobre base de R$ 6,3 bi, sendo que as duas maiores altas vieram com reservas
  /// de lucro caindo junto. Medir pelo patrimônio é imune, porque bonificação não
  /// altera o PL.
  ///
  /// - [anterior]: exercício imediatamente anterior. Devolve `null` quando
  ///   qualquer das duas bases falta.
  double? externalCapitalAgainst(
    FundamentalsSnapshot anterior, {
    required bool viaFirma,
  }) {
    final atual = viaFirma ? investedCapital : equityBookValue;
    final antes = viaFirma ? anterior.investedCapital : anterior.equityBookValue;
    if (atual == null || antes == null) return null;
    final lucro = viaFirma ? nopatOrDerived : netIncome;
    final excesso = (atual - antes) - (lucro ?? 0);
    return excesso > 0 ? excesso : 0.0;
  }
}
