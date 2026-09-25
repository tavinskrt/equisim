import 'dart:math' as math;

import '../audit/audit_recorder.dart';
import '../audit/calculation_trace.dart';
import '../entities/fundamentals.dart';
import '../entities/price_series.dart';
import '../entities/valuation.dart';
import '../failures/failure.dart';
import '../failures/result.dart';
import '../services/valuation/calibrated_band.dart';
import '../services/valuation/capital_base.dart';
import '../services/valuation/concession_sectors.dart';
import '../services/valuation/financial_sectors.dart';
import '../services/valuation/peer_multiples.dart';
import '../services/valuation/cost_of_capital.dart';
import '../services/valuation/cyclical_sectors.dart';
import '../services/valuation/dcf.dart';
import '../services/valuation/eligibility.dart';
import '../services/valuation/growth_estimator.dart';
import '../services/valuation/growth_guards.dart';
import '../services/valuation/levered_rates.dart';
import '../services/valuation/moat_fixed_point.dart';
import '../services/valuation/scenario_engine.dart';
import '../services/valuation/yield_curve.dart';
import '../time/point_in_time_view.dart';
import '../value_objects/money.dart';
import '../value_objects/ticker.dart';

/// Insumos já resolvidos para uma avaliação.
///
/// Reunir tudo aqui mantém a cascata **pura e síncrona**: ela decide qual
/// modelo aplicar sem tocar em rede, o que permite testá-la exaustivamente e
/// executá-la dentro de uma isolate.
class ValuationInputs {
  /// Ativo a avaliar.
  final Ticker ticker;

  /// Data de referência. Define o corte *point-in-time* dos fundamentos.
  final DateTime asOf;

  /// Série completa de exercícios, **sem** filtro de publicação — o filtro é
  /// aplicado internamente por `PointInTimeView`.
  final List<FundamentalsSnapshot> fundamentals;

  /// Cotação na data de referência, em reais **por unidade negociada**.
  final double marketPrice;

  /// Insumos do CAPM já resolvidos, incluindo a origem do beta.
  final CapmInputs capm;

  /// Margem de segurança aplicada ao preço justo, em fração.
  final double marginOfSafety;

  /// Anos de projeção explícita.
  ///
  /// **Dez, por medição** ([decisão 115](../../../../../docs/decisoes/115-o-horizonte-fica-em-dez-anos-por-medicao.md)):
  /// a mediana do preço justo anda menos de 1% entre 5 e 20 anos, e o que muda
  /// é o peso do terminal — 57% a cinco anos, 8% a vinte.
  final int projectionYears;

  /// Como o cenário de desconto vira deslocamento do `Ke` na rota derivada
  /// (item B20, decisão 121). O padrão é o declarado; as outras duas são
  /// imposição de diagnóstico, para medir a largura da faixa sob cada leitura.
  final ScenarioTranslation scenarioTranslation;

  /// Valor a somar ao peso do capital próprio pelo minoritário, em reais —
  /// **imposição de diagnóstico do item B23**, e não caminho de produção.
  ///
  /// O peso do WACC estático é `divisor × preço`, que é o valor de mercado da
  /// **controladora**, enquanto o fluxo descontado é o consolidado. Este campo
  /// existe para medir o que mudaria se a fatia dos não controladores entrasse
  /// no denominador. `null` é o comportamento declarado.
  ///
  /// **O caminho resolvido não precisa dele**: a realavancagem pondera pelo
  /// capital próprio que o **modelo** produz — `V − D` sobre um fluxo
  /// consolidado —, que já inclui o minoritário. A assimetria é entre o
  /// estático e o resolvido, e não entre o motor e a teoria.
  final double? minorityEquityValue;

  /// Medianas de múltiplos dos pares do ativo, para a segunda leitura (item
  /// B5).
  ///
  /// **O núcleo não sabe calculá-las**: a mediana é do universo, e a cascata
  /// avalia um ativo por vez. Quem mede é `tool/multiplos_empacotar.dart`, que
  /// grava pacote versionado; quem carrega é o aplicativo. `null` desliga a
  /// triangulação, e a avaliação sai como sempre saiu.
  final PeerMultipleSet? peerMultiples;

  /// Chave do setor, em minúsculas: a do setor econômico da B3 quando o
  /// emissor é classificado (decisão 87), e a da fonte de preços no recuo.
  ///
  /// Entra na Porta 1, por [FinancialSectors]. `null`
  /// quando o perfil não pôde ser carregado, caso em que a Porta 1 não dispara e
  /// o roteamento cai na Porta 3 — degradação segura, porque o teste de fluxo
  /// sozinho já barra instituição financeira: BBAS3 e BPAC11 não têm NOPAT em
  /// exercício nenhum.
  final String? sectorKey;

  /// Subsetor como publicado — com acento e pontuação. Na taxonomia oficial da
  /// B3, "Subsetor / Segmento".
  ///
  /// Entra na precedência da Guarda 3 sobre a Guarda 1, e existe porque a chave
  /// setorial sozinha não separa o que precisa ser separado: `energia` reúne
  /// exploração de petróleo, que é commodity pura, e 28 elétricas, que são
  /// concessão regulada. Ver [CyclicalSectors].
  ///
  /// `null` quando o perfil não pôde ser carregado, caso em que a precedência
  /// recai apenas sobre a chave setorial.
  final String? industry;

  /// Série de cotações da janela, para o corte de liquidez da Porta 0.
  ///
  /// Opcional: sem ela — ou sem volume nela — o teste de liquidez é **omitido**,
  /// não reprovado. Recusar por dado ausente confundiria falta de informação com
  /// falta de liquidez.
  final PriceSeries? prices;

  /// `true` quando o ativo consta da lista externa de recuperação judicial.
  ///
  /// Vem de fora porque a fonte não publica a informação: `isActive` marca
  /// negociabilidade, não continuidade, e os 786 tickers do universo vêm todos
  /// com ele verdadeiro.
  final bool isDistressed;

  /// Inflação anual observada, em fração.
  ///
  /// É a âncora *top-down* da Saída 2, adotada quando o crescimento fundamental
  /// não é identificável e a retenção observada a financia.
  final double inflation;

  /// Taxa livre de risco **estrutural**, em fração — o destino do decaimento.
  ///
  /// O CAPM usa a taxa corrente, que é o custo de oportunidade de hoje. Mas o
  /// modelo não tem curva de juros, e descontar dez anos e uma perpetuidade por
  /// um indexador de um dia casa duração infinita com duração zero: no topo do
  /// ciclo monetário isso esmaga todo valor terminal, e no vale o infla.
  ///
  /// Esta é a média decenal do CDI, medida — não chumbada. Omiti-la faz cair
  /// para a taxa corrente, que reproduz o comportamento anterior.
  final double? declaredTerminalRiskFreeRate;

  /// Curva de juros observada, quando disponível (item A2, decisão 74).
  ///
  /// **Com ela, a taxa de cada ano da projeção é o forward de um ano da curva
  /// dos títulos prefixados**, e a da perpetuidade é o forward depois do fim
  /// da projeção. Sem ela, vale a interpolação linear entre o CDI corrente e
  /// [declaredTerminalRiskFreeRate], que é o comportamento anterior.
  ///
  /// A diferença não é detalhe: medido nas coortes de 30/09 de 2021 a 2025, o
  /// forward longo da curva ficou de **2,9 a 4,5 p.p. acima** da média decenal
  /// do CDI que o motor usava como taxa de equilíbrio.
  final YieldCurve? riskFreeCurve;

  /// Contagem oficial de ações do registro da B3, quando disponível
  /// (item A3.3, decisão 83).
  ///
  /// **É o árbitro que a ponte por papel não tinha.** As duas contagens da
  /// fonte de preços divergem, e a regra do maior acertava onde a corrente
  /// estava errada para menos — MILS3, MEAL3 — e errava onde estava errada
  /// para mais: CTKA4 com 62 milhões contra 6,2 oficiais, FIEI3 com 48 contra
  /// 2,4, AUAU3 com 451 contra 861.
  final OfficialShareCount? officialShares;

  /// Taxa livre de risco estrutural, com o padrão já resolvido.
  ///
  /// Com [riskFreeCurve], é o forward da curva depois do fim da projeção.
  double get terminalRiskFreeRate =>
      riskFreeCurve?.terminalRate(projectionYears) ??
      declaredTerminalRiskFreeRate ??
      capm.riskFreeRate;

  /// Retorno terminal imposto de fora, no lugar do que o veredito de vantagem
  /// competitiva decidiria.
  ///
  /// **Existe para o DCF reverso e não é usado pelo aplicativo.** A pergunta
  /// que ele responde — qual `RONIC_∞` iguala o preço justo ao preço de
  /// mercado — exige varrer o retorno terminal pela cascata inteira, com o
  /// roteamento, as guardas e a ponte no lugar. Reimplementar o desconto no
  /// utilitário mediria outro motor.
  ///
  /// Nulo é o comportamento de produção: quem decide é
  /// [GrowthGuards.residualMoat]. Preenchido, ele **substitui** o veredito
  /// sem simular sua aprovação — a narrativa de vantagem competitiva continua
  /// atrelada ao veredito real, e o resultado declara a imposição.
  final double? terminalReturnOverride;

  /// Beta **desalavancado** do ativo, de `ShrunkBeta.unlevered`.
  ///
  /// É o que permite realavancar `Ke` ano a ano contra a estrutura de capital
  /// que a própria avaliação produz — ver `LeveredCostOfCapital` e a
  /// decisão 41. Nulo faz o desconto cair para a interpolação de dois pontos,
  /// que é o comportamento anterior e que **supõe alavancagem constante sem
  /// produzi-la**.
  final double? unleveredBeta;

  /// Crescimento explícito imposto de fora, no lugar do que as guardas
  /// decidiriam.
  ///
  /// **Existe para o teste A1 e não é usado pelo aplicativo.** As duas vias
  /// medem crescimento em bases de capital diferentes — capital investido de
  /// um lado, patrimônio do outro — e discordam em mais de 3 p.p. em 43 de 92
  /// ativos. Uma empresa, porém, tem **um** crescimento: a divergência é do
  /// medidor, não do negócio. Impor o mesmo dos dois lados é o que mede quanto
  /// da discordância entre as vias vem daí.
  final double? growthOverride;

  /// Fator de normalização da base imposto de fora.
  ///
  /// Mesmo propósito de [growthOverride]: uma empresa tem **uma** posição no
  /// ciclo, e as duas vias a medem separadamente — o fator sai de [0,8; 1,25]
  /// entre elas em 34 de 92 ativos.
  final double? baseFactorOverride;

  /// Via imposta de fora, no lugar do que o roteamento decidiria.
  ///
  /// **Existe para medir a discordância entre as duas vias, e não é usada pelo
  /// aplicativo.** A pós-condição da ponte escolhe uma das duas por um limiar,
  /// e as duas discordam por múltiplos — 12,7× na VBBR3. Medir a discordância
  /// exige avaliar as duas no mesmo ativo, o que o roteamento por construção
  /// impede.
  ///
  /// Preenchida, ela **também desliga a migração**: o ponto de impor uma via é
  /// medir aquela via, e deixar a pós-condição migrar de volta devolveria a
  /// outra. O resultado declara a imposição.
  final ValuationLane? laneOverride;

  /// Política do freio de reinvestimento imposta de fora.
  ///
  /// **Existe para o D4 e não é usada pelo aplicativo.** O resíduo entre o
  /// preço justo e o de mercado se decompõe rodando contrafactuais do freio, e
  /// rodá-los fora da cascata mede outro motor: em 10/09/2026 o laço de
  /// `tool/fluxo_explicito.dart` usava o teto da economia como crescimento
  /// perpétuo em 78 dos 120 e reinterpolava a taxa em vez de usar o caminho
  /// resolvido. Impondo a política aqui, o contrafactual atravessa as duas
  /// vias, a rota derivada e o ponto fixo — o motor de verdade.
  ///
  /// O resultado declara a imposição, como todas as outras costuras.
  final ReinvestmentPolicy? reinvestmentOverride;

  /// Convenção de chegada do caixa imposta de fora.
  ///
  /// Mesma razão do [reinvestmentOverride]: medir o que a convenção de meio de
  /// ano vale no universo exige rodar a **outra** convenção pela cascata real,
  /// e não por um laço paralelo.
  final CashTiming? cashTimingOverride;

  /// Proventos reinvestidos no retorno do ativo que estimou o beta. Zero
  /// quando o beta saiu do fechamento, que é o retorno de preço (decisão 89).
  final int dividendsInBeta;

  /// Fim do contrato de concessão: a mediana das outorgas vigentes no
  /// Formulário de Referência da CVM (item A6, decisão 88).
  ///
  /// **Só age sobre concessão**, pela classificação de [ConcessionSectors].
  /// Quando acaba antes do fim da projeção explícita, a projeção termina no
  /// contrato e o valor terminal é o capital investido nessa data. Quando acaba
  /// depois, o valor terminal é o capital no fim da projeção mais o excedente
  /// de retorno sobre ele só até o fim do contrato
  /// ([DcfAssumptions.contractYearsAfterHorizon]). `null` mantém a projeção
  /// inteira e o excedente perpétuo.
  final DateTime? concessionEnd;

  /// Taxa livre de risco **da data da avaliação**, que arbitra se a despesa
  /// financeira publicada pode ser lida como juro de dívida (item B10).
  ///
  /// A regra de `CostOfCapital.syntheticSpread` compara o custo da dívida
  /// observado com a faixa `[Rf, Rf + 10 p.p.]`. Medida contra a taxa do
  /// cenário, a faixa andava com ela: um deslocamento de 25 pontos-base tirava a
  /// cobertura de juros da conta, o custo da dívida caía até 2,3 p.p. e o preço
  /// justo **subia** com a taxa — GOAU4, SMTO3, RANI3 e UNIP6 na varredura de
  /// 16/09/2026. A pergunta é sobre o dado do exercício, e não sobre a taxa que
  /// se está supondo: a referência fica fixa na data, e o WACC corrente e o de
  /// equilíbrio leem o mesmo veredito. `null` recua para a taxa do CAPM.
  final double? creditReferenceRiskFree;

  /// Extensão, em anos, da série que estimou o beta (item B17).
  ///
  /// **A janela pedida é de cinco anos, e nem toda série a tem.** A fonte de
  /// cotações devolve uma janela fixa de dez anos: numa avaliação datada de
  /// 2018, a série começa em 2016 e o beta sai de pouco mais de um ano de
  /// pregões. O efeito é ruído no `Ke`, e ele entrava sem dizer.
  ///
  /// `null` quando não foi medida — o que inclui todo chamador que monta os
  /// insumos à mão.
  final double? betaWindowYears;

  /// Peso do beta do próprio ativo no beta de **equilíbrio** — imposição de
  /// diagnóstico do item B15.
  ///
  /// `β_∞ = w·β + (1 − w)·1`, o ajuste de Blume. `0,67` é a forma clássica;
  /// `1` é o comportamento de produção, que leva o beta de hoje à perpetuidade
  /// sem convergência. Só age sobre a taxa de **equilíbrio** — a corrente
  /// continua sendo o beta observado, que é o que o dado mede.
  ///
  /// **Não é do aplicativo.** Como as demais imposições, existe para que a
  /// varredura meça o efeito de uma alternativa antes de o registro escolher
  /// entre elas.
  final double? terminalBetaWeightOverride;

  /// `D/E` imposto na perpetuidade — imposição de diagnóstico do item B15.
  ///
  /// Em produção a alavancagem de equilíbrio é a que a projeção alcança no ano
  /// N (decisão 105) ou, sem taxas resolvidas, a de hoje. Este campo a
  /// substitui pela que a varredura quiser testar — a mediana do setor da B3,
  /// por exemplo.
  ///
  /// O prêmio de crédito **não** se move com ele: ele sai da alavancagem
  /// observada sobre o EBITDA, que é fato do exercício, e não da estrutura que
  /// se está supondo.
  final double? terminalLeverageOverride;

  /// Ações reunidas na unit, **como a companhia declara** (item B16).
  ///
  /// Vem do quadro de valores mobiliários da FCA da CVM, pelo formulário mais
  /// recente até [asOf] — ver `UnitCompositionCodec`. Presente, é ela que
  /// converte a contagem por ação das demonstrações para a unidade negociada, e
  /// a razão medida no valor de mercado vira **conferência**.
  ///
  /// **Por que a medida não basta.** `contagem × preço da unit ÷ valor de
  /// mercado` só devolve o número de ações da unit quando ordinária e
  /// preferencial valem o mesmo. Nas coortes, contra a composição declarada,
  /// ela erra 79 de 220 observações: em 49 cai em 1 e a unit é avaliada como
  /// ação; em 12 cai no inteiro errado dentro da folga de 5% — a ENGI11 com 4
  /// em vez de 5 —, sem aviso; em 18 a espécie não negocia e o valor de mercado
  /// volta a ser a contagem vezes o preço, o que devolve 1 por construção. Ver
  /// [`ponte_por_papel.md`](../../../../../docs/validacao/ponte_por_papel.md) §3.
  ///
  /// `null` sem declaração — e aí vale a medida, com a ressalva dizendo que foi
  /// inferida.
  final int? declaredSharesPerUnit;

  /// Teto **nominal** do crescimento na perpetuidade, em fração.
  ///
  /// Precisa estar na mesma unidade do desconto, que é nominal por vir do CDI.
  /// O padrão repete o crescimento real de longo prazo apenas para não quebrar
  /// quem constrói os insumos à mão; a aplicação passa
  /// `MarketAnchors.nominalEconomyGrowth`, derivado do IPCA observado.
  final double perpetualGrowthCap;

  /// Ressalvas que a camada de dados conhece e a cascata não enxerga — a CVM
  /// ausente ou defasada, a curva que faltou, o prior do beta indisponível.
  ///
  /// **Entram no resultado e no rastro** (item D4). Antes a tela as acrescentava
  /// depois da avaliação, e o JSON exportado do painel de logs não as tinha: o
  /// que se lia na tela não era o que se depurava no arquivo. Nenhum número
  /// muda por elas.
  final List<String> contextNotes;

  /// Agrupa os insumos. Não busca nada — quem busca é
  /// [PrepareValuationInputs], e a separação é o que mantém a cascata pura.
  const ValuationInputs({
    required this.ticker,
    required this.asOf,
    required this.fundamentals,
    required this.marketPrice,
    required this.capm,
    this.marginOfSafety = 0.0,
    this.projectionYears = 10,
    this.perpetualGrowthCap = 0.0652,
    this.sectorKey,
    this.industry,
    this.inflation = 0.05,
    this.declaredTerminalRiskFreeRate,
    this.riskFreeCurve,
    this.officialShares,
    this.prices,
    this.isDistressed = false,
    this.terminalReturnOverride,
    this.laneOverride,
    this.growthOverride,
    this.baseFactorOverride,
    this.unleveredBeta,
    this.reinvestmentOverride,
    this.cashTimingOverride,
    this.concessionEnd,
    this.dividendsInBeta = 0,
    this.creditReferenceRiskFree,
    this.declaredSharesPerUnit,
    this.terminalBetaWeightOverride,
    this.terminalLeverageOverride,
    this.betaWindowYears,
    this.peerMultiples,
    this.minorityEquityValue,
    this.scenarioTranslation = ScenarioTranslation.umPorUm,
    this.contextNotes = const [],
  });

  /// Marcador de «não mudar» para os campos anuláveis de [_copy]: com ele, o
  /// `null` passado de propósito — tirar a série de preços, por exemplo — se
  /// distingue do campo que não foi mencionado.
  static const Object _mantem = Object();

  /// **A única cópia de [ValuationInputs]** (item B27).
  ///
  /// Até 22/09/2026 cada cópia repetia a lista de campos à mão, e cada campo
  /// novo precisava ser lembrado em todas. Não foi: [withProjectionYears] — que
  /// a concessão que acaba dentro da projeção usa em produção — perdia os
  /// múltiplos de pares, o valor do minoritário e a tradução do cenário, e as
  /// cópias das ferramentas perdiam a composição declarada da unit, a taxa de
  /// referência do crédito e a janela do beta. **Ao acrescentar um campo,
  /// acrescente aqui e no teste «a cópia preserva todo campo».**
  ValuationInputs _copy({
    List<FundamentalsSnapshot>? fundamentals,
    CapmInputs? capm,
    int? projectionYears,
    Object? declaredTerminalRiskFreeRate = _mantem,
    Object? riskFreeCurve = _mantem,
    Object? prices = _mantem,
    Object? creditReferenceRiskFree = _mantem,
    Object? terminalReturnOverride = _mantem,
    Object? laneOverride = _mantem,
    Object? growthOverride = _mantem,
    Object? baseFactorOverride = _mantem,
    Object? reinvestmentOverride = _mantem,
    Object? cashTimingOverride = _mantem,
    Object? peerMultiples = _mantem,
    List<String>? contextNotes,
  }) {
    T? ou<T>(Object? novo, T? atual) =>
        identical(novo, _mantem) ? atual : novo as T?;
    return ValuationInputs(
      ticker: ticker,
      asOf: asOf,
      fundamentals: fundamentals ?? this.fundamentals,
      marketPrice: marketPrice,
      capm: capm ?? this.capm,
      marginOfSafety: marginOfSafety,
      projectionYears: projectionYears ?? this.projectionYears,
      perpetualGrowthCap: perpetualGrowthCap,
      sectorKey: sectorKey,
      industry: industry,
      inflation: inflation,
      declaredTerminalRiskFreeRate:
          ou(declaredTerminalRiskFreeRate, this.declaredTerminalRiskFreeRate),
      riskFreeCurve: ou(riskFreeCurve, this.riskFreeCurve),
      officialShares: officialShares,
      prices: ou(prices, this.prices),
      isDistressed: isDistressed,
      terminalReturnOverride:
          ou(terminalReturnOverride, this.terminalReturnOverride),
      laneOverride: ou(laneOverride, this.laneOverride),
      growthOverride: ou(growthOverride, this.growthOverride),
      baseFactorOverride: ou(baseFactorOverride, this.baseFactorOverride),
      unleveredBeta: unleveredBeta,
      reinvestmentOverride: ou(reinvestmentOverride, this.reinvestmentOverride),
      cashTimingOverride: ou(cashTimingOverride, this.cashTimingOverride),
      concessionEnd: concessionEnd,
      dividendsInBeta: dividendsInBeta,
      creditReferenceRiskFree:
          ou(creditReferenceRiskFree, this.creditReferenceRiskFree),
      declaredSharesPerUnit: declaredSharesPerUnit,
      terminalBetaWeightOverride: terminalBetaWeightOverride,
      terminalLeverageOverride: terminalLeverageOverride,
      betaWindowYears: betaWindowYears,
      peerMultiples: ou(peerMultiples, this.peerMultiples),
      minorityEquityValue: minorityEquityValue,
      scenarioTranslation: scenarioTranslation,
      contextNotes: contextNotes ?? this.contextNotes,
    );
  }

  /// Os mesmos insumos, com [n] anos de projeção explícita.
  ValuationInputs withProjectionYears(int n) => _copy(projectionYears: n);

  /// Os mesmos insumos com outra série de exercícios — a ancorada no trimestre
  /// do backtest (item C1c), por exemplo.
  ValuationInputs withFundamentals(List<FundamentalsSnapshot> series) =>
      _copy(fundamentals: series);

  /// Os mesmos insumos sem a série de cotações: a Porta 0 omite o corte de
  /// liquidez sem ela, e nada mais na cascata lê a série. Instrumento de
  /// diagnóstico.
  ValuationInputs withoutPrices() => _copy(prices: null);

  /// Os mesmos insumos com outras medianas de pares — ou sem elas.
  ValuationInputs withPeerMultiples(PeerMultipleSet? pares) =>
      _copy(peerMultiples: pares);

  /// Os mesmos insumos com as ressalvas de contexto (ver [contextNotes]).
  ValuationInputs withContextNotes(List<String> notes) =>
      _copy(contextNotes: List.unmodifiable(notes));

  /// Os mesmos insumos com as **imposições de diagnóstico** trocadas pelas
  /// informadas — `null` desliga a imposição. Não são do aplicativo: servem às
  /// varreduras que medem o efeito de uma alternativa.
  ValuationInputs withOverrides({
    ValuationLane? lane,
    double? terminalReturn,
    double? growth,
    double? baseFactor,
    ReinvestmentPolicy? reinvestment,
    CashTiming? cashTiming,
  }) =>
      _copy(
        laneOverride: lane,
        terminalReturnOverride: terminalReturn,
        growthOverride: growth,
        baseFactorOverride: baseFactor,
        reinvestmentOverride: reinvestment,
        cashTimingOverride: cashTiming,
      );

  /// Os mesmos insumos com o **nível** da taxa livre de risco deslocado em
  /// [delta]: a corrente, a de equilíbrio declarada e cada vértice da curva.
  ///
  /// É instrumento de diagnóstico — a varredura que confere se o preço justo
  /// cai quando o capital encarece (item B10). Deslocar só uma das taxas mudaria
  /// a inclinação da estrutura a termo, que é outra pergunta. O piso de 0,1%
  /// evita taxa negativa, que não tem leitura aqui. O custo da dívida observado
  /// nos exercícios não se move, e a referência do crédito
  /// ([creditReferenceRiskFree]) também não: ela é da data do dado.
  ValuationInputs withRiskFreeShift(double delta) {
    double piso(double x) => x < 0.001 ? 0.001 : x;
    final curva = riskFreeCurve;
    final declarada = declaredTerminalRiskFreeRate;
    return _copy(
      capm: capm.withRiskFree(piso(capm.riskFreeRate + delta)),
      declaredTerminalRiskFreeRate:
          declarada == null ? null : piso(declarada + delta),
      riskFreeCurve: curva == null
          ? null
          : YieldCurve.of(curva.referenceDate, [
              for (final v in curva.vertices)
                CurveVertex(v.years, piso(v.rate + delta)),
            ]),
      creditReferenceRiskFree: creditReferenceRiskFree ?? capm.riskFreeRate,
    );
  }

  /// O CAPM de **equilíbrio**: a taxa livre de risco estrutural e, quando a
  /// varredura do B15 o impõe, o beta convergido em direção a 1.
  ///
  /// Existe aqui para que as duas rotas — a interpolada e a resolvida — leiam a
  /// mesma regra, em vez de cada uma remontar o ajuste do seu jeito.
  CapmInputs get terminalCapm {
    final w = terminalBetaWeightOverride;
    final base = capm.withRiskFree(terminalRiskFreeRate);
    if (w == null) return base;
    return CapmInputs(
      riskFreeRate: base.riskFreeRate,
      beta: w * capm.beta + (1 - w) * 1.0,
      marketPremium: base.marketPremium,
      betaSource: base.betaSource,
      premiumSource: base.premiumSource,
    );
  }
}

/// De onde veio a contagem de papéis da ponte.
enum QuotedSharesSource {
  /// Implícita no valor de mercado: `VM ÷ preço`. É a que forma a cotação, e é
  /// a adotada sempre que as duas contagens publicadas concordam.
  market,

  /// Conciliada pelas demonstrações, adotada quando é a **maior** das duas e as
  /// duas divergem além de uma ação societária plausível.
  reconciled,

  /// Única disponível: o valor de mercado não pôde ser usado.
  onlyAvailable,

  /// Registro oficial da B3, líquida da fração em tesouraria (decisão 83).
  official;
}

/// Como o deslocamento do cenário de desconto vira deslocamento do `Ke` na
/// rota derivada (item B20, decisão 121).
///
/// O cenário perturba `DcfAssumptions.discountRate`. Na via do acionista esse
/// campo **é** o `Ke`, e o deslocamento é um a um por construção. Na via da
/// firma ele é o WACC, e a rota derivada desconta ao `Ke`: traduzir exige
/// escolher **o que o cenário está perturbando**, e ele não diz.
enum ScenarioTranslation {
  /// `ΔK_e = ΔWACC`. O cenário perturba **a taxa aplicada ao fluxo**, que é a
  /// que esta rota usa — e é o que faz as duas vias quererem dizer a mesma
  /// coisa.
  umPorUm,

  /// `ΔK_e = ΔWACC ÷ w_E`. O cenário perturba **o custo de capital da firma**
  /// com `K_d` e os pesos parados.
  estruturaFixa,

  /// `ΔK_e = ΔWACC ÷ (1 − w_D·t)`. O cenário perturba **a taxa livre de
  /// risco**, que move `K_e` e `K_d` juntos.
  taxaLivreDeRisco,
}

/// Contagem de ações de um emissor no registro oficial da B3.
class OfficialShareCount {
  /// Ações emitidas, **com as em tesouraria** — é como a B3 publica.
  final double total;

  /// Dia em que o registro foi consultado.
  final DateTime asOf;

  /// Declara a contagem.
  const OfficialShareCount({required this.total, required this.asOf});
}

/// Contagem de papéis da ponte, com a origem e as duas candidatas.
class QuotedShares {
  /// Papéis na unidade negociada. Sempre positiva.
  final double count;

  /// De onde ela veio.
  final QuotedSharesSource source;

  /// Contagem implícita no valor de mercado, na unidade negociada. `null`
  /// quando o valor de mercado não está publicado.
  final double? fromMarketCap;

  /// Contagem conciliada pelas demonstrações, na unidade negociada. `null`
  /// quando nenhuma das duas contagens societárias é utilizável.
  final double? fromStatements;

  /// Razão de unidade medida, para o aviso de *unit*.
  final double sharesPerQuote;

  /// Contagem oficial da B3 na unidade negociada e líquida de tesouraria,
  /// quando havia registro utilizável — adotada ou não.
  final double? fromRegistry;

  /// Dia da consulta ao registro, quando [fromRegistry] existe.
  final DateTime? registryAsOf;

  const QuotedShares({
    required this.count,
    required this.source,
    required this.fromMarketCap,
    required this.fromStatements,
    required this.sharesPerQuote,
    this.fromRegistry,
    this.registryAsOf,
  });

  /// Cópia adotando a contagem oficial.
  QuotedShares _comOficial(double oficial, DateTime consulta) => QuotedShares(
        count: oficial,
        source: QuotedSharesSource.official,
        fromMarketCap: fromMarketCap,
        fromStatements: fromStatements,
        sharesPerQuote: sharesPerQuote,
        fromRegistry: oficial,
        registryAsOf: consulta,
      );

  /// Cópia registrando a contagem oficial que **não** foi adotada.
  QuotedShares _comOficialRecusada(double oficial, DateTime consulta) =>
      QuotedShares(
        count: count,
        source: source,
        fromMarketCap: fromMarketCap,
        fromStatements: fromStatements,
        sharesPerQuote: sharesPerQuote,
        fromRegistry: oficial,
        registryAsOf: consulta,
      );

  /// `true` quando as duas candidatas divergem além da banda de conciliação.
  bool get diverge {
    final a = fromMarketCap, b = fromStatements;
    if (a == null || b == null) return false;
    final d = a >= b ? a / b : b / a;
    return d > FundamentalsSnapshot.reconciliationBand;
  }

  /// Razão entre a maior e a menor candidata, sempre `>= 1`. `null` quando só
  /// uma existe.
  double? get divergence {
    final a = fromMarketCap, b = fromStatements;
    if (a == null || b == null) return null;
    return a >= b ? a / b : b / a;
  }
}

/// O que uma via recebe e não muda ao longo dos estágios dela (D1).
class _Via {
  final ValuationInputs inputs;

  /// Exercícios publicados na data, com demonstração de resultado.
  final List<FundamentalsSnapshot> published;

  /// O mais recente deles.
  final FundamentalsSnapshot latest;

  final ValuationLane lane;

  /// Contagem de papéis da ponte.
  final QuotedShares divisor;

  final AuditTransaction? audit;

  const _Via({
    required this.inputs,
    required this.published,
    required this.latest,
    required this.lane,
    required this.divisor,
    required this.audit,
  });
}

/// O que os estágios de uma via devolvem ao condutor, `_evaluateLane` (D1).
sealed class _Desconto {
  const _Desconto();
}

/// A realavancagem recusou a estrutura de capital (decisão 45). Se a avaliação
/// migra de via é decisão do condutor, e não do estágio.
final class _EstruturaRecusada extends _Desconto {
  /// Frase da recusa, com o ativo e a via.
  final String motivo;

  const _EstruturaRecusada(this.motivo);
}

/// A via descontada, com tudo o que a pós-condição da ponte e a conclusão leem.
final class _ViaDescontada extends _Desconto {
  final _Base saida1;
  final GrowthOrigin origem;
  final _Premissas premissas;

  /// Fluxo-base descontado.
  final double base;

  /// `true` quando o fluxo-base foi reconstruído do ciclo (decisão 53).
  final bool baseReconstruida;

  final _Custo custo;

  /// O desconto sob as premissas finais.
  final DcfOutcome outcome;

  /// Avisos da via, na ordem em que os estágios os declararam.
  final List<String> avisos;

  const _ViaDescontada({
    required this.saida1,
    required this.origem,
    required this.premissas,
    required this.base,
    required this.baseReconstruida,
    required this.custo,
    required this.outcome,
    required this.avisos,
  });
}

/// O que a Saída 1 da Porta 2 deixa para os estágios seguintes da via (D1).
class _Base {
  /// Alíquota estrutural do ativo, ou `null` sem exercício que a meça.
  final double? aliquota;

  /// Série de capital da via, na alíquota estrutural.
  final CapitalSeries series;

  /// Retorno sobre o capital do exercício mais recente.
  final double? retornoAtual;

  /// Retorno mediano na janela do ciclo.
  final double? retornoCiclo;

  /// Φ — capital externo em múltiplos da base inicial da janela.
  final double? phi;

  /// `true` quando a trava de saúde operacional vale para o ativo.
  final bool travaDeSaude;

  /// Fator de normalização aplicado ao fluxo-base.
  final double fator;

  const _Base({
    required this.aliquota,
    required this.series,
    required this.retornoAtual,
    required this.retornoCiclo,
    required this.phi,
    required this.travaDeSaude,
    required this.fator,
  });
}

/// As premissas de uma via, antes do ponto fixo das taxas (D1).
class _Premissas {
  /// Taxa de desconto corrente: WACC na via da firma, Ke na do acionista.
  final double desconto;

  /// Taxa de equilíbrio, sobre a taxa livre de risco estrutural.
  final double descontoTerminal;

  /// Crescimento na perpetuidade.
  final double perpetuo;

  /// `true` quando o ativo é concessão.
  final bool prazoDeterminado;

  /// Primeiro veredito da vantagem competitiva, contra [descontoTerminal].
  final MoatVerdict veredito;

  /// Retorno terminal que o veredito concede, ou `null`.
  final double? moatVerificado;

  /// Retorno terminal aplicado: o imposto de fora, ou o do veredito.
  final double? moat;

  /// Retorno implícito no fluxo-base, que converte crescimento em retenção.
  final double retornoDaBase;

  /// Premissas do DCF com a taxa interpolada.
  final DcfAssumptions assumptions;

  /// `Ke` do CAPM na taxa corrente e na de equilíbrio. Na via da firma, é o
  /// desconto do fluxo do acionista derivado quando o caminho de taxas não é
  /// resolvido (decisão 102).
  final double keCorrente;
  final double keTerminal;

  /// Custo da dívida aplicado no WACC — a classificação sintética —, ou
  /// `null` quando o WACC degenerou para o `Ke`.
  final double? custoDaDivida;

  /// Prêmio de crédito da classificação sintética, em fração.
  ///
  /// É o que o solucionador do caminho de taxas recebe, para que o `K_d` de
  /// cada ano seja `Rf_t + spread` — o mesmo que o WACC estático aplica, e a
  /// mesma leitura da decisão 31. Zero sem dívida bruta: ali não há custo de
  /// dívida a medir, e o que sobra é rendimento de caixa (decisão 58).
  final double spreadDeCredito;

  const _Premissas({
    required this.desconto,
    required this.descontoTerminal,
    required this.perpetuo,
    required this.prazoDeterminado,
    required this.veredito,
    required this.moatVerificado,
    required this.moat,
    required this.retornoDaBase,
    required this.assumptions,
    required this.keCorrente,
    required this.keTerminal,
    required this.custoDaDivida,
    required this.spreadDeCredito,
  });
}

/// O custo de capital resolvido de uma via, e o veredito que fechou com ele (D1).
class _Custo {
  /// Premissas finais: as de [_Premissas], com o caminho de taxas resolvido e
  /// o retorno terminal do último passe quando o ponto fixo fechou.
  final DcfAssumptions assumptions;

  /// Caminho de taxas resolvido, ou `null` quando vale a interpolação.
  final LeveredRates? taxas;

  /// Motivo da recusa **econômica** da estrutura de capital pelo solucionador,
  /// ou `null` (decisão 45).
  final String? estruturaRejeitada;

  /// Veredito final da vantagem competitiva.
  final MoatVerdict veredito;

  /// Retorno terminal que o veredito final concede, ou `null`.
  final double? moatVerificado;

  /// Retorno terminal aplicado ao fim.
  final double? moat;

  /// O caminho da taxa livre de risco contra o qual [taxas] foram resolvidas,
  /// ou `null` sem elas. A rota derivada precisa dele para o `K_d` e o
  /// rendimento do caixa de cada ano (item B24, decisão 127).
  final List<double>? caminhoRf;

  const _Custo({
    required this.assumptions,
    required this.taxas,
    this.caminhoRf,
    required this.estruturaRejeitada,
    required this.veredito,
    required this.moatVerificado,
    required this.moat,
  });
}

/// Roteia o ativo por portas e aplica a via correspondente.
///
/// A arquitetura é a da decisão 25, e substituiu a cascata de três degraus que
/// caía de modelo em modelo por falta de dado:
///
/// - **Porta 0** — elegibilidade: liquidez, histórico e continuidade. Ativo que
///   não passa não é avaliado, e a recusa é declarada.
/// - **Porta 1** — instituição financeira sai da via da firma, porque depósito e
///   captação são insumo do negócio, não financiamento.
/// - **Porta 3** — o lucro operacional recorrente decide se o fluxo da firma
///   sustenta uma perpetuidade.
/// - **Porta 2** — duas saídas independentes: uma normaliza a base pela
///   convergência ao ciclo, outra decide de onde vem a taxa de crescimento.
///
/// Depois do desconto há ainda uma **pós-condição**: quando a dívida líquida
/// quase consome o valor da firma, o preço por papel é resíduo de subtração, e a
/// avaliação migra para a via do acionista — declarando a migração.
///
/// A via aplicada **vai no resultado**, junto dos avisos. Cair silenciosamente
/// para um modelo inferior e rotular o número como "preço justo" esconderia do
/// usuário a qualidade real da estimativa.
abstract final class ValuationCascade {
  /// Avalia usando o melhor modelo possível.
  ///
  /// - [inputs]: insumos já resolvidos.
  /// - [scenarioBuilder]: constrói a fonte de cenários a partir das premissas
  ///   centrais. Sem ele, os modelos de fluxo usam três cenários discretos.
  /// - [monteCarloSamples]: sorteios quando a fonte é estocástica. Padrão
  ///   `10000`.
  /// - [seed]: semente do gerador. Padrão `42`, fixo por reprodutibilidade.
  ///
  /// Devolve [InvalidInput] sem preço de mercado; [InsufficientData] quando
  /// nenhum exercício havia sido publicado na data de referência, ou quando
  /// **nenhum** dos três modelos se aplica.
  ///
  /// **Síncrono e puro:** não toca rede nem relógio, e a mesma entrada produz
  /// sempre a mesma saída. É o que permite executá-la dentro de uma isolate e
  /// testar a decisão de modelo sem dependência externa.
  ///
  /// A instrumentação de auditoria abre transação **antes** da primeira
  /// validação: um ativo recusado é tão auditável quanto um avaliado.
  static Result<ValuationResult> evaluate(
    ValuationInputs recebidos, {
    AssumptionSource Function(DcfAssumptions base)? scenarioBuilder,
    int monteCarloSamples = 10000,
    int seed = 42,
  }) {
    // A transação é aberta antes de qualquer validação: um ativo recusado por
    // falta de dado é tão auditável quanto um avaliado, e a banca pergunta
    // justamente pelos recusados.
    final audit = AuditRecorder.begin(
      '/core/valuation/${recebidos.ticker.value}',
      inputPayload: _inputPayload(recebidos),
    );
    // **Uma exceção também fecha a transação** (item D4). Sem isto, um erro
    // inesperado no meio da cascata deixava a transação aberta para sempre, e o
    // painel de logs não recebia nada — justamente o caso que se abre o painel
    // para depurar. A exceção continua subindo: o rastro registra, não engole.
    try {
      return _evaluate(recebidos, audit,
          scenarioBuilder: scenarioBuilder,
          monteCarloSamples: monteCarloSamples,
          seed: seed);
    } catch (e, pilha) {
      audit?.abort('Exceção não tratada na cascata: $e', extra: {
        'excecao': e.runtimeType.toString(),
        'pilha': pilha.toString().split('\n').take(12).toList(),
        'notasDeContexto': recebidos.contextNotes,
      });
      rethrow;
    }
  }

  static Result<ValuationResult> _evaluate(
    ValuationInputs recebidos,
    AuditTransaction? audit, {
    AssumptionSource Function(DcfAssumptions base)? scenarioBuilder,
    required int monteCarloSamples,
    required int seed,
  }) {

    // **Concessão que acaba dentro da projeção termina a projeção no contrato**
    // (item A6, decisão 88). Antes de tudo, porque o horizonte governa a curva,
    // o decaimento do crescimento, a convergência do retorno e o ponto fixo das
    // taxas — encurtá-lo depois deixaria cada peça com um N diferente.
    final anosDeContrato = contractYears(recebidos);
    final inputs = anosDeContrato != null &&
            anosDeContrato < recebidos.projectionYears
        ? recebidos.withProjectionYears(anosDeContrato)
        : recebidos;

    if (inputs.marketPrice <= 0) {
      audit?.abort('Preço de mercado indisponível.');
      return const Err(InvalidInput('Preço de mercado indisponível.'));
    }

    final view = PointInTimeView(inputs.asOf);
    final divulgados = view.published(inputs.fundamentals);

    // **Exercício sem demonstração de resultado não é exercício de zero**
    // (decisão 52). A fonte publica a linha com o balanço preenchido e o
    // resultado inteiro zerado, e lê-la como zero produz base nula, retorno
    // nulo e recusa por "os dados não sustentam nenhuma das duas vias" — que é
    // a mensagem errada para um dado que a fonte não entregou. Ver
    // [FundamentalsSnapshot.hasIncomeStatement].
    final published = [
      for (final s in divulgados)
        if (s.hasIncomeStatement) s
    ];
    final vazios = divulgados.length - published.length;

    if (published.isEmpty) {
      final message = divulgados.isEmpty
          ? 'Nenhum exercício de ${inputs.ticker.value} havia sido divulgado '
              'em ${_fmt(inputs.asOf)} (defasagem de '
              '${view.publicationLag.inDays} dias).'
          : 'Os ${divulgados.length} exercícios divulgados de '
              '${inputs.ticker.value} vêm sem demonstração de resultado: '
              'receita, resultado operacional, lucro e lucro por ação zerados. '
              'Não há o que descontar.';
      audit?.abort(message, extra: {
        'exerciciosRecebidos': inputs.fundamentals.length,
        'exerciciosPublicados': divulgados.length,
        'exerciciosSemResultado': vazios,
      });
      return Err(InsufficientData(message, subject: inputs.ticker.value));
    }

    // Porta 0 — elegibilidade. Vem antes de qualquer decisão de modelo: um
    // ativo ilíquido, de histórico curto ou sem continuidade não é caso de
    // escolher via, é caso de não avaliar.
    final elegibilidade = EligibilityGate.assess(
      snapshots: published,
      prices: inputs.prices,
      isDistressed: inputs.isDistressed,
    );
    if (!elegibilidade.isEligible) {
      final message = elegibilidade.message!;
      audit?.abort(message, extra: {
        'motivos': [for (final r in elegibilidade.reasons) r.name],
        'exerciciosPublicados': elegibilidade.publishedPeriods,
        if (elegibilidade.averageDailyTradedValue != null)
          'volumeFinanceiroMediano':
              _r(elegibilidade.averageDailyTradedValue!, 0),
      });
      return Err(InsufficientData(message, subject: inputs.ticker.value));
    }

    final latest = published.last;
    final warnings = <String>[];
    if (vazios > 0) {
      warnings.add(
        '$vazios ${vazios == 1 ? "exercício divulgado veio" : "exercícios "
            "divulgados vieram"} sem demonstração de resultado — receita, '
        'resultado operacional, lucro e lucro por ação zerados, com balanço '
        'preenchido. ${vazios == 1 ? "Ele ficou" : "Eles ficaram"} de fora da '
        'série: ausência não é zero, e lê-la como zero produziria base e '
        'retorno nulos.',
      );
    }

    if (latest.fiscalPeriodEnd.year < inputs.asOf.year - 2) {
      warnings.add(
        'O exercício mais recente já divulgado é de ${latest.fiscalPeriodEnd.year}; '
        'a avaliação pode estar desatualizada.',
      );
    }

    // **A composição declarada decide, e a medida confere** (item B16). A razão
    // medida no valor de mercado continua sendo calculada: ela é a conferência,
    // e é o que sobra quando a companhia não declara.
    final medida = quotedUnitRatio(
      sharesOutstanding: latest.sharesOutstanding,
      marketCap: latest.marketCap,
      marketPrice: inputs.marketPrice,
    );
    final declarada = inputs.declaredSharesPerUnit;
    final declaradaValida =
        declarada != null && declarada >= 1 && declarada <= maxSharesPerUnit;
    final sharesPerQuote =
        declaradaValida ? declarada.toDouble() : medida;
    _auditUnitRatio(audit, inputs, latest, sharesPerQuote,
        medida: medida, declarada: declaradaValida ? declarada : null);
    _auditCapm(audit, inputs.capm, inputs.dividendsInBeta);

    // **A janela do beta, quando ela é curta** (item B17, decisão 111). A
    // fonte de cotações devolve dez anos: numa avaliação datada de 2018 a
    // série começa em 2016, e o beta sai de pouco mais de um ano de pregões
    // sem que nada diga. O corte é de 80% da janela pedida — abaixo disso não
    // é feriado nem pregão faltando, é série que não existe.
    final janelaDoBeta = inputs.betaWindowYears;
    if (janelaDoBeta != null &&
        janelaDoBeta > 0 &&
        janelaDoBeta < betaWindowYears * minimumBetaWindowShare) {
      warnings.add(
        'O beta foi estimado sobre ${janelaDoBeta.toStringAsFixed(1)} ano(s) '
        'de cotação, e não sobre os $betaWindowYears que a janela pede: a '
        'série do papel não cobre o período inteiro. O custo do capital próprio '
        'carrega esse ruído, e o preço justo com ele.',
      );
    }

    if (sharesPerQuote > 1) {
      warnings.add(
        '${inputs.ticker.value} é negociada em unit de '
        '${sharesPerQuote.toStringAsFixed(0)} ações'
        '${declaradaValida ? ', pela composição que a companhia declara no formulário cadastral da CVM' : ', razão inferida do valor de mercado — a companhia não declara a composição'}'
        '. Os demonstrativos vêm por ação e a cotação é por unit: o valor '
        'justo é convertido para a unit antes de ser comparado ao preço.',
      );
    }
    // A conferência: a razão medida discorda da declarada. Não muda número —
    // vale a declarada —, mas é o sinal de que as espécies negociam a preços
    // diferentes, ou de que uma delas não negociou na data.
    if (declaradaValida && (medida - declarada).abs() > 1e-9) {
      warnings.add(
        'A razão de unidade medida no valor de mercado deu '
        '${medida.toStringAsFixed(0)} e a composição declarada diz '
        '${declarada.toStringAsFixed(0)}: vale a declarada. A razão medida só '
        'devolve o número de ações da unit quando as espécies valem o mesmo, e '
        'esta divergência diz que não valem.',
      );
    }

    final divisor = quotedShares(
      latest: latest,
      marketPrice: inputs.marketPrice,
      sharesPerQuote: sharesPerQuote,
      published: published,
      official: inputs.officialShares,
      asOf: inputs.asOf,
    );
    if (divisor == null) {
      const message = 'Nenhuma contagem de papéis utilizável: a ponte por papel '
          'não pode ser feita.';
      audit?.abort(message);
      return const Err(InsufficientData(message));
    }
    _auditQuotedShares(audit, latest, inputs.marketPrice, divisor);

    if (!shareBaseIsConsistent(published, latest)) {
      warnings.add(
        'A contagem de ações do exercício de ${latest.fiscalPeriodEnd.year} '
        '(${_r(latest.sharesOutstandingAsOf ?? 0, 0)}) destoa por mais de '
        '${CapitalSeries.neighbourFactor.toStringAsFixed(0)}x da dos exercícios '
        'vizinhos, o que é falha de escala da fonte e não ação societária. Ela '
        'foi descartada do divisor da ponte por papel, que passou a usar a '
        'contagem implícita no valor de mercado. As bases contábeis não são '
        'afetadas: nelas o erro se cancela contra o valor por ação publicado na '
        'mesma escala.',
      );
    }

    if (divisor.source == QuotedSharesSource.official) {
      final oficial = divisor.fromRegistry!;
      final discordantes = [
        if (divisor.fromMarketCap != null &&
            _razao(divisor.fromMarketCap!, oficial) >
                FundamentalsSnapshot.reconciliationBand)
          '${_r(divisor.fromMarketCap!, 0)} implícitas no valor de mercado',
        if (divisor.fromStatements != null &&
            _razao(divisor.fromStatements!, oficial) >
                FundamentalsSnapshot.reconciliationBand)
          '${_r(divisor.fromStatements!, 0)} conciliadas pelas demonstrações',
      ];
      if (discordantes.isNotEmpty) {
        warnings.add(
          'A contagem oficial da B3, de ${_fmt(divisor.registryAsOf!)}, é de '
          '${_r(oficial, 0)} papéis líquidos de tesouraria, e a fonte de '
          'preços diverge dela além da banda de conciliação: '
          '${discordantes.join(' e ')}. Foi adotada a oficial.',
        );
      }
    } else if (divisor.fromRegistry != null) {
      warnings.add(
        'A contagem oficial da B3 é de ${_fmt(divisor.registryAsOf!)}, mais '
        'antiga que $officialSharesMaxAgeDays dias, e diverge das duas '
        'contagens da fonte — o que um evento de ações depois da consulta '
        'explicaria. Ela não foi usada, e a ponte por papel seguiu a regra da '
        'fonte.',
      );
    }

    if (divisor.diverge && divisor.source != QuotedSharesSource.official) {
      warnings.add(
        'As contagens de papéis da fonte divergem por '
        '${divisor.divergence!.toStringAsFixed(2)}x: '
        '${_r(divisor.fromMarketCap!, 0)} implícitas no valor de mercado '
        'contra ${_r(divisor.fromStatements!, 0)} conciliadas pelas '
        'demonstrações. Nada no dado arbitra qual descreve a base societária '
        'de hoje, e foi adotada a **maior** — ${divisor.source.diagnostico} —, '
        'porque divisor pequeno demais infla o preço justo e produz sinal '
        'falso de desconto. O preço justo é, nesta medida, conservador.',
      );
    } else if (latest.sharesDisagree) {
      warnings.add(
        'As duas contagens de ações publicadas pela fonte discordam: '
        '${_r(latest.sharesOutstanding ?? 0, 0)} correntes contra '
        '${_r(latest.sharesOutstandingAsOf ?? 0, 0)} do exercício. As bases '
        'contábeis usam a do exercício, que reconstrói o patrimônio publicado; '
        'a ponte por papel usa a implícita no valor de mercado, que é a que '
        'forma o preço comparado.',
      );
    }

    final imposta = inputs.laneOverride;
    final lane = imposta ?? _route(inputs, published, latest, warnings, audit);
    if (imposta != null) {
      warnings.add(
        'Via imposta em "${imposta.diagnostico}" por varredura externa. Este '
        'resultado é instrumento de diagnóstico, não avaliação: o roteamento '
        'foi ignorado.',
      );
    }
    final refusals = <String>[];
    final result = _evaluateLane(inputs, published, latest, lane, warnings,
        scenarioBuilder, monteCarloSamples, seed, divisor, audit,
        refusals: refusals);
    if (result != null) {
      final comNotas = inputs.contextNotes.isEmpty
          ? result
          : result.withWarnings(inputs.contextNotes);
      _auditVerdict(audit, comNotas);
      audit?.complete(_outputPayload(comNotas));
      return Ok(comNotas);
    }

    final message = refusals.isNotEmpty
        ? refusals.first
        : 'Os dados de ${inputs.ticker.value} não sustentam nenhuma das duas '
            'vias de avaliação.';
    audit?.abort(message, extra: {
      'viaTentada': lane.diagnostico,
      'exerciciosPublicados': published.length,
      if (inputs.contextNotes.isNotEmpty) 'notasDeContexto': inputs.contextNotes,
    });
    return Err(InsufficientData(message, subject: inputs.ticker.value));
  }

  // ------------------------------------------------ Unidade de negociação --

  /// Quantas ações compõem a **unit** negociada, ou 1 para a ação comum.
  ///
  /// Existe porque a fonte mistura duas convenções no mesmo ativo: as
  /// demonstrações e o `sharesOutstanding` vêm por **ação**, enquanto a
  /// cotação e o `marketCap` vêm por **unit**. Dividir um valor
  /// de firma pelo número de ações produz preço justo por ação, que era então
  /// comparado ao preço da unit — erro de 5× em SAPR11 e KLBN11 e de 3× em
  /// BPAC11 (medido em 21/08/2026).
  ///
  /// A razão é **medida, não tabelada**: `ações × preço ÷ valor de mercado`
  /// devolve 1,00 para ação comum e o número de ações da unit para as demais,
  /// sem depender de uma lista que envelhece a cada reorganização societária.
  /// Fora da faixa plausível ou longe de um inteiro, adota-se 1 — preferível
  /// a aplicar um fator inventado.
  ///
  /// - [sharesOutstanding]: papéis em circulação, por ação.
  /// - [marketCap]: valor de mercado publicado.
  /// - [marketPrice]: cotação da unidade negociada.
  ///
  /// **A tolerância é relativa, e a razão de ser dela está na grandeza que
  /// mede** (decisão 61). O desvio `bruto ÷ u − 1` é exatamente a discordância
  /// relativa entre `ações × preço` e `u × valor de mercado` — isto é, o quanto
  /// o preço andou desde o instante do valor de mercado publicado. Uma banda
  /// **absoluta** de 0,12 dava 12% de folga à ação comum, onde aceitar e
  /// recusar devolvem o mesmo 1,0, e 1,2% à unit de dez ações, onde o fator
  /// errado custa dez vezes. **A SAPR11 — uma das duas que motivaram esta
  /// função — media 4,8799 e era recusada por 0,0001**, caindo para a convenção
  /// de ação comum.
  ///
  /// Retorna a razão arredondada, sempre em `[1, maxSharesPerUnit]`. Devolve
  /// `1.0` — nunca `null`, nunca zero — para qualquer entrada ausente, não
  /// positiva, não finita, fora da faixa, ou a mais de [unitRatioTolerance] de
  /// um inteiro, em termos relativos. O valor é seguro como divisor.
  static double quotedUnitRatio({
    required double? sharesOutstanding,
    required double? marketCap,
    required double marketPrice,
  }) {
    if (sharesOutstanding == null || sharesOutstanding <= 0) return 1.0;
    if (marketCap == null || marketCap <= 0) return 1.0;
    if (marketPrice <= 0) return 1.0;

    final raw = sharesOutstanding * marketPrice / marketCap;
    if (!raw.isFinite) return 1.0;

    final rounded = raw.roundToDouble();
    if (rounded < 1 || rounded > maxSharesPerUnit) return 1.0;
    // A tolerância absorve a diferença de data entre o preço e o valor de
    // mercado publicado, que é de fechamento — e essa diferença é relativa.
    if ((raw / rounded - 1).abs() > unitRatioTolerance) return 1.0;
    return rounded;
  }

  /// A contagem de ações do exercício mais recente é coerente com a série?
  ///
  /// **Por que a pergunta existe.** A fonte publica a contagem do exercício e as
  /// métricas por ação na mesma base, de modo que um erro de escala nas duas se
  /// cancela em `VPA × N` e passa despercebido no patrimônio. Ele **não** se
  /// cancela no divisor da ponte por papel, que usa `N` sozinho.
  ///
  /// O caso medido é a EQTL3, cujo exercício de 2024 vem com **246.152** ações
  /// contra 1,50 bilhão em 2023 e 1,26 bilhão em 2025 — um fator de cinco mil.
  /// O VPA acompanha, em R$ 121.419,23, e o patrimônio sai correto em R$ 29,9
  /// bilhões; o lucro por ação sai em R$ 11.422,52. Hoje isso não muda número
  /// nenhum, porque o exercício de 2025 já é público. Numa análise datada entre
  /// as duas divulgações — e é o que a validação *point-in-time* faz —, aquele
  /// exercício seria o mais recente, e o preço justo por papel sairia cinco mil
  /// vezes errado.
  ///
  /// **O teste é de vizinhança, e o fator é o mesmo de [CapitalSeries].** Lá o
  /// raciocínio já está escrito: falha de fonte é de ordem de grandeza, salto
  /// societário real fica entre duas e nove vezes e **precisa passar**. A VIVT3
  /// dobrou a base em 2024 — 1,65 para 3,26 bilhões, com o VPA caindo de R$
  /// 42,13 para R$ 21,40 — e passa, que é o certo: foi ação societária, não
  /// erro.
  ///
  /// - [published]: exercícios publicados, em ordem cronológica. Lista vazia
  ///   **aprova**: sem série não há vizinhança contra a qual julgar, e ausência
  ///   de dado não é evidência de defeito.
  /// - [latest]: exercício cuja contagem se quer julgar.
  static bool shareBaseIsConsistent(
    List<FundamentalsSnapshot> published,
    FundamentalsSnapshot latest,
  ) {
    final alvo = latest.sharesOutstandingAsOf;
    if (alvo == null || alvo <= 0) return true;

    final vizinhos = <double>[];
    for (final s in published) {
      if (identical(s, latest)) continue;
      final n = s.sharesOutstandingAsOf;
      if (n != null && n > 0) vizinhos.add(n);
    }
    if (vizinhos.length < 2) return true;

    final recentes = vizinhos.length <= CapitalSeries.neighbourRadius
        ? vizinhos
        : vizinhos.sublist(vizinhos.length - CapitalSeries.neighbourRadius);
    recentes.sort();
    final m = recentes.length ~/ 2;
    final referencia = recentes.length.isOdd
        ? recentes[m]
        : (recentes[m - 1] + recentes[m]) / 2;
    if (referencia <= 0) return true;

    final razao = alvo >= referencia ? alvo / referencia : referencia / alvo;
    return razao <= CapitalSeries.neighbourFactor;
  }

  /// Janela, em anos, que o beta pede — e contra a qual a efetiva é medida.
  ///
  /// Mora aqui, e não em `PrepareValuationInputs`, porque quem declara a
  /// janela curta é a cascata: o preparo apenas mede a que a série deu. O
  /// preparo referencia esta constante, de modo que as duas não podem
  /// divergir.
  /// Fração do patrimônio consolidado a partir da qual o minoritário torna o
  /// recuo ao WACC estático uma ressalva (item B23, decisão 120).
  ///
  /// Um centésimo do consolidado: abaixo disso o tratamento do minoritário
  /// move o terceiro decimal da taxa, e declarar seria ruído.
  static const double minorityWeightMateriality = 0.01;

  static const int betaWindowYears = 5;

  /// Fração da janela do beta abaixo da qual a avaliação declara a janela
  /// curta (item B17).
  ///
  /// **Oitenta por cento.** Feriado, suspensão e pregão faltando no meio tiram
  /// dias, não anos: uma série que cobre quatro dos cinco anos pedidos é a
  /// mesma janela. Abaixo disso a série **não existe** no período — é o caso
  /// da coorte de 31/03/2018, cuja cotação começa em setembro de 2016 e dá
  /// pouco mais de um ano e meio.
  static const double minimumBetaWindowShare = 0.8;

  /// Teto de ações por unit. As units da B3 vão até 5 (1 ON + 4 PN).
  static const double maxSharesPerUnit = 10;

  /// Folga **relativa** admitida entre a razão medida e o inteiro mais
  /// próximo, em [quotedUnitRatio].
  ///
  /// Cinco por cento é o que separa os dois grupos medidos em 11/09/2026 sobre
  /// os 359 ativos com razão mensurável: as nove units reais ficam todas em
  /// **2,40% ou menos** (IGTI11 0,38%, KLBN11 0,51%, TAEE11 0,58%, ENGI11
  /// 0,73%, ALUP11 1,03%, BRBI11 1,38%, SANB11 1,70%, BPAC11 2,00%, SAPR11
  /// 2,40%), e o falso positivo mais próximo, a EQPA5, em **10,44%**. Há um
  /// fator de quatro de margem para cada lado.
  ///
  /// **Não é mais permissiva que a banda absoluta que substituiu, senão de
  /// u = 3 para cima**: em u = 2 ela aperta de 0,12 para 0,10, e em u = 1 tanto
  /// faz — aceitar e recusar devolvem 1,0 igualmente.
  static const double unitRatioTolerance = 0.05;

  /// Papéis na **unidade negociada** para a ponte por papel.
  ///
  /// **A ponte compara duas coisas que precisam estar na mesma escala:** o
  /// valor do capital próprio que o modelo apura, em reais absolutos, e a
  /// cotação de uma unidade negociada. O divisor correto é, por definição, a
  /// contagem de unidades que forma essa cotação — `VM ÷ P_mkt`. Adotá-la faz o
  /// potencial virar `E ÷ VM − 1`, e nenhuma contagem de ação sobra na conta:
  /// desdobramento, grupamento, *unit* e registro corrompido saem por
  /// construção.
  ///
  /// **A contagem do exercício continua certa onde sempre esteve.** Ela
  /// reconstrói o patrimônio publicado — `VPA × N_exercício = PL` em 4.461 de
  /// 4.462 exercícios do cache — e é ela que [CapitalSeries] usa para medir
  /// ROIC, Φ e crescimento. O que ela não descreve é a escala do preço de hoje:
  /// medido em 07/09/2026, o divisor saía errado por mais de 5% em **30 dos
  /// 120 avaliados**, com 2,65x na MOVI3 e 1,49x na B3SA3.
  ///
  /// **Quando as duas contagens divergem, a fonte não tem árbitro, e a escolha
  /// é por consequência.** Isso foi medido, não suposto:
  ///
  /// - `N = lucro ÷ LPA` é **tautológico** para esta pergunta. Os dois campos
  ///   vêm das mesmas demonstrações, então ele só pode confirmar a contagem do
  ///   exercício — e confirma, em todos os divergentes.
  /// - O valor de mercado da fonte é, quase sempre, `contagem corrente ×
  ///   preço`, e herda o defeito dessa contagem: o MILS3 chega com R$ 760 mil
  ///   de capitalização contra R$ 9,6 milhões de volume mediano por pregão.
  /// - O `enterpriseToEbitda` publicado seria independente, mas erra por mais
  ///   de 2x em 12% dos ativos cujas duas contagens **concordam** — o piso de
  ///   ruído dele — e chega a discordar entre classes da mesma empresa: SAPR4
  ///   acusa 3,01 e SAPR11, 1,47.
  /// - A série de preços não denuncia desdobramento: o `close` da fonte já vem
  ///   ajustado por ação societária, e não há salto nenhum em dez anos.
  ///
  /// Sem árbitro, decide o sentido do erro. **Divisor pequeno demais infla o
  /// preço justo** e produz sinal falso de "barato", que é o pior sentido
  /// possível — o mesmo argumento que a Porta 0 usa para o corte de liquidez.
  /// Divisor grande demais deprime o preço justo, e o erro que sobra é o
  /// conservador. Por isso, na divergência, **adota-se a maior das duas**, e a
  /// divergência é declarada no resultado.
  ///
  /// Dentro da banda de conciliação as duas concordam e vale a do mercado, que
  /// é a que zera a contagem da comparação.
  ///
  /// - [latest]: exercício mais recente publicado.
  /// - [marketPrice]: cotação da unidade negociada.
  /// - [sharesPerQuote]: razão de unidade, de [quotedUnitRatio]. Converte a
  ///   contagem por ação das demonstrações para a unidade negociada.
  ///
  /// Devolve `null` quando nenhuma das duas contagens é utilizável.
  static QuotedShares? quotedShares({
    required FundamentalsSnapshot latest,
    required double marketPrice,
    required double sharesPerQuote,
    List<FundamentalsSnapshot> published = const [],
    OfficialShareCount? official,
    DateTime? asOf,
  }) {
    final daFonte = _quotedSharesDaFonte(
      latest: latest,
      marketPrice: marketPrice,
      sharesPerQuote: sharesPerQuote,
      published: published,
    );
    final oficial = _oficialNaUnidade(latest, official, sharesPerQuote, asOf);
    if (oficial == null) return daFonte;
    final consulta = official!.asOf;
    if (daFonte == null) {
      return QuotedShares(
        count: oficial,
        source: QuotedSharesSource.official,
        fromMarketCap: null,
        fromStatements: null,
        sharesPerQuote: sharesPerQuote,
        fromRegistry: oficial,
        registryAsOf: consulta,
      );
    }
    final idade = asOf == null
        ? 0
        : DateTime.utc(asOf.year, asOf.month, asOf.day)
            .difference(
                DateTime.utc(consulta.year, consulta.month, consulta.day))
            .inDays;
    bool concorda(double? c) {
      if (c == null || c <= 0) return false;
      final d = c >= oficial ? c / oficial : oficial / c;
      return d <= FundamentalsSnapshot.reconciliationBand;
    }

    // Registro recente arbitra sozinho. Registro antigo só arbitra quando
    // concorda com alguma das contagens da fonte: um evento de ações depois
    // da consulta o deixaria defasado por um fator, e a fonte já o refletiria.
    if (idade <= officialSharesMaxAgeDays ||
        concorda(daFonte.fromMarketCap) ||
        concorda(daFonte.fromStatements)) {
      return daFonte._comOficial(oficial, consulta);
    }
    return daFonte._comOficialRecusada(oficial, consulta);
  }

  /// Idade máxima, em dias, em que o registro oficial arbitra sozinho.
  ///
  /// O registro é consultado quando o pacote do aplicativo é gerado. Um mês
  /// cobre um ciclo de build; mais velho que isso, ele só vale quando concorda
  /// com alguma das contagens da fonte — ver [quotedShares].
  static const int officialSharesMaxAgeDays = 31;

  /// A contagem oficial na unidade negociada e líquida de tesouraria, ou
  /// `null` quando não há registro utilizável **na data**.
  ///
  /// **Nunca olha para a frente:** um registro consultado depois de [asOf] não
  /// existia na avaliação, e é por isso que coorte de backtest não o usa.
  ///
  /// **A tesouraria sai pela fração, e só por ela.** O total da B3 inclui as
  /// ações em tesouraria — conferido contra o capital integralizado declarado
  /// à CVM em 260 de 293 emissores —, e ação em tesouraria não tem direito ao
  /// patrimônio. A contagem absoluta da CVM não serve aqui: vem em unidade ou
  /// em milhar sem dizer qual (decisão 70); a fração é invariante.
  static double? _oficialNaUnidade(
    FundamentalsSnapshot latest,
    OfficialShareCount? official,
    double sharesPerQuote,
    DateTime? asOf,
  ) {
    if (official == null) return null;
    if (!official.total.isFinite || official.total <= 0) return null;
    if (asOf != null) {
      final c = DateTime.utc(
          official.asOf.year, official.asOf.month, official.asOf.day);
      final a = DateTime.utc(asOf.year, asOf.month, asOf.day);
      if (c.isAfter(a)) return null;
    }
    final f = latest.treasuryFraction;
    final liquida = (f != null && f.isFinite && f > 0 && f < 1)
        ? (official.total * (1 - f)).roundToDouble()
        : official.total;
    return liquida / sharesPerQuote;
  }

  static QuotedShares? _quotedSharesDaFonte({
    required FundamentalsSnapshot latest,
    required double marketPrice,
    required double sharesPerQuote,
    List<FundamentalsSnapshot> published = const [],
  }) {
    final pelaFonte = latest.sharesFromMarketCap(marketPrice);
    final conciliada =
        shareBaseIsConsistent(published, latest) ? latest.reconciledShares : null;
    final peloBalanco = (conciliada != null && conciliada > 0)
        ? conciliada / sharesPerQuote
        : null;

    if (pelaFonte == null && peloBalanco == null) return null;
    if (pelaFonte == null) {
      return QuotedShares(
        count: peloBalanco!,
        source: QuotedSharesSource.onlyAvailable,
        fromMarketCap: null,
        fromStatements: peloBalanco,
        sharesPerQuote: sharesPerQuote,
      );
    }
    if (peloBalanco == null) {
      return QuotedShares(
        count: pelaFonte,
        source: QuotedSharesSource.onlyAvailable,
        fromMarketCap: pelaFonte,
        fromStatements: null,
        sharesPerQuote: sharesPerQuote,
      );
    }

    final candidata = QuotedShares(
      count: pelaFonte,
      source: QuotedSharesSource.market,
      fromMarketCap: pelaFonte,
      fromStatements: peloBalanco,
      sharesPerQuote: sharesPerQuote,
    );
    if (!candidata.diverge || pelaFonte >= peloBalanco) return candidata;

    return QuotedShares(
      count: peloBalanco,
      source: QuotedSharesSource.reconciled,
      fromMarketCap: pelaFonte,
      fromStatements: peloBalanco,
      sharesPerQuote: sharesPerQuote,
    );
  }

  // ------------------------------------------------- A6: prazo do contrato --

  /// Anos até o fim do contrato de concessão, ou `null`.
  ///
  /// `null` quando o ativo não é concessão, quando o fim não é conhecido e
  /// quando ele já passou — o Formulário de Referência repete contrato vencido
  /// e renovado, e sem o prazo novo não há horizonte a impor.
  ///
  /// **Arredondado ao ano, e nunca abaixo de um**: a projeção explícita conta
  /// anos inteiros. O arredondamento é `round` e não `floor` porque ele
  /// **minimiza o erro** — `floor` tiraria até um ano inteiro de contrato que
  /// existe, e `round` erra no máximo meio ano, para os dois lados (lente
  /// `metodo`, 21/09/2026).
  ///
  /// **O piso de um ano é a única assimetria**, e é deliberada: um contrato com
  /// dias de vida recebe um ano que não tem, porque projeção de zero ano
  /// explícito não é modelo. Ela só morde em concessão a menos de seis meses do
  /// fim, e ali o prazo da renovação — que o Formulário ainda não traz — é a
  /// incerteza que domina.
  static int? contractYears(ValuationInputs inputs) {
    final fim = inputs.concessionEnd;
    if (fim == null) return null;
    if (!ConcessionSectors.hasFiniteTerm(
        sectorKey: inputs.sectorKey, industry: inputs.industry)) {
      return null;
    }
    final hoje =
        DateTime.utc(inputs.asOf.year, inputs.asOf.month, inputs.asOf.day);
    final ate = DateTime.utc(fim.year, fim.month, fim.day);
    final dias = ate.difference(hoje).inDays;
    if (dias <= 0) return null;
    final anos = (dias / 365.25).round();
    return anos < 1 ? 1 : anos;
  }

  /// Anos de contrato depois do fim da projeção — já encurtada até ele, quando
  /// acaba antes —, ou `null` sem prazo.
  static int? _anosDeContratoAlemDaProjecao(ValuationInputs inputs) {
    final t = contractYears(inputs);
    if (t == null) return null;
    final m = t - inputs.projectionYears;
    return m < 0 ? 0 : m;
  }

  // -------------------------------------------- Porta 1 e Porta 3: a via --

  /// Decide de quem é o fluxo.
  ///
  /// **Porta 1** — instituição financeira sai da via da firma, **pelo setor**.
  ///
  /// A exigência de dívida bruta nula que acompanhava o setor foi removida em
  /// 07/09/2026, e o motivo é que a justificativa dela não valia na taxonomia
  /// que o código compara. Ela citava a RENT3 chegando classificada como
  /// `Finance` — mas isso é a taxonomia da **listagem**, e a porta compara
  /// contra a do **perfil**, onde a RENT3 e a MOVI3 vêm como `consumo-ciclico`.
  /// Conferido por execução sobre o cache de produção: os 28 ativos com
  /// `servicos-financeiros` no perfil são bancos, seguradoras, resseguradora,
  /// corretora, bolsa e serviços financeiros diversos — não há locadora nem
  /// nada de outra natureza a barrar.
  ///
  /// O que a exigência fazia, na prática, era barrar quem tem passivo oneroso —
  /// isto é, **a própria definição do negócio bancário**. Cinco dos 28 caíam
  /// por ela para a via da firma, e a B3SA3 é o caso de maior efeito: as
  /// debêntures viravam dívida líquida subtraída do valor da firma, o que não
  /// tem sentido econômico numa bolsa, onde captação e tesouraria são
  /// engrenagem operacional.
  ///
  /// **Porta 3** — o fluxo da firma precisa se sustentar. Mede sobre NOPAT, que
  /// é o fluxo de manutenção sob a aproximação `CapEx_manutenção ≈ D&A`, e não
  /// sobre o fluxo livre publicado: este reprova quem está em ciclo de
  /// investimento. A EGIE3 caía para a via do acionista por um exercício
  /// negativo depois de onze positivos em dezesseis.
  static ValuationLane _route(
    ValuationInputs inputs,
    List<FundamentalsSnapshot> published,
    FundamentalsSnapshot latest,
    List<String> warnings,
    AuditTransaction? audit,
  ) {
    // Taxonomia oficial da B3 quando o emissor é classificado, e a da fonte de
    // preços no recuo (decisão 87). A fonte mantém duas taxonomias que não
    // coincidem — o perfil devolve `servicos-financeiros` e a listagem de
    // tickers `Finance` —, e comparar contra a errada fazia a Porta 1 nunca
    // disparar: o Banco ABC chegava com `servicos-financeiros` e passava reto.
    final porta1 = FinancialSectors.isFinancial(
      sectorKey: inputs.sectorKey,
      industry: inputs.industry,
    );

    final fluxoSustentado =
        porta1 ? false : GrowthGuards.firmFlowIsSustained(published);
    final lane = (porta1 || !fluxoSustentado)
        ? ValuationLane.shareholder
        : ValuationLane.firm;

    if (porta1) {
      warnings.add(
        'Instituição financeira: depósito, captação e passivo oneroso são '
        'insumo do negócio, não financiamento. A avaliação é do fluxo do '
        'acionista, descontada ao custo do capital próprio e sem ponte de '
        'dívida líquida — subtrair a captação do valor da firma trataria a '
        'matéria-prima do negócio como estrutura de capital.',
      );
    } else if (!fluxoSustentado) {
      warnings.add(
        'O lucro operacional não se sustenta na maioria dos exercícios; a '
        'avaliação passa para o fluxo do acionista.',
      );
    }

    audit?.step(
      formulaName: 'Roteamento por porta',
      latex: r'\text{via} = f(\text{setor},\, D_{bruta},\, \Pr[NOPAT > 0])',
      variables: {
        'setor': inputs.sectorKey ?? 'não informado',
        'dívida bruta (R\$)': _r(latest.totalDebt),
        'Porta 1 (financeira)': porta1 ? 'sim' : 'não',
        'Porta 3 (fluxo sustentado)': fluxoSustentado ? 'sim' : 'não',
      },
      steps: [
        'Porta 1: setor financeiro → '
            '${porta1 ? "via do acionista" : "segue para a Porta 3"}',
        if (!porta1)
          'Porta 3: NOPAT positivo em ao menos '
              '${_pct(ValuationParameters.minPositiveFlow)} dos exercícios → '
              '${fluxoSustentado ? "via da firma" : "via do acionista"}',
      ],
      result: lane == ValuationLane.firm ? 1 : 2,
      unit: lane == ValuationLane.firm ? 'via da firma' : 'via do acionista',
    );
    return lane;
  }

  // ------------------------------------------------ Porta 2 e a avaliação --

  /// Aplica a Porta 2 e desconta, na via informada.
  ///
  /// **É o condutor, e os estágios são funções** (item D1). A Saída 1, a Saída
  /// 2, as premissas, o fluxo-base e o custo de capital resolvido estão em
  /// [_descontarVia], cada um com entrada e saída declaradas; e o rastro, os
  /// cenários e os diagnósticos em [_concluir].
  ///
  /// **Nenhuma avaliação muda de via no meio da conta** (decisão 102). A via
  /// sai do roteamento — setor e sustentação do lucro operacional, fatos de
  /// longo prazo que não dependem da taxa nem do resultado —, e a conta que ela
  /// começa é a que ela termina. Até 16/09/2026 a via da firma migrava para a do
  /// acionista sobre LPA quando a participação do capital próprio caía abaixo
  /// de 35%, e quando a realavancagem recusava a estrutura de capital: 42 dos
  /// 109 não financeiros avaliados pelo aplicativo tinham o preço, inteiro ou em
  /// parte, de um modelo diferente do que a rota decidia, e o preço justo subia
  /// com a taxa em 18 deles. As duas vias são modelos independentes (decisão
  /// 39), e escolher entre elas pela conta é o que fazia o degrau.
  ///
  /// Devolve `null` quando a via não é aplicável com os dados disponíveis, o que
  /// o chamador converte em recusa declarada; a recusa com motivo vai para
  /// [refusals].
  static ValuationResult? _evaluateLane(
    ValuationInputs inputs,
    List<FundamentalsSnapshot> published,
    FundamentalsSnapshot latest,
    ValuationLane lane,
    List<String> warnings,
    AssumptionSource Function(DcfAssumptions)? scenarioBuilder,
    int samples,
    int seed,
    QuotedShares divisor,
    AuditTransaction? audit, {
    List<String>? refusals,
  }) {
    final via = _Via(
      inputs: inputs,
      published: published,
      latest: latest,
      lane: lane,
      divisor: divisor,
      audit: audit,
    );

    final descontada = _descontarVia(via, warnings);
    switch (descontada) {
      case null:
        return null;

      // --- A estrutura de capital recusada (decisão 45) ----------------------
      //
      // Não convergir é falha de método, e recuar para a interpolação é resposta
      // legítima; **recusar** é a conta dizendo que a estrutura não fecha — o
      // capital próprio some quando o custo dele é reprecificado pela
      // alavancagem que ele mesmo tem. Recuar para a interpolação lavaria a
      // recusa em preço, e a decisão 45 mandava o ativo para a via do acionista.
      // Desde a decisão 102 ele não vai: a via do acionista é outro modelo, e
      // trocar de modelo porque o primeiro recusou é o degrau que o B10 mediu.
      case _EstruturaRecusada(:final motivo):
        refusals?.add(
          '$motivo A avaliação não muda de via: a do acionista é outro modelo, '
          'e trocar de modelo porque este recusou faria o preço justo depender '
          'de qual dos dois a conta alcançou.',
        );
        return null;

      case final _ViaDescontada d:
        if (lane == ValuationLane.firm && d.outcome.fairValuePerShare <= 0) {
          // **Recusa nomeada, e não número sem conteúdo.** O capital próprio sai
          // do fluxo do acionista derivado do da firma; não positivo, a dívida
          // consome o que a operação gera, e não há o que repartir por papel.
          final participacao = d.outcome.equityShare;
          refusals?.add(
            'O fluxo do acionista de ${inputs.ticker.value}, derivado do da '
            'firma, não sustenta capital próprio positivo: a dívida líquida '
            'consome o valor que a operação gera'
            '${participacao > 0 ? ', e o capital próprio responderia por ${_pct(participacao)} do valor da firma' : ''}. '
            'O ativo não é avaliável por fluxo descontado nesta estrutura de '
            'capital.',
          );
          return null;
        }
        return _concluir(via, d, scenarioBuilder, samples, seed);
    }
  }

  /// **Os estágios da via, até o primeiro desconto.**
  ///
  /// Devolve `null` quando um estágio não se aplica aos dados;
  /// [_EstruturaRecusada] quando a realavancagem recusa a estrutura de capital,
  /// para o condutor decidir se migra; e [_ViaDescontada] com tudo o que a
  /// pós-condição e a conclusão leem.
  static _Desconto? _descontarVia(_Via via, List<String> warnings) {
    final inputs = via.inputs;
    final lane = via.lane;
    final audit = via.audit;
    final local = [...warnings];

    // --- Saída 1: a base ---------------------------------------------------
    final b = _saida1(via, local);
    if (b == null) return null;

    // --- Saída 2: a taxa ---------------------------------------------------
    final taxa = _saida2(via, b, local);
    if (taxa == null) return null;

    // --- Premissas ---------------------------------------------------------
    final p = _premissas(via, b, taxa.g, local);

    // --- Fluxo-base --------------------------------------------------------
    final fluxo = _fluxoBase(via, b, local);
    if (fluxo == null) return null;

    // --- Custo de capital realavancado e quem resolve o Ke ----------------
    final custo = _resolverCusto(via, b, p, fluxo.base, local);

    // A auditoria e a narrativa do *moat* saem agora, com o veredito final —
    // que pode ser o do segundo passe.
    _auditMoat(audit, custo.veredito);
    if (p.prazoDeterminado) {
      local.add(_avisoDoContrato(inputs, capitalApurado: p.retornoDaBase > 0));
    }
    final rInfFinal = custo.taxas?.terminalWacc ?? p.descontoTerminal;
    if (custo.moatVerificado != null &&
        inputs.terminalReturnOverride == null) {
      local.add(
        'Vantagem competitiva residual: retorno do ciclo de '
        '${_pct(b.retornoCiclo!)} contra custo de capital de equilíbrio de '
        '${_pct(rInfFinal)}, com excedente decaindo '
        '${_pct(1 - custo.veredito.persistence!)} ao ano — persistência medida '
        'na própria série do ativo, sobre ${custo.veredito.persistencePoints} '
        'pares. Em ${inputs.projectionYears} anos sobram '
        '${_pct(custo.veredito.retainedFraction!)} do excedente, e o retorno '
        'terminal fica em ${_pct(custo.moatVerificado!)} em vez do estado '
        'estacionário. O valor terminal volta a depender do crescimento '
        'perpétuo.',
      );
    }


    if (custo.estruturaRejeitada != null) {
      return _EstruturaRecusada(
        'A estrutura de capital de ${inputs.ticker.value} não sustenta a via '
        '${lane == ValuationLane.firm ? 'da firma' : 'do acionista'}: '
        '${custo.estruturaRejeitada}',
      );
    }

    final primeiro =
        _descontarFluxo(via, fluxo.base, custo, custo.assumptions, p);
    if (primeiro.isErr) return null;

    return _ViaDescontada(
      saida1: b,
      origem: taxa.origem,
      premissas: p,
      base: fluxo.base,
      baseReconstruida: fluxo.reconstruida,
      custo: custo,
      outcome: primeiro.unwrap(),
      avisos: local,
    );
  }

  /// **O desconto do fluxo da via**, sob as premissas [a].
  ///
  /// **Na via da firma, o capital próprio vem sempre do fluxo do acionista
  /// derivado do da firma** — `FCFE = FCFF − juros(1−τ) + ΔDívida` —, e nunca
  /// da subtração `EV − D` (decisão 102, que estende a 43).
  ///
  /// - **Com o caminho de taxas resolvido**, descontado ao caminho de `Ke` que a
  ///   realavancagem devolve; as duas rotas coincidem dentro de 1e-6, travado
  ///   por teste (decisão 43).
  /// - **Sem ele**, descontado ao `Ke` do CAPM, da taxa corrente à de
  ///   equilíbrio — o desconto que a via do acionista já usa —, com o custo da
  ///   dívida que o WACC aplica. O deslocamento que um cenário impõe ao desconto
  ///   da firma é aplicado ao `Ke` do mesmo jeito.
  ///
  /// **Por que não a ponte.** Com o capital próprio fino, `EV − D` é a diferença
  /// de dois números grandes e quase iguais, e o erro relativo chega ao preço por
  /// papel amplificado por `1/participação` — 138 vezes na RENT3. A ponte pedia
  /// uma pós-condição, e a pós-condição trocava de modelo: era o degrau.
  ///
  /// **Sem dívida bruta não há custo de dívida a medir, e o que sobra é
  /// rendimento de caixa** (decisão 58): a taxa livre de risco é o que caixa
  /// rende.
  ///
  /// A parte dos não controladores no patrimônio consolidado, que o fluxo da
  /// firma carrega e o acionista da controladora não recebe (decisão 49).
  static Result<DcfOutcome> _descontarFluxo(
    _Via via,
    double base,
    _Custo custo,
    DcfAssumptions a,
    _Premissas premissas,
  ) {
    if (via.lane == ValuationLane.shareholder) {
      return DcfCalculator.shareholder(baseProfit: base, assumptions: a);
    }
    final taxas = custo.taxas;
    final latest = via.latest;
    // **O centro é a premissa que produziu o preço justo**, e não a
    // interpolada (item B11). O cenário move o desconto da firma em relação ao
    // centro, e o mesmo deslocamento é aplicado ao `Ke` — que é a taxa que esta
    // rota usa. Com o centro errado, o cenário base não voltava ao preço
    // justo, e a faixa de sensibilidade cercava outro número.
    final centro = custo.assumptions;
    // **O deslocamento vira deslocamento do `Ke` pelo fator que a
    // [ScenarioTranslation] escolhe** (item B20, decisão 121). `Ke` e `WACC`
    // não se movem na mesma razão, e qual é a razão depende do que o cenário
    // está perturbando — coisa que ele não diz. As três leituras estão no
    // enum, e o padrão é o **um a um**, porque é o que faz as duas vias
    // quererem dizer a mesma coisa: na via do acionista o campo perturbado
    // **é** o `Ke`.
    final fatorDoCenario = _fatorDoCenario(via, custo);
    final dKe = (a.discountRate - centro.discountRate) * fatorDoCenario;
    final dKeTerminal =
        (a.terminalDiscountRate - centro.terminalDiscountRate) *
            fatorDoCenario;
    // O divisor é a contagem de unidades que forma a cotação — ver
    // [ValuationCascade.quotedShares]. Com ela, o potencial é `E ÷ VM − 1` e
    // nenhuma contagem de ação sobra na comparação com o preço de tela.
    final shares = via.divisor.count;
    final minoritarios = latest.minorityInterest ?? 0;
    // O custo da dívida é **sempre o sintético que o WACC aplica** — nas duas
    // rotas (item B11). O observado, `despesa financeira ÷ dívida bruta`, a
    // decisão 31 já descartou: ele carrega arrendamento e variação cambial, e
    // caía fora da banda defensável em 70 dos 120 avaliados.
    final kd = premissas.custoDaDivida ?? via.inputs.capm.riskFreeRate;
    // **O caixa rende a taxa livre de risco** (decisão 119, que estende a 113
    // à rota derivada).
    final rendimentoDoCaixa = via.inputs.capm.riskFreeRate;
    // **Com o caminho de taxas resolvido, o juro e o rendimento seguem a
    // curva** (item B24, decisão 127). O ponto fixo fecha o WACC com
    // `K_d,t = Rf_t + spread` e o caixa a `Rf_t`, e o `Ke` que desconta este
    // fluxo sai desse mesmo caminho. Projetar o juro com o `K_d` do primeiro
    // ano parado e descontar pelo `Ke` que se move quebrava a identidade entre
    // as duas rotas (lente `metodo`, 22/09/2026).
    final caminhoRf = custo.caminhoRf;
    final spread = premissas.spreadDeCredito;
    if (taxas == null) {
      return DcfCalculator.equityFromFirm(
        baseProfit: base,
        assumptions: a,
        netDebt: latest.netDebt,
        sharesOutstanding: shares,
        costOfDebt: kd,
        taxRate: ValuationParameters.statutoryTaxRate,
        equityDiscountRate: premissas.keCorrente + dKe,
        terminalEquityDiscountRate: premissas.keTerminal + dKeTerminal,
        minorityInterest: minoritarios,
        cash: latest.totalCash,
        cashYield: rendimentoDoCaixa,
      );
    }
    return DcfCalculator.equityFromFirm(
      baseProfit: base,
      assumptions: a,
      netDebt: latest.netDebt,
      sharesOutstanding: shares,
      costOfDebt: kd,
      taxRate: ValuationParameters.statutoryTaxRate,
      equityDiscountRate: taxas.costOfEquity.first + dKe,
      terminalEquityDiscountRate: taxas.terminalCostOfEquity + dKeTerminal,
      equityDiscountRatePath: [
        for (final k in taxas.costOfEquity) k + dKe,
      ],
      minorityInterest: minoritarios,
      cash: latest.totalCash,
      cashYield: rendimentoDoCaixa,
      costOfDebtPath:
          caminhoRf == null ? null : [for (final rf in caminhoRf) rf + spread],
      cashYieldPath: caminhoRf,
      terminalCostOfDebt: caminhoRf == null
          ? null
          : via.inputs.terminalRiskFreeRate + spread,
      terminalCashYield:
          caminhoRf == null ? null : via.inputs.terminalRiskFreeRate,
    );
  }

  /// **A conclusão da via**: o rastro do desconto e da ponte, os cenários e os
  /// diagnósticos. Devolve `null` com preço justo não positivo.
  static ValuationResult? _concluir(
    _Via via,
    _ViaDescontada d,
    AssumptionSource Function(DcfAssumptions)? scenarioBuilder,
    int samples,
    int seed,
  ) {
    final inputs = via.inputs;
    final lane = via.lane;
    final audit = via.audit;
    final outcome = d.outcome;
    // **As premissas finais, e não as interpoladas** (item B11). O preço justo
    // sai do caminho de taxas e do retorno terminal do último passe; o rastro,
    // os cenários, a taxa exibida e os diagnósticos saíam do chute de que o
    // ponto fixo parte. No aplicativo de antes as duas coincidiam, porque ele
    // não resolvia o prior — ligar o prior sem isto descasaria a banda de
    // sensibilidade do preço que ela cerca.
    final assumptions = d.custo.assumptions;
    if (outcome.fairValuePerShare <= 0) return null;

    // **O que a perpetuidade supõe sobre o capital que já existe** (item B12,
    // decisão 107). O retorno neutro fixa o do capital **novo**; o instalado
    // continua rendendo o que a projeção alcança, e na maioria dos avaliados
    // isso é **abaixo** do custo de capital. Onde a parcela domina o preço, ela
    // é dita — no rastro de auditoria ela sai sempre.
    final excedente = outcome.discountedTerminalExcess;
    final pesoExcedente = (excedente == null || outcome.equityValue <= 0)
        ? null
        : excedente / outcome.equityValue;
    final retornoInstalado = outcome.impliedTerminalReturn;
    if (pesoExcedente != null &&
        retornoInstalado != null &&
        pesoExcedente.abs() > ValuationDiagnostics.terminalExcessLimit) {
      final rInf = d.custo.taxas?.terminalWacc ?? d.premissas.descontoTerminal;
      final deficit = retornoInstalado < rInf;
      d.avisos.add(
        'A perpetuidade supõe que o capital já instalado continue rendendo '
        '${_pct(retornoInstalado)} ao ano para sempre, contra um custo de '
        'capital de equilíbrio de ${_pct(rInf)}: '
        '${_pct(pesoExcedente.abs())} do preço justo '
        '${deficit ? 'é subtraído por esse déficit' : 'vem desse excedente'}. '
        'O retorno terminal neutro recusa valor ao capital **novo**, e não ao '
        'que já existe — são duas afirmações, e só a primeira está no rótulo.',
      );
    }

    _auditDcf(
      audit,
      outcome: outcome,
      assumptions: assumptions,
      baseFlow: d.base,
      flowSymbol: lane == ValuationLane.firm ? 'NOPAT' : 'LPA',
      discountSymbol: lane == ValuationLane.firm ? 'WACC' : 'K_e',
      perShareAlready: lane == ValuationLane.shareholder,
    );
    if (lane == ValuationLane.firm) {
      _auditEquityBridge(
        audit,
        outcome: outcome,
        netDebt: via.latest.netDebt,
        minorityInterest: via.latest.minorityInterest ?? 0,
        shares: via.divisor.count,
        resolved: d.custo.taxas != null,
      );
    }

    // **A segunda leitura** (item B5, decisão 118). Ela usa o **mesmo
    // exercício-base e o mesmo divisor** do fluxo descontado: comparar duas
    // leituras que dividem por contagens diferentes mediria a ponte, e não o
    // modelo (decisão 83).
    final triangulacao = PeerTriangulation.build(
      latest: via.latest,
      shares: via.divisor.count,
      peers: inputs.peerMultiples,
      dcfFairValue: outcome.fairValuePerShare,
      sectorKey: inputs.sectorKey,
      industry: inputs.industry,
    );
    final avisosComTriangulacao = [
      ...d.avisos,
      if (triangulacao != null && triangulacao.diverges)
        _avisoDaTriangulacao(triangulacao, outcome.fairValuePerShare),
    ];

    return _withScenarios(
      inputs: inputs,
      model: lane == ValuationLane.firm
          ? ValuationModel.dcfFcff
          : ValuationModel.dcfEarnings,
      assumptions: assumptions,
      baseValue: outcome.fairValuePerShare,
      triangulation: triangulacao,
      valuate: (a) => _descontarFluxo(via, d.base, d.custo, a, d.premissas)
          .map((o) => o.fairValuePerShare),
      scenarioBuilder: scenarioBuilder,
      samples: samples,
      seed: seed,
      warnings: avisosComTriangulacao,
      diagnostics: _diagnose(
        outcome: outcome,
        divisor: via.divisor,
        baseFactor: d.saida1.fator,
        growthOrigin: d.origem,
        // O veredito, e não o retorno imposto: `moatApplied` alimenta relatório
        // de cobertura, e uma varredura de diagnóstico não é vantagem
        // competitiva reconhecida.
        moatApplied: d.custo.moatVerificado != null,
        finiteTerm: d.premissas.prazoDeterminado,
        rebuiltBase: d.baseReconstruida,
        // `Rf + β·prêmio` sobre a taxa corrente: o retorno esperado
        // incondicional do papel, que a camada de carteira ancora.
        costOfEquity: inputs.capm.costOfEquity,
        terminalDiscountRate:
            d.custo.taxas?.terminalWacc ?? d.premissas.descontoTerminal,
        terminalRetainedSpread: d.custo.veredito.retainedFraction ?? 0.0,
        growthRate: assumptions.growthRate,
        returnOnCapital: assumptions.returnOnCapital,
        terminalReturnOnCapital: assumptions.terminalReturnOnCapital,
        firmTaxRate: lane == ValuationLane.firm ? d.saida1.aliquota : null,
        terminalCostOfEquity: d.custo.taxas?.terminalCostOfEquity,
        // A estrutura de capital da perpetuidade é a do ano N do modelo, e não
        // a de hoje (item B15, decisão 105).
        terminalEquityShare:
            d.custo.taxas?.equityShareAt(inputs.projectionYears),
        retentionPath: [
          for (var t = 1; t <= inputs.projectionYears; t++)
            assumptions.retentionAt(t),
        ],
        growthPath: [
          for (var t = 1; t <= inputs.projectionYears; t++)
            assumptions.growthAt(t),
        ],
      ),
    );
  }

  /// **O custo de capital realavancado ano a ano** (decisões 41, 44, 46 e 51),
  /// com o veredito da vantagem competitiva refeito contra a taxa resolvida até
  /// o par parar de mudar.
  ///
  /// A interpolação de dois pontos supõe que só a taxa livre de risco se
  /// move. Medido, `D/V` sai de 0,29 no ano zero para 0,38 no ano dez — e um
  /// `WACC` único ao longo da projeção **é** a hipótese de `D/V` constante,
  /// que a projeção da dívida contradizia. Ver
  /// `docs/validacao/identidade_das_vias.md`.
  ///
  /// O ponto fixo resolve as duas coisas de uma vez: o caminho de taxas e a
  /// circularidade do peso do capital próprio, que hoje vem do valor de
  /// mercado enquanto o modelo diz outra coisa.
  ///
  /// **Sem beta desalavancado não há realavancagem**, e aí vale a
  /// interpolação — que é o comportamento anterior, declarado.
  static _Custo _resolverCusto(
    _Via via,
    _Base b,
    _Premissas p,
    double base,
    List<String> local,
  ) {
    final inputs = via.inputs;
    final latest = via.latest;
    final lane = via.lane;
    final divisor = via.divisor;
    final assumptions = p.assumptions;
    var moatVeredito = p.veredito;
    var moatVerificado = p.moatVerificado;
    var moat = p.moat;
    MoatVerdict vereditoDoMoat(double rInf) =>
        _vereditoDoMoat(inputs, b, p.prazoDeterminado, rInf);
    var assumptionsFinal = assumptions;
    LeveredRates? taxasResolvidas;
    List<double>? caminhoRfResolvido;
    // Recusa **econômica** do solucionador, distinta da numérica: ver o
    // bloco da estrutura rejeitada mais abaixo.
    String? estruturaRejeitada;
    final betaU = inputs.unleveredBeta;

    // --- Quem resolve o custo do capital próprio (decisão 46) --------------
    //
    // A via da firma resolve desde a decisão 41. A do acionista não resolvia, e
    // **é ela que avalia sozinha 33 dos 120** — instituição financeira, lucro
    // operacional não sustentado e estrutura de capital recusada. Nesses o
    // motor supunha a alavancagem de hoje perene, que é precisamente a hipótese
    // que a decisão 41 mediu e descartou.
    //
    // **A exceção é a instituição financeira, e é de direito.** Ali depósito e
    // captação são insumo do negócio, não financiamento: realavancar por `D/E`
    // trataria a matéria-prima como estrutura de capital, que é exatamente o
    // que o roteamento da Porta 1 existe para não fazer. Para banco vale o
    // `Ke` do CAPM sobre o beta observado, e a alavancagem perene é premissa
    // declarada em vez de descuido.
    final ehFinanceira = FinancialSectors.isFinancial(
      sectorKey: inputs.sectorKey,
      industry: inputs.industry,
    );
    final resolveTaxas = betaU != null &&
        betaU.isFinite &&
        (lane == ValuationLane.firm || !ehFinanceira);
    if (resolveTaxas) {
      final n = inputs.projectionYears;
      // Caminho da taxa livre de risco. Com curva observada, o forward de um
      // ano de cada ano da projeção (decisão 74); sem ela, o decaimento linear
      // de dois pontos da decisão 31.
      final curva = inputs.riskFreeCurve;
      final rfPath = curva != null
          ? curva.annualForwards(n)
          : <double>[
              for (var tAno = 1; tAno <= n; tAno++)
                inputs.capm.riskFreeRate -
                    (inputs.capm.riskFreeRate - inputs.terminalRiskFreeRate) *
                        (n <= 1 ? 1.0 : (tAno - 1) / (n - 1)),
            ];
      // A dívida por papel usa a mesma contagem que forma a cotação, que é a
      // que o preço justo da via do acionista carrega. Ver [quotedShares].
      final dividaPorPapel = divisor.count > 0
          ? latest.netDebt / divisor.count
          : double.nan;

      Result<LeveredRates> resolverTaxas(DcfAssumptions a) =>
          lane == ValuationLane.firm
              ? LeveredCostOfCapital.solve(
                  baseProfit: base,
                  assumptions: a,
                  netDebt: latest.netDebt,
                  unleveredBeta: betaU,
                  riskFreePath: rfPath,
                  terminalRiskFree: inputs.terminalRiskFreeRate,
                  marketPremium: inputs.capm.marketPremium,
                  // O prêmio de crédito da classificação sintética, e não o
                  // custo observado que a decisão 31 descartou (item B11).
                  creditSpread: p.spreadDeCredito,
                  taxRate: ValuationParameters.statutoryTaxRate,
                  // O caixa rende `R_f`, e não `R_f + spread` — a mesma
                  // separação do WACC estático, para que as duas rotas não
                  // discordem no mesmo ativo (lente `metodo`, 21/09/2026).
                  cash: latest.totalCash,
                  terminalBetaWeight: inputs.terminalBetaWeightOverride,
                  terminalLeverage: inputs.terminalLeverageOverride,
                  // O ponto fixo é tentado de dois lugares, e o que ele tem a
                  // dizer sobre a diferença entre eles é ressalva (item B18).
                  warnings: local,
                )
              : LeveredCostOfCapital.solveEquity(
                  baseProfit: base,
                  assumptions: a,
                  netDebtPerShare: dividaPorPapel,
                  unleveredBeta: betaU,
                  riskFreePath: rfPath,
                  terminalRiskFree: inputs.terminalRiskFreeRate,
                  marketPremium: inputs.capm.marketPremium,
                  taxRate: ValuationParameters.statutoryTaxRate,
                  terminalBetaWeight: inputs.terminalBetaWeightOverride,
                  terminalLeverage: inputs.terminalLeverageOverride,
                  warnings: local,
                );

      final resolvido = resolverTaxas(assumptions);
      if (resolvido.isOk) {
        var r = resolvido.unwrap();
        if (r.converged) {
          // --- Segundo passe: o moat contra a taxa resolvida (decisão 44) ---
          //
          // O veredito do primeiro passe usou a taxa interpolada, que é o
          // chute de que o ponto fixo parte. Com a taxa de equilíbrio
          // resolvida em mãos, o excedente muda de referência — e, quando o
          // retorno terminal resultante muda, a projeção inteira muda com ele.
          // Um passe só deixaria a perpetuidade sendo decidida por uma taxa
          // que a própria conta descartou.
          //
          // **Dois passes não fecham a volta** (decisão 51). O segundo passe
          // resolve as taxas de novo contra o veredito refeito, e a taxa que
          // ele devolve **não é** a que o veredito usou — de modo que a
          // pergunta se repõe exatamente como estava. O laço abaixo a repõe
          // até parar de mudar, com teto declarado porque a circularidade
          // pode não ter ponto fixo: um ativo na fronteira do veredito
          // alterna entre conceder e recusar para sempre.
          //
          // A volta mora em `MoatFixedPoint.iterate`, que a testa isolada —
          // inclusive o teto alcançado com o par alternando (item D3). **O
          // veredito só é adotado se a taxa dele existir**: adotá-lo antes de
          // saber se o solucionador fecha deixaria o retorno terminal de um
          // passe casado com o caminho de taxas do anterior.
          final volta = MoatFixedPoint.iterate<MoatVerdict, LeveredRates>(
            verdict: moatVeredito,
            moat: moat,
            rates: r,
            reassess: (taxas) => vereditoDoMoat(taxas.terminalWacc),
            moatOf: (v) => inputs.terminalReturnOverride ?? v.terminalReturn,
            solve: (novoMoat) {
              final proximo = resolverTaxas(assumptions.copyWith(
                terminalReturnOnCapital: novoMoat,
                neutralTerminalReturn: novoMoat == null,
              ));
              return proximo.isOk && proximo.unwrap().converged
                  ? proximo.unwrap()
                  : null;
            },
          );
          final passes = volta.passes;
          final estavel = volta.stable;
          final travouNoSolucionador = volta.solverFailed;
          if (passes > 1) {
            moatVeredito = volta.verdict;
            moatVerificado = volta.verdict.terminalReturn;
          }
          moat = volta.moat;
          r = volta.rates;
          if (!estavel) {
            final motivo = travouNoSolucionador
                ? 'o veredito seguinte pedia uma taxa que o ponto fixo não '
                    'fechou'
                : 'o teto de ${ValuationParameters.moatMaxPasses} passes foi '
                    'alcançado e o par ainda alternava';
            local.add(
              'O veredito de vantagem competitiva e a taxa de equilíbrio não '
              'se estabilizaram em $passes passes: $motivo. A volta é '
              'circular — o retorno terminal muda a projeção, que muda a '
              'alavancagem, que muda a taxa contra a qual o excedente é '
              'medido —, e vale o último par consistente entre si.',
            );
          }
          taxasResolvidas = r;
          caminhoRfResolvido = rfPath;
          assumptionsFinal = assumptions.copyWith(
            terminalReturnOnCapital: moat,
            neutralTerminalReturn: moat == null,
            discountRatePath: List<double>.from(r.wacc),
            terminalDiscountRate: r.terminalWacc,
          );
          final simbolo = lane == ValuationLane.firm ? 'WACC' : 'Ke';
          local.add(
            'O custo de capital é resolvido ano a ano contra a alavancagem que '
            'a própria avaliação produz: o $simbolo vai de '
            '${_pct(r.wacc.first)} no primeiro ano a ${_pct(r.wacc.last)} no '
            'ano $n, e a perpetuidade é descontada a '
            '${_pct(r.terminalWacc)}. ${_trechoDaParticipacao(r, n)} '
            'Ponto fixo em ${r.iterations} iterações, e o veredito '
            'da perpetuidade fechou em $passes '
            '${passes == 1 ? "passe" : "passes"}.',
          );
        } else {
          local.add(
            'O ponto fixo do custo de capital não convergiu em '
            '${r.iterations} iterações; vale a interpolação de dois pontos, '
            'que supõe alavancagem constante.',
          );
        }
      } else {
        final falha = resolvido.failureOrNull;
        if (falha is ComputationFailure) {
          // Não é falha de método: é a estrutura de capital sendo recusada
          // pela própria conta. Ver o bloco da estrutura rejeitada.
          estruturaRejeitada = falha.message;
        } else {
          local.add(
            'O custo de capital não pôde ser resolvido contra a alavancagem '
            '(${falha?.message}); vale a interpolação de dois pontos.',
          );
        }
      }
    }

    // **A condição de exposição do minoritário** (item B23, decisão 120). O
    // peso do WACC **estático** é o valor de mercado da controladora, e o fluxo
    // que ele desconta é o consolidado; o **resolvido** não tem o problema,
    // porque pondera pelo capital próprio que o modelo produz. Medido em
    // 21/09/2026, a interseção — via da firma, recuo estático e minoritário
    // material — é **vazia** no universo inteiro.
    //
    // **Vazia hoje não é vazia sempre.** O aviso existe para que, no dia em que
    // um ativo cair nas três condições, o preço justo dele não saia calado com
    // um WACC achatado.
    if (lane == ValuationLane.firm && taxasResolvidas == null) {
      final minoritario = latest.minorityInterest ?? 0;
      final controlador = latest.totalStockholderEquity ?? 0;
      final consolidado = minoritario + controlador;
      if (minoritario > 0 &&
          consolidado > 0 &&
          minoritario / consolidado >= minorityWeightMateriality) {
        local.add(
          'A avaliação recuou para o WACC estático, e ${_pct(minoritario / consolidado)} '
          'do patrimônio consolidado é de não controladores. **O peso do '
          'capital próprio na taxa é o valor de mercado da controladora**, e o '
          'fluxo descontado é o consolidado: a participação da dívida sai '
          'inflada e o desconto, achatado. O caminho resolvido não teria o '
          'problema, porque pondera pelo capital próprio que o próprio modelo '
          'produz (item B23).',
        );
      }
    }

    return _Custo(
      assumptions: assumptionsFinal,
      taxas: taxasResolvidas,
      caminhoRf: taxasResolvidas == null ? null : caminhoRfResolvido,
      estruturaRejeitada: estruturaRejeitada,
      veredito: moatVeredito,
      moatVerificado: moatVerificado,
      moat: moat,
    );
  }

  /// **As premissas da via**: a taxa corrente e a de equilíbrio, o crescimento
  /// perpétuo, o primeiro veredito da vantagem competitiva — contra a taxa
  /// interpolada, que é o chute de que o ponto fixo parte — e o retorno que
  /// converte crescimento em retenção.
  static _Premissas _premissas(
    _Via via,
    _Base b,
    double g,
    List<String> local,
  ) {
    final inputs = via.inputs;
    final latest = via.latest;
    final lane = via.lane;
    final divisor = via.divisor;
    final audit = via.audit;
    final aliquotaEstrutural = b.aliquota;
    final retornoAtual = b.retornoAtual;
    final retornoCiclo = b.retornoCiclo;
    final fatorBase = b.fator;

    final custoCorrente = lane == ValuationLane.firm
        ? _wacc(inputs, latest, local, divisor, audit)
        : (
            rate: inputs.capm.costOfEquity,
            costOfDebtEstimated: false,
            costOfDebt: null,
            creditSpread: 0.0,
          );
    final desconto = custoCorrente.rate;

    // Custo de capital de **equilíbrio**: o mesmo beta, o mesmo prêmio e a mesma
    // estrutura de capital, sobre a taxa livre de risco estrutural em vez da
    // corrente. É o destino do decaimento e a taxa da perpetuidade. Os avisos e
    // a auditoria saem só da montagem corrente — esta repetiria os mesmos.
    // **O beta e a estrutura de equilíbrio** (item B15). Em produção o beta é o
    // de hoje — ele não converge para 1 — e a estrutura, sem taxas resolvidas,
    // é a de hoje também; com elas, é a do ano N (decisão 105). As duas
    // imposições de diagnóstico entram por aqui.
    final capmTerminal = inputs.terminalCapm;
    final descontoTerminal = lane == ValuationLane.firm
        ? _wacc(inputs, latest, <String>[], divisor, null,
                capmOverride: capmTerminal, terminal: true)
            .rate
        : capmTerminal.costOfEquity;

    final perpetuo = GrowthEstimator.perpetual(
      explicitGrowth: g,
      economyGrowth: inputs.perpetualGrowthCap,
    );
    _auditPerpetualGrowth(audit, g, inputs.perpetualGrowthCap, perpetuo);

    // Vantagem competitiva residual, contínua desde a decisão 36: o que
    // sobrevive à perpetuidade é `φ^N` do excedente, com `φ` estimado da série
    // do próprio ativo. O veredito carrega o motivo da recusa e os dois valores
    // de `φ` — sem isso, um universo em que quase ninguém passa é
    // indistinguível de um universo em que quase ninguém merece passar.
    //
    // O excedente é medido contra a taxa de **equilíbrio**, e não contra a
    // corrente: é a perpetuidade que se está descrevendo, e usar a taxa do dia
    // faria a persistência do excedente andar com o ciclo monetário — o mesmo
    // erro que a decisão 34 removeu da fronteira das vias.
    //
    // **A taxa de equilíbrio contra a qual o excedente se mede é a resolvida,
    // não a interpolada** (decisão 44). O veredito é fechado uma vez com a
    // interpolação — que é o chute de que o ponto fixo parte — e refeito
    // contra a taxa que o ponto fixo devolve.
    // **Concessão não preserva excedente** (decisão 50): o que sai é a
    // afirmação que o contrato nega de frente — a de que o retorno excedente
    // do capital novo sobrevive para sempre num negócio que será relicitado.
    // O do capital existente acaba no fim do contrato, quando o prazo foi lido
    // do Formulário de Referência (decisão 88).
    final prazoDeterminado = ConcessionSectors.hasFiniteTerm(
      sectorKey: inputs.sectorKey,
      industry: inputs.industry,
    );

    final moatVeredito =
        _vereditoDoMoat(inputs, b, prazoDeterminado, descontoTerminal);
    // O veredito e o retorno terminal efetivamente aplicado são grandezas
    // distintas: o segundo pode vir imposto pelo DCF reverso. Manter os dois
    // separados é o que impede a narrativa de vantagem competitiva de afirmar
    // um veredito que não houve.
    final moatVerificado = moatVeredito.terminalReturn;
    final moat = inputs.terminalReturnOverride ?? moatVerificado;

    _auditDiscountTerm(audit, inputs, desconto, descontoTerminal);

    // Tolerância, e não igualdade estrita: os dois vêm de `_wacc` sobre os
    // mesmos insumos com taxas livres de risco diferentes, e quando as duas
    // coincidem o resultado é bit a bit idêntico — mas depender disso é depender
    // de determinismo de ponto flutuante para decidir se um aviso aparece. A
    // banda de 1e-7 é muito menor que qualquer diferença de taxa que valha ser
    // declarada (0,00001 p.p.) e maior que qualquer ruído de IEEE-754.
    final curvaDeJuros = inputs.riskFreeCurve;
    if (curvaDeJuros != null) {
      final ref = curvaDeJuros.referenceDate;
      final fw = curvaDeJuros.annualForwards(inputs.projectionYears);
      local.add(
        'A taxa livre de risco segue a curva dos títulos prefixados do Tesouro '
        'de ${ref.day.toString().padLeft(2, '0')}/'
        '${ref.month.toString().padLeft(2, '0')}/${ref.year}: '
        '${_pct(fw.first)} a.a. no primeiro ano, ${_pct(fw.last)} a.a. no ano '
        '${inputs.projectionYears} e ${_pct(inputs.terminalRiskFreeRate)} a.a. '
        'na perpetuidade. É a taxa que o mercado de títulos atribui a cada '
        'prazo, e não uma previsão do motor.',
      );
    } else if ((desconto - descontoTerminal).abs() > 1e-7) {
      local.add(
        'O desconto parte de ${_pct(desconto)} a.a. no primeiro ano e converge '
        'linearmente para ${_pct(descontoTerminal)} a.a. no ano '
        '${inputs.projectionYears}, que é a taxa da perpetuidade. A taxa livre '
        'de risco vai de ${_pct(inputs.capm.riskFreeRate)} para '
        '${_pct(inputs.terminalRiskFreeRate)}: sem curva de juros observada, '
        'descontar perpetuidade pelo CDI de um dia casaria durações '
        'incompatíveis.',
      );
    }

    if (lane == ValuationLane.firm &&
        aliquotaEstrutural != null &&
        (aliquotaEstrutural - ValuationParameters.statutoryTaxRate).abs() >
            0.01) {
      local.add(
        'O lucro operacional é tributado à alíquota estrutural do ativo, '
        '${_pct(aliquotaEstrutural)}, e não aos '
        '${_pct(ValuationParameters.statutoryTaxRate)} estatutários que a '
        'fonte embute em todo NOPAT publicado. É a mediana dos exercícios, '
        'não a do último: JCP, incentivo regional e lucro presumido são '
        'regime no Brasil, e regime é o que se projeta. O escudo fiscal do '
        'WACC continua na estatutária, que é a alíquota da margem.',
      );
    }

    if (inputs.terminalReturnOverride != null) {
      local.add(
        'Retorno terminal imposto em '
        '${_pct(inputs.terminalReturnOverride!)} por varredura externa. '
        'Este resultado é instrumento de diagnóstico, não avaliação: o '
        'veredito de vantagem competitiva foi ignorado.',
      );
    }

    // A narrativa e a auditoria do *moat* saem **depois** do ponto fixo, porque
    // o veredito pode ser refeito contra a taxa resolvida. Publicá-los aqui
    // afirmaria um veredito que a taxa final pode não sustentar.

    // O retorno que converte crescimento em retenção, ano a ano — `b_t = g_t /
    // ROIC_t` —, precisa ser o retorno **do fluxo-base que se está
    // descontando**, e não o do ciclo por princípio.
    //
    // Como o fluxo-base é `NOPAT_atual × fator` sobre a mesma base de capital,
    // o retorno implícito nele é `retorno_atual × fator`. A identidade fecha os
    // três casos de uma vez: normalizado sem saturar, dá exatamente o retorno do
    // ciclo; normalizado com saturação, dá o retorno que a saturação de fato
    // impôs; não normalizado, dá o retorno corrente.
    //
    // Usar o ciclo quando a base **não** foi normalizada misturava o fluxo de um
    // ano com o retorno de outro, e sempre na direção de exigir menos
    // reinvestimento do que a empresa precisa: medido na AZZA3, um retorno de
    // ciclo de 19,55% sobre um fluxo-base de retorno corrente de 7,82% inflava
    // o valor da firma em 17%.
    //
    // Sem retorno corrente utilizável — série curta, exercício de prejuízo ou
    // buraco na ponta —, o do ciclo continua sendo a melhor estimativa
    // disponível e é o que entra. Zerar ali **desligaria** o freio, que é a
    // direção agressiva: o fluxo cresceria sem nada retido para financiá-lo.
    final retornoDaBase = (retornoAtual != null && retornoAtual > 0)
        ? retornoAtual * fatorBase
        : (retornoCiclo ?? 0.0);

    final assumptions = DcfAssumptions(
      projectionYears: inputs.projectionYears,
      growthRate: g,
      perpetualGrowth: perpetuo,
      discountRate: desconto,
      terminalDiscountRate: descontoTerminal,
      returnOnCapital: retornoDaBase,
      terminalReturnOnCapital: moat,
      marginOfSafety: inputs.marginOfSafety,
      reinvestmentPolicy:
          inputs.reinvestmentOverride ?? ReinvestmentPolicy.medido,
      inflation: inputs.inflation,
      cashTiming: inputs.cashTimingOverride ?? CashTiming.meioDeAno,
      contractYearsAfterHorizon: _anosDeContratoAlemDaProjecao(inputs),
    );
    if (inputs.cashTimingOverride != null) {
      local.add(
        'Convenção de caixa imposta em '
        '"${inputs.cashTimingOverride!.name}" por varredura externa, no lugar '
        'do meio de ano. Este resultado é instrumento de diagnóstico, não '
        'avaliação.',
      );
    }
    if (inputs.reinvestmentOverride != null) {
      local.add(
        'Freio de reinvestimento imposto em '
        '"${inputs.reinvestmentOverride!.name}" por varredura externa, no '
        'lugar do `b = g/ROIC` medido. Este resultado é instrumento de '
        'diagnóstico, não avaliação.',
      );
    }

    return _Premissas(
      desconto: desconto,
      descontoTerminal: descontoTerminal,
      perpetuo: perpetuo,
      prazoDeterminado: prazoDeterminado,
      veredito: moatVeredito,
      moatVerificado: moatVerificado,
      moat: moat,
      retornoDaBase: retornoDaBase,
      assumptions: assumptions,
      keCorrente: inputs.capm.costOfEquity,
      keTerminal: capmTerminal.costOfEquity,
      custoDaDivida: custoCorrente.costOfDebt,
      spreadDeCredito: custoCorrente.creditSpread,
    );
  }

  /// Veredito da vantagem competitiva residual contra a taxa de equilíbrio
  /// [rInf] (decisões 36, 44 e 50).
  static MoatVerdict _vereditoDoMoat(
    ValuationInputs inputs,
    _Base b,
    bool prazoDeterminado,
    double rInf,
  ) =>
      GrowthGuards.residualMoat(
        cycleReturn: b.retornoCiclo,
        terminalDiscountRate: rInf,
        externalCapitalRatio: b.phi,
        periods: b.series.length,
        excessReturns: [
          for (final r in b.series.returns)
            if (r.value.isFinite) (year: r.year, excess: r.value - rInf),
        ],
        projectionYears: inputs.projectionYears,
        finiteTerm: prazoDeterminado,
      );

  /// **Saída 1 da Porta 2 — a base.**
  ///
  /// Monta a série de capital na alíquota estrutural e decide se o retorno do
  /// exercício mais recente converge ao do ciclo, com a precedência do ciclo em
  /// commodity, a trava de saúde operacional e a saturação do fator. Devolve
  /// `null` quando a série é curta demais, e aí a via não se aplica.
  static _Base? _saida1(_Via via, List<String> local) {
    final inputs = via.inputs;
    final published = via.published;
    final lane = via.lane;
    final audit = via.audit;
    // Alíquota estrutural do ativo, no lugar dos 34% que a fonte embute em
    // todo `NOPAT` publicado. Ela entra **na série e no fluxo-base ao mesmo
    // tempo**: mudar só o fluxo deixaria o ROIC na convenção antiga, e o freio
    // `b = g/ROIC` passaria a cobrar reinvestimento de um retorno que não é o
    // do fluxo que se está descontando — o mesmo defeito que a decisão 31
    // mediu em 17% na AZZA3.
    final aliquotaEstrutural = CapitalSeries.structuralTaxRate(
      published,
      statutoryRate: ValuationParameters.statutoryTaxRate,
    );
    final series = CapitalSeries.build(
      published,
      lane,
      firmTaxRate: aliquotaEstrutural,
    );
    if (series.isTooShort) return null;

    final retornoAtual = series.latestReturn;
    final retornoCiclo =
        series.cycleReturn(window: ValuationParameters.cycleWindow);
    // A deriva da tendência é medida na janela do ciclo, e **não** no horizonte
    // de projeção: um veredito estatístico sobre a série não pode mudar porque
    // o usuário trocou a projeção de 5 para 10 anos. Ver
    // [ValuationParameters.trendDriftWindow].
    final tendencia = GrowthGuards.trend(series);
    final phi = GrowthGuards.externalCapitalRatio(series);
    final destoa = GrowthGuards.deviatesFromCycle(series);

    final comparavel =
        phi == null || phi <= ValuationParameters.maxExternalCapital;

    // **A comparabilidade não trava a normalização.** Φ mede quanto da expansão
    // da base veio de fora, e é uma grandeza de *tamanho*; o que se normaliza
    // aqui é o **retorno percentual**, que é intensivo. Que a base tenha mudado
    // de escala por evento societário não torna o ROIC de um exercício de pico
    // um patamar perene: a rentabilidade percentual reverte à mediana do ciclo
    // independentemente do tamanho que a empresa passou a ter.
    //
    // Sob a precedência anterior, Φ > 1,0 impedia a normalização e o pico virava
    // base perene. A guarda passa a **declarar** a base inorgânica em vez de
    // barrar a correção do nível, e o fator continua sendo aplicado sobre a base
    // de capital corrente — a da empresa de hoje, já incorporada.
    //
    // **Em commodity, a Guarda 3 tem precedência sobre a Guarda 1.** A perna de
    // alta do ciclo tem exatamente a forma de uma tendência, e o teste a lê como
    // estrutural: a SUZB3 travou 41,5% de retorno corrente contra 18,4% de ciclo
    // e saiu a +259,1%. Em setor de commodity o preço reverte à média por
    // definição do produto, e nenhuma sequência de anos de alta muda isso — ver
    // [CyclicalSectors].
    final precedenciaDoCiclo = CyclicalSectors.hasCyclePrecedence(
      sectorKey: inputs.sectorKey,
      industry: inputs.industry,
    );
    final tendenciaTrava = tendencia?.dominates == true && !precedenciaDoCiclo;

    final normaliza = !tendenciaTrava &&
        destoa == true &&
        retornoAtual != null &&
        retornoCiclo != null &&
        retornoAtual > 0;

    // **Saúde operacional trava a normalização para cima.** A mesma medida que
    // barra o *moat*: empresa que perdeu mais da metade do resultado no triênio
    // mudou de patamar, e puxar a base dela de volta à mediana de oito anos
    // produz um retorno que ela não vai repetir. A QUAL3 perdeu a vantagem
    // residual na quarta rodada e continuou a +477,3% justamente por aqui — o
    // número não vinha da perpetuidade, vinha da base normalizada por 2,1x.
    //
    // Só o teto cai; o piso continua valendo. Quem deteriorou e ainda assim teve
    // um exercício acima do ciclo é normalizado para baixo normalmente, que é a
    // direção conservadora.
    final queda = GrowthGuards.recentOperationalDecline(published);
    final saudeReprovada =
        queda != null && queda > ValuationParameters.maxOperationalDecline;

    // **Setor cíclico é isento da trava, aqui e só aqui.** Em commodity a queda
    // de resultado entre pico e vale é oscilação do preço do insumo, e a trava
    // desfazia no vale exatamente a precedência que a decisão 28 estabeleceu:
    // VALE3 e GGBR4 acusavam quedas de 87% e iam a −70,3% e −92,7% de potencial.
    // O que limita a normalização em commodity é a saturação, que vale igual.
    //
    // A isenção **não alcança o *moat***: lá a pergunta é sobre o futuro do
    // retorno excedente, e um vale de ciclo não o sustenta melhor que uma
    // deterioração estrutural. `moatVeredito` recebe a queda sem filtro.
    final travaDeSaude = saudeReprovada && !precedenciaDoCiclo;
    final teto = travaDeSaude ? 1.0 : ValuationParameters.baseFactorCeiling;

    // O fator é saturado em razão, `1/3` a `3`. Sem teto ele explode quando o
    // exercício corrente tem retorno próximo de zero, e o DCF é homogêneo de
    // grau 1 no fluxo-base: a MBRF3 recebeu 21,4x e saiu a +406,1%.
    final fatorBruto = normaliza ? retornoCiclo / retornoAtual : 1.0;
    final fatorDecidido =
        normaliza ? fatorBruto.clamp(ValuationParameters.baseFactorFloor, teto) : 1.0;
    final fatorBase = inputs.baseFactorOverride ?? fatorDecidido;
    if (inputs.baseFactorOverride != null) {
      local.add(
        'Fator de normalização imposto em '
        '${fatorBase.toStringAsFixed(3)}x por varredura externa, no lugar do '
        '${fatorDecidido.toStringAsFixed(3)}x apurado. Este resultado é '
        'instrumento de diagnóstico, não avaliação.',
      );
    }

    // Os dois confinamentos são reportados em separado: um é a banda de
    // política, o outro é a trava de saúde, e atribuir um ao outro faria a
    // calibragem seguinte olhar para o parâmetro errado.
    final travadoPelaSaude = normaliza && travaDeSaude && fatorBruto > 1.0;
    final saturou = normaliza &&
        (fatorBruto > ValuationParameters.baseFactorCeiling ||
            fatorBruto < ValuationParameters.baseFactorFloor);

    _auditBaseGuards(audit, retornoAtual, retornoCiclo, tendencia, phi,
        destoa == true, normaliza, fatorBase, series,
        precedenciaDoCiclo: precedenciaDoCiclo,
        rawFactor: fatorBruto,
        saturated: saturou,
        operationalDecline: queda,
        healthCapped: travadoPelaSaude,
        healthExempt: saudeReprovada && precedenciaDoCiclo);

    if (normaliza) {
      local.add(
        'O retorno sobre o capital do exercício mais recente '
        '(${_pct(retornoAtual)}) destoa da mediana de '
        '${ValuationParameters.cycleWindow} exercícios (${_pct(retornoCiclo)}); '
        'a base converge para o ciclo ao longo da projeção, fator de '
        '${fatorBase.toStringAsFixed(2)}x.',
      );
      if (precedenciaDoCiclo && tendencia?.dominates == true) {
        local.add(
          'A tendência do retorno é significante e domina a reversão à média, '
          'mas o ativo é de setor de commodity ou cíclico pesado: ali a perna '
          'de alta do ciclo tem a forma de uma tendência, e lê-la como patamar '
          'estrutural é o erro que se quer evitar. A reversão ao ciclo tem '
          'precedência, e a base foi normalizada.',
        );
      }
      if (saudeReprovada && precedenciaDoCiclo && fatorBruto > 1.0) {
        local.add(
          'O lucro ou o EBITDA recuou ${_pct(queda)} no triênio, acima do '
          'máximo de ${_pct(ValuationParameters.maxOperationalDecline)}, mas o '
          'ativo é de setor de commodity: ali a queda entre pico e vale é '
          'oscilação do preço do insumo, não quebra de modelo de negócio. A '
          'trava de saúde não se aplica à base, e a convergência ao ciclo opera '
          'nos dois sentidos. A vantagem competitiva residual segue barrada por '
          'ela, sem isenção.',
        );
      }
      if (travadoPelaSaude) {
        local.add(
          'O lucro ou o EBITDA recuou ${_pct(queda)} no triênio recente, acima '
          'do máximo de ${_pct(ValuationParameters.maxOperationalDecline)}. A '
          'base **não foi normalizada para cima**: o fator seria de '
          '${fatorBruto.toStringAsFixed(2)}x e ficou em 1,00x. Uma empresa que '
          'perdeu mais da metade do resultado mudou de patamar, e trazer a base '
          'de volta à mediana de ${ValuationParameters.cycleWindow} exercícios '
          'atribuiria a ela um retorno que não vai se repetir.',
        );
      }
      if (saturou && !travadoPelaSaude) {
        local.add(
          'O fator bruto de normalização seria de '
          '${fatorBruto.toStringAsFixed(2)}x e foi saturado em '
          '${fatorBase.toStringAsFixed(2)}x. O limite é de política, não de '
          'estatística: o preço justo é proporcional ao fluxo-base, e acima de '
          '${ValuationParameters.baseFactorCeiling.toStringAsFixed(2)}x a '
          'normalização deixaria de corrigir um exercício para inventar uma '
          'empresa. O preço justo abaixo é, nesta medida, conservador.',
        );
      }
      if (!comparavel) {
        local.add(
          'A base de capital cresceu ${_r(phi, 2)}x além do que o lucro '
          'retido financiaria, o que indica evento societário ou aquisição. '
          'A normalização foi aplicada mesmo assim: o retorno percentual é '
          'grandeza intensiva, e reverte à mediana do ciclo qualquer que tenha '
          'sido a mudança de tamanho. O que a série não sustenta é comparar '
          '**níveis absolutos** de lucro entre as pontas da janela.',
        );
      }
    }

    return _Base(
      aliquota: aliquotaEstrutural,
      series: series,
      retornoAtual: retornoAtual,
      retornoCiclo: retornoCiclo,
      phi: phi,
      travaDeSaude: travaDeSaude,
      fator: fatorBase,
    );
  }

  /// **O fluxo-base da via**: o exercício mais recente vezes o fator do ciclo,
  /// ou, com o exercício no prejuízo, o retorno do ciclo sobre o capital de
  /// hoje. Devolve `null` sem base positiva, e aí a via não se aplica.
  ///
  /// **A normalização funcionava no pico e desligava no vale** (decisão 53).
  /// O fator é `ciclo ÷ atual` e exige denominador positivo, de modo que um
  /// exercício de prejuízo não era corrigido — era recusado. Numa siderúrgica
  /// o vale é metade do ciclo, e recusar ali descarta a empresa por causa de
  /// um ano.
  ///
  /// A reconstrução escreve a mesma conta de um jeito que sobrevive ao
  /// denominador: `fluxo-base = retorno do ciclo × capital de hoje`. As três
  /// condições são as que já existem, e nenhuma é nova:
  ///
  /// - **o ciclo tem de ser positivo e medível** — sem isso não há a que
  ///   voltar;
  /// - **o prejuízo tem de ser exceção** — ao menos
  ///   [ValuationParameters.minPositiveFlow] da janela positiva, que é o
  ///   mesmo corte com que a Porta 3 decide se um fluxo se sustenta. É ele
  ///   que separa o vale do declínio: a HBSA3 tem mediana de +0,2% com
  ///   metade da janela no prejuízo, e não volta.
  ///
  /// - **a trava de saúde tem de não reprovar** — a mesma que já impede a
  ///   normalização para cima em quem deteriorou, com a isenção cíclica da
  ///   decisão 30.
  ///
  /// **A trava foi retirada e reposta, por medição.** O argumento para tirá-la
  /// era de ordenação: ela devolve nulo quando a referência de três anos
  /// atrás também era prejuízo, de modo que aprova quem já perdia dinheiro lá
  /// atrás e reprova quem perdeu agora. Sem ela, porém, a RAPT4 entra a
  /// **+311,7% de potencial** — resultado caído 109% no triênio, e o
  /// fluxo-base reconstruído sobre um retorno de ciclo de 17,6% que a empresa
  /// acabou de deixar de ter. O risco que a trava controla é esse, e é
  /// assimétrico: reconstruir a base erra para cima. A ordenação imperfeita é
  /// o preço, e ele é menor.
  static ({double base, bool reconstruida})? _fluxoBase(
    _Via via,
    _Base b,
    List<String> local,
  ) {
    final lane = via.lane;
    final latest = via.latest;
    final divisor = via.divisor;
    final series = b.series;
    final retornoAtual = b.retornoAtual;
    final retornoCiclo = b.retornoCiclo;
    final fatorBase = b.fator;
    double? baseDoCiclo;
    if (retornoAtual != null &&
        retornoAtual <= 0 &&
        retornoCiclo != null &&
        retornoCiclo > 0 &&
        !b.travaDeSaude) {
      final fracao =
          series.positiveShare(window: ValuationParameters.cycleWindow);
      final capital = series.latestBase;
      if (fracao != null &&
          fracao >= ValuationParameters.minPositiveFlow &&
          capital != null &&
          capital > 0) {
        final total = retornoCiclo * capital;
        final porUnidade = lane == ValuationLane.firm
            ? total
            : (divisor.count > 0 ? total / divisor.count : null);
        if (porUnidade != null && porUnidade.isFinite && porUnidade > 0) {
          baseDoCiclo = porUnidade;
          local.add(
            'O exercício-base veio no prejuízo — retorno de '
            '${_pct(retornoAtual)} sobre o capital —, e o fluxo-base foi '
            'reconstruído do ciclo: ${_pct(retornoCiclo)} de retorno mediano '
            'sobre o capital de hoje, com ${_pct(fracao)} da janela positiva. '
            '**O preço justo não repousa em nenhum exercício recente '
            'observado**: repousa na afirmação de que a empresa volta ao que '
            'já foi.',
          );
        }
      }
    }

    final base = baseDoCiclo ??
        _baseProfitFor(
          lane,
          latest,
          divisor,
          fatorBase,
          b.aliquota,
        );
    if (base == null || base <= 0) return null;
    return (base: base, reconstruida: baseDoCiclo != null);
  }

  /// **Saída 2 da Porta 2 — de onde vem a taxa de crescimento.**
  ///
  /// Fundamental quando a dispersão da série a identifica; a inflação quando
  /// não identifica e a retenção observada a financia; zero no resto, que é o
  /// valor da capacidade de gerar lucro. Devolve `null` quando a dispersão não
  /// é medível, e aí a via não se aplica.
  static ({GrowthOrigin origem, double g})? _saida2(
    _Via via,
    _Base b,
    List<String> local,
  ) {
    final inputs = via.inputs;
    final series = b.series;
    final retornoCiclo = b.retornoCiclo;
    final audit = via.audit;
    final dispersao = GrowthGuards.dispersion(series);
    if (dispersao == null) return null;

    final retencao = series.medianRetention;
    final GrowthOrigin origem;
    final double gDecidido;
    if (dispersao.isIdentified) {
      origem = GrowthOrigin.fundamental;
      gDecidido = dispersao.medianGrowth;
    } else if (GrowthGuards.anchorIsFundable(
      inflation: inputs.inflation,
      cycleReturn: retornoCiclo,
      observedRetention: retencao,
    )) {
      origem = GrowthOrigin.inflationAnchor;
      gDecidido = inputs.inflation;
      local.add(
        'Crescimento fundamental não identificável: ${dispersao.failure}. '
        'Adotada a inflação de ${_pct(inputs.inflation)}, que a retenção '
        'observada de ${_pct(retencao ?? 0)} financia.',
      );
    } else {
      origem = GrowthOrigin.earningsPower;
      gDecidido = 0.0;
      local.add(
        'Crescimento não identificável nem financiável pela retenção observada; '
        'a avaliação é do valor da capacidade de gerar lucro, sem crescimento. '
        'É estimativa deliberadamente conservadora.',
      );
    }
    final g = inputs.growthOverride ?? gDecidido;
    if (inputs.growthOverride != null) {
      local.add(
        'Crescimento imposto em ${_pct(g)} por varredura externa, no lugar '
        'dos ${_pct(gDecidido)} que as guardas apuraram. Este resultado é '
        'instrumento de diagnóstico, não avaliação.',
      );
    }
    _auditGrowthOutcome(
        audit, dispersao, origem, g, retencao, retornoCiclo, inputs.inflation);
    return (origem: origem, g: g);
  }

  /// Reúne os fatos que qualificam o preço justo.
  ///
  /// **Não julga nada de novo.** Cada ressalva corresponde a uma decisão que a
  /// cascata já tomou e já declarou em texto; o que muda é que sai também em
  /// forma estruturada, para que a carteira possa ponderar por firmeza em vez
  /// de tratar todo preço justo como igualmente apoiado.
  /// A frase da participação do capital próprio, ou o motivo de não haver uma.
  ///
  /// Com caixa líquido maior que o próprio negócio, `E + D` fica não positivo
  /// e a razão não tem sentido. Dizer "0%" ali seria afirmar o que não se
  /// mediu.
  /// O que o prazo da concessão faz com a avaliação, em texto (decisão 88).
  ///
  /// [capitalApurado] é `false` quando não há retorno sobre o capital
  /// utilizável: sem ele o capital investido não se apura, e o terminal do
  /// contrato não pode ser montado.
  static String _avisoDoContrato(ValuationInputs inputs,
      {required bool capitalApurado}) {
    final n = inputs.projectionYears;
    const recusa = 'O excedente de retorno do capital novo é recusado, como em '
        'toda concessão: a tarifa remunera o capital ao custo dele.';
    const devolve = 'o que a amortização, a indenização do investimento não '
        'amortizado ou uma renovação que refaz a tarifa ao custo de capital '
        'devolvem';
    final fim = inputs.concessionEnd;
    final anos = contractYears(inputs);
    final anosTexto = n == 1 ? '1 ano' : '$n anos';
    if (fim != null && anos != null && capitalApurado) {
      if (anos <= n) {
        return 'O negócio opera sob concessão, e a mediana das outorgas '
            'vigentes no Formulário de Referência termina em ${_fmt(fim)}: a '
            'projeção explícita vai até lá, $anosTexto, e o valor terminal é o '
            'capital investido nessa data — $devolve —, sem excedente depois '
            'do contrato. $recusa';
      }
      final alem = anos - n;
      return 'O negócio opera sob concessão, e a mediana das outorgas vigentes '
          'no Formulário de Referência termina em ${_fmt(fim)}, $alem '
          '${alem == 1 ? "ano" : "anos"} depois da projeção. O valor terminal é '
          'o capital investido no fim da projeção mais o excedente de retorno '
          'sobre ele até o fim do contrato, e não para sempre: no fim, o '
          'capital volta — $devolve. $recusa';
    }
    final motivo = fim == null
        ? 'o prazo não foi lido do Formulário de Referência'
        : anos == null
            ? 'a mediana das outorgas declaradas no Formulário de Referência, '
                '${_fmt(fim)}, já passou'
            : 'sem retorno sobre o capital utilizável, o capital investido não '
                'se apura e o terminal do contrato não pode ser montado';
    return 'O negócio opera sob concessão, e $motivo. O valor terminal supõe o '
        'excedente de retorno sobre o capital existente para sempre; num '
        'contrato que acaba, ele acaba junto, e o preço justo fica abaixo do '
        'publicado — acima, se o capital rende menos que o custo dele. $recusa';
  }

  static String _trechoDaParticipacao(LeveredRates r, int n) {
    final inicio = r.equityShareAt(0);
    final fim = r.equityShareAt(n);
    if (inicio == null || fim == null) {
      return 'A participação do capital próprio no valor da firma não tem '
          'sentido aqui — o caixa líquido supera o próprio negócio.';
    }
    return 'A participação do capital próprio sai de ${_pct(inicio)} para '
        '${_pct(fim)} no mesmo intervalo — e é justamente o que a taxa única '
        'não enxergava.';
  }

  static ValuationDiagnostics _diagnose({
    required DcfOutcome outcome,
    required QuotedShares divisor,
    required double baseFactor,
    required GrowthOrigin growthOrigin,
    required bool moatApplied,
    required bool finiteTerm,
    required bool rebuiltBase,
    required double costOfEquity,
    required double terminalDiscountRate,
    required double terminalRetainedSpread,
    required double growthRate,
    required double returnOnCapital,
    required double? terminalReturnOnCapital,
    required double? firmTaxRate,
    required double? terminalCostOfEquity,
    required double? terminalEquityShare,
    required List<double> retentionPath,
    required List<double> growthPath,
  }) {
    final caveats = <ValuationCaveat>[];
    if (outcome.terminalShare > ValuationDiagnostics.terminalShareLimit) {
      caveats.add(ValuationCaveat.terminalPesado);
    }
    if (growthOrigin != GrowthOrigin.fundamental) {
      caveats.add(ValuationCaveat.crescimentoNaoIdentificado);
    }
    if (divisor.diverge && divisor.source != QuotedSharesSource.official) {
      caveats.add(ValuationCaveat.escalaIncerta);
    }
    if (baseFactor > ValuationDiagnostics.baseFactorLimit ||
        baseFactor < 1 / ValuationDiagnostics.baseFactorLimit) {
      caveats.add(ValuationCaveat.baseNormalizadaForte);
    }
    if (finiteTerm) caveats.add(ValuationCaveat.prazoDeterminado);
    if (rebuiltBase) caveats.add(ValuationCaveat.baseReconstruida);
    if (outcome.equityShare < ValuationDiagnostics.fragileEquityShare) {
      caveats.add(ValuationCaveat.ponteFragil);
    }
    // **O excedente perpétuo do capital instalado** (item B12): a parcela do
    // preço justo que vem de o terminal neutro manter para sempre o retorno
    // acima do custo sobre o ativo que já existe. O denominador é o valor do
    // capital próprio, o mesmo de `terminalShare`.
    final excedente = outcome.discountedTerminalExcess;
    final pesoDoExcedente = (excedente == null || outcome.equityValue <= 0)
        ? null
        : excedente / outcome.equityValue;
    return ValuationDiagnostics(
      terminalShare: outcome.terminalShare,
      terminalExcessShare: pesoDoExcedente,
      impliedTerminalReturn: outcome.impliedTerminalReturn,
      terminalEquityShare: terminalEquityShare,
      equityShare: outcome.equityShare,
      costOfEquity: costOfEquity,
      baseFactor: baseFactor,
      growthIdentified: growthOrigin == GrowthOrigin.fundamental,
      moatApplied: moatApplied,
      terminalDiscountRate: terminalDiscountRate,
      terminalRetainedSpread: terminalRetainedSpread,
      growthRate: growthRate,
      returnOnCapital: returnOnCapital,
      terminalReturnOnCapital: terminalReturnOnCapital,
      firmTaxRate: firmTaxRate,
      terminalCostOfEquity: terminalCostOfEquity,
      retentionPath: List.unmodifiable(retentionPath),
      growthPath: List.unmodifiable(growthPath),
      caveats: List.unmodifiable(caveats),
    );
  }

  /// Lucro-base da via, já normalizado pelo fator do ciclo.
  ///
  /// Na via da firma é o NOPAT; na do acionista, o lucro por papel na unidade
  /// negociada. Multiplicar o lucro observado pelo fator equivale a partir do
  /// retorno do ciclo aplicado à base de capital corrente, e mantém a escala da
  /// empresa de hoje — que é o que a winsorização contra a mediana absoluta
  /// perdia ao misturar ciclo com crescimento de tamanho.
  static double? _baseProfitFor(
    ValuationLane lane,
    FundamentalsSnapshot latest,
    QuotedShares divisor,
    double fatorBase,
    double? firmTaxRate,
  ) {
    if (lane == ValuationLane.firm) {
      final n = latest.nopatAtRate(firmTaxRate);
      return n == null ? null : n * fatorBase;
    }
    final lpa = _earningsPerQuotedUnit(latest, divisor);
    return lpa == null ? null : lpa * fatorBase;
  }

  /// Lucro por **unidade negociada**, na mesma escala do preço de tela.
  ///
  /// Divide o lucro agregado pela contagem que forma a cotação, e não pela do
  /// exercício: o resultado é comparado com o preço de hoje, e um LPA na escala
  /// societária de outro momento não o é. O recuo para o LPA publicado só age
  /// quando o lucro agregado falta, e converte pela razão de unidade.
  static double? _earningsPerQuotedUnit(
    FundamentalsSnapshot snapshot,
    QuotedShares divisor,
  ) {
    final netIncome = snapshot.netIncome;
    if (netIncome != null && divisor.count > 0) {
      return netIncome / divisor.count;
    }
    final published = snapshot.earningsPerShare;
    return published == null ? null : published * divisor.sharesPerQuote;
  }
  /// Monta o WACC, ou o Ke quando a estrutura de capital não é observável.
  ///
  /// - [capmOverride]: substitui o CAPM dos insumos. Serve para montar o custo
  ///   de capital **de equilíbrio**, com a taxa livre de risco estrutural no
  ///   lugar da corrente, sem duplicar esta função.
  /// Devolve a taxa **e** se o custo da dívida usado foi estimado.
  ///
  /// O segundo campo não é detalhe de log: ele entra nos diagnósticos do
  /// resultado, e recalculá-lo fora daqui duplicaria a regra de
  /// `CostOfCapital`.
  static ({
    double rate,
    bool costOfDebtEstimated,
    double? costOfDebt,
    double creditSpread,
  }) _wacc(
    ValuationInputs inputs,
    FundamentalsSnapshot latest,
    List<String> warnings,
    QuotedShares divisor,
    AuditTransaction? audit, {
    CapmInputs? capmOverride,
    bool terminal = false,
  }) {
    final capm = capmOverride ?? inputs.capm;
    // **A dívida dos pesos é a líquida** (decisão 104), a mesma que a apuração
    // do capital próprio subtrai, que a realavancagem da decisão 41 pondera e
    // contra a qual o beta é desalavancado (decisão 54). A bruta continua sendo
    // o denominador do custo da dívida observado, que é razão sobre o que de
    // fato paga juro.
    final bruta = latest.totalDebt;
    // `D/E` imposto na perpetuidade é imposição de diagnóstico do B15, e só
    // vale na montagem de equilíbrio: a corrente é a estrutura observada.
    final imposto = terminal ? inputs.terminalLeverageOverride : null;
    final debt = imposto == null
        ? latest.netDebt
        : divisor.count * inputs.marketPrice * imposto;
    // O peso do capital próprio é o valor de mercado **pelo divisor da ponte**,
    // e não o `marketCap` da fonte (decisão 83). Quando o divisor é a contagem
    // implícita no valor de mercado, os dois são o mesmo número; quando a
    // fonte erra a contagem — a MILS3 com R$ 762 mil de capitalização —, o
    // divisor já foi arbitrado, e o WACC não pode readquirir o erro.
    // **O minoritário não entra neste peso** (lente `metodo`, 21/09/2026; item
    // B23). O fluxo descontado é o **consolidado**, e este `E` é o valor de
    // mercado da **controladora**: a fatia dos não controladores fica fora do
    // denominador `E + D`, o que infla a participação da dívida e achata o
    // WACC. **O obstáculo é o dado** — o valor de mercado do minoritário não é
    // observável, e só o contábil existe.
    //
    // **E a assimetria é interna**: o caminho **resolvido** pondera pelo
    // capital próprio que o modelo produz, `V − D` sobre fluxo consolidado, que
    // já inclui o minoritário. Só o estático — que é o recuo — fica de fora.
    // [ValuationInputs.minorityEquityValue] mede o que mudaria.
    final equity =
        divisor.count * inputs.marketPrice + (inputs.minorityEquityValue ?? 0);

    // O observado entra apenas como **conferência**: desde a decisão 31 o Kd
    // aplicado é `Rf + spread(cobertura)`, e como `capm` aqui pode ser o de
    // equilíbrio, o custo da dívida do terminal decai junto com a taxa livre de
    // risco, preservando o prêmio de crédito. Medido numa empresa de cobertura
    // 3,7x: 16,49% no corrente contra 11,80% no terminal, com os mesmos 2,40
    // p.p. de spread. Ver `CostOfCapital.effectiveCostOfDebt`.
    final kd = latest.costOfDebt;
    // O escudo fiscal usa a alíquota **marginal estatutária**, não a efetiva do
    // exercício: o benefício do endividamento é o valor presente dos escudos
    // futuros, que se realizam à alíquota legal. A efetiva continua sendo
    // medida e declarada quando destoa — ver
    // [ValuationParameters.statutoryTaxRate].
    const tax = ValuationParameters.statutoryTaxRate;
    final efetiva = latest.effectiveTaxRate;

    // **Quando a estrutura é mesmo desconhecida, e não só sem dívida.** Duas
    // situações, e só elas: sem valor de mercado utilizável não há peso a
    // formar; e com dívida contratada cujo custo não é medível — despesa
    // financeira ausente — não há `K_d` a ponderar.
    //
    // **Companhia sem dívida e com caixa não entra aqui** (lente `metodo`,
    // 20/09/2026). Ela tem estrutura conhecida: dívida líquida **negativa**, e
    // a apuração do capital próprio devolve esse caixa ao acionista. Degenerar
    // para o `Ke` devolveria o caixa duas vezes — uma no desconto brando, outra
    // na apuração —, que é o defeito que a decisão 104 corrigiu para quem tem
    // dívida. O que falta ali é o prêmio de crédito, e não o peso: sem dívida
    // contratada o `K_d` é a taxa livre de risco, que é o que caixa rende
    // (decisão 58).
    final semDividaContratada = bruta <= 0;
    // A faixa que decide se a despesa financeira é juro de dívida é medida na
    // taxa da **data**, e não na do cenário nem na de equilíbrio: é pergunta
    // sobre o dado do exercício (item B10). Ver
    // [ValuationInputs.creditReferenceRiskFree].
    final referencia = inputs.creditReferenceRiskFree ?? inputs.capm.riskFreeRate;
    // **O prêmio de crédito existe mesmo quando o WACC estático não** (item
    // B26). Ele é o que o ponto fixo recebe, e o ponto fixo não precisa do
    // valor de mercado — pondera pelo capital próprio que a própria avaliação
    // produz. Com o prêmio derivado do custo que o WACC estático devolvia, a
    // degeneração dele zerava o prêmio, e o caminho resolvido tomava dinheiro
    // à taxa livre de risco: a NATU3 descontava a 16,3% com `Ke` de 21,0%.
    final premio = semDividaContratada
        ? 0.0
        : CostOfCapital.syntheticSpread(
            leverage: latest.netDebtToEbitda,
            coverage: latest.interestCoverage,
            observedCostOfDebt: kd,
            riskFreeRate: referencia,
          );

    // **Só a falta de valor de mercado impede o WACC estático** (item B26).
    // Até 22/09/2026 a despesa financeira ausente também o impedia — «não há
    // `K_d` a ponderar» —, o que contradizia a decisão 31: desde ela o `K_d` é
    // a classificação sintética, e a alavancagem não precisa da despesa.
    if (equity <= 0) {
      warnings.add(
        'Estrutura de capital indisponível: sem valor de mercado utilizável o '
        'WACC estático não é montável, e quando o custo de capital não é '
        'resolvido ano a ano o desconto é o custo do capital próprio.',
      );
      audit?.step(
        formulaName: 'Taxa de desconto — degeneração para o Ke',
        latex: r'r = K_e \quad (\text{sem estrutura de capital observável})',
        variables: {
          'D bruta (R\$)': _r(bruta),
          'D líquida (R\$)': _r(debt),
          'E (R\$)': _r(equity),
          'K_d (% a.a.)': kd == null ? null : _r(kd * 100),
        },
        steps: const [
          'Passo único: dívida, valor de mercado ou custo da dívida ausentes; '
              'o WACC não é montável e o desconto adota o custo do capital '
              'próprio.',
        ],
        result: capm.costOfEquity * 100,
        unit: '% a.a.',
      );
      return (
        rate: capm.costOfEquity,
        costOfDebtEstimated: false,
        costOfDebt: null,
        creditSpread: premio,
      );
    }

    if (efetiva != null && (efetiva - tax).abs() > 0.10) {
      warnings.add(
        'A alíquota efetiva do exercício foi de ${_pct(efetiva)}, distante da '
        'alíquota marginal estatutária de ${_pct(tax)} usada no escudo fiscal '
        'do WACC. O escudo desconta despesa financeira **futura**, que se '
        'realiza à alíquota legal; a efetiva de um exercício carrega '
        'incentivo, JCP, prejuízo compensado e diferimento.',
      );
    }

    final coc = CostOfCapital(
      capm: capm,
      costOfDebt: kd,
      taxRate: tax,
      equityValue: equity,
      debtValue: debt,
      interestCoverage: latest.interestCoverage,
      netDebtToEbitda: latest.netDebtToEbitda,
      creditReferenceRate: referencia,
      hasContractedDebt: !semDividaContratada,
      // **O caixa entra separado, e rende a taxa livre de risco** (lente
      // `metodo`, 21/09/2026). Sem ele, a perna negativa da dívida líquida
      // seria remunerada ao custo de **empréstimo**, e um balanço com mais
      // caixa que dívida ganharia um WACC baixo demais. Com `D/E` imposto o
      // corte não existe — a dívida ali é arbitrada, não observada —, e a
      // forma colapsa na anterior.
      cashValue: imposto == null ? latest.totalCash : null,
    );

    if (semDividaContratada) {
      warnings.add(
        '${inputs.ticker.value} não tem dívida contratada nos demonstrativos: '
        'o que sobra do lado do financiamento é caixa, e ele entra no desconto '
        'com peso negativo e rendimento igual à taxa livre de risco '
        '(${_pct(capm.riskFreeRate)} a.a.). O caixa sai da taxa e volta na '
        'apuração do capital próprio — contá-lo só de um lado inflaria o preço '
        'justo.',
      );
    }
    if (!semDividaContratada && kd == null) {
      final alavancagem = latest.netDebtToEbitda;
      warnings.add(
        'A despesa financeira de ${inputs.ticker.value} não está publicada: a '
        'cobertura de juros não é medível, e o prêmio de crédito sai só da '
        'alavancagem'
        '${alavancagem == null ? ', que também não é medível — prêmio máximo' : ' (${alavancagem.toStringAsFixed(2)}x de dívida líquida sobre EBITDA)'}'
        '. Custo da dívida adotado: ${_pct(coc.effectiveCostOfDebt)} a.a.',
      );
    }
    if (!semDividaContratada && coc.costOfDebtWasClamped) {
      final alavancagem = latest.netDebtToEbitda;
      warnings.add(
        'O custo da dívida implícito nos demonstrativos deu '
        '${_pct(kd!)} a.a., fora da faixa defensável de '
        '${_pct(referencia)} a '
        '${_pct(referencia + CostOfCapital.maxCreditSpread)}. A despesa '
        'financeira publicada inclui arrendamento e variação cambial, que não '
        'são captação. Adotado ${_pct(coc.effectiveCostOfDebt)} a.a., da '
        'classificação sintética por alavancagem'
        '${alavancagem == null ? ' (dívida líquida sobre EBITDA não medível)' : ' de ${alavancagem.toStringAsFixed(2)}x'}.',
      );
    }
    if (coc.waccWasFloored) {
      warnings.add(
        'O WACC calculado (${_pct(coc.rawWacc)} a.a.) ficou abaixo da taxa '
        'livre de risco; adotada a própria taxa livre de risco '
        '(${_pct(capm.riskFreeRate)} a.a.) como piso do desconto.',
      );
    }
    // **Caixa líquido**: o peso da dívida é negativo e o WACC fica acima do Ke.
    // É consequência da convenção — a ponte devolve o caixa ao acionista, de
    // modo que o fluxo descontado é o do ativo operacional sozinho —, e fica
    // declarada em vez de aparecer como taxa inexplicada na tela (decisão 104).
    if (debt < 0 && coc.totalCapital > 0) {
      warnings.add(
        '${inputs.ticker.value} tem caixa líquido: o peso da dívida no WACC é '
        'negativo (${_r(coc.debtShare, 4)}) e o desconto fica acima do custo '
        'do capital próprio. A conta é a mesma dos dois lados — o caixa sai da '
        'taxa e volta na apuração do capital próprio, que subtrai a dívida '
        'líquida.',
      );
    }

    _auditWacc(audit, coc);
    return (
      rate: coc.wacc,
      costOfDebtEstimated: coc.costOfDebtWasClamped,
      costOfDebt: coc.effectiveCostOfDebt,
      creditSpread: premio,
    );
  }

  /// O fator que traduz o deslocamento do cenário em deslocamento do `Ke`
  /// (item B20, decisão 121).
  ///
  /// A participação sai do **caminho resolvido** quando há um — `E ÷ (E + D)`
  /// no ano zero, que é a estrutura que a própria avaliação produziu —, e do
  /// WACC estático quando não há. Participação fora de `(0, 1]` devolve 1: com
  /// caixa líquido ela passa de 1 e o fator viraria **redutor**, o que nenhuma
  /// das três leituras quer dizer.
  static double _fatorDoCenario(_Via via, _Custo custo) {
    final leitura = via.inputs.scenarioTranslation;
    if (leitura == ScenarioTranslation.umPorUm) return 1.0;

    final taxas = custo.taxas;
    double? pesoE;
    if (taxas != null && taxas.equity.isNotEmpty && taxas.debt.isNotEmpty) {
      final v = taxas.equity.first + taxas.debt.first;
      if (v > 0) pesoE = taxas.equity.first / v;
    } else {
      final e = via.divisor.count * via.inputs.marketPrice;
      final v = e + via.latest.netDebt;
      if (v > 0) pesoE = e / v;
    }
    if (pesoE == null || !pesoE.isFinite || pesoE <= 0 || pesoE > 1) {
      return 1.0;
    }

    return switch (leitura) {
      ScenarioTranslation.umPorUm => 1.0,
      // `ΔWACC = w_E·ΔK_e` com `K_d` e os pesos parados.
      ScenarioTranslation.estruturaFixa => 1 / pesoE,
      // `ΔWACC = ΔR_f·(w_E + w_D(1−t))` quando os dois custos sobem junto com
      // a taxa livre de risco, e `ΔK_e = ΔR_f`.
      ScenarioTranslation.taxaLivreDeRisco => 1 /
          (1 -
              (1 - pesoE) * ValuationParameters.statutoryTaxRate),
    };
  }

  static String _pct(double fraction) =>
      '${(fraction * 100).toStringAsFixed(1)}%';

  /// O aviso da triangulação, quando as duas leituras discordam além do limite.
  ///
  /// **Ele não escolhe.** Diz quanto cada uma vale, de quantos pares saiu a
  /// segunda, e que o preço justo continua sendo o do fluxo descontado. Um
  /// aviso que sugerisse a média estaria propondo um terceiro modelo que
  /// ninguém validou.
  static String _avisoDaTriangulacao(PeerTriangulation t, double dcf) {
    final aplicadas = [
      for (final r in t.readings)
        if (r.applied)
          '${r.kind.diagnostico} ${_r(r.peer!.median, 2)}× '
              '(${r.peer!.peers} pares, ${r.peer!.group})',
    ];
    return 'A leitura por múltiplos de pares diverge do fluxo descontado: '
        'R\$ ${_r(t.consolidated!, 2)} contra R\$ ${_r(dcf, 2)}, '
        '${_pct(t.divergence!)} de diferença. '
        'Saiu de ${aplicadas.join("; ")}. '
        '**O preço justo continua sendo o do fluxo descontado** — a segunda '
        'leitura é teste de sanidade sobre o nível, e a divergência fica '
        'declarada em vez de reconciliada.';
  }
  static ValuationResult _withScenarios({
    required ValuationInputs inputs,
    required ValuationModel model,
    required DcfAssumptions assumptions,
    required double baseValue,
    required Result<double> Function(DcfAssumptions) valuate,
    required AssumptionSource Function(DcfAssumptions)? scenarioBuilder,
    required int samples,
    required int seed,
    required List<String> warnings,
    required ValuationDiagnostics diagnostics,
    PeerTriangulation? triangulation,
  }) {
    final source = (scenarioBuilder ?? DiscreteScenarios.around)(assumptions);
    final volatilidade = inputs.prices == null
        ? null
        : CalibratedBand.trailingVolatility(inputs.prices!);
    final outcome = ScenarioEngine.run(
      source: source,
      valuate: valuate,
      samples: samples,
      seed: seed,
    );

    if (outcome.isErr) {
      return ValuationResult(
        ticker: inputs.ticker,
        asOf: inputs.asOf,
        model: model,
        fairValue: Money.fromReais(baseValue),
        marketPrice: Money.fromReais(inputs.marketPrice),
        // **A taxa do ano 1, e não o campo escalar** (item B11): com o
        // caminho resolvido, `discountRate` guarda o chute da interpolação,
        // e o que desconta o primeiro fluxo é `discountRateAt(1)`. Exibir o
        // chute mostrava na tela uma taxa que a conta não usou.
        discountRate: assumptions.discountRateAt(1),
        marginOfSafety: inputs.marginOfSafety,
        warnings: [
          ...warnings,
          'Cenários não puderam ser gerados; apresentado apenas o cenário base.',
        ],
        diagnostics: diagnostics,
        priceVolatility: volatilidade,
        triangulation: triangulation,
      );
    }

    final scenarios = outcome.unwrap();
    final local = [...warnings];
    if (scenarios.discarded > 0 && scenarios.mode == ScenarioMode.monteCarlo) {
      final pct = scenarios.discarded / math.max(1, samples) * 100;
      if (pct > 5) {
        local.add(
          '${pct.toStringAsFixed(0)}% dos sorteios foram descartados por '
          'produzirem valor inválido; estreite as faixas de premissas.',
        );
      }
    }

    return ValuationResult(
      ticker: inputs.ticker,
      asOf: inputs.asOf,
      model: model,
      fairValue: Money.fromReais(baseValue),
      marketPrice: Money.fromReais(inputs.marketPrice),
      discountRate: assumptions.discountRateAt(1),
      marginOfSafety: inputs.marginOfSafety,
      mode: scenarios.mode,
      discreteScenarios: scenarios.discrete?.map(
        (band, value) => MapEntry(band, Money.fromReais(value)),
      ),
      distribution: scenarios.distribution,
      warnings: local,
      diagnostics: diagnostics,
      priceVolatility: volatilidade,
      triangulation: triangulation,
    );
  }

  static String _fmt(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  // ------------------------------------------------------------ Auditoria --
  //
  // Tudo daqui para baixo é rastro, não cálculo: cada função recebe valores
  // **já computados** pelo caminho normal e apenas os descreve. Nenhuma linha
  // aqui recalcula nada, e é isso que garante que o que a auditoria mostra é o
  // que o resultado usa — uma segunda implementação da mesma fórmula, escrita
  // para exibição, divergiria da primeira no dia em que alguém mexesse em uma
  // e esquecesse a outra.
  //
  // Todas saem cedo quando não há transação aberta, de modo que o custo com a
  // auditoria desligada é uma comparação com `null`.

  /// Arredonda para o JSON: `num` em vez de `String` para o valor continuar
  /// sendo número no payload exportado.
  ///
  /// **O que não é finito passa como é** (item D4). Até 22/09/2026 ele virava
  /// `0`, e um `NaN` ou um infinito — o sinal de que uma conta degenerou —
  /// aparecia no rastro como zero, que é o valor mais enganoso possível numa
  /// depuração. Agora ele chega ao rastro e sai no JSON como `"NaN"` ou
  /// `"Infinity"`, pela serialização segura de [AuditJson].
  static num _r(double value, [int decimals = 2]) {
    if (!value.isFinite) return value;
    if (decimals <= 0) return value.round();
    final factor = math.pow(10, decimals);
    return (value * factor).round() / factor;
  }

  static Map<String, dynamic> _inputPayload(ValuationInputs inputs) {
    // Os exercícios entram resumidos e limitados aos mais recentes: o payload
    // atravessa a fronteira entre abas do navegador, e dezesseis exercícios
    // com vinte campos cada só encheriam a tela sem informar mais.
    final recent = inputs.fundamentals.length <= 6
        ? inputs.fundamentals
        : inputs.fundamentals.sublist(inputs.fundamentals.length - 6);

    return {
      'ticker': inputs.ticker.value,
      'asOf': inputs.asOf.toIso8601String(),
      'marketPrice': _r(inputs.marketPrice),
      'capm': {
        'riskFreeRate': _r(inputs.capm.riskFreeRate, 6),
        'beta': _r(inputs.capm.beta, 4),
        'marketPremium': _r(inputs.capm.marketPremium, 6),
        'betaSource': inputs.capm.betaSource.name,
        'premiumSource': inputs.capm.premiumSource.name,
      },
      'marginOfSafety': _r(inputs.marginOfSafety, 4),
      'projectionYears': inputs.projectionYears,
      if (inputs.concessionEnd != null)
        'concessionEnd': _fmt(inputs.concessionEnd!),
      'perpetualGrowthCap': _r(inputs.perpetualGrowthCap, 6),
      'fundamentalsPeriods': inputs.fundamentals.length,
      // Quantos exercícios ficaram de fora do resumo abaixo — o rastro diz que
      // resumiu, em vez de parecer que a série tinha seis.
      'fundamentalsOmitted': inputs.fundamentals.length - recent.length,
      'fundamentals': [
        for (final f in recent)
          {
            'fiscalPeriodEnd': f.fiscalPeriodEnd.toIso8601String(),
            'netIncome': f.netIncome == null ? null : _r(f.netIncome!),
            'ebitda': f.ebitda == null ? null : _r(f.ebitda!),
            'operatingCashFlow':
                f.operatingCashFlow == null ? null : _r(f.operatingCashFlow!),
            'freeCashFlow':
                f.freeCashFlow == null ? null : _r(f.freeCashFlow!),
            'sharesOutstanding':
                f.sharesOutstanding == null ? null : _r(f.sharesOutstanding!, 0),
            'marketCap': f.marketCap == null ? null : _r(f.marketCap!),
            'totalDebt': _r(f.totalDebt),
            'netDebt': _r(f.netDebt),
            'effectiveTaxRate': f.effectiveTaxRate == null
                ? null
                : _r(f.effectiveTaxRate!, 4),
            'enterpriseToEbitda': f.enterpriseToEbitda == null
                ? null
                : _r(f.enterpriseToEbitda!, 4),
            'bookValuePerShare': f.bookValuePerShare == null
                ? null
                : _r(f.bookValuePerShare!),
          },
      ],
      // **O resto do que entra na conta** (item D4). O payload trazia preço,
      // CAPM e exercícios; a curva, a contagem oficial, a composição da unit,
      // o prior do beta e as imposições de diagnóstico mudam o preço justo e
      // não apareciam — depurar pelo JSON exigia adivinhar com que insumo a
      // cascata tinha rodado.
      'scenarioTranslation': inputs.scenarioTranslation.name,
      'sectorKey': inputs.sectorKey,
      'industry': inputs.industry,
      'isDistressed': inputs.isDistressed,
      'inflation': _r(inputs.inflation, 6),
      'terminalRiskFreeRate': _r(inputs.terminalRiskFreeRate, 6),
      if (inputs.riskFreeCurve case final curva?)
        'riskFreeCurve': {
          'referenceDate': _fmt(curva.referenceDate),
          'vertices': [
            for (final v in curva.vertices)
              {'years': _r(v.years, 4), 'rate': _r(v.rate, 6)},
          ],
        },
      if (inputs.officialShares case final oficial?)
        'officialShares': {
          'total': _r(oficial.total, 0),
          'asOf': _fmt(oficial.asOf),
        },
      'declaredSharesPerUnit': inputs.declaredSharesPerUnit,
      'unleveredBeta':
          inputs.unleveredBeta == null ? null : _r(inputs.unleveredBeta!, 4),
      'betaWindowYears': inputs.betaWindowYears == null
          ? null
          : _r(inputs.betaWindowYears!, 2),
      'dividendsInBeta': inputs.dividendsInBeta,
      'creditReferenceRiskFree': inputs.creditReferenceRiskFree == null
          ? null
          : _r(inputs.creditReferenceRiskFree!, 6),
      'minorityEquityValue': inputs.minorityEquityValue == null
          ? null
          : _r(inputs.minorityEquityValue!),
      if (inputs.prices case final serie?)
        'prices': {
          'points': serie.points.length,
          if (serie.points.isNotEmpty) 'first': _fmt(serie.points.first.date),
          if (serie.points.isNotEmpty) 'last': _fmt(serie.points.last.date),
        },
      if (inputs.peerMultiples case final pares?)
        'peerMultiples': {
          'asOf': _fmt(pares.asOf),
          for (final e in pares.byKind.entries)
            e.key.name: {
              'median': _r(e.value.median, 4),
              'peers': e.value.peers,
              'group': e.value.group,
            },
        },
      'overrides': {
        if (inputs.laneOverride case final v?) 'lane': v.name,
        if (inputs.terminalReturnOverride case final v?)
          'terminalReturn': _r(v, 6),
        if (inputs.growthOverride case final v?) 'growth': _r(v, 6),
        if (inputs.baseFactorOverride case final v?) 'baseFactor': _r(v, 4),
        if (inputs.reinvestmentOverride case final v?) 'reinvestment': v.name,
        if (inputs.cashTimingOverride case final v?) 'cashTiming': v.name,
        if (inputs.terminalBetaWeightOverride case final v?)
          'terminalBetaWeight': _r(v, 4),
        if (inputs.terminalLeverageOverride case final v?)
          'terminalLeverage': _r(v, 4),
      },
      if (inputs.contextNotes.isNotEmpty) 'contextNotes': inputs.contextNotes,
    };
  }

  static Map<String, dynamic> _outputPayload(ValuationResult result) => {
        'status': 'ok',
        'ticker': result.ticker.value,
        'model': result.model.diagnostico,
        'fairValue': _r(result.fairValue.reais),
        'safetyPrice': _r(result.safetyPrice.reais),
        'marketPrice': _r(result.marketPrice.reais),
        'upside': _r(result.upside, 6),
        'discountRate': _r(result.discountRate, 6),
        'marginOfSafety': _r(result.marginOfSafety, 4),
        'isUndervalued': result.isUndervalued,
        'scenarioMode': result.mode.name,
        if (result.discreteScenarios != null)
          'discreteScenarios': {
            for (final e in result.discreteScenarios!.entries)
              e.key.name: _r(e.value.reais),
          },
        if (result.distribution != null && !result.distribution!.isEmpty)
          'distribution': {
            'samples': result.distribution!.sortedValues.length,
            'p5': _r(result.distribution!.p5),
            'median': _r(result.distribution!.median),
            'p95': _r(result.distribution!.p95),
            'mean': _r(result.distribution!.mean),
            'probabilityAboveMarket': _r(
              result.distribution!
                  .probabilityAbove(result.marketPrice.reais),
              4,
            ),
          },
        // **O diagnóstico inteiro, e não cinco campos** (item D4). A tela lê o
        // `Ke`, o caminho de crescimento e o retorno terminal; o rastro
        // exportado precisa ter o mesmo, ou a depuração do JSON não reproduz a
        // tela.
        if (result.diagnostics case final d?)
          'diagnostics': {
            'terminalShare': _r(d.terminalShare, 4),
            'equityShare': _r(d.equityShare, 4),
            'baseFactor': _r(d.baseFactor, 4),
            'growthIdentified': d.growthIdentified,
            'moatApplied': d.moatApplied,
            'caveats': [for (final c in d.caveats) c.name],
            'terminalRetainedSpread': _r(d.terminalRetainedSpread, 6),
            'growthRate': _r(d.growthRate, 6),
            'terminalReturnOnCapital': d.terminalReturnOnCapital == null
                ? null
                : _r(d.terminalReturnOnCapital!, 6),
            'firmTaxRate':
                d.firmTaxRate == null ? null : _r(d.firmTaxRate!, 6),
            'returnOnCapital': _r(d.returnOnCapital, 6),
            'terminalDiscountRate': _r(d.terminalDiscountRate, 6),
            'terminalCostOfEquity': d.terminalCostOfEquity == null
                ? null
                : _r(d.terminalCostOfEquity!, 6),
            'costOfEquity': _r(d.costOfEquity, 6),
            'terminalExcessShare': d.terminalExcessShare == null
                ? null
                : _r(d.terminalExcessShare!, 4),
            'impliedTerminalReturn': d.impliedTerminalReturn == null
                ? null
                : _r(d.impliedTerminalReturn!, 6),
            'terminalEquityShare': d.terminalEquityShare == null
                ? null
                : _r(d.terminalEquityShare!, 4),
            'growthPath': [for (final g in d.growthPath) _r(g, 6)],
            'retentionPath': [for (final b in d.retentionPath) _r(b, 6)],
          },
        // O insumo da faixa calibrada, que a tela monta com ele (decisão 100).
        'priceVolatility': result.priceVolatility == null
            ? null
            : _r(result.priceVolatility!, 6),
        if (result.triangulation case final t?)
          'triangulation': {
            'asOf': _fmt(t.asOf),
            'consolidated':
                t.consolidated == null ? null : _r(t.consolidated!),
            'divergence': t.divergence == null ? null : _r(t.divergence!, 4),
            'readings': [
              for (final r in t.readings)
                {
                  'kind': r.kind.name,
                  'fairValuePerShare': r.fairValuePerShare == null
                      ? null
                      : _r(r.fairValuePerShare!),
                  'refusal': r.refusal?.name,
                  if (r.peer case final p?)
                    'peer': {
                      'median': _r(p.median, 4),
                      'peers': p.peers,
                      'group': p.group,
                    },
                },
            ],
          },
        'warnings': result.warnings,
      };

  static void _auditUnitRatio(
    AuditTransaction? audit,
    ValuationInputs inputs,
    FundamentalsSnapshot latest,
    double sharesPerQuote, {
    required double medida,
    required int? declarada,
  }) {
    if (audit == null) return;
    final shares = latest.sharesOutstanding;
    final cap = latest.marketCap;
    final raw = (shares != null && cap != null && cap > 0)
        ? shares * inputs.marketPrice / cap
        : null;

    audit.step(
      formulaName: 'Razão da unidade negociada',
      latex: declarada != null
          ? r'u = u_{declarada} \quad ; \quad '
              r'u_{medida} = \mathrm{round}\!\left('
              r'\frac{N_{ações} \cdot P_{mkt}}{VM}\right)'
          : r'u = \mathrm{round}\!\left(\frac{N_{ações} \cdot P_{mkt}}{VM}\right)',
      variables: {
        'N_ações': shares == null ? null : _r(shares, 0),
        'P_mkt (R\$)': _r(inputs.marketPrice),
        'VM (R\$)': cap == null ? null : _r(cap),
        'u_declarada': declarada,
        'u_medida': _r(medida, 0),
      },
      steps: [
        if (raw == null)
          'Passo 1: quantidade de ações ou valor de mercado ausentes; a razão '
              'medida cai na convenção de ação comum (u = 1).'
        else ...[
          'Passo 1: razão medida → ${_r(shares!, 0)} × '
              '${_r(inputs.marketPrice)} ÷ ${_r(cap!)} = ${_r(raw, 4)}',
          'Passo 2: arredondamento e teste de plausibilidade (1 ≤ u ≤ '
              '${_r(maxSharesPerUnit, 0)}, desvio relativo ≤ '
              '${_r(unitRatioTolerance * 100, 0)}%) → u medida = '
              '${_r(medida, 0)}',
        ],
        if (declarada != null)
          'Passo 3: a composição declarada no formulário cadastral da CVM diz '
              '$declarada ${declarada == 1 ? 'ação' : 'ações'} por unit, e é '
              'ela que vale; a medida fica como conferência (item B16)'
        else
          'Passo 3: sem composição declarada para este papel; vale a razão '
              'medida, e a avaliação declara que ela foi inferida',
      ],
      result: sharesPerQuote,
      unit: 'ações por papel negociado',
    );
  }

  static double _razao(double a, double b) => a >= b ? a / b : b / a;

  static void _auditQuotedShares(
    AuditTransaction? audit,
    FundamentalsSnapshot latest,
    double marketPrice,
    QuotedShares divisor,
  ) {
    if (audit == null) return;
    final vm = latest.marketCap;
    audit.step(
      formulaName: 'Contagem de papéis da ponte',
      latex: r'N_{ponte} = \max\!\left(\frac{VM}{P_{mkt}},\; '
          r'\frac{N_{conciliado}}{u}\right)'
          r'\;\;\text{na divergência};\;\; \frac{VM}{P_{mkt}}\;\;\text{fora dela}',
      variables: {
        'VM (R\$)': vm == null ? null : _r(vm),
        'P_mkt (R\$)': _r(marketPrice),
        'N pelo mercado': divisor.fromMarketCap == null
            ? null
            : _r(divisor.fromMarketCap!, 0),
        'N pelas demonstrações': divisor.fromStatements == null
            ? null
            : _r(divisor.fromStatements!, 0),
        'divergência (x)':
            divisor.divergence == null ? null : _r(divisor.divergence!, 3),
        'N oficial da B3, líquido de tesouraria': divisor.fromRegistry == null
            ? null
            : _r(divisor.fromRegistry!, 0),
      },
      steps: [
        'Passo 1: contagem implícita no valor de mercado → '
            '${vm == null ? 'valor de mercado ausente' : '${_r(vm)} ÷ ${_r(marketPrice)} = ${_r(divisor.fromMarketCap ?? 0, 0)}'}',
        'Passo 2: contagem conciliada pelas demonstrações, na unidade '
            'negociada → ${_r(divisor.fromStatements ?? 0, 0)}',
        'Passo 3: as duas ${divisor.diverge ? 'divergem além da banda de ${FundamentalsSnapshot.reconciliationBand}x; adotada a maior, que é o sentido conservador do erro' : 'concordam dentro da banda de ${FundamentalsSnapshot.reconciliationBand}x; adotada a do mercado'} → '
            '${divisor.source.diagnostico}',
        if (divisor.fromRegistry != null)
          'Passo 4: registro oficial da B3 de ${_fmt(divisor.registryAsOf!)} → '
              '${divisor.source == QuotedSharesSource.official ? 'adotado; ele arbitra a divergência da fonte' : 'recusado; antigo demais e sem concordar com a fonte'}',
      ],
      result: _r(divisor.count, 0).toDouble(),
      unit: 'papéis na unidade negociada',
    );
  }

  static void _auditCapm(
      AuditTransaction? audit, CapmInputs capm, int proventosNoBeta) {
    if (audit == null) return;
    final risk = capm.beta * capm.marketPremium;
    audit.step(
      formulaName: 'Custo do capital próprio (CAPM)',
      latex: r'K_e = R_f + \beta \cdot (R_m - R_f)',
      variables: {
        'R_f (% a.a.)': _r(capm.riskFreeRate * 100),
        'beta': _r(capm.beta, 4),
        'R_m - R_f (% a.a.)': _r(capm.marketPremium * 100),
        'origem do beta': capm.betaSource.name,
        'retorno do beta': proventosNoBeta > 0
            ? 'total, $proventosNoBeta proventos reinvestidos'
            : 'de preço',
      },
      steps: [
        'Passo 1: prêmio ajustado ao risco sistemático → ${_r(capm.beta, 4)} × '
            '${_pct(capm.marketPremium)} = ${_pct(risk)}',
        'Passo 2: soma à taxa livre de risco → ${_pct(capm.riskFreeRate)} + '
            '${_pct(risk)} = ${_pct(capm.costOfEquity)}',
      ],
      result: _r(capm.costOfEquity * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditWacc(AuditTransaction? audit, CostOfCapital coc) {
    if (audit == null) return;
    final kd = coc.effectiveCostOfDebt;
    final afterTax = kd * (1 - coc.effectiveTaxShield);
    final equityLeg = coc.equityShare * coc.costOfEquity;
    // **A perna do financiamento se abre em duas quando o caixa é conhecido**
    // (lente `metodo`, 21/09/2026): dívida bruta ao custo de empréstimo, caixa
    // ao rendimento da taxa livre de risco. O registro tem de mostrar a forma
    // que a conta usou — repetir a de uma perna só faria o Passo 5 fechar num
    // número diferente do resultado.
    final wBruta = coc.grossDebtShare;
    final wCaixa = coc.cashShare;
    final separa = wBruta != null && wCaixa != null;
    final rendimento = coc.afterTaxCashYield;
    final debtLeg = separa
        ? wBruta * afterTax - wCaixa * rendimento
        : coc.debtShare * afterTax;
    // **O Passo 3 diz a regra que a conta usa** (item B25, lente `metodo`,
    // 22/09/2026). Ele escrevia «observado fora da banda; limitado a X» e
    // «observado dentro da banda → X», que é a regra anterior à decisão 31 —
    // limitar o observado a uma banda. Desde ela o `K_d` é sempre `R_f` mais o
    // prêmio sintético, e o observado só arbitra se a cobertura pode falar:
    // um leitor do rastro concluía que o custo observado entrava na taxa.
    final porAlavancagem = CostOfCapital.leverageSpread(coc.netDebtToEbitda);
    final referencia = coc.creditReferenceRate ?? coc.capm.riskFreeRate;
    final observado = coc.costOfDebt;
    final despesaFala = observado != null &&
        observado >= referencia &&
        observado <= referencia + CostOfCapital.maxCreditSpread;
    final porCobertura = CostOfCapital.coverageSpread(coc.interestCoverage);
    final passo3 = !coc.hasContractedDebt
        ? 'Passo 3: sem dívida contratada não há prêmio de crédito → K_d = R_f '
            '= ${_pct(kd)}'
        : 'Passo 3: K_d = R_f + prêmio sintético → prêmio pela alavancagem '
            '(${coc.netDebtToEbitda == null ? '—' : _r(coc.netDebtToEbitda!, 2)}× '
            'dívida líquida ÷ EBITDA) = ${_pct(porAlavancagem)}; '
            '${observado == null ? 'a despesa financeira não está publicada, e a '
                'cobertura sai da conta' : despesaFala ? 'a despesa observada '
                '(${_pct(observado)} da dívida) está na banda, e a cobertura '
                'fala → prêmio pela cobertura = ${_pct(porCobertura)}, vale o '
                'maior' : 'a despesa observada (${_pct(observado)} da dívida) '
                'está fora da banda e mede outra coisa, e a cobertura sai da '
                'conta'} → '
            '${_pct(coc.capm.riskFreeRate)} + '
            '${_pct(kd - coc.capm.riskFreeRate)} = ${_pct(kd)}. O observado '
            'não entra na taxa';

    audit.step(
      formulaName: 'Custo médio ponderado de capital (WACC)',
      latex: separa
          ? r'WACC = \frac{E}{E+D_{liq}}\,K_e + '
              r'\frac{D_{bruta}}{E+D_{liq}}\,K_d\,(1 - t) - '
              r'\frac{C}{E+D_{liq}}\,R_f\,(1 - \tau)'
          : r'WACC = \frac{E}{E+D_{liq}}\,K_e + '
              r'\frac{D_{liq}}{E+D_{liq}}\,K_d\,(1 - t)',
      variables: {
        'E (R\$)': _r(coc.equityValue),
        'D líquida (R\$)': _r(coc.debtValue),
        if (separa) 'D bruta (R\$)': _r(coc.debtValue + coc.cashValue!),
        if (separa) 'C — caixa (R\$)': _r(coc.cashValue!),
        'K_e (% a.a.)': _r(coc.costOfEquity * 100),
        'K_d (% a.a.)': _r(kd * 100),
        if (separa) 'R_f (% a.a.)': _r(coc.capm.riskFreeRate * 100),
        't (%)': _r(coc.effectiveTaxShield * 100),
      },
      steps: [
        'Passo 1: participação do capital próprio → ${_r(coc.equityValue)} ÷ '
            '${_r(coc.totalCapital)} = ${_r(coc.equityShare, 4)}',
        if (separa)
          'Passo 2: participação da dívida bruta → '
              '${_r(coc.debtValue + coc.cashValue!)} ÷ '
              '${_r(coc.totalCapital)} = ${_r(wBruta, 4)}; e do caixa → '
              '${_r(coc.cashValue!)} ÷ ${_r(coc.totalCapital)} = '
              '${_r(wCaixa, 4)}. A diferença das duas é a participação da '
              'dívida líquida, ${_r(coc.debtShare, 4)} — o que a separação '
              'muda é a **taxa** de cada metade, e não o peso'
        else
          'Passo 2: participação do capital de terceiros → '
              '${_r(coc.debtValue)} ÷ ${_r(coc.totalCapital)} = '
              '${_r(coc.debtShare, 4)}',
        passo3,
        'Passo 4: benefício fiscal da dívida → ${_pct(kd)} × (1 − '
            '${_r(coc.effectiveTaxShield, 4)}) = ${_pct(afterTax)}',
        if (separa)
          'Passo 5: o caixa rende a taxa livre de risco, tributada → '
              '${_pct(coc.capm.riskFreeRate)} × (1 − ${_r(coc.taxRate, 4)}) = '
              '${_pct(rendimento)}. Soma ponderada → '
              '${_r(coc.equityShare, 4)} × ${_pct(coc.costOfEquity)} + '
              '${_r(wBruta, 4)} × ${_pct(afterTax)} − ${_r(wCaixa, 4)} × '
              '${_pct(rendimento)} = ${_pct(equityLeg)} + ${_pct(debtLeg)} = '
              '${_pct(coc.rawWacc)}'
        else
          'Passo 5: soma ponderada → ${_r(coc.equityShare, 4)} × '
              '${_pct(coc.costOfEquity)} + ${_r(coc.debtShare, 4)} × '
              '${_pct(afterTax)} = ${_pct(equityLeg)} + ${_pct(debtLeg)} = '
              '${_pct(coc.rawWacc)}',
        if (coc.waccWasFloored)
          'Passo 6: WACC abaixo da taxa livre de risco; adotado o piso de '
              '${_pct(coc.capm.riskFreeRate)}'
        else
          'Passo 6: WACC acima da taxa livre de risco; nenhum piso aplicado',
      ],
      result: _r(coc.wacc * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  /// Registra as três guardas da Saída 1 e o veredito sobre a base.
  static void _auditBaseGuards(
    AuditTransaction? audit,
    double? retornoAtual,
    double? retornoCiclo,
    TrendVerdict? tendencia,
    double? phi,
    bool destoa,
    bool normaliza,
    double fator,
    CapitalSeries series, {
    required bool precedenciaDoCiclo,
    required double rawFactor,
    required bool saturated,
    required double? operationalDecline,
    required bool healthCapped,
    required bool healthExempt,
  }) {
    if (audit == null) return;
    audit.step(
      sample: _returnSample(series, retornoCiclo, retornoAtual, normaliza),
      formulaName: 'Base do fluxo: normalização pelo ciclo',
      latex: r'fluxo_0 = NOPAT_{atual} \cdot \frac{r_{ciclo}}{r_{atual}}',
      variables: {
        'retorno atual (% a.a.)': _r((retornoAtual ?? 0) * 100),
        'mediana do ciclo (% a.a.)': _r((retornoCiclo ?? 0) * 100),
        'inclinação da tendência (p.p./ano)':
            tendencia == null ? 'n/d' : _r(tendencia.slope * 100, 2),
        't de Newey-West': tendencia == null ? 'n/d' : _r(tendencia.tStatistic, 2),
        'capital externo / base (Φ)': phi == null ? 'n/d' : _r(phi, 2),
        // Chaves de leitura por máquina, pelo mesmo motivo das do passo da
        // vantagem residual: sem elas, "a base não foi normalizada" não diz
        // qual guarda decidiu, e a calibragem vira suposição.
        'guarda 1 — tendência': tendencia == null
            ? 'não avaliável'
            : (tendencia.dominates ? 'domina' : 'não domina'),
        'guarda 3 — desvio do ciclo':
            destoa ? 'destoa' : 'dentro da banda e do desvio robusto',
        'precedência do ciclo (setor cíclico)': precedenciaDoCiclo,
        'fator bruto': _r(rawFactor, 3),
        'fator saturado': saturated,
        'queda no triênio (%)':
            operationalDecline == null ? null : _r(operationalDecline * 100),
        'teto travado pela saúde': healthCapped,
        'isento da trava por setor cíclico': healthExempt,
      },
      steps: [
        'Guarda 1 — tendência: '
            '${tendencia == null ? "não avaliável" : (tendencia.dominates ? (precedenciaDoCiclo ? "domina a reversão, mas o setor é cíclico: a Guarda 3 tem precedência" : "domina a reversão, base mantida") : (tendencia.isSignificant ? "significante, mas a reversão é maior" : "sem tendência"))}',
        'Guarda 2 — comparabilidade (declara, não barra): '
            '${phi == null ? "não avaliável" : (phi <= ValuationParameters.maxExternalCapital ? "expansão orgânica, base comparável" : "capital externo de ${_r(phi, 2)}x a base inicial, base inorgânica")}',
        'Guarda 3 — desvio do ciclo: '
            '${destoa ? "o exercício destoa" : "dentro da banda e do desvio robusto"}',
        normaliza
            ? 'Base normalizada por ${fator.toStringAsFixed(2)}x, convergindo ao longo da projeção'
            : 'Base mantida como observada',
        if (healthCapped)
          'Saúde operacional: queda de '
              '${operationalDecline == null ? "n/d" : _pct(operationalDecline)} '
              'no triênio; o teto do fator cai para 1,00x e a base não é '
              'normalizada para cima',
        if (healthExempt)
          'Saúde operacional: queda de '
              '${operationalDecline == null ? "n/d" : _pct(operationalDecline)} '
              'no triênio, mas o setor é cíclico — isento da trava na Porta 2a. '
              'A vantagem residual segue barrada por ela',
        if (saturated)
          'Saturação: o fator bruto de ${rawFactor.toStringAsFixed(2)}x saiu da '
              'banda de [${ValuationParameters.baseFactorFloor}, '
              '${ValuationParameters.baseFactorCeiling}] e foi confinado a '
              '${fator.toStringAsFixed(2)}x',
      ],
      result: _r(fator, 3).toDouble(),
      unit: 'fator sobre o lucro observado',
    );
  }

  /// Amostra de retorno que sustenta a mediana do ciclo.
  ///
  /// Substitui a amostra do fluxo-base, que saiu com a decisão 25: o
  /// normalizador passou a operar sobre o **retorno** sobre a base de capital, e
  /// é essa a série que precisa ficar visível para quem confere a conta.
  static TraceSample? _returnSample(
    CapitalSeries series,
    double? ciclo,
    double? atual,
    bool normaliza,
  ) {
    final r = series.returns;
    if (r.length < 3) return null;
    final ini = r.length - 1 - ValuationParameters.cycleWindow;
    final janela = r.sublist(ini < 0 ? 0 : ini);

    // Marcação por **posição na ordenação**, não por valor: com exercícios de
    // retorno repetido, comparar por valor marcaria três ou quatro pontos e
    // daria a entender que todos entraram na conta. Exatamente um ponto é
    // marcado numa amostra ímpar, exatamente dois numa par.
    final ordem = [for (var i = 0; i < janela.length; i++) i]
      ..sort((a, b) => janela[a].value.compareTo(janela[b].value));
    final meio = ordem.length ~/ 2;
    final centrais = ordem.length.isOdd
        ? {ordem[meio]}
        : {ordem[meio - 1], ordem[meio]};

    return TraceSample(
      title: series.lane == ValuationLane.firm
          ? 'Retorno sobre o capital investido, por exercício'
          : 'Retorno sobre o patrimônio, por exercício',
      points: [
        for (var i = 0; i < janela.length; i++)
          TraceSamplePoint(
            label: '${janela[i].year}',
            value: _r(janela[i].value * 100).toDouble(),
            definesResult: centrais.contains(i) && i != janela.length - 1,
            isObserved: i == janela.length - 1,
          ),
      ],
      summary: ciclo == null ? null : _r(ciclo * 100).toDouble(),
      summaryLabel: 'mediana do ciclo',
      selected: (normaliza && ciclo != null)
          ? _r(ciclo * 100).toDouble()
          : (atual == null ? null : _r(atual * 100).toDouble()),
      unit: '%',
    );
  }

  /// Registra a Saída 2: qual estimador decidiu a taxa, e por quê.
  static void _auditGrowthOutcome(
    AuditTransaction? audit,
    DispersionVerdict d,
    GrowthOrigin origem,
    double g,
    double? retencao,
    double? retornoCiclo,
    double inflacao,
  ) {
    if (audit == null) return;
    final exigida =
        (retornoCiclo != null && retornoCiclo > 0) ? inflacao / retornoCiclo : null;
    audit.step(
      formulaName: 'Crescimento explícito',
      latex: r'g = \mathrm{mediana}\left(\frac{\Delta \text{base}_t}{\text{base}_{t-1}}\right)',
      variables: {
        'g pela mediana (% a.a.)': _r(d.medianGrowth * 100),
        'g pela regressão (% a.a.)': _r(d.regressionGrowth * 100),
        'erro-padrão de ĝ (p.p.)': _r(d.stdError * 100, 2),
        'discordância D': _r(d.d, 2),
        'D crítico': _r(d.criticalD, 2),
        'retenção observada (%)': retencao == null ? 'n/d' : _r(retencao * 100),
      },
      steps: [
        'Passo 1: precisão e concordância → '
            '${d.isIdentified ? "crescimento identificável" : d.failure}',
        if (!d.isIdentified)
          'Passo 2: a inflação de ${_pct(inflacao)} exigiria reter '
              '${exigida == null ? "n/d" : _pct(exigida)} contra '
              '${retencao == null ? "n/d" : _pct(retencao)} observados → '
              '${origem == GrowthOrigin.inflationAnchor ? "âncora aceita" : "âncora recusada"}',
        'Origem adotada: ${origem.diagnostico}',
      ],
      result: _r(g * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditPerpetualGrowth(
    AuditTransaction? audit,
    double explicitGrowth,
    double economyGrowth,
    double perpetual,
  ) {
    if (audit == null) return;
    audit.step(
      formulaName: 'Crescimento na perpetuidade',
      latex: r'g_\infty = \mathrm{clamp}\big(\min(g,\, g_{eco}),\, 0,\, g_{eco}\big)',
      variables: {
        'g (% a.a.)': _r(explicitGrowth * 100),
        'g_eco nominal (% a.a.)': _r(economyGrowth * 100),
      },
      steps: [
        'Passo 1: menor entre o crescimento explícito e o da economia → '
            'min(${_pct(explicitGrowth)}, ${_pct(economyGrowth)}) = '
            '${_pct(explicitGrowth < economyGrowth ? explicitGrowth : economyGrowth)}',
        'Passo 2: confinado a [0, ${_pct(economyGrowth)}] — uma empresa não '
            'cresce acima da economia para sempre → ${_pct(perpetual)}. '
            'O teto é **nominal**: composto do crescimento real da atividade com '
            'a inflação observada, porque a taxa de desconto também é nominal, '
            'por sair do CDI. Não é o PIB real.',
      ],
      result: _r(perpetual * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditDiscountTerm(
    AuditTransaction? audit,
    ValuationInputs inputs,
    double spot,
    double terminal,
  ) {
    if (audit == null) return;
    audit.step(
      formulaName: 'Estrutura a termo da taxa de desconto',
      latex: r'r_t = r_{spot} - (r_{spot} - r_\infty)\cdot\frac{t-1}{N-1}',
      variables: {
        'R_f corrente (% a.a.)': _r(inputs.capm.riskFreeRate * 100),
        'R_f estrutural (% a.a.)': _r(inputs.terminalRiskFreeRate * 100),
        'r_spot (% a.a.)': _r(spot * 100),
        'r_inf (% a.a.)': _r(terminal * 100),
        'N (anos)': inputs.projectionYears,
      },
      steps: [
        'Passo 1: o custo de capital do ano 1 usa a taxa livre de risco '
            'corrente → ${_pct(spot)}',
        'Passo 2: o custo de capital de equilíbrio repete beta, prêmio e '
            'estrutura de capital sobre a taxa estrutural → ${_pct(terminal)}. '
            'Como Ke e WACC são afins na taxa livre de risco, decair o custo de '
            'capital equivale a decair a taxa e remontar o custo a cada ano',
        'Passo 3: a perpetuidade é descontada a ${_pct(terminal)}, e o fator de '
            'desconto acumula as taxas ano a ano em vez de elevar uma só a t',
      ],
      result: _r(terminal * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditMoat(AuditTransaction? audit, MoatVerdict v) {
    if (audit == null) return;
    final ciclo = v.cycleReturn;
    final excedente = v.spread;
    audit.step(
      formulaName: 'Vantagem competitiva residual na perpetuidade',
      latex:
          r'ROIC_\infty = WACC_\infty + \varphi^{N}(ROIC_{ciclo} - WACC_\infty)',
      variables: {
        'ROIC do ciclo (% a.a.)': ciclo == null ? null : _r(ciclo * 100),
        'WACC de equilíbrio (% a.a.)': _r(v.terminalDiscountRate * 100),
        'excedente do ciclo (p.p.)':
            excedente == null ? null : _r(excedente * 100),
        'Phi': v.externalCapitalRatio == null
            ? null
            : _r(v.externalCapitalRatio!, 2),
        'exercícios': v.periods,
        'phi cru (AR(1))':
            v.rawPersistence == null ? null : _r(v.rawPersistence!, 4),
        'phi aplicado': v.persistence == null ? null : _r(v.persistence!, 4),
        'pares na regressão': v.persistencePoints,
        'lambda': v.retainedFraction == null
            ? null
            : _r(v.retainedFraction!, 4),
        'condição que barrou': v.primaryBlock?.name ?? 'nenhuma',
        'condições que barraram': [for (final b in v.blocks) b.name],
      },
      steps: [
        'Passo 1: crescimento orgânico? Phi = '
            '${v.externalCapitalRatio == null ? "não medido" : _r(v.externalCapitalRatio!, 2)} '
            '${v.externalCapitalRatio != null && v.externalCapitalRatio! <= ValuationParameters.moatMaxExternalCapital ? "<=" : ">"} '
            '${ValuationParameters.moatMaxExternalCapital}',
        'Passo 2: histórico longo? ${v.periods} exercícios contra '
            '${ValuationParameters.moatMinPeriods} exigidos',
        'Passo 3: excedente positivo? ROIC do ciclo de '
            '${ciclo == null ? "não medido" : _pct(ciclo)} contra WACC de '
            'equilíbrio de ${_pct(v.terminalDiscountRate)}',
        'Passo 4: persistência do excedente por AR(1) sobre '
            '${v.persistencePoints} pares — phi cru '
            '${v.rawPersistence == null ? "não estimável" : _r(v.rawPersistence!, 4)}, '
            'confinado em '
            '${v.persistence == null ? "—" : _r(v.persistence!, 4)}; '
            'lambda = phi^N = '
            '${v.retainedFraction == null ? "—" : _r(v.retainedFraction!, 4)}',
        v.isProven
            ? 'Passo 5: há excedente e ele persiste — ROIC_inf = '
                '${_pct(v.terminalReturn!)}, e o valor terminal volta a depender '
                'de g_inf, que é o preço declarado da exceção'
            : 'Passo 5: barrado por ${v.blocks.map((b) => b.diagnostico).join(", ")} — '
                'vale o estado estacionário, ROIC_inf = WACC_inf, e o valor '
                'terminal não depende de g_inf',
      ],
      // O resultado é o retorno terminal **efetivamente adotado**: o do moat
      // quando as três condições valem, o próprio custo de capital quando não.
      // Nunca nulo — a etapa decidiu algo em qualquer dos dois caminhos.
      result: _r((v.terminalReturn ?? v.terminalDiscountRate) * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditDcf(
    AuditTransaction? audit, {
    required DcfOutcome outcome,
    required DcfAssumptions assumptions,
    required double baseFlow,
    required String flowSymbol,
    required String discountSymbol,
    bool perShareAlready = false,
  }) {
    if (audit == null) return;
    final r = assumptions.discountRate;
    final rInf = assumptions.terminalDiscountRate;
    final g = assumptions.growthRate;
    final gInf = assumptions.perpetualGrowth;
    final n = outcome.projectedFlows.length;
    final sumPv = outcome.enterpriseValue - outcome.discountedTerminalValue;

    // O rastro precisa reproduzir a conta que foi feita, e a conta usa taxa,
    // crescimento e retenção **variáveis** ano a ano. Descrevê-la com g e r
    // constantes escrevia números que não fecham com o resultado ao lado: num
    // ativo típico, o fluxo do ano 10 aparecia 2,45x maior que o efetivamente
    // usado, e o fator de desconto 1,21x maior. O fator abaixo é o mesmo
    // acumulado que `DcfCalculator._project` monta.
    var fator = 1.0;
    final fatores = <double>[];
    for (var t = 1; t <= n; t++) {
      fator *= 1 + assumptions.discountRateAt(t);
      fatores.add(fator);
    }

    // **A convenção de caixa entra na fórmula, não só na conta** (decisão
    // 48). O rastro existe para reproduzir o que foi feito, e um LaTeX que
    // omite o levantamento de meio de ano descreve um desconto 6% maior que
    // o aplicado — exatamente a divergência que a auditoria existe para
    // impedir.
    final meioDeAno = assumptions.cashTiming == CashTiming.meioDeAno;
    audit.step(
      formulaName: 'Projeção e desconto do período explícito ($flowSymbol)',
      latex: meioDeAno
          ? r'VP_{explícito} = \sum_{t=1}^{N} '
              r'\frac{L_t\,(1 - b_t)\,\sqrt{1 + r_t}}{\prod_{s=1}^{t}(1 + r_s)}'
              r'\quad;\quad L_t = L_{t-1}(1 + g_t),\; b_t = g_t / ROIC_t'
          : r'VP_{explícito} = \sum_{t=1}^{N} '
              r'\frac{L_t\,(1 - b_t)}{\prod_{s=1}^{t}(1 + r_s)}'
              r'\quad;\quad L_t = L_{t-1}(1 + g_t),\; b_t = g_t / ROIC_t',
      variables: {
        'F_0': _r(baseFlow),
        'g_1 (% a.a.)': _r(g * 100),
        'g_N (% a.a.)': _r(assumptions.growthAt(n) * 100),
        'r_1 = $discountSymbol (% a.a.)': _r(r * 100),
        'r_N (% a.a.)': _r(assumptions.discountRateAt(n) * 100),
        'ROIC_1 (% a.a.)': _r(assumptions.returnOnCapitalAt(1) * 100),
        'N (anos)': assumptions.projectionYears,
      },
      steps: [
        'Passo 0: as taxas decaem linearmente ao longo da janela. O fator de '
            'desconto **acumula** a taxa de cada ano em vez de elevar uma só a '
            't, e o fluxo do ano é o lucro menos a retenção que financia o '
            'crescimento daquele mesmo ano.',
        if (meioDeAno)
          'Passo 0b: o caixa do exercício chega ao longo do ano, e não no '
              'último dia dele. Cada fluxo é levantado por raiz de (1 + r '
              'do ano) — a convenção de meio de ano da decisão 48.',
        for (var t = 1; t <= n; t++)
          'Passo $t: ano $t → g = ${_pct(assumptions.growthAt(t))}, '
              'retenção = ${_pct(assumptions.retentionAt(t))}, '
              'r = ${_pct(assumptions.discountRateAt(t))}; fluxo '
              '${_r(outcome.projectedFlows[t - 1])} ÷ fator acumulado '
              '${_r(fatores[t - 1], 6)} → valor presente '
              '${_r(outcome.discountedFlows[t - 1])}',
        'Passo ${n + 1}: soma dos valores presentes do período explícito → '
            '${_r(sumPv)}',
      ],
      result: sumPv,
      unit: perShareAlready ? r'R$ por papel' : r'R$',
    );

    // Três formas de terminal, e o rastro precisa dizer qual foi aplicada. Com
    // retorno neutro o crescimento perpétuo **sai** da fórmula, e exibir o
    // spread de Gordon ali descreveria uma conta que não foi feita. A taxa é
    // sempre a de equilíbrio, nunca a corrente.
    //
    // O ramo de retenção só existe quando não há retorno terminal declarado
    // **e** o retorno neutro está desligado — caminho que a cascata não usa,
    // mas que a classe permite a quem monta premissas à mão.
    final moat = assumptions.terminalReturnOnCapital;
    final neutro = moat == null && assumptions.neutralTerminalReturn;
    // **A concessão tem terminal próprio, e o rastro tem de dizê-lo** (lente
    // `metodo`, 21/09/2026). Com prazo, o terminal é `capital_N + EVA·anuidade`
    // (decisão 88), e imprimir a perpetuidade de Gordon ali descrevia uma conta
    // que não foi feita — o mesmo defeito que a ponte `EV − D` tinha.
    final contrato =
        neutro ? assumptions.contractYearsAfterHorizon : null;
    final reinvestimento = moat != null
        ? (gInf / moat).clamp(0.0, 0.95)
        : assumptions.retentionAt(assumptions.projectionYears);
    final fatorFinal = n == 0 ? 1.0 : fatores[n - 1];
    final vtForma = contrato != null
        ? r'VT = K_N + EVA_{N+1}\,'
            r'\frac{1 - (1+r_\infty)^{-M}}{r_\infty}'
        : neutro
            ? r'VT = \frac{L_{N+1}}{r_\infty}'
            : r'VT = \frac{L_{N+1}\,(1 - b_\infty)}{r_\infty - g_\infty}';
    // O valor presente do terminal carrega o mesmo levantamento dos fluxos,
    // sob a taxa de equilíbrio, que é a que o capitaliza.
    final vpForma = meioDeAno
        ? r'VP(VT) = \frac{VT\,\sqrt{1 + r_\infty}}{\prod_{s=1}^{N}(1+r_s)}'
        : r'VP(VT) = \frac{VT}{\prod_{s=1}^{N}(1+r_s)}';
    const separadorLatex = r'\quad;\quad ';
    audit.step(
      formulaName: contrato != null
          ? 'Valor terminal (contrato com prazo: capital devolvido e excedente '
              'até o fim)'
          : neutro
              ? 'Valor terminal (retorno neutro, RONIC_inf = r_inf)'
              : 'Valor terminal (Gordon com reinvestimento)',
      latex: '$vtForma$separadorLatex$vpForma',
      variables: {
        'L_N': n == 0 ? null : _r(outcome.projectedFlows[n - 1]),
        'g_inf (% a.a.)': _r(gInf * 100),
        'r_inf (% a.a.)': _r(rInf * 100),
        'ROIC_inf (% a.a.)': moat == null ? null : _r(moat * 100),
        'ROIC implícito do instalado (% a.a.)':
            outcome.impliedTerminalReturn == null
                ? null
                : _r(outcome.impliedTerminalReturn! * 100),
        'N (anos)': assumptions.projectionYears,
        'M (anos de contrato além de N)': contrato,
      },
      steps: [
        if (contrato != null)
          'Passo 1: o contrato acaba $contrato ano(s) depois do horizonte — o '
              'capital volta e o excedente sobre ele dura só até lá, de modo '
              'que a perpetuidade não se aplica (decisão 88)'
        else if (neutro)
          'Passo 1: com RONIC_inf = r_inf — o **capital novo** sem valor — a '
              'álgebra colapsa e o crescimento perpétuo sai da perpetuidade: '
              'VT = L_(N+1) ÷ r_inf, sem spread'
        else
          'Passo 1: spread da perpetuidade → ${_pct(rInf)} − ${_pct(gInf)} = '
              '${_pct(rInf - gInf)}; retenção perpétua = '
              '${_pct(reinvestimento)}',
        'Passo 2: valor terminal no ano ${assumptions.projectionYears} → '
            '${_r(outcome.terminalValue)}',
        'Passo 3: trazido a presente pelo fator acumulado '
            '${_r(fatorFinal, 6)}'
            '${meioDeAno ? ', levantado por '
                '${_r(assumptions.lift(rInf), 6)} de meio de ano' : ''}'
            ' → ${_r(outcome.discountedTerminalValue)}',
        'Passo 4: participação do valor terminal no total → '
            '${_pct(outcome.terminalShare)}',
        // **O que o retorno neutro não diz** (item B12): ele fixa o retorno do
        // capital **novo**, e não o do instalado. O instalado continua rendendo
        // o que a projeção alcança, e a mesma expressão reagrupada mostra
        // quanto disso é excedente — ou déficit — perpétuo.
        if (contrato == null &&
            neutro &&
            outcome.impliedTerminalReturn != null)
          'Passo 5: o retorno neutro vale para o capital **novo**; o instalado '
              'rende ${_pct(outcome.impliedTerminalReturn!)} na perpetuidade, '
              'contra ${_pct(rInf)} de custo de capital. Reagrupando, '
              'VT = capital_N + EVA_(N+1) ÷ r_inf, e a segunda parcela vale '
              '${_r(outcome.discountedTerminalExcess ?? 0)} a valor presente '
              '— ${outcome.impliedTerminalReturn! < rInf ? 'déficit' : 'excedente'} '
              'mantido para sempre',
      ],
      result: outcome.discountedTerminalValue,
      unit: perShareAlready ? r'R$ por papel' : r'R$',
    );

    if (perShareAlready) {
      audit.step(
        formulaName: 'Preço justo por papel (DCF sobre o lucro)',
        latex: r'P_0 = VP_{explícito} + VP(VT)',
        variables: {
          'VP_explícito (R\$)': _r(sumPv),
          'VP(VT) (R\$)': _r(outcome.discountedTerminalValue),
        },
        steps: [
          'Passo único: soma das duas parcelas → ${_r(sumPv)} + '
              '${_r(outcome.discountedTerminalValue)} = '
              '${_r(outcome.fairValuePerShare)}',
        ],
        result: outcome.fairValuePerShare,
        unit: r'R$ por papel',
      );
    }
  }

  /// O capital próprio da via da firma, **como ele é calculado**: pelo fluxo do
  /// acionista derivado do da firma, e não pela subtração `EV − D` (decisão
  /// 102). O rastro mostrava a ponte depois de a ponte ter saído da conta, e o
  /// rastro que descreve outra conta é pior que nenhum.
  static void _auditEquityBridge(
    AuditTransaction? audit, {
    required DcfOutcome outcome,
    required double netDebt,
    required double minorityInterest,
    required double shares,
    required bool resolved,
  }) {
    if (audit == null) return;
    final explicito =
        outcome.discountedFlows.fold<double>(0, (a, b) => a + b);
    final terminal = outcome.discountedTerminalValue;
    final minoritarios = minorityInterest < 0 ? 0.0 : minorityInterest;
    audit.step(
      formulaName: 'Capital próprio pelo fluxo do acionista derivado',
      latex: r'FCFE_t = FCFF_t - D_{t-1}\,[K_d(1-\tau) - g_t] \quad;\quad '
          r'P_0 = \frac{\sum_t \frac{FCFE_t}{(1+K_{e,t})^t} + '
          r'\frac{VT_{acionista}}{(1+K_e)^N} - M}{N_{papéis}}',
      variables: {
        'VP do fluxo explícito do acionista (R\$)': _r(explicito),
        'VP do terminal do acionista (R\$)': _r(terminal),
        'minoritários M (R\$)': _r(minoritarios),
        'dívida líquida inicial D_0 (R\$)': _r(netDebt),
        'N_papéis': _r(shares, 0),
        'desconto': resolved
            ? 'caminho de K_e resolvido pela realavancagem'
            : 'K_e do CAPM, da taxa corrente à de equilíbrio',
      },
      steps: [
        'Passo 1: fluxo do acionista de cada ano = fluxo da firma menos o juro '
            'líquido da dívida, mais o acréscimo dela a g — a dívida parte de '
            '${_r(netDebt)}',
        'Passo 2: valor presente do fluxo explícito → ${_r(explicito)}',
        'Passo 3: valor presente do terminal do acionista → ${_r(terminal)}',
        'Passo 4: menos a parte dos não controladores → ${_r(explicito)} + '
            '${_r(terminal)} − ${_r(minoritarios)} = ${_r(outcome.equityValue)}',
        'Passo 5: divisão pelo número de papéis negociados → '
            '${_r(outcome.equityValue)} ÷ ${_r(shares, 0)} = '
            '${_r(outcome.fairValuePerShare)}',
      ],
      result: outcome.fairValuePerShare,
      unit: r'R$ por papel',
    );
  }

  static void _auditVerdict(AuditTransaction? audit, ValuationResult result) {
    if (audit == null) return;
    final fair = result.fairValue.reais;
    final market = result.marketPrice.reais;

    audit.step(
      formulaName: 'Margem de segurança e potencial de valorização',
      latex: r'P_{seg} = P_0\,(1 - s) \quad;\quad '
          r'upside = \frac{P_0 - P_{mkt}}{P_{mkt}}',
      variables: {
        'P_0 (R\$)': _r(fair),
        's (%)': _r(result.marginOfSafety * 100),
        'P_mkt (R\$)': _r(market),
      },
      steps: [
        'Passo 1: preço justo com margem de segurança → ${_r(fair)} × (1 − '
            '${_r(result.marginOfSafety, 4)}) = ${_r(result.safetyPrice.reais)}',
        'Passo 2: potencial de valorização total → (${_r(fair)} − '
            '${_r(market)}) ÷ ${_r(market)} = ${_pct(result.upside)}',
        'Passo 3: veredito → o preço de mercado '
            '${result.isUndervalued ? 'está abaixo' : 'não está abaixo'} do '
            'preço com margem de segurança',
      ],
      result: _r(result.upside * 100).toDouble(),
      unit: '% (total, sem prazo)',
    );
  }
}

// ---------------------------------------------------------------- diagnóstico

/// Fraseado de **diagnóstico** — rastro de cálculo e mensagem de falha, que a decisão 122 mantém no núcleo. O rótulo de tela, quando há, mora na apresentação (decisão 125).
extension _QuotedSharesSourceDiagnostico on QuotedSharesSource {
  String get diagnostico => switch (this) {
        QuotedSharesSource.market => 'implícita no valor de mercado',
        QuotedSharesSource.reconciled => 'conciliada pelas demonstrações',
        QuotedSharesSource.onlyAvailable => 'única contagem disponível',
        QuotedSharesSource.official => 'contagem oficial da B3, líquida de tesouraria',
      };
}

/// Fraseado de **diagnóstico** — rastro de cálculo e mensagem de falha, que a decisão 122 mantém no núcleo. O rótulo de tela, quando há, mora na apresentação (decisão 125).
extension _ValuationLaneDiagnostico on ValuationLane {
  String get diagnostico => switch (this) {
        ValuationLane.firm => 'firma',
        ValuationLane.shareholder => 'acionista',
      };
}

/// Fraseado de **diagnóstico** — rastro de cálculo e mensagem de falha, que a decisão 122 mantém no núcleo. O rótulo de tela, quando há, mora na apresentação (decisão 125).
extension _MultipleKindDiagnostico on MultipleKind {
  String get diagnostico => switch (this) {
        MultipleKind.precoLucro => 'P/L',
        MultipleKind.precoPatrimonio => 'P/VP',
        MultipleKind.firmaEbitda => 'EV/EBITDA',
      };
}

/// Fraseado de **diagnóstico** — rastro de cálculo e mensagem de falha, que a decisão 122 mantém no núcleo. O rótulo de tela, quando há, mora na apresentação (decisão 125).
extension _ValuationModelDiagnostico on ValuationModel {
  String get diagnostico => switch (this) {
        ValuationModel.dcfFcff => 'DCF por fluxo da firma',
        ValuationModel.dcfEarnings => 'DCF sobre lucro distribuível',
      };
}

/// Fraseado de **diagnóstico** — rastro de cálculo e mensagem de falha, que a decisão 122 mantém no núcleo. O rótulo de tela, quando há, mora na apresentação (decisão 125).
extension _GrowthOriginDiagnostico on GrowthOrigin {
  String get diagnostico => switch (this) {
        GrowthOrigin.fundamental => 'crescimento fundamental da base de capital',
        GrowthOrigin.inflationAnchor => 'âncora de inflação, financiável pela retenção observada',
        GrowthOrigin.earningsPower => 'valor da capacidade de gerar lucro, sem crescimento',
      };
}

/// Fraseado de **diagnóstico** — rastro de cálculo e mensagem de falha, que a decisão 122 mantém no núcleo. O rótulo de tela, quando há, mora na apresentação (decisão 125).
extension _MoatBlockDiagnostico on MoatBlock {
  String get diagnostico => switch (this) {
        MoatBlock.semRetornoDoCiclo => 'retorno do ciclo não medido',
        MoatBlock.semCustoDeCapital => 'custo de capital de equilíbrio não positivo',
        MoatBlock.historicoCurto => 'histórico curto',
        MoatBlock.capitalExternoNaoMedido => 'capital externo não medido',
        MoatBlock.crescimentoInorganico => 'crescimento inorgânico',
        MoatBlock.persistenciaNaoEstimavel => 'persistência do excedente não estimável',
        MoatBlock.semExcedente => 'retorno do ciclo não supera o custo de capital',
        MoatBlock.excedenteDegenerado => 'excedente não sobrevive ao decaimento medido',
        MoatBlock.prazoDeterminado => 'o negócio opera sob contrato de prazo determinado',
      };
}
