// A ponte por papel nas coortes — item C3.
//
// A limitação §3.5 dizia que nenhuma coorte exercitava a ponte por papel: com o
// valor de mercado reconstruído pela contagem do exercício, a razão de unidade
// saía 1 e as duas candidatas a divisor, iguais, por construção. Com a montagem
// na base da data (`tool/coortes/base_da_data.dart`), esta ferramenta mede o que
// passou a acontecer, na mesma execução do backtest:
//
// 1. **o fator de base** — quanto o preço da fonte estava fora da base da data;
// 2. **de onde saiu o valor de mercado** — espécie a espécie, ou recuo;
// 3. **a razão de unidade contra a composição declarada na FCA** — a verdade
//    que a decisão 61 não tinha fora da amostra;
// 4. **a origem do divisor e a divergência** entre as candidatas;
// 5. **a coerência entre a unit e as espécies** da mesma companhia na mesma
//    coorte, que a §3 de `unidade.md` mediu num dia só.
//
// Entrada: `docs/validacao/backtest_trimestral.json`. Saída:
// `docs/validacao/ponte_por_papel.json`. Não vai à rede.
//
// Uso:
//   dart run tool/ponte_por_papel.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'cvm/codigos_fca.dart';

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

double _mediana(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.isEmpty ? double.nan : (s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2);
}

void main() {
  const fonte = 'docs/validacao/backtest_trimestral.json';
  final arquivo = File(fonte);
  if (!arquivo.existsSync()) {
    stderr.writeln('Falta $fonte. Rode antes: dart run tool/backtest_valuation.dart '
        '--montagem aplicativo --com-deslistadas --trimestral --contrafactual-base');
    exit(2);
  }
  final linhas = (jsonDecode(arquivo.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final listadas = [for (final l in linhas) if (l['deslistada'] != true) l];
  final saida = <String, Object?>{'fonte': fonte, 'observacoes': linhas.length};

  // ---- 1. O fator de base -------------------------------------------------
  final faixas = <String, int>{};
  final porCoorte = <String, List<int>>{};
  var outroCodigo = 0;
  for (final l in listadas) {
    final k = _num(l['fatorDeBase']);
    if (k == null || k <= 0) continue;
    final d = math.log(k).abs();
    final faixa = d < math.log(1.02)
        ? 'ate2pct'
        : d < math.log(1.10)
            ? 'de2a10pct'
            : d < math.log(1.5)
                ? 'de10a50pct'
                : 'acimaDe1vezEMeia';
    faixas[faixa] = (faixas[faixa] ?? 0) + 1;
    final c = porCoorte['${l['coorte']}'] ??= [0, 0];
    c[1]++;
    if (d >= math.log(1.02)) c[0]++;
    if (l['pregaoDeOutroCodigo'] == true) outroCodigo++;
  }
  saida['fatorDeBase'] = {
    'observacoesDasListadas': listadas.length,
    'faixas': faixas,
    'pregaoDeCodigoAnterior': outroCodigo,
    'foraDe2pctPorCoorte': {
      for (final e in (porCoorte.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))))
        e.key: '${e.value[0]}/${e.value[1]}',
    },
  };
  stdout.writeln('== 1. Fator de base (listadas) ==');
  stdout.writeln('  $faixas; pregão de código anterior: $outroCodigo');

  // ---- 2. De onde saiu o valor de mercado ---------------------------------
  final origem = <String, int>{};
  for (final l in linhas) {
    final o = '${l['deslistada'] == true ? 'deslistada' : 'listada'}:'
        '${l['origemDoValorDeMercado']}';
    origem[o] = (origem[o] ?? 0) + 1;
  }
  saida['origemDoValorDeMercado'] = origem;
  stdout.writeln('\n== 2. Valor de mercado ==\n  $origem');

  // ---- 3. A razão de unidade contra a composição declarada ----------------
  final fca = CodigosFca.ler();
  final porUnit = <String, Map<String, Object?>>{};
  var unitsIguais = 0, unitsMedidas = 0;
  final distanciasUnits = <double>[];
  var falsosPositivos = 0, naoUnitsMedidas = 0;
  for (final l in listadas) {
    final u = _num(l['razaoDeUnidade']);
    final acoes = _num(l['acoesNaData']);
    final vm = _num(l['valorDeMercado']);
    final preco = _num(l['preco']);
    if (u == null) continue;
    final t = l['ticker'] as String;
    final declarada = fca.acoesPorUnit[t];
    if (t.endsWith('11') && declarada != null) {
      unitsMedidas++;
      if ((u - declarada).abs() < 1e-9) unitsIguais++;
      final bruta = (acoes != null && vm != null && vm > 0 && preco != null)
          ? acoes * preco / vm
          : null;
      if (bruta != null) distanciasUnits.add((bruta / declarada - 1).abs());
      final r = porUnit[t] ??= {
        'declarada': declarada,
        'coortes': 0,
        'iguais': 0,
        'brutaMediana': <double>[],
      };
      r['coortes'] = (r['coortes'] as int) + 1;
      if ((u - declarada).abs() < 1e-9) r['iguais'] = (r['iguais'] as int) + 1;
      if (bruta != null) (r['brutaMediana'] as List<double>).add(bruta);
    } else if (!t.endsWith('11')) {
      naoUnitsMedidas++;
      if (u > 1) falsosPositivos++;
    }
  }
  for (final r in porUnit.values) {
    final b = r['brutaMediana'] as List<double>;
    r['brutaMediana'] = b.isEmpty ? null : _mediana(b);
  }
  distanciasUnits.sort();
  double quantilDist(double p) => distanciasUnits.isEmpty
      ? double.nan
      : distanciasUnits[((distanciasUnits.length - 1) * p).round()];
  saida['razaoDeUnidade'] = {
    'unitsComComposicaoDeclarada': unitsMedidas,
    'iguaisADeclarada': unitsIguais,
    'distanciaRelativaDaDeclarada': {
      'mediana': quantilDist(0.5),
      'p75': quantilDist(0.75),
      'p90': quantilDist(0.9),
    },
    'folgaDaDecisao61': ValuationCascade.unitRatioTolerance,
    'porUnit': porUnit,
    'naoUnitsComRazaoMaiorQueUm': falsosPositivos,
    'naoUnitsMedidas': naoUnitsMedidas,
  };
  stdout.writeln('\n== 3. Razão de unidade ==');
  stdout.writeln('  units com composição declarada: $unitsIguais de '
      '$unitsMedidas coortes com a razão igual à declarada');
  stdout.writeln('  distância relativa da declarada: mediana '
      '${quantilDist(0.5).toStringAsFixed(3)}, p75 '
      '${quantilDist(0.75).toStringAsFixed(3)}, p90 '
      '${quantilDist(0.9).toStringAsFixed(3)}');
  porUnit.forEach((t, r) => stdout.writeln('    $t: $r'));
  stdout.writeln('  não units com razão > 1: $falsosPositivos de $naoUnitsMedidas');

  // ---- 4. A origem do divisor ---------------------------------------------
  final divisor = <String, int>{};
  var diverge = 0, medidos = 0;
  for (final l in linhas) {
    final o = l['origemDoDivisor'];
    if (o == null) continue;
    medidos++;
    divisor['$o'] = (divisor['$o'] ?? 0) + 1;
    if (l['divisorDiverge'] == true) diverge++;
  }
  saida['divisor'] = {'origem': divisor, 'candidatasDivergem': diverge, 'medidos': medidos};
  stdout.writeln('\n== 4. Divisor ==\n  $divisor; candidatas divergem em $diverge de $medidos');

  // ---- 5. A unit contra as espécies da mesma companhia --------------------
  // Na mesma coorte, o potencial da unit e o da espécie mais próxima dela
  // descrevem o mesmo negócio; o que sobra é o ágio entre espécies.
  final porChave = <String, Map<String, double>>{};
  for (final l in listadas) {
    final up = _num(l['upside']);
    if (up == null) continue;
    final t = l['ticker'] as String;
    (porChave['${l['coorte']}|${t.substring(0, 4)}'] ??= {})[t] = up;
  }
  final diferencas = <double>[];
  final antigas = <double>[];
  for (final e in porChave.entries) {
    final m = e.value;
    final unit = m.entries.where((x) => x.key.endsWith('11')).toList();
    final especies = m.entries.where((x) => !x.key.endsWith('11')).toList();
    if (unit.isEmpty || especies.isEmpty) continue;
    for (final u in unit) {
      final melhor = especies
          .map((x) => ((1 + u.value) / (1 + x.value) - 1).abs())
          .reduce(math.min);
      diferencas.add(melhor);
    }
  }
  for (final l in listadas) {
    // A mesma distância na montagem antiga, quando a coorte de 30/09 a mediu.
    final t = l['ticker'] as String;
    if (!t.endsWith('11')) continue;
    final ua = _num(l['upsideBaseAntiga']);
    if (ua == null) continue;
    final pares = listadas.where((x) =>
        x['coorte'] == l['coorte'] &&
        (x['ticker'] as String).startsWith(t.substring(0, 4)) &&
        !(x['ticker'] as String).endsWith('11') &&
        _num(x['upsideBaseAntiga']) != null);
    if (pares.isEmpty) continue;
    antigas.add(pares
        .map((x) => ((1 + ua) / (1 + _num(x['upsideBaseAntiga'])!) - 1).abs())
        .reduce(math.min));
  }
  saida['unitContraEspecie'] = {
    'pares': diferencas.length,
    'distanciaMediana': diferencas.isEmpty ? null : _mediana(diferencas),
    'paresNaBaseAntiga': antigas.length,
    'distanciaMedianaNaBaseAntiga': antigas.isEmpty ? null : _mediana(antigas),
  };
  stdout.writeln('\n== 5. Unit contra espécie ==\n  ${saida['unitContraEspecie']}');

  File('docs/validacao/ponte_por_papel.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida));
  stderr.writeln('\nescrito docs/validacao/ponte_por_papel.json');
}
