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
import 'dart:convert';
import 'dart:io';

import 'validation/regression.dart';

/// Uma observação utilizável: os três ordenadores e o retorno, todos presentes.
class Obs {
  final int coorte;
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
List<Obs> _carregar(List<dynamic> bruto, String campoRetorno) {
  final out = <Obs>[];
  for (final linha in bruto) {
    final m = linha as Map<String, dynamic>;
    final pot = _num(m['upside']);
    final bm = _num(m['bookToMarket']);
    final ey = _num(m['earningsYield']);
    final ret = _num(m[campoRetorno]);
    if (pot == null || bm == null || ey == null || ret == null) continue;
    out.add(Obs(
      coorte: (m['coorte'] as num).toInt(),
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
  final int coorte;
  final int n;

  /// Coeficientes da regressão conjunta, em postos padronizados.
  final double? coefPotencial;
  final double? coefBookToMarket;
  final double? coefEarningsYield;
  final double? tPotencial;
  final double? r2;

  /// Coeficiente da regressão só com o potencial — equivalente ao IC.
  final double? coefSozinho;

  /// Correlação de ordem do resíduo do potencial com o retorno.
  final double? icIncremental;

  /// IC simples de cada ordenador, para conferir contra o relatório anterior.
  final double? icPotencial;
  final double? icBookToMarket;
  final double? icEarningsYield;

  const PorCoorte({
    required this.coorte,
    required this.n,
    required this.coefPotencial,
    required this.coefBookToMarket,
    required this.coefEarningsYield,
    required this.tPotencial,
    required this.r2,
    required this.coefSozinho,
    required this.icIncremental,
    required this.icPotencial,
    required this.icBookToMarket,
    required this.icEarningsYield,
  });

  Map<String, dynamic> toJson() => {
        'coorte': coorte,
        'n': n,
        'coefPotencial': coefPotencial,
        'coefBookToMarket': coefBookToMarket,
        'coefEarningsYield': coefEarningsYield,
        'tPotencial': tPotencial,
        'r2': r2,
        'coefSozinho': coefSozinho,
        'icIncremental': icIncremental,
        'icPotencial': icPotencial,
        'icBookToMarket': icBookToMarket,
        'icEarningsYield': icEarningsYield,
      };
}

PorCoorte _rodarCoorte(int coorte, List<Obs> obs) {
  final pot = [for (final o in obs) o.potencial];
  final bm = [for (final o in obs) o.bookToMarket];
  final ey = [for (final o in obs) o.earningsYield];
  final ret = [for (final o in obs) o.retorno];

  final zPot = Regression.standardizedRanks(pot);
  final zBm = Regression.standardizedRanks(bm);
  final zEy = Regression.standardizedRanks(ey);
  final zRet = Regression.standardizedRanks(ret);

  final conjunta = Regression.ols([zPot, zBm, zEy], zRet);
  final sozinho = Regression.ols([zPot], zRet);
  final residuo = Regression.residualize(zPot, [zBm, zEy]);

  return PorCoorte(
    coorte: coorte,
    n: obs.length,
    coefPotencial: conjunta?.coefficients[1],
    coefBookToMarket: conjunta?.coefficients[2],
    coefEarningsYield: conjunta?.coefficients[3],
    tPotencial: conjunta?.tStats[1],
    r2: conjunta?.r2,
    coefSozinho: sozinho?.coefficients[1],
    icIncremental: residuo == null ? null : Regression.spearman(residuo, ret),
    icPotencial: Regression.spearman(pot, ret),
    icBookToMarket: Regression.spearman(bm, ret),
    icEarningsYield: Regression.spearman(ey, ret),
  );
}

Map<String, dynamic> _horizonte(List<dynamic> bruto, String campo) {
  final obs = _carregar(bruto, campo);
  final porCoorte = <int, List<Obs>>{};
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
    ({double mean, double sd, double t, int n, int positive})? v,
  ) =>
      v == null
          ? null
          : {
              'media': v.mean,
              'desvio': v.sd,
              't': v.t,
              'coortes': v.n,
              'positivas': v.positive,
            };

  return {
    'observacoes': obs.length,
    'coortesUsadas': linhas.length,
    'porCoorte': [for (final l in linhas) l.toJson()],
    'famaMacBeth': {
      'potencialConjunto': j(s((l) => l.coefPotencial)),
      'bookToMarketConjunto': j(s((l) => l.coefBookToMarket)),
      'earningsYieldConjunto': j(s((l) => l.coefEarningsYield)),
      'potencialSozinho': j(s((l) => l.coefSozinho)),
      'icIncremental': j(s((l) => l.icIncremental)),
      'icPotencial': j(s((l) => l.icPotencial)),
      'icBookToMarket': j(s((l) => l.icBookToMarket)),
      'icEarningsYield': j(s((l) => l.icEarningsYield)),
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
    stdout.writeln('  ${rotulo.padRight(34)} '
        'média=${(v['media'] as double).toStringAsFixed(3)}  '
        't=${(v['t'] as double).toStringAsFixed(2)}  '
        'positivas=${v['positivas']}/${v['coortes']}');
  }

  stdout.writeln('\nsegundo passo de Fama-MacBeth:');
  linha('IC do potencial (referência)', 'icPotencial');
  linha('IC do P/B', 'icBookToMarket');
  linha('IC do L/P', 'icEarningsYield');
  linha('coef. do potencial sozinho', 'potencialSozinho');
  linha('coef. do potencial COM P/B e L/P', 'potencialConjunto');
  linha('coef. do P/B com os outros', 'bookToMarketConjunto');
  linha('coef. do L/P com os outros', 'earningsYieldConjunto');
  linha('IC INCREMENTAL do potencial', 'icIncremental');
}

Future<void> main(List<String> args) async {
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

  File('docs/validacao/regressao_condicional.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(resultado),
  );

  _imprimirHorizonte('36 MESES', resultado['h36'] as Map<String, dynamic>);
  _imprimirHorizonte('12 MESES', resultado['h12'] as Map<String, dynamic>);
  _imprimirHorizonte(
    '36 MESES — série ajustada (secundária, ver §1.2 das limitações)',
    resultado['h36ajustado'] as Map<String, dynamic>,
  );

  stderr.writeln('\nescrito docs/validacao/regressao_condicional.json');
}
