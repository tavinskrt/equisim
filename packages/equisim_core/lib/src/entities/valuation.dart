import '../services/valuation/peer_multiples.dart';
import '../value_objects/money.dart';
import '../value_objects/ticker.dart';

/// Modelo efetivamente aplicado no cálculo.
///
/// O modelo **faz parte do resultado**, não é detalhe interno: cair
/// silenciosamente para um modelo inferior e apresentar o número como "preço
/// justo" esconde do usuário a qualidade da estimativa.
enum ValuationModel {
  /// Fluxo da firma, descontado ao WACC.
  ///
  /// `NOPAT × (1 − RI)`, com freio de reinvestimento — a decisão 25 estendeu à
  /// firma a correção que a 24 fizera só do lado do acionista.
  dcfFcff,

  /// DCF sobre lucro distribuível, descontado ao Ke.
  ///
  /// É o modelo de desconto de dividendos da via do acionista: o fluxo é
  /// `LPA × (1 − b)`, e `1 − b` é o *payout*. O dividendo vem da identidade da
  /// retenção, não de dado publicado de provento — o que o mantém compatível com
  /// a decisão 23.
  dcfEarnings;
}

/// Como os cenários foram gerados.
enum ScenarioMode {
  /// Três conjuntos fixos de premissas — Pessimista, Base e Otimista.
  /// Preenche `discreteScenarios` no resultado.
  discrete,

  /// Premissas sorteadas de distribuições triangulares declaradas.
  /// Preenche `distribution` no resultado.
  monteCarlo,
}

/// Faixas nomeadas apresentadas ao usuário.
enum ScenarioBand {
  /// Crescimento deslocado para baixo e desconto para cima.
  bear,

  /// Premissas centrais. É o cenário cujo valor vira o preço justo.
  base,

  /// Crescimento deslocado para cima e desconto para baixo, respeitado o
  /// spread mínimo da perpetuidade.
  bull;
}

/// Distribuição de valores justos produzida pelo motor de cenários.
class ValueDistribution {
  /// Valores por ação, ordenados crescentemente.
  final List<double> sortedValues;

  /// Envolve uma lista **já ordenada**. Não ordena nem copia — ordenar é
  /// responsabilidade de quem constrói, e `ScenarioEngine.run` o faz.
  /// Passar lista desordenada produz percentis errados em silêncio.
  const ValueDistribution(this.sortedValues);

  /// `true` quando nenhum cenário produziu valor válido.
  bool get isEmpty => sortedValues.isEmpty;

  /// Percentil por interpolação linear. [p] em [0, 1].
  ///
  /// - [p]: posição desejada, travada em `[0, 1]` — valores fora da faixa não
  ///   lançam, saem nas pontas.
  ///
  /// Devolve `0.0` para distribuição vazia, e o único elemento quando há
  /// apenas um. Complexidade O(1).
  double percentile(double p) {
    if (sortedValues.isEmpty) return 0.0;
    if (sortedValues.length == 1) return sortedValues.first;
    final position = p.clamp(0.0, 1.0) * (sortedValues.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sortedValues[lower];
    final fraction = position - lower;
    return sortedValues[lower] * (1 - fraction) + sortedValues[upper] * fraction;
  }

  /// Percentil 5 — borda pessimista da banda apresentada.
  double get p5 => percentile(0.05);

  /// Mediana. É o valor central apresentado no modo Monte Carlo, preferido à
  /// [mean] por não ser arrastado pela cauda direita da distribuição de preços.
  double get median => percentile(0.50);

  /// Percentil 95 — borda otimista da banda apresentada.
  double get p95 => percentile(0.95);

  /// Média aritmética. Devolve `0.0` para distribuição vazia. Complexidade
  /// O(n) — ao contrário dos percentis, não aproveita a ordenação.
  double get mean =>
      sortedValues.isEmpty
          ? 0.0
          : sortedValues.reduce((a, b) => a + b) / sortedValues.length;

  /// Proporção de cenários em que o valor justo supera [price].
  ///
  /// - [price]: preço de comparação, tipicamente a cotação de mercado.
  ///
  /// Devolve fração em `[0, 1]`, e `0.0` para distribuição vazia. A comparação
  /// é estrita: cenários exatamente iguais a [price] não contam.
  /// Complexidade O(n).
  double probabilityAbove(double price) {
    if (sortedValues.isEmpty) return 0.0;
    final count = sortedValues.where((v) => v > price).length;
    return count / sortedValues.length;
  }
}

/// Por que a estimativa perdeu confiança.
///
/// Cada item é um **fato medido** no caminho do cálculo, não um julgamento: a
/// cascata já os apura para decidir a conta, e antes eles só existiam diluídos
/// no texto dos avisos. Estruturá-los é o que permite ao consumidor ponderar o
/// preço justo em vez de tratar todos como igualmente firmes.
enum ValuationCaveat {
  /// O valor terminal responde por mais que
  /// [ValuationDiagnostics.terminalShareLimit] do total: o número é sobretudo
  /// premissa, e a parte apoiada em exercício observado decide pouco.
  terminalPesado,

  /// A taxa de crescimento não veio do próprio ativo — foi a âncora de
  /// inflação ou a ausência de crescimento.
  crescimentoNaoIdentificado,

  /// As duas contagens de papéis publicadas divergem além de uma ação
  /// societária plausível, e a escolha do divisor foi por conservadorismo.
  escalaIncerta,

  /// Um único exercício foi multiplicado por mais de
  /// [ValuationDiagnostics.baseFactorLimit] para virar o fluxo-base.
  baseNormalizadaForte,

  /// A avaliação começou na via da firma e migrou para a do acionista.
  ///
  /// **Não é mais emitida desde a decisão 102**: nenhuma avaliação muda de via.
  /// Fica para ler resultados gravados antes dela.
  viaMigrada,

  /// O capital próprio responde por pouco do valor da firma, e o preço por
  /// papel é resíduo de subtração entre números próximos.
  ///
  /// **A ressalva de custo da dívida estimado saiu deste conjunto**, e a
  /// medição é o motivo: ela disparava em 469 das 821 avaliações do backtest —
  /// 57% —, porque a classificação sintética passou a ser o **método** pela
  /// decisão 31, e não mais um recuo. Ressalva que vale para a maioria não
  /// distingue nada; a substituição continua declarada nos avisos, que é onde
  /// ela informa.
  ponteFragil,

  /// O preço justo é combinação das duas vias, na faixa em que nenhuma domina.
  ///
  /// Medido em 10/09/2026: as duas vias discordam além de 1,5× em **55 de 92**
  /// ativos e além de 2× em 33. Enquanto a pós-condição escolhia uma delas por
  /// limiar, essa discordância virava um degrau no preço justo — a VBBR3 saía
  /// a R$ 2,65 ou R$ 33,71 conforme a participação cruzasse 20%. A combinação
  /// remove o degrau; **não remove a discordância**, e é isso que esta
  /// ressalva declara.
  ///
  /// **Não é mais emitida desde a decisão 102**: a mistura continuava subindo
  /// com a taxa, e as duas vias deixaram de se combinar. Fica para ler
  /// resultados gravados antes dela.
  viasMescladas,

  /// O fluxo-base não veio do exercício observado: ele foi reconstruído do
  /// retorno mediano do ciclo sobre o capital de hoje.
  ///
  /// Acontece quando o exercício mais recente veio no prejuízo. O fator de
  /// normalização não serve ali — ele é `ciclo ÷ atual`, e o denominador não é
  /// positivo —, e sem a reconstrução a avaliação seria recusada por fluxo-base
  /// não positivo. Ver
  /// [`base_negativa.md`](../../../../../docs/validacao/base_negativa.md).
  ///
  /// **É a ressalva mais forte da lista.** O preço justo aqui não repousa em
  /// nenhum exercício observado recente: repousa na afirmação de que a empresa
  /// volta ao que já foi.
  baseReconstruida,

  /// O negócio opera sob contrato de prazo determinado, e o valor terminal
  /// supõe perpetuidade.
  ///
  /// **A ressalva existe porque o conserto não é possível com o que a fonte
  /// publica.** O prazo da concessão não é campo de demonstração financeira, e
  /// o estimador que parecia servir — `(imobilizado + intangível) ÷ D&A` —
  /// mede giro da base, não vencimento de contrato: dá 6,3 anos para a TAEE11,
  /// cujas outorgas vão a 2042. Ver
  /// [`concessao.md`](../../../../../docs/validacao/concessao.md).
  ///
  /// O tamanho está medido: se o contrato acabasse em dez anos, o preço justo
  /// mediano dos expostos ficaria em 0,80 do publicado; em vinte, 0,90.
  prazoDeterminado;
}

/// Fatos medidos que qualificam o preço justo.
///
/// **Por que existe.** Um preço justo cujo valor terminal responde por 85% do
/// total, cuja taxa veio da inflação e cujo divisor é ambíguo não é o mesmo
/// objeto que um apoiado em crescimento identificado e escala conciliada — e,
/// até aqui, os dois chegavam à tela como um número só, com a diferença
/// espalhada em texto corrido. Para decisão patrimonial isso não basta: a
/// carteira precisa poder ponderar pela firmeza da estimativa.
///
/// Tudo aqui já era apurado pela cascata. O que muda é que passa a sair com o
/// resultado, em forma que a máquina lê.
class ValuationDiagnostics {
  /// Parcela do preço justo explicada pelo valor terminal, em fração.
  ///
  /// **É contra o capital próprio, nas três rotas** (decisão 51). Antes a
  /// ponte media contra o valor da firma e as outras duas contra o do
  /// acionista: o mesmo campo carregava duas grandezas conforme um caminho que
  /// o leitor não vê, e o corte de [terminalShareLimit] valia para as duas.
  ///
  /// Pode passar de 1: com capital próprio fino, o terminal descontado supera
  /// o que sobra ao acionista, e é justamente o caso que a ressalva existe
  /// para marcar.
  final double terminalShare;

  /// Participação do capital próprio no valor da firma. `1.0` na via do
  /// acionista, que não tem ponte.
  final double equityShare;

  /// Fator de normalização aplicado ao exercício-base.
  final double baseFactor;

  /// `true` quando a taxa de crescimento saiu do próprio histórico.
  final bool growthIdentified;

  /// `true` quando a perpetuidade preserva excedente de retorno.
  ///
  /// **Bandeira, e desde a decisão 36 ela vem acompanhada.** Enquanto a
  /// exceção era um degrau, o booleano bastava: ou se preservava 30% do
  /// excedente ou não se preservava nada. Com `λ` contínuo ele passou a
  /// esconder a diferença entre preservar meio ponto-base e preservar um
  /// terço — ver [terminalRetainedSpread].
  final bool moatApplied;

  /// Fração do excedente de retorno preservada na perpetuidade — o `λ = φ^N`
  /// da decisão 36. `0` no estado estacionário.
  ///
  /// É a magnitude que [moatApplied] não carrega. Sai com o resultado porque
  /// duas avaliações com a bandeira ligada e `λ` de 0,001 e 0,30 não são o
  /// mesmo objeto.
  final double terminalRetainedSpread;

  /// Crescimento do primeiro ano da projeção explícita, antes do decaimento.
  ///
  /// Junto com [returnOnCapital] fecha o par que governa o **freio de
  /// reinvestimento**: `b_t = g_t / ROIC_t`. Sem os dois no resultado, o
  /// tamanho do fluxo explícito não é auditável de fora sem reimplementar a
  /// projeção — e reimplementá-la mediria outro motor.
  final double growthRate;

  /// Retorno terminal efetivamente aplicado, ou `null` no estado estacionário.
  ///
  /// **Sai porque reconstruí-lo de fora dá errado.** Ele é
  /// `r_∞ + λ·(ROIC_do_ciclo − r_∞)`, e o retorno do ciclo **não** é
  /// [returnOnCapital] — este é o do fluxo-base, `retorno corrente × fator`.
  /// Quem tentasse remontar o terminal a partir dos dois campos anteriores
  /// erraria em todo ativo em que o fator de normalização não é 1.
  final double? terminalReturnOnCapital;

  /// Alíquota estrutural aplicada ao NOPAT da via da firma.
  ///
  /// `null` na via do acionista, que parte do lucro líquido já tributado, e
  /// também quando a série não tem exercícios suficientes para medi-la — caso
  /// em que vale a estatutária embutida pela fonte.
  final double? firmTaxRate;

  /// Retorno sobre o capital do fluxo-base, o denominador do freio.
  ///
  /// É `retorno corrente × fator de normalização` quando há retorno corrente
  /// utilizável, e o do ciclo quando não há. Vale `0` quando o freio está
  /// desligado por falta de retorno medível — o que é a direção agressiva, e
  /// o resultado já a declara em texto.
  final double returnOnCapital;

  /// Custo de capital de equilíbrio — a taxa que desconta a perpetuidade.
  ///
  /// [ValuationResult.discountRate] é a taxa do **primeiro ano**, e desde a
  /// estrutura a termo da decisão 31 as duas não coincidem: a taxa decai
  /// linearmente do CDI corrente até esta ao longo da projeção. Com o terminal
  /// respondendo pela maior parte do valor, era esta que faltava sair — e ela
  /// é também a referência contra a qual o excedente de retorno se mede.
  final double terminalDiscountRate;

  /// Custo do capital próprio de **equilíbrio resolvido** contra a
  /// alavancagem, quando o ponto fixo da decisão 41 valeu.
  ///
  /// `null` quando ele não valeu — inclusive na via do acionista, que precifica
  /// o `Ke` pelo beta alavancado de hoje e supõe essa alavancagem perene. Sai
  /// com o resultado porque é a única maneira de comparar, de fora, os dois
  /// custos de capital próprio que o motor produz para o mesmo ativo.
  final double? terminalCostOfEquity;

  /// Crescimento **aplicado** em cada ano explícito.
  ///
  /// Não é o decaimento de [growthRate] até a perpetuidade: desde a guarda do
  /// crescimento financiável ele é confinado a `b_max · ROIC_t`, e [growthRate]
  /// passou a ser o que as guardas *decidiram*, não o que a projeção *usou*.
  /// Publicar só o primeiro faria todo leitor de fora remontar a projeção
  /// errada — foi o que aconteceu com o próprio utilitário de validação.
  final List<double> growthPath;

  /// Retenção aplicada em cada ano explícito — o `b_t = g_t/ROIC_t` do freio.
  ///
  /// **Sai porque reconstruí-la de fora mede outro motor.** O `ROIC_t` converge
  /// para a taxa de desconto **daquele ano**, e desde a decisão 42 essa taxa é
  /// um caminho resolvido por ponto fixo, não uma interpolação de dois pontos.
  /// Quem remontasse o freio a partir de [growthRate], [returnOnCapital] e
  /// [terminalDiscountRate] erraria em todo ativo com alavancagem que se move.
  final List<double> retentionPath;

  /// Ressalvas medidas, na ordem em que a cascata as apura.
  /// Custo do capital próprio do ativo pelo CAPM, sobre a taxa livre de risco
  /// **corrente**.
  ///
  /// **É o retorno esperado incondicional do papel** — `Rf + β·prêmio` —, e
  /// sai com o resultado porque a camada de carteira precisa dele. O estimador
  /// transversal ancorava no CDI, o que dava ao ativo mediano um retorno
  /// esperado **sem prêmio de risco algum**: uma carteira de ações centrada na
  /// seção esperava exatamente a renda fixa (decisão 58).
  ///
  /// Não confundir com [ValuationResult.discountRate], que é WACC na via da
  /// firma — abaixo do `Ke` sempre que há dívida.
  final double costOfEquity;

  /// Parcela do preço justo que vem do **excedente perpétuo do capital
  /// instalado**, em fração (item B12).
  ///
  /// O terminal neutro recusa valor ao capital **novo** — `RONIC = r` —, e
  /// mantém para sempre o retorno acima do custo sobre o capital que já existe:
  /// `lucro_{N+1}/r = capital_N + EVA_{N+1}/r`. Este campo é o peso da segunda
  /// parcela no valor do capital próprio.
  ///
  /// `null` quando a decomposição não se aplica — vantagem competitiva
  /// concedida, contrato com prazo, ou capital não medível. **Pode ser
  /// negativa**, quando o instalado rende abaixo do custo dele, e aí o terminal
  /// vale menos que o capital.
  final double? terminalExcessShare;

  /// Retorno que a perpetuidade supõe sobre o capital instalado, implícito na
  /// projeção: `lucro_{N+1} ÷ capital_N` (item B12).
  ///
  /// Sai ao lado de [terminalDiscountRate] porque a comparação entre os dois é
  /// a pergunta: o terminal neutro se apresenta como "sem lucro econômico na
  /// perpetuidade", e isso exige que os dois sejam o mesmo número.
  final double? impliedTerminalReturn;

  /// Participação do capital próprio no valor da firma **no ano N**, que é a
  /// estrutura de capital com que a perpetuidade é descontada (item B15).
  ///
  /// **Não é a de hoje.** Desde a decisão 105 o caminho de taxas é resolvido, e
  /// a alavancagem de equilíbrio é a que a própria projeção alcança no fim do
  /// horizonte — a de hoje é [equityShare]. `null` quando as taxas não são
  /// resolvidas, e aí a perpetuidade herda a estrutura de hoje.
  final double? terminalEquityShare;

  final List<ValuationCaveat> caveats;

  const ValuationDiagnostics({
    required this.terminalShare,
    required this.equityShare,
    required this.baseFactor,
    required this.growthIdentified,
    required this.moatApplied,
    required this.terminalDiscountRate,
    required this.terminalRetainedSpread,
    required this.growthRate,
    required this.returnOnCapital,
    this.terminalReturnOnCapital,
    this.firmTaxRate,
    this.terminalCostOfEquity,
    required this.costOfEquity,
    this.retentionPath = const [],
    this.growthPath = const [],
    this.terminalExcessShare,
    this.impliedTerminalReturn,
    this.terminalEquityShare,
    this.caveats = const [],
  });

  /// Acima disto, o valor terminal domina e a estimativa é rebaixada.
  ///
  /// **80%, e o corte tem origem.** A decisão 25 fixou a projeção explícita em
  /// dez anos justamente porque, com cinco, o terminal carregava de 63,5% a
  /// 80,0% do preço justo e "a parte da conta apoiada em dado observado decidia
  /// pouco". O limiar é o topo daquela faixa: acima dele, o horizonte de dez
  /// anos não conseguiu o que foi escolhido para conseguir.
  static const double terminalShareLimit = 0.80;

  /// Acima disto, um único exercício move demais a avaliação inteira.
  ///
  /// **2,0x, e é metade da autoridade que a saturação permite.** A decisão 28
  /// confinou o fator em `[0,33; 3,00]` dizendo que acima de 3x "a normalização
  /// deixaria de corrigir um exercício para inventar uma empresa". O corte aqui
  /// não proíbe nada — apenas marca que, passando de 2x, o preço justo passou a
  /// depender mais da mediana do ciclo que do exercício observado.
  static const double baseFactorLimit = 2.0;

  /// Acima disto em módulo, o excedente perpétuo do capital instalado é
  /// declarado na avaliação (item B12).
  ///
  /// **Vinte por cento, e o corte tem origem na distribuição medida.** Em
  /// 21/09/2026, sobre os 83 avaliados do universo em que a decomposição se
  /// aplica, o peso é de **−14,1%** na mediana — déficit, e não excedente —,
  /// passa de 10% em módulo em 50 deles e de 20% em 33. Um quinto do preço
  /// justo é o ponto em que a parcela deixa de ser detalhe e vira a premissa
  /// dominante; abaixo disso ela fica no rastro de auditoria, que a traz
  /// sempre. Ver
  /// [`terminal_excedente.md`](../../../../../docs/validacao/terminal_excedente.md).
  static const double terminalExcessLimit = 0.20;

  /// Abaixo disto a ponte é frágil, embora ainda acima do corte que faz migrar.
  ///
  /// **35%, contra os 20% que reprovam.** A pós-condição da via da firma migra
  /// abaixo de 20%; entre 20% e 35% ela não migra e o preço por papel já é
  /// resíduo de uma subtração com amplificação de três a cinco vezes. A faixa
  /// entre os dois cortes é onde o número sai sem aviso nenhum, e é ela que
  /// esta ressalva cobre.
  static const double fragileEquityShare = 0.35;

  /// **Não existe nota de confiança aqui, e a ausência é medida.**
  ///
  /// A primeira versão destes diagnósticos trazia uma nota ordinal — alta,
  /// média, baixa — derivada da contagem de ressalvas. A validação preditiva da
  /// decisão 32 a desmentiu: no horizonte de 36 meses, o grupo **sem ressalva
  /// alguma** teve coeficiente de informação de **−0,007**, positivo em 2 de 5
  /// coortes, enquanto o grupo com uma ou duas ressalvas teve **0,206**,
  /// positivo em 5 de 5. A nota ordenava ao contrário do que prometia.
  ///
  /// A explicação plausível — não medida — é que o ativo sem ressalva é o
  /// estável e previsível, que é justamente o que o mercado já precifica bem;
  /// a discordância informativa aparece onde o modelo faz algo que o preço não
  /// fez. Seja qual for a causa, apresentar uma nota que ordena ao contrário
  /// seria falsa precisão num número destinado a decisão patrimonial.
  ///
  /// O que fica são os **fatos**: eles descrevem o que a conta fez, e isso
  /// continua verdadeiro e continua útil. O que saiu foi a promessa de que eles
  /// medem confiabilidade.
  bool get hasCaveats => caveats.isNotEmpty;
}

/// Resultado de uma avaliação de valor intrínseco.
class ValuationResult {
  /// Ativo avaliado.
  final Ticker ticker;

  /// Data de referência da avaliação — define o recorte *point-in-time* dos
  /// fundamentos e o preço de mercado comparado.
  final DateTime asOf;

  /// Modelo que efetivamente produziu [fairValue]. **Faz parte do resultado**:
  /// um número vindo de múltiplos não tem a mesma qualidade de um vindo de
  /// FCFF, e omitir isso esconderia a diferença.
  final ValuationModel model;

  /// Preço justo por ação no cenário base.
  final Money fairValue;

  /// Preço de mercado na data de referência.
  final Money marketPrice;

  /// Margem de segurança aplicada sobre o preço justo, em fração.
  final double marginOfSafety;

  /// Como os cenários foram gerados. Determina qual de [discreteScenarios] e
  /// [distribution] está preenchido.
  final ScenarioMode mode;

  /// Preenchido no modo discreto.
  final Map<ScenarioBand, Money>? discreteScenarios;

  /// Preenchido no modo Monte Carlo.
  final ValueDistribution? distribution;

  /// Custo de capital efetivamente usado no desconto, em fração.
  final double discountRate;

  /// Avisos acumulados (dados faltantes, aproximações, quedas de modelo).
  final List<String> warnings;

  /// Fatos medidos que qualificam o preço justo. `null` só quando o resultado
  /// é montado à mão, fora da cascata.
  final ValuationDiagnostics? diagnostics;

  /// Volatilidade anualizada do papel na janela da avaliação, ou `null`.
  ///
  /// É a escala da faixa calibrada na forma que cobre (item C2b): a faixa de um
  /// papel sai do preço de hoje, do preço justo e dela. Sai com o resultado
  /// porque vem da **mesma série** que a cascata usou — recalculá-la na tela, de
  /// outra janela, daria outra faixa. `null` quando a série tem menos de
  /// `CalibratedBand.volatilityMinimumReturns` retornos.
  final double? priceVolatility;

  /// A segunda leitura, por múltiplos de pares (item B5, decisão 118).
  ///
  /// **Não é preço, e não entra em [fairValue].** O produto do motor continua
  /// sendo o fluxo descontado; isto é o teste de sanidade sobre o nível, com a
  /// divergência declarada em vez de reconciliada. `null` quando o pacote de
  /// medianas setoriais não está presente.
  final PeerTriangulation? triangulation;

  /// Agrupa o resultado já apurado. Não calcula nada — o cálculo vive em
  /// `ValuationCascade.evaluate`.
  const ValuationResult({
    required this.ticker,
    required this.asOf,
    required this.model,
    required this.fairValue,
    required this.marketPrice,
    required this.discountRate,
    this.marginOfSafety = 0.0,
    this.mode = ScenarioMode.discrete,
    this.discreteScenarios,
    this.distribution,
    this.warnings = const [],
    this.diagnostics,
    this.priceVolatility,
    this.triangulation,
  });

  /// Ressalvas estruturadas do cálculo, vazias quando não há diagnóstico.
  List<ValuationCaveat> get caveats =>
      diagnostics?.caveats ?? const <ValuationCaveat>[];

  /// O mesmo resultado, com [extra] ao fim dos avisos.
  ///
  /// Para o que a cascata não enxerga e quem monta a avaliação sabe — a
  /// demonstração da CVM que faltou no pacote, por exemplo. Nenhum número
  /// muda: só a narrativa ganha a ressalva.
  ValuationResult withWarnings(List<String> extra) => extra.isEmpty
      ? this
      : ValuationResult(
          ticker: ticker,
          asOf: asOf,
          model: model,
          fairValue: fairValue,
          marketPrice: marketPrice,
          discountRate: discountRate,
          marginOfSafety: marginOfSafety,
          mode: mode,
          discreteScenarios: discreteScenarios,
          distribution: distribution,
          warnings: List.unmodifiable([...warnings, ...extra]),
          diagnostics: diagnostics,
          priceVolatility: priceVolatility,
          triangulation: triangulation,
        );

  /// Preço justo já descontado da margem de segurança.
  ///
  /// É o limiar de compra: só abaixo dele o ativo é considerado descontado.
  /// Herda o arredondamento de [Money.operator *].
  Money get safetyPrice => fairValue * (1.0 - marginOfSafety);

  /// Valorização total esperada até o preço justo, em fração.
  ///
  /// Atenção: é um número **total**, sem prazo. Para comparar com uma taxa
  /// requerida anual é preciso anualizá-lo por um horizonte de convergência
  /// declarado — ver `ExpectedReturn.annualizedFromUpside`.
  double get upside {
    if (marketPrice.cents <= 0) return 0.0;
    return (fairValue.reais - marketPrice.reais) / marketPrice.reais;
  }

  /// `true` quando o preço de mercado está em ou abaixo de [safetyPrice].
  ///
  /// Comparação exata entre inteiros de centavos, e **inclusiva** na borda:
  /// preço igual ao de segurança conta como descontado.
  bool get isUndervalued => marketPrice <= safetyPrice;
}
