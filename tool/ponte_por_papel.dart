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

double _median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.isEmpty ? double.nan : (s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2);
}

void main() {
  const source = 'docs/validacao/backtest_trimestral.json';
  final file = File(source);
  if (!file.existsSync()) {
    stderr.writeln('Falta $source. Rode antes: dart run tool/backtest_valuation.dart '
        '--montagem aplicativo --com-deslistadas --trimestral --contrafactual-base');
    exit(2);
  }
  final rows = (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final listed = [for (final l in rows) if (l['deslistada'] != true) l];
  final output = <String, Object?>{'fonte': source, 'observacoes': rows.length};

  // ---- 1. O fator de base -------------------------------------------------
  final bands = <String, int>{};
  final byCohort = <String, List<int>>{};
  var otherCode = 0;
  for (final l in listed) {
    final k = _num(l['fatorDeBase']);
    if (k == null || k <= 0) continue;
    final d = math.log(k).abs();
    final band = d < math.log(1.02)
        ? 'ate2pct'
        : d < math.log(1.10)
            ? 'de2a10pct'
            : d < math.log(1.5)
                ? 'de10a50pct'
                : 'acimaDe1vezEMeia';
    bands[band] = (bands[band] ?? 0) + 1;
    final c = byCohort['${l['coorte']}'] ??= [0, 0];
    c[1]++;
    if (d >= math.log(1.02)) c[0]++;
    if (l['pregaoDeOutroCodigo'] == true) otherCode++;
  }
  output['fatorDeBase'] = {
    'observacoesDasListadas': listed.length,
    'faixas': bands,
    'pregaoDeCodigoAnterior': otherCode,
    'foraDe2pctPorCoorte': {
      for (final e in (byCohort.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))))
        e.key: '${e.value[0]}/${e.value[1]}',
    },
  };
  stdout.writeln('== 1. Fator de base (listadas) ==');
  stdout.writeln('  $bands; pregão de código anterior: $otherCode');

  // ---- 2. De onde saiu o valor de mercado ---------------------------------
  final origin = <String, int>{};
  for (final l in rows) {
    final o = '${l['deslistada'] == true ? 'deslistada' : 'listada'}:'
        '${l['origemDoValorDeMercado']}';
    origin[o] = (origin[o] ?? 0) + 1;
  }
  output['origemDoValorDeMercado'] = origin;
  stdout.writeln('\n== 2. Valor de mercado ==\n  $origin');

  // ---- 3. A razão de unidade contra a composição declarada ----------------
  final fca = FcaCodes.read();
  final byUnit = <String, Map<String, Object?>>{};
  var equalUnits = 0, measuredUnits = 0;
  final unitDistances = <double>[];
  var falsePositiveCount = 0, nonUnitsMeasured = 0;
  for (final l in listed) {
    final u = _num(l['razaoDeUnidade']);
    final shares = _num(l['acoesNaData']);
    final marketValue = _num(l['valorDeMercado']);
    final price = _num(l['preco']);
    if (u == null) continue;
    final t = l['ticker'] as String;
    final declared = fca.sharesPerUnit[t];
    if (t.endsWith('11') && declared != null) {
      measuredUnits++;
      if ((u - declared).abs() < 1e-9) equalUnits++;
      final raw = (shares != null && marketValue != null && marketValue > 0 && price != null)
          ? shares * price / marketValue
          : null;
      if (raw != null) unitDistances.add((raw / declared - 1).abs());
      final r = byUnit[t] ??= {
        'declarada': declared,
        'coortes': 0,
        'iguais': 0,
        'brutaMediana': <double>[],
      };
      r['coortes'] = (r['coortes'] as int) + 1;
      if ((u - declared).abs() < 1e-9) r['iguais'] = (r['iguais'] as int) + 1;
      if (raw != null) (r['brutaMediana'] as List<double>).add(raw);
    } else if (!t.endsWith('11')) {
      nonUnitsMeasured++;
      if (u > 1) falsePositiveCount++;
    }
  }
  for (final r in byUnit.values) {
    final b = r['brutaMediana'] as List<double>;
    r['brutaMediana'] = b.isEmpty ? null : _median(b);
  }
  unitDistances.sort();
  double distanceQuantile(double p) => unitDistances.isEmpty
      ? double.nan
      : unitDistances[((unitDistances.length - 1) * p).round()];
  output['razaoDeUnidade'] = {
    'unitsComComposicaoDeclarada': measuredUnits,
    'iguaisADeclarada': equalUnits,
    'distanciaRelativaDaDeclarada': {
      'mediana': distanceQuantile(0.5),
      'p75': distanceQuantile(0.75),
      'p90': distanceQuantile(0.9),
    },
    'folgaDaDecisao61': ValuationCascade.unitRatioTolerance,
    'porUnit': byUnit,
    'naoUnitsComRazaoMaiorQueUm': falsePositiveCount,
    'naoUnitsMedidas': nonUnitsMeasured,
  };
  stdout.writeln('\n== 3. Razão de unidade ==');
  stdout.writeln('  units com composição declarada: $equalUnits de '
      '$measuredUnits coortes com a razão igual à declarada');
  stdout.writeln('  distância relativa da declarada: mediana '
      '${distanceQuantile(0.5).toStringAsFixed(3)}, p75 '
      '${distanceQuantile(0.75).toStringAsFixed(3)}, p90 '
      '${distanceQuantile(0.9).toStringAsFixed(3)}');
  byUnit.forEach((t, r) => stdout.writeln('    $t: $r'));
  stdout.writeln('  não units com razão > 1: $falsePositiveCount de $nonUnitsMeasured');

  // ---- 4. A origem do divisor ---------------------------------------------
  final divisor = <String, int>{};
  var diverge = 0, measuredCount = 0;
  for (final l in rows) {
    final o = l['origemDoDivisor'];
    if (o == null) continue;
    measuredCount++;
    divisor['$o'] = (divisor['$o'] ?? 0) + 1;
    if (l['divisorDiverge'] == true) diverge++;
  }
  output['divisor'] = {'origem': divisor, 'candidatasDivergem': diverge, 'medidos': measuredCount};
  stdout.writeln('\n== 4. Divisor ==\n  $divisor; candidatas divergem em $diverge de $measuredCount');

  // ---- 5. A unit contra as espécies da mesma companhia --------------------
  // Na mesma coorte, o potencial da unit e o da espécie mais próxima dela
  // descrevem o mesmo negócio; o que sobra é o ágio entre espécies.
  final byKey = <String, Map<String, double>>{};
  for (final l in listed) {
    final up = _num(l['upside']);
    if (up == null) continue;
    final t = l['ticker'] as String;
    (byKey['${l['coorte']}|${t.substring(0, 4)}'] ??= {})[t] = up;
  }
  final differences = <double>[];
  final oldVersions = <double>[];
  for (final e in byKey.entries) {
    final m = e.value;
    final unit = m.entries.where((x) => x.key.endsWith('11')).toList();
    final kinds = m.entries.where((x) => !x.key.endsWith('11')).toList();
    if (unit.isEmpty || kinds.isEmpty) continue;
    for (final u in unit) {
      final best = kinds
          .map((x) => ((1 + u.value) / (1 + x.value) - 1).abs())
          .reduce(math.min);
      differences.add(best);
    }
  }
  for (final l in listed) {
    // A mesma distância na montagem antiga, quando a coorte de 30/09 a mediu.
    final t = l['ticker'] as String;
    if (!t.endsWith('11')) continue;
    final oldUpside = _num(l['upsideBaseAntiga']);
    if (oldUpside == null) continue;
    final pairs = listed.where((x) =>
        x['coorte'] == l['coorte'] &&
        (x['ticker'] as String).startsWith(t.substring(0, 4)) &&
        !(x['ticker'] as String).endsWith('11') &&
        _num(x['upsideBaseAntiga']) != null);
    if (pairs.isEmpty) continue;
    oldVersions.add(pairs
        .map((x) => ((1 + oldUpside) / (1 + _num(x['upsideBaseAntiga'])!) - 1).abs())
        .reduce(math.min));
  }
  output['unitContraEspecie'] = {
    'pares': differences.length,
    'distanciaMediana': differences.isEmpty ? null : _median(differences),
    'paresNaBaseAntiga': oldVersions.length,
    'distanciaMedianaNaBaseAntiga': oldVersions.isEmpty ? null : _median(oldVersions),
  };
  stdout.writeln('\n== 5. Unit contra espécie ==\n  ${output['unitContraEspecie']}');

  File('docs/validacao/ponte_por_papel.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(output));
  stderr.writeln('\nescrito docs/validacao/ponte_por_papel.json');
}
