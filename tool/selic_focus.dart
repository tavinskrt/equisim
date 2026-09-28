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

const _saida = 'docs/validacao/selic_focus.json';

/// As variantes, na ordem em que são impressas; a primeira é a referência.
const _variantes = ['curva', 'orientador', 'trajetoria', 'passado'];

/// As expectativas anuais da Selic (fim de ano, em fração) na última data do
/// Focus até [ate].
Future<({String data, Map<int, double> porAno})> _focus(DateTime ate) async {
  final dia = ate.toIso8601String().substring(0, 10);
  final url = Uri.parse(
      'https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/'
      'ExpectativasMercadoAnuais?\$top=20'
      "&\$filter=Indicador%20eq%20'Selic'%20and%20baseCalculo%20eq%200"
      "%20and%20Data%20le%20'$dia'"
      '&\$orderby=Data%20desc&\$format=json'
      '&\$select=Data,DataReferencia,Mediana');
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await cliente.getUrl(url);
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw HttpException('Focus respondeu ${resp.statusCode}', uri: url);
    }
    final corpo = await resp.transform(utf8.decoder).join();
    final linhas = ((jsonDecode(corpo) as Map)['value'] as List)
        .cast<Map<String, dynamic>>();
    if (linhas.isEmpty) throw StateError('Focus sem expectativa até $dia');
    final data = linhas.first['Data'] as String;
    return (
      data: data,
      porAno: {
        for (final l in linhas)
          if (l['Data'] == data)
            int.parse(l['DataReferencia'] as String):
                (l['Mediana'] as num).toDouble() / 100,
      },
    );
  } finally {
    cliente.close();
  }
}

/// A curva de uma trajetória de taxas anuais: vértices à vista nos anos
/// inteiros, compostos dos forwards; depois do último, a curva segue no último
/// forward, que é a extrapolação da `YieldCurve`.
YieldCurve curvaDosForwards(DateTime ref, List<double> forwards) {
  var fator = 1.0;
  final vertices = <CurveVertex>[];
  for (var k = 1; k <= forwards.length; k++) {
    fator *= 1 + forwards[k - 1];
    vertices.add(CurveVertex(k.toDouble(), math.pow(fator, 1 / k) - 1.0));
  }
  return YieldCurve.of(ref, vertices)!;
}

/// A Selic média esperada em cada um dos [n] anos seguintes a [hoje].
///
/// A trajetória liga, por segmentos de reta, a taxa corrente em [hoje] à
/// expectativa de cada fim de ano, e segue plana na última. A taxa do ano é a
/// média composta da trajetória nele — `exp(média de ln(1 + S))` —, que é o que
/// o CDI acumularia.
List<double> forwardsDoFocus(
    DateTime hoje, double corrente, Map<int, double> porAno, int n) {
  // Em UTC: diferença entre datas locais perde um dia na troca de horário.
  final hojeUtc = DateTime.utc(hoje.year, hoje.month, hoje.day);
  double anos(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).difference(hojeUtc).inDays / 365.25;
  final pontos = <(double, double)>[
    (0.0, corrente),
    for (final a in porAno.keys.toList()..sort())
      if (anos(DateTime(a, 12, 31)) > 0) (anos(DateTime(a, 12, 31)), porAno[a]!),
  ];
  double taxa(double t) {
    if (t >= pontos.last.$1) return pontos.last.$2;
    for (var i = 1; i < pontos.length; i++) {
      if (t <= pontos[i].$1) {
        final (t0, s0) = pontos[i - 1];
        final (t1, s1) = pontos[i];
        return s0 + (s1 - s0) * (t - t0) / (t1 - t0);
      }
    }
    return pontos.last.$2;
  }

  const passos = 360;
  return [
    for (var k = 1; k <= n; k++)
      () {
        var soma = 0.0;
        for (var j = 0; j < passos; j++) {
          soma += math.log(1 + taxa(k - 1 + (j + 0.5) / passos));
        }
        return math.exp(soma / passos) - 1;
      }(),
  ];
}

/// A mediana, ou `null` para lista vazia — `NaN` derrubaria o JSON.
double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final o = [...v]..sort();
  final m = o.length ~/ 2;
  return o.length.isOdd ? o[m] : (o[m - 1] + o[m]) / 2;
}

String _pct(double? v) => v == null || !v.isFinite
    ? '   —  '
    : '${(v * 100).toStringAsFixed(2).padLeft(6)}%';

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  final ({String data, Map<int, double> porAno}) focus;
  try {
    focus = await _focus(hojeCongelado);
  } on Object catch (e) {
    stderr.writeln('sem o Focus do Banco Central: $e');
    exitCode = 2;
    return;
  }
  final anosFocus = focus.porAno.keys.toList()..sort();
  final expectativas = [for (final a in anosFocus) focus.porAno[a]!];
  // `_focus` recusa resposta sem expectativa: a lista não é vazia.
  final medianaFocus = _mediana(expectativas)!;
  final corrente = c.anchors.currentRiskFreeRate;
  final forwards = forwardsDoFocus(hojeCongelado, corrente, focus.porAno, 10);
  final trajetoria = curvaDosForwards(hojeCongelado, forwards);

  final taxas = <String, ({YieldCurve? curva, double? estrutural})?>{
    'curva': null,
    'orientador': (curva: null, estrutural: medianaFocus),
    // Com curva, a perpetuidade é o forward terminal dela (a última
    // expectativa); a estrutural só vale sem curva, e é dita aqui por clareza.
    'trajetoria': (curva: trajetoria, estrutural: forwards.last),
    'passado': (curva: null, estrutural: c.anchors.riskFreeCagr),
  };

  stdout.writeln('-- as taxas, em ${hojeCongelado.toIso8601String().substring(0, 10)} --');
  stdout.writeln('  Focus de ${focus.data}: '
      '${[for (final a in anosFocus) '$a ${_pct(focus.porAno[a]!)}'].join('  ')}');
  stdout.writeln('  mediana das expectativas anuais   ${_pct(medianaFocus)}');
  stdout.writeln('  CDI corrente                      ${_pct(corrente)}');
  stdout.writeln('  média decenal do CDI              ${_pct(c.anchors.riskFreeCagr)}');

  final caminhos = <String, Map<String, dynamic>>{};
  final justos = <String, Map<String, int>>{};
  final potenciais = <String, Map<String, double>>{};
  for (final v in _variantes) {
    justos[v] = {};
    potenciais[v] = {};
    final referencia = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 50 == 0) stderr.write('  $v: $i/${c.universo.length}   \r');
      final prep = await c.preparar(t, taxa: taxas[v]);
      if (prep.isErr) continue;
      final insumos = prep.unwrap();
      if (!caminhos.containsKey(v)) {
        final curva = insumos.riskFreeCurve;
        final n = insumos.projectionYears;
        final fw = curva != null
            ? curva.annualForwards(n)
            : [
                for (var k = 1; k <= n; k++)
                  n <= 1
                      ? insumos.capm.riskFreeRate
                      : insumos.capm.riskFreeRate +
                          (insumos.terminalRiskFreeRate -
                                  insumos.capm.riskFreeRate) *
                              (k - 1) /
                              (n - 1),
              ];
        caminhos[v] = {
          'ano1': fw.first,
          'ano5': fw.length >= 5 ? fw[4] : null,
          'ano10': fw.last,
          'perpetuidade': insumos.terminalRiskFreeRate,
          // Média composta, e não aritmética: taxa se compõe (regra R3).
          'mediaDosDezAnos': math.pow(
                  fw.map((r) => 1 + r).reduce((a, b) => a * b), 1 / fw.length) -
              1.0,
        };
      }
      final r = ValuationCascade.evaluate(insumos);
      if (v == 'curva') referencia[t] = r.valueOrNull;
      if (r.isErr) continue;
      justos[v]![t.value] = r.unwrap().fairValue.cents;
      potenciais[v]![t.value] = r.unwrap().upside;
    }
    if (v == 'curva') {
      final div = await c.conferirContraGabarito(referencia);
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

  final base = potenciais['curva']!;
  final baseJusto = justos['curva']!;
  final linhas = <Map<String, dynamic>>[];
  stdout.writeln('');
  stdout.writeln('-- o que cada fonte de taxa faz, sobre a entrada congelada --');
  stdout.writeln('  fonte        ano 1   ano 10  perpet.  avaliados  potencial '
      'mediano  acima de zero  justo vs curva  postos');
  for (final v in _variantes) {
    final pots = potenciais[v]!.values.toList();
    final comuns = justos[v]!.keys.where(baseJusto.containsKey).toList()..sort();
    final variacao = [
      for (final k in comuns)
        if (baseJusto[k]! != 0) justos[v]![k]! / baseJusto[k]! - 1,
    ];
    final rho = comuns.length < 3
        ? null
        : Regression.spearman([for (final k in comuns) base[k]!],
            [for (final k in comuns) potenciais[v]![k]!]);
    final ganhos = justos[v]!.keys.where((k) => !baseJusto.containsKey(k)).toList()
      ..sort();
    final perdidos =
        baseJusto.keys.where((k) => !justos[v]!.containsKey(k)).toList()..sort();
    final cam = caminhos[v]!;
    final acima = pots.where((p) => p > 0).length;
    stdout.writeln('  ${v.padRight(11)} ${_pct(cam['ano1'] as double)} '
        '${_pct(cam['ano10'] as double)} ${_pct(cam['perpetuidade'] as double)}  '
        '${pots.length.toString().padLeft(9)}   ${_pct(_mediana(pots)).padLeft(14)}  '
        '${acima.toString().padLeft(6)} de ${pots.length}   '
        '${_pct(_mediana(variacao)).padLeft(13)}   '
        '${rho == null ? '  —  ' : rho.toStringAsFixed(4)}');
    if (ganhos.isNotEmpty || perdidos.isNotEmpty) {
      stdout.writeln('               ganha ${ganhos.join(', ')}; perde ${perdidos.join(', ')}');
    }
    linhas.add({
      'fonte': v,
      'taxas': cam,
      'avaliados': pots.length,
      'potencialMediano': _mediana(pots),
      'acimaDeZero': acima,
      'justoMedianoContraCurva': _mediana(variacao),
      'spearmanContraCurva': rho,
      'ganha': ganhos,
      'perde': perdidos,
    });
  }

  File(_saida).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert({
        'dataDaEntrada': hojeCongelado.toIso8601String().substring(0, 10),
        'focus': {
          'data': focus.data,
          'expectativas': {
            for (final a in anosFocus) '$a': focus.porAno[a],
          },
          'mediana': medianaFocus,
          'forwardsDaTrajetoria': forwards,
        },
        'cdiCorrente': corrente,
        'mediaDecenalDoCdi': c.anchors.riskFreeCagr,
        'fontes': linhas,
        'porAtivo': {
          for (final k in (baseJusto.keys.toSet()
                ..addAll(justos['orientador']!.keys)
                ..addAll(justos['trajetoria']!.keys))
              .toList()
            ..sort())
            k: {
              for (final v in _variantes)
                if (justos[v]!.containsKey(k))
                  v: {'justoCentavos': justos[v]![k], 'potencial': potenciais[v]![k]},
            },
        },
      })}\n');
  stdout.writeln('');
  stdout.writeln('escrito $_saida');
}
