// Regressão condicional — o potencial informa o que os fatores ingênuos não
// informam?
//
// **A pergunta.** A validação preditiva mediu o coeficiente de informação do
// potencial em 0,170 contra 0,213 do valor patrimonial sobre preço e 0,186 do
// lucro sobre preço, em 36 meses. O motor ordena, e **não** supera dois
// fatores de uma linha. Isso deixa aberta a única pergunta que decide se a
// cascata se paga: o que ela vê é o que o P/B e o L/P já viam, ou é
// informação própria?
//
// Correlação isolada não responde. Três ordenadores correlacionados entre si
// podem ter o mesmo IC e conteúdo idêntico. O que separa é a regressão
// **conjunta**: com os três dentro, o coeficiente do potencial sobrevive?
//
// **Como.** Fama-MacBeth em dois passos. Em cada coorte, uma regressão
// transversal do retorno realizado nos três ordenadores; depois, a média dos
// coeficientes entre coortes, com o `t` do segundo passo. Tudo em postos
// padronizados — o potencial tem cauda pesadíssima (um ativo chega a +477%) e
// regressão de nível sobre ele mediria o extremo, não a relação.
//
// A **IC incremental** é a mesma pergunta por outro caminho, e é a mais fácil
// de ler: retira-se do potencial o que P/B e L/P explicam, e mede-se a
// correlação de ordem do resíduo com o retorno. É o sinal que sobra depois de
// pagar o que já estava disponível de graça.
//
// **A ressalva que viaja junto.** Cinco coortes anuais de 36 meses não são
// cinco observações independentes: as janelas se sobrepõem em dois terços. O
// `t` do segundo passo superestima a confiança, e o que a medição sustenta é
// o sinal e a consistência, não um nível de significância.
//
// Entrada: `docs/validacao/backtest_valuation.json`, produzido por
// `tool/backtest_valuation.dart`. Este utilitário **não vai à rede**.
//
// Uso:
//   dart run tool/regressao_condicional.dart
//   dart run tool/regressao_condicional.dart --aplicativo   # C1a e C1b, anuais
//   dart run tool/regressao_condicional.dart --trimestral   # C1c, C1d e C3
//   dart run tool/regressao_condicional.dart --pacote-habilidade  # B1.0
//
// `--trimestral` grava também `assets/validacao/habilidade.json`, a leitura que a
// tela de metas mostra (item B1.0); `--pacote-habilidade` regrava só o pacote,
// a partir de `docs/validacao/habilidade_trimestral.json`, sem remedir.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart'
    show
        SkillReadingCodec,
        TransversalOrdering,
        TransversalScore,
        TransversalSignals;

import 'validation/regression.dart';
import 'package:equisim/presentation/shared/domain_copy.dart';

/// Uma observação utilizável: os três ordenadores e o retorno, todos presentes.
class Obs {
  /// A data da coorte, ou o ano nas saídas anuais antigas: em ordem de texto é
  /// a ordem de data nos dois formatos.
  final String cohort;
  final String ticker;
  final double upside;
  final double bookToMarket;
  final double earningsYield;
  final double returnRate;

  const Obs({
    required this.cohort,
    required this.ticker,
    required this.upside,
    required this.bookToMarket,
    required this.earningsYield,
    required this.returnRate,
  });
}

double? _num(dynamic v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  return null;
}

/// Lê as observações de um horizonte, mantendo só as linhas completas.
///
/// O recorte é **conjunto** de propósito: comparar ordenadores medidos em
/// subconjuntos diferentes compararia coberturas, e não ordenadores.
/// - [upside], [bookToMarket], [earningsYield]: os campos lidos — os da série
///   de DFPs por padrão; os `…Ancorada` e `…BaseAntiga` nas comparações.
/// - [require]: campos que têm de estar presentes, para que duas leituras sejam
///   medidas sobre as mesmas observações.
List<Obs> _load(
  List<dynamic> raw,
  String returnField, {
  String upside = 'upside',
  String bookToMarket = 'bookToMarket',
  String earningsYield = 'earningsYield',
  List<String> require = const [],
  bool Function(Map<String, dynamic>)? filter,
}) {
  final out = <Obs>[];
  for (final row in raw) {
    final m = row as Map<String, dynamic>;
    if (filter != null && !filter(m)) continue;
    if (require.any((c) => _num(m[c]) == null)) continue;
    final upsides = _num(m[upside]);
    final bm = _num(m[bookToMarket]);
    final ey = _num(m[earningsYield]);
    final ret = _num(m[returnField]);
    if (upsides == null || bm == null || ey == null || ret == null) continue;
    out.add(Obs(
      cohort: '${m['coorte']}',
      ticker: m['ticker'] as String,
      upside: upsides,
      bookToMarket: bm,
      earningsYield: ey,
      returnRate: ret,
    ));
  }
  return out;
}

/// **O instrumento do R3, para quem o reaplica** — a leitura do C7
/// (`tool/c7_leitura.dart`). É a mesma função que mede as coortes de 2018 a
/// 2025: reimplementá-la ao lado daria dois instrumentos, e a réplica só vale
/// se o instrumento for o mesmo.
///
/// - [rows]: observações no formato do backtest — `coorte`, `upside`,
///   `bookToMarket`, `earningsYield` e o campo de retorno.
/// - [field]: `ret12tot` ou `ret36tot`.
/// - [lag]: `meses ÷ 3 − 1` nas coortes trimestrais.
Map<String, dynamic> skillHorizon(
  List<dynamic> rows,
  String field, {
  required int lag,
}) =>
    _horizon(rows, field, lag: lag);

/// O que uma coorte devolve.
class PerCohort {
  final String cohort;
  final int n;

  /// Coeficientes da regressão conjunta, em postos padronizados.
  final double? upsideCoef;
  final double? coefBookToMarket;
  final double? coefEarningsYield;
  final double? upsideT;
  final double? r2;

  /// Coeficiente do potencial condicionado **só** ao P/B — o critério do R3.
  final double? upsideCoefGivenBm;

  /// Coeficiente da regressão só com o potencial — equivalente ao IC.
  final double? aloneCoef;

  /// Correlação de ordem do resíduo do potencial com o retorno.
  final double? icIncremental;

  /// O IC do potencial **ortogonalizado ao book-to-market sozinho** — o item
  /// B2, ao pé da letra.
  ///
  /// [icIncremental] tira do potencial o que o P/B **e** o L/P explicam; este
  /// tira só o que o P/B explica. A distinção importa: o P/B é o fator contra
  /// o qual a §0 do plano mediu o motor, e é ele que o B2 nomeia. Publicar os
  /// dois evita que a grandeza de acompanhamento mude de definição entre
  /// rodadas sem ninguém notar.
  final double? incrementalIcGivenBm;

  /// IC simples de cada ordenador, para conferir contra o relatório anterior.
  final double? upsideIc;
  final double? icBookToMarket;
  final double? icEarningsYield;

  /// IC do composto — a média dos escores robustos dos três sinais, pela mesma
  /// função que o aplicativo usa (item B1, `ordenacao_lado_a_lado.md` §1).
  final double? compositeIc;

  const PerCohort({
    required this.cohort,
    required this.n,
    required this.upsideCoef,
    required this.coefBookToMarket,
    required this.coefEarningsYield,
    required this.upsideT,
    required this.r2,
    required this.upsideCoefGivenBm,
    required this.aloneCoef,
    required this.icIncremental,
    required this.incrementalIcGivenBm,
    required this.upsideIc,
    required this.icBookToMarket,
    required this.icEarningsYield,
    required this.compositeIc,
  });

  Map<String, dynamic> toJson() => {
        'coorte': cohort,
        'n': n,
        'coefPotencial': upsideCoef,
        'coefBookToMarket': coefBookToMarket,
        'coefEarningsYield': coefEarningsYield,
        'tPotencial': upsideT,
        'r2': r2,
        'coefPotencialDadoBm': upsideCoefGivenBm,
        'coefSozinho': aloneCoef,
        'icIncremental': icIncremental,
        'icIncrementalDadoBm': incrementalIcGivenBm,
        'icPotencial': upsideIc,
        'icBookToMarket': icBookToMarket,
        'icEarningsYield': icEarningsYield,
        'icComposto': compositeIc,
      };
}

PerCohort _runCohort(String cohort, List<Obs> obs) {
  final upsides = [for (final o in obs) o.upside];
  final bm = [for (final o in obs) o.bookToMarket];
  final ey = [for (final o in obs) o.earningsYield];
  final ret = [for (final o in obs) o.returnRate];

  final zUpside = Regression.standardizedRanks(upsides);
  final zBm = Regression.standardizedRanks(bm);
  final zEy = Regression.standardizedRanks(ey);
  final zRet = Regression.standardizedRanks(ret);

  final joint = Regression.ols([zUpside, zBm, zEy], zRet);
  final givenBm = Regression.ols([zUpside, zBm], zRet);
  final alone = Regression.ols([zUpside], zRet);
  final residual = Regression.residualize(zUpside, [zBm, zEy]);
  final residualGivenBm = Regression.residualize(zUpside, [zBm]);
  // O composto com a seção da coorte, pela função do núcleo.
  final composite = TransversalScore.scores({
    for (var i = 0; i < obs.length; i++)
      i: TransversalSignals(
        potential: obs[i].upside,
        bookToMarket: obs[i].bookToMarket,
        earningsYield: obs[i].earningsYield,
      ),
  }, TransversalOrdering.composite);

  return PerCohort(
    cohort: cohort,
    n: obs.length,
    upsideCoef: joint?.coefficients[1],
    coefBookToMarket: joint?.coefficients[2],
    coefEarningsYield: joint?.coefficients[3],
    upsideT: joint?.tStats[1],
    r2: joint?.r2,
    upsideCoefGivenBm: givenBm?.coefficients[1],
    aloneCoef: alone?.coefficients[1],
    icIncremental: residual == null ? null : Regression.spearman(residual, ret),
    incrementalIcGivenBm: residualGivenBm == null
        ? null
        : Regression.spearman(residualGivenBm, ret),
    upsideIc: Regression.spearman(upsides, ret),
    icBookToMarket: Regression.spearman(bm, ret),
    icEarningsYield: Regression.spearman(ey, ret),
    compositeIc: Regression.spearman(
        [for (var i = 0; i < obs.length; i++) composite[i]!], ret),
  );
}

/// - [lag]: coortes vizinhas cujas janelas se sobrepõem — `h/12 − 1` em
///   coortes anuais, `h/3 − 1` nas trimestrais —, para o `t` de Newey-West
///   (item C1a) e para a correção da sobreposição (item C1c).
Map<String, dynamic> _horizon(
  List<dynamic> raw,
  String field, {
  int lag = 0,
  String upside = 'upside',
  String bookToMarket = 'bookToMarket',
  String earningsYield = 'earningsYield',
  List<String> require = const [],
  bool Function(Map<String, dynamic>)? filter,
}) {
  final obs = _load(raw, field,
      upside: upside,
      bookToMarket: bookToMarket,
      earningsYield: earningsYield,
      require: require,
      filter: filter);
  final byCohort = <String, List<Obs>>{};
  for (final o in obs) {
    (byCohort[o.cohort] ??= []).add(o);
  }
  final cohorts = byCohort.keys.toList()..sort();

  final rows = <PerCohort>[];
  for (final c in cohorts) {
    // Menos de 30 ativos numa seção transversal não sustenta três regressores
    // com postos: o erro-padrão fica maior que o coeficiente por construção.
    if (byCohort[c]!.length < 30) continue;
    rows.add(_runCohort(c, byCohort[c]!));
  }

  List<double> col(double? Function(PerCohort) f) =>
      [for (final l in rows) if (f(l) != null) f(l)!];

  ({double mean, double sd, double t, int n, int positive})? s(
    double? Function(PerCohort) f,
  ) =>
      Regression.summarize(col(f));

  Map<String, dynamic>? j(
    ({double mean, double sd, double t, int n, int positive})? v, [
    double? Function(PerCohort)? f,
  ]) {
    if (v == null) return null;
    // `linhas` está em ordem de coorte: é a ordem que a autocovariância exige.
    final series = f == null ? null : col(f);
    return {
      'media': v.mean,
      'desvio': v.sd,
      't': v.t,
      if (series != null) ..._tReadings(series, lag),
      'coortes': v.n,
      'positivas': v.positive,
    };
  }

  Map<String, dynamic>? js(double? Function(PerCohort) f) => j(s(f), f);

  return {
    'observacoes': obs.length,
    'coortesUsadas': rows.length,
    'porCoorte': [for (final l in rows) l.toJson()],
    'famaMacBeth': {
      'potencialConjunto': js((l) => l.upsideCoef),
      'potencialDadoBm': js((l) => l.upsideCoefGivenBm),
      'bookToMarketConjunto': js((l) => l.coefBookToMarket),
      'earningsYieldConjunto': js((l) => l.coefEarningsYield),
      'potencialSozinho': js((l) => l.aloneCoef),
      'icIncremental': js((l) => l.icIncremental),
      'icIncrementalDadoBm': js((l) => l.incrementalIcGivenBm),
      'icPotencial': js((l) => l.upsideIc),
      'icBookToMarket': js((l) => l.icBookToMarket),
      'icEarningsYield': js((l) => l.icEarningsYield),
      'icComposto': js((l) => l.compositeIc),
    },
  };
}

void _printHorizon(String title, Map<String, dynamic> h) {
  stdout.writeln('\n=== $title ===');
  stdout.writeln('${h['observacoes']} observações, '
      '${h['coortesUsadas']} coortes com n ≥ 30');

  final byCohort = h['porCoorte'] as List;
  stdout.writeln('\ncoorte    n   IC pot  IC P/B  IC L/P |  coef pot   t   IC increm');
  for (final c in byCohort) {
    final m = c as Map<String, dynamic>;
    String f(dynamic v, [int d = 3]) =>
        v == null ? '   —  ' : (v as num).toDouble().toStringAsFixed(d);
    stdout.writeln('  ${m['coorte']}  ${m['n'].toString().padLeft(3)}   '
        '${f(m['icPotencial'])}   ${f(m['icBookToMarket'])}   '
        '${f(m['icEarningsYield'])} |   ${f(m['coefPotencial'])}  '
        '${f(m['tPotencial'], 2).padLeft(6)}     ${f(m['icIncremental'])}');
  }

  final fmb = h['famaMacBeth'] as Map<String, dynamic>;
  void row(String label, String key) {
    final v = fmb[key] as Map<String, dynamic>?;
    if (v == null) {
      stdout.writeln('  ${label.padRight(34)} —');
      return;
    }
    final nw = v['tNeweyWest'] as double?;
    final overlapT = v['tSobreposicao'] as double?;
    final critical = v['criticoSobreposicao'] as double?;
    final p = v['pSobreposicao'] as double?;
    stdout.writeln('  ${label.padRight(34)} '
        'média=${(v['media'] as double).toStringAsFixed(3)}  '
        't=${(v['t'] as double).toStringAsFixed(2)}  '
        '${nw == null ? '' : 't_NW(${v['defasagem']})=${nw.toStringAsFixed(2)}  '}'
        '${overlapT == null || critical == null || p == null ? '' : 't_sob=${overlapT.toStringAsFixed(2)}/${critical.toStringAsFixed(2)} p=${p.toStringAsFixed(3)}  '}'
        'positivas=${v['positivas']}/${v['coortes']}');
  }

  stdout.writeln('\nsegundo passo de Fama-MacBeth:');
  row('IC do potencial (referência)', 'icPotencial');
  row('IC do P/B', 'icBookToMarket');
  row('IC do L/P', 'icEarningsYield');
  row('IC do COMPOSTO', 'icComposto');
  row('coef. do potencial sozinho', 'potencialSozinho');
  row('coef. do potencial DADO O P/B', 'potencialDadoBm');
  row('coef. do potencial COM P/B e L/P', 'potencialConjunto');
  row('coef. do P/B com os outros', 'bookToMarketConjunto');
  row('coef. do L/P com os outros', 'earningsYieldConjunto');
  row('IC INCREMENTAL do potencial', 'icIncremental');
  row('IC ORTOGONALIZADO ao P/B (B2)', 'icIncrementalDadoBm');
}

Future<void> main(List<String> args) async {
  if (args.contains('--aplicativo')) return _app();
  if (args.contains('--trimestral')) return _quarterly();
  if (args.contains('--custos')) return _costs();
  if (args.contains('--pacote-habilidade')) {
    return _skillPackage(jsonDecode(
            File('docs/validacao/habilidade_trimestral.json').readAsStringSync())
        as Map<String, dynamic>);
  }
  final file = File('docs/validacao/backtest_valuation.json');
  if (!file.existsSync()) {
    stderr.writeln('Falta docs/validacao/backtest_valuation.json. '
        'Rode antes: dart run tool/backtest_valuation.dart');
    exit(2);
  }

  final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  stderr.writeln('${raw.length} linhas lidas');

  final result = {
    'gerado': DateTime.now().toIso8601String(),
    'fonte': 'docs/validacao/backtest_valuation.json',
    'h36': _horizon(raw, 'ret36'),
    'h12': _horizon(raw, 'ret12'),
    // Leitura secundária, sobre a série ajustada. A §1.2 das limitações mede
    // desvio mediano de 9,1% entre o ajuste da fonte e o fluxo de proventos
    // publicado, e é por isso que ela não é a principal.
    'h36ajustado': _horizon(raw, 'ret36aj'),
  };

  // Retorno total, com os proventos da B3 reinvestidos na data ex (item A4,
  // decisão 89). Vem de `tool/proventos_conferir.dart`, que grava as mesmas
  // coortes com `ret12tot` e `ret36tot`.
  final withTotal = File('docs/validacao/backtest_valuation_total.json');
  if (withTotal.existsSync()) {
    final total = jsonDecode(withTotal.readAsStringSync()) as List<dynamic>;
    result['h36total'] = _horizon(total, 'ret36tot');
    result['h12total'] = _horizon(total, 'ret12tot');
  }

  File('docs/validacao/regressao_condicional.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(result),
  );

  _printHorizon('36 MESES', result['h36'] as Map<String, dynamic>);
  _printHorizon('12 MESES', result['h12'] as Map<String, dynamic>);
  _printHorizon(
    '36 MESES — série ajustada (secundária, ver §1.2 das limitações)',
    result['h36ajustado'] as Map<String, dynamic>,
  );
  if (result['h36total'] != null) {
    _printHorizon('36 MESES — retorno total, proventos da B3',
        result['h36total'] as Map<String, dynamic>);
    _printHorizon('12 MESES — retorno total, proventos da B3',
        result['h12total'] as Map<String, dynamic>);
  }

  stderr.writeln('\nescrito docs/validacao/regressao_condicional.json');
}

/// As leituras do `t` de uma série de coeficientes de coorte em ordem de data.
///
/// **O critério do R3 (decisão 96).** O `t` corrigido pela estrutura da
/// sobreposição, contra o crítico que a mesma estrutura dá ao nível de `t > 2`,
/// **e** o Newey-West acima de 2. O corrigido não estima nada da série; o
/// Newey-West pega a persistência que vá além da sobreposição.
Map<String, dynamic> _tReadings(List<double> series, int lag) {
  final nw = Regression.neweyWestMean(series, lag);
  final overlapT = Regression.overlapAdjustedT(series, lag);
  final critical =
      overlapT == null ? null : Regression.overlapCritical(overlapT.n, overlapT.overlap);
  return {
    if (nw != null) 'tNeweyWest': nw.t,
    if (nw != null) 'defasagem': nw.lags,
    if (overlapT != null) 'tSobreposicao': overlapT.t,
    'criticoSobreposicao': ?critical,
    if (overlapT != null)
      'pSobreposicao': Regression.overlapPValue(overlapT.t, overlapT.n, overlapT.overlap),
    if (overlapT != null && nw != null && critical != null)
      'passaR3': overlapT.t > critical && nw.t > 2,
  };
}

/// Média, entre coortes, de uma diferença entre duas leituras medidas nas mesmas
/// observações, com as mesmas leituras do `t`.
Map<String, dynamic>? _difference(List<double> series, int lag) {
  final v = Regression.summarize(series);
  if (v == null) return null;
  return {
    'media': v.mean,
    't': v.t,
    ..._tReadings(series, lag),
    'coortes': v.n,
    'positivas': v.positive,
  };
}

/// A série ancorada no trimestre contra a de DFPs, nas mesmas observações e com
/// o mesmo B/M da série anual como controle (item C1c).
///
/// Três perguntas: qual ordena mais sozinha (IC), qual ordena mais dado o B/M,
/// e se uma acrescenta à outra — o coeficiente da ancorada com a anual e o B/M
/// na mesma regressão, e o inverso.
Map<String, dynamic> _anchoredComparison(
    List<dynamic> raw, String field, int lag) {
  const require = ['upside', 'upsideAncorada', 'bookToMarket', 'earningsYield'];
  final annual = _horizon(raw, field, lag: lag, require: require);
  final anchored = _horizon(raw, field,
      lag: lag, upside: 'upsideAncorada', require: require);
  final anchoredWithOwnBm = _horizon(raw, field,
      lag: lag,
      upside: 'upsideAncorada',
      bookToMarket: 'bookToMarketAncorada',
      earningsYield: 'earningsYieldAncorada',
      require: require);

  // Por coorte: a diferença de IC e as regressões cruzadas.
  final byCohort = <String, List<Map<String, dynamic>>>{};
  for (final l in raw) {
    final m = l as Map<String, dynamic>;
    if ([...require, field].any((c) => _num(m[c]) == null)) continue;
    (byCohort['${m['coorte']}'] ??= []).add(m);
  }
  final diffIc = <double>[];
  final anchoredGivenAnnual = <double>[];
  final annualGivenAnchored = <double>[];
  var moved = 0, total = 0;
  for (final c in byCohort.keys.toList()..sort()) {
    final g = byCohort[c]!;
    if (g.length < 30) continue;
    List<double> col(String k) => [for (final m in g) _num(m[k])!];
    final ret = col(field);
    final a = col('upside');
    final q = col('upsideAncorada');
    total += g.length;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - q[i]).abs() > 1e-9) moved++;
    }
    final icQ = Regression.spearman(q, ret);
    final icA = Regression.spearman(a, ret);
    if (icQ != null && icA != null) diffIc.add(icQ - icA);
    final r = Regression.ols([
      Regression.standardizedRanks(q),
      Regression.standardizedRanks(a),
      Regression.standardizedRanks(col('bookToMarket')),
    ], Regression.standardizedRanks(ret));
    if (r != null) {
      anchoredGivenAnnual.add(r.coefficients[1]);
      annualGivenAnchored.add(r.coefficients[2]);
    }
  }
  Map<String, dynamic>? fm(Map<String, dynamic> h, String k) =>
      (h['famaMacBeth'] as Map<String, dynamic>)[k] as Map<String, dynamic>?;
  return {
    'observacoes': annual['observacoes'],
    'fracaoComPotencialDiferente': total == 0 ? null : moved / total,
    'icAnual': fm(annual, 'icPotencial'),
    'icAncorada': fm(anchored, 'icPotencial'),
    'diferencaDeIc': _difference(diffIc, lag),
    'anualDadoBm': fm(annual, 'potencialDadoBm'),
    'ancoradaDadoBm': fm(anchored, 'potencialDadoBm'),
    'ancoradaDadoSeuBm': fm(anchoredWithOwnBm, 'potencialDadoBm'),
    'ancoradaDadaAnualEBm': _difference(anchoredGivenAnnual, lag),
    'anualDadaAncoradaEBm': _difference(annualGivenAnchored, lag),
  };
}

/// Coortes trimestrais, com as deslistadas da ponte ampliada, na montagem na
/// base da data (itens C1c, C1d e C3).
///
/// Tudo sai da **mesma execução** de `dart run tool/backtest_valuation.dart
/// --montagem aplicativo --com-deslistadas --trimestral --contrafactual-base`.
/// **Não é o veredito do R3**: a medição da habilidade fica para o fim das
/// fases, a pedido do usuário em 15/09/2026. O que sai aqui é o instrumento
/// calibrado, e a leitura dele.
Future<void> _quarterly() async {
  const source = 'docs/validacao/backtest_trimestral.json';
  final file = File(source);
  if (!file.existsSync()) {
    stderr.writeln('Falta $source. Rode antes: dart run '
        'tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas '
        '--trimestral --contrafactual-base');
    exit(2);
  }
  final allRows = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  bool listedOnly(Map<String, dynamic> m) => m['deslistada'] != true;
  bool september(Map<String, dynamic> m) => '${m['coorte']}'.endsWith('-09-30');
  stderr.writeln('${allRows.length} linhas');

  Map<String, dynamic> reading(String field, int months) => {
        'trimestral': {
          'comDeslistadas': _horizon(allRows, field, lag: months ~/ 3 - 1),
          'semDeslistadas': _horizon(allRows, field,
              lag: months ~/ 3 - 1, filter: listedOnly),
        },
        'anualEm30deSetembro': {
          'comDeslistadas': _horizon(allRows, field,
              lag: months ~/ 12 - 1, filter: september),
          'semDeslistadas': _horizon(allRows, field,
              lag: months ~/ 12 - 1,
              filter: (m) => listedOnly(m) && september(m)),
        },
        'ancoradaContraAnual':
            _anchoredComparison(allRows, field, months ~/ 3 - 1),
      };

  // O contrafactual da base (item C3): as mesmas observações de 30/09 das
  // listadas, na montagem da rodada anterior e na da data.
  Map<String, dynamic> base(String field, int months) {
    const require = [
      'upside',
      'upsideBaseAntiga',
      'bookToMarket',
      'bookToMarketBaseAntiga',
    ];
    bool f(Map<String, dynamic> m) => listedOnly(m) && september(m);
    return {
      'naData': _horizon(allRows, field,
          lag: months ~/ 12 - 1, require: require, filter: f),
      'baseAntiga': _horizon(allRows, field,
          lag: months ~/ 12 - 1,
          upside: 'upsideBaseAntiga',
          bookToMarket: 'bookToMarketBaseAntiga',
          require: require,
          filter: f),
    };
  }

  final result = {
    'gerado': DateTime.now().toIso8601String(),
    'fonte': source,
    'retorno': 'total, com os proventos da B3 reinvestidos na data ex',
    'h36': reading('ret36tot', 36),
    'h12': reading('ret12tot', 12),
    'contrafactualDaBase': {
      'h36': base('ret36tot', 36),
      'h12': base('ret12tot', 12),
    },
  };
  File('docs/validacao/habilidade_trimestral.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(result),
  );
  for (final h in ['h36', 'h12']) {
    final r = result[h] as Map<String, dynamic>;
    for (final g in ['trimestral', 'anualEm30deSetembro']) {
      for (final a in ['comDeslistadas', 'semDeslistadas']) {
        _printHorizon('$h — $g — $a',
            (r[g] as Map<String, dynamic>)[a] as Map<String, dynamic>);
      }
    }
    stdout.writeln('\n=== $h — ancorada contra anual ===');
    stdout.writeln(
        const JsonEncoder.withIndent(' ').convert(r['ancoradaContraAnual']));
  }
  final counter = result['contrafactualDaBase'] as Map<String, dynamic>;
  for (final h in ['h36', 'h12']) {
    final b = counter[h] as Map<String, dynamic>;
    _printHorizon(
        '$h — base da data', b['naData'] as Map<String, dynamic>);
    _printHorizon(
        '$h — base antiga', b['baseAntiga'] as Map<String, dynamic>);
  }
  stderr.writeln('\nescrito docs/validacao/habilidade_trimestral.json');
  _skillPackage(result);
}

/// Caminho do pacote da habilidade que o aplicativo lê (item B1.0).
const _skillPackageFile = 'assets/validacao/habilidade.json';

/// Grava a leitura que a tela de metas mostra: 36 meses, coortes trimestrais,
/// com as deslistadas — a amostra do R3 (decisões 93 e 96).
///
/// O pacote leva os números, e não o veredito: o critério da decisão 96 e a
/// regra que escolhe a ordenação do prêmio (item B1, `ordenacao_lado_a_lado.md`
/// §1) moram em `SkillReading`, e o teste do pacote confere que eles concordam
/// com o `passaR3` desta medição.
void _skillPackage(Map<String, dynamic> result) {
  Map<String, dynamic> m(Object? v) => v as Map<String, dynamic>;
  final sample = m(m(m(result['h36'])['trimestral'])['comDeslistadas']);
  final fm = m(sample['famaMacBeth']);
  final datum = m(fm['potencialDadoBm']);
  Map<String, Object?> reading(String key) {
    final l = m(fm[key]);
    return {
      'ic': l['media'],
      'tCorrigido': l['tSobreposicao'],
      'critico': l['criticoSobreposicao'],
      'tNeweyWest': l['tNeweyWest'],
    };
  }

  final package = {
    'versao': SkillReadingCodec.version,
    'fonte': 'docs/validacao/habilidade_trimestral.json',
    'medidoEm': '${result['gerado']}'.substring(0, 10),
    'horizonteMeses': 36,
    'coortes': datum['coortes'],
    'observacoes': sample['observacoes'],
    'potencialDadoBookToMarket': {
      'coeficiente': datum['media'],
      'tCorrigido': datum['tSobreposicao'],
      'critico': datum['criticoSobreposicao'],
      'tNeweyWest': datum['tNeweyWest'],
    },
    'ordenacoes': {
      SkillReadingCodec.key(TransversalOrdering.composite):
          reading('icComposto'),
      SkillReadingCodec.key(TransversalOrdering.bookToMarket):
          reading('icBookToMarket'),
      SkillReadingCodec.key(TransversalOrdering.potential):
          reading('icPotencial'),
    },
  };
  final readOrdering = SkillReadingCodec.decode(package);
  if (readOrdering == null) {
    stderr.writeln('A leitura da habilidade saiu malformada; o pacote não foi '
        'gravado.');
    exit(1);
  }
  File(_skillPackageFile).writeAsStringSync(jsonEncode(package));
  final premium = readOrdering.premiumOrdering;
  stderr.writeln('escrito $_skillPackageFile — potencial dado o B/M '
      '${readOrdering.demonstrated ? 'comprovado' : 'não comprovado'}; prêmio do '
      'retorno esperado: ${premium == null ? 'nenhum, nenhuma ordenação passou' : premium.label}');
}

/// A habilidade sobre a montagem do aplicativo por data, com e sem as
/// deslistadas, no retorno total (itens C1a e C1b).
///
/// As duas amostras saem da **mesma execução** de
/// `dart run tool/backtest_valuation.dart --montagem aplicativo
/// --com-deslistadas`: comparar com uma execução anterior misturaria o efeito
/// das deslistadas com a deriva do dado de mercado.
Future<void> _app() async {
  const source = 'docs/validacao/backtest_aplicativo_deslistadas.json';
  final file = File(source);
  if (!file.existsSync()) {
    stderr.writeln('Falta $source. Rode antes: dart run tool/backtest_valuation.dart '
        '--montagem aplicativo --com-deslistadas');
    exit(2);
  }
  final allRows = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  final listed = [
    for (final l in allRows)
      if ((l as Map<String, dynamic>)['deslistada'] != true) l,
  ];
  stderr.writeln('${allRows.length} linhas, ${listed.length} de listadas');

  final result = {
    'gerado': DateTime.now().toIso8601String(),
    'fonte': source,
    'retorno': 'total, com os proventos da B3 reinvestidos na data ex',
    'h36': {
      'semDeslistadas': _horizon(listed, 'ret36tot', lag: 2),
      'comDeslistadas': _horizon(allRows, 'ret36tot', lag: 2),
    },
    'h12': {
      'semDeslistadas': _horizon(listed, 'ret12tot'),
      'comDeslistadas': _horizon(allRows, 'ret12tot'),
    },
  };
  File('docs/validacao/habilidade_aplicativo.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(result),
  );
  for (final h in ['h36', 'h12']) {
    for (final a in ['semDeslistadas', 'comDeslistadas']) {
      _printHorizon('${h == 'h36' ? '36' : '12'} MESES — $a',
          (result[h] as Map<String, dynamic>)[a] as Map<String, dynamic>);
    }
  }
  stderr.writeln('\nescrito docs/validacao/habilidade_aplicativo.json');
}

/// A habilidade sobre o retorno **líquido** de custo de transação (item C4).
///
/// O custo de ida e volta de cada observação sai de `tool/custos_spread.py`:
/// tarifa da B3 nas duas pontas e meio spread de Abdi e Ranaldo em cada uma.
/// O retorno líquido é `(1 + r)·fator − 1`, e o resto é a mesma medição de
/// `--trimestral` — coortes trimestrais com as deslistadas, 36 e 12 meses,
/// critério da decisão 96.
///
/// **Custo uniforme não mexe no IC**, e isto não é descoberta: somar a mesma
/// constante a todos os retornos de uma coorte preserva a ordem. O que o custo
/// pode mudar é a ordem **quando ele varia com a liquidez** — e varia, de
/// 0,4% a 1,7% de spread entre os tercis. Por isso a medição importa.
Future<void> _costs() async {
  const source = 'docs/validacao/backtest_trimestral.json';
  const costs = 'docs/validacao/custos_spread.json';
  for (final f in [source, costs]) {
    if (!File(f).existsSync()) {
      stderr.writeln('Falta $f. Rode antes: dart run tool/backtest_valuation.dart '
          '--montagem aplicativo --com-deslistadas --trimestral, '
          'python tool/b3_baixar.py --extremos --de 2017 e '
          'python tool/custos_spread.py');
      exit(2);
    }
  }
  final allRows = jsonDecode(File(source).readAsStringSync()) as List<dynamic>;
  final byObs = ((jsonDecode(File(costs).readAsStringSync())
          as Map<String, dynamic>)['porObservacao'] as Map<String, dynamic>)
      .cast<String, Map<String, dynamic>>();
  var withoutCost = 0;
  for (final l in allRows) {
    final m = l as Map<String, dynamic>;
    final c = byObs['${m['coorte']}|${m['ticker']}'];
    if (c == null) {
      withoutCost++;
      continue;
    }
    for (final h in ['12', '36']) {
      final r = _num(m['ret${h}tot']);
      final f = _num(c['fator$h']);
      if (r != null && f != null) m['ret${h}totLiq'] = (1 + r) * f - 1;
    }
  }

  /// Custo de ida e volta de cada observação, `1 − fator`, por horizonte.
  double? costOf(Obs o, String h) {
    final f = _num(byObs['${o.cohort}|${o.ticker}']?['fator$h']);
    return f == null ? null : 1 - f;
  }

  /// Quintil de cima menos o de baixo, por coorte, em média igual.
  ///
  /// Com [cost], acrescenta a carteira **comprada e vendida**: a diferença
  /// entre os líquidos já desconta o custo da ponta comprada, mas trata a
  /// vendida como se o custo dela a favorecesse. Vender a descoberto e zerar
  /// também paga spread e tarifa — o custo da perna vendida entra duas vezes,
  /// uma para desfazer o sinal errado e outra para cobrá-lo.
  Map<String, dynamic> quintiles(List<Obs> obs, double Function(Obs) key,
      {double? Function(Obs)? cost}) {
    final byCohort = <String, List<Obs>>{};
    for (final o in obs) {
      (byCohort[o.cohort] ??= []).add(o);
    }
    final diffs = <double>[];
    final longShort = <double>[];
    for (final g in byCohort.values) {
      if (g.length < 30) continue;
      final s = [...g]..sort((a, b) => key(a).compareTo(key(b)));
      final q = s.length ~/ 5;
      double mean(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
      final top = s.skip(s.length - q), background = s.take(q);
      final d = mean(top.map((o) => o.returnRate)) -
          mean(background.map((o) => o.returnRate));
      diffs.add(d);
      if (cost != null) {
        final c = [for (final o in background) cost(o) ?? 0.0];
        longShort.add(d - 2 * mean(c));
      }
    }
    final v = Regression.summarize(diffs);
    final cv = Regression.summarize(longShort);
    return {
      'media': v?.mean,
      't': v?.t,
      'coortes': diffs.length,
      if (cv != null) 'compradoVendido': {'media': cv.mean, 't': cv.t},
    };
  }

  Map<String, dynamic> pair(String raw, String net, int months) {
    final h = '$months';
    final lag = months ~/ 3 - 1;
    // As mesmas observações nas duas leituras: a bruta só entra onde a líquida
    // existe.
    final require = [raw, net];
    Map<String, dynamic> reading(String field, {required bool withCost}) {
      final r = _horizon(allRows, field, lag: lag, require: require);
      final obs = _load(allRows, field, require: require);
      final returns = [for (final o in obs) o.returnRate]..sort();
      final costs = [
        for (final o in obs) ?costOf(o, h),
      ]..sort();
      double? cost(Obs o) => withCost ? costOf(o, h) : null;
      return {
        ...r,
        'retornoMediano':
            returns.isEmpty ? null : returns[returns.length ~/ 2],
        if (withCost)
          'custoIdaEVoltaMediano':
              costs.isEmpty ? null : costs[costs.length ~/ 2],
        'quintilPotencial': quintiles(obs, (o) => o.upside,
            cost: withCost ? cost : null),
        'quintilBookToMarket': quintiles(obs, (o) => o.bookToMarket,
            cost: withCost ? cost : null),
      };
    }

    return {
      'bruto': reading(raw, withCost: false),
      'liquido': reading(net, withCost: true),
    };
  }

  final result = {
    'gerado': DateTime.now().toIso8601String(),
    'fonte': source,
    'custos': costs,
    'observacoesSemCusto': withoutCost,
    'h36': pair('ret36tot', 'ret36totLiq', 36),
    'h12': pair('ret12tot', 'ret12totLiq', 12),
  };
  File('docs/validacao/custos_transacao.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(result),
  );

  for (final h in ['h36', 'h12']) {
    final r = result[h] as Map<String, dynamic>;
    stdout.writeln('\n=== $h: bruto contra líquido ===');
    for (final k in ['bruto', 'liquido']) {
      final l = r[k] as Map<String, dynamic>;
      final fm = l['famaMacBeth'] as Map<String, dynamic>;
      String ic(String key) {
        final v = fm[key] as Map<String, dynamic>?;
        if (v == null) return '—';
        final overlapT = v['tSobreposicao'] as double?;
        final nw = v['tNeweyWest'] as double?;
        return '${(v['media'] as double).toStringAsFixed(3)} '
            '(t_sob ${overlapT?.toStringAsFixed(2) ?? '—'}, '
            'NW ${nw?.toStringAsFixed(2) ?? '—'}, '
            '${v['passaR3'] == true ? 'PASSA' : 'não passa'})';
      }

      final qp = l['quintilPotencial'] as Map<String, dynamic>;
      final qb = l['quintilBookToMarket'] as Map<String, dynamic>;
      String pct(Object? v) =>
          v == null ? '—' : '${((v as double) * 100).toStringAsFixed(2)}%';
      stdout.writeln('  $k  n=${l['observacoes']}  '
          'retorno mediano ${pct(l['retornoMediano'])}');
      stdout.writeln('    potencial dado o B/M  ${ic('potencialDadoBm')}');
      stdout.writeln('    IC do potencial       ${ic('icPotencial')}');
      stdout.writeln('    IC do B/M             ${ic('icBookToMarket')}');
      stdout.writeln('    IC do L/P             ${ic('icEarningsYield')}');
      stdout.writeln('    IC do composto        ${ic('icComposto')}');
      String cv(Map<String, dynamic> q) {
        final c = q['compradoVendido'] as Map<String, dynamic>?;
        return c == null ? '' : ' (comprado-vendido ${pct(c['media'])})';
      }

      stdout.writeln('    Q5−Q1 potencial ${pct(qp['media'])}${cv(qp)}  '
          'Q5−Q1 B/M ${pct(qb['media'])}${cv(qb)}');
      if (l['custoIdaEVoltaMediano'] != null) {
        stdout.writeln('    custo de ida e volta mediano '
            '${pct(l['custoIdaEVoltaMediano'])}');
      }
    }
  }
  stderr.writeln('\nescrito docs/validacao/custos_transacao.json');
}
