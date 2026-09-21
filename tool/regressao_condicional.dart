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

/// Uma observação utilizável: os três ordenadores e o retorno, todos presentes.
class Obs {
  /// A data da coorte, ou o ano nas saídas anuais antigas: em ordem de texto é
  /// a ordem de data nos dois formatos.
  final String coorte;
  final String ticker;
  final double potencial;
  final double bookToMarket;
  final double earningsYield;
  final double retorno;

  const Obs({
    required this.coorte,
    required this.ticker,
    required this.potencial,
    required this.bookToMarket,
    required this.earningsYield,
    required this.retorno,
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
/// - [potencial], [bookToMarket], [earningsYield]: os campos lidos — os da série
///   de DFPs por padrão; os `…Ancorada` e `…BaseAntiga` nas comparações.
/// - [exigir]: campos que têm de estar presentes, para que duas leituras sejam
///   medidas sobre as mesmas observações.
List<Obs> _carregar(
  List<dynamic> bruto,
  String campoRetorno, {
  String potencial = 'upside',
  String bookToMarket = 'bookToMarket',
  String earningsYield = 'earningsYield',
  List<String> exigir = const [],
  bool Function(Map<String, dynamic>)? filtro,
}) {
  final out = <Obs>[];
  for (final linha in bruto) {
    final m = linha as Map<String, dynamic>;
    if (filtro != null && !filtro(m)) continue;
    if (exigir.any((c) => _num(m[c]) == null)) continue;
    final pot = _num(m[potencial]);
    final bm = _num(m[bookToMarket]);
    final ey = _num(m[earningsYield]);
    final ret = _num(m[campoRetorno]);
    if (pot == null || bm == null || ey == null || ret == null) continue;
    out.add(Obs(
      coorte: '${m['coorte']}',
      ticker: m['ticker'] as String,
      potencial: pot,
      bookToMarket: bm,
      earningsYield: ey,
      retorno: ret,
    ));
  }
  return out;
}

/// O que uma coorte devolve.
class PorCoorte {
  final String coorte;
  final int n;

  /// Coeficientes da regressão conjunta, em postos padronizados.
  final double? coefPotencial;
  final double? coefBookToMarket;
  final double? coefEarningsYield;
  final double? tPotencial;
  final double? r2;

  /// Coeficiente do potencial condicionado **só** ao P/B — o critério do R3.
  final double? coefPotencialDadoBm;

  /// Coeficiente da regressão só com o potencial — equivalente ao IC.
  final double? coefSozinho;

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
  final double? icIncrementalDadoBm;

  /// IC simples de cada ordenador, para conferir contra o relatório anterior.
  final double? icPotencial;
  final double? icBookToMarket;
  final double? icEarningsYield;

  /// IC do composto — a média dos escores robustos dos três sinais, pela mesma
  /// função que o aplicativo usa (item B1, `ordenacao_lado_a_lado.md` §1).
  final double? icComposto;

  const PorCoorte({
    required this.coorte,
    required this.n,
    required this.coefPotencial,
    required this.coefBookToMarket,
    required this.coefEarningsYield,
    required this.tPotencial,
    required this.r2,
    required this.coefPotencialDadoBm,
    required this.coefSozinho,
    required this.icIncremental,
    required this.icIncrementalDadoBm,
    required this.icPotencial,
    required this.icBookToMarket,
    required this.icEarningsYield,
    required this.icComposto,
  });

  Map<String, dynamic> toJson() => {
        'coorte': coorte,
        'n': n,
        'coefPotencial': coefPotencial,
        'coefBookToMarket': coefBookToMarket,
        'coefEarningsYield': coefEarningsYield,
        'tPotencial': tPotencial,
        'r2': r2,
        'coefPotencialDadoBm': coefPotencialDadoBm,
        'coefSozinho': coefSozinho,
        'icIncremental': icIncremental,
        'icIncrementalDadoBm': icIncrementalDadoBm,
        'icPotencial': icPotencial,
        'icBookToMarket': icBookToMarket,
        'icEarningsYield': icEarningsYield,
        'icComposto': icComposto,
      };
}

PorCoorte _rodarCoorte(String coorte, List<Obs> obs) {
  final pot = [for (final o in obs) o.potencial];
  final bm = [for (final o in obs) o.bookToMarket];
  final ey = [for (final o in obs) o.earningsYield];
  final ret = [for (final o in obs) o.retorno];

  final zPot = Regression.standardizedRanks(pot);
  final zBm = Regression.standardizedRanks(bm);
  final zEy = Regression.standardizedRanks(ey);
  final zRet = Regression.standardizedRanks(ret);

  final conjunta = Regression.ols([zPot, zBm, zEy], zRet);
  final dadoBm = Regression.ols([zPot, zBm], zRet);
  final sozinho = Regression.ols([zPot], zRet);
  final residuo = Regression.residualize(zPot, [zBm, zEy]);
  final residuoDadoBm = Regression.residualize(zPot, [zBm]);
  // O composto com a seção da coorte, pela função do núcleo.
  final composto = TransversalScore.scores({
    for (var i = 0; i < obs.length; i++)
      i: TransversalSignals(
        potential: obs[i].potencial,
        bookToMarket: obs[i].bookToMarket,
        earningsYield: obs[i].earningsYield,
      ),
  }, TransversalOrdering.composite);

  return PorCoorte(
    coorte: coorte,
    n: obs.length,
    coefPotencial: conjunta?.coefficients[1],
    coefBookToMarket: conjunta?.coefficients[2],
    coefEarningsYield: conjunta?.coefficients[3],
    tPotencial: conjunta?.tStats[1],
    r2: conjunta?.r2,
    coefPotencialDadoBm: dadoBm?.coefficients[1],
    coefSozinho: sozinho?.coefficients[1],
    icIncremental: residuo == null ? null : Regression.spearman(residuo, ret),
    icIncrementalDadoBm: residuoDadoBm == null
        ? null
        : Regression.spearman(residuoDadoBm, ret),
    icPotencial: Regression.spearman(pot, ret),
    icBookToMarket: Regression.spearman(bm, ret),
    icEarningsYield: Regression.spearman(ey, ret),
    icComposto: Regression.spearman(
        [for (var i = 0; i < obs.length; i++) composto[i]!], ret),
  );
}

/// - [defasagem]: coortes vizinhas cujas janelas se sobrepõem — `h/12 − 1` em
///   coortes anuais, `h/3 − 1` nas trimestrais —, para o `t` de Newey-West
///   (item C1a) e para a correção da sobreposição (item C1c).
Map<String, dynamic> _horizonte(
  List<dynamic> bruto,
  String campo, {
  int defasagem = 0,
  String potencial = 'upside',
  String bookToMarket = 'bookToMarket',
  String earningsYield = 'earningsYield',
  List<String> exigir = const [],
  bool Function(Map<String, dynamic>)? filtro,
}) {
  final obs = _carregar(bruto, campo,
      potencial: potencial,
      bookToMarket: bookToMarket,
      earningsYield: earningsYield,
      exigir: exigir,
      filtro: filtro);
  final porCoorte = <String, List<Obs>>{};
  for (final o in obs) {
    (porCoorte[o.coorte] ??= []).add(o);
  }
  final coortes = porCoorte.keys.toList()..sort();

  final linhas = <PorCoorte>[];
  for (final c in coortes) {
    // Menos de 30 ativos numa seção transversal não sustenta três regressores
    // com postos: o erro-padrão fica maior que o coeficiente por construção.
    if (porCoorte[c]!.length < 30) continue;
    linhas.add(_rodarCoorte(c, porCoorte[c]!));
  }

  List<double> col(double? Function(PorCoorte) f) =>
      [for (final l in linhas) if (f(l) != null) f(l)!];

  ({double mean, double sd, double t, int n, int positive})? s(
    double? Function(PorCoorte) f,
  ) =>
      Regression.summarize(col(f));

  Map<String, dynamic>? j(
    ({double mean, double sd, double t, int n, int positive})? v, [
    double? Function(PorCoorte)? f,
  ]) {
    if (v == null) return null;
    // `linhas` está em ordem de coorte: é a ordem que a autocovariância exige.
    final serie = f == null ? null : col(f);
    return {
      'media': v.mean,
      'desvio': v.sd,
      't': v.t,
      if (serie != null) ..._leiturasDoT(serie, defasagem),
      'coortes': v.n,
      'positivas': v.positive,
    };
  }

  Map<String, dynamic>? js(double? Function(PorCoorte) f) => j(s(f), f);

  return {
    'observacoes': obs.length,
    'coortesUsadas': linhas.length,
    'porCoorte': [for (final l in linhas) l.toJson()],
    'famaMacBeth': {
      'potencialConjunto': js((l) => l.coefPotencial),
      'potencialDadoBm': js((l) => l.coefPotencialDadoBm),
      'bookToMarketConjunto': js((l) => l.coefBookToMarket),
      'earningsYieldConjunto': js((l) => l.coefEarningsYield),
      'potencialSozinho': js((l) => l.coefSozinho),
      'icIncremental': js((l) => l.icIncremental),
      'icIncrementalDadoBm': js((l) => l.icIncrementalDadoBm),
      'icPotencial': js((l) => l.icPotencial),
      'icBookToMarket': js((l) => l.icBookToMarket),
      'icEarningsYield': js((l) => l.icEarningsYield),
      'icComposto': js((l) => l.icComposto),
    },
  };
}

void _imprimirHorizonte(String titulo, Map<String, dynamic> h) {
  stdout.writeln('\n=== $titulo ===');
  stdout.writeln('${h['observacoes']} observações, '
      '${h['coortesUsadas']} coortes com n ≥ 30');

  final porCoorte = h['porCoorte'] as List;
  stdout.writeln('\ncoorte    n   IC pot  IC P/B  IC L/P |  coef pot   t   IC increm');
  for (final c in porCoorte) {
    final m = c as Map<String, dynamic>;
    String f(dynamic v, [int d = 3]) =>
        v == null ? '   —  ' : (v as num).toDouble().toStringAsFixed(d);
    stdout.writeln('  ${m['coorte']}  ${m['n'].toString().padLeft(3)}   '
        '${f(m['icPotencial'])}   ${f(m['icBookToMarket'])}   '
        '${f(m['icEarningsYield'])} |   ${f(m['coefPotencial'])}  '
        '${f(m['tPotencial'], 2).padLeft(6)}     ${f(m['icIncremental'])}');
  }

  final fmb = h['famaMacBeth'] as Map<String, dynamic>;
  void linha(String rotulo, String chave) {
    final v = fmb[chave] as Map<String, dynamic>?;
    if (v == null) {
      stdout.writeln('  ${rotulo.padRight(34)} —');
      return;
    }
    final nw = v['tNeweyWest'] as double?;
    final sob = v['tSobreposicao'] as double?;
    final critico = v['criticoSobreposicao'] as double?;
    final p = v['pSobreposicao'] as double?;
    stdout.writeln('  ${rotulo.padRight(34)} '
        'média=${(v['media'] as double).toStringAsFixed(3)}  '
        't=${(v['t'] as double).toStringAsFixed(2)}  '
        '${nw == null ? '' : 't_NW(${v['defasagem']})=${nw.toStringAsFixed(2)}  '}'
        '${sob == null || critico == null || p == null ? '' : 't_sob=${sob.toStringAsFixed(2)}/${critico.toStringAsFixed(2)} p=${p.toStringAsFixed(3)}  '}'
        'positivas=${v['positivas']}/${v['coortes']}');
  }

  stdout.writeln('\nsegundo passo de Fama-MacBeth:');
  linha('IC do potencial (referência)', 'icPotencial');
  linha('IC do P/B', 'icBookToMarket');
  linha('IC do L/P', 'icEarningsYield');
  linha('IC do COMPOSTO', 'icComposto');
  linha('coef. do potencial sozinho', 'potencialSozinho');
  linha('coef. do potencial DADO O P/B', 'potencialDadoBm');
  linha('coef. do potencial COM P/B e L/P', 'potencialConjunto');
  linha('coef. do P/B com os outros', 'bookToMarketConjunto');
  linha('coef. do L/P com os outros', 'earningsYieldConjunto');
  linha('IC INCREMENTAL do potencial', 'icIncremental');
  linha('IC ORTOGONALIZADO ao P/B (B2)', 'icIncrementalDadoBm');
}

Future<void> main(List<String> args) async {
  if (args.contains('--aplicativo')) return _aplicativo();
  if (args.contains('--trimestral')) return _trimestral();
  if (args.contains('--pacote-habilidade')) {
    return _pacoteDaHabilidade(jsonDecode(
            File('docs/validacao/habilidade_trimestral.json').readAsStringSync())
        as Map<String, dynamic>);
  }
  final arquivo = File('docs/validacao/backtest_valuation.json');
  if (!arquivo.existsSync()) {
    stderr.writeln('Falta docs/validacao/backtest_valuation.json. '
        'Rode antes: dart run tool/backtest_valuation.dart');
    exit(2);
  }

  final bruto = jsonDecode(arquivo.readAsStringSync()) as List<dynamic>;
  stderr.writeln('${bruto.length} linhas lidas');

  final resultado = {
    'gerado': DateTime.now().toIso8601String(),
    'fonte': 'docs/validacao/backtest_valuation.json',
    'h36': _horizonte(bruto, 'ret36'),
    'h12': _horizonte(bruto, 'ret12'),
    // Leitura secundária, sobre a série ajustada. A §1.2 das limitações mede
    // desvio mediano de 9,1% entre o ajuste da fonte e o fluxo de proventos
    // publicado, e é por isso que ela não é a principal.
    'h36ajustado': _horizonte(bruto, 'ret36aj'),
  };

  // Retorno total, com os proventos da B3 reinvestidos na data ex (item A4,
  // decisão 89). Vem de `tool/proventos_conferir.dart`, que grava as mesmas
  // coortes com `ret12tot` e `ret36tot`.
  final comTotal = File('docs/validacao/backtest_valuation_total.json');
  if (comTotal.existsSync()) {
    final total = jsonDecode(comTotal.readAsStringSync()) as List<dynamic>;
    resultado['h36total'] = _horizonte(total, 'ret36tot');
    resultado['h12total'] = _horizonte(total, 'ret12tot');
  }

  File('docs/validacao/regressao_condicional.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(resultado),
  );

  _imprimirHorizonte('36 MESES', resultado['h36'] as Map<String, dynamic>);
  _imprimirHorizonte('12 MESES', resultado['h12'] as Map<String, dynamic>);
  _imprimirHorizonte(
    '36 MESES — série ajustada (secundária, ver §1.2 das limitações)',
    resultado['h36ajustado'] as Map<String, dynamic>,
  );
  if (resultado['h36total'] != null) {
    _imprimirHorizonte('36 MESES — retorno total, proventos da B3',
        resultado['h36total'] as Map<String, dynamic>);
    _imprimirHorizonte('12 MESES — retorno total, proventos da B3',
        resultado['h12total'] as Map<String, dynamic>);
  }

  stderr.writeln('\nescrito docs/validacao/regressao_condicional.json');
}

/// As leituras do `t` de uma série de coeficientes de coorte em ordem de data.
///
/// **O critério do R3 (decisão 96).** O `t` corrigido pela estrutura da
/// sobreposição, contra o crítico que a mesma estrutura dá ao nível de `t > 2`,
/// **e** o Newey-West acima de 2. O corrigido não estima nada da série; o
/// Newey-West pega a persistência que vá além da sobreposição.
Map<String, dynamic> _leiturasDoT(List<double> serie, int defasagem) {
  final nw = Regression.neweyWestMean(serie, defasagem);
  final sob = Regression.overlapAdjustedT(serie, defasagem);
  final critico =
      sob == null ? null : Regression.overlapCritical(sob.n, sob.overlap);
  return {
    if (nw != null) 'tNeweyWest': nw.t,
    if (nw != null) 'defasagem': nw.lags,
    if (sob != null) 'tSobreposicao': sob.t,
    'criticoSobreposicao': ?critico,
    if (sob != null)
      'pSobreposicao': Regression.overlapPValue(sob.t, sob.n, sob.overlap),
    if (sob != null && nw != null && critico != null)
      'passaR3': sob.t > critico && nw.t > 2,
  };
}

/// Média, entre coortes, de uma diferença entre duas leituras medidas nas mesmas
/// observações, com as mesmas leituras do `t`.
Map<String, dynamic>? _diferenca(List<double> serie, int defasagem) {
  final v = Regression.summarize(serie);
  if (v == null) return null;
  return {
    'media': v.mean,
    't': v.t,
    ..._leiturasDoT(serie, defasagem),
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
Map<String, dynamic> _comparacaoAncorada(
    List<dynamic> bruto, String campo, int defasagem) {
  const exigir = ['upside', 'upsideAncorada', 'bookToMarket', 'earningsYield'];
  final anual = _horizonte(bruto, campo, defasagem: defasagem, exigir: exigir);
  final ancorada = _horizonte(bruto, campo,
      defasagem: defasagem, potencial: 'upsideAncorada', exigir: exigir);
  final ancoradaComSeuBm = _horizonte(bruto, campo,
      defasagem: defasagem,
      potencial: 'upsideAncorada',
      bookToMarket: 'bookToMarketAncorada',
      earningsYield: 'earningsYieldAncorada',
      exigir: exigir);

  // Por coorte: a diferença de IC e as regressões cruzadas.
  final porCoorte = <String, List<Map<String, dynamic>>>{};
  for (final l in bruto) {
    final m = l as Map<String, dynamic>;
    if ([...exigir, campo].any((c) => _num(m[c]) == null)) continue;
    (porCoorte['${m['coorte']}'] ??= []).add(m);
  }
  final difIc = <double>[];
  final ancoradaDadaAnual = <double>[];
  final anualDadaAncorada = <double>[];
  var movidas = 0, total = 0;
  for (final c in porCoorte.keys.toList()..sort()) {
    final g = porCoorte[c]!;
    if (g.length < 30) continue;
    List<double> col(String k) => [for (final m in g) _num(m[k])!];
    final ret = col(campo);
    final a = col('upside');
    final q = col('upsideAncorada');
    total += g.length;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - q[i]).abs() > 1e-9) movidas++;
    }
    final icQ = Regression.spearman(q, ret);
    final icA = Regression.spearman(a, ret);
    if (icQ != null && icA != null) difIc.add(icQ - icA);
    final r = Regression.ols([
      Regression.standardizedRanks(q),
      Regression.standardizedRanks(a),
      Regression.standardizedRanks(col('bookToMarket')),
    ], Regression.standardizedRanks(ret));
    if (r != null) {
      ancoradaDadaAnual.add(r.coefficients[1]);
      anualDadaAncorada.add(r.coefficients[2]);
    }
  }
  Map<String, dynamic>? fm(Map<String, dynamic> h, String k) =>
      (h['famaMacBeth'] as Map<String, dynamic>)[k] as Map<String, dynamic>?;
  return {
    'observacoes': anual['observacoes'],
    'fracaoComPotencialDiferente': total == 0 ? null : movidas / total,
    'icAnual': fm(anual, 'icPotencial'),
    'icAncorada': fm(ancorada, 'icPotencial'),
    'diferencaDeIc': _diferenca(difIc, defasagem),
    'anualDadoBm': fm(anual, 'potencialDadoBm'),
    'ancoradaDadoBm': fm(ancorada, 'potencialDadoBm'),
    'ancoradaDadoSeuBm': fm(ancoradaComSeuBm, 'potencialDadoBm'),
    'ancoradaDadaAnualEBm': _diferenca(ancoradaDadaAnual, defasagem),
    'anualDadaAncoradaEBm': _diferenca(anualDadaAncorada, defasagem),
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
Future<void> _trimestral() async {
  const fonte = 'docs/validacao/backtest_trimestral.json';
  final arquivo = File(fonte);
  if (!arquivo.existsSync()) {
    stderr.writeln('Falta $fonte. Rode antes: dart run '
        'tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas '
        '--trimestral --contrafactual-base');
    exit(2);
  }
  final todas = jsonDecode(arquivo.readAsStringSync()) as List<dynamic>;
  bool listada(Map<String, dynamic> m) => m['deslistada'] != true;
  bool setembro(Map<String, dynamic> m) => '${m['coorte']}'.endsWith('-09-30');
  stderr.writeln('${todas.length} linhas');

  Map<String, dynamic> leitura(String campo, int meses) => {
        'trimestral': {
          'comDeslistadas': _horizonte(todas, campo, defasagem: meses ~/ 3 - 1),
          'semDeslistadas': _horizonte(todas, campo,
              defasagem: meses ~/ 3 - 1, filtro: listada),
        },
        'anualEm30deSetembro': {
          'comDeslistadas': _horizonte(todas, campo,
              defasagem: meses ~/ 12 - 1, filtro: setembro),
          'semDeslistadas': _horizonte(todas, campo,
              defasagem: meses ~/ 12 - 1,
              filtro: (m) => listada(m) && setembro(m)),
        },
        'ancoradaContraAnual':
            _comparacaoAncorada(todas, campo, meses ~/ 3 - 1),
      };

  // O contrafactual da base (item C3): as mesmas observações de 30/09 das
  // listadas, na montagem da rodada anterior e na da data.
  Map<String, dynamic> base(String campo, int meses) {
    const exigir = [
      'upside',
      'upsideBaseAntiga',
      'bookToMarket',
      'bookToMarketBaseAntiga',
    ];
    bool f(Map<String, dynamic> m) => listada(m) && setembro(m);
    return {
      'naData': _horizonte(todas, campo,
          defasagem: meses ~/ 12 - 1, exigir: exigir, filtro: f),
      'baseAntiga': _horizonte(todas, campo,
          defasagem: meses ~/ 12 - 1,
          potencial: 'upsideBaseAntiga',
          bookToMarket: 'bookToMarketBaseAntiga',
          exigir: exigir,
          filtro: f),
    };
  }

  final resultado = {
    'gerado': DateTime.now().toIso8601String(),
    'fonte': fonte,
    'retorno': 'total, com os proventos da B3 reinvestidos na data ex',
    'h36': leitura('ret36tot', 36),
    'h12': leitura('ret12tot', 12),
    'contrafactualDaBase': {
      'h36': base('ret36tot', 36),
      'h12': base('ret12tot', 12),
    },
  };
  File('docs/validacao/habilidade_trimestral.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(resultado),
  );
  for (final h in ['h36', 'h12']) {
    final r = resultado[h] as Map<String, dynamic>;
    for (final g in ['trimestral', 'anualEm30deSetembro']) {
      for (final a in ['comDeslistadas', 'semDeslistadas']) {
        _imprimirHorizonte('$h — $g — $a',
            (r[g] as Map<String, dynamic>)[a] as Map<String, dynamic>);
      }
    }
    stdout.writeln('\n=== $h — ancorada contra anual ===');
    stdout.writeln(
        const JsonEncoder.withIndent(' ').convert(r['ancoradaContraAnual']));
  }
  final contra = resultado['contrafactualDaBase'] as Map<String, dynamic>;
  for (final h in ['h36', 'h12']) {
    final b = contra[h] as Map<String, dynamic>;
    _imprimirHorizonte(
        '$h — base da data', b['naData'] as Map<String, dynamic>);
    _imprimirHorizonte(
        '$h — base antiga', b['baseAntiga'] as Map<String, dynamic>);
  }
  stderr.writeln('\nescrito docs/validacao/habilidade_trimestral.json');
  _pacoteDaHabilidade(resultado);
}

/// Caminho do pacote da habilidade que o aplicativo lê (item B1.0).
const _pacoteHabilidade = 'assets/validacao/habilidade.json';

/// Grava a leitura que a tela de metas mostra: 36 meses, coortes trimestrais,
/// com as deslistadas — a amostra do R3 (decisões 93 e 96).
///
/// O pacote leva os números, e não o veredito: o critério da decisão 96 e a
/// regra que escolhe a ordenação do prêmio (item B1, `ordenacao_lado_a_lado.md`
/// §1) moram em `SkillReading`, e o teste do pacote confere que eles concordam
/// com o `passaR3` desta medição.
void _pacoteDaHabilidade(Map<String, dynamic> resultado) {
  Map<String, dynamic> m(Object? v) => v as Map<String, dynamic>;
  final amostra = m(m(m(resultado['h36'])['trimestral'])['comDeslistadas']);
  final fm = m(amostra['famaMacBeth']);
  final dado = m(fm['potencialDadoBm']);
  Map<String, Object?> leitura(String chave) {
    final l = m(fm[chave]);
    return {
      'ic': l['media'],
      'tCorrigido': l['tSobreposicao'],
      'critico': l['criticoSobreposicao'],
      'tNeweyWest': l['tNeweyWest'],
    };
  }

  final pacote = {
    'versao': SkillReadingCodec.versao,
    'fonte': 'docs/validacao/habilidade_trimestral.json',
    'medidoEm': '${resultado['gerado']}'.substring(0, 10),
    'horizonteMeses': 36,
    'coortes': dado['coortes'],
    'observacoes': amostra['observacoes'],
    'potencialDadoBookToMarket': {
      'coeficiente': dado['media'],
      'tCorrigido': dado['tSobreposicao'],
      'critico': dado['criticoSobreposicao'],
      'tNeweyWest': dado['tNeweyWest'],
    },
    'ordenacoes': {
      SkillReadingCodec.chave(TransversalOrdering.composite):
          leitura('icComposto'),
      SkillReadingCodec.chave(TransversalOrdering.bookToMarket):
          leitura('icBookToMarket'),
      SkillReadingCodec.chave(TransversalOrdering.potential):
          leitura('icPotencial'),
    },
  };
  final lida = SkillReadingCodec.decode(pacote);
  if (lida == null) {
    stderr.writeln('A leitura da habilidade saiu malformada; o pacote não foi '
        'gravado.');
    exit(1);
  }
  File(_pacoteHabilidade).writeAsStringSync(jsonEncode(pacote));
  final premio = lida.premiumOrdering;
  stderr.writeln('escrito $_pacoteHabilidade — potencial dado o B/M '
      '${lida.demonstrated ? 'comprovado' : 'não comprovado'}; prêmio do '
      'retorno esperado: ${premio == null ? 'nenhum, nenhuma ordenação passou' : premio.label}');
}

/// A habilidade sobre a montagem do aplicativo por data, com e sem as
/// deslistadas, no retorno total (itens C1a e C1b).
///
/// As duas amostras saem da **mesma execução** de
/// `dart run tool/backtest_valuation.dart --montagem aplicativo
/// --com-deslistadas`: comparar com uma execução anterior misturaria o efeito
/// das deslistadas com a deriva do dado de mercado.
Future<void> _aplicativo() async {
  const fonte = 'docs/validacao/backtest_aplicativo_deslistadas.json';
  final arquivo = File(fonte);
  if (!arquivo.existsSync()) {
    stderr.writeln('Falta $fonte. Rode antes: dart run tool/backtest_valuation.dart '
        '--montagem aplicativo --com-deslistadas');
    exit(2);
  }
  final todas = jsonDecode(arquivo.readAsStringSync()) as List<dynamic>;
  final listadas = [
    for (final l in todas)
      if ((l as Map<String, dynamic>)['deslistada'] != true) l,
  ];
  stderr.writeln('${todas.length} linhas, ${listadas.length} de listadas');

  final resultado = {
    'gerado': DateTime.now().toIso8601String(),
    'fonte': fonte,
    'retorno': 'total, com os proventos da B3 reinvestidos na data ex',
    'h36': {
      'semDeslistadas': _horizonte(listadas, 'ret36tot', defasagem: 2),
      'comDeslistadas': _horizonte(todas, 'ret36tot', defasagem: 2),
    },
    'h12': {
      'semDeslistadas': _horizonte(listadas, 'ret12tot'),
      'comDeslistadas': _horizonte(todas, 'ret12tot'),
    },
  };
  File('docs/validacao/habilidade_aplicativo.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(resultado),
  );
  for (final h in ['h36', 'h12']) {
    for (final a in ['semDeslistadas', 'comDeslistadas']) {
      _imprimirHorizonte('${h == 'h36' ? '36' : '12'} MESES — $a',
          (resultado[h] as Map<String, dynamic>)[a] as Map<String, dynamic>);
    }
  }
  stderr.writeln('\nescrito docs/validacao/habilidade_aplicativo.json');
}
