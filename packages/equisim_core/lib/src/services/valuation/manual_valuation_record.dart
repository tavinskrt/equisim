/// O valuation confirmado: as premissas do usuário e o que a conta deu com
/// elas, guardados juntos (decisão 150).
library;

import '../../audit/calculation_trace.dart';
import '../../failures/failure.dart';
import '../../failures/result.dart';
import '../../value_objects/money.dart';
import '../../value_objects/ticker.dart';
import 'capital_base.dart';
import 'manual_valuation.dart';

/// **Um valuation que o usuário confirmou** (decisão 150).
///
/// A tela de edição (decisão 147) recalcula enquanto se digita, e nada do que
/// ela mostra sobrevivia a fechar a tela. Este é o retrato do momento da
/// confirmação: as premissas digitadas, as do motor de que elas partiram, e o
/// resultado inteiro da conta — o preço justo, a ponte até ele, os dez anos, os
/// avisos e a decomposição contra o motor.
///
/// **Nada aqui recalcula.** O resultado é o [ManualOutcome] que
/// [ManualValuation.evaluate] devolveu na confirmação, guardado como saiu. Reler
/// o registro um ano depois dá os números daquele dia, e não os de uma conta
/// refeita com dados novos — é o que permite comparar a opinião do usuário com
/// o que o mercado fez depois.
///
/// O mesmo retrato vai a dois lugares: ao armazenamento, por [toJson], e ao
/// painel de auditoria, por [toAuditEvent]. O identificador é o mesmo nos dois,
/// e é ele que impede o painel de mostrar o mesmo valuation duas vezes.
class ManualValuationRecord {
  /// Versão do formato gravado por [toJson]. [fromJson] recusa outra.
  static const int format = 1;

  /// Prefixo do endereço do evento de auditoria. Começa por `/core/`, então o
  /// painel o conta entre os cálculos — e não entre as idas à rede.
  static const String endpointPrefix = '/core/valuation/manual/';

  /// Identificador do registro. É também o `transactionId` do evento de
  /// auditoria e o nome do documento no armazenamento.
  final String id;

  /// Ativo avaliado.
  final Ticker ticker;

  /// Instante da confirmação. **Relógio do sistema**, recebido por parâmetro:
  /// é metadado do registro, e nunca entra em conta.
  final DateTime savedAt;

  /// Data de referência da avaliação do motor de que a conta partiu.
  final DateTime engineAsOf;

  /// Via da avaliação do motor. O lucro de partida é `NOPAT` na da firma e
  /// lucro líquido na do acionista.
  final ValuationLane lane;

  /// Preço de mercado da avaliação, por papel.
  final double marketPrice;

  /// Preço justo do motor por papel, antes do arredondamento ao centavo.
  final double engineFairValue;

  /// Papéis da ponte — a contagem que divide o valor do patrimônio.
  final double shares;

  /// As premissas do motor, de onde os campos abriram.
  final ManualPremises enginePremises;

  /// As premissas confirmadas pelo usuário.
  final ManualPremises premises;

  /// O resultado da conta com [premises], como [ManualValuation.evaluate] o
  /// devolveu.
  final ManualOutcome outcome;

  /// Do preço do motor ao do usuário, um grupo de premissas de cada vez — o
  /// cartão "onde você discorda do motor" no momento da confirmação.
  final List<ManualStep> attribution;

  /// Declara o registro. Quem o monta é [capture], ou [fromJson] ao reler.
  const ManualValuationRecord({
    required this.id,
    required this.ticker,
    required this.savedAt,
    required this.engineAsOf,
    required this.lane,
    required this.marketPrice,
    required this.engineFairValue,
    required this.shares,
    required this.enginePremises,
    required this.premises,
    required this.outcome,
    this.attribution = const [],
  });

  /// Retrata a conta de [valuation] com [premises] no instante [savedAt].
  ///
  /// Recusa o que a tela também recusaria: premissa sem conta devolve a mesma
  /// falha de [ManualValuation.evaluate], com o campo nomeado. Um registro
  /// existe só para valuation com preço.
  ///
  /// - [id]: identificador único — a camada de aplicação o sorteia.
  /// - [engineAsOf]: data de referência da avaliação do motor.
  static Result<ManualValuationRecord> capture({
    required String id,
    required Ticker ticker,
    required DateTime engineAsOf,
    required ManualValuation valuation,
    required ManualPremises premises,
    required DateTime savedAt,
  }) {
    if (id.trim().isEmpty) {
      return const Err(InvalidInput('Valuation sem identificador.'));
    }
    final evaluated = valuation.evaluate(premises);
    final outcome = evaluated.valueOrNull;
    if (outcome == null) return Err(evaluated.failureOrNull!);
    if (!outcome.fairValuePerShare.isFinite ||
        !outcome.equityValue.isFinite) {
      return const Err(ComputationFailure(
        'A conta não chegou a um preço justo finito: não há o que salvar.',
      ));
    }
    return Ok(ManualValuationRecord(
      id: id,
      ticker: ticker,
      savedAt: savedAt,
      engineAsOf: engineAsOf,
      lane: valuation.lane,
      marketPrice: valuation.marketPrice,
      engineFairValue: valuation.engineFairValue,
      shares: valuation.shares,
      enginePremises: valuation.enginePremises,
      premises: premises,
      outcome: outcome,
      attribution: valuation.attribution(premises),
    ));
  }

  // ------------------------------------------------------------ Derivados --

  /// Preço justo do usuário por papel, sem arredondamento.
  double get fairValuePerShare => outcome.fairValuePerShare;

  /// Preço justo do usuário **arredondado ao centavo** — a fronteira do
  /// `double` para o dinheiro, pela regra de [Money.fromReais].
  Money get fairValue => Money.fromReais(outcome.fairValuePerShare);

  /// Potencial total sobre o preço de mercado da avaliação, em fração, ou
  /// `null` sem preço de mercado positivo.
  double? get upside =>
      marketPrice > 0 ? outcome.fairValuePerShare / marketPrice - 1 : null;

  /// Quanto o preço do usuário se afasta do preço do motor, em reais por papel.
  double get engineDelta => outcome.fairValuePerShare - engineFairValue;

  /// O endereço do evento de auditoria.
  String get endpoint => '$endpointPrefix${ticker.value}';

  /// Os campos que o usuário trocou em relação ao motor, na ordem da tela.
  ///
  /// Um campo conta como trocado quando o valor difere **ou** o modo que o
  /// acompanha difere: o caminho do crescimento, o da taxa e a forma do
  /// reinvestimento. O retorno sobre o capital só conta no reinvestimento pelo
  /// retorno, e a parcela reinvestida só na parcela fixa — é onde cada um
  /// entra na conta.
  List<ManualField> get changedFields {
    final p = premises;
    final e = enginePremises;
    final byReturn = p.reinvestment == ManualReinvestment.byReturn;
    return [
      for (final f in ManualField.values)
        if (switch (f) {
          ManualField.baseProfit => p.baseProfit != e.baseProfit,
          ManualField.growth =>
            p.growth != e.growth || p.growthPath != e.growthPath,
          ManualField.discountRate =>
            p.discountRate != e.discountRate || p.ratePath != e.ratePath,
          ManualField.perpetualGrowth => p.perpetualGrowth != e.perpetualGrowth,
          ManualField.returnOnCapital =>
            byReturn && p.returnOnCapital != e.returnOnCapital,
          ManualField.retention => !byReturn &&
              (e.reinvestment != p.reinvestment || p.retention != e.retention),
          ManualField.terminalReturn => p.terminalReturn != e.terminalReturn,
        })
          f,
    ];
  }

  // ---------------------------------------------------------- Persistência --

  /// Serializa o registro inteiro, num mapa que `jsonEncode` e o Firestore
  /// aceitam sempre.
  ///
  /// Os enums vão pela chave de [_Wire], e não pelo nome do identificador:
  /// renomear um valor no código não pode tornar ilegível o que já foi gravado.
  /// Valor não finito — o lucro de um ano que a calculadora não decompôs —
  /// vira o texto `NaN`, pela regra de [AuditJson.safe].
  Map<String, dynamic> toJson() => AuditJson.safeMap({
        'formato': format,
        'id': id,
        'ticker': ticker.value,
        'salvoEm': savedAt.toUtc().toIso8601String(),
        // Sem conversão a UTC: a data de referência é uma data de calendário, e
        // convertê-la deslocaria o dia num aparelho de outro fuso.
        'dataDaAvaliacao': engineAsOf.toIso8601String(),
        'via': _Wire.lane[lane],
        'precoDeMercado': marketPrice,
        'precoJustoDoMotor': engineFairValue,
        'acoes': shares,
        'premissasDoMotor': _premisesJson(enginePremises),
        'premissas': _premisesJson(premises),
        'resultado': _outcomeJson(outcome),
        'decomposicao': [
          for (final s in attribution)
            {
              'grupos': [for (final g in s.groups) _Wire.group[g]],
              'de': s.from,
              'para': s.to,
            },
        ],
      });

  /// Relê um registro gravado por [toJson], ou devolve `null` quando o mapa
  /// não é um registro legível deste formato.
  ///
  /// **Não lança.** Um documento corrompido no armazenamento não pode derrubar
  /// a lista inteira dos valuations do usuário: quem lê descarta o ilegível e
  /// segue com o resto.
  static ManualValuationRecord? fromJson(Map<String, dynamic> json) {
    try {
      if (json['formato'] != format) return null;
      final id = _text(json, 'id');
      final ticker = Ticker.tryParse(_text(json, 'ticker'));
      if (id.trim().isEmpty || ticker == null) return null;
      return ManualValuationRecord(
        id: id,
        ticker: ticker,
        savedAt: _date(json, 'salvoEm').toLocal(),
        engineAsOf: _date(json, 'dataDaAvaliacao'),
        lane: _decode(_Wire.lane, json['via']),
        marketPrice: _number(json, 'precoDeMercado'),
        engineFairValue: _number(json, 'precoJustoDoMotor'),
        shares: _number(json, 'acoes'),
        enginePremises: _premisesFrom(_map(json, 'premissasDoMotor')),
        premises: _premisesFrom(_map(json, 'premissas')),
        outcome: _outcomeFrom(_map(json, 'resultado')),
        attribution: [
          for (final raw in _list(json, 'decomposicao'))
            _stepFrom(_asMap(raw)),
        ],
      );
    } on FormatException {
      return null;
    }
  }

  // ------------------------------------------------------------- Auditoria --

  /// O registro como evento do painel de auditoria.
  ///
  /// O `transactionId` é [id] e o instante é [savedAt]: o mesmo valuation
  /// emitido na confirmação e de novo ao reler o histórico é **um** evento só
  /// no painel, que descarta o identificador repetido. As fórmulas são as da
  /// ponte da tela, com os números deste registro — nenhuma é refeita.
  AuditEvent toAuditEvent() {
    final changed = changedFields;
    return AuditEvent(
      transactionId: id,
      timestamp: savedAt,
      endpoint: endpoint,
      inputPayload: {
        'origem': 'valuation confirmado pelo usuário na edição (decisão 150)',
        'ticker': ticker.value,
        'via': _Wire.lane[lane],
        'dataDaAvaliacaoDoMotor': engineAsOf.toIso8601String(),
        'precoDeMercado': marketPrice,
        'precoJustoDoMotor': engineFairValue,
        'acoes': shares,
        'camposTrocados': [for (final f in changed) _Wire.field[f]],
        'premissas': _premisesJson(premises),
        'premissasDoMotor': _premisesJson(enginePremises),
      },
      outputPayload: {
        'status': 'confirmado',
        'salvoEm': savedAt.toUtc().toIso8601String(),
        'precoJusto': outcome.fairValuePerShare,
        'precoJustoCentavos': fairValue.cents,
        'potencial': upside,
        'diferencaContraOMotor': engineDelta,
        ..._outcomeJson(outcome),
      },
      executionTimeMs: 0,
      calculations: List.unmodifiable(_traces(changed)),
    );
  }

  List<CalculationTrace> _traces(List<ManualField> changed) {
    final o = outcome;
    final years = o.years;
    final upsideValue = upside;
    return [
      CalculationTrace(
        formulaName: 'Valor presente dos anos explícitos — seus números',
        latexRepresentation: r'VP_{anos} = \sum_{t=1}^{N} \frac{FC_t}{FD_t}',
        mappedVariables: {
          'N': years.length,
          'VP_{anos} (R\$)': o.explicitPresentValue,
        },
        intermediateSteps: [
          for (final y in years)
            'Ano ${y.year}: FC ${_millions(y.flow)} ÷ FD '
                '${_decimal(y.discountFactor, 4)} = ${_millions(y.presentValue)} '
                '(crescimento ${_percent(y.growth)}, taxa ${_percent(y.rate)})',
          'Soma: ${_millions(o.explicitPresentValue)}',
        ],
        finalValue: o.explicitPresentValue,
        unit: 'R\$',
        sample: TraceSample(
          title: 'Valor presente de cada ano',
          points: [
            for (final y in years)
              TraceSamplePoint(label: 'ano ${y.year}', value: y.presentValue),
          ],
          unit: 'R\$',
        ),
      ),
      CalculationTrace(
        formulaName: 'Valor terminal — ${_terminalName(o.terminalKind)}',
        latexRepresentation: _terminalLatex(o.terminalKind),
        mappedVariables: {
          'k_{\\infty} (% a.a.)': o.terminalRate * 100,
          'g (% a.a.)': premises.perpetualGrowth * 100,
          if (o.terminalKind == ManualTerminal.advantage)
            'r_{\\infty} (% a.a.)': (premises.terminalReturn ?? o.terminalRate) *
                100,
          if (o.terminalKind == ManualTerminal.fixedFraction)
            'b (%)': premises.retention * 100,
          'TV (R\$)': o.terminalValue,
          'VP_{TV} (R\$)': o.terminalPresentValue,
        },
        intermediateSteps: [
          'Valor terminal no ano ${years.length}: ${_millions(o.terminalValue)}',
          'Trazido a valor presente: ${_millions(o.terminalPresentValue)}',
        ],
        finalValue: o.terminalPresentValue,
        unit: 'R\$',
      ),
      CalculationTrace(
        formulaName: 'Valor do patrimônio — seus números',
        latexRepresentation: r'VPL = VP_{anos} + VP_{TV} - M + C_{pos}',
        mappedVariables: {
          'VP_{anos} (R\$)': o.explicitPresentValue,
          'VP_{TV} (R\$)': o.terminalPresentValue,
          'M (R\$)': o.minorityInterest,
          'C_{pos} (R\$)': o.postStatementCapital,
        },
        intermediateSteps: [
          '${_millions(o.explicitPresentValue)} + '
              '${_millions(o.terminalPresentValue)} − '
              '${_millions(o.minorityInterest)} + '
              '${_millions(o.postStatementCapital)} = '
              '${_millions(o.equityValue)}',
        ],
        finalValue: o.equityValue,
        unit: 'R\$',
      ),
      CalculationTrace(
        formulaName: 'Preço justo por ação — seus números',
        latexRepresentation: r'P = \frac{VPL}{N_{acoes}}',
        mappedVariables: {
          'VPL (R\$)': o.equityValue,
          'N_{acoes}': shares,
        },
        intermediateSteps: [
          '${_millions(o.equityValue)} ÷ ${_decimal(shares / 1e6, 1)} mi de '
              'ações = ${_money(fairValue)} por ação',
        ],
        finalValue: o.fairValuePerShare,
        unit: 'R\$',
        explanation: const [
          'É a conta do motor refeita com os números do usuário (decisão 147). '
              'A faixa calibrada e a habilidade medida continuam sendo do preço '
              'do motor: este preço é a opinião do usuário, sem validação '
              'própria.',
        ],
      ),
      CalculationTrace(
        formulaName: 'Potencial sobre o preço de mercado',
        latexRepresentation: r'u = \frac{P}{P_{mercado}} - 1',
        mappedVariables: {
          'P (R\$)': o.fairValuePerShare,
          'P_{mercado} (R\$)': marketPrice,
        },
        intermediateSteps: [
          if (upsideValue != null)
            '${_money(fairValue)} ÷ ${_price(marketPrice)} − 1 '
                '= ${_percent(upsideValue)}'
          else
            'Sem preço de mercado positivo, o potencial não é definido.',
        ],
        finalValue: upsideValue == null ? null : upsideValue * 100,
        unit: '%',
      ),
      CalculationTrace(
        formulaName: 'Diferença contra o preço justo do motor',
        latexRepresentation: r'\Delta = P - P_{motor}',
        mappedVariables: {
          'P (R\$)': o.fairValuePerShare,
          'P_{motor} (R\$)': engineFairValue,
          'campos trocados': changed.isEmpty
              ? 'nenhum'
              : [for (final f in changed) _fieldName(f)].join(', '),
        },
        intermediateSteps: [
          if (attribution.isEmpty)
            'Nenhum campo trocado: o preço é o do motor.',
          for (final s in attribution)
            '${[for (final g in s.groups) _groupName(g)].join(' + ')}: '
                '${_price(s.from)} → '
                '${s.to == null ? 'sem valor finito' : _price(s.to!)}',
        ],
        finalValue: engineDelta,
        unit: 'R\$',
      ),
    ];
  }

  // -------------------------------------------------------------- Codecs --

  static Map<String, dynamic> _premisesJson(ManualPremises p) => {
        'lucroDePartida': p.baseProfit,
        'crescimento': p.growth,
        'caminhoDoCrescimento': _Wire.growthPath[p.growthPath],
        'taxaDeDesconto': p.discountRate,
        'caminhoDaTaxa': _Wire.ratePath[p.ratePath],
        'crescimentoPerpetuo': p.perpetualGrowth,
        'reinvestimento': _Wire.reinvestment[p.reinvestment],
        'retornoSobreOCapital': p.returnOnCapital,
        'parcelaReinvestida': p.retention,
        // `null` é dado, e não ausência: é o estado estacionário, em que o
        // capital novo rende a própria taxa.
        'retornoDoCapitalNovo': p.terminalReturn,
      };

  static ManualPremises _premisesFrom(Map<String, dynamic> json) =>
      ManualPremises(
        baseProfit: _number(json, 'lucroDePartida'),
        growth: _number(json, 'crescimento'),
        growthPath: _decode(_Wire.growthPath, json['caminhoDoCrescimento']),
        discountRate: _number(json, 'taxaDeDesconto'),
        ratePath: _decode(_Wire.ratePath, json['caminhoDaTaxa']),
        perpetualGrowth: _number(json, 'crescimentoPerpetuo'),
        reinvestment: _decode(_Wire.reinvestment, json['reinvestimento']),
        returnOnCapital: _number(json, 'retornoSobreOCapital'),
        retention: _number(json, 'parcelaReinvestida'),
        terminalReturn: json['retornoDoCapitalNovo'] == null
            ? null
            : _number(json, 'retornoDoCapitalNovo'),
      );

  static Map<String, dynamic> _outcomeJson(ManualOutcome o) => {
        'precoJustoPorAcao': o.fairValuePerShare,
        'valorDoPatrimonio': o.equityValue,
        'valorPresenteDosAnos': o.explicitPresentValue,
        'valorTerminal': o.terminalValue,
        'valorPresenteDaPerpetuidade': o.terminalPresentValue,
        'minoritarios': o.minorityInterest,
        'capitalPosBalanco': o.postStatementCapital,
        'taxaDaPerpetuidade': o.terminalRate,
        'custoDoCapitalPorAno': o.capitalCostRates,
        'custoDoCapitalNaPerpetuidade': o.terminalCapitalCost,
        'perpetuidade': _Wire.terminal[o.terminalKind],
        'avisos': [
          for (final n in o.notices)
            {'tipo': _Wire.notice[n.kind], 'anos': n.years},
        ],
        'anos': [
          for (final y in o.years)
            {
              'ano': y.year,
              'crescimento': y.growth,
              'crescimentoPedido': y.plannedGrowth,
              'lucro': y.profit,
              'parcelaReinvestida': y.retention,
              'fluxoDaFirma': y.firmFlow,
              'servicoDaDivida': y.debtService,
              'fluxo': y.flow,
              'taxa': y.rate,
              'fatorDeDesconto': y.discountFactor,
              'valorPresente': y.presentValue,
            },
        ],
      };

  static ManualOutcome _outcomeFrom(Map<String, dynamic> json) {
    final costs = json['custoDoCapitalPorAno'];
    return ManualOutcome(
      fairValuePerShare: _number(json, 'precoJustoPorAcao'),
      equityValue: _number(json, 'valorDoPatrimonio'),
      explicitPresentValue: _number(json, 'valorPresenteDosAnos'),
      terminalValue: _number(json, 'valorTerminal'),
      terminalPresentValue: _number(json, 'valorPresenteDaPerpetuidade'),
      minorityInterest: _number(json, 'minoritarios'),
      postStatementCapital: _number(json, 'capitalPosBalanco'),
      terminalRate: _number(json, 'taxaDaPerpetuidade'),
      capitalCostRates: costs == null
          ? null
          : List.unmodifiable([
              for (final c in _list(json, 'custoDoCapitalPorAno'))
                _numberOf(c),
            ]),
      terminalCapitalCost: json['custoDoCapitalNaPerpetuidade'] == null
          ? null
          : _number(json, 'custoDoCapitalNaPerpetuidade'),
      terminalKind: _decode(_Wire.terminal, json['perpetuidade']),
      notices: List.unmodifiable([
        for (final raw in _list(json, 'avisos'))
          _noticeFrom(_asMap(raw)),
      ]),
      years: List.unmodifiable([
        for (final raw in _list(json, 'anos')) _yearFrom(_asMap(raw)),
      ]),
    );
  }

  static ManualNotice _noticeFrom(Map<String, dynamic> json) => ManualNotice(
        _decode(_Wire.notice, json['tipo']),
        years: List.unmodifiable([
          for (final a in _list(json, 'anos')) _numberOf(a).round(),
        ]),
      );

  static ManualYear _yearFrom(Map<String, dynamic> json) => ManualYear(
        year: _number(json, 'ano').round(),
        growth: _number(json, 'crescimento'),
        plannedGrowth: _number(json, 'crescimentoPedido'),
        profit: _number(json, 'lucro'),
        retention: _number(json, 'parcelaReinvestida'),
        firmFlow: json['fluxoDaFirma'] == null
            ? null
            : _number(json, 'fluxoDaFirma'),
        debtService: json['servicoDaDivida'] == null
            ? null
            : _number(json, 'servicoDaDivida'),
        flow: _number(json, 'fluxo'),
        rate: _number(json, 'taxa'),
        discountFactor: _number(json, 'fatorDeDesconto'),
        presentValue: _number(json, 'valorPresente'),
      );

  static ManualStep _stepFrom(Map<String, dynamic> json) => ManualStep(
        groups: List.unmodifiable([
          for (final g in _list(json, 'grupos')) _decode(_Wire.group, g),
        ]),
        from: _number(json, 'de'),
        to: json['para'] == null ? null : _number(json, 'para'),
      );

  // ---------------------------------------------- Leitura tolerante, local --

  static Object? _field(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key)) throw FormatException('Campo ausente: $key');
    return json[key];
  }

  static String _text(Map<String, dynamic> json, String key) {
    final v = _field(json, key);
    if (v is! String) throw FormatException('Campo não textual: $key');
    return v;
  }

  static double _number(Map<String, dynamic> json, String key) =>
      _numberOf(_field(json, key));

  /// Número gravado, aceitando os textos `NaN` e `Infinity` de [AuditJson].
  static double _numberOf(Object? raw) {
    final n = AuditJson.number(raw);
    if (n == null) throw FormatException('Valor não numérico: $raw');
    return n;
  }

  static DateTime _date(Map<String, dynamic> json, String key) {
    final d = DateTime.tryParse(_text(json, key));
    if (d == null) throw FormatException('Data ilegível: $key');
    return d;
  }

  static Map<String, dynamic> _map(Map<String, dynamic> json, String key) =>
      _asMap(_field(json, key));

  static Map<String, dynamic> _asMap(Object? raw) {
    if (raw is! Map) throw const FormatException('Esperado um mapa.');
    return raw.map((k, v) => MapEntry('$k', v));
  }

  static List<Object?> _list(Map<String, dynamic> json, String key) {
    final v = _field(json, key);
    if (v is! List) throw FormatException('Campo não é lista: $key');
    return v;
  }

  static T _decode<T>(Map<T, String> keys, Object? raw) {
    for (final e in keys.entries) {
      if (e.value == raw) return e.key;
    }
    throw FormatException('Chave desconhecida: $raw');
  }

  // ------------------------------------------------------- Texto do rastro --

  /// Reais em milhões, com uma casa, arredondados meio afastado de zero.
  static String _millions(double v) {
    if (!v.isFinite) return '$v';
    final tenths = (v.abs() / 1e5).round();
    return '${v < 0 ? '−' : ''}R\$ ${tenths ~/ 10},${tenths % 10} mi';
  }

  /// Dinheiro já em centavos: o texto não arredonda de novo.
  static String _money(Money m) {
    final c = m.cents.abs();
    return '${m.cents < 0 ? '−' : ''}R\$ ${c ~/ 100},'
        '${(c % 100).toString().padLeft(2, '0')}';
  }

  /// Preço em reais, arredondado ao centavo por [Money.fromReais]. Valor não
  /// finito sai como está, em vez de lançar dentro do rastro.
  static String _price(double v) =>
      v.isFinite ? _money(Money.fromReais(v)) : '$v';

  /// Fração como percentual com duas casas, arredondado meio afastado de zero.
  static String _percent(double fraction) {
    if (!fraction.isFinite) return '$fraction';
    final hundredths = (fraction * 10000).round();
    final m = hundredths.abs();
    return '${hundredths < 0 ? '−' : ''}${m ~/ 100},'
        '${(m % 100).toString().padLeft(2, '0')}%';
  }

  /// Número com [decimals] casas, arredondado meio afastado de zero.
  static String _decimal(double v, int decimals) {
    if (!v.isFinite) return '$v';
    var scale = 1;
    for (var i = 0; i < decimals; i++) {
      scale *= 10;
    }
    final scaled = (v * scale).round();
    final m = scaled.abs();
    final fraction = (m % scale).toString().padLeft(decimals, '0');
    return '${scaled < 0 ? '−' : ''}${m ~/ scale}'
        '${decimals > 0 ? ',$fraction' : ''}';
  }

  static String _terminalName(ManualTerminal kind) => switch (kind) {
        ManualTerminal.neutral => 'capital novo rendendo a própria taxa',
        ManualTerminal.advantage => 'Gordon com retorno próprio do capital novo',
        ManualTerminal.fixedFraction => 'Gordon com a parcela fixa',
        ManualTerminal.contract => 'concessão, até o fim do contrato',
      };

  static String _terminalLatex(ManualTerminal kind) => switch (kind) {
        ManualTerminal.neutral => r'TV = \frac{L_{N+1}}{k_{\infty}}',
        ManualTerminal.advantage =>
          r'TV = \frac{L_{N+1}\,(1 - g/r_{\infty})}{k_{\infty} - g}',
        ManualTerminal.fixedFraction =>
          r'TV = \frac{L_{N+1}\,(1 - b)}{k_{\infty} - g}',
        ManualTerminal.contract =>
          r'TV = \text{excedente até o fim do contrato} + \text{capital}',
      };

  static String _fieldName(ManualField f) => switch (f) {
        ManualField.baseProfit => 'lucro de partida',
        ManualField.growth => 'crescimento nos primeiros anos',
        ManualField.discountRate => 'taxa de desconto',
        ManualField.perpetualGrowth => 'crescimento na perpetuidade',
        ManualField.returnOnCapital => 'retorno sobre o capital',
        ManualField.retention => 'parcela reinvestida',
        ManualField.terminalReturn => 'retorno do capital novo',
      };

  static String _groupName(ManualGroup g) => switch (g) {
        ManualGroup.profit => 'Lucro de partida',
        ManualGroup.growth => 'Crescimento',
        ManualGroup.reinvestment => 'Reinvestimento',
        ManualGroup.rate => 'Taxa de desconto',
        ManualGroup.perpetuity => 'Perpetuidade',
        ManualGroup.newCapital => 'Capital novo',
      };
}

/// As chaves gravadas de cada enum do registro. **São dado, e não código**:
/// mudar uma delas torna ilegível o que já foi salvo com a antiga.
abstract final class _Wire {
  static const lane = {
    ValuationLane.firm: 'firma',
    ValuationLane.shareholder: 'acionista',
  };

  static const field = {
    ManualField.baseProfit: 'lucroDePartida',
    ManualField.growth: 'crescimento',
    ManualField.discountRate: 'taxaDeDesconto',
    ManualField.perpetualGrowth: 'crescimentoPerpetuo',
    ManualField.returnOnCapital: 'retornoSobreOCapital',
    ManualField.retention: 'parcelaReinvestida',
    ManualField.terminalReturn: 'retornoDoCapitalNovo',
  };

  static const growthPath = {
    ManualGrowthPath.decays: 'caiAtePerpetuidade',
    ManualGrowthPath.constant: 'constante',
  };

  static const ratePath = {
    ManualRatePath.engine: 'curvaDoMotor',
    ManualRatePath.constant: 'constante',
  };

  static const reinvestment = {
    ManualReinvestment.byReturn: 'peloRetorno',
    ManualReinvestment.fixedFraction: 'parcelaFixa',
  };

  static const terminal = {
    ManualTerminal.neutral: 'neutra',
    ManualTerminal.advantage: 'vantagem',
    ManualTerminal.fixedFraction: 'parcelaFixa',
    ManualTerminal.contract: 'contrato',
  };

  static const notice = {
    ManualNoticeKind.confinedGrowth: 'crescimentoConfinado',
    ManualNoticeKind.negativeFlow: 'fluxoNegativo',
    ManualNoticeKind.perpetualConcession: 'concessaoPerpetua',
    ManualNoticeKind.neutralPerpetuity: 'perpetuidadeNeutra',
  };

  static const group = {
    ManualGroup.profit: 'lucro',
    ManualGroup.growth: 'crescimento',
    ManualGroup.reinvestment: 'reinvestimento',
    ManualGroup.rate: 'taxa',
    ManualGroup.perpetuity: 'perpetuidade',
    ManualGroup.newCapital: 'capitalNovo',
  };
}
