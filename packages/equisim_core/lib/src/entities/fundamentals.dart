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

  /// Lucro operacional líquido de imposto, como a fonte o publica.
  ///
  /// **Ele não é um dado independente do EBIT.** Conferido em 08/09/2026 sobre
  /// o cache de produção: `nopat = EBIT × 0,66` em **4.572 de 4.572**
  /// exercícios, e os dois campos estão preenchidos exatamente nos mesmos
  /// 4.580. A fonte aplica a alíquota estatutária brasileira de 34% e publica
  /// o resultado — de modo que o fluxo da firma já chega apurado a ela, e o
  /// recuo de [nopatOrDerived] para `EBIT × (1 − alíquota efetiva)` nunca é
  /// alcançado com este cache.
  ///
  /// É por isso que o escudo fiscal do WACC usa a mesma alíquota estatutária:
  /// ver `ValuationParameters.statutoryTaxRate`.
  ///
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

  /// Participação dos **não controladores** no patrimônio consolidado.
  ///
  /// A demonstração consolida 100% das controladas, e o acionista da
  /// controladora não é dono de tudo isso. O fluxo da firma carrega o
  /// resultado inteiro; a ponte precisa devolver a parte que não é dele.
  final double? minorityInterest;

  /// Resultado de **equivalência patrimonial**, em reais do exercício.
  ///
  /// Na DRE brasileira ele entra em "Outras Receitas e Despesas Operacionais",
  /// **acima** do resultado antes do financeiro — de modo que já está dentro
  /// do EBIT publicado. Medido em 10/09/2026 no ITSA4: EBIT de R$ 18,1 bi
  /// contra equivalência de R$ 17,5 bi.
  ///
  /// Isso tem duas consequências opostas, e as duas importam:
  ///
  /// - **não se soma a participação societária ao valor da firma**, porque o
  ///   resultado dela já está no fluxo descontado — somá-la contaria duas
  ///   vezes;
  /// - **não se tributa esse pedaço de novo**: a equivalência chega líquida do
  ///   imposto pago pela investida, e aplicar a alíquota da controladora sobre
  ///   ela cobra o mesmo tributo duas vezes.
  final double? equityIncomeResult;

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
    this.minorityInterest,
    this.equityIncomeResult,
  });

  /// Depreciação e amortização, derivada de EBITDA − EBIT.
  double? get depreciationAndAmortization {
    if (ebitda == null || ebit == null) return null;
    final da = ebitda! - ebit!;
    return da >= 0 ? da : null;
  }

  /// Alíquota efetiva de imposto, limitada a [0, 0.5] para conter distorções
  /// de exercícios com prejuízo ou créditos fiscais extraordinários.
  ///
  /// **A fonte grava a despesa com sinal negativo**, e a conta respeita isso
  /// desde 10/09/2026. Conferido pela identidade contábil no cache: a AALR3
  /// tem lucro antes de R$ 34,6 mi, `incomeTaxExpense` de −R$ 5,9 mi e lucro
  /// líquido de R$ 28,8 mi — a despesa **soma**. Num exercício de crédito o
  /// campo vem positivo: lucro antes de −R$ 7,9 mi, imposto de +R$ 22,6 mi e
  /// líquido de R$ 14,6 mi.
  ///
  /// A versão anterior usava `.abs()`, o que acertava o caso comum pelo motivo
  /// errado e **errava o crédito**: o exercício em que a empresa recuperou
  /// imposto saía com alíquota positiva, e o `clamp` — que existe justamente
  /// para conter a distorção — nunca chegava a agir, porque o sinal já tinha
  /// sido apagado. Negar o sinal em vez de tirar o módulo acerta os dois: o
  /// crédito produz razão negativa, e o piso de zero faz o que prometia.
  ///
  /// **Tirar o `.abs()` sem negar seria pior que mantê-lo.** Medido: a
  /// alíquota mediana do universo iria a 0,0% e 98 dos 122 preços justos se
  /// moveriam, porque toda despesa normal viraria razão negativa.
  ///
  /// A distinção era inócua enquanto isto só alimentava o ramo de recuo de
  /// [nopatOrDerived], nunca alcançado com o cache atual. Passou a pesar com
  /// a decisão 37, que tornou a alíquota efetiva a base tributária do fluxo
  /// da firma.
  double? get effectiveTaxRate {
    if (incomeBeforeTax == null || incomeTaxExpense == null) return null;
    if (incomeBeforeTax! <= 0) return null;
    final rate = -incomeTaxExpense! / incomeBeforeTax!;
    if (rate.isNaN || rate.isInfinite) return null;
    return rate.clamp(0.0, 0.5);
  }

  /// `true` quando o exercício traz demonstração de resultado.
  ///
  /// **A fonte publica o exercício com o balanço preenchido e o resultado
  /// inteiro zerado.** Medido em 10/09/2026: acontece em 4 dos 376 ativos, em
  /// 7 exercícios, e nos quatro o patrimônio do mesmo exercício tem valor —
  /// prova de que o exercício existe e de que o que falta é a demonstração,
  /// não a empresa. A TIMS3 aparecia com receita, EBIT, lucro e LPA zerados e
  /// patrimônio líquido de R$ 24 bilhões, tendo tido EBIT de R$ 4,7 bi dois
  /// exercícios antes.
  ///
  /// **Zero é um número, e ausência não é zero.** Lido como zero, o exercício
  /// vira base de avaliação nula — e o ativo é recusado por "os dados não
  /// sustentam nenhuma das duas vias", que é a mensagem errada para um dado
  /// que a fonte não entregou.
  ///
  /// O teste são **os quatro juntos**: receita, resultado operacional, lucro
  /// líquido e lucro por ação. Zerar um deles é possível — holding sem
  /// receita, empresa no zero a zero, exercício sem lucro por ação publicado.
  /// Zerar os quatro com balanço preenchido, não.
  /// **A comparação é de magnitude, e não de igualdade.** O zero da fonte às
  /// vezes chega como resíduo de ponto flutuante, e `== 0` trataria `1e-16`
  /// como resultado publicado. Os agregados usam [_residuo]; o lucro por ação
  /// usa [_residuoPorPapel], porque um LPA de R$ 0,50 é legítimo e um real
  /// inteiro de corte o descartaria.
  bool get hasIncomeStatement {
    bool vazio(double? v, double residuo) =>
        v == null || !v.isFinite || v.abs() <= residuo;
    return !(vazio(totalRevenue, _residuo) &&
        vazio(ebit, _residuo) &&
        vazio(netIncome, _residuo) &&
        vazio(earningsPerShare, _residuoPorPapel));
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

  /// Cobertura de juros: `EBIT ÷ despesa financeira`.
  ///
  /// **Serve ao escudo fiscal, e só a ele** — ver
  /// `CostOfCapital.effectiveTaxShield`. Ali a contaminação por arrendamento e
  /// variação cambial não atrapalha, e até ajuda: a pergunta é se há lucro
  /// tributável que absorva a dedução, e juro de arrendamento e perda cambial
  /// **também são dedutíveis**. O total é a grandeza certa para essa conta.
  ///
  /// O prêmio de crédito passou a vir da alavancagem — ver [netDebtToEbitda] —,
  /// porque ali a contaminação distorce.
  ///
  /// Devolve `null` sem EBIT ou sem despesa financeira, e **zero** quando o
  /// EBIT é negativo: quem não gera resultado operacional não cobre juro
  /// nenhum, e é a leitura que a tabela de prêmios espera.
  double? get interestCoverage {
    final op = ebit;
    final juros = interestExpense;
    if (op == null || juros == null) return null;
    final d = juros.abs();
    if (d <= 0) return null;
    if (op <= 0) return 0.0;
    final c = op / d;
    return c.isFinite ? c : null;
  }

  /// Alavancagem: dívida líquida sobre EBITDA.
  ///
  /// **É o direcionador da classificação sintética de crédito**, no lugar da
  /// cobertura de juros. O motivo é de qualidade de insumo: a cobertura tem no
  /// denominador a mesma despesa financeira que carrega arrendamento e variação
  /// cambial, e usar um número contaminado para consertar um problema causado
  /// por essa contaminação é circular. Medido em 08/09/2026 sobre os avaliados:
  /// a ABEV3 e a WEGE3, ambas de **caixa líquido**, apareciam com cobertura de
  /// 3,8x e 3,7x e recebiam prêmio de 2,4 p.p.; a SAPR11, com 0,60x de
  /// alavancagem, recebia o **teto** de 10 p.p. porque a cobertura dela dava
  /// 0,76x.
  ///
  /// Dívida líquida e EBITDA são os mesmos campos que a ponte e a base já usam,
  /// e nenhum dos dois passa pela despesa financeira. A distribuição no universo
  /// avaliado é bem-comportada — mediana de 1,64x, p90 de 3,55x, apenas três
  /// ativos acima de 4x e dezoito com caixa líquido.
  ///
  /// Devolve `null` sem EBITDA positivo: ali a razão não tem leitura, e quem
  /// consome trata como o pior caso.
  double? get netDebtToEbitda {
    final e = ebitda;
    if (e == null || e <= 0) return null;
    final r = netDebt / e;
    return r.isFinite ? r : null;
  }

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
      if (distancia <= reconciliationBand) return melhor;
    }
    return doExercicio;
  }

  /// Unidades negociadas implícitas no valor de mercado: `VM ÷ preço`.
  ///
  /// **É a contagem que forma o preço com que o preço justo é comparado**, e
  /// por isso é a única defensável no divisor da ponte por papel. Já vem na
  /// unidade negociada: a fonte publica [marketCap] e a cotação na mesma
  /// convenção — por *unit* onde a *unit* é o que se negocia —, de modo que o
  /// quociente dispensa a razão de unidade que a contagem por ação exige.
  ///
  /// **O que isso faz com o potencial.** Sendo `P_0 = E ÷ (VM ÷ P_mkt)`, o
  /// potencial vira `E ÷ VM − 1`: a comparação entre o valor do capital próprio
  /// que o modelo apura e o que o mercado atribui, **sem contagem de ação
  /// nenhuma no caminho**. Desdobramento, grupamento, *unit* e registro
  /// corrompido saem da conta por construção.
  ///
  /// **Por que [reconciledShares] não serve aqui, e continua servindo lá.** O
  /// árbitro `N = lucro ÷ LPA` compara duas contagens usando dois campos das
  /// **mesmas demonstrações**, e por isso só pode confirmar a contagem do
  /// exercício — o que é o certo para reconstituir patrimônio e capital
  /// investido, e foi verificado: `VPA × N_exercício` reproduz o patrimônio
  /// publicado em 4.461 de 4.462 exercícios do cache, e a contagem corrente o
  /// reproduz em **nenhum**. Mas o preço de tela não se forma na escala das
  /// demonstrações, e adotar a do exercício no divisor errava por mais de 5% em
  /// **30 dos 120 avaliados** — a MOVI3 por 2,65x e a B3SA3 por 1,49x.
  ///
  /// - [marketPrice]: cotação da unidade negociada, na mesma data de [marketCap].
  ///
  /// Devolve `null` sem valor de mercado ou sem preço utilizável.
  double? sharesFromMarketCap(double marketPrice) {
    final vm = marketCap;
    if (vm == null || !vm.isFinite || vm <= 0) return null;
    if (!marketPrice.isFinite || marketPrice <= 0) return null;
    final n = vm / marketPrice;
    return n.isFinite && n > 0 ? n : null;
  }

  /// `true` quando as duas contagens discordam além de uma ação societária
  /// plausível — o que a cascata registra como aviso.
  bool get sharesDisagree {
    final a = _positive(sharesOutstandingAsOf);
    final b = _positive(sharesOutstanding);
    if (a == null || b == null) return false;
    return _logDistance(a, b) > reconciliationBand;
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
  ///
  /// Pública porque a ponte por papel usa a **mesma** banda para decidir se as
  /// duas candidatas a divisor concordam — ver `ValuationCascade.quotedShares`.
  /// Duas cópias do mesmo limiar divergiriam na primeira recalibragem.
  static const double reconciliationBand = 1.5;

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

  /// Magnitude abaixo da qual um valor **por papel** é resíduo, não número.
  ///
  /// Um centavo. O corte dos agregados não serve aqui: um lucro por ação de
  /// R$ 0,50 é legítimo, e um real inteiro de corte o leria como ausência.
  static const double _residuoPorPapel = 0.01;

  /// NOPAT publicado, ou derivado por `EBIT × (1 − alíquota efetiva)`.
  ///
  /// O teste é de **magnitude**, nunca de igualdade: dinheiro em ponto flutuante
  /// não se compara com `==`.
  ///
  /// **O ramo derivado não é alcançado com o cache atual** — ver [nopat]. Ele
  /// fica como caminho de degradação para fonte que publique EBIT sem NOPAT, e
  /// quem o exercitar precisa saber que ali a convenção tributária muda: a
  /// efetiva do exercício no lugar da estatutária.
  double? get nopatOrDerived {
    final publicado = nopat;
    if (publicado != null && publicado.abs() > _residuo) return publicado;
    final op = ebit;
    final t = effectiveTaxRate;
    if (op == null || t == null) return null;
    final v = op * (1 - t);
    return v.isFinite ? v : null;
  }

  /// NOPAT recalculado a uma alíquota informada, no lugar da que a fonte usou.
  ///
  /// **Por que existe.** A fonte publica `NOPAT = EBIT × 0,66` — a alíquota
  /// estatutária brasileira aplicada a **toda** empresa, em 4.572 de 4.572
  /// exercícios do cache. Medido em 10/09/2026 sobre os 122 avaliados, a
  /// alíquota efetiva mediana é de **22,1%**, e 112 dos 122 pagam menos que a
  /// estatutária. JCP, incentivo regional, lucro presumido e prejuízo fiscal
  /// compensado não são exceção no Brasil: são o regime.
  ///
  /// A alíquota que entra aqui é **estrutural** — a mediana dos exercícios
  /// publicados, não a do último —, e a dispersão dentro da empresa é de
  /// 7,5 p.p. sobre quinze exercícios na mediana, o que a torna regime e não
  /// evento. Ver [`fluxo_explicito.md`](../../../../../docs/validacao/fluxo_explicito.md).
  ///
  /// **Não confundir com o escudo fiscal do WACC**, que continua na
  /// estatutária e deve continuar: a dedutibilidade do juro vale na margem, e
  /// a margem é a alíquota cheia. As duas alíquotas medem coisas diferentes e
  /// só coincidiam por acidente da fonte.
  ///
  /// **A equivalência patrimonial atravessa sem ser tributada de novo.** Ela
  /// está dentro do EBIT publicado e chega líquida do imposto da investida;
  /// multiplicar o EBIT inteiro por `(1 − τ)` cobra o tributo duas vezes sobre
  /// esse pedaço. O que se tributa é `EBIT − equivalência`. Ver
  /// [equityIncomeResult].
  ///
  /// Recua para [nopatOrDerived] sem EBIT ou sem alíquota informada.
  double? nopatAtRate(double? rate) {
    final op = ebit;
    if (op == null || rate == null || !rate.isFinite) return nopatOrDerived;
    final v = op * (1 - rate) + taxableEquityIncome * rate;
    return v.isFinite ? v : nopatOrDerived;
  }

  /// Equivalência patrimonial utilizável na conta do tributo, ou zero.
  ///
  /// **Só o lado positivo.** Equivalência negativa é prejuízo da investida, e
  /// ela reduz o EBIT sem ter gerado crédito tributário na controladora —
  /// devolver imposto sobre ela inventaria caixa. O tratamento é assimétrico
  /// de propósito, e é a direção conservadora.
  double get taxableEquityIncome {
    final e = equityIncomeResult;
    if (e == null || !e.isFinite || e <= 0) return 0.0;
    final op = ebit;
    // Não pode passar do próprio EBIT: acima disso a operação dá prejuízo e a
    // conta deixaria o NOPAT maior que o resultado que o gerou.
    if (op == null || !op.isFinite || op <= 0) return 0.0;
    return e > op ? op : e;
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
