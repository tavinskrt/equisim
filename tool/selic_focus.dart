// A Selic prevista no lugar da taxa livre de risco — o pedido do orientador,
// medido sobre a entrada congelada do gabarito.
//
// **A pergunta.** O orientador pediu, em 27/09/2026, que a projeção deixasse de
// usar "a mediana da Selic do passado" e usasse "a mediana da Selic prevista
// para os próximos cinco anos". A média do passado — a decenal do CDI — foi a
// taxa estrutural do motor até a decisão 84, e hoje só vale quando a curva do
// Tesouro falta. Desde 14/09/2026 a taxa de cada ano é o forward da curva dos
// prefixados, que é o que o mercado de títulos cobra por prazo.
//
// **O que esta ferramenta mede**, na mesma execução e com a montagem de
// referência conferida contra o gabarito:
//
//   curva        o motor de hoje: forwards da curva prefixada do Tesouro
//   orientador   dois pontos: o CDI corrente convergindo à mediana das
//                expectativas anuais do Focus (ano corrente e quatro seguintes)
//                no ano 10, e a perpetuidade nela
//   trajetoria   a trajetória do Focus: a taxa de cada ano é a Selic média que
//                o Focus espera para ele, e depois do último ano a última
//                expectativa segue até a perpetuidade
//   passado      dois pontos até a média decenal do CDI — o motor de antes da
//                decisão 84, e o recuo de hoje quando a curva falta
//
// O Focus vem do Banco Central (Olinda, `ExpectativasMercadoAnuais`,
// indicador `Selic`, base de cálculo 0), na última data até a da entrada
// congelada, e fica gravado no JSON de saída.
//
//   dart run tool/gabarito_cascata.dart        # congela a entrada
//   dart run tool/selic_focus.dart             # grava selic_focus.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/regression.dart';

const _output = 'docs/validacao/selic_focus.json';

/// As variantes, na ordem em que são impressas; a primeira é a referência.
const _variants = ['curva', 'orientador', 'trajetoria', 'passado'];

/// As expectativas anuais da Selic (fim de ano, em fração) na última data do
/// Focus até [until].
Future<({String date, Map<int, double> byYear})> _focus(DateTime until) async {
  final day = until.toIso8601String().substring(0, 10);
  final url = Uri.parse(
      'https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/'
      'ExpectativasMercadoAnuais?\$top=20'
      "&\$filter=Indicador%20eq%20'Selic'%20and%20baseCalculo%20eq%200"
      "%20and%20Data%20le%20'$day'"
      '&\$orderby=Data%20desc&\$format=json'
      '&\$select=Data,DataReferencia,Mediana');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client.getUrl(url);
    final response = await req.close();
    if (response.statusCode != 200) {
      throw HttpException('Focus respondeu ${response.statusCode}', uri: url);
    }
    final body = await response.transform(utf8.decoder).join();
    final rows = ((jsonDecode(body) as Map)['value'] as List)
        .cast<Map<String, dynamic>>();
    if (rows.isEmpty) throw StateError('Focus sem expectativa até $day');
    final date = rows.first['Data'] as String;
    return (
      date: date,
      byYear: {
        for (final l in rows)
          if (l['Data'] == date)
            int.parse(l['DataReferencia'] as String):
                (l['Mediana'] as num).toDouble() / 100,
      },
    );
  } finally {
    client.close();
  }
}

/// A curva de uma trajetória de taxas anuais: vértices à vista nos anos
/// inteiros, compostos dos forwards; depois do último, a curva segue no último
/// forward, que é a extrapolação da `YieldCurve`.
YieldCurve forwardsCurve(DateTime ref, List<double> forwards) {
  var factor = 1.0;
  final vertices = <CurveVertex>[];
  for (var k = 1; k <= forwards.length; k++) {
    factor *= 1 + forwards[k - 1];
    vertices.add(CurveVertex(k.toDouble(), math.pow(factor, 1 / k) - 1.0));
  }
  return YieldCurve.of(ref, vertices)!;
}

/// A Selic média esperada em cada um dos [n] anos seguintes a [today].
///
/// A trajetória liga, por segmentos de reta, a taxa corrente em [today] à
/// expectativa de cada fim de ano, e segue plana na última. A taxa do ano é a
/// média composta da trajetória nele — `exp(média de ln(1 + S))` —, que é o que
/// o CDI acumularia.
List<double> focusForwards(
    DateTime today, double current, Map<int, double> byYear, int n) {
  // Em UTC: diferença entre datas locais perde um dia na troca de horário.
  final todayUtc = DateTime.utc(today.year, today.month, today.day);
  double years(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).difference(todayUtc).inDays / 365.25;
  final points = <(double, double)>[
    (0.0, current),
    for (final a in byYear.keys.toList()..sort())
      if (years(DateTime(a, 12, 31)) > 0) (years(DateTime(a, 12, 31)), byYear[a]!),
  ];
  double rate(double t) {
    if (t >= points.last.$1) return points.last.$2;
    for (var i = 1; i < points.length; i++) {
      if (t <= points[i].$1) {
        final (t0, s0) = points[i - 1];
        final (t1, s1) = points[i];
        return s0 + (s1 - s0) * (t - t0) / (t1 - t0);
      }
    }
    return points.last.$2;
  }

  const stepCount = 360;
  return [
    for (var k = 1; k <= n; k++)
      () {
        var sum = 0.0;
        for (var j = 0; j < stepCount; j++) {
          sum += math.log(1 + rate(k - 1 + (j + 0.5) / stepCount));
        }
        return math.exp(sum / stepCount) - 1;
      }(),
  ];
}

/// A mediana, ou `null` para lista vazia — `NaN` derrubaria o JSON.
double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final o = [...v]..sort();
  final m = o.length ~/ 2;
  return o.length.isOdd ? o[m] : (o[m - 1] + o[m]) / 2;
}

String _pct(double? v) => v == null || !v.isFinite
    ? '   —  '
    : '${(v * 100).toStringAsFixed(2).padLeft(6)}%';

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  final ({String date, Map<int, double> byYear}) focus;
  try {
    focus = await _focus(frozenToday);
  } on Object catch (e) {
    stderr.writeln('sem o Focus do Banco Central: $e');
    exitCode = 2;
    return;
  }
  final focusYears = focus.byYear.keys.toList()..sort();
  final expectations = [for (final a in focusYears) focus.byYear[a]!];
  // `_focus` recusa resposta sem expectativa: a lista não é vazia.
  final focusMedian = _median(expectations)!;
  final current = c.anchors.currentRiskFreeRate;
  final forwards = focusForwards(frozenToday, current, focus.byYear, 10);
  final trajectory = forwardsCurve(frozenToday, forwards);

  final rates = <String, ({YieldCurve? curve, double? structural})?>{
    'curva': null,
    'orientador': (curve: null, structural: focusMedian),
    // Com curva, a perpetuidade é o forward terminal dela (a última
    // expectativa); a estrutural só vale sem curva, e é dita aqui por clareza.
    'trajetoria': (curve: trajectory, structural: forwards.last),
    'passado': (curve: null, structural: c.anchors.riskFreeCagr),
  };

  stdout.writeln('-- as taxas, em ${frozenToday.toIso8601String().substring(0, 10)} --');
  stdout.writeln('  Focus de ${focus.date}: '
      '${[for (final a in focusYears) '$a ${_pct(focus.byYear[a]!)}'].join('  ')}');
  stdout.writeln('  mediana das expectativas anuais   ${_pct(focusMedian)}');
  stdout.writeln('  CDI corrente                      ${_pct(current)}');
  stdout.writeln('  média decenal do CDI              ${_pct(c.anchors.riskFreeCagr)}');

  final paths = <String, Map<String, dynamic>>{};
  final fairValues = <String, Map<String, int>>{};
  final upsideByTicker = <String, Map<String, double>>{};
  for (final v in _variants) {
    fairValues[v] = {};
    upsideByTicker[v] = {};
    final reference = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 50 == 0) stderr.write('  $v: $i/${c.universe.length}   \r');
      final prep = await c.prepare(t, rate: rates[v]);
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      if (!paths.containsKey(v)) {
        final curve = inputs.riskFreeCurve;
        final n = inputs.projectionYears;
        final fw = curve != null
            ? curve.annualForwards(n)
            : [
                for (var k = 1; k <= n; k++)
                  n <= 1
                      ? inputs.capm.riskFreeRate
                      : inputs.capm.riskFreeRate +
                          (inputs.terminalRiskFreeRate -
                                  inputs.capm.riskFreeRate) *
                              (k - 1) /
                              (n - 1),
              ];
        paths[v] = {
          'ano1': fw.first,
          'ano5': fw.length >= 5 ? fw[4] : null,
          'ano10': fw.last,
          'perpetuidade': inputs.terminalRiskFreeRate,
          // Média composta, e não aritmética: taxa se compõe (regra R3).
          'mediaDosDezAnos': math.pow(
                  fw.map((r) => 1 + r).reduce((a, b) => a * b), 1 / fw.length) -
              1.0,
        };
      }
      final r = ValuationCascade.evaluate(inputs);
      if (v == 'curva') reference[t] = r.valueOrNull;
      if (r.isErr) continue;
      fairValues[v]![t.value] = r.unwrap().fairValue.cents;
      upsideByTicker[v]![t.value] = r.unwrap().upside;
    }
    if (v == 'curva') {
      final div = await c.checkAgainstAnswerKey(reference);
      if (div == null) {
        stderr.writeln('AVISO: gabarito ausente; montagem não conferida.');
      } else if (div.isNotEmpty) {
        stderr.writeln('ERRO: a montagem de referência diverge do gabarito em '
            '${div.length}: ${div.take(8).join(", ")}');
        exitCode = 1;
        return;
      } else {
        stdout.writeln('  montagem da curva conferida contra o gabarito: '
            'zero divergências');
      }
    }
  }
  stderr.write('                                        \r');

  final base = upsideByTicker['curva']!;
  final baseFairValue = fairValues['curva']!;
  final rows = <Map<String, dynamic>>[];
  stdout.writeln('');
  stdout.writeln('-- o que cada fonte de taxa faz, sobre a entrada congelada --');
  stdout.writeln('  fonte        ano 1   ano 10  perpet.  avaliados  potencial '
      'mediano  acima de zero  justo vs curva  postos');
  for (final v in _variants) {
    final upsideValues = upsideByTicker[v]!.values.toList();
    final common = fairValues[v]!.keys.where(baseFairValue.containsKey).toList()..sort();
    final changeList = [
      for (final k in common)
        if (baseFairValue[k]! != 0) fairValues[v]![k]! / baseFairValue[k]! - 1,
    ];
    final rho = common.length < 3
        ? null
        : Regression.spearman([for (final k in common) base[k]!],
            [for (final k in common) upsideByTicker[v]![k]!]);
    final gains = fairValues[v]!.keys.where((k) => !baseFairValue.containsKey(k)).toList()
      ..sort();
    final lost =
        baseFairValue.keys.where((k) => !fairValues[v]!.containsKey(k)).toList()..sort();
    final selectedPath = paths[v]!;
    final above = upsideValues.where((p) => p > 0).length;
    stdout.writeln('  ${v.padRight(11)} ${_pct(selectedPath['ano1'] as double)} '
        '${_pct(selectedPath['ano10'] as double)} ${_pct(selectedPath['perpetuidade'] as double)}  '
        '${upsideValues.length.toString().padLeft(9)}   ${_pct(_median(upsideValues)).padLeft(14)}  '
        '${above.toString().padLeft(6)} de ${upsideValues.length}   '
        '${_pct(_median(changeList)).padLeft(13)}   '
        '${rho == null ? '  —  ' : rho.toStringAsFixed(4)}');
    if (gains.isNotEmpty || lost.isNotEmpty) {
      stdout.writeln('               ganha ${gains.join(', ')}; perde ${lost.join(', ')}');
    }
    rows.add({
      'fonte': v,
      'taxas': selectedPath,
      'avaliados': upsideValues.length,
      'potencialMediano': _median(upsideValues),
      'acimaDeZero': above,
      'justoMedianoContraCurva': _median(changeList),
      'spearmanContraCurva': rho,
      'ganha': gains,
      'perde': lost,
    });
  }

  File(_output).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert({
        'dataDaEntrada': frozenToday.toIso8601String().substring(0, 10),
        'focus': {
          'data': focus.date,
          'expectativas': {
            for (final a in focusYears) '$a': focus.byYear[a],
          },
          'mediana': focusMedian,
          'forwardsDaTrajetoria': forwards,
        },
        'cdiCorrente': current,
        'mediaDecenalDoCdi': c.anchors.riskFreeCagr,
        'fontes': rows,
        'porAtivo': {
          for (final k in (baseFairValue.keys.toSet()
                ..addAll(fairValues['orientador']!.keys)
                ..addAll(fairValues['trajetoria']!.keys))
              .toList()
            ..sort())
            k: {
              for (final v in _variants)
                if (fairValues[v]!.containsKey(k))
                  v: {'justoCentavos': fairValues[v]![k], 'potencial': upsideByTicker[v]![k]},
            },
        },
      })}\n');
  stdout.writeln('');
  stdout.writeln('escrito $_output');
}
