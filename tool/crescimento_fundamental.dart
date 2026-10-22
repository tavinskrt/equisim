// O crescimento fundamental `g = ROE × (1 − payout)`, e o do PIB do setor para
// quem cresce sem reter — medição, sem ligar nada no motor.
//
// **A pergunta.** O motor tira o `g` da mediana das variações anuais da base
// de capital — o patrimônio na via do acionista, o capital investido na da
// firma (decisão 25). Pela identidade do lucro limpo, `Δpatrimônio = lucro ×
// retenção` quando não entra nem sai capital, e a variação da base **é** o
// `ROE × retenção` realizado ano a ano. A proposta do orientador é a versão
// que olha para a frente: o ROE normalizado vezes a retenção que o payout
// observado implica; e, para quem cresce sem precisar reter — as de pouco
// capital e as que distribuem quase tudo —, o crescimento nominal do setor.
//
// **As regras, fixadas antes de medir.**
//
//     ROE normalizado = mediana dos últimos 8 retornos sobre o patrimônio de
//                       abertura, com o do último exercício (≥ 4)
//     payout          = dividendos e JCP pagos ÷ lucro líquido, somados nos
//                       últimos 5 exercícios (≥ 3), do fluxo de caixa da DFP
//     g fundamental   = ROE normalizado × (1 − payout), retenção em [0; 1]
//
//     regra combinada:
//       commodity (a lista de precedência do ciclo do motor) → g = inflação
//       payout ≥ 75% ou receita ÷ capital investido ≥ 2      → g = PIB nominal
//                                                              do setor, 10 anos
//       o resto                                               → g fundamental
//
// Para commodity a proposta é crescimento real zero sobre a base normalizada
// pelo ciclo: preço real de commodity não tem tendência positiva de longo
// prazo, e o motor já põe a base no meio do ciclo. A variante que cresce pelo
// reinvestimento ao retorno do ciclo é a do `g` fundamental, medida ao lado.
//
// **Duas medições.**
//
// 1. Na entrada congelada, o universo reavaliado com cada `g`, imposto pelo
//    ponto de diagnóstico do motor (`withOverrides(growth:)`): o decaimento
//    até `g∞`, o teto da economia e o freio `g ≤ 0,95 × ROIC` continuam.
// 2. No histórico: em cada exercício de 2014 a 2022, o `g` que cada regra
//    daria com os dados até ele, contra o crescimento que aconteceu nos três
//    exercícios seguintes. É a régua de «projeção real».
//
//   python tool/cvm/dividendos_pagos.py        # data/cvm/dividendos_pagos.json
//   python tool/pib_setorial_baixar.py         # data/indices/pib_setorial.json
//   dart run tool/crescimento_fundamental.dart # grava crescimento_fundamental.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/ibovespa_longo.dart';
import 'validation/regression.dart';

const _output = 'docs/validacao/crescimento_fundamental.json';

/// Payout a partir do qual a companhia é alta pagadora.
const _highPayout = 0.75;

/// Receita ÷ capital investido a partir da qual o negócio é de pouco capital.
const _salesToCapital = 2.0;

/// Exercícios somados no payout, e o mínimo presente.
const _payoutYears = 5;
const _minPayoutYears = 3;

/// Retornos na mediana do ROE normalizado, e o mínimo.
const _roeWindow = 8;
const _minRoeYears = 4;

/// Anos do crescimento do setor.
const _sectorYears = 10;

/// Dias entre o fim do trimestre e a publicação das Contas Nacionais.
const _gdpLag = 70;

/// Exercícios do crescimento realizado.
const _realizedYears = 3;

/// A atividade do IBGE de cada setor e subsetor da B3, fixada antes de medir.
const Map<String, String> _activity = {
  'Bens Industriais|Comércio': 'Comércio',
  'Bens Industriais|Construção e Engenharia': 'Construção',
  'Bens Industriais|Material de Transporte': 'Indústrias de transformação',
  'Bens Industriais|Máquinas e Equipamentos': 'Indústrias de transformação',
  'Bens Industriais|Serviços': 'Outras atividades de serviços',
  'Bens Industriais|Transporte': 'Transporte, armazenagem e correio',
  'Comunicações|Telecomunicações': 'Informação e comunicação',
  'Consumo Cíclico|Automóveis e Motocicletas': 'Indústrias de transformação',
  'Consumo Cíclico|Comércio': 'Comércio',
  'Consumo Cíclico|Construção Civil': 'Construção',
  'Consumo Cíclico|Diversos': 'Outras atividades de serviços',
  'Consumo Cíclico|Hoteis e Restaurantes': 'Outras atividades de serviços',
  'Consumo Cíclico|Tecidos. Vestuário e Calçados':
      'Indústrias de transformação',
  'Consumo Cíclico|Utilidades Domésticas': 'Indústrias de transformação',
  'Consumo Cíclico|Viagens e Lazer': 'Outras atividades de serviços',
  'Consumo não Cíclico|Agropecuária': 'Agropecuária - total',
  'Consumo não Cíclico|Alimentos Processados': 'Indústrias de transformação',
  'Consumo não Cíclico|Bebidas': 'Indústrias de transformação',
  'Consumo não Cíclico|Comércio e Distribuição': 'Comércio',
  'Consumo não Cíclico|Produtos de Uso Pessoal e de Limpeza':
      'Indústrias de transformação',
  'Financeiro|Exploração de Imóveis': 'Atividades imobiliárias',
  'Financeiro|Holdings Diversificadas':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Financeiro|Intermediários Financeiros':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Financeiro|Previdência e Seguros':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Financeiro|Serviços Diversos':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Financeiro|Serviços Financeiros Diversos':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Materiais Básicos|Embalagens': 'Indústrias de transformação',
  'Materiais Básicos|Madeira e Papel': 'Indústrias de transformação',
  'Materiais Básicos|Materiais Diversos': 'Indústrias de transformação',
  'Materiais Básicos|Mineração': 'Indústrias extrativas',
  'Materiais Básicos|Químicos': 'Indústrias de transformação',
  'Materiais Básicos|Siderurgia e Metalurgia': 'Indústrias de transformação',
  'Petróleo. Gás e Biocombustíveis|Petróleo. Gás e Biocombustíveis':
      'Indústrias extrativas',
  'Saúde|Comércio e Distribuição': 'Comércio',
  'Saúde|Equipamentos': 'Indústrias de transformação',
  'Saúde|Medicamentos e Outros Produtos': 'Indústrias de transformação',
  'Saúde|Serv.Méd.Hospit..Análises e Diagnósticos':
      'Outras atividades de serviços',
  'Tecnologia da Informação|Computadores e Equipamentos':
      'Indústrias de transformação',
  'Tecnologia da Informação|Programas e Serviços': 'Informação e comunicação',
  'Utilidade Pública|Energia Elétrica':
      'Eletricidade e gás, água, esgoto, atividades de gestão de resíduos',
  'Utilidade Pública|Gás':
      'Eletricidade e gás, água, esgoto, atividades de gestão de resíduos',
  'Utilidade Pública|Água e Saneamento':
      'Eletricidade e gás, água, esgoto, atividades de gestão de resíduos',
};

/// Sem subsetor mapeado, o valor adicionado da economia inteira.
const _economy = 'Valor adicionado a preços básicos';

String _pct(double? v, [int decimals = 2]) =>
    v == null ? '—' : '${(v * 100).toStringAsFixed(decimals)}%';

double? _median(List<double> v) => v.isEmpty ? null : Inference.median(v);

// ---------------------------------------------------------------------------
// Fontes
// ---------------------------------------------------------------------------

/// O valor adicionado por atividade, de `tool/pib_setorial_baixar.py`.
class _SectorGdp {
  _SectorGdp(this._series);
  final Map<String, Map<DateTime, double>> _series;

  static _SectorGdp read() {
    final f = File('data/indices/pib_setorial.json');
    if (!f.existsSync()) {
      throw StateError(
        'Falta data/indices/pib_setorial.json. Rode antes: '
        'python tool/pib_setorial_baixar.py',
      );
    }
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return _SectorGdp({
      for (final e in (j['atividades'] as Map<String, dynamic>).entries)
        e.key: {
          for (final p in (e.value as List).cast<List>())
            _endOfQuarter(p[0] as String): (p[1] as num).toDouble(),
        },
    });
  }

  /// `201904` é o quarto trimestre de 2019; devolve o último dia dele, em UTC.
  static DateTime _endOfQuarter(String code) {
    final year = int.parse(code.substring(0, 4));
    final t = int.parse(code.substring(4));
    return DateTime.utc(year, t * 3 + 1, 0);
  }

  /// Crescimento anual composto das quatro últimas leituras publicadas até
  /// [date] contra as mesmas quatro, [years] antes.
  double? growth(
    String activity,
    DateTime date, {
    int years = _sectorYears,
  }) {
    final s = _series[activity];
    if (s == null) return null;
    final limit = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).subtract(const Duration(days: _gdpLag));
    final published = s.keys.where((d) => !d.isAfter(limit)).toList()..sort();
    if (published.length < 4) return null;
    final lastOnes = published.sublist(published.length - 4);
    var today = 0.0, before = 0.0;
    for (final d in lastOnes) {
      final old = DateTime.utc(d.year - years, d.month + 1, 0);
      final v = s[old];
      if (v == null) return null;
      today += s[d]!;
      before += v;
    }
    if (!(before > 0) || !(today > 0)) return null;
    return math.pow(today / before, 1 / years).toDouble() - 1;
  }
}

/// Dividendos e JCP pagos por CNPJ e exercício, em centavos, de
/// `tool/cvm/dividendos_pagos.py`.
Map<String, Map<int, int>> _readDividends() {
  final f = File('data/cvm/dividendos_pagos.json');
  if (!f.existsSync()) {
    throw StateError(
      'Falta data/cvm/dividendos_pagos.json. Rode antes: '
      'python tool/cvm/dividendos_pagos.py',
    );
  }
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in (j['companhias'] as Map<String, dynamic>).entries)
      e.key: {
        for (final a in (e.value as Map<String, dynamic>).entries)
          int.parse(
            a.key,
          ): (((a.value as Map<String, dynamic>)['pago'] as num) * 100)
              .round(),
      },
  };
}

// ---------------------------------------------------------------------------
// As grandezas de cada regra, com os dados até o exercício [ano]
// ---------------------------------------------------------------------------

/// Os exercícios até [year], um por ano (o de fim mais tardio).
List<FundamentalsSnapshot> _until(List<FundamentalsSnapshot> fs, int year) {
  final byYear = <int, FundamentalsSnapshot>{};
  for (final s in fs) {
    final y = s.fiscalPeriodEnd.year;
    if (y > year) continue;
    final current = byYear[y];
    if (current == null || s.fiscalPeriodEnd.isAfter(current.fiscalPeriodEnd)) {
      byYear[y] = s;
    }
  }
  return [for (final y in byYear.keys.toList()..sort()) byYear[y]!];
}

/// Mediana dos últimos [_roeWindow] retornos sobre o patrimônio de abertura.
double? _normalizedRoe(List<FundamentalsSnapshot> until) {
  final r = CapitalSeries.build(until, ValuationLane.shareholder).returns;
  if (r.length < _minRoeYears) return null;
  final window = r.sublist(math.max(0, r.length - _roeWindow));
  return _median([for (final x in window) x.value]);
}

/// Dividendos pagos ÷ lucro, somados nos últimos [_payoutYears] exercícios.
double? _payout(List<FundamentalsSnapshot> until, Map<int, int>? paidByYear, int year) {
  if (paidByYear == null) return null;
  var paid = 0, profit = 0, n = 0;
  for (final s in until) {
    final y = s.fiscalPeriodEnd.year;
    if (y <= year - _payoutYears || y > year) continue;
    final d = paidByYear[y];
    final l = s.netIncome;
    if (d == null || l == null || !l.isFinite) continue;
    paid += d;
    profit += (l * 100).round();
    n++;
  }
  if (n < _minPayoutYears || profit <= 0) return null;
  return paid / profit;
}

/// Receita ÷ capital investido, mediana dos três últimos exercícios.
double? _salesPerCapital(List<FundamentalsSnapshot> until) {
  final v = <double>[
    for (final s in until.sublist(math.max(0, until.length - 3)))
      if ((s.totalRevenue ?? 0) > 0 && (s.investedCapital ?? 0) > 0)
        s.totalRevenue! / s.investedCapital!,
  ];
  return v.length < 2 ? null : _median(v);
}

enum _Group { commodity, highPayer, lowCapital, fundamental, noData }

String _nameOf(_Group g) => switch (g) {
  _Group.commodity => 'commodity',
  _Group.highPayer => 'alta pagadora',
  _Group.lowCapital => 'pouco capital',
  _Group.fundamental => 'ROE × retenção',
  _Group.noData => 'sem dado',
};

/// O que as duas propostas dão para uma companhia num exercício.
class _Reading {
  _Reading({
    required this.roe,
    required this.payout,
    required this.salesPerCapital,
    required this.gFundamental,
    required this.gSector,
    required this.activity,
    required this.group,
    required this.gRule,
  });
  final double? roe;
  final double? payout;
  final double? salesPerCapital;
  final double? gFundamental;
  final double? gSector;
  final String activity;
  final _Group group;
  final double? gRule;
}

_Reading _read({
  required List<FundamentalsSnapshot> fs,
  required int year,
  required Map<int, int>? paidByYear,
  required bool commodity,
  required String activity,
  required _SectorGdp gdp,
  required DateTime date,
  required double inflation,
}) {
  final until = _until(fs, year);
  final roe = _normalizedRoe(until);
  final payout = _payout(until, paidByYear, year);
  final salesPerCapitalValue = _salesPerCapital(until);
  final gFund = (roe == null || payout == null)
      ? null
      : roe * (1 - payout).clamp(0.0, 1.0);
  final gSector = gdp.growth(activity, date);
  final _Group group;
  final double? gRule;
  if (commodity) {
    group = _Group.commodity;
    gRule = inflation;
  } else if ((payout ?? 0) >= _highPayout) {
    group = _Group.highPayer;
    gRule = gSector;
  } else if ((salesPerCapitalValue ?? 0) >= _salesToCapital) {
    group = _Group.lowCapital;
    gRule = gSector;
  } else if (gFund != null) {
    group = _Group.fundamental;
    gRule = gFund;
  } else {
    group = _Group.noData;
    gRule = null;
  }
  return _Reading(
    roe: roe,
    payout: payout,
    salesPerCapital: salesPerCapitalValue,
    gFundamental: gFund,
    gSector: gSector,
    activity: activity,
    group: group,
    gRule: gRule,
  );
}

/// O `g` que a regra do motor dá com os dados até [ano], na via [lane]: a
/// mediana das variações da base quando a dispersão a identifica; a inflação
/// quando não identifica e a retenção a financia; zero no resto (`_output2`).
double? _engineG(
  List<FundamentalsSnapshot> until,
  ValuationLane lane,
  double inflation,
) {
  final series = CapitalSeries.build(until, lane);
  final d = GrowthGuards.dispersion(series);
  if (d == null) return null;
  if (d.isIdentified) return d.medianGrowth;
  final cycle = series.cycleReturn(window: ValuationParameters.cycleWindow);
  return GrowthGuards.anchorIsFundable(
        inflation: inflation,
        cycleReturn: cycle,
        observedRetention: series.medianRetention,
      )
      ? inflation
      : 0.0;
}

/// Crescimento anual composto dos três primeiros anos do caminho que o motor
/// projeta a partir de [g]: decai em linha reta até `g∞ = min(g, teto)`, em
/// [−5%; teto]. Composto, e não média das taxas, porque o realizado contra o
/// qual se compara também é composto.
double? _pathMean(double g, double cap, {int years = 10}) {
  final gInf = GrowthEstimator.perpetual(
    explicitGrowth: g,
    economyGrowth: cap,
  );
  var factor = 1.0;
  for (var t = 1; t <= _realizedYears; t++) {
    factor *= 1 + g - (g - gInf) * ((t - 1) / (years - 1));
  }
  // Taxa abaixo de −100% num ano não tem caminho composto: fica sem leitura.
  if (!(factor > 0)) return null;
  return math.pow(factor, 1 / _realizedYears).toDouble() - 1;
}

/// Crescimento realizado do lucro: da média dos três exercícios até [year] à
/// dos três seguintes, anualizado em três anos. `null` se uma média não é
/// positiva ou falta exercício.
double? _realizedProfit(List<FundamentalsSnapshot> fs, int year) {
  final byYear = {
    for (final s in _until(fs, year + _realizedYears)) s.fiscalPeriodEnd.year: s,
  };
  double? mean(int from, int until) {
    final v = <double>[];
    for (var y = from; y <= until; y++) {
      final l = byYear[y]?.netIncome;
      if (l == null || !l.isFinite) return null;
      v.add(l);
    }
    final m = v.reduce((a, b) => a + b) / v.length;
    return m > 0 ? m : null;
  }

  final before = mean(year - 2, year);
  final after = mean(year + 1, year + _realizedYears);
  if (before == null || after == null) return null;
  return math.pow(after / before, 1 / _realizedYears).toDouble() - 1;
}

/// Crescimento realizado do patrimônio em três exercícios.
double? _realizedEquity(List<FundamentalsSnapshot> fs, int year) {
  final byYear = {
    for (final s in _until(fs, year + _realizedYears)) s.fiscalPeriodEnd.year: s,
  };
  final a = byYear[year]?.equityBookValue;
  final b = byYear[year + _realizedYears]?.equityBookValue;
  if (a == null || b == null || !(a > 0) || !(b > 0)) return null;
  return math.pow(b / a, 1 / _realizedYears).toDouble() - 1;
}

// ---------------------------------------------------------------------------

class _Asset {
  _Asset(this.ticker, this.sector, this.reading);
  final String ticker;
  final String sector;
  final _Reading reading;
  double? g0;
  ValuationLane? lane;
  final Map<String, int?> fairValue = {};
  final Map<String, double?> upside = {};
  double? price;
}

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  try {
    final bridge =
        ((jsonDecode(File('docs/validacao/ponte_cvm.json').readAsStringSync())
                    as Map<String, dynamic>)['ponte']
                as Map<String, dynamic>)
            .cast<String, String>();
    final dividendTotals = _readDividends();
    final gdp = _SectorGdp.read();
    final today = frozenToday;
    final todayDate = DateTime.utc(today.year, today.month, today.day);
    final currentInflation = c.anchors.inflationCagr;
    final currentCap = c.anchors.nominalEconomyGrowth;

    // -----------------------------------------------------------------------
    // 1. A entrada congelada
    // -----------------------------------------------------------------------
    final assets = <_Asset>[];
    final histories = <String, List<FundamentalsSnapshot>>{};
    final cnpjOf = <String, String?>{};
    final commodityOf = <String, bool>{};
    final activityOf = <String, String>{};
    final baseEvaluated = <Ticker, ValuationResult?>{};
    final withoutMap = <String>[];
    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final prep = await c.prepare(t);
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      final r0 = ValuationCascade.evaluate(inputs);
      baseEvaluated[t] = r0.valueOrNull;

      final classification = c.issuer(t)?.classification;
      final key = classification == null || classification.subsector == null
          ? ''
          : '${classification.sector}|${classification.subsector}';
      final activity = _activity[key] ?? _economy;
      if (!_activity.containsKey(key)) withoutMap.add('${t.value} «$key»');
      final commodity = CyclicalSectors.hasCyclePrecedence(
        sectorKey: inputs.sectorKey,
        industry: inputs.industry,
      );
      final cnpj = bridge[t.value];
      final lastYear = _until(
        inputs.fundamentals,
        today.year,
      ).lastOrNull?.fiscalPeriodEnd.year;
      if (lastYear == null) continue;
      final reading = _read(
        fs: inputs.fundamentals,
        year: lastYear,
        paidByYear: cnpj == null ? null : dividendTotals[cnpj],
        commodity: commodity,
        activity: activity,
        gdp: gdp,
        date: todayDate,
        inflation: currentInflation,
      );
      final a = _Asset(t.value, key.replaceAll('|', ' / '), reading);
      histories[t.value] = inputs.fundamentals;
      cnpjOf[t.value] = cnpj;
      commodityOf[t.value] = commodity;
      activityOf[t.value] = activity;
      a.price = inputs.marketPrice;

      void store(String label, Result<ValuationResult> r) {
        final v = r.valueOrNull;
        a.fairValue[label] = v?.fairValue.cents;
        a.upside[label] = v?.upside;
      }

      store('motor', r0);
      a.g0 = r0.valueOrNull?.diagnostics?.growthRate;
      a.lane = switch (r0.valueOrNull?.model) {
        ValuationModel.dcfFcff => ValuationLane.firm,
        ValuationModel.dcfEarnings => ValuationLane.shareholder,
        null => null,
      };
      final gF = reading.gFundamental;
      store(
        'fundamental',
        gF == null
            ? r0
            : ValuationCascade.evaluate(inputs.withOverrides(growth: gF)),
      );
      final gR = reading.gRule;
      store(
        'combinada',
        gR == null
            ? r0
            : ValuationCascade.evaluate(inputs.withOverrides(growth: gR)),
      );
      assets.add(a);
    }
    stderr.write('                    \r');
    if (withoutMap.isNotEmpty) {
      stderr.writeln(
        'sem atividade mapeada (vai a economia inteira): '
        '${withoutMap.join(', ')}',
      );
    }

    final divergent = await c.checkAgainstAnswerKey(baseEvaluated);
    if (divergent != null && divergent.isNotEmpty) {
      stderr.writeln(
        'ERRO: a montagem diverge do gabarito em '
        '${divergent.length}: ${divergent.take(8).join(', ')}',
      );
      exitCode = 1;
      return;
    }

    final variants = ['motor', 'fundamental', 'combinada'];
    final evaluated =
        assets.where((a) => variants.any((v) => a.fairValue[v] != null)).toList()
          ..sort((x, y) => x.ticker.compareTo(y.ticker));

    stdout.writeln('-- a entrada congelada: o g de cada regra --');
    stdout.writeln(
      '  ticker   grupo            payout   ROE norm  g motor  '
      'g fund   g setor  g regra   justo motor  justo fund  justo regra   preço',
    );
    String r$(int? cents) =>
        cents == null ? 'recusada' : (cents / 100).toStringAsFixed(2);
    for (final a in evaluated) {
      final l = a.reading;
      stdout.writeln(
        '  ${a.ticker.padRight(7)}  '
        '${_nameOf(l.group).padRight(15)}  ${_pct(l.payout, 0).padLeft(6)}  '
        '${_pct(l.roe, 1).padLeft(8)}  ${_pct(a.g0, 1).padLeft(7)}  '
        '${_pct(l.gFundamental, 1).padLeft(6)}  ${_pct(l.gSector, 1).padLeft(7)}  '
        '${_pct(l.gRule, 1).padLeft(7)}   ${r$(a.fairValue['motor']).padLeft(11)}  '
        '${r$(a.fairValue['fundamental']).padLeft(10)}  '
        '${r$(a.fairValue['combinada']).padLeft(11)}  '
        '${a.price?.toStringAsFixed(2)}',
      );
    }

    final summary = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- o universo com cada regra --');
    stdout.writeln(
      '  regra         avaliados  potencial mediano  acima de zero  '
      'distância mediana ao preço  justo vs motor  postos',
    );
    for (final v in variants) {
      final withInput = [
        for (final a in evaluated)
          if (a.fairValue[v] != null) a,
      ];
      final upsideValues = [for (final a in withInput) ?a.upside[v]];
      // O logaritmo só existe com as duas pontas positivas.
      final dist = [
        for (final a in withInput)
          if ((a.price ?? 0) > 0 && a.fairValue[v]! > 0)
            (math.log(a.fairValue[v]! / 100 / a.price!)).abs(),
      ];
      final common = [
        for (final a in evaluated)
          if (a.fairValue[v] != null &&
              a.fairValue['motor'] != null &&
              a.upside[v] != null &&
              a.upside['motor'] != null)
            a,
      ];
      final changeList = [
        for (final a in common)
          if (a.fairValue['motor']! != 0) a.fairValue[v]! / a.fairValue['motor']! - 1,
      ];
      final rho = common.length < 3
          ? null
          : Regression.spearman(
              [for (final a in common) a.upside['motor']!],
              [for (final a in common) a.upside[v]!],
            );
      final medianUpside = _median(upsideValues);
      final medDist = _median(dist);
      final medVar = _median(changeList);
      final above = upsideValues.where((p) => p > 0).length;
      stdout.writeln(
        '  ${v.padRight(12)}  ${withInput.length.toString().padLeft(9)}  '
        '${_pct(medianUpside, 1).padLeft(17)}  ${'$above de ${withInput.length}'.padLeft(13)}  '
        '${(medDist == null ? '—' : medDist.toStringAsFixed(3)).padLeft(26)}  '
        '${_pct(medVar, 1).padLeft(14)}  ${rho?.toStringAsFixed(3) ?? '—'}',
      );
      summary.add({
        'regra': v,
        'avaliados': withInput.length,
        'potencialMediano': medianUpside,
        'acimaDeZero': above,
        'distanciaMedianaAoPreco': medDist,
        'justoMedianoContraMotor': medVar,
        'spearmanContraMotor': rho,
      });
    }

    // Por grupo da regra combinada.
    final byGroup = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- por grupo da regra combinada --');
    for (final g in _Group.values) {
      final ofGroup = [
        for (final a in evaluated)
          if (a.reading.group == g) a,
      ];
      if (ofGroup.isEmpty) continue;
      double? med(double? Function(_Asset) f) =>
          _median([for (final a in ofGroup) ?f(a)]);
      final row = {
        'grupo': _nameOf(g),
        'ativos': ofGroup.length,
        'gMotor': med((a) => a.g0),
        'gFundamental': med((a) => a.reading.gFundamental),
        'gRegra': med((a) => a.reading.gRule),
        'potencialMotor': med((a) => a.upside['motor']),
        'potencialFundamental': med((a) => a.upside['fundamental']),
        'potencialCombinada': med((a) => a.upside['combinada']),
      };
      byGroup.add(row);
      stdout.writeln(
        '  ${_nameOf(g).padRight(15)} ${ofGroup.length.toString().padLeft(3)}  '
        'g motor ${_pct(row['gMotor'] as double?, 1)}  '
        'g fund ${_pct(row['gFundamental'] as double?, 1)}  '
        'g regra ${_pct(row['gRegra'] as double?, 1)}  '
        'potencial ${_pct(row['potencialMotor'] as double?, 1)} → '
        '${_pct(row['potencialFundamental'] as double?, 1)} / '
        '${_pct(row['potencialCombinada'] as double?, 1)}',
      );
    }

    // -----------------------------------------------------------------------
    // 2. O histórico: qual g acertou o crescimento seguinte
    // -----------------------------------------------------------------------
    final index = await LongIbovespa.build(
      c.ctx.benchmark,
      sourceWindow: DateRange(
        DateTime(today.year - 10, today.month, today.day),
        today,
      ),
    );
    final panel = <Map<String, Object?>>[];
    for (var year = 2014; year <= 2022; year++) {
      final anchors = (await ResolveMarketAnchors.call(
        macro: c.ctx.macro,
        benchmark: index,
        asOf: DateTime(year, 12, 31),
      )).unwrap();
      final inflation = anchors.inflationCagr;
      final cap = anchors.nominalEconomyGrowth;
      final date = DateTime.utc(year + 1, 3, 31);
      for (final a in evaluated) {
        final fs = histories[a.ticker]!;
        final lane = a.lane ?? ValuationLane.shareholder;
        final until = _until(fs, year);
        if (until.isEmpty || until.last.fiscalPeriodEnd.year != year) continue;
        final gEngine = _engineG(until, lane, inflation);
        final l = _read(
          fs: fs,
          year: year,
          paidByYear: cnpjOf[a.ticker] == null ? null : dividendTotals[cnpjOf[a.ticker]],
          commodity: commodityOf[a.ticker]!,
          activity: activityOf[a.ticker]!,
          gdp: gdp,
          date: date,
          inflation: inflation,
        );
        final profit = _realizedProfit(fs, year);
        final equity = _realizedEquity(fs, year);
        panel.add({
          'ticker': a.ticker,
          'ano': year,
          'grupo': _nameOf(l.group),
          'gMotor': gEngine == null ? null : _pathMean(gEngine, cap),
          'gFundamental': l.gFundamental == null
              ? null
              : _pathMean(l.gFundamental!, cap),
          'gCombinada': l.gRule == null
              ? null
              : _pathMean(l.gRule!, cap),
          'realizadoLucro': profit,
          'realizadoPatrimonio': equity,
        });
      }
    }

    final tests = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln(
      '-- o histórico: o g de cada regra contra o crescimento dos três '
      'exercícios seguintes (2014 a 2022) --',
    );
    stdout.writeln(
      '  alvo         regra         pares  erro absoluto mediano  '
      'viés mediano  postos',
    );
    for (final target in ['realizadoLucro', 'realizadoPatrimonio']) {
      // Só os pares em que as três regras existem: a comparação é no mesmo
      // conjunto.
      final pairs = [
        for (final p in panel)
          if (p[target] != null &&
              p['gMotor'] != null &&
              p['gFundamental'] != null &&
              p['gCombinada'] != null)
            p,
      ];
      for (final rule in ['gMotor', 'gFundamental', 'gCombinada']) {
        final errors = [
          for (final p in pairs) (p[rule] as double) - (p[target] as double),
        ];
        final abs = [for (final e in errors) e.abs()];
        final rho = pairs.length < 3
            ? null
            : Regression.spearman(
                [for (final p in pairs) p[rule] as double],
                [for (final p in pairs) p[target] as double],
              );
        final row = {
          'alvo': target,
          'regra': rule,
          'pares': pairs.length,
          'erroAbsolutoMediano': _median(abs),
          'viesMediano': _median(errors),
          'spearman': rho,
        };
        tests.add(row);
        stdout.writeln(
          '  ${target.padRight(11)}  ${rule.padRight(12)}  '
          '${pairs.length.toString().padLeft(5)}  '
          '${_pct(row['erroAbsolutoMediano'] as double?).padLeft(21)}  '
          '${_pct(row['viesMediano'] as double?).padLeft(12)}  '
          '${rho?.toStringAsFixed(3) ?? '—'}',
        );
      }
    }

    File(_output).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'geradoPor': 'tool/crescimento_fundamental.dart',
        'dataDaEntrada': today.toIso8601String().substring(0, 10),
        'inflacao': currentInflation,
        'teto': currentCap,
        'regras': {
          'payoutAlto': _highPayout,
          'vendasSobreCapital': _salesToCapital,
          'anosDoPayout': _payoutYears,
          'janelaDoRoe': _roeWindow,
          'anosDoSetor': _sectorYears,
        },
        'ativos': [
          for (final a in evaluated)
            {
              'ticker': a.ticker,
              'setor': a.sector,
              'atividade': a.reading.activity,
              'grupo': _nameOf(a.reading.group),
              'payout': a.reading.payout,
              'roeNormalizado': a.reading.roe,
              'vendasPorCapital': a.reading.salesPerCapital,
              'gMotor': a.g0,
              'gFundamental': a.reading.gFundamental,
              'gSetor': a.reading.gSector,
              'gRegra': a.reading.gRule,
              'preco': a.price,
              'justoCentavos': a.fairValue,
              'potencial': a.upside,
            },
        ],
        'resumo': summary,
        'porGrupo': byGroup,
        'historico': {'testes': tests, 'painel': panel},
      }),
    );
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}
