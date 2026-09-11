/// Como o custo de capital foi obtido — rastreabilidade exigida pela
/// reprodutibilidade acadêmica.
enum BetaSource {
  /// Calculado pelo próprio domínio contra o ^BVSP, janela declarada.
  computed,

  /// Informado pela fonte externa (janela e índice não documentados).
  apiProvided,

  /// Arbitrado pelo usuário.
  manual,

  /// Regressão **encolhida** em direção ao prior transversal, por precisão.
  ///
  /// Só aparece quando o encolhimento de fato moveu o número — peso do
  /// estimador individual abaixo de 1. Medido em 10/09/2026: 23 dos 363
  /// papéis, com peso mediano de 0,98 no universo inteiro.
  shrunk,
}

/// Como o prêmio de risco de mercado foi definido.
enum MarketPremiumSource {
  /// Parametrizado (padrão do sistema: 5–6% a.a.).
  parameterized,

  /// Média histórica do índice na janela declarada.
  historical,
}

/// Insumos do CAPM.
class CapmInputs {
  /// Taxa livre de risco anual, em fração. Deve vir do CDI observado.
  final double riskFreeRate;

  /// Sensibilidade do ativo ao mercado. `1.0` significa neutro.
  final double beta;

  /// Origem de [beta] — entra nos avisos do resultado, porque um beta
  /// arbitrado e um calculado não sustentam a mesma conclusão.
  final BetaSource betaSource;

  /// Prêmio de risco de mercado (Rm − Rf) anual, em fração.
  final double marketPremium;
  /// Origem de [marketPremium].
  final MarketPremiumSource premiumSource;

  /// Declara os insumos. Não valida faixa — beta negativo e prêmio nulo são
  /// entradas legítimas para análise de sensibilidade.
  const CapmInputs({
    required this.riskFreeRate,
    required this.beta,
    required this.marketPremium,
    this.betaSource = BetaSource.computed,
    this.premiumSource = MarketPremiumSource.parameterized,
  });

  /// Prêmio padrão para o Brasil: 5,5% a.a., ponto médio da faixa de 5–6%
  /// adotada como parâmetro do projeto.
  static const double defaultMarketPremium = 0.055;

  /// Ke = Rf + β · (Rm − Rf)
  double get costOfEquity => riskFreeRate + beta * marketPremium;

  /// Os mesmos insumos com outra taxa livre de risco.
  ///
  /// Existe para montar o custo de capital **de equilíbrio**: o mesmo beta e o
  /// mesmo prêmio, sobre a taxa estrutural em vez da corrente. É o que sustenta
  /// a estrutura a termo do desconto sem duplicar a montagem do WACC.
  CapmInputs withRiskFree(double rate) => CapmInputs(
        riskFreeRate: rate,
        beta: beta,
        marketPremium: marketPremium,
        betaSource: betaSource,
        premiumSource: premiumSource,
      );
}

/// Custo de capital da empresa.
///
/// **Ponto metodológico**: FCFF é fluxo disponível a *todos* os provedores de
/// capital e por isso deve ser descontado ao **WACC**, não ao Ke. Descontar
/// FCFF ao custo de capital próprio superestimaria a taxa e subavaliaria a
/// empresa — erro comum e facilmente cobrável em banca. O Ke sozinho só é
/// consistente com FCFE.
class CostOfCapital {
  final CapmInputs capm;

  /// Custo da dívida antes de impostos **como observado**, em fração.
  ///
  /// Vem de `despesa financeira ÷ dívida bruta`, e a fonte torna essa razão
  /// pouco confiável: a despesa financeira publicada nem sempre é o juro da
  /// dívida, e a dívida bruta nem sempre está completa. Medido em 21/08/2026:
  /// PETR4 saiu com 0,9% a.a. e WEGE3 com 47,3% a.a. — nenhum dos dois é um
  /// custo de dívida. Por isso o valor usado no WACC é [effectiveCostOfDebt],
  /// não este.
  final double costOfDebt;

  /// Alíquota efetiva de imposto, em fração.
  final double taxRate;

  /// Valor de mercado do equity.
  final double equityValue;

  /// Dívida bruta.
  final double debtValue;

  /// Cobertura de juros, `EBIT ÷ despesa financeira`. `null` quando não medível.
  ///
  /// Decide a alíquota do escudo fiscal — ver [effectiveTaxShield] — e, **quando
  /// a despesa financeira é utilizável**, entra também no prêmio de crédito, em
  /// união com a alavancagem (ver [syntheticSpread]).
  ///
  /// No escudo a contaminação por arrendamento e variação cambial não atrapalha,
  /// porque as duas também são dedutíveis e a pergunta ali é se há lucro
  /// tributável que absorva a dedução.
  final double? interestCoverage;

  /// Alavancagem, `dívida líquida ÷ EBITDA`. `null` sem EBITDA positivo.
  ///
  /// **Decide o prêmio de crédito** — ver [syntheticSpread]. Substituiu a
  /// cobertura de juros nesse papel em 08/09/2026, e o motivo está medido no
  /// doc de [syntheticSpread].
  final double? netDebtToEbitda;

  /// Declara a estrutura de capital. Todos os valores monetários devem estar
  /// na **mesma escala** — misturar reais com milhares distorce os pesos.
  const CostOfCapital({
    required this.capm,
    required this.costOfDebt,
    required this.taxRate,
    required this.equityValue,
    required this.debtValue,
    this.interestCoverage,
    this.netDebtToEbitda,
  });

  /// Prêmio de crédito máximo admitido sobre a taxa livre de risco.
  ///
  /// Dez pontos percentuais acomodam desde a empresa de primeira linha até a
  /// alavancada; acima disso a empresa não estaria se financiando.
  static const double maxCreditSpread = 0.10;

  /// Ke, repassado do CAPM. Atalho para `capm.costOfEquity`.
  double get costOfEquity => capm.costOfEquity;

  /// Prêmio de crédito por faixa de **alavancagem** — classificação sintética.
  ///
  /// **Por que a razão observada não serve.** `despesa financeira ÷ dívida
  /// bruta` é inutilizável na maioria dos casos: medido sobre o universo
  /// elegível, **70 dos 120 avaliados** caíam fora da banda defensável, com
  /// valores de até 100% ao ano. O numerador não é juro de dívida — carrega
  /// arrendamento (IFRS 16 / CPC 06 R2), variação cambial e monetária.
  ///
  /// **Por que a cobertura de juros também não serve.** Ela foi o primeiro
  /// substituto, e herdava o defeito: a despesa contaminada está no denominador
  /// dela. Medido em 08/09/2026 sobre os mesmos avaliados, o resultado era
  /// sistematicamente errado, e errado contra as empresas mais sólidas:
  ///
  /// | Ativo | Cobertura | Dívida líq./EBITDA | Prêmio pela cobertura |
  /// |---|---|---|---|
  /// | ABEV3 | 3,77x | **−0,57x** (caixa líquido) | 2,4 p.p. |
  /// | WEGE3 | 3,68x | **−0,30x** (caixa líquido) | 2,4 p.p. |
  /// | RADL3 | 1,50x | **0,70x** | 7,5 p.p. |
  /// | SAPR11 | 0,76x | **0,60x** | **10,0 p.p.** (o teto) |
  /// | AZZA3 | 1,26x | **1,17x** | 7,5 p.p. |
  ///
  /// Empresa com caixa líquido pagando prêmio de dois pontos e saneamento
  /// regulado com 0,6x de alavancagem pagando o teto não é ordenação de crédito
  /// — é o eco da contaminação.
  ///
  /// **A alavancagem não passa pela despesa financeira.** Dívida líquida e
  /// EBITDA são os mesmos campos que a ponte de equity e a base de capital já
  /// usam. A distribuição no universo avaliado é bem-comportada: mediana de
  /// 1,64x, p90 de 3,55x, três ativos acima de 4x e dezoito com caixa líquido.
  ///
  /// As faixas seguem a convenção de covenant do crédito corporativo
  /// brasileiro, e o teto continua sendo [maxCreditSpread].
  static const List<({double maxLeverage, double spread})> creditSpreads = [
    (maxLeverage: 0.00, spread: 0.010),
    (maxLeverage: 1.00, spread: 0.013),
    (maxLeverage: 2.00, spread: 0.018),
    (maxLeverage: 2.50, spread: 0.024),
    (maxLeverage: 3.00, spread: 0.031),
    (maxLeverage: 3.50, spread: 0.040),
    (maxLeverage: 4.00, spread: 0.055),
    (maxLeverage: 5.00, spread: 0.075),
  ];

  /// Prêmio de crédito para a alavancagem informada.
  ///
  /// Devolve [maxCreditSpread] sem alavancagem medível — o que inclui EBITDA
  /// não positivo — e acima da última faixa: os dois casos são o de quem não
  /// sustenta o próprio endividamento.
  static double leverageSpread(double? leverage) {
    if (leverage == null || !leverage.isFinite) return maxCreditSpread;
    for (final faixa in creditSpreads) {
      if (leverage <= faixa.maxLeverage) return faixa.spread;
    }
    return maxCreditSpread;
  }

  /// Prêmio de crédito por faixa de cobertura de juros, no formato de
  /// Damodaran.
  ///
  /// **Só vale quando a despesa financeira é utilizável** — ver
  /// [syntheticSpread]. Ela mede o que a alavancagem não mede: a empresa
  /// consegue pagar o juro que contratou, e não só quanto deve.
  static const List<({double minCoverage, double spread})> coverageSpreads = [
    (minCoverage: 8.50, spread: 0.010),
    (minCoverage: 6.50, spread: 0.013),
    (minCoverage: 5.50, spread: 0.016),
    (minCoverage: 4.25, spread: 0.020),
    (minCoverage: 3.00, spread: 0.024),
    (minCoverage: 2.50, spread: 0.031),
    (minCoverage: 2.00, spread: 0.040),
    (minCoverage: 1.50, spread: 0.055),
    (minCoverage: 1.25, spread: 0.075),
    (minCoverage: 0.80, spread: 0.090),
  ];

  /// Prêmio de crédito para a cobertura informada.
  static double coverageSpread(double? coverage) {
    if (coverage == null || !coverage.isFinite) return maxCreditSpread;
    for (final faixa in coverageSpreads) {
      if (coverage >= faixa.minCoverage) return faixa.spread;
    }
    return maxCreditSpread;
  }

  /// Prêmio de crédito aplicado, pelas duas razões e por quem pode falar.
  ///
  /// **As duas medem coisas diferentes e falham de jeitos diferentes.**
  /// A alavancagem mede o estoque da dívida e usa dado limpo; a cobertura mede
  /// a capacidade de serviço e usa a despesa financeira, que a fonte contamina
  /// com arrendamento e variação cambial. Usar só uma delas erra dos dois
  /// lados, e as duas medições estão registradas:
  ///
  /// - **Só cobertura:** a ABEV3 e a WEGE3, de caixa líquido, pagavam prêmio de
  ///   2,4 p.p.; a SAPR11, com 0,60x de alavancagem, pagava o **teto** de
  ///   10 p.p. porque a cobertura contaminada dela dava 0,76x.
  /// - **Só alavancagem:** a MOVI3, cujo EBIT não cobre o juro que ela de fato
  ///   paga — despesa de R$ 3,59 bi sobre R$ 21,9 bi de dívida, 16,4% ao ano,
  ///   plenamente plausível —, ganhava 5 p.p. de desconto e o potencial dela
  ///   saltava de +170% para +622%.
  ///
  /// **Quem decide se a cobertura pode falar é a própria despesa financeira.**
  /// Quando a razão observada `despesa ÷ dívida` cai dentro da banda
  /// defensável, a despesa é juro de dívida e a cobertura é informação: vale a
  /// **mais exigente** das duas, porque estoque alto e serviço apertado são
  /// riscos que se somam. Quando cai fora, a despesa está medindo outra coisa e
  /// a cobertura sai da conta: sobra a alavancagem, que não passa por ela.
  ///
  /// - [leverage]: dívida líquida sobre EBITDA.
  /// - [coverage]: EBIT sobre despesa financeira.
  /// - [observedCostOfDebt]: a razão observada, que arbitra.
  /// - [riskFreeRate]: piso da banda de plausibilidade.
  static double syntheticSpread({
    required double? leverage,
    required double? coverage,
    required double observedCostOfDebt,
    required double riskFreeRate,
  }) {
    final porAlavancagem = leverageSpread(leverage);
    final despesaUtilizavel = observedCostOfDebt >= riskFreeRate &&
        observedCostOfDebt <= riskFreeRate + maxCreditSpread;
    if (!despesaUtilizavel) return porAlavancagem;
    final porCobertura = coverageSpread(coverage);
    return porCobertura > porAlavancagem ? porCobertura : porAlavancagem;
  }

  /// Custo da dívida efetivamente aplicado: `Rf + spread(cobertura)`.
  ///
  /// **É sempre a classificação sintética, e a uniformidade é o ponto.** A
  /// alternativa — usar o observado quando ele cai dentro da banda defensável e
  /// a tabela quando cai fora — reintroduz exatamente o defeito que este motor
  /// passou a caçar: um corte binário sobre grandeza contínua. Duas empresas de
  /// mesma cobertura recebiam custos de dívida diferentes conforme a razão
  /// observada de cada uma caísse de um lado ou de outro da borda, e a borda não
  /// tem conteúdo econômico.
  ///
  /// **O observado não sobrevive ao exame.** `despesa financeira ÷ dívida
  /// bruta` caía fora da banda em 70 dos 120 avaliados, e dentro dela carrega
  /// dois vieses de sinais opostos: para cima, arrendamento (IFRS 16 / CPC 06
  /// R2) e variação cambial, que não são captação; para baixo, dívida antiga a
  /// taxa velha e dívida que a fonte não publica no denominador. Nenhum dos dois
  /// é o que o WACC pede, que é o custo **marginal** de captar hoje.
  ///
  /// As duas razões respondem a essa pergunta com dado do próprio exercício, e
  /// a própria despesa financeira arbitra qual delas pode falar — ver
  /// [syntheticSpread]. O observado continua sendo medido e entra no resultado
  /// como conferência — ver [costOfDebtWasClamped].
  double get effectiveCostOfDebt =>
      capm.riskFreeRate +
      syntheticSpread(
        leverage: netDebtToEbitda,
        coverage: interestCoverage,
        observedCostOfDebt: costOfDebt,
        riskFreeRate: capm.riskFreeRate,
      );

  /// `true` quando o observado se afasta materialmente do estimado.
  ///
  /// Existe para que a interface declare a substituição em vez de apresentar o
  /// número estimado como se fosse o medido. O corte de 1 p.p. é o passo da
  /// própria tabela de prêmios: abaixo dele os dois números diriam a mesma
  /// coisa.
  bool get costOfDebtWasClamped =>
      (effectiveCostOfDebt - costOfDebt).abs() > 0.01;

  /// Capital total: equity mais dívida. Denominador dos pesos do WACC.
  double get totalCapital => equityValue + debtValue;

  /// Participação do capital próprio. **Degenera para `1.0`** quando o capital
  /// total é não positivo — sem estrutura conhecida, o WACC vira Ke, que é a
  /// hipótese conservadora.
  double get equityShare =>
      totalCapital > 0 ? equityValue / totalCapital : 1.0;

  /// Participação da dívida. Degenera para `0.0` no mesmo caso, mantendo
  /// `equityShare + debtShare == 1`.
  double get debtShare => totalCapital > 0 ? debtValue / totalCapital : 0.0;

  /// Alíquota do escudo fiscal efetivamente aplicada.
  ///
  /// **É a estatutária limitada pela capacidade de usá-la.** A dedução de juros
  /// só vale a alíquota cheia enquanto houver lucro tributável que a absorva:
  /// com `EBIT < despesa financeira`, a parcela excedente não abate imposto no
  /// exercício — vira prejuízo fiscal a compensar, cujo valor presente é menor.
  /// É o tratamento de Damodaran, e a razão de a cobertura entrar aqui além de
  /// entrar no prêmio de crédito.
  ///
  /// Sem cobertura medível vale a alíquota cheia, que é o caso normal de quem
  /// cobre os juros com folga.
  double get effectiveTaxShield {
    final c = interestCoverage;
    if (c == null || !c.isFinite) return taxRate;
    if (c >= 1.0) return taxRate;
    return taxRate * (c < 0 ? 0.0 : c);
  }

  /// WACC bruto: `E/(E+D)·Ke + D/(E+D)·Kd·(1 − t)`.
  double get rawWacc =>
      equityShare * costOfEquity +
      debtShare * effectiveCostOfDebt * (1.0 - effectiveTaxShield);

  /// WACC aplicado ao desconto, nunca abaixo da taxa livre de risco.
  ///
  /// O benefício fiscal da dívida pode, na aritmética, empurrar o WACC abaixo
  /// de Rf numa empresa muito alavancada. Descontar um fluxo de risco a menos
  /// que o soberano não é custo de oportunidade defensável, e o efeito sobre a
  /// perpetuidade é violento: é o que produzia preços justos várias vezes
  /// acima do mercado. O piso mantém o número no terreno econômico, e
  /// [waccWasFloored] existe para que a interface diga que isso aconteceu.
  double get wacc => rawWacc < capm.riskFreeRate ? capm.riskFreeRate : rawWacc;

  /// `true` quando o piso de [wacc] precisou agir.
  bool get waccWasFloored => rawWacc < capm.riskFreeRate;

  /// Empresa sem dívida: WACC degenera para Ke.
  factory CostOfCapital.unlevered(CapmInputs capm) => CostOfCapital(
        capm: capm,
        costOfDebt: 0.0,
        taxRate: 0.0,
        equityValue: 1.0,
        debtValue: 0.0,
      );
}
