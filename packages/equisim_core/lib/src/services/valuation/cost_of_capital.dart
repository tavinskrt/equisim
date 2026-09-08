/// Como o custo de capital foi obtido — rastreabilidade exigida pela
/// reprodutibilidade acadêmica.
enum BetaSource {
  /// Calculado pelo próprio domínio contra o ^BVSP, janela declarada.
  computed,

  /// Informado pela fonte externa (janela e índice não documentados).
  apiProvided,

  /// Arbitrado pelo usuário.
  manual,
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
  /// Decide duas coisas, e as duas pela mesma razão econômica — quanto do
  /// serviço da dívida o resultado operacional sustenta:
  ///
  /// - o **prêmio de crédito** sobre a taxa livre de risco, que é o custo da
  ///   dívida efetivamente aplicado — ver [syntheticSpread];
  /// - a **alíquota do escudo fiscal**, sempre: dedução de juros acima do lucro
  ///   operacional não abate imposto no exercício — ver [effectiveTaxShield].
  final double? interestCoverage;

  /// Declara a estrutura de capital. Todos os valores monetários devem estar
  /// na **mesma escala** — misturar reais com milhares distorce os pesos.
  const CostOfCapital({
    required this.capm,
    required this.costOfDebt,
    required this.taxRate,
    required this.equityValue,
    required this.debtValue,
    this.interestCoverage,
  });

  /// Prêmio de crédito máximo admitido sobre a taxa livre de risco.
  ///
  /// Dez pontos percentuais acomodam desde a empresa de primeira linha até a
  /// alavancada; acima disso a empresa não estaria se financiando.
  static const double maxCreditSpread = 0.10;

  /// Ke, repassado do CAPM. Atalho para `capm.costOfEquity`.
  double get costOfEquity => capm.costOfEquity;

  /// Prêmio de crédito por faixa de cobertura de juros — classificação
  /// sintética, no formato de Damodaran.
  ///
  /// **Por que existe.** A razão observada `despesa financeira ÷ dívida bruta`
  /// é inutilizável na maioria dos casos: medido em 07/09/2026 sobre o universo
  /// elegível, **70 dos 120 avaliados** caíam fora da banda defensável, com
  /// valores de até 100% ao ano. O numerador não é juro de dívida — carrega
  /// arrendamento (IFRS 16 / CPC 06 R2), variação cambial e monetária —, e o
  /// denominador ignora dívida que a fonte não publica.
  ///
  /// Antes, todos esses 70 recebiam **o mesmo** `Rf + 10%`, que é o teto: a
  /// WEGE3, de caixa líquido, ficava com o custo de dívida de uma empresa em
  /// pré-falência. A cobertura de juros distingue os dois, com o dado que já
  /// existe no exercício.
  ///
  /// **O teto da tabela é [maxCreditSpread]**, de modo que a faixa de prêmios
  /// continua confinada onde a banda anterior confinava — o que muda é que
  /// dentro dela há ordenação em vez de um único valor.
  ///
  /// **Limite declarado:** a cobertura usa a mesma despesa financeira
  /// contaminada, e portanto subestima a cobertura de quem tem arrendamento
  /// relevante ou dívida em moeda estrangeira. O erro que ela substitui era
  /// pior: nenhuma discriminação.
  static const List<({double minCoverage, double spread})> creditSpreads = [
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
  ///
  /// Devolve [maxCreditSpread] sem cobertura medível, com cobertura não
  /// positiva — EBIT negativo — ou abaixo da última faixa: os três casos são o
  /// de quem não cobre o próprio serviço da dívida.
  static double syntheticSpread(double? coverage) {
    if (coverage == null || !coverage.isFinite) return maxCreditSpread;
    for (final faixa in creditSpreads) {
      if (coverage >= faixa.minCoverage) return faixa.spread;
    }
    return maxCreditSpread;
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
  /// A cobertura de juros responde a essa pergunta com o dado do próprio
  /// exercício, e é o método de Damodaran. O observado continua sendo medido e
  /// entra no resultado como conferência — ver [costOfDebtWasClamped].
  double get effectiveCostOfDebt =>
      capm.riskFreeRate + syntheticSpread(interestCoverage);

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
